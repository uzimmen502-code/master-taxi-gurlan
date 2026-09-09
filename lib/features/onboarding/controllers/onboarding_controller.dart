import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/service_config_holder.dart';
import '../../../core/utils/firebase_functions_errors.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/user_address.dart';
import '../../../repositories/device_binding_repository.dart';
import '../../../repositories/user_repository.dart';
import '../../../services/device_fingerprint_service.dart';
import '../../../services/fcm_service.dart';
import '../../tv_market/services/tv_owner_name.dart';

/// Onboarding wizard uchun ChangeNotifier.
class OnboardingController extends ChangeNotifier {
  OnboardingController({
    required UserRepository userRepo,
    DeviceFingerprintService? fingerprintService,
    DeviceBindingRepository? deviceBindingRepo,
  })  : _userRepo = userRepo,
        _fingerprintService = fingerprintService ?? DeviceFingerprintService(),
        _deviceBindingRepo = deviceBindingRepo ?? DeviceBindingRepository();

  final UserRepository _userRepo;
  final DeviceFingerprintService _fingerprintService;
  final DeviceBindingRepository _deviceBindingRepo;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Custom token sign-in + force-refresh so Firestore rules see
  /// durable `phone_number` claim (isOwner) on the next request.
  Future<void> _signInWithPhoneCustomToken(String token) async {
    await _auth.signInWithCustomToken(token);
    await _auth.currentUser?.getIdToken(true);
  }

  /// Fingerprint binding OK (eski nom: otpVerified — bootstrap/finish учун).
  bool otpVerified = false;

  DeviceFingerprintSnapshot? _fingerprintSnapshot;
  bool _bindingRegistered = false;
  String _deviceLockedUid = '';

  /// Peer-transfer approve dan keyin bootstrap uchun.
  void markBindingRegistered(String phone) {
    final digits = phoneDigits(phone);
    otpVerified = true;
    _bindingRegistered = true;
    _deviceLockedUid = digits;
    phoneStepError = null;
    notifyListeners();
  }

  DeviceFingerprintSnapshot? get fingerprintSnapshot => _fingerprintSnapshot;

  /// Oxirgi checkDeviceBinding natijasi (conflict sheet uchun).
  DeviceBindingCheckResult? lastBindingResult;

  /// Ихчам онбординг: шахс+телефон → fingerprint bind → Home. Тил/туман олдинда.
  String gender = 'male';
  String birthDate = '';

  // Манзил (МФЙ/кўча/уй/GPS) онбордингда йиғилмайди — фойдаланувчи уни
  // Профилда (`AddressEditScreen`) киритади ва ўша ерда таҳрирлайди.

  // Config-driven zona (ixtiyoriy — tanlansa xizmat mavjudligini aniqlaydi).
  String geoRegionId = '';
  String geoDistrictId = '';
  String geoServiceAreaId = '';

  bool isSubmitting = false;
  String? errorMessage;

  bool isCheckingDevice = false;
  String? phoneStepError;

  bool get skipSmsVerification => otpVerified && _bindingRegistered;

  void setGender(String v) {
    gender = v;
    notifyListeners();
  }

  void setBirthDate(String v) {
    birthDate = v.trim();
    notifyListeners();
  }

