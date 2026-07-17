import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/service_module_config.dart';
import '../repositories/service_config_repository.dart';

/// Konfiguratsiyaga asoslangan modul mavjudligi — ilova bo'ylab yagona manba.
///
/// Yakuniy holat = `config/module_defaults` (global baseline)
///   ustiga `service_area_modules/{serviceAreaId}` (MFY override) qo'shiladi.
///
/// Buzilmaslik kafolati: hech qanday konfig hujjati bo'lmasa (yoki offline),
/// barcha ma'lum modullar `enabled` (ilova hozirgidek ishlaydi).
///
/// Ishlatish:
///   1. `main.dart` da Firebase init dan keyin `bootstrap()` (defaults + kesh).
///   2. User hujjati yuklangach `applyServiceArea(serviceAreaId)`.
class ServiceConfigHolder {
  ServiceConfigHolder._();

  static const _cacheKeyDefaults = 'svc_module_defaults';
  static const _cacheKeyArea = 'svc_area_modules';
  static const _cacheKeyAreaId = 'svc_area_id';
  static const _cacheKeyEnforce = 'svc_enforce';
  static const _cacheKeyRegionId = 'svc_region_id';
  static const _cacheKeyDistrictId = 'svc_district_id';

  /// Config o'zgarganda UI yangilanishi uchun (Home grid, resume).
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static void _notifyRevision() {
    revision.value++;
  }

  static final ServiceConfigRepository _repo = ServiceConfigRepository();

  static ServiceModuleConfig _defaults = ServiceModuleConfig.empty;
  static ServiceModuleConfig _areaOverride = ServiceModuleConfig.empty;
  static String _serviceAreaId = '';

  /// Hisobot denormalizatsiyasi uchun (order/trip hujjatlariga bosiladi).
  static String _regionId = '';
  static String _districtId = '';

  /// Gating yoqilganmi. `false` (default) → hamma modul enabled (hozirgi holat).
  static bool _enforce = false;

  static bool get enforced => _enforce;

  /// Barcha ma'lum modullar enabled — konfig umuman bo'lmagandagi tayanch.
  static final ServiceModuleConfig _fallback =
      ServiceModuleConfig.allEnabled(kKnownModuleIds);

  /// Joriy yakuniy konfig: fallback → defaults → area override.
  static ServiceModuleConfig get effective {
    final base = _defaults.modules.isEmpty ? _fallback : _defaults;
    return base.merge(_areaOverride);
  }

  /// Gating o'chiq bo'lsa — har doim [ModuleStatus.enabled] (regressiyasiz).
  static ModuleStatus statusOf(String moduleId) {
    if (!_enforce) return ModuleStatus.enabled;
    return effective.statusOf(moduleId, fallback: ModuleStatus.hidden);
  }

  static bool isVisible(String moduleId) => statusOf(moduleId).isVisible;
  static bool isOpenable(String moduleId) => statusOf(moduleId).isOpenable;

  static String get serviceAreaId => _serviceAreaId;
  static String get regionId => _regionId;
  static String get districtId => _districtId;

  /// Order/trip hujjatlariga bosiladigan hisobot muhri (faqat boʻsh emaslar).
  /// Xizmat mavjudligiga taʼsir qilmaydi — faqat hisobot/dashboard uchun.
  static Map<String, dynamic> reportStamp() => {
        if (_regionId.isNotEmpty) 'regionId': _regionId,
        if (_districtId.isNotEmpty) 'districtId': _districtId,
        if (_serviceAreaId.isNotEmpty) 'serviceAreaId': _serviceAreaId,
      };

  /// Faqat SharedPreferences keshidan tiklash — Firestore'siz, cold-start uchun tez.
  static Future<void> loadCacheOnly() async {
    await _loadFromCache();
    _notifyRevision();
  }

  /// Startda: keshdan tez tiklash + `config/module_defaults` ni yangilash.
  /// Kesh'da serviceAreaId bo'lsa (qaytgan foydalanuvchi) — override ham yangilanadi.
  static Future<void> bootstrap() async {
    await _loadFromCache();
    try {
      final res = await _repo.fetchModuleDefaults();
      _defaults = res.config;
      _enforce = res.enforce;
      await _saveDefaultsToCache();
    } catch (e, st) {
      debugPrint('ServiceConfigHolder.bootstrap: $e\n$st');
    }
    if (_serviceAreaId.isNotEmpty) {
      try {
        _areaOverride = await _repo.fetchServiceAreaModules(_serviceAreaId);
        await _saveAreaToCache();
      } catch (e, st) {
        debugPrint('ServiceConfigHolder.bootstrap(area): $e\n$st');
      }
    }
    _notifyRevision();
  }

