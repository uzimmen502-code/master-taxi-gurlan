import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../service_config_holder.dart';
import 'module_geo_policy.dart';

/// Туман/вилоят жуфтлиги (ID + қисқа номлар).
@immutable
class GeoArea {
  const GeoArea({
    required this.regionId,
    required this.districtId,
    this.regionLabel = '',
    this.districtLabel = '',
  });

  static const empty = GeoArea(regionId: '', districtId: '');

  final String regionId;
  final String districtId;
  final String regionLabel;
  final String districtLabel;

  bool get isEmpty => regionId.isEmpty && districtId.isEmpty;

  /// «Гурлан, Хоразм» / «Гурлан» / «Хоразм» / ''.
  String get label {
    final d = districtLabel.trim();
    final r = regionLabel.trim();
    if (d.isEmpty) return r;
    if (r.isEmpty) return d;
    return '$d, $r';
  }

  bool sameAs(GeoArea o) => o.regionId == regionId && o.districtId == districtId;

  Map<String, dynamic> toJson() => {
        'regionId': regionId,
        'districtId': districtId,
        'regionLabel': regionLabel,
        'districtLabel': districtLabel,
      };

  factory GeoArea.fromJson(Map<String, dynamic> j) => GeoArea(
        regionId: (j['regionId'] ?? '') as String,
        districtId: (j['districtId'] ?? '') as String,
        regionLabel: (j['regionLabel'] ?? '') as String,
        districtLabel: (j['districtLabel'] ?? '') as String,
      );

  @override
  bool operator ==(Object other) =>
      other is GeoArea &&
      other.regionId == regionId &&
      other.districtId == districtId &&
      other.regionLabel == regionLabel &&
      other.districtLabel == districtLabel;

  @override
  int get hashCode => Object.hash(regionId, districtId, regionLabel, districtLabel);
}

/// Модулдаги кўриниш: даража + таянч ҳудуд.
@immutable
class GeoScope {
  const GeoScope({required this.level, required this.area, this.pinned = false});

  final GeoLevel level;
  final GeoArea area;

  /// Ҳудуд модул ичида АТАЙЛАБ танланган («Бошқа ҳудуд») — сақланади.
  /// `false` бўлса фақат даража сақланади, ҳудуд эса фаол ҳудудга
  /// эргашади (сафарда локация таклифи қабул қилинса модул ҳам ўтади).
  final bool pinned;

  /// Сўров учун: туман даражасида — туман ID, вилоятда — вилоят ID,
  /// Республикада — иккаласи ҳам бўш.
  String get districtFilter => level == GeoLevel.district ? area.districtId : '';
  String get regionFilter => level == GeoLevel.region ? area.regionId : '';

  GeoScope copyWith({GeoLevel? level, GeoArea? area, bool? pinned}) => GeoScope(
        level: level ?? this.level,
        area: area ?? this.area,
        pinned: pinned ?? this.pinned,
      );

  /// Ўзгармайдиган калит (бўлим `ValueKey`, оқим кеши).
  String get key => '${level.name}:${area.regionId}:${area.districtId}';

  Map<String, dynamic> toJson() =>
      {'level': level.name, 'area': area.toJson(), 'pinned': pinned};