  /// `DD.MM.YYYY` yoki eski `YYYY-MM-DD` — noto'g'ri/bo'sh bo'lsa `null`.
  /// (Umumiy [parseBirthDate] — `core/utils/formatters.dart`).
  static DateTime? parseBirthDate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    RegExpMatch? m =
        RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$').firstMatch(trimmed);
    int? y, mo, d;
    if (m != null) {
      d = int.tryParse(m.group(1)!);
      mo = int.tryParse(m.group(2)!);
      y = int.tryParse(m.group(3)!);
    } else {
      m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(trimmed);
      if (m == null) return null;
      y = int.tryParse(m.group(1)!);
      mo = int.tryParse(m.group(2)!);
      d = int.tryParse(m.group(3)!);
    }
    if (y == null || mo == null || d == null) return null;
    try {
      final parsed = DateTime(y, mo, d);
      if (parsed.year != y || parsed.month != mo || parsed.day != d) {
        return null;
      }
      return parsed;
    } catch (_) {
      return null;
    }
  }

  String? validate({
    required String name,
    required String phone,
  }) {
    if (name.trim().isEmpty) return 'ob_err_name';
    final d = phoneDigits(phone);
    if (d.length < 12) return 'ob_phone_required';
    if (birthDate.trim().isNotEmpty &&
        parseBirthDate(birthDate.trim()) == null) {
      return 'ob_birth_invalid_format';
    }
    return null;
  }

  /// Тил+туман экранида танланган зонани юклаш.
  Future<void> loadPreselectedGeo() async {
    final fromHolderRegion = ServiceConfigHolder.regionId.trim();
    final fromHolderDistrict = ServiceConfigHolder.districtId.trim();
    final fromHolderArea = ServiceConfigHolder.serviceAreaId.trim();
    if (fromHolderRegion.isNotEmpty && fromHolderDistrict.isNotEmpty) {
      geoRegionId = fromHolderRegion;
      geoDistrictId = fromHolderDistrict;
      geoServiceAreaId = fromHolderArea;
      notifyListeners();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    geoRegionId = (prefs.getString('pre_onboarding_region_id') ?? '').trim();
    geoDistrictId =
        (prefs.getString('pre_onboarding_district_id') ?? '').trim();
    geoServiceAreaId =
        (prefs.getString('pre_onboarding_service_area_id') ?? '').trim();
    if (geoRegionId.isNotEmpty && geoDistrictId.isNotEmpty) {
      try {
        await ServiceConfigHolder.applyGeo(
          regionId: geoRegionId,
          districtId: geoDistrictId,
          serviceAreaId: geoServiceAreaId,
        );
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<DeviceFingerprintSnapshot> _ensureFingerprint() async {
    _fingerprintSnapshot ??= await _fingerprintService.collect();
    return _fingerprintSnapshot!;
  }

  /// Тил экрани / онboarding очилишида фонда — кейинги CF кутмасin.
  void prefetchFingerprint() {
    unawaited(_ensureFingerprint());
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
      phoneStepError = 'ob_phone_required';
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
      lastBindingResult = result;

      switch (result.status) {
        case DeviceBindingStatus.trustedDevice:
          // Auth/token — createPhoneSession (bootstrap ekranida / fonda).
          otpVerified = true;
          _bindingRegistered = true;
          _deviceLockedUid = digits;
          phoneStepError = null;
          return true;

        case DeviceBindingStatus.needsVerification:
          // Pending-code оқими олиб ташланди — фақат fingerprint bind.
          phoneStepError = result.message ??
              'Қурилмани боғлаб бўлмади. Қайта уриниб кўринг.';
          return false;

        case DeviceBindingStatus.deviceBoundOtherPhone:
        case DeviceBindingStatus.phoneBoundOtherDevice:
        case DeviceBindingStatus.blocked:
          // UI conflict sheet ko‘rsatadi (self-serve / soft limit).
          phoneStepError = result.message;
          return false;

        case DeviceBindingStatus.unknown:
          phoneStepError = result.message ?? 'Noma\'lum xatolik. Qayta urinib ko\'ring.';
          return false;
      }
    } on FirebaseFunctionsException catch (e) {
      phoneStepError = firebaseFunctionsUserMessage(e);
      return false;
    } catch (e) {
      final raw = e.toString().toUpperCase();
      phoneStepError = raw.contains('DEADLINE_EXCEEDED')
          ? 'Сервер жавоб бермади. Бироздан кейин қайта уриниб кўринг.'
          : 'Хатолик: $e';
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

  Future<bool> _hasNetworkInterface() async {
    if (kIsWeb) return true;
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// Binding OK → Auth session (createUser/claims/token).
  /// `checkDeviceBinding` trusted жавобида `customToken` бўлса — 2-чи CF чақирилмайди.
  Future<bool> establishPhoneSession(String phone) async {
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      if (!await _requireValidFingerprintHash()) {
        errorMessage = phoneStepError ?? 'Қурилма аниқланмади';
        return false;
      }
      final cached = lastBindingResult?.customToken?.trim() ?? '';
      // Бир марта ишлатилади.
      if (cached.isNotEmpty && lastBindingResult != null) {
        lastBindingResult = DeviceBindingCheckResult(
          status: lastBindingResult!.status,
          message: lastBindingResult!.message,
          failedAttempts: lastBindingResult!.failedAttempts,
          selfServeAvailable: lastBindingResult!.selfServeAvailable,
          oldDeviceLabel: lastBindingResult!.oldDeviceLabel,
          selfServeHint: lastBindingResult!.selfServeHint,
          retryAfterMs: lastBindingResult!.retryAfterMs,
        );
      }
      if (cached.isNotEmpty) {
        try {
          await _signInWithPhoneCustomToken(cached);
          return true;
        } catch (_) {
          // Токен эскирган/яроқсиз бўлса — одатдаги йўлга қайтамиз.
        }
      }
      final token = await _deviceBindingRepo.createPhoneSession(
        phone: phone,
        snapshot: _fingerprintSnapshot!,
      );
      await _signInWithPhoneCustomToken(token);
      return true;
    } on FirebaseFunctionsException catch (e) {
      errorMessage = firebaseFunctionsUserMessage(e);
      return false;
    } catch (e) {
      final raw = e.toString().toUpperCase();
      errorMessage = raw.contains('DEADLINE_EXCEEDED')
          ? 'Сервер жавоб бермади. Бироздан кейин қайта уриниб кўринг.'
          : 'Хатолик: $e';
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<bool> persistLocalOnboardingPrefs({
    required String name,
    required String phone,
  }) async {
    if (geoRegionId.trim().isEmpty || geoDistrictId.trim().isEmpty) {
      await loadPreselectedGeo();
    }
    if (geoRegionId.trim().isEmpty || geoDistrictId.trim().isEmpty) {
      errorMessage = 'Xizmat zonasi — tumanni tanlang (til ekranida)';
      notifyListeners();
      return false;
    }

    final uid = canonicalPhoneId(phone);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId', uid);
    await prefs.setString('userName', name.trim());
    await prefs.setString('user_name', name.trim());
    unawaited(syncTvPublisherPublicName(name.trim(), phone: uid));
    await prefs.setString('user_phone', canonicalPhoneId(phone.trim()));
    await prefs.setString('user_gender', gender);
    if (birthDate.isNotEmpty) {
      await prefs.setString('user_birth_date', birthDate);
    }
    // `user_address` бу ерда ёзилмайди — онбордингда манзил йиғилмайди.
    // Аввал бўш манзилнинг `formatted`и (фақат туман номи) ёзиларди ва
    // Профилдаги манзил таҳририда «кўча» майдонига prefill бўлиб қоларди.
    await prefs.setBool('onboarding_done', true);
    await prefs.setBool('phone_reverified', true);
    _deviceLockedUid = uid;
    return true;
  }

  /// Home очилгандан кейин: profile ‖ zone ‖ FCM.
  Future<void> syncProfileZoneFcmInBackground({
    required String name,
    required String phone,
  }) async {
    final uid = canonicalPhoneId(phone);
    final regionId = geoRegionId;
    final districtId = geoDistrictId;
    final areaId = geoServiceAreaId;

    try {
      final writes = <Future<void>>[
        // Манзил онбордингда йиғилмайди — бўш `UserAddress` юборилади ва
        // repo уни ёзмайди (мавжуд манзил ўчиб кетмаслиги учун). Манзилни
        // фойдаланувчи Профилда (`AddressEditScreen`) киритади/таҳрирлайди.
        _userRepo.createOrMergeProfileWithAddress(
          uid: uid,
          phone: phone,
          name: name,
          gender: gender,
          birthDate: birthDate,
          legacyAddressLine: '',
          address: const UserAddress(),
          requireCompleteAddress: false,
        ),
      ];
      if (districtId.trim().isNotEmpty) {
        writes.add(
          _userRepo.saveServiceArea(
            uid: uid,
            regionId: regionId,
            districtId: districtId,
            serviceAreaId: areaId,
          ),
        );
      }
      await Future.wait(writes);
      if (districtId.trim().isNotEmpty) {
        try {
          await ServiceConfigHolder.applyGeo(
            regionId: regionId,
            districtId: districtId,
            serviceAreaId: areaId,
          );
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('onboarding bg profile/zone: $e');
    }

    try {
      await FCMService().refreshToken();
      FCMService().stopListeners();
      await FCMService().startListeners();
    } catch (_) {}
  }

  /// OTP йўли: сессия бор → prefs → Home; profile/zone/FCM фон.
  Future<bool> finish({
    required String name,
    required String phone,
  }) async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) {
      debugPrint('finish() blocked: no Firebase session');
      return false;
    }
    try {
      await firebaseUser.getIdToken(true);
    } catch (e) {
      debugPrint('finish() token refresh failed: $e');
    }

    isSubmitting = true;
    notifyListeners();
    try {
      final ok = await persistLocalOnboardingPrefs(name: name, phone: phone);
      if (!ok) return false;
      unawaited(syncProfileZoneFcmInBackground(name: name, phone: phone));
      return true;
    } catch (e) {
      if (e is ArgumentError) {
        errorMessage = e.message?.toString() ?? e.toString();
      } else {
        errorMessage = 'Хатолик: $e';
      }
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