  /// User serviceAreaId ma'lum bo'lgach — MFY override yuklash.
  /// region/district hisobot muhri uchun ServiceArea hujjatidan olinadi.
  static Future<void> applyServiceArea(String? serviceAreaId) async {
    final id = (serviceAreaId ?? '').trim();
    if (id.isEmpty) {
      _serviceAreaId = '';
      _regionId = '';
      _districtId = '';
      _areaOverride = ServiceModuleConfig.empty;
      await _saveAreaToCache();
      _notifyRevision();
      return;
    }
    _serviceAreaId = id;
    try {
      _areaOverride = await _repo.fetchServiceAreaModules(id);
      final area = await _repo.fetchServiceArea(id);
      if (area != null) {
        _regionId = area.regionId;
        _districtId = area.districtId;
      }
      await _saveAreaToCache();
    } catch (e, st) {
      debugPrint('ServiceConfigHolder.applyServiceArea: $e\n$st');
    }
    _notifyRevision();
  }

  /// region/district/area barchasi ma'lum bo'lganda (onboarding/manzil) —
  /// qo'shimcha fetch'siz to'g'ridan-to'g'ri qo'llash.
  static Future<void> applyGeo({
    required String regionId,
    required String districtId,
    required String serviceAreaId,
  }) async {
    final id = serviceAreaId.trim();
    _serviceAreaId = id;
    _regionId = regionId.trim();
    _districtId = districtId.trim();
    if (id.isEmpty) {
      _areaOverride = ServiceModuleConfig.empty;
    } else {
      try {
        _areaOverride = await _repo.fetchServiceAreaModules(id);
      } catch (e, st) {
        debugPrint('ServiceConfigHolder.applyGeo: $e\n$st');
      }
    }
    await _saveAreaToCache();
    _notifyRevision();
  }

  static Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _defaults = ServiceModuleConfig.fromCacheMap(
        _decode(prefs.getStringList(_cacheKeyDefaults)),
      );
      _areaOverride = ServiceModuleConfig.fromCacheMap(
        _decode(prefs.getStringList(_cacheKeyArea)),
      );
      _serviceAreaId = prefs.getString(_cacheKeyAreaId) ?? '';
      _regionId = prefs.getString(_cacheKeyRegionId) ?? '';
      _districtId = prefs.getString(_cacheKeyDistrictId) ?? '';
      _enforce = prefs.getBool(_cacheKeyEnforce) ?? false;
    } catch (_) {}
  }

  static Future<void> _saveDefaultsToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          _cacheKeyDefaults, _encode(_defaults.toCacheMap()));
      await prefs.setBool(_cacheKeyEnforce, _enforce);
    } catch (_) {}
  }

  static Future<void> _saveAreaToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          _cacheKeyArea, _encode(_areaOverride.toCacheMap()));
      await prefs.setString(_cacheKeyAreaId, _serviceAreaId);
      await prefs.setString(_cacheKeyRegionId, _regionId);
      await prefs.setString(_cacheKeyDistrictId, _districtId);
    } catch (_) {}
  }

  /// `moduleId → wire` xaritasini `["id=wire", ...]` sifatida saqlash.
  static List<String> _encode(Map<String, String> map) =>
      [for (final e in map.entries) '${e.key}=${e.value}'];

  static Map<String, String> _decode(List<String>? raw) {
    if (raw == null) return const {};
    final out = <String, String>{};
    for (final line in raw) {
      final i = line.indexOf('=');
      if (i <= 0) continue;
      out[line.substring(0, i)] = line.substring(i + 1);
    }
    return out;
  }

  @visibleForTesting
  static void setForTest({
    ServiceModuleConfig? defaults,
    ServiceModuleConfig? areaOverride,
    String serviceAreaId = '',
    String regionId = '',
    String districtId = '',
    bool enforce = false,
  }) {
    _defaults = defaults ?? ServiceModuleConfig.empty;
    _areaOverride = areaOverride ?? ServiceModuleConfig.empty;
    _serviceAreaId = serviceAreaId;
    _regionId = regionId;
    _districtId = districtId;
    _enforce = enforce;
  }

  @visibleForTesting
  static void resetForTest() {
    _defaults = ServiceModuleConfig.empty;
    _areaOverride = ServiceModuleConfig.empty;
    _serviceAreaId = '';
    _regionId = '';
    _districtId = '';
    _enforce = false;
  }
}
