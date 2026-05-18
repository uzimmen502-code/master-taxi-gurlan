import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/user_address.dart';
import '../../../repositories/user_repository.dart';
import '../../../services/device_identity_service.dart';
import '../../../services/fcm_service.dart';
import '../../../services/location_service.dart';

/// Onboarding wizard uchun ChangeNotifier.
///
/// 5 sahifa: ism → telefon (device lock) → jins → tug'ilgan kun → **manzil**.
///
/// Manzil sahifasida foydalanuvchi GPS bilan koordinatasini oladi va shu yerda
/// MFY/ko'cha/uy/tuman maydonlarini to'ldiradi — `finish()` ikkalasini ham
/// `UserModel`ga yozadi. Shu sababli onboarding bajarilgan zahoti foydalanuvchi
/// to'liq manzilga ega (legacy `address` string + structured `UserAddress`).
/// Profil ekranida "kelajakda to'ldiring" warning'i chiqmaydi.
class OnboardingController extends ChangeNotifier {
  OnboardingController({
    required UserRepository userRepo,
    required LocationService locationService,
  })  : _userRepo = userRepo,
        _locationService = locationService;

  final UserRepository _userRepo;
  final LocationService _locationService;
  final DeviceIdentityService _deviceIdentity = DeviceIdentityService();

  static const totalPages = 5;

  int currentPage = 0;
  String gender = 'male';
  String birthDate = '';

  // ─── Manzil holati (sahifa 5) ─────────────────────────────────────
  String mfy = '';
  String street = '';
  String house = '';
  String district = 'Гурлан';
  String note = '';

  double? lat;
  double? lng;
  double? accuracy;
  DateTime? geoUpdatedAt;

  /// GPSdan reverse geocoding orqali olingan inson o'qiy oladigan manzil.
  /// Faqat `street` bo'sh bo'lganda avto-prefill uchun ishlatamiz.
  String _geoSuggestedStreet = '';

  bool isSubmitting = false;
  bool isGpsLoading = false;
  String? errorMessage;

  // ─── Open access + device lock ──────────────────────────────────────
  bool isCheckingDevice = false;
  String? phoneStepError;
  String _deviceLockedUid = '';

  bool get isLastPage => currentPage == totalPages - 1;

  /// 3 ta majburiy qo'lda maydon to'ldirilganmi?
  bool get hasManualParts =>
      mfy.trim().isNotEmpty &&
      street.trim().isNotEmpty &&
      house.trim().isNotEmpty;

  /// GPS olinganmi?
  bool get hasGps => lat != null && lng != null;

  /// 4-sahifa to'la mukammalmi — `finish()` faqat shunda ishlaydi.
  bool get hasCompleteAddress => hasManualParts && hasGps;

  bool isGpsRequiredForPhone(String phone) {
    if (!kIsWeb) return true;
    return phoneDigits(phone) != '998912778777';
  }

  void setGender(String v) {
    gender = v;
    notifyListeners();
  }

  void setBirthDate(String v) {
    birthDate = v.trim();
    notifyListeners();
  }

  // ─── Manzil maydonlari ─────────────────────────────────────────────
  void setMfy(String v) {
    mfy = v;
    notifyListeners();
  }

  void setStreet(String v) {
    street = v;
    notifyListeners();
  }

  void setHouse(String v) {
    house = v;
    notifyListeners();
  }

  void setDistrict(String v) {
    district = v;
    notifyListeners();
  }

  void setNote(String v) {
    note = v;
    notifyListeners();
  }

  /// Joriy sahifani validatsiya qiladi.
  /// Xatolik bo'lsa — string qaytaradi (snackbar uchun), aks holda `null`.
  String? validate({
    required String name,
    required String phone,
  }) {
    switch (currentPage) {
      case 0:
        if (name.trim().isEmpty) return 'Исмингизни киритинг';
        break;
      case 1:
        final d = phoneDigits(phone);
        if (d.length < 12) return 'Телефон рақамини тўлиқ киритинг';
        break;
      case 4:
        final gpsRequired = isGpsRequiredForPhone(phone);
        if (gpsRequired && !hasGps) {
          return 'GPS манзилни олинг — "Жорий GPS манзилни олиш" тугмасини босинг';
        }
        if (!hasManualParts) {
          return 'МФЙ, кўча ва уй рақамини тўлдиринг';
        }
        break;
    }
    return null;
  }

  void goToPage(int page) {
    currentPage = page;
    notifyListeners();
  }

  void advance() {
    if (currentPage < totalPages - 1) {
      currentPage++;
      notifyListeners();
    }
  }

  void back() {
    if (currentPage == 1) resetPhoneStepError();
    if (currentPage > 0) {
      currentPage--;
      notifyListeners();
    }
  }

  Future<bool> checkPhoneDeviceLock(String phone) async {
    final digits = phoneDigits(phone);
    if (digits.length < 12) {
      phoneStepError = 'Телефон рақамини тўлиқ киритинг';
      notifyListeners();
      return false;
    }
    if (_deviceLockedUid == digits) {
      phoneStepError = null;
      notifyListeners();
      return true;
    }
    isCheckingDevice = true;
    phoneStepError = null;
    notifyListeners();

    try {
      final device = await _deviceIdentity.getSnapshot();
      await _userRepo.bindDeviceOrRequestChange(
        deviceId: device.deviceId,
        uid: digits,
        phone: phone,
        signalKey: device.signalKey,
        signals: device.signals,
      );
      _deviceLockedUid = digits;
      return true;
    } on StateError catch (e) {
      if (e.message == 'device_bound_to_other_phone') {
        phoneStepError =
            'Бу қурилма аввал бошқа телефон рақамга боғланган. Рақамни алмаштириш сўрови админга юборилди.';
      } else {
        phoneStepError = 'Хатолик: ${e.message}';
      }
      return false;
    } catch (e) {
      phoneStepError = 'Хатолик: $e';
      return false;
    } finally {
      isCheckingDevice = false;
      notifyListeners();
    }
  }

