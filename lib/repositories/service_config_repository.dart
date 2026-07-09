import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/geo_area.dart';
import '../models/service_module_config.dart';

/// Konfiguratsiyaga asoslangan platforma — Firestore o'qish/yozish qatlami.
///
/// Kolleksiyalar:
///   - `config/module_defaults`         — global baseline modul holati
///   - `service_area_modules/{areaId}`  — MFY bo'yicha override
///   - `geo_regions` / `geo_districts` / `service_areas` — ierarxiya
class ServiceConfigRepository {
  ServiceConfigRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const String moduleDefaultsCollection = 'config';
  static const String moduleDefaultsDoc = 'module_defaults';
  static const String serviceAreaModulesCollection = 'service_area_modules';

  DocumentReference<Map<String, dynamic>> get _defaultsRef => _db
      .collection(moduleDefaultsCollection)
      .doc(moduleDefaultsDoc);

  DocumentReference<Map<String, dynamic>> _areaModulesRef(String areaId) =>
      _db.collection(serviceAreaModulesCollection).doc(areaId);

  /// Global baseline (`config/module_defaults`) + `enforce` bayrog'i.
  ///
  /// [enforce] = false (default) → gating O'CHIQ: barcha modul enabled deb
  /// qaraladi (ilova hozirgidek). Admin barcha user'lar zonaga ega bo'lgach
  /// `enforce=true` qilib config-driven rejimni yoqadi.
  Future<({ServiceModuleConfig config, bool enforce})>
      fetchModuleDefaults() async {
    try {
      final snap = await _defaultsRef.get();
      if (!snap.exists) {
        return (config: ServiceModuleConfig.empty, enforce: false);
      }
      final data = snap.data();
      return (
        config: ServiceModuleConfig.fromMap(data),
        enforce: data?['enforce'] as bool? ?? false,
      );
    } catch (e, st) {
      debugPrint('ServiceConfigRepository.fetchModuleDefaults: $e\n$st');
      return (config: ServiceModuleConfig.empty, enforce: false);
    }
  }

  /// MFY override (`service_area_modules/{areaId}`). Yo'q/bo'sh → [ServiceModuleConfig.empty].
  Future<ServiceModuleConfig> fetchServiceAreaModules(String areaId) async {
    if (areaId.trim().isEmpty) return ServiceModuleConfig.empty;
    try {
      final snap = await _areaModulesRef(areaId).get();
      return snap.exists
          ? ServiceModuleConfig.fromMap(snap.data())
          : ServiceModuleConfig.empty;
    } catch (e, st) {
      debugPrint('ServiceConfigRepository.fetchServiceAreaModules: $e\n$st');
      return ServiceModuleConfig.empty;
    }
  }

  /// Admin: global baseline'ni yozish. [enforce] berilsa — bayroq ham yoziladi.
  Future<void> setModuleDefaults(
    ServiceModuleConfig config, {
    bool? enforce,
    String? updatedBy,
  }) async {
    await _defaultsRef.set({
      ...config.toMap(),
      if (enforce != null) 'enforce': enforce,
      'updatedAt': FieldValue.serverTimestamp(),
      if (updatedBy != null) 'updatedBy': updatedBy,
    }, SetOptions(merge: true));
  }

  /// Admin: MFY override'ni yozish.
  Future<void> setServiceAreaModules(
    ServiceArea area,
    ServiceModuleConfig config, {
    String? updatedBy,
  }) async {
    await _areaModulesRef(area.id).set({
      'serviceAreaId': area.id,
      'districtId': area.districtId,
      'regionId': area.regionId,
      ...config.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (updatedBy != null) 'updatedBy': updatedBy,
    }, SetOptions(merge: true));
  }

  // ── Geografik ierarxiya (admin va onboarding kaskadi uchun) ──

  Future<List<GeoRegion>> fetchRegions({bool activeOnly = true}) async {
    try {
      Query<Map<String, dynamic>> q = _db.collection(GeoRegion.collection);
      if (activeOnly) q = q.where('active', isEqualTo: true);
      final snap = await q.get();
      final list = snap.docs.map(GeoRegion.fromDoc).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      return list;
    } catch (e, st) {
      debugPrint('ServiceConfigRepository.fetchRegions: $e\n$st');
      return const [];
    }
  }

  Future<List<GeoDistrict>> fetchDistricts(
    String regionId, {
    bool activeOnly = true,
  }) async {
    if (regionId.trim().isEmpty) return const [];
    try {
      Query<Map<String, dynamic>> q = _db
          .collection(GeoDistrict.collection)
          .where('regionId', isEqualTo: regionId);
      if (activeOnly) q = q.where('active', isEqualTo: true);
      final snap = await q.get();
      final list = snap.docs.map(GeoDistrict.fromDoc).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      return list;
    } catch (e, st) {
      debugPrint('ServiceConfigRepository.fetchDistricts: $e\n$st');
      return const [];
    }
  }

  Future<List<ServiceArea>> fetchServiceAreas(
    String districtId, {
    bool activeOnly = true,
  }) async {
    if (districtId.trim().isEmpty) return const [];
    try {
      Query<Map<String, dynamic>> q = _db
          .collection(ServiceArea.collection)
          .where('districtId', isEqualTo: districtId);
      if (activeOnly) q = q.where('active', isEqualTo: true);
      final snap = await q.get();
      final list = snap.docs.map(ServiceArea.fromDoc).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      return list;
    } catch (e, st) {
      debugPrint('ServiceConfigRepository.fetchServiceAreas: $e\n$st');
      return const [];
    }
  }

  /// Viloyat bo'yicha barcha xizmat zonalarini (MFY + markaz).
  Future<List<ServiceArea>> fetchServiceAreasForRegion(
    String regionId, {
    bool activeOnly = true,
  }) async {
    if (regionId.trim().isEmpty) return const [];
    try {
      Query<Map<String, dynamic>> q = _db
          .collection(ServiceArea.collection)
          .where('regionId', isEqualTo: regionId);
      if (activeOnly) q = q.where('active', isEqualTo: true);
      final snap = await q.get();
      final list = snap.docs.map(ServiceArea.fromDoc).toList()
        ..sort((a, b) {
          final d = a.districtId.compareTo(b.districtId);
          if (d != 0) return d;
          return a.order.compareTo(b.order);
        });
      return list;
    } catch (e, st) {
      debugPrint('ServiceConfigRepository.fetchServiceAreasForRegion: $e\n$st');
      return const [];
    }
  }

  /// Bir nechta zona uchun override'larni parallel yuklash.
  Future<Map<String, ServiceModuleConfig>> fetchAreaModulesBatch(
    Iterable<String> areaIds,
  ) async {
    final ids = areaIds.where((id) => id.trim().isNotEmpty).toSet();
    if (ids.isEmpty) return const {};
    final out = <String, ServiceModuleConfig>{};
    await Future.wait(ids.map((id) async {
      out[id] = await fetchServiceAreaModules(id);
    }));
    return out;
  }

  Future<ServiceArea?> fetchServiceArea(String areaId) async {
    if (areaId.trim().isEmpty) return null;
    try {
      final snap =
          await _db.collection(ServiceArea.collection).doc(areaId).get();
      return snap.exists ? ServiceArea.fromDoc(snap) : null;
    } catch (e, st) {
      debugPrint('ServiceConfigRepository.fetchServiceArea: $e\n$st');
      return null;
    }
  }
}
