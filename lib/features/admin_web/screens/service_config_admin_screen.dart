import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/geo_area.dart';
import '../../../models/service_module_config.dart';
import '../../../repositories/service_config_repository.dart';
import '../../home/home_module_gate.dart';
import '../services/admin_auth_service.dart';

/// Admin — "Ҳудудлар ва хизматлар".
///
/// Matritsa ko'rinishi:
///   - Qatorlar: 17 ta xizmat moduli
///   - Ustunlar: tuman markazlari (default); tuman bosilsa MFY ustunlari ochiladi
///   - Yuqorida: global baseline + enforce kill-switch
///
///   1. Baseline GLOBAL
///   2. Tuman (Region Override) — `geo_district_modules`
///   3. MFY (ixtiyoriy) — `service_area_modules`
/// Runtime (APK): yangi modul hech qachon avtomatik ON.
class ServiceConfigAdminScreen extends StatefulWidget {
  const ServiceConfigAdminScreen({super.key});

  @override
  State<ServiceConfigAdminScreen> createState() =>
      _ServiceConfigAdminScreenState();
}

const Map<String, String> _moduleLabels = {
  'local_taxi': 'Mahalliy taksi',
  'intercity': 'Shaharlararo',
  'marshrut': 'Marshrutka',
  'yuk_birja': 'Yuk birjasi',
  'courier': 'Kuryer',
  'sell': 'Sotish',
  'food': 'Ovqat',
  'jobs': 'ИШ ЭЪЛОН',
  'cheap_products_home': 'Arzon bozor',
  'bread': 'Non',
  'carpet_wash': 'Gilam yuvish',
  'circles': 'Qarindoshlar',
  'dating': 'Tanishuv',
  'milk': 'Sut qabul',
  'tire': 'Avto shina',
  'car_wash': 'Avto yuvish',
  'oil_change': 'Moy almashtirish',
  'platform_store': 'AVA do\'koni',
  'tv_market': 'TV Market',
};

String _labelFor(String id) => _moduleLabels[id] ?? id;

/// Matritsa ustuni — bitta xizmat zonasi yoki global baseline.
class _MatrixColumn {
  const _MatrixColumn({
    this.area,
    this.district,
    this.isPrimary = false,
    this.isGlobal = false,
  });

  final ServiceArea? area;
  final GeoDistrict? district;

  /// Tuman yig'ilgan holatda Region Override ustuni.
  final bool isPrimary;

  /// Global baseline ustuni (birinchi ustun).
  final bool isGlobal;

  String get columnKey {
    if (isGlobal) return '__global__';
    if (isPrimary && district != null) return '__d:${district!.id}';
    return area!.id;
  }
}

class _ServiceConfigAdminScreenState extends State<ServiceConfigAdminScreen> {
  final ServiceConfigRepository _repo = ServiceConfigRepository();

  bool _loading = true;
  bool _savingGlobal = false;
  bool _savingMatrix = false;

  bool _enforce = false;
  bool _savedEnforce = false;
  final Map<String, ModuleStatus> _defaults = {};
  /// Oxirgi saqlangan baseline — cascade uchun (eski qiymat bilan solishtirish).
  final Map<String, ModuleStatus> _savedDefaults = {};

  static const String _regionId = 'xorazm';
  List<GeoDistrict> _districts = const [];
  List<ServiceArea> _allAreas = const [];
  final Set<String> _expandedDistricts = {};

  /// areaId → moduleId → override (null = inherit baseline).
  final Map<String, Map<String, ModuleStatus?>> _overrides = {};

  /// Saqlangan (server) holat — dirty tekshiruv uchun.
  final Map<String, Map<String, ModuleStatus?>> _savedOverrides = {};

  /// areaId → admin qoʻlda belgilagan modul ID lari (Baseline cascade dan himoya).
  final Map<String, Set<String>> _manualByArea = {};
  final Map<String, Set<String>> _savedManualByArea = {};

  /// districtId → moduleId → region override (null = inherit baseline).
  final Map<String, Map<String, ModuleStatus?>> _districtOverrides = {};
  final Map<String, Map<String, ModuleStatus?>> _savedDistrictOverrides = {};
  final Map<String, Set<String>> _manualByDistrict = {};
  final Map<String, Set<String>> _savedManualByDistrict = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final defaultsFuture = _repo.fetchModuleDefaults();
      final districtsFuture = _repo.fetchDistricts(_regionId);
      final areasFuture = _repo.fetchServiceAreasForRegion(_regionId);

      final defaultsRes = await defaultsFuture;
      final districts = await districtsFuture;
      final areas = await areasFuture;

      final areaIds = areas.map((a) => a.id).toList();
      final districtIds = districts.map((d) => d.id).toList();
      final batch = await _repo.fetchAreaModulesBatch(areaIds);
      final districtBatch = await _repo.fetchDistrictModulesBatch(districtIds);

      if (!mounted) return;