  void resetPhoneStepError() {
    phoneStepError = null;
    notifyListeners();
  }

  /// GPS koordinatalarini oladi va, agar `street` hali bo'sh bo'lsa, reverse
  /// geocoding'dan ko'cha nomini qo'shimcha hint sifatida saqlaydi.
  ///
  /// Qaytariladi `true` muvaffaqiyat bo'lsa, `false` — ruxsat yo'q yoki xato.
  Future<bool> fetchGps() async {
    isGpsLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final coords = await _locationService.getCurrentCoords(
        timeout: const Duration(seconds: 10),
      );
      lat = coords.lat;
      lng = coords.lng;
      accuracy = coords.accuracy;
      geoUpdatedAt = DateTime.now();

      // Reverse geocoding — alohida try/catch, GPS muvaffaqiyatli bo'lsa
      // ko'cha topilmaslik onboardingni to'xtatmasin.
      try {
        _geoSuggestedStreet =
            await _locationService.addressFromCoords(coords.lat, coords.lng);
      } catch (_) {
        _geoSuggestedStreet = '';
      }
      // Agar foydalanuvchi `street`'ni hali yozmagan bo'lsa — auto-prefill.
      if (street.trim().isEmpty && _geoSuggestedStreet.isNotEmpty) {
        street = _geoSuggestedStreet;
      }
      return true;
    } on LocationException catch (e) {
      errorMessage = e.kind == LocationErrorKind.permissionDenied
          ? 'GPS рухсати йўқ. Илтимос, телефон созламаларидан рухсат беринг.'
          : 'GPS аниқланмади. Очиқ жойга чиқиб қайта уриниб кўринг.';
      return false;
    } finally {
      isGpsLoading = false;
      notifyListeners();
    }
  }

  /// Onboarding tugаgach: Firestore'ga foydalanuvchi yaratiladi —
  /// **legacy `address` string + structured `UserAddress`** ikkalasi ham
  /// yoziladi. SharedPreferences'ga yozish ham shu yerda.
  Future<bool> finish({
    required String name,
    required String phone,
  }) async {
    final gpsRequired = isGpsRequiredForPhone(phone);
    if (gpsRequired && !hasGps) {
      errorMessage =
          'GPS манзилни олинг — "Жорий GPS манзилни олиш" тугмасини босинг';
      notifyListeners();
      return false;
    }
    if (!hasManualParts) {
      errorMessage = 'МФЙ, кўча ва уй рақамини тўлдиринг';
      notifyListeners();
      return false;
    }

    isSubmitting = true;
    notifyListeners();

    final uid = phoneDigits(phone);
    final structured = UserAddress(
      mfy: mfy.trim(),
      street: street.trim(),
      house: house.trim(),
      district: district.trim().isEmpty ? 'Гурлан' : district.trim(),
      note: note.trim(),
      lat: lat,
      lng: lng,
      accuracy: accuracy,
      geoUpdatedAt: geoUpdatedAt,
      manualUpdatedAt: DateTime.now(),
    );
    final formatted = structured.formatted;

    try {
      if (_deviceLockedUid != uid) {
        final device = await _deviceIdentity.getSnapshot();
        await _userRepo.bindDeviceOrRequestChange(
          deviceId: device.deviceId,
          uid: uid,
          phone: phone,
          signalKey: device.signalKey,
          signals: device.signals,
        );
        _deviceLockedUid = uid;
      }

      await _userRepo.createOrMergeProfileWithAddress(
        uid: uid,
        phone: phone,
        name: name,
        gender: gender,
        birthDate: birthDate,
        legacyAddressLine: formatted,
        address: structured,
      );

      // 2) SharedPreferences — eski va yangi key'lar ikkalasi (boshqa
      //    joylarda ishlatilgan).
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userId', uid);
      await prefs.setString('userName', name.trim());
      await prefs.setString('user_name', name.trim());
      await prefs.setString('user_phone', phone.trim());
      await prefs.setString('user_gender', gender);
      if (birthDate.isNotEmpty) {
        await prefs.setString('user_birth_date', birthDate);
      }
      await prefs.setString('user_address', formatted);
      await prefs.setBool('onboarding_done', true);

      try {
        await FCMService().refreshToken();
        FCMService().stopListeners();
        await FCMService().startListeners();
      } catch (_) {}

      return true;
    } on StateError catch (e) {
      if (e.message == 'device_bound_to_other_phone') {
        errorMessage =
            'Бу қурилма аввал бошқа телефон рақамга боғланган. Рақамни алмаштириш сўрови админга юборилди.';
      } else {
        errorMessage = 'Хатолик: ${e.message}';
      }
      return false;
    } catch (e) {
      errorMessage = 'Хатолик: $e';
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  String? consumeError() {
    final m = errorMessage;
    errorMessage = null;
    return m;
  }
}
