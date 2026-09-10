import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/service_config_holder.dart';
import 'device_fingerprint_service.dart';

/// Guest (anonim) sessiya — "Value First → Registration When Needed".
///
/// `ensureAnonymousSession()` ikkala holatni ham qamraydi: birinchi marta
/// (hali hech qanday Firebase Auth sessiyasi yo'q) — `signInAnonymously()`
/// + `anon_sessions/{uid}` hujjatini yaratadi; keyingi ochilishlarda
/// (anonim sessiya allaqachon mavjud) — faqat `lastActiveAt`ni yangilaydi.
/// Telefon orqali ro'yxatdan o'tgan foydalanuvchiga tegmaydi.
///
/// `device_bindings`ga umuman yozilmaydi — fingerprint faqat shu hujjatda.
class AnonSessionService {
  AnonSessionService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    DeviceFingerprintService? fingerprintService,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _fingerprintService = fingerprintService ?? DeviceFingerprintService();

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final DeviceFingerprintService _fingerprintService;

  Future<void> ensureAnonymousSession() async {
    var user = _auth.currentUser;
    if (user == null) {
      try {
        final cred = await _auth.signInAnonymously();
        user = cred.user;
      } catch (e, st) {
        debugPrint('AnonSessionService.signInAnonymously: $e\n$st');
        return;
      }
    }
    if (user == null || !user.isAnonymous) return;

    try {
      final ref = _firestore.collection('anon_sessions').doc(user.uid);
      final snap = await ref.get();
      if (!snap.exists) {
        final fp = await _fingerprintService.collect();
        final geo = await _readPreselectedGeo();
        await ref.set({
          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
          'lastActiveAt': FieldValue.serverTimestamp(),
          'deviceFingerprintHash': fp.hash,
          'regionId': geo.regionId,
          'districtId': geo.districtId,
          'serviceAreaId': geo.serviceAreaId,
        });
      } else {
        await ref.set(
          {'lastActiveAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
      }
    } catch (e, st) {
      debugPrint('AnonSessionService.anon_sessions write: $e\n$st');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('anon_session_id', user.uid);
  }

  /// `OnboardingController.loadPreselectedGeo()` bilan bir xil tartib:
  /// avval `ServiceConfigHolder` statiklari, keyin `pre_onboarding_*` prefs.
  Future<PreselectedGeo> _readPreselectedGeo() async {
    final prefs = await SharedPreferences.getInstance();
    return resolvePreselectedGeo(
      holderRegionId: ServiceConfigHolder.regionId,
      holderDistrictId: ServiceConfigHolder.districtId,
      holderServiceAreaId: ServiceConfigHolder.serviceAreaId,
      prefsRegionId: prefs.getString('pre_onboarding_region_id') ?? '',
      prefsDistrictId: prefs.getString('pre_onboarding_district_id') ?? '',
      prefsServiceAreaId:
          prefs.getString('pre_onboarding_service_area_id') ?? '',
    );
  }
}

class PreselectedGeo {
  const PreselectedGeo(this.regionId, this.districtId, this.serviceAreaId);
  final String regionId;
  final String districtId;
  final String serviceAreaId;
}

/// Sof mantiq (Firebase/prefs'siz, testlanadigan): `ServiceConfigHolder`
/// statiklari to'liq bo'lsa ular, aks holda `pre_onboarding_*` prefs
/// qiymatlari ishlatiladi — xuddi `OnboardingController.loadPreselectedGeo()`
/// bilan bir xil tartib.
PreselectedGeo resolvePreselectedGeo({
  required String holderRegionId,
  required String holderDistrictId,
  required String holderServiceAreaId,
  required String prefsRegionId,
  required String prefsDistrictId,
  required String prefsServiceAreaId,
}) {
  final region = holderRegionId.trim();
  final district = holderDistrictId.trim();
  if (region.isNotEmpty && district.isNotEmpty) {
    return PreselectedGeo(region, district, holderServiceAreaId.trim());
  }
  return PreselectedGeo(
    prefsRegionId.trim(),
    prefsDistrictId.trim(),
    prefsServiceAreaId.trim(),
  );
}
