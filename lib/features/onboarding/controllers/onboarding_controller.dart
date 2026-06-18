import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/firebase_functions_errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/user_address.dart';
import '../../../repositories/device_binding_repository.dart';
import '../../../repositories/pending_code_repository.dart';
import '../../../repositories/user_repository.dart';
import '../../../services/device_fingerprint_service.dart';
import '../../../services/fcm_service.dart';
import '../../../services/location_service.dart';

/// Onboarding wizard uchun ChangeNotifier.
class OnboardingController extends ChangeNotifier {
  OnboardingController({
    required UserRepository userRepo,
    required LocationService locationService,
    DeviceFingerprintService? fingerprintService,
    DeviceBindingRepository? deviceBindingRepo,
    PendingCodeRepository? pendingCodeRepo,
  })  : _userRepo = userRepo,
        _locationService = locationService,
        _fingerprintService = fingerprintService ?? DeviceFingerprintService(),
        _deviceBindingRepo = deviceBindingRepo ?? DeviceBindingRepository(),
        _pendingCodeRepo = pendingCodeRepo ?? PendingCodeRepository();

  final UserRepository _userRepo;
  final LocationService _locationService;
  final DeviceFingerprintService _fingerprintService;
  final DeviceBindingRepository _deviceBindingRepo;
  final PendingCodeRepository _pendingCodeRepo;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  StreamSubscription<PendingCodeStatusUpdate>? _pendingCodeSubscription;
  bool isVerifyingOtp = false;
  bool isSendingOtp = false;
  String? otpError;
  bool otpVerified = false;
  bool isAdminCodeReady = false;
  String? generatedAdminCode;

  DeviceFingerprintSnapshot? _fingerprintSnapshot;
  bool _bindingRegistered = false;
  String _deviceLockedUid = '';

  static const totalPages = 6;

  int currentPage = 0;
  String gender = 'male';
  String birthDate = '';

  String mfy = '';
  String street = '';
  String house = '';
  String district = 'Гурлан';
  String note = '';

  double? lat;
  double? lng;
  double? accuracy;
  DateTime? geoUpdatedAt;
  bool gpsFromLastKnown = false;

  String? geoHint;
  bool isGeoHintLoading = false;

  bool isSubmitting = false;
  bool isGpsLoading = false;
  String? errorMessage;

  bool isCheckingDevice = false;
  String? phoneStepError;

  bool get isLastPage => currentPage == totalPages - 1;
  bool get skipSmsVerification => otpVerified && _bindingRegistered;

  bool get hasManualParts =>
      mfy.trim().isNotEmpty &&
      street.trim().isNotEmpty &&
      house.trim().isNotEmpty;

  bool get hasGps => lat != null && lng != null;

  bool get hasCompleteAddress => hasManualParts && hasGps;

  bool get hasLowAccuracyGps {
    if (accuracy == null) return false;
    return accuracy! > 100;
  }

  bool isGpsRequiredForPhone(String phone) => true;

  void setGender(String v) {
    gender = v;
    notifyListeners();
  }

