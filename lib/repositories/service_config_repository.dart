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

  /// MFY override (`service_area_modules/{areaId}`).
  ///
  /// Faqat `manualModules` dagi kalitlar qaytariladi. Maydon yoʻq/boʻsh
  /// (eski seed) → boʻsh config — Baseline hukmron (seed appda koʻrinmasin).
  Future<ServiceModuleConfig> fetchServiceAreaModules(String areaId) async {
    final detailed = await fetchServiceAreaModulesDetailed(areaId);
    if (detailed.manualModules.isEmpty) {
      return ServiceModuleConfig.empty;
    }
    final filtered = <String, ModuleStatus>{
      for (final id in detailed.manualModules)
        if (detailed.config.modules.containsKey(id))
          id: detailed.config.modules[id]!,
    };
    return ServiceModuleConfig(filtered);
  }

  /// Override + qaysi modullar admin tomonidan qoʻlda belgilangan.
  ///
  /// `manualModules` maydoni yoʻq (eski seed) → boʻsh toʻplam: Baseline
  /// cascade barcha kalitlarni inherit qiladi.
  Future<
      ({
        ServiceModuleConfig config,
        Set<String> manualModules,
      })> fetchServiceAreaModulesDetailed(String areaId) async {
    if (areaId.trim().isEmpty) {
      return (config: ServiceModuleConfig.empty, manualModules: <String>{});
    }
    try {
      final snap = await _areaModulesRef(areaId).get();
      if (!snap.exists) {
        return (config: ServiceModuleConfig.empty, manualModules: <String>{});
      }
      final data = snap.data() ?? const <String, dynamic>{};
      final manualRaw = data['manualModules'];
      final manual = <String>{};
      if (manualRaw is Iterable) {
        for (final e in manualRaw) {
          final id = e.toString().trim();
          if (id.isNotEmpty) manual.add(id);
        }
      }
      return (
        config: ServiceModuleConfig.fromMap(data),
        manualModules: manual,
      );
    } catch (e, st) {
      debugPrint(
          'ServiceConfigRepository.fetchServiceAreaModulesDetailed: $e\n$st');
      return (config: ServiceModuleConfig.empty, manualModules: <String>{});
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
  ///
  /// `modules` va `manualModules` **toʻliq almashtiriladi** — inherit kalitlari
  /// oʻchadi; faqat [manualModules] dagi farqlar Baseline cascade dan himoyalanadi.
  Future<void> setServiceAreaModules(
    ServiceArea area,
    ServiceModuleConfig config, {
    Set<String> manualModules = const {},
    String? updatedBy,
  }) async {
    final manual = manualModules
        .where((id) => id.trim().isNotEmpty && config.modules.containsKey(id))
        .toList()
      ..sort();
    await _areaModulesRef(area.id).set({
      'serviceAreaId': area.id,
      'districtId': area.districtId,
      'regionId': area.regionId,
      'modules': {
        for (final e in config.modules.entries)
          e.key: {'status': e.value.wire},
      },
      'manualModules': manual,
      'updatedAt': FieldValue.serverTimestamp(),
      if (updatedBy != null) 'updatedBy': updatedBy,
    });
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
  Future<
      Map<
          String,
          ({
            ServiceModuleConfig config,
            Set<String> manualModules,
          })>> fetchAreaModulesBatch(
    Iterable<String> areaIds,
  ) async {
    final ids = areaIds.where((id) => id.trim().isNotEmpty).toSet();
    if (ids.isEmpty) return const {};
    final out = <String,
        ({
          ServiceModuleConfig config,
          Set<String> manualModules,
        })>{};
    await Future.wait(ids.map((id) async {
      out[id] = await fetchServiceAreaModulesDetailed(id);
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

  Future<GeoDistrict?> fetchDistrict(String districtId) async {
    if (districtId.trim().isEmpty) return null;
    try {
      final snap =
          await _db.collection(GeoDistrict.collection).doc(districtId).get();
      return snap.exists ? GeoDistrict.fromDoc(snap) : null;
    } catch (e, st) {
      debugPrint('ServiceConfigRepository.fetchDistrict: $e\n$st');
      return null;
    }
  }
}