      final overrides = <String, Map<String, ModuleStatus?>>{};
      final saved = <String, Map<String, ModuleStatus?>>{};
      final manuals = <String, Set<String>>{};
      final savedManuals = <String, Set<String>>{};
      final staleSeedAreaIds = <String>[];
      for (final area in areas) {
        final packed = batch[area.id];
        final cfg = packed?.config ?? ServiceModuleConfig.empty;
        final manual = packed?.manualModules ?? <String>{};
        overrides[area.id] = {
          for (final id in kKnownModuleIds)
            id: manual.contains(id) ? cfg.modules[id] : null,
        };
        if (manual.isEmpty && cfg.modules.isNotEmpty) {
          staleSeedAreaIds.add(area.id);
        }
        saved[area.id] = Map<String, ModuleStatus?>.from(overrides[area.id]!);
        manuals[area.id] = Set<String>.from(manual);
        savedManuals[area.id] = Set<String>.from(manual);
      }

      final dOverrides = <String, Map<String, ModuleStatus?>>{};
      final dSaved = <String, Map<String, ModuleStatus?>>{};
      final dManuals = <String, Set<String>>{};
      final dSavedManuals = <String, Set<String>>{};
      final liftDistrictIds = <String>[];
      for (final d in districts) {
        final packed = districtBatch[d.id];
        var cfg = packed?.config ?? ServiceModuleConfig.empty;
        var manual = packed?.manualModules ?? <String>{};
        if (manual.isEmpty) {
          final primary = areas.where((a) => a.districtId == d.id).toList()
            ..sort((a, b) => a.order.compareTo(b.order));
          if (primary.isNotEmpty) {
            final fromArea = manuals[primary.first.id] ?? const <String>{};
            if (fromArea.isNotEmpty) {
              manual = Set<String>.from(fromArea);
              cfg = ServiceModuleConfig({
                for (final id in fromArea)
                  if (overrides[primary.first.id]?[id] != null)
                    id: overrides[primary.first.id]![id]!,
              });
              liftDistrictIds.add(d.id);
            }
          }
        }
        dOverrides[d.id] = {
          for (final id in kKnownModuleIds)
            id: manual.contains(id) ? cfg.modules[id] : null,
        };
        dSaved[d.id] = Map<String, ModuleStatus?>.from(dOverrides[d.id]!);
        dManuals[d.id] = Set<String>.from(manual);
        dSavedManuals[d.id] = Set<String>.from(manual);
      }

      setState(() {
        _enforce = defaultsRes.enforce;
        _savedEnforce = defaultsRes.enforce;
        _defaults
          ..clear()
          ..addEntries(kKnownModuleIds.map((id) => MapEntry(
                id,
                defaultsRes.config.statusOf(id, fallback: ModuleStatus.hidden),
              )));
        _savedDefaults
          ..clear()
          ..addAll(_defaults);
        _districts = districts;
        _allAreas = areas;
        _overrides
          ..clear()
          ..addAll(overrides);
        _savedOverrides
          ..clear()
          ..addAll(saved);
        _manualByArea
          ..clear()
          ..addAll(manuals);
        _savedManualByArea
          ..clear()
          ..addAll(savedManuals);
        _districtOverrides
          ..clear()
          ..addAll(dOverrides);
        _savedDistrictOverrides
          ..clear()
          ..addAll(dSaved);
        _manualByDistrict
          ..clear()
          ..addAll(dManuals);
        _savedManualByDistrict
          ..clear()
          ..addAll(dSavedManuals);
        _loading = false;
      });

      if (staleSeedAreaIds.isNotEmpty) {
        unawaited(_purgeStaleSeedOverrides(staleSeedAreaIds));
      }
      if (liftDistrictIds.isNotEmpty) {
        unawaited(_persistLiftedDistrictOverrides(liftDistrictIds));
      }
      unawaited(_syncMissingBaselineModules(
        defaultsRes.config,
        defaultsRes.enforce,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yuklash xatosi: $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// Eski seed override'larini fonda tozalash (UI ni bloklamaydi).
  Future<void> _purgeStaleSeedOverrides(List<String> areaIds) async {
    final by = _adminId();
    const chunk = 12;
    var n = 0;
    for (var i = 0; i < areaIds.length; i += chunk) {
      final slice = areaIds.sublist(
        i,
        i + chunk > areaIds.length ? areaIds.length : i + chunk,
      );
      final results = await Future.wait(slice.map((areaId) async {
        final area = _areaById[areaId];
        if (area == null) return false;
        try {
          await _repo
              .setServiceAreaModules(
                area,
                ServiceModuleConfig.empty,
                manualModules: const {},
                updatedBy: by,
              )
              .timeout(const Duration(seconds: 12));
          return true;
        } catch (_) {
          return false;
        }
      }));
      n += results.where((ok) => ok).length;
    }
    if (!mounted || n == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        'Eski zona override tozalandi ($n) — endi Baseline barcha tumanga tatbiq',
      ),
      backgroundColor: AppColors.button,
    ));
  }

  Future<void> _persistLiftedDistrictOverrides(List<String> districtIds) async {
    final by = _adminId();
    for (final id in districtIds) {
      final district = _districtById[id];
      if (district == null) continue;
      final manual = _manualByDistrict[id] ?? const <String>{};
      if (manual.isEmpty) continue;
      final cur = _districtOverrides[id] ?? const {};
      final overridden = <String, ModuleStatus>{
        for (final mid in manual)
          if (cur[mid] != null) mid: cur[mid]!,
      };
      try {
        await _repo.setDistrictModules(
          district,
          ServiceModuleConfig(overridden),
          manualModules: manual,
          updatedBy: by,
        );
      } catch (e) {
        debugPrint('[ServiceConfigAdmin] lift district $id: $e');
      }
    }
  }