  static GeoScope? fromJson(Map<String, dynamic> j) {
    final lv = GeoLevel.values.where((l) => l.name == j['level']).firstOrNull;
    final a = j['area'];
    if (lv == null || a is! Map) return null;
    return GeoScope(
      level: lv,
      area: GeoArea.fromJson(Map<String, dynamic>.from(a)),
      pinned: j['pinned'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GeoScope &&
      other.level == level &&
      other.area == area &&
      other.pinned == pinned;

  @override
  int get hashCode => Object.hash(level, area, pinned);
}

/// Фаол ҳудуд қаердан келган.
enum GeoAreaSource { home, location, manual }

/// Фойдаланувчининг ҳудуд контексти (D-GEO-1, 1-такомиллаштириш):
///
/// - **Яшаш жойи** ([home]) — профилдан (`ServiceConfigHolder`), фақат
///   Профилда ўзгаради. Модул дарвозаси (ёқилган/ёпиқ) ҳам шунга қарайди.
/// - **Фаол ҳудуд** ([active]) — бош саҳифа тугмаси ёки локация таклифи
///   (D-GEO-12) билан танланади; профилни ЎЗГАРТИРМАЙДИ. Танланмаган
///   бўлса — яшаш жойига эргашади.
/// - **Модулдаги танлов** ([scopeFor]) — даража ва ҳудуд; қоида
///   [kModuleGeoPolicies]да (сақланади ёки йўқ).
class GeoContext {
  GeoContext._();

  static const _kActive = 'geo_active_v1';
  static const _kScopePrefix = 'geo_scope_v1_';

  /// Фаол ҳудуд ёки модул танлови ўзгарганда.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static GeoArea? _active;
  static GeoAreaSource _activeSource = GeoAreaSource.home;
  static final Map<String, GeoScope> _scopes = {};
  static bool _loaded = false;

  /// Тест учун — яшаш жойини бериш (`ServiceConfigHolder`сиз).
  @visibleForTesting
  static GeoArea Function()? homeOverride;

  static GeoArea get home =>
      homeOverride?.call() ??
      GeoArea(
        regionId: ServiceConfigHolder.regionId,
        districtId: ServiceConfigHolder.districtId,
        regionLabel: ServiceConfigHolder.regionLabel,
        districtLabel: ServiceConfigHolder.districtLabel,
      );

  static GeoArea get active => _active ?? home;
  static GeoAreaSource get activeSource =>
      _active == null ? GeoAreaSource.home : _activeSource;

  /// Фаол ҳудуд яшаш жойидан бошқами (UI «Яшаш жойимга қайтиш»).
  static bool get isAway => _active != null && !_active!.sameAs(home);

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kActive);
      if (raw != null && raw.isNotEmpty) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final a = GeoArea.fromJson(Map<String, dynamic>.from(j['area'] as Map));
        if (!a.isEmpty) {
          _active = a;
          _activeSource = GeoAreaSource.values
                  .where((s) => s.name == j['source'])
                  .firstOrNull ??
              GeoAreaSource.manual;
        }
      }
      for (final key in prefs.getKeys().where((k) => k.startsWith(_kScopePrefix))) {
        final s = prefs.getString(key);
        if (s == null || s.isEmpty) continue;
        final scope = GeoScope.fromJson(jsonDecode(s) as Map<String, dynamic>);
        if (scope != null) _scopes[key.substring(_kScopePrefix.length)] = scope;
      }
    } catch (e) {
      debugPrint('GeoContext.load: $e');
    }
    revision.value++;
  }

  /// Фаол ҳудудни белгилаш. Яшаш жойи билан бир хил бўлса — «яшаш жойига
  /// эргашиш» режимига қайтади (профил ўзгарса ҳам тўғри қолади).
  static Future<void> setActive(GeoArea area, GeoAreaSource source) async {
    if (area.isEmpty || area.sameAs(home)) {
      _active = null;
    } else {
      _active = area;
      _activeSource = source;
    }
    revision.value++;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_active == null) {
        await prefs.remove(_kActive);
      } else {
        await prefs.setString(
          _kActive,
          jsonEncode({'area': _active!.toJson(), 'source': _activeSource.name}),
        );
      }
    } catch (e) {
      debugPrint('GeoContext.setActive: $e');
    }
  }

  static Future<void> resetToHome() => setActive(GeoArea.empty, GeoAreaSource.home);

  /// Модулдаги жорий кўриниш. Сақланган танлов бўлмаса — қоидадаги сукут
  /// даража + фаол ҳудуд.
  static GeoScope scopeFor(String moduleId) {
    final policy = geoPolicyFor(moduleId);
    final saved = policy.persistSelection ? _scopes[moduleId] : _sessionScopes[moduleId];
    if (saved != null && policy.levels.contains(saved.level)) {
      return saved.pinned ? saved : saved.copyWith(area: active);
    }
    return GeoScope(level: policy.defaultLevel, area: active);
  }

  /// Сақланмайдиган модуллар (Улгуржи) — фақат экран очиқ турганда.
  static final Map<String, GeoScope> _sessionScopes = {};

  static Future<void> setScope(String moduleId, GeoScope scope) async {
    final policy = geoPolicyFor(moduleId);
    if (!policy.levels.contains(scope.level)) return;
    if (!policy.persistSelection) {
      _sessionScopes[moduleId] = scope;
      revision.value++;
      return;
    }
    _scopes[moduleId] = scope;
    revision.value++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_kScopePrefix$moduleId', jsonEncode(scope.toJson()));
    } catch (e) {
      debugPrint('GeoContext.setScope: $e');
    }
  }

  /// Сақланмайдиган танловни тозалаш (экран ёпилганда — D-GEO-10: Улгуржи
  /// кейинги сафар яна «Бутун Ўзбекистон»дан очилади).
  static void clearSessionScope(String moduleId) {
    if (_sessionScopes.remove(moduleId) != null) revision.value++;
  }

  @visibleForTesting
  static void resetForTest() {
    _active = null;
    _activeSource = GeoAreaSource.home;
    _scopes.clear();
    _sessionScopes.clear();
    _loaded = false;
    homeOverride = null;
  }
}
