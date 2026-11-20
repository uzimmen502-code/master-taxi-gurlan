/// «AVA Супермаркет» таксономияси — `taxonomy/supermarket` ҳужжатининг клиент модели
/// (1-босқич, эга 2026-11-20). Клиент фақат ўқийди; ёзувчи — `adminSetSupermarketTaxonomy` (сервер).
///
/// Шакл (сервер шартномаси): `{version, categories:[{id, order, icon, names{uz_Cyrl,uz_Latn,ru},
/// groups:[{id, order, names, unit kg|l|piece|pack|bunch, step, weighed, synonyms[]}]}]}`.
/// Бузилган/номаълум ёзув ташланади (crash эмас).
library;

import '../../markets/domain/market_taxonomy.dart' show localizedName;
import 'sm_qty.dart';

export '../../markets/domain/market_taxonomy.dart' show localizedName;

/// Шартномадаги бирликлар. Номаълум бирлик — гуруҳ ташланади.
const kSmUnits = <String>{'kg', 'l', 'piece', 'pack', 'bunch'};

Map<String, String> smNames(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, String>{};
  raw.forEach((k, v) {
    if (k is String && v is String && v.trim().isNotEmpty) out[k] = v.trim();
  });
  return out;
}

String _str(Object? v) => v is String ? v.trim() : '';
int _int(Object? v, [int d = 0]) => v is num ? v.toInt() : d;

class SmGroup {
  const SmGroup({
    required this.id,
    required this.categoryId,
    required this.order,
    required this.names,
    required this.unit,
    required this.stepMilli,
    required this.weighed,
    this.synonyms = const [],
    this.pairs = const [],
  });

  /// «Буни ҳам қўшасизми?» учун жуфт гуруҳлар (2-босқич шартномаси, ихтиёрий; эски ҳужжатда йўқ).
  final List<String> pairs;

  final String id;
  final String categoryId;
  final int order;
  final Map<String, String> names;
  final String unit;

  /// Қадам минг улушда (0.5 кг → 500). Пул эмас — фақат миқдор.
  final int stepMilli;
  final bool weighed;
  final List<String> synonyms;

  String name(String lang) => localizedName(names, lang, fallback: id);

  static SmGroup? fromMap(Object? raw, String categoryId) {
    if (raw is! Map) return null;
    final id = _str(raw['id']);
    final unit = _str(raw['unit']);
    if (id.isEmpty || !kSmUnits.contains(unit)) return null;
    final step = raw['step'] is num ? smToMilli(raw['step'] as num) : 1000;
    return SmGroup(
      id: id,
      categoryId: categoryId,
      order: _int(raw['order']),
      names: smNames(raw['names']),
      unit: unit,
      stepMilli: step > 0 ? step : 1000,
      weighed: raw['weighed'] == true,
      synonyms: [
        if (raw['synonyms'] is List)
          for (final s in raw['synonyms'] as List)
            if (s is String && s.trim().isNotEmpty) s.trim(),
      ],
      pairs: [
        if (raw['pairs'] is List)
          for (final p in (raw['pairs'] as List).toSet())
            if (p is String && p.trim().isNotEmpty && p.trim() != id) p.trim(),
      ],
    );
  }
}

class SmCategory {
  const SmCategory({
    required this.id,
    required this.order,
    required this.icon,
    required this.names,
    required this.groups,
  });

  final String id;
  final int order;

  /// Сервердаги иконка калити (`icon`); клиент уни [smCategoryIcon] орқали чизади.
  final String icon;
  final Map<String, String> names;
  final List<SmGroup> groups;

  String name(String lang) => localizedName(names, lang, fallback: id);

  static SmCategory? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = _str(raw['id']);
    if (id.isEmpty) return null;
    final groups = <SmGroup>[
      if (raw['groups'] is List)
        ...(raw['groups'] as List).map((g) => SmGroup.fromMap(g, id)).whereType<SmGroup>(),
    ]..sort((a, b) => a.order.compareTo(b.order));
    return SmCategory(
      id: id,
      order: _int(raw['order']),
      icon: _str(raw['icon']),
      names: smNames(raw['names']),
      groups: List.unmodifiable(groups),
    );
  }
}

class SmTaxonomy {
  SmTaxonomy({required this.version, required List<SmCategory> categories})
      : categories = List.unmodifiable(categories),
        _groups = {
          for (final c in categories)
            for (final g in c.groups) g.id: g,
        };

  static final empty = SmTaxonomy(version: 0, categories: const []);

  final int version;
  final List<SmCategory> categories;
  final Map<String, SmGroup> _groups;

  SmGroup? group(String id) => _groups[id];

  SmCategory? category(String id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  factory SmTaxonomy.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return empty;
    final cats = <SmCategory>[
      if (raw['categories'] is List)
        ...(raw['categories'] as List).map(SmCategory.fromMap).whereType<SmCategory>(),
    ]..sort((a, b) => a.order.compareTo(b.order));
    return SmTaxonomy(version: _int(raw['version']), categories: cats);
  }
}