  Map<String, GeoDistrict> get _districtById => {
        for (final d in _districts) d.id: d,
      };

  bool _isDistrictKey(String key) => key.startsWith('__d:');

  String? _districtIdFromKey(String key) =>
      _isDistrictKey(key) ? key.substring(4) : null;

  /// APK/admin янги модул қўшса — Baseline Global га автоматик ёзилади
  /// (`hidden`). Админ «Сақлаш» босмаса ҳам қоида жорий бўлади.
  Future<void> _syncMissingBaselineModules(
    ServiceModuleConfig remote,
    bool enforce,
  ) async {
    if (remote.modules.isEmpty) return;
    final missing = kKnownModuleIds
        .where((id) => !remote.modules.containsKey(id))
        .toList(growable: false);
    if (missing.isEmpty) return;
    final merged = <String, ModuleStatus>{
      ...remote.modules,
      for (final id in missing) id: ModuleStatus.hidden,
    };
    try {
      await _repo.setModuleDefaults(
        ServiceModuleConfig(merged),
        enforce: enforce,
        updatedBy: 'apk_module_sync',
      );
      if (!mounted) return;
      _savedDefaults
        ..clear()
        ..addAll(_defaults);
    } catch (e) {
      debugPrint('[ServiceConfigAdmin] baseline sync: $e');
    }
  }

  List<ServiceArea> _areasForDistrict(String districtId) =>
      _allAreas.where((a) => a.districtId == districtId).toList()
        ..sort((a, b) => a.order.compareTo(b.order));

  List<_MatrixColumn> get _visibleColumns {
    final cols = <_MatrixColumn>[
      const _MatrixColumn(isGlobal: true),
    ];
    for (final d in _districts) {
      final areas = _areasForDistrict(d.id);
      if (areas.isEmpty) continue;

      final expanded = _expandedDistricts.contains(d.id);
      final showAll = expanded && areas.length > 1;

      if (showAll) {
        for (final a in areas) {
          cols.add(_MatrixColumn(area: a, district: d));
        }
      } else {
        final primary = areas.first;
        cols.add(_MatrixColumn(area: primary, district: d, isPrimary: true));
      }
    }
    return cols;
  }

  ModuleStatus _effective(String columnKey, String moduleId) {
    if (columnKey == '__global__') {
      return _defaults[moduleId] ?? ModuleStatus.hidden;
    }
    if (_isDistrictKey(columnKey)) {
      final did = _districtIdFromKey(columnKey)!;
      return _districtOverrides[did]?[moduleId] ??
          _defaults[moduleId] ??
          ModuleStatus.hidden;
    }
    final ov = _overrides[columnKey]?[moduleId];
    if (ov != null) return ov;
    final area = _areaById[columnKey];
    if (area != null) {
      final dOv = _districtOverrides[area.districtId]?[moduleId];
      if (dOv != null) return dOv;
    }
    return _defaults[moduleId] ?? ModuleStatus.hidden;
  }

  bool _isInherited(String columnKey, String moduleId) {
    if (columnKey == '__global__') return false;
    if (_isDistrictKey(columnKey)) {
      final did = _districtIdFromKey(columnKey)!;
      return !(_manualByDistrict[did]?.contains(moduleId) ?? false);
    }
    return !(_manualByArea[columnKey]?.contains(moduleId) ?? false);
  }

  bool get _hasDirtyDefaults {
    if (_enforce != _savedEnforce) return true;
    for (final id in kKnownModuleIds) {
      if (_defaults[id] != _savedDefaults[id]) return true;
    }
    return false;
  }

  bool get _hasDirtyMatrix {
    for (final districtId in _districtOverrides.keys) {
      final cur = _districtOverrides[districtId] ?? const {};
      final saved = _savedDistrictOverrides[districtId] ?? const {};
      for (final id in kKnownModuleIds) {
        if (cur[id] != saved[id]) return true;
      }
      final curMan = _manualByDistrict[districtId] ?? const <String>{};
      final savedMan = _savedManualByDistrict[districtId] ?? const <String>{};
      if (curMan.length != savedMan.length || !curMan.containsAll(savedMan)) {
        return true;
      }
    }
    for (final areaId in _overrides.keys) {
      final cur = _overrides[areaId] ?? const {};
      final saved = _savedOverrides[areaId] ?? const {};
      for (final id in kKnownModuleIds) {
        if (cur[id] != saved[id]) return true;
      }
      final curMan = _manualByArea[areaId] ?? const <String>{};
      final savedMan = _savedManualByArea[areaId] ?? const <String>{};
      if (curMan.length != savedMan.length ||
          !curMan.containsAll(savedMan)) {
        return true;
      }
    }
    return false;
  }

  bool get _hasDirtyAny => _hasDirtyDefaults || _hasDirtyMatrix;

  void _toggleDistrict(String districtId) {
    setState(() {
      if (_expandedDistricts.contains(districtId)) {
        _expandedDistricts.remove(districtId);
      } else {
        _expandedDistricts.add(districtId);
      }
    });
  }

