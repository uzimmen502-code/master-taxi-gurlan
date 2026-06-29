import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../intercity_taxi/driver/intercity_driver_resume.dart';
import '../../../models/order_model.dart';
import '../../../models/trip_model.dart';
import '../../../models/user_address.dart';
import '../../../repositories/driver_repository.dart';
import '../../../repositories/marshrut_driver_repository.dart';
import '../../../repositories/orders_repository.dart';
import '../../../repositories/trips_repository.dart';
import '../../../repositories/couriers_repository.dart';
import '../../../repositories/device_binding_repository.dart';
import '../../../repositories/user_repository.dart';
import '../../../services/device_fingerprint_service.dart';
import '../../../services/fcm_service.dart';
import '../../../services/location_service.dart';
import '../../../services/user_role_sync.dart';

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
    MarshrutDriverRepository? marshrutDriverRepo,
  })  : _driverRepo = driverRepo,
        _marshrutDriverRepo = marshrutDriverRepo ?? MarshrutDriverRepository(),
        _tripsRepo = tripsRepo,
        _ordersRepo = ordersRepo,
        _userRepo = userRepo,
        _locationService = locationService;

  final DriverRepository _driverRepo;
  final MarshrutDriverRepository _marshrutDriverRepo;
  final TripsRepository _tripsRepo;
  final OrdersRepository _ordersRepo;
  final UserRepository _userRepo;
  final LocationService _locationService;
  final _fingerprintService = DeviceFingerprintService();
  final _bindingRepo = DeviceBindingRepository();

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
  String _carModel = '';
  String _carColor = '';
  String _carPlate = '';
  int _carSeats = 0;
  String taxiType = 'alone';

  String get carModel => _carModel;
  String get carColor => _carColor;
  String get carPlate => _carPlate;
  int get carSeats => _carSeats;
  bool get hasCarInfo =>
      _carModel.isNotEmpty &&
      _carColor.isNotEmpty &&
      _carPlate.isNotEmpty &&
      _carSeats > 0;

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

  SharedPreferences? _prefs;
  bool _driverOnline = false;

  bool get isDriverOnline => _prefs?.getBool('driver_is_online') ?? _driverOnline;

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
    _prefs = prefs;
    _driverOnline = prefs.getBool('driver_is_online') ?? false;
    role = await UserRoleSync().syncToPreferences();
    name = prefs.getString('user_name') ?? '';
    phone = prefs.getString('user_phone') ?? '';
    gender = prefs.getString('user_gender') ?? 'male';
    birthDate = prefs.getString('user_birth_date') ?? '';
    address = prefs.getString('user_address') ?? '';
    imagePath = prefs.getString('profile_image');
    taxiType = prefs.getString('taxi_type') ?? 'alone';

    final carFromFirestore =
        await _userRepo.getCarInfo(phoneDigits(phone));
    if (carFromFirestore != null) {
      _carModel = carFromFirestore['carModel'] ?? '';
      _carColor = carFromFirestore['carColor'] ?? '';
      _carPlate = carFromFirestore['carPlate'] ?? '';
      _carSeats =
          int.tryParse(carFromFirestore['carSeats'] ?? '') ??
              prefs.getInt('car_seats') ??
              0;
    } else {
      _carModel = prefs.getString('car_model') ?? '';
      _carColor = prefs.getString('car_color') ?? '';
      _carPlate = prefs.getString('car_plate') ?? '';
      _carSeats = prefs.getInt('car_seats') ?? 0;
    }
    notifyListeners();

    // Структуралaнган манзилни Firestore'дан ўқиш (паралел).
    final tasks = <Future<void>>[_loadStructuredAddress()];
    if (role == 'driver' && phone.isNotEmpty) {
      tasks.addAll([
        _loadDriverStats(),
        _loadDriverTrips(),
        _syncDriverOnlineFromFirestore(),
      ]);
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
    final uid = canonicalPhoneId(phone);
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
      var firestoreRole = user.role;
      if (role == 'courier' && firestoreRole.trim() != 'courier') {
        try {
          await _userRepo.updateProfile(uid: uid, role: 'courier');
          firestoreRole = 'courier';
        } catch (_) {}
      } else if (role == 'user' && firestoreRole.trim() == 'courier') {
        try {
          await _userRepo.updateProfile(uid: uid, role: 'user');
          firestoreRole = 'user';
        } catch (_) {}
      }

      final resolved = UserRoleSync.reconcile(
        localRole: role,
        firestoreRole: firestoreRole,
      );
      if (resolved != role) {
        role = resolved;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_role', resolved);
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
    final uid = canonicalPhoneId(phone);
    final stats = await _driverRepo.getStats(uid);
    if (stats != null) {
      driverRating = stats.rating;
      driverTripCount = stats.ratingCount;
      notifyListeners();
    }
  }

  Future<void> _loadDriverTrips() async {
    try {
      final uid = canonicalPhoneId(phone);
      final list = await _tripsRepo.completedByDriver(uid);
      trips = list;
      driverEarnings = list.fold<int>(0, (acc, t) => acc + t.fare);
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
    if (UserRoleSync.isPrivileged(v)) return;
    role = v;
    notifyListeners();
  }

  /// Roleni darhol saqlash (chip bosilganda).
  /// Rolени тeзкор сaқлaш — SharedPreferences + Firestore + FCM listener restart.
  ///
  /// Firestore сaқлaш муҳим: `AdminService.isCurrentUserAdmin()` server-side
  /// rolени тeкширaди — фaқaт локaл сaқлaнсa, Админ панелгa киришни рaд этaди.
  Future<void> _syncDriverOnlineFromFirestore() async {
    final uid = canonicalPhoneId(phone);
    if (uid.length < 9) return;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('drivers').doc(uid).get();
      final online = snap.data()?['isOnline'] == true;
      _driverOnline = online;
      await _prefs?.setBool('driver_is_online', online);
      notifyListeners();
    } catch (_) {}
  }

  /// Смена тугатиш — роль `driver` қолади, офлайн (Concept B).
  Future<void> endShift() async {
    final uid = canonicalPhoneId(phone);
    if (uid.length < 9) {
      errorMessage = 'shift_end_error';
      notifyListeners();
      return;
    }
    try {
      await _marshrutDriverRepo.goOffline(uid);
      await _driverRepo.goOffline(uid);
      _driverOnline = false;
      await _prefs?.setBool('driver_is_online', false);
      notifyListeners();
    } catch (e) {
      errorMessage = 'shift_end_error';
      notifyListeners();
    }
  }

  Future<bool> saveCarInfo({
    required String model,
    required String color,
    required String plate,
    required int seats,
  }) async {
    try {
      await _userRepo.saveCarInfo(
        uid: phoneDigits(phone),
        carModel: model,
        carColor: color,
        carPlate: plate,
        carSeats: seats,
      );
      _carModel = model;
      _carColor = color;
      _carPlate = plate;
      _carSeats = seats;
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = 'error_generic';
      notifyListeners();
      return false;
    }
  }

  Future<void> clearCarInfo() async {
    try {
      final uid = canonicalPhoneId(phoneDigits(phone));
      await _userRepo.clearCarInfo(uid);
      _carModel = '';
      _carColor = '';
      _carPlate = '';
      _carSeats = 0;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('car_model');
      await prefs.remove('car_color');
      await prefs.remove('car_plate');
      await prefs.remove('car_seats');
      notifyListeners();
    } catch (e) {
      errorMessage = 'error_generic';
      notifyListeners();
    }
  }

  Future<bool> quickSaveRole(String v) async {
    if (!isClientAssignableRole(v)) {
      errorMessage =
          'Админ ролини фақат админ панел орқали бериш мумкин.';
      notifyListeners();
      return false;
    }
    if (v == 'courier' && role == 'driver') {
      errorMessage = 'Haydovchi rolini PIN orqali kuryerga o\'zgartirib bo\'lmaydi.';
      notifyListeners();
      return false;
    }
    if (UserRoleSync.isPrivileged(role)) {
      errorMessage =
          'Админ ролини фақат админ панел орқали бериш мумкин.';
      notifyListeners();
      return false;
    }
    role = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', v);

    var firestoreOk = true;
    final uid = canonicalPhoneId(phone);
    if (uid.length >= 9 &&
        (v == 'courier' || v == 'user')) {
      try {
        await _userRepo.updateProfile(uid: uid, role: v);
      } catch (_) {
        firestoreOk = false;
      }
    }

    try {
      FCMService().stopListeners();
      await FCMService().startListeners();
    } catch (_) {}

    return firestoreOk || v == 'courier';
  }

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
      await _changePhone(requestedPhone);
      if (errorMessage != null) {
        isSaving = false;
        notifyListeners();
        return false;
      }
      successMessage = 'Телефон рақами янгиланди';
    }

    await prefs.setString('user_name', newName.trim());
    if (!phoneChanged) {
      await prefs.setString('user_phone', requestedPhone);
    }
    await prefs.setString('user_gender', gender);
    final roleToSave =
        isClientAssignableRole(role) ? role : 'user';
    if (roleToSave != role) {
      role = roleToSave;
    }
    await prefs.setString('user_role', roleToSave);
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

    final uid = canonicalPhoneId(phone);
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
      errorMessage = LocationException.userMessage(e.kind);
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

  Future<void> _changePhone(String newPhone) async {
    try {
      final snapshot = await _fingerprintService.collect();
      final fingerprintHash = snapshot.hash;
      if (!DeviceBindingRepository.isValidFingerprintHash(fingerprintHash)) {
        _showError('Қурилма идентификатори хато');
        return;
      }
      final currentBinding =
          await _bindingRepo.getBinding(fingerprintHash);
      if (currentBinding == null) {
        _showError('Қурилма топилмади');
        return;
      }
      await FirebaseFunctions.instance
          .httpsCallable('changeDevicePhone')
          .call({
        'deviceFingerprintHash': fingerprintHash,
        'newPhone': phoneDigits(newPhone),
      });
      await load();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_phone', canonicalPhoneId(newPhone));
      phone = canonicalPhoneId(newPhone);
      notifyListeners();
    } catch (e) {
      _showError('Хатолик: $e');
    }
  }

  void _showError(String message) {
    errorMessage = message;
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
    IntercityDriverResume.resetSession();
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('role') ?? '';
    final userId = prefs.getString('userId') ?? '';
    if (role == 'courier' && userId.isNotEmpty) {
      try {
        await CouriersRepository().goOffline(userId);
      } catch (_) {}
    }
    await FirebaseAuth.instance.signOut();
    await prefs.remove('phone_reverified');
    await prefs.clear();
  }
}
