import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/geo_area.dart';
import '../../../models/service_module_config.dart';
import '../../../repositories/service_config_repository.dart';
import '../../home/home_module_gate.dart';
import '../utils/module_config_changes.dart';

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
  const ServiceConfigAdminScreen({super.key, this.repository});

  /// Тест учун алмаштирилади; бўш бўлса ҳақиқий репозиторий.
  final ServiceConfigRepository? repository;

  @override
  State<ServiceConfigAdminScreen> createState() =>
      _ServiceConfigAdminScreenState();
}

const Map<String, String> _moduleLabels = {
  'local_taxi': 'Mahalliy taksi',
  'intercity': 'Shaharlararo',
  'marshrut': 'Marshrutka',
  'yuk_local': 'Yuk: tuman ichida',
  'yuk_intercity': 'Yuk: shaharlararo',
  'courier': 'Kuryer',
  'jobs': 'Эълонлар ва хизматлар',
  'cheap_products_home': 'Aholi bozori',
  'bread': 'Non',
  'carpet_wash': 'Gilam yuvish',
  'circles': 'Qarindoshlar',
  'dating': 'Tanishuv',
  'milk': 'Sut qabul',
  'tire': 'Avto shina',
  'car_wash': 'Avto yuvish',
  'oil_change': 'Moy almashtirish',
  'tv_market': 'AVAGram',
  'chatgpt': 'AVA ёрдамчиси',
  'ev_charging': 'EV zaryadlash',
  'pay_click': 'Click',
  'pay_payme': 'Payme',
  'pay_paynet': 'Paynet',
  'wholesale_market': 'Улгуржи бозор',
  'china_market': 'Хитой бозори',
  'realty': 'Кўчмас мулк кластери',
  'logistics': 'AVA Logistics (жўнатма)',
  'demand_intent': 'Уста чақириш (қидирувдан сўров)',
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
  late final ServiceConfigRepository _repo = widget.repository ?? ServiceConfigRepository();

  /// Матрица қаторлари тепа-пастга тортилади; сарлавҳа қатори тепада қолади (эга, 2026-10-19).
  final ScrollController _matrixVScroll = ScrollController();
  final ScrollController _matrixHScroll = ScrollController();

  @override
  void dispose() {
    _matrixVScroll.dispose();
    _matrixHScroll.dispose();
    super.dispose();
  }

  bool _loading = true;
  bool _savingGlobal = false;
  bool _savingMatrix = false;

  bool _enforce = false;
  bool _savedEnforce = false;
  final Map<String, ModuleStatus> _defaults = {};
  /// Oxirgi saqlangan baseline — cascade uchun (eski qiymat bilan solishtirish).
  final Map<String, ModuleStatus> _savedDefaults = {};

  /// Serverdagi `config/module_defaults`da YO'Q modullar (ekranda `hidden`
  /// ko'rinadi). Saqlashda ularning `from`i — `null`: server shu bilan
  /// solishtiradi.
  final Set<String> _absentDefaults = {};

  /// Geo seed bo'lmaganda (yoki region o'chirilganda) tayanch viloyat.
  static const String _fallbackRegionId = 'xorazm';

  String _regionId = _fallbackRegionId;
  List<GeoRegion> _regions = const [];
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
      final regionsFuture = _repo.fetchRegions();

      final defaultsRes = await defaultsFuture;
      final regions = await regionsFuture;
      final regionId = _resolveRegionId(regions);

      final districtsFuture = _repo.fetchDistricts(regionId);
      final areasFuture = _repo.fetchServiceAreasForRegion(regionId);

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
      // Аввал бу ерда «эски seed override'ни тозалаш» бор эди (`manualModules`
      // бўш, `modules` тўла МФЙ ҳужжатини клиент ўзи бўшатарди). 2026-10-08
      // да production'да бундай ҳужжат 0/61, илова уларни барибир ўқимайди
      // (`fetchServiceAreaModules` фақат `manualModules`), МФЙ'га клиент ёзуви
      // эса rules'да ёпилди — модул созламаси фақат `adminSaveModuleConfig`.
      for (final area in areas) {
        final packed = batch[area.id];
        final cfg = packed?.config ?? ServiceModuleConfig.empty;
        final manual = packed?.manualModules ?? <String>{};
        overrides[area.id] = {
          for (final id in kKnownModuleIds)
            id: manual.contains(id) ? cfg.modules[id] : null,
        };
        saved[area.id] = Map<String, ModuleStatus?>.from(overrides[area.id]!);
        manuals[area.id] = Set<String>.from(manual);
        savedManuals[area.id] = Set<String>.from(manual);
      }

      final dOverrides = <String, Map<String, ModuleStatus?>>{};
      final dSaved = <String, Map<String, ModuleStatus?>>{};
      final dManuals = <String, Set<String>>{};
      final dSavedManuals = <String, Set<String>>{};
      // Аввал бу ерда «lift» бор эди: туманда `manualModules` бўш бўлса,
      // биринчи МФЙ override'и ҲАР очилишда туманга кўчириб сақланарди.
      // Бу 2026-08-20 даги бир марталик миграция эди (туман даражаси
      // қўшилганда, `58f1925`) ва ўшандан бери бажарилган. Ҳозир у фақат
      // зарар қиларди: битта МФЙ учун мўлжалланган пилот бутун туманга
      // ёйиларди ва туманни «Default (мерос)»га қайтариб бўлмасди.
      for (final d in districts) {
        final packed = districtBatch[d.id];
        final cfg = packed?.config ?? ServiceModuleConfig.empty;
        final manual = packed?.manualModules ?? <String>{};
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
        _absentDefaults
          ..clear()
          ..addAll(kKnownModuleIds
              .where((id) => !defaultsRes.config.modules.containsKey(id)));
        _regions = regions;
        _regionId = regionId;
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

  /// Joriy viloyat: tanlangani → `xorazm` → ro'yxatdagi birinchisi.
  String _resolveRegionId(List<GeoRegion> regions) {
    if (regions.any((r) => r.id == _regionId)) return _regionId;
    if (regions.any((r) => r.id == _fallbackRegionId)) return _fallbackRegionId;
    return regions.isEmpty ? _fallbackRegionId : regions.first.id;
  }

  Future<void> _onRegionChanged(String? id) async {
    final next = (id ?? '').trim();
    if (next.isEmpty || next == _regionId) return;
    if (_hasDirtyAny) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Saqlanmagan oʻzgarish bor'),
          content: const Text(
            'Viloyat almashtirilsa saqlanmagan oʻzgarishlar yoʻqoladi.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bekor qilish'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Davom etish'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    if (!mounted) return;
    setState(() {
      _regionId = next;
      _expandedDistricts.clear();
    });
    await _loadAll();
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
    // `enforce=false` да `ServiceConfigHolder.statusOf` config'да БОР ҳар
    // қандай модулни `enabled` қилади — `hidden` ёзиш янги модулни
    // ЁҚИБ юборарди (`service_runtime_gate_test`: «enforce=false ham yangi
    // APK modulini avtomatik ON qilmaydi»). Шу ҳолатда тегмаймиз.
    if (!enforce) return;
    final missing = kKnownModuleIds
        .where((id) => !remote.modules.containsKey(id))
        .toList(growable: false);
    if (missing.isEmpty) return;
    // Фақат етишмаган модуллар (`null → hidden`) — аввал бутун устун
    // қайта ёзиларди. Аудитда `source: apk_module_sync`.
    try {
      await _saveModuleConfig({
        'scope': 'global',
        'source': 'apk_module_sync',
        'changes': [
          for (final id in missing)
            ModuleChange(id, null, ModuleStatus.hidden).toJson(),
        ],
      });
      if (!mounted) return;
      _absentDefaults.removeAll(missing);
    } catch (e) {
      // Конфликт — бошқа админ аллақачон қўшган; бошқа хато — кейинги
      // очилишда қайта уринилади.
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
      final expanded = _expandedDistricts.contains(d.id);
      final showAll = expanded && areas.length > 1;

      if (showAll) {
        for (final a in areas) {
          cols.add(_MatrixColumn(area: a, district: d));
        }
      } else {
        // MFY seed qilinmagan tuman ham ustun oladi — `geo_district_modules`
        // override'i zonaga bog'liq emas.
        cols.add(_MatrixColumn(
          area: areas.isEmpty ? null : areas.first,
          district: d,
          isPrimary: true,
        ));
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

  /// Callable: модул ҳолатини сақлаш. Сервер ҳар катакнинг `from`ини
  /// ўзидаги жорий қиймат билан солиштиради (фарқ бўлса — конфликт, ҳеч
  /// нарса ёзилмайди) ва ҳар сақлашни `admin_audit`га ёзади (эга,
  /// 2026-10-08). Аввал бу ерда бутун Global устун тўғридан-тўғри Firestore'га
  /// қайта ёзиларди.
  Future<int> _saveModuleConfig(Map<String, Object?> payload) async {
    final res = await FirebaseFunctions.instance
        .httpsCallable('adminSaveModuleConfig')
        .call<Object?>(payload)
        .timeout(const Duration(seconds: 25));
    final data = res.data;
    return data is Map ? ((data['applied'] as num?)?.toInt() ?? 0) : 0;
  }

  /// Сақланмаган ўзгаришлар — нишон (Global / туман / МФЙ) бўйича, фақат
  /// ўзгарган катаклар.
  List<_SaveTarget> _pendingTargets({bool globalOnly = false}) {
    final out = <_SaveTarget>[];
    final global = [
      for (final c
          in diffModuleStatuses(_savedDefaults, _defaults, kKnownModuleIds))
        ModuleChange(c.moduleId,
            _absentDefaults.contains(c.moduleId) ? null : c.from, c.to),
    ];
    final enforceChanged = _enforce != _savedEnforce;
    if (global.isNotEmpty || enforceChanged) {
      out.add(_SaveTarget(
        scope: 'global',
        targetId: '',
        title: 'Baseline GLOBAL',
        changes: global,
        enforce: enforceChanged ? (from: _savedEnforce, to: _enforce) : null,
      ));
    }
    if (globalOnly) return out;
    for (final did in _districtOverrides.keys) {
      final changes = diffModuleStatuses(
        _savedDistrictOverrides[did] ?? const {},
        _districtOverrides[did] ?? const {},
        kKnownModuleIds,
      );
      if (changes.isEmpty) continue;
      out.add(_SaveTarget(
        scope: 'district',
        targetId: did,
        title: _districtById[did]?.displayName ?? did,
        changes: changes,
      ));
    }
    for (final aid in _overrides.keys) {
      final changes = diffModuleStatuses(
        _savedOverrides[aid] ?? const {},
        _overrides[aid] ?? const {},
        kKnownModuleIds,
      );
      if (changes.isEmpty) continue;
      out.add(_SaveTarget(
        scope: 'area',
        targetId: aid,
        title: _areaById[aid]?.displayName ?? aid,
        changes: changes,
      ));
    }
    return out;
  }

  /// Сақланган нишон — фақат юборилган катаклар «сақланган» бўлади (сақлаш
  /// пайтида бошқа катак ўзгарган бўлса, у сақланмаган бўлиб қолади).
  void _markSaved(_SaveTarget t) {
    if (t.scope == 'global') {
      for (final c in t.changes) {
        _savedDefaults[c.moduleId] = c.to!;
        _absentDefaults.remove(c.moduleId);
      }
      if (t.enforce != null) _savedEnforce = t.enforce!.to;
      return;
    }
    final isDistrict = t.scope == 'district';
    final saved = (isDistrict ? _savedDistrictOverrides : _savedOverrides)
        .putIfAbsent(t.targetId, () => {});
    final savedMan = (isDistrict ? _savedManualByDistrict : _savedManualByArea)
        .putIfAbsent(t.targetId, () => <String>{});
    for (final c in t.changes) {
      saved[c.moduleId] = c.to;
      if (c.to == null) {
        savedMan.remove(c.moduleId);
      } else {
        savedMan.add(c.moduleId);
      }
    }
  }

  Future<void> _saveGlobal() => _save(globalOnly: true);

  Future<void> _saveAll() => _save();

  /// «Сақлаш»: аввал нима ўзгаришини кўрсатади; тасдиқлангач ҳар нишон
  /// алоҳида callable. Конфликт бўлса — жадвал сервердан қайта юкланади.
  Future<void> _save({bool globalOnly = false}) async {
    final targets = _pendingTargets(globalOnly: globalOnly);
    if (targets.isEmpty) return;
    final confirmed = await _confirmChanges(targets);
    if (confirmed != true || !mounted) return;
    setState(() {
      _savingGlobal = targets.any((t) => t.scope == 'global');
      _savingMatrix = targets.any((t) => t.scope != 'global');
    });
    final messenger = ScaffoldMessenger.of(context);
    var applied = 0;
    try {
      for (final t in targets) {
        applied += await _saveModuleConfig(t.toPayload());
        if (!mounted) return;
        setState(() => _markSaved(t));
      }
      messenger.showSnackBar(SnackBar(
        content: Text('Сақланди: $applied та ўзгариш (журналга ёзилди)',
            style: const TextStyle(color: AppColors.onPrimary)),
        backgroundColor: AppColors.button,
      ));
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      final code = details is Map ? '${details['code'] ?? e.code}' : e.code;
      if (code == 'MODULE_CONFIG_CONFLICT') {
        final conflicts = details is Map && details['conflicts'] is List
            ? details['conflicts'] as List
            : const [];
        final names = [
          for (final c in conflicts)
            if (c is Map && c['moduleId'] != null)
              _labelFor('${c['moduleId']}'),
        ].join(', ');
        messenger.showSnackBar(SnackBar(
          content: Text('Бошқа админ шу орада ўзгартирди'
              '${names.isEmpty ? '' : ': $names'}. Жадвал янгиланди — '
              'ўзгаришни қайта киритинг. ($code)'),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 8),
        ));
        if (mounted) await _loadAll();
      } else {
        messenger.showSnackBar(SnackBar(
          content: Text('Сақлаб бўлмади. Қайта уриниб кўринг. ($code)'),
          backgroundColor: Colors.red,
        ));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Сақлаб бўлмади. Қайта уриниб кўринг. ($e)'),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) {
        setState(() {
          _savingGlobal = false;
          _savingMatrix = false;
        });
      }
    }
  }

  /// «Журнал»: ким, қачон, қайси модулни ўзгартирди (`admin_audit`дан,
  /// сервер орқали — `admin_audit` клиентга ёпиқ).
  Future<void> _openJournal() async {
    final future = FirebaseFunctions.instance
        .httpsCallable('adminListModuleConfigAudit')
        .call<Object?>({'limit': 100})
        .timeout(const Duration(seconds: 25))
        .then((res) {
      final raw = res.data is Map ? (res.data as Map)['entries'] : null;
      return <ModuleAuditEntry>[
        if (raw is List)
          for (final e in raw)
            if (e is Map) ModuleAuditEntry.fromMap(e),
      ];
    });
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Журнал — модул ўзгаришлари'),
        content: SizedBox(
          width: 560,
          height: 480,
          child: FutureBuilder<List<ModuleAuditEntry>>(
            future: future,
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                final e = snap.error;
                final code = e is FirebaseFunctionsException ? e.code : '$e';
                return Center(
                  child: Text('Журнални юклаб бўлмади. Қайта уриниб кўринг. '
                      '($code)'),
                );
              }
              final list = snap.data ?? const <ModuleAuditEntry>[];
              if (list.isEmpty) {
                return const Center(child: Text('Ҳали ёзув йўқ.'));
              }
              return ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 16),
                itemBuilder: (_, i) => _journalTile(list[i]),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Ёпиш'),
          ),
        ],
      ),
    );
  }

  Widget _journalTile(ModuleAuditEntry e) {
    String st(ModuleStatus? s) =>
        s == null ? (e.scope == 'global' ? 'йўқ' : 'мерос') : _statusLabel(s);
    String two(int v) => v.toString().padLeft(2, '0');
    final at = e.at;
    final when = at == null
        ? '—'
        : '${two(at.day)}.${two(at.month)}.${at.year} '
            '${two(at.hour)}:${two(at.minute)}';
    final target = switch (e.scope) {
      'global' => 'Baseline GLOBAL',
      'district' => _districtById[e.targetId]?.displayName ?? e.targetId,
      _ => _areaById[e.targetId]?.displayName ?? e.targetId,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$when · $target',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(
          '+${e.actor}'
          '${e.source == 'apk_module_sync' ? ' · APK модул синхрони' : ''}',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        if (e.enforceFrom != null && e.enforceTo != null)
          Text('Config-driven rejim (enforce): '
              '${e.enforceFrom! ? 'ёқилган' : 'ўчиқ'} → '
              '${e.enforceTo! ? 'ёқилган' : 'ўчиқ'}'),
        for (final c in e.changes)
          Text('${_labelFor(c.moduleId)}: ${st(c.from)} → ${st(c.to)}'),
      ],
    );
  }

  /// Сақлашдан олдин — нима ўзгаришини кўрсатиш.
  Future<bool?> _confirmChanges(List<_SaveTarget> targets) {
    String st(ModuleStatus? s, String scope) =>
        s == null ? (scope == 'global' ? 'йўқ' : 'мерос') : _statusLabel(s);
    String onOff(bool v) => v ? 'ёқилган' : 'ўчиқ';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ўзгаришларни сақлаш'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final t in targets) ...[
                  Text(t.title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (t.enforce != null)
                    Text('  Config-driven rejim (enforce): '
                        '${onOff(t.enforce!.from)} → ${onOff(t.enforce!.to)}'),
                  for (final c in t.changes)
                    Text('  ${_labelFor(c.moduleId)}: '
                        '${st(c.from, t.scope)} → ${st(c.to, t.scope)}'),
                  const SizedBox(height: 10),
                ],
                Text('Ким ва қачон ўзгартиргани журналга ёзилади.',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Бекор'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сақлаш'),
          ),
        ],
      ),
    );
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
                // Ўртага тенгланади (эга қарори, 2026-09-28): аввал
                // `start` эди ва вилоят танлагичи баланд enforce
                // панелининг ёнида тепага ёпишиб, остида бўш жой
                // қоларди.
                crossAxisAlignment: CrossAxisAlignment.center,
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
                  if (_regions.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    SizedBox(width: 220, child: _regionPicker()),
                  ],
                  const SizedBox(width: 8),
                  // 320 тор эди: сарлавҳа 2 қаторга, изоҳ 3 қаторга
                  // бўлиниб, панел баландлашиб кетарди. Кенгайтирилди —
                  // иккови ҳам бир қаторга сиғади ва баландлик тушади.
                  SizedBox(width: 470, child: _enforceBar()),
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
              OutlinedButton.icon(
                onPressed: _openJournal,
                icon: const Icon(Icons.history, size: 18),
                label: const Text('Журнал'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
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
    // ЎҚИЛАДИГАН ўлчамлар (эга, 2026-10-19: «ёзувлар жуда майдалашиб кетган»): матн 13–14 px, катак баландлиги 44,
    // экранга сиғдириш учун қисилмайди — қаторлар тепа-пастга тортилади, сарлавҳа қатори тепада туради.
    const labelW = 210.0;
    const minCellW = 88.0;
    const cellH = 44.0;
    final collapsed = _isCollapsedView;
    final districtHeaderH = collapsed ? 68.0 : 52.0;
    final zoneHeaderH = collapsed ? 0.0 : 60.0;

    final colCount = columns.length;
    final dataW = constraints.maxWidth - labelW;

    final fillWidth = colCount > 0 && colCount * minCellW <= dataW;
    final cellW = fillWidth && colCount > 0 ? dataW / colCount : minCellW;
    const headerFont = 13.0;
    const rowFont = 14.0;
    final matrixW = fillWidth ? constraints.maxWidth : labelW + colCount * cellW;

    final table = SizedBox(
      width: matrixW,
      height: constraints.maxHeight,
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
          Expanded(
            child: Scrollbar(
              controller: _matrixVScroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                key: const ValueKey('matrix-rows-scroll'),
                controller: _matrixVScroll,
                child: Column(
                  children: [
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
              ),
            ),
          ),
        ],
      ),
    );

    if (fillWidth) return table;

    // Устунлар кўп бўлса — ён томонга ҳам тортилади (қаторлар тепа-пастга тортилгани ҳолда).
    return Scrollbar(
      controller: _matrixHScroll,
      thumbVisibility: true,
      notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _matrixHScroll,
        scrollDirection: Axis.horizontal,
        child: table,
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
              canExpand ? AppColors.primaryText : Colors.black87,
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
              color: Colors.grey.shade700,
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

  Widget _regionPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _regions.any((r) => r.id == _regionId) ? _regionId : null,
          isExpanded: true,
          isDense: true,
          icon: const Icon(Icons.expand_more, size: 18),
          hint: const Text('Вилоят', style: TextStyle(fontSize: 13)),
          style: const TextStyle(fontSize: 13, color: Colors.black87),
          selectedItemBuilder: (_) => [
            for (final r in _regions)
              Row(
                children: [
                  const Icon(Icons.public, size: 15, color: AppColors.primaryText),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      r.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
          ],
          items: [
            for (final r in _regions)
              DropdownMenuItem(
                value: r.id,
                child: Text(r.displayName, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (_savingMatrix || _savingGlobal) ? null : _onRegionChanged,
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
              // Иккови ҳам БИР ҚАТОР — панел баландлиги матн ўралишига
              // қараб ўзгармасин.
              title: const Text(
                'Config-driven rejim (enforce)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _enforce
                    ? 'YOQILGAN — faqat yoqilgan modullar ochiladi'
                    : 'OʻCHIQ — barcha modul ochiladi',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
            label: Text(
              _hasDirtyDefaults ? 'Baseline*' : 'Baseline',
              maxLines: 1,
              style: const TextStyle(fontSize: 12),
            ),
            // Кичик, БИР ҚАТОР тугма (эга қарори, 2026-09-28):
            // `Material` нинг стандарт 48px минимал баландлиги олиб
            // ташланади, акс ҳолда тугма ёнидаги матндан баланд туради.
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
        titleColor: canExpand ? AppColors.primaryText : Colors.black87,
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
        : col.area == null
            ? _districtDisplayName(col.district!.displayName)
            : _zoneDisplayName(col.area!.displayName, col.district!.displayName);

    final child = Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
              padding: const EdgeInsets.only(left: 12, right: 6),
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
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
    if (_savingGlobal || _savingMatrix) return;
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

    // Ойна ташқарисига босиб ёпилса `showDialog` `null` қайтаради — бу «ҳеч
    // нарса танланмади». Аввал шу `null` «мерос» деб қабул қилиниб, туман/
    // МФЙ катагидаги override жимгина ўчарди (эга, 2026-10-08).
    final picked = await showDialog<CellPick>(
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
              onPressed: () => Navigator.pop(ctx, const CellPick(null)),
              child: Text(_isDistrictKey(areaId)
                  ? 'Global baseline (inherit)'
                  : 'Tuman / baseline (inherit)'),
            ),
          for (final s in ModuleStatus.values)
            if (!isPlaceholder || s != ModuleStatus.enabled)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, CellPick(s)),
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
    if (!cellPickChanges(picked, current) || !mounted) return;
    _setCell(areaId, moduleId, picked!.status);
  }

  List<Widget> _legendChips() => [
        _legend('Очиқ', Colors.green),
        _legend('Ҳамкорлик', Colors.orange),
        _legend('Тез кунда', Colors.blue),
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
        ModuleStatus.soon => 'Тез кунда',
        ModuleStatus.hidden => 'Ёпиқ',
      };

  static Color _statusColor(ModuleStatus s) => switch (s) {
        ModuleStatus.enabled => AvaLight.ok,
        ModuleStatus.comingSoon => Colors.orange.shade800,
        ModuleStatus.soon => Colors.blue.shade600,
        ModuleStatus.hidden => Colors.grey.shade600,
      };
}

class _DistrictSpan {
  const _DistrictSpan({required this.district, required this.count});
  final GeoDistrict district;
  final int count;
}

/// Бир нишон (Global / туман / МФЙ) учун сақланадиган ўзгаришлар —
/// `adminSaveModuleConfig` callable'и учун.
class _SaveTarget {
  const _SaveTarget({
    required this.scope,
    required this.targetId,
    required this.title,
    required this.changes,
    this.enforce,
  });

  /// `global` · `district` · `area`.
  final String scope;
  final String targetId;
  final String title;
  final List<ModuleChange> changes;
  final ({bool from, bool to})? enforce;

  Map<String, Object?> toPayload() => {
        'scope': scope,
        if (scope != 'global') 'targetId': targetId,
        'changes': [for (final c in changes) c.toJson()],
        if (enforce != null)
          'enforce': {'from': enforce!.from, 'to': enforce!.to},
        'source': 'admin_ui',
      };
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