  void setBirthDate(String v) {
    birthDate = v.trim();
    notifyListeners();
  }

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
      case 2:
        if (!otpVerified) return 'Телефон рақамини тасдиқланг';
        break;
      case 5:
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
    if (currentPage == 2) {
      cancelPendingCodeWatch();
      otpVerified = false;
      otpError = null;
      isAdminCodeReady = false;
      generatedAdminCode = null;
    }
    if (currentPage == 1) resetPhoneStepError();
    if (currentPage > 0) {
      currentPage--;
      notifyListeners();
    }
  }

  Future<DeviceFingerprintSnapshot> _ensureFingerprint() async {
    _fingerprintSnapshot ??= await _fingerprintService.collect();
    return _fingerprintSnapshot!;
  }

  /// Faqat SHA-256 fingerprintHash (64 hex) — eski `device_bindings` ID lar ishlatilmaydi.
  Future<bool> _requireValidFingerprintHash() async {
    final snapshot = await _ensureFingerprint();
    if (!DeviceBindingRepository.isValidFingerprintHash(snapshot.hash)) {
      phoneStepError =
          'Qurilma identifikatori noto\'g\'ri. Ilovani qayta oching yoki qayta o\'rnating.';
      notifyListeners();
      return false;
    }
    return true;
  }

  /// Telefon + composite fingerprint bo'yicha qurilma bog'lanishini tekshiradi.
  Future<bool> checkPhoneDeviceLock(String phone) async {
    final digits = phoneDigits(phone);
    if (digits.length < 12) {
      phoneStepError = 'Телефон рақамини тўлиқ киритинг';
      notifyListeners();
      return false;
    }
    if (_deviceLockedUid == digits && otpVerified) {
      phoneStepError = null;
      notifyListeners();
      return true;
    }

    isCheckingDevice = true;
    phoneStepError = null;
    notifyListeners();

    try {
      if (!await _hasNetworkInterface()) {
        phoneStepError =
            'Интернет уланиши йўқ. Internetni yoqing va qayta urinib ko\'ring.';
        return false;
      }
      if (!await _requireValidFingerprintHash()) {
        return false;
      }
      final snapshot = _fingerprintSnapshot!;
      final result = await _deviceBindingRepo.checkDeviceBinding(
        phone: phone,
        snapshot: snapshot,
      );

      switch (result.status) {
        case DeviceBindingStatus.trustedDevice:
          final token = result.customToken;
          if (token != null && token.isNotEmpty) {
            await _auth.signInWithCustomToken(token);
          }
          otpVerified = true;
          _bindingRegistered = true;
          _deviceLockedUid = digits;
          phoneStepError = null;
          return true;

        case DeviceBindingStatus.needsVerification:
          _deviceLockedUid = digits;
          phoneStepError = null;
          return true;

        case DeviceBindingStatus.deviceBoundOtherPhone:
          phoneStepError =
              result.message ??
              'Бу қурилма boshqa raqamga bog\'liq. Adminga murojaat qiling.';
          return false;

        case DeviceBindingStatus.phoneBoundOtherDevice:
          phoneStepError =
              result.message ??
              'Bu raqam boshqa qurilmaga bog\'liq. Adminga murojaat qiling.';
          return false;

        case DeviceBindingStatus.blocked:
          phoneStepError =
              result.message ??
              'Qurilma vaqtincha bloklangan. Adminga murojaat qiling.';
          return false;

        case DeviceBindingStatus.unknown:
          phoneStepError = result.message ?? 'Noma\'lum xatolik. Qayta urinib ko\'ring.';
          return false;
      }
    } on FirebaseFunctionsException catch (e) {
      phoneStepError = firebaseFunctionsUserMessage(e);
      return false;
    } catch (e) {
      phoneStepError = 'Xatolik: $e';
      return false;
    } finally {
      isCheckingDevice = false;
      notifyListeners();
    }
  }

  String _pendingDocId(String rawPhone) => phoneDigits(rawPhone);

  void cancelPendingCodeWatch() {
    _pendingCodeSubscription?.cancel();
    _pendingCodeSubscription = null;
  }

  /// Admin panel orqali kod (real SMS yo'q).
  Future<bool> requestAdminCode(String rawPhone) async {
    final digits = _pendingDocId(rawPhone);
    if (digits.length < 12) {
      otpError = 'Telefon raqamini to\'liq kiriting';
      notifyListeners();
      return false;
    }

    isSendingOtp = true;
    otpError = null;
    isAdminCodeReady = false;
    generatedAdminCode = null;
    _deviceLockedUid = digits;
    notifyListeners();

    try {
      if (!await _requireValidFingerprintHash()) {
        return false;
      }
      final snapshot = _fingerprintSnapshot!;
      await _pendingCodeRepo.requestPendingCode(
        phone: digits,
        snapshot: snapshot,
      );

      cancelPendingCodeWatch();
      _pendingCodeSubscription = _pendingCodeRepo
          .watchStatus(
            phone: digits,
            deviceFingerprintHash: snapshot.hash,
          )
          .listen((update) {
        if (update.status == 'expired') {
          otpError = 'Код муддати ўтган. Қайта урининг.';
          isAdminCodeReady = false;
          generatedAdminCode = null;
          notifyListeners();
          return;
        }

        if (update.isApproved) {
          generatedAdminCode = update.code;
          isAdminCodeReady = true;
          otpError = null;
          notifyListeners();
        }
      }, onError: (Object e) {
        otpError = 'Xatolik: $e';
        notifyListeners();
      });

      return true;
    } catch (e) {
      otpError = 'Xatolik: $e';
      return false;
    } finally {
      isSendingOtp = false;
      notifyListeners();
    }
  }

  /// Eski nomlar — onboarding UI bilan mos.
  Future<bool> sendOtp(String rawPhone) => requestAdminCode(rawPhone);

  Future<bool> verifyAdminCode(String rawPhone, String enteredCode) async {
    final digits = _pendingDocId(rawPhone);
    final code = enteredCode.trim();
    if (digits.length < 12) {
      otpError = 'Telefon raqamini to\'liq kiriting';
      notifyListeners();
      return false;
    }
    if (code.length != 6) {
      otpError = '6 рақамли кодни киритинг';
      notifyListeners();
      return false;
    }

    isVerifyingOtp = true;
    otpError = null;
    notifyListeners();

    try {
      if (!await _requireValidFingerprintHash()) {
        return false;
      }
      final snapshot = _fingerprintSnapshot!;
      final callable =
          FirebaseFunctions.instance.httpsCallable('verifyPendingCodeAndRegister');
      final result = await callable.call<Map<String, dynamic>>({
        'phone': digits,
        'code': code,
        'deviceFingerprintHash': snapshot.hash,
        'fingerprint': Map<String, String>.from(snapshot.components),
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final token = data['customToken'] as String?;
      if (token != null && token.isNotEmpty) {
        await _auth.signInWithCustomToken(token);
      }
      otpVerified = true;
      _bindingRegistered = true;
      _deviceLockedUid = digits;
      cancelPendingCodeWatch();
      return true;
    } on FirebaseFunctionsException catch (e) {
      otpError = _callableErrorMessage(e);
      return false;
    } catch (e) {
      otpError = 'Xatolik: $e';
      return false;
    } finally {
      isVerifyingOtp = false;
      notifyListeners();
    }
  }

  Future<bool> verifyOtp(String code) =>
      verifyAdminCode(_deviceLockedUid, code);

  void resetPhoneStepError() {
    phoneStepError = null;
    notifyListeners();
  }

  String _callableErrorMessage(FirebaseFunctionsException e) =>
      firebaseFunctionsUserMessage(e);

  Future<bool> _hasNetworkInterface() async {
    if (kIsWeb) return true;
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<bool> fetchGps() async {
    isGpsLoading = true;
    errorMessage = null;
    geoHint = null;
    notifyListeners();
    try {
      final coords = await _locationService.getCurrentCoords();
      lat = coords.lat;
      lng = coords.lng;
      accuracy = coords.accuracy;
      geoUpdatedAt = DateTime.now();
      gpsFromLastKnown = coords.fromLastKnown;

      isGpsLoading = false;
      notifyListeners();

      unawaited(_loadGeoHintInBackground(coords.lat, coords.lng));
      return true;
    } on LocationException catch (e) {
      errorMessage = LocationException.userMessage(e.kind);
      return false;
    } finally {
      if (isGpsLoading) {
        isGpsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadGeoHintInBackground(double lat, double lng) async {
    isGeoHintLoading = true;
    notifyListeners();
    try {
      final hint = await _locationService.addressFromCoords(
        lat,
        lng,
        timeout: const Duration(seconds: 5),
        fallbackToCoords: false,
      );
      geoHint = hint?.trim().isNotEmpty == true ? hint!.trim() : null;
    } catch (_) {
      geoHint = null;
    } finally {
      isGeoHintLoading = false;
      notifyListeners();
    }
  }

  Future<bool> finish({
    required String name,
    required String phone,
  }) async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) {
      debugPrint('finish() blocked: no Firebase session');
      return false;
    }

    final gpsRequired = isGpsRequiredForPhone(phone);
    if (gpsRequired && !hasGps) {
      errorMessage =
          'GPS manzilni oling — "Joriy GPS manzilni olish" tugmasini bosing';
      notifyListeners();
      return false;
    }
    if (!hasManualParts) {
      errorMessage = 'MFY, ko\'cha va uy raqamini to\'ldiring';
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
      district: district.trim().isEmpty ? 'Gurlan' : district.trim(),
      note: note.trim(),
      lat: lat,
      lng: lng,
      accuracy: accuracy,
      geoUpdatedAt: geoUpdatedAt,
      manualUpdatedAt: DateTime.now(),
    );
    final formatted = structured.formatted;

    try {
      await _userRepo.createOrMergeProfileWithAddress(
        uid: uid,
        phone: phone,
        name: name,
        gender: gender,
        birthDate: birthDate,
        legacyAddressLine: formatted,
        address: structured,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userId', uid);
      await prefs.setString('userName', name.trim());
      await prefs.setString('user_name', name.trim());
      await prefs.setString('user_phone', canonicalPhoneId(phone.trim()));
      await prefs.setString('user_gender', gender);
      if (birthDate.isNotEmpty) {
        await prefs.setString('user_birth_date', birthDate);
      }
      await prefs.setString('user_address', formatted);
      await prefs.setBool('onboarding_done', true);
      await prefs.setBool('phone_reverified', true);

      try {
        await FCMService().refreshToken();
        FCMService().stopListeners();
        await FCMService().startListeners();
      } catch (_) {}

      _deviceLockedUid = uid;
      return true;
    } catch (e) {
      errorMessage = 'Xatolik: $e';
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