  Future<void> _saveGlobal() async {
    setState(() => _savingGlobal = true);
    final messenger = ScaffoldMessenger.of(context);
    final by = _adminId();
    final newDefaults = Map<String, ModuleStatus>.from(_defaults);
    try {
      // Faqat baseline — barcha zonani ketma-ket yozish UI ni osiltirardi.
      // Ilova allaqachon faqat manualModules override'ni oladi.
      await _repo
          .setModuleDefaults(
            ServiceModuleConfig(newDefaults),
            enforce: _enforce,
            updatedBy: by,
          )
          .timeout(const Duration(seconds: 20));

      for (final districtId in _districtOverrides.keys) {
        final manual = _manualByDistrict[districtId] ?? const <String>{};
        final cur = _districtOverrides[districtId] ?? {};
        _districtOverrides[districtId] = {
          for (final id in kKnownModuleIds)
            id: manual.contains(id) ? cur[id] : null,
        };
        _savedDistrictOverrides[districtId] =
            Map<String, ModuleStatus?>.from(_districtOverrides[districtId]!);
        _savedManualByDistrict[districtId] = Set<String>.from(manual);
      }

      // Local UI: no-manual kataklar inherit koʻrinsin.
      for (final areaId in _overrides.keys) {
        final manual = _manualByArea[areaId] ?? const <String>{};
        final cur = _overrides[areaId] ?? {};
        _overrides[areaId] = {
          for (final id in kKnownModuleIds)
            id: manual.contains(id) ? cur[id] : null,
        };
        _savedOverrides[areaId] =
            Map<String, ModuleStatus?>.from(_overrides[areaId]!);
        _savedManualByArea[areaId] = Set<String>.from(manual);
      }

      _savedDefaults
        ..clear()
        ..addAll(newDefaults);
      _savedEnforce = _enforce;

      if (mounted) setState(() {});
      messenger.showSnackBar(const SnackBar(
        content: Text('Global baseline saqlandi'),
        backgroundColor: AppColors.button,
      ));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Xatolik: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _savingGlobal = false);
    }
  }

  Future<void> _saveAll() async {
    if (!_hasDirtyAny) return;
    final hadDefaults = _hasDirtyDefaults;
    final hadMatrix = _hasDirtyMatrix;
    try {
      if (hadDefaults) {
        await _saveGlobal();
        if (!mounted) return;
      }
      if (hadMatrix && _hasDirtyMatrix) {
        await _saveMatrix();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Xatolik: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _saveMatrix() async {
    if (!_hasDirtyMatrix) return;
    setState(() => _savingMatrix = true);
    final messenger = ScaffoldMessenger.of(context);
    final by = _adminId();
    var saved = 0;
    try {
      for (final districtId in _districtOverrides.keys) {
        final cur = _districtOverrides[districtId] ?? const {};
        final prev = _savedDistrictOverrides[districtId] ?? const {};
        final curMan = _manualByDistrict[districtId] ?? const <String>{};
        final savedMan = _savedManualByDistrict[districtId] ?? const <String>{};
        var dirty = curMan.length != savedMan.length ||
            !curMan.containsAll(savedMan);
        if (!dirty) {
          for (final id in kKnownModuleIds) {
            if (cur[id] != prev[id]) {
              dirty = true;
              break;
            }
          }
        }
        if (!dirty) continue;
        final district = _districtById[districtId];
        if (district == null) continue;
        final manual = Set<String>.from(curMan);
        final overridden = <String, ModuleStatus>{
          for (final id in manual)
            if (cur[id] != null) id: cur[id]!,
        };
        await _repo.setDistrictModules(
          district,
          ServiceModuleConfig(overridden),
          manualModules: manual,
          updatedBy: by,
        );
        _districtOverrides[districtId] = {
          for (final id in kKnownModuleIds)
            id: manual.contains(id) ? cur[id] : null,
        };
        _savedDistrictOverrides[districtId] =
            Map<String, ModuleStatus?>.from(_districtOverrides[districtId]!);
        _manualByDistrict[districtId] = manual;
        _savedManualByDistrict[districtId] = Set<String>.from(manual);
        saved++;
      }
      for (final areaId in _overrides.keys) {
        final cur = _overrides[areaId] ?? const {};
        final prev = _savedOverrides[areaId] ?? const {};
        final curMan = _manualByArea[areaId] ?? const <String>{};
        final savedMan = _savedManualByArea[areaId] ?? const <String>{};
        var dirty = curMan.length != savedMan.length ||
            !curMan.containsAll(savedMan);
        if (!dirty) {
          for (final id in kKnownModuleIds) {
            if (cur[id] != prev[id]) {
              dirty = true;
              break;
            }
          }
        }
        if (!dirty) continue;

        final area = _areaById[areaId];
        if (area == null) continue;

        final manual = Set<String>.from(curMan);
        final overridden = <String, ModuleStatus>{
          for (final id in manual)
            if (cur[id] != null) id: cur[id]!,
        };
        await _repo.setServiceAreaModules(
          area,
          ServiceModuleConfig(overridden),
          manualModules: manual,
          updatedBy: by,
        );
        _overrides[areaId] = {
          for (final id in kKnownModuleIds)
            id: manual.contains(id) ? cur[id] : null,
        };
        _savedOverrides[areaId] =
            Map<String, ModuleStatus?>.from(_overrides[areaId]!);
        _manualByArea[areaId] = manual;
        _savedManualByArea[areaId] = Set<String>.from(manual);
        saved++;
      }
      messenger.showSnackBar(SnackBar(
        content: Text('$saved ta tuman/zona saqlandi'),
        backgroundColor: AppColors.button,
      ));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Xatolik: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _savingMatrix = false);
    }
  }

  void _setCell(String columnKey, String moduleId, ModuleStatus? status) {
    if (columnKey == '__global__') {
      if (status == null) return;
      setState(() => _defaults[moduleId] = status);
      return;
    }
    if (_isDistrictKey(columnKey)) {
      final did = _districtIdFromKey(columnKey)!;
      setState(() {
        _districtOverrides.putIfAbsent(did, () => {});
        _manualByDistrict.putIfAbsent(did, () => <String>{});
        if (status == null) {
          _districtOverrides[did]![moduleId] = null;
          _manualByDistrict[did]!.remove(moduleId);
        } else {
          _districtOverrides[did]![moduleId] = status;
          _manualByDistrict[did]!.add(moduleId);
        }
      });
      return;
    }
    setState(() {
      _overrides.putIfAbsent(columnKey, () => {});
      _manualByArea.putIfAbsent(columnKey, () => <String>{});
      if (status == null) {
        _overrides[columnKey]![moduleId] = null;
        _manualByArea[columnKey]!.remove(moduleId);
      } else {
        _overrides[columnKey]![moduleId] = status;
        _manualByArea[columnKey]!.add(moduleId);
      }
    });
  }

  Map<String, ServiceArea> get _areaById => {
        for (final a in _allAreas) a.id: a,
      };

  String _adminId() =>
      context.read<AdminAuthService>().phoneDigits ??
      context.read<AdminAuthService>().phone ??
      'unknown';

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final columns = _visibleColumns;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ҳудудлар ва хизматлар',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        if (columns.isNotEmpty)
                          Text(
                            '${kKnownModuleIds.length} xizmat · Baseline GLOBAL → tuman override → APK gate',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade700),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: 320, child: _enforceBar()),
                ],
              ),
            ],
          ),
        ),
        if (columns.isEmpty)
          const Expanded(
            child: Center(
                child: Text('Zonalar topilmadi — seed skriptni ishga tushiring')),
          )
        else
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LayoutBuilder(
                    builder: (context, constraints) =>
                        _buildFillMatrix(columns, constraints),
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: (_savingMatrix || _savingGlobal || !_hasDirtyAny)
                    ? null
                    : _saveAll,
                icon: (_savingMatrix || _savingGlobal)
                    ? const _Spinner()
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(
                  !_hasDirtyAny
                      ? 'Oʻzgarish yoʻq'
                      : _hasDirtyDefaults && _hasDirtyMatrix
                          ? 'Baseline + zonalarni saqlash'
                          : _hasDirtyDefaults
                              ? 'Baseline saqlash'
                              : 'Zonalarni saqlash',
                ),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
              ),
              ..._legendChips(),
            ],
          ),
        ),
      ],
    );
  }

  bool get _isCollapsedView => _expandedDistricts.isEmpty;

  /// Matritsa — mavjud ekranni to'ldiradi; kerak bo'lsa scroll.
  Widget _buildFillMatrix(
    List<_MatrixColumn> columns,
    BoxConstraints constraints,
  ) {
    const labelW = 118.0;
    const minCellW = 36.0;
    const minCellH = 24.0;
    final collapsed = _isCollapsedView;
    final districtHeaderH = collapsed ? 46.0 : 36.0;
    final zoneHeaderH = collapsed ? 0.0 : 40.0;
    final headerTotal = districtHeaderH + zoneHeaderH + 1;

    final colCount = columns.length;
    final dataW = constraints.maxWidth - labelW;
    final dataH = constraints.maxHeight - headerTotal;

    final fillWidth = colCount > 0 && colCount * minCellW <= dataW;
    final fillHeight =
        kKnownModuleIds.length * minCellH <= dataH && dataH > 0;

    final cellW = fillWidth && colCount > 0 ? dataW / colCount : minCellW;
    final cellH = fillHeight && kKnownModuleIds.isNotEmpty
        ? dataH / kKnownModuleIds.length
        : minCellH;
    final headerFont = (cellW * 0.22).clamp(8.0, 11.0);
    final rowFont = (cellH * 0.36).clamp(9.0, 12.0);
    final matrixW = fillWidth ? constraints.maxWidth : labelW + colCount * cellW;
    final matrixH = fillHeight
        ? constraints.maxHeight
        : headerTotal + kKnownModuleIds.length * cellH;

    final table = SizedBox(
      width: matrixW,
      height: matrixH,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: districtHeaderH,
            child: collapsed
                ? _combinedHeaderRow(
                    columns: columns,
                    labelW: labelW,
                    cellW: cellW,
                    fontSize: headerFont,
                    fillWidth: fillWidth,
                  )
                : _districtHeaderRow(
                    columns: columns,
                    labelW: labelW,
                    cellW: cellW,
                    fontSize: headerFont,
                    fillWidth: fillWidth,
                  ),
          ),
          if (!collapsed)
            SizedBox(
              height: zoneHeaderH,
              child: _zoneHeaderRow(
                columns: columns,
                labelW: labelW,
                cellW: cellW,
                fontSize: headerFont,
                fillWidth: fillWidth,
              ),
            ),
          Divider(height: 1, color: Colors.grey.shade300),
          if (fillHeight)
            Expanded(
              child: Column(
                children: [
                  for (final moduleId in kKnownModuleIds)
                    Expanded(
                      child: _moduleRow(
                        moduleId: moduleId,
                        columns: columns,
                        labelW: labelW,
                        cellW: cellW,
                        fontSize: rowFont,
                        fillWidth: fillWidth,
                      ),
                    ),
                ],
              ),
            )
          else
            for (final moduleId in kKnownModuleIds)
              _moduleRow(
                moduleId: moduleId,
                columns: columns,
                labelW: labelW,
                cellW: cellW,
                cellH: cellH,
                fontSize: rowFont,
                fillWidth: fillWidth,
              ),
        ],
      ),
    );

    if (fillWidth && fillHeight) return table;

    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: table,
        ),
      ),
    );
  }

  /// Yig'ilgan ko'rinish: bitta qator — tuman + zona (qisqartirmasdan FittedBox).
  Widget _combinedHeaderRow({
    required List<_MatrixColumn> columns,
    required double labelW,
    required double cellW,
    required double fontSize,
    required bool fillWidth,
  }) {
    Widget cell(_MatrixColumn col) {
      if (col.isGlobal) {
        return _headerCell(
          title: 'Baseline',
          subtitle: 'GLOBAL',
          fontSize: fontSize,
          bg: Colors.blue.shade50,
          titleColor: Colors.blue.shade800,
          fillWidth: fillWidth,
          cellW: cellW,
        );
      }
      final d = col.district!;
      final areas = _areasForDistrict(d.id);
      final canExpand = areas.length > 1;
      final expanded = _expandedDistricts.contains(d.id);
      return InkWell(
        onTap: canExpand ? () => _toggleDistrict(d.id) : null,
        child: _headerCell(
          title: _districtDisplayName(d.displayName),
          subtitle: col.isPrimary
              ? (canExpand ? 'override · ${areas.length} zona' : 'region override')
              : _zoneDisplayName(col.area!.displayName, d.displayName),
          fontSize: fontSize,
          bg: expanded
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.grey.shade50,
          titleColor:
              canExpand ? AppColors.primaryDark : Colors.black87,
          underline: canExpand,
          fillWidth: fillWidth,
          cellW: cellW,
        ),
      );
    }

    final dataCells = fillWidth
        ? Expanded(
            child: Row(
              children: [
                for (final col in columns)
                  Expanded(child: cell(col)),
              ],
            ),
          )
        : Row(
            children: [
              for (final col in columns)
                SizedBox(width: cellW, child: cell(col)),
            ],
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: labelW,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _fitText(
                'Xizmat / hudud',
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
                maxLines: 2,
                align: TextAlign.left,
              ),
            ),
          ),
        ),
        dataCells,
      ],
    );
  }

  Widget _headerCell({
    required String title,
    required String subtitle,
    required double fontSize,
    required Color bg,
    required Color titleColor,
    required bool fillWidth,
    double? cellW,
    bool underline = false,
  }) {
    final child = Container(
      width: fillWidth ? null : cellW,
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          right: BorderSide(color: Colors.grey.shade300),
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _fitText(
            title,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: titleColor,
            decoration: underline ? TextDecoration.underline : null,
            maxLines: 2,
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 1),
            _fitText(
              subtitle,
              fontSize: fontSize - 1,
              color: Colors.grey.shade600,
              maxLines: 1,
            ),
          ],
        ],
      ),
    );
    return child;
  }

  /// Matn sig'masa kichraytiradi, lekin qisqartirmaydi (ellipsis yo'q).
  Widget _fitText(
    String text, {
    required double fontSize,
    FontWeight fontWeight = FontWeight.normal,
    FontStyle fontStyle = FontStyle.normal,
    Color? color,
    int maxLines = 2,
    TextAlign align = TextAlign.center,
    TextDecoration? decoration,
  }) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: align == TextAlign.left
          ? Alignment.centerLeft
          : Alignment.center,
      child: Text(
        text,
        textAlign: align,
        maxLines: maxLines,
        overflow: TextOverflow.visible,
        softWrap: true,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          color: color ?? Colors.black87,
          decoration: decoration,
          height: 1.1,
        ),
      ),
    );
  }

  Widget _enforceBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _enforce ? Colors.orange.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _enforce ? Colors.orange.shade300 : Colors.grey.shade300,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text(
                'Config-driven rejim (enforce)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _enforce
                    ? 'YOQILGAN — faqat yoqilgan modullar ochiladi'
                    : 'OʻCHIQ — barcha modul ochiladi',
                style: const TextStyle(fontSize: 11),
              ),
              value: _enforce,
              activeThumbColor: AppColors.primary,
              onChanged:
                  _savingGlobal ? null : (v) => setState(() => _enforce = v),
            ),
          ),
          FilledButton.icon(
            onPressed: _savingGlobal || !_hasDirtyDefaults ? null : _saveGlobal,
            icon: _savingGlobal
                ? const _Spinner()
                : const Icon(Icons.tune, size: 16),
            label: Text(_hasDirtyDefaults ? 'Baseline*' : 'Baseline'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _districtHeaderRow({
    required List<_MatrixColumn> columns,
    required double labelW,
    required double cellW,
    required double fontSize,
    required bool fillWidth,
  }) {
    final spans = <_DistrictSpan>[];
    var i = columns.isNotEmpty && columns.first.isGlobal ? 1 : 0;
    if (i < columns.length) {
      String? curDistrictId;
      var start = i;
      for (; i < columns.length; i++) {
        final col = columns[i];
        if (col.isGlobal) continue;
        final dId = col.district!.id;
        if (curDistrictId != null && dId != curDistrictId) {
          spans.add(_DistrictSpan(
            district: columns[start].district!,
            count: i - start,
          ));
          start = i;
        }
        curDistrictId = dId;
      }
      if (start < columns.length && !columns[start].isGlobal) {
        spans.add(_DistrictSpan(
          district: columns[start].district!,
          count: columns.length - start,
        ));
      }
    }

    Widget dataCells;
    if (fillWidth) {
      dataCells = Expanded(
        child: Row(
          children: [
            if (columns.isNotEmpty && columns.first.isGlobal)
              Expanded(
                child: _headerCell(
                  title: 'GLOBAL',
                  subtitle: '',
                  fontSize: fontSize,
                  bg: Colors.blue.shade50,
                  titleColor: Colors.blue.shade800,
                  fillWidth: true,
                ),
              ),
            for (final span in spans)
              Expanded(
                flex: span.count,
                child: _districtHeaderCell(
                  span,
                  fontSize: fontSize,
                  fillWidth: true,
                ),
              ),
          ],
        ),
      );
    } else {
      dataCells = Row(
        children: [
          if (columns.isNotEmpty && columns.first.isGlobal)
            _headerCell(
              title: 'GLOBAL',
              subtitle: '',
              fontSize: fontSize,
              bg: Colors.blue.shade50,
              titleColor: Colors.blue.shade800,
              fillWidth: false,
              cellW: cellW,
            ),
          for (final span in spans)
            _districtHeaderCell(
              span,
              fontSize: fontSize,
              fillWidth: false,
              cellW: cellW * span.count,
            ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: labelW,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _fitText(
                'Tuman',
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
                align: TextAlign.left,
              ),
            ),
          ),
        ),
        dataCells,
      ],
    );
  }

  Widget _districtHeaderCell(
    _DistrictSpan span, {
    required double fontSize,
    double? cellW,
    bool fillWidth = false,
  }) {
    final d = span.district;
    final areas = _areasForDistrict(d.id);
    final canExpand = areas.length > 1;
    final expanded = _expandedDistricts.contains(d.id);

    return InkWell(
      onTap: canExpand ? () => _toggleDistrict(d.id) : null,
      child: _headerCell(
        title: _districtDisplayName(d.displayName),
        subtitle: canExpand && !expanded ? '${areas.length} zona' : '',
        fontSize: fontSize,
        bg: expanded
            ? AppColors.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        titleColor: canExpand ? AppColors.primaryDark : Colors.black87,
        underline: canExpand,
        fillWidth: fillWidth,
        cellW: cellW,
      ),
    );
  }

  Widget _zoneHeaderRow({
    required List<_MatrixColumn> columns,
    required double labelW,
    required double cellW,
    required double fontSize,
    required bool fillWidth,
  }) {
    Widget dataCells;
    if (fillWidth) {
      dataCells = Expanded(
        child: Row(
          children: [
            for (final col in columns)
              Expanded(child: _zoneHeaderCell(col, fontSize, fillWidth: true)),
          ],
        ),
      );
    } else {
      dataCells = Row(
        children: [
          for (final col in columns)
            _zoneHeaderCell(col, fontSize, cellW: cellW),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: labelW,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _fitText(
                'MFY / zona',
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
                align: TextAlign.left,
              ),
            ),
          ),
        ),
        dataCells,
      ],
    );
  }

  Widget _zoneHeaderCell(
    _MatrixColumn col,
    double fontSize, {
    double? cellW,
    bool fillWidth = false,
  }) {
    final decoration = BoxDecoration(
      color: col.isGlobal
          ? Colors.blue.shade50
          : (col.isPrimary ? Colors.grey.shade50 : null),
      border: Border(
        right: BorderSide(color: Colors.grey.shade200),
        bottom: BorderSide(color: Colors.grey.shade200),
      ),
    );

    final label = col.isGlobal
        ? 'Baseline'
        : _zoneDisplayName(col.area!.displayName, col.district!.displayName);

    final child = Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: decoration,
      child: _fitText(
        label,
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: col.isGlobal ? Colors.blue.shade800 : Colors.black87,
        maxLines: 3,
      ),
    );

    if (fillWidth) return child;
    return SizedBox(width: cellW, child: child);
  }

  Widget _moduleRow({
    required String moduleId,
    required List<_MatrixColumn> columns,
    required double labelW,
    required double cellW,
    required double fontSize,
    required bool fillWidth,
    double? cellH,
  }) {
    Widget dataCells;
    if (fillWidth) {
      dataCells = Expanded(
        child: Row(
          children: [
            for (final col in columns)
              Expanded(
                child: _matrixCell(
                  areaId: col.columnKey,
                  moduleId: moduleId,
                  fontSize: fontSize,
                  isGlobal: col.isGlobal,
                  expand: true,
                ),
              ),
          ],
        ),
      );
    } else {
      dataCells = Row(
        children: [
          for (final col in columns)
            _matrixCell(
              areaId: col.columnKey,
              moduleId: moduleId,
              cellW: cellW,
              fontSize: fontSize,
              isGlobal: col.isGlobal,
            ),
        ],
      );
    }

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: labelW,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 6, right: 2),
              child: _fitText(
                _labelFor(moduleId),
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
                maxLines: 2,
                align: TextAlign.left,
              ),
            ),
          ),
        ),
        dataCells,
      ],
    );

    if (cellH != null) return SizedBox(height: cellH, child: row);
    return row;
  }

  Widget _matrixCell({
    required String areaId,
    required String moduleId,
    required double fontSize,
    double? cellW,
    bool isGlobal = false,
    bool expand = false,
  }) {
    final status = _effective(areaId, moduleId);
    final inherited = _isInherited(areaId, moduleId);
    final color = _statusColor(status);

    final child = InkWell(
      onTap: () => _showCellMenu(areaId, moduleId, isGlobal: isGlobal),
      child: Container(
        width: expand ? null : cellW,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isGlobal
              ? Colors.blue.shade50.withValues(alpha: 0.5)
              : color.withValues(alpha: inherited ? 0.06 : 0.14),
          border: Border(
            right: BorderSide(color: Colors.grey.shade200),
            bottom: BorderSide(color: Colors.grey.shade100),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: _fitText(
            _statusLabel(status),
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            fontStyle: inherited ? FontStyle.italic : FontStyle.normal,
            color: color,
            maxLines: 2,
          ),
        ),
      ),
    );

    return child;
  }

  Future<void> _showCellMenu(
    String areaId,
    String moduleId, {
    bool isGlobal = false,
  }) async {
    final districtId = _districtIdFromKey(areaId);
    ModuleStatus? current;
    if (isGlobal) {
      current = _defaults[moduleId];
    } else if (districtId != null) {
      current = _districtOverrides[districtId]?[moduleId];
    } else {
      current = _overrides[areaId]?[moduleId];
    }

    // Bu ikkitasi hali real ekranga ega emas — ilova ularni har doim
    // "Ҳамкорлик" sifatida ko'rsatadi (`HomeModuleGate.placeholderModuleIds`).
    // "Очиқ" tanlansa ham iloviada hech narsa ochilmaydi — chalg'itmaslik
    // uchun bu variant picker'dan olib tashlanadi.
    final isPlaceholder = HomeModuleGate.placeholderModuleIds.contains(moduleId);

    final picked = await showDialog<ModuleStatus?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(_labelFor(moduleId)),
        children: [
          if (isPlaceholder)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              child: Text(
                'Бу модул иловада ҳали ишламайди — фақат Ёпиқ/Ҳамкорлик '
                'кўринишига таъсир қилади.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          if (!isGlobal)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text(_isDistrictKey(areaId)
                  ? 'Global baseline (inherit)'
                  : 'Tuman / baseline (inherit)'),
            ),
          for (final s in ModuleStatus.values)
            if (!isPlaceholder || s != ModuleStatus.enabled)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, s),
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 10, color: _statusColor(s)),
                    const SizedBox(width: 8),
                    Text(_statusLabel(s)),
                  ],
                ),
              ),
        ],
      ),
    );
    if (picked == current) return;
    if (!mounted) return;
    _setCell(areaId, moduleId, picked);
  }

  List<Widget> _legendChips() => [
        _legend('Очиқ', Colors.green),
        _legend('Ҳамкорлик', Colors.orange),
        _legend('Ёпиқ', Colors.grey),
        Text(
          'kursiv = inherit · GLOBAL = baseline · tuman katak = region override',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ];

  Widget _legend(String label, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: color,
                  fontSize: 11)),
        ],
      );

  static String _districtDisplayName(String name) => name
      .replaceAll(' tumani', '')
      .replaceAll(' тумани', '')
      .replaceAll(' shahri', ' sh.')
      .replaceAll(' шаҳри', ' sh.')
      .trim();

  static String _zoneDisplayName(String zoneName, String districtName) {
    var s = zoneName
        .replaceAll(' — марказ', '')
        .replaceAll(' — markaz', '')
        .trim();
    final d = _districtDisplayName(districtName);
    if (s.isEmpty) return 'марказ';
    // MFY nomi to'liq — faqat keraksiz takrorni olib tashlaymiz.
    if (s.toLowerCase().startsWith(d.toLowerCase())) {
      s = s.substring(d.length).trim();
    }
    return s.isEmpty ? 'марказ' : s;
  }

  static String _statusLabel(ModuleStatus s) => switch (s) {
        ModuleStatus.enabled => 'Очиқ',
        ModuleStatus.comingSoon => 'Ҳамкорлик',
        ModuleStatus.hidden => 'Ёпиқ',
      };

  static Color _statusColor(ModuleStatus s) => switch (s) {
        ModuleStatus.enabled => Colors.green.shade700,
        ModuleStatus.comingSoon => Colors.orange.shade800,
        ModuleStatus.hidden => Colors.grey.shade600,
      };
}

class _DistrictSpan {
  const _DistrictSpan({required this.district, required this.count});
  final GeoDistrict district;
  final int count;
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
  }
}
