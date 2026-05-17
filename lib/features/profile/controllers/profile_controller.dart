import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/order_model.dart';
import '../../../models/trip_model.dart';
import '../../../models/user_address.dart';
import '../../../repositories/driver_repository.dart';
import '../../../repositories/orders_repository.dart';
import '../../../repositories/trips_repository.dart';
import '../../../repositories/user_repository.dart';
import '../../../services/device_identity_service.dart';
import '../../../services/fcm_service.dart';
import '../../../services/location_service.dart';

/// ProfileScreen uchun butun holatni boshqaradigan ChangeNotifier.
///
/// UI bilan ma'lumot qatlami orasida joylashgan. Screen faqat shu controller'ni
/// kuzatadi — to'g'ridan-to'g'ri Firestore'ga kirmaydi.
class ProfileController extends ChangeNotifier {
  ProfileController({
    required DriverRepository driverRepo,
    required TripsRepository tripsRepo,
    required OrdersRepository ordersRepo,
    required UserRepository userRepo,
    required LocationService locationService,
  })  : _driverRepo = driverRepo,
        _tripsRepo = tripsRepo,
        _ordersRepo = ordersRepo,
        _userRepo = userRepo,
        _locationService = locationService;

  final DriverRepository _driverRepo;
  final TripsRepository _tripsRepo;
  final OrdersRepository _ordersRepo;
  final UserRepository _userRepo;
  final LocationService _locationService;
  final DeviceIdentityService _deviceIdentity = DeviceIdentityService();

  final ImagePicker _picker = ImagePicker();

  // ─── Asosiy maydonlar (SharedPreferences'dan) ──────────────────────
  String name = '';
  String phone = '';
  String gender = 'male';
  String role = 'user';
  String birthDate = '';

  /// `address` — қатор (`displayString`). UI ва эски код учун.
  String address = '';

  /// Структуралaнган манзил — мажбурий 4 майдон + GPS.
  UserAddress structuredAddress = const UserAddress();

  String? imagePath;

  // Mashina ma'lumotlari
  String carModel = '';
  String carColor = '';
  String carPlate = '';
  String taxiType = 'alone';

  // Haydovchi statistikasi
  double driverRating = 0.0;
  int driverTripCount = 0;
  int driverEarnings = 0;

  // Ro'yxatlar
  List<TripModel> trips = const [];
  List<OrderModel> orders = const [];

  // Holat bayroqlari
  bool isEditing = false;
  bool isSaving = false;
  bool isGpsLoading = false;
  bool ordersLoading = true;
  bool tripsLoading = true;

  String? errorMessage;
  String? successMessage;

  String _oldRole = '';
  bool get roleChangedAfterSave => role != _oldRole;

  /// Манзил тўлдирилганми? — қўлдаги мажбурий 3 майдон + GPS координаталари
  /// иккаласи ҳам сақланган. Legacy `address` (string) бу шартни **қониқтирмайди** —
  /// эски фойдаланувчилар янги форматда қайта тўлдиришлари керак.
  bool get hasCompleteAddress => structuredAddress.isComplete;

  /// UI учун — структурaнli ёки legacy.
  String get addressDisplay {
    if (structuredAddress.isComplete) return structuredAddress.formatted;
    return address;
  }

  // ─── Yuklash ────────────────────────────────────────────────────────
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    name = prefs.getString('user_name') ?? '';
    phone = prefs.getString('user_phone') ?? '';
    gender = prefs.getString('user_gender') ?? 'male';
    role = prefs.getString('user_role') ?? 'user';
    birthDate = prefs.getString('user_birth_date') ?? '';
    address = prefs.getString('user_address') ?? '';
    imagePath = prefs.getString('profile_image');
    carModel = prefs.getString('car_model') ?? '';
    carColor = prefs.getString('car_color') ?? '';
    carPlate = prefs.getString('car_plate') ?? '';
    taxiType = prefs.getString('taxi_type') ?? 'alone';
    notifyListeners();

    // Структуралaнган манзилни Firestore'дан ўқиш (паралел).
    final tasks = <Future<void>>[_loadStructuredAddress()];
    if (role == 'driver' && phone.isNotEmpty) {
      tasks.addAll([_loadDriverStats(), _loadDriverTrips()]);
    } else {
      tasks.addAll([_loadOrders(), _loadUserTrips()]);
    }
    await Future.wait(tasks);
  }

  /// Firestore'дан `users/{uid}` ҳужжатини ўқиб, `structuredAddress`, legacy
  /// `address` ва **`role`** ни синхронлаш.
  ///
  /// `role` Firestore'даги ҳаqиqий qиймат — агар локaлдан фарqли бўлса,
  /// SharedPreferences ҳам янгилaнaди. Бу — Firebase Console'дан админ rolени
  /// qўлдa ўзгaртиргaн ҳолда, илова рестарт qилмaй туриб ҳам синхронлaнсин.
  ///
  /// Internet йўқ ёки ҳужжат йўқ бўлса — silent fail.
  Future<void> _loadStructuredAddress() async {
    final uid = phoneDigits(phone);
    if (uid.length < 9) return;
    try {
      final user = await _userRepo.getById(uid);
      if (user == null) return;
      structuredAddress = user.address;
      // Legacy address — agar Firestore'da bo'lsa va SharedPreferences bo'sh
      // bo'lsa — to'ldiramiz (eskи фойдаланувчилар учун).
      if (address.isEmpty && user.addressLegacy.isNotEmpty) {
        address = user.addressLegacy;
      }
      // Role'ни Firestore'дан синxронlaш (agar фарqли бўлса).
      if (user.role.isNotEmpty && user.role != role) {
        role = user.role;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_role', user.role);
      }
      if (user.birthDate.isNotEmpty && user.birthDate != birthDate) {
        birthDate = user.birthDate;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_birth_date', user.birthDate);
      }
      notifyListeners();
    } catch (_) {
      // Internet yo'q ёки rules denied — bu yerda silent fail.
    }
  }

  Future<void> _loadDriverStats() async {
    final uid = phoneDigits(phone);
    final stats = await _driverRepo.getStats(uid);
    if (stats != null) {
      driverRating = stats.rating;
      driverTripCount = stats.ratingCount;
      notifyListeners();
    }
  }

  Future<void> _loadDriverTrips() async {
    try {
      final uid = phoneDigits(phone);
      final list = await _tripsRepo.completedByDriver(uid);
      trips = list;
      driverEarnings = list.fold<int>(0, (sum, t) => sum + t.fare);
    } catch (_) {
      // log qilinishi mumkin
    } finally {
      tripsLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadUserTrips() async {
    try {
      final aliases = phoneAliases(phone);
      trips = await _tripsRepo.completedByUser(aliases);
    } catch (_) {
    } finally {
      tripsLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadOrders() async {
    try {
      final aliases = phoneAliases(phone);
      orders = await _ordersRepo.recentByUser(aliases);
    } catch (_) {
    } finally {
      ordersLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshOrders() async {
    ordersLoading = true;
    notifyListeners();
    await _loadOrders();
  }

  /// Address edit экранидан қайтгандан кейин:
  ///   - SharedPreferences'дaги legacy `user_address` ни қайта ўқийди
  ///   - Firestore'дан `structuredAddress` ни **ҳақиқатдан** қайта юклайди
  ///
  /// Bu метод `Navigator.pop` каллер addr-ни ушлай олмаган ҳолатлар (масалан,
  /// AddressGate бошқа окимдан очилган) учун keng tarmoqli fallback.
  Future<void> reloadAddressFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    address = prefs.getString('user_address') ?? '';
    notifyListeners();
    await _loadStructuredAddress();
  }

  /// AddressEditScreen `Navigator.pop(context, address)` қайтарган `UserAddress`
  /// ни тўғридан-тўғри қабул қилиш — Firestore'дан қайта ўқишга hojat yo'q.
  ///
  /// Bu eng tezkor yo'l: ekran allaqachon saqlab bo'lgan, kontroller darhol
  /// state'ни yangiletadi va warning banner yo'qoladi.
  void applyAddress(UserAddress addr) {
    structuredAddress = addr;
    address = addr.formatted;
    notifyListeners();
  }

  // ─── Tahrirlash rejimi ─────────────────────────────────────────────
  void startEditing() {
    isEditing = true;
    notifyListeners();
  }

  void cancelEditing() {
    isEditing = false;
    notifyListeners();
  }

  void setGender(String v) {
    gender = v;
    notifyListeners();
  }

  void setRole(String v) {
    role = v;
    notifyListeners();
  }

  /// Roleni darhol saqlash (chip bosilganda).
  /// Rolени тeзкор сaқлaш — SharedPreferences + Firestore + FCM listener restart.
  ///
  /// Firestore сaқлaш муҳим: `AdminService.isCurrentUserAdmin()` server-side
  /// rolени тeкширaди — фaқaт локaл сaқлaнсa, Админ панелгa киришни рaд этaди.
  Future<void> quickSaveRole(String v) async {
    role = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', v);

    // Firestore'гa ёзиш — `AdminService` ва бошқa role-aware экранлaр учун.
    final uid = phoneDigits(phone);
    if (uid.length >= 9) {
      try {
        await _userRepo.updateProfile(uid: uid, role: v);
      } catch (_) {
        // Internet yo'q — keyingi load()да синxронлaнaди.
      }
    }

    try {
      FCMService().stopListeners();
      await FCMService().startListeners();
    } catch (_) {}
  }

  /// Admin PIN — Cloud Function orqali Firestore'da `role: admin` (client rules ruxsat bermaydi).
  Future<String?> promoteToAdminWithPin(String pin) async {
    final uid = phoneDigits(phone);
    if (uid.length < 9) {
      return 'Аввал телефон рақамингизни профилда сақланг.';
    }
    try {
      final fn =
          FirebaseFunctions.instance.httpsCallable('promoteToAdminWithPin');
      await fn.call(<String, dynamic>{
        'phone': phone,
        'pin': pin.trim(),
      });
      await quickSaveRole('admin');
      return null;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found' || e.code == 'unimplemented') {
        return 'Server funksiyasi deploy qilinmagan. '
            'Firebase Console → users/$uid → role = admin qo\'ying '
            'yoki: firebase deploy --only functions:promoteToAdminWithPin';
      }
      return e.message ?? 'Admin rol berilmadi (${e.code})';
    } catch (e) {
      return 'Xatolik: $e';
    }
  }

  /// Forma maydonlaridan kelgan yangi qiymatlar bilan saqlash.
  Future<bool> save({
    required String newName,
    required String newPhone,
    required String newAddress,
  }) async {
    if (newName.trim().isEmpty) {
      errorMessage = 'Исмни киритинг';
      notifyListeners();
      return false;
    }

    isSaving = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    _oldRole = prefs.getString('user_role') ?? 'user';
    final currentPhone = phone.trim();
    final requestedPhone = newPhone.trim();
    final phoneChanged =
        phoneDigits(requestedPhone) != phoneDigits(currentPhone);

    if (phoneChanged) {
      final currentUid = phoneDigits(currentPhone);
      if (currentUid.length < 9 || phoneDigits(requestedPhone).length < 9) {
        isSaving = false;
        errorMessage = 'Телефон рақамини тўлиқ киритинг';
        notifyListeners();
        return false;
      }
      try {
        final device = await _deviceIdentity.getSnapshot();
        await _userRepo.requestPhoneChange(
          deviceId: device.deviceId,
          currentUserId: currentUid,
          currentPhone: currentPhone,
          requestedPhone: requestedPhone,
          signalKey: device.signalKey,
          signals: device.signals,
        );
        successMessage =
            'Телефон рақамини ўзгартириш сўрови админга юборилди';
      } catch (e) {
        isSaving = false;
        errorMessage = 'Телефон ўзгартириш сўрови юборилмади: $e';
        notifyListeners();
        return false;
      }
    }

    await prefs.setString('user_name', newName.trim());
    if (!phoneChanged) {
      await prefs.setString('user_phone', requestedPhone);
    }
    await prefs.setString('user_gender', gender);
    await prefs.setString('user_role', role);
    await prefs.setString('user_address', newAddress.trim());

    name = newName.trim();
    if (!phoneChanged) {
      phone = requestedPhone;
    }
    address = newAddress.trim();
    isEditing = false;
    isSaving = false;
    successMessage ??= 'Маълумотлар сақланди';
    notifyListeners();

    try {
      await FCMService().refreshToken();
      FCMService().stopListeners();
      await FCMService().startListeners();
    } catch (_) {}

    return true;
  }

  bool _isValidBirthDate(String value) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
    if (m == null) return false;
    final y = int.tryParse(m.group(1)!);
    final mo = int.tryParse(m.group(2)!);
    final d = int.tryParse(m.group(3)!);
    if (y == null || mo == null || d == null) return false;
    final now = DateTime.now();
    try {
      final parsed = DateTime(y, mo, d);
      if (parsed.year != y || parsed.month != mo || parsed.day != d) {
        return false;
      }
      if (parsed.isAfter(now)) return false;
      if (parsed.year < 1920) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> saveBirthDateOrRequest(String requestedBirthDate) async {
    final requested = requestedBirthDate.trim();
    if (!_isValidBirthDate(requested)) {
      errorMessage = 'Туғилган кун формати YYYY-MM-DD бўлсин';
      notifyListeners();
      return false;
    }

    final uid = phoneDigits(phone);
    if (uid.length < 9) {
      errorMessage = 'Аввал телефон рақамингизни профилда сақланг';
      notifyListeners();
      return false;
    }

    isSaving = true;
    notifyListeners();
    try {
      if (birthDate.trim().isEmpty || birthDate.trim() == requested) {
        await _userRepo.setBirthDateIfEmpty(uid: uid, birthDate: requested);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_birth_date', requested);
        birthDate = requested;
        successMessage = 'Туғилган кун сақланди';
      } else {
        await _userRepo.requestBirthDateChange(
          uid: uid,
          currentBirthDate: birthDate,
          requestedBirthDate: requested,
        );
        successMessage = 'Ўзгартириш сўрови админга юборилди';
      }
      return true;
    } on StateError catch (_) {
      await _userRepo.requestBirthDateChange(
        uid: uid,
        currentBirthDate: birthDate,
        requestedBirthDate: requested,
      );
      successMessage = 'Ўзгартириш сўрови админга юборилди';
      return true;
    } catch (e) {
      errorMessage = 'Хатолик: $e';
      return false;
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  // ─── GPS orqali manzil ─────────────────────────────────────────────
  Future<String?> fetchAddressFromGps() async {
    isGpsLoading = true;
    notifyListeners();
    try {
      final addr = await _locationService.getCurrentAddress();
      address = addr;
      return addr;
    } on LocationException catch (e) {
      errorMessage = e.kind == LocationErrorKind.permissionDenied
          ? 'GPS рухсати берилмади'
          : 'GPS аниқланмади';
      return null;
    } finally {
      isGpsLoading = false;
      notifyListeners();
    }
  }

  // ─── Profil rasmi ──────────────────────────────────────────────────
  Future<void> pickImage(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 80);
    if (file == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final saved = await File(file.path).copy('${dir.path}/profile.jpg');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_image', saved.path);
    imagePath = saved.path;
    notifyListeners();
  }

  Future<void> deleteImage() async {
    if (imagePath != null) {
      final f = File(imagePath!);
      if (await f.exists()) await f.delete();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('profile_image');
    imagePath = null;
    notifyListeners();
  }

  // ─── Snackbar xabarlarini "iste'mol" qilish ───────────────────────
  String? consumeError() {
    final m = errorMessage;
    errorMessage = null;
    return m;
  }

  String? consumeSuccess() {
    final m = successMessage;
    successMessage = null;
    return m;
  }

  // ─── Chiqib ketish ─────────────────────────────────────────────────
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
