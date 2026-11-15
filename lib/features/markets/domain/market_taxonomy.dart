/// «Бозорлар» таксономияси — `taxonomy/markets` ҳужжатининг клиент модели (5+6-босқич, эга 2026-11-15).
///
/// Ягона манба (7-банд): бозорлар, бўлимлар, динамик майдонлар ва нарх бирликлари — ҲУЖЖАТДАН
/// (`functions/market_taxonomy.js` валидатори ёзади: `adminSetMarketTaxonomy`, `version` + `markets`).
/// Бўлим/майдон номлари 3 тилда ҳужжатда (`names.uz_Cyrl|uz_Latn|ru`), lang файлларида эмас.
///
/// Бузилган/номаълум шакл — ташланади (crash эмас): эски APK янги майдон турини кўрса уни кўрсатмайди.
library;

import '../../tv_market/domain/price_unit.dart';

/// Тилли ном: `lang` → `uz_Cyrl` → биринчи бўш бўлмагани → [fallback].
String localizedName(Map<String, String> names, String lang, {String fallback = ''}) {
  final own = names[lang]?.trim() ?? '';
  if (own.isNotEmpty) return own;
  final cyr = names['uz_Cyrl']?.trim() ?? '';
  if (cyr.isNotEmpty) return cyr;
  for (final v in names.values) {
    if (v.trim().isNotEmpty) return v.trim();
  }
  return fallback;
}

Map<String, String> _names(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, String>{};
  raw.forEach((k, v) {
    if (k is String && v is String && v.trim().isNotEmpty) out[k] = v.trim();
  });
  return out;
}

String _str(Object? v) => v is String ? v.trim() : '';
int? _int(Object? v) => v is int ? v : (v is num && v == v.roundToDouble() ? v.toInt() : null);

/// Импорт белгиси (`imported`) бор бозорлар — эга қарори 2026-11-15 (AVA_DECIDED: «Гўшт: … + Импорт»).
/// Таксономия ҳужжатида бу белги ҳали йўқ (очиқ масала: кейин `markets.{id}.importFlag`га кўчириш).
const Set<String> kMarketsWithImported = {'meat'};

/// Бозор экранида «Барчаси»сиз ТАБЛАР (бўлимлар бир-биридан тубдан фарқ қилади: мошина ≠ эҳтиёт қисм) —
/// эга қарори 2026-11-15 (AVA_DECIDED: «Мошина tabs Мошиналар·Мото·Техника·Эҳтиёт қисмлар»). Қолган кўп бўлимли
/// бозорлар — «Барчаси» + чиплар. Таксономияда белги йўқ (очиқ масала).
const Set<String> kMarketsWithoutAllTab = {'auto'};

enum MarketFieldType { int, text, select, bool, date }

MarketFieldType? _fieldType(String s) {
  for (final t in MarketFieldType.values) {
    if (t.name == s) return t;
  }
  return null;
}

class MarketOption {
  const MarketOption(this.id, this.names);
  final String id;
  final Map<String, String> names;
  String label(String lang) => localizedName(names, lang, fallback: id);
}

class MarketCategory {
  const MarketCategory({required this.id, required this.names, this.orderable = false});
  final String id;
  final Map<String, String> names;
  final bool orderable;
  String label(String lang) => localizedName(names, lang, fallback: id);
}

/// Майдон текширув хатоси (кодлар — lang калитларига `market_err_*` орқали боғланади).
enum MarketFieldError { required, number, min, max, maxLen, option }

class MarketField {
  const MarketField({
    required this.key,
    required this.type,
    required this.names,
    this.required = false,
    this.min,
    this.max,
    this.maxLen,
    this.options = const [],
    this.categories = const [],
  });

  final String key;
  final MarketFieldType type;
  final Map<String, String> names;
  final bool required;
  final int? min;
  final int? max;
  final int? maxLen;
  final List<MarketOption> options;

  /// Бўш — барча бўлимларга; бўлмаса фақат шу бўлимларда.
  final List<String> categories;

  String label(String lang) => localizedName(names, lang, fallback: key);

  bool appliesTo(String category) => categories.isEmpty || categories.contains(category);

  MarketOption? option(String id) {
    for (final o in options) {
      if (o.id == id) return o;
    }
    return null;
  }

  static MarketField? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final key = _str(raw['key']);
    final type = _fieldType(_str(raw['type']));
    if (key.isEmpty || type == null) return null;
    final opts = <MarketOption>[];
    final rawOpts = raw['options'];
    if (rawOpts is List) {
      for (final o in rawOpts) {
        if (o is! Map) continue;
        final id = _str(o['id']);
        if (id.isNotEmpty) opts.add(MarketOption(id, _names(o['names'])));
      }
    }
    if (type == MarketFieldType.select && opts.isEmpty) return null;
    final cats = raw['categories'];
    return MarketField(
      key: key,
      type: type,
      names: _names(raw['names']),
      required: raw['required'] == true,
      min: _int(raw['min']),
      max: _int(raw['max']),
      maxLen: _int(raw['maxLen']),
      options: opts,
      categories: cats is List ? [for (final c in cats) if (_str(c).isNotEmpty) _str(c)] : const [],
    );
  }

  /// Формадаги қиймат текшируви. [value] — форма ҳолати: int/text/date учун матн (`String`), select — option id,
  /// bool — `bool`. Бўш қиймат: [required] бўлса хато, бўлмаса тўғри.
  MarketFieldError? validate(Object? value) {
    final empty = value == null || (value is String && value.trim().isEmpty) || (type == MarketFieldType.bool && value != true);
    if (empty) return required ? MarketFieldError.required : null;
    switch (type) {
      case MarketFieldType.int:
        final n = int.tryParse('$value'.replaceAll(' ', '').trim());
        if (n == null) return MarketFieldError.number;
        if (min != null && n < min!) return MarketFieldError.min;
        if (max != null && n > max!) return MarketFieldError.max;
        return null;
      case MarketFieldType.text:
        if (maxLen != null && '$value'.trim().length > maxLen!) return MarketFieldError.maxLen;
        return null;
      case MarketFieldType.select:
        return option('$value') == null ? MarketFieldError.option : null;
      case MarketFieldType.bool:
        return null;
      case MarketFieldType.date:
        return parseIsoDate('$value') == null ? MarketFieldError.number : null;
    }
  }

  /// Форма қиймати → ҳужжат қиймати (турли; бўш — `null`, ёзилмайди). Текширувдан ўтган қиймат кутилади.
  Object? serialize(Object? value) {
    if (value == null) return null;
    switch (type) {
      case MarketFieldType.int:
        return int.tryParse('$value'.replaceAll(' ', '').trim());
      case MarketFieldType.text:
        final s = '$value'.trim();
        return s.isEmpty ? null : s;
      case MarketFieldType.select:
        return option('$value') == null ? null : '$value';
      case MarketFieldType.bool:
        // Белгиланмаган = «кўрсатилмаган» (ёзилмайди); фақат `true` сақланади.
        return value == true ? true : null;
      case MarketFieldType.date:
        final d = parseIsoDate('$value');
        return d == null ? null : isoDate(d);
    }
  }

  /// Ҳужжат қиймати → кўрсатиш матни ([lang]); номаълум/бузилган қиймат — бўш.
  String display(Object? stored, String lang, {String yes = ''}) {
    switch (type) {
      case MarketFieldType.int:
        final n = _int(stored);
        return n == null ? '' : '$n';
      case MarketFieldType.text:
        return _str(stored);
      case MarketFieldType.select:
        return option(_str(stored))?.label(lang) ?? '';
      case MarketFieldType.bool:
        return stored == true ? yes : '';
      case MarketFieldType.date:
        final d = parseIsoDate(_str(stored));
        return d == null ? '' : displayDate(d);
    }
  }

  /// Ҳужжат қиймати → форма ҳолати (таҳрир учун).
  Object? toFormValue(Object? stored) {
    switch (type) {
      case MarketFieldType.int:
        final n = _int(stored);
        return n == null ? '' : '$n';
      case MarketFieldType.text:
      case MarketFieldType.date:
        return _str(stored);
      case MarketFieldType.select:
        return option(_str(stored)) == null ? null : _str(stored);
      case MarketFieldType.bool:
        return stored == true;
    }
  }
}

/// `yyyy-mm-dd` (ISO сана; вақт зонасиз — эга шартномаси: сана сатр сифатида ёзилади).
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? parseIsoDate(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s.trim());
  if (m == null) return null;
  final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
  final dt = DateTime(y, mo, d);
  return (dt.year == y && dt.month == mo && dt.day == d) ? dt : null;
}

/// Кўрсатиш учун `dd.mm.yyyy`.
String displayDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

class MarketDef {
  const MarketDef({
    required this.id,
    required this.moduleId,
    required this.order,
    required this.names,
    this.slogan = const {},
    this.categories = const [],
    this.fields = const [],
    this.priceUnits = const [PriceUnit.fixed],
  });

  final String id;
  final String moduleId;
  final int order;
  final Map<String, String> names;
  final Map<String, String> slogan;
  final List<MarketCategory> categories;
  final List<MarketField> fields;

  /// Таксономия тартибида (биринчиси — сукут). Бўш бўлмайди.
  final List<PriceUnit> priceUnits;

  String label(String lang) => localizedName(names, lang, fallback: id);

  /// Битта бўлим (Мол бозори: `all`) — ўзи қўйилади, чип кўрсатилмайди.
  String? get autoCategory => categories.length == 1 ? categories.first.id : null;
  bool get hasCategoryChoice => categories.length > 1;
  bool get hasImported => kMarketsWithImported.contains(id);

  /// Бозор экранида «Барчаси»сиз таблар ([kMarketsWithoutAllTab]).
  bool get usesTabs => hasCategoryChoice && kMarketsWithoutAllTab.contains(id);

  MarketCategory? category(String id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Бўлимга тегишли майдонлар (таксономия тартибида).
  List<MarketField> fieldsFor(String category) => [for (final f in fields) if (f.appliesTo(category)) f];

  static MarketDef? fromMap(String id, Object? raw) {
    if (raw is! Map || id.trim().isEmpty) return null;
    final moduleId = _str(raw['moduleId']);
    if (moduleId.isEmpty) return null;
    final cats = <MarketCategory>[];
    final rawCats = raw['categories'];
    if (rawCats is List) {
      for (final c in rawCats) {
        if (c is! Map) continue;
        final cid = _str(c['id']);
        if (cid.isEmpty || cats.any((x) => x.id == cid)) continue;
        cats.add(MarketCategory(id: cid, names: _names(c['names']), orderable: c['orderable'] == true));
      }
    }
    final fields = <MarketField>[];
    final rawFields = raw['fields'];
    if (rawFields is List) {
      for (final f in rawFields) {
        final parsed = MarketField.fromMap(f);
        if (parsed != null && !fields.any((x) => x.key == parsed.key)) fields.add(parsed);
      }
    }
    final units = <PriceUnit>[];
    final rawUnits = raw['priceUnits'];
    if (rawUnits is List) {
      for (final u in rawUnits) {
        if (u is! String) continue;
        final pu = PriceUnit.fromWire(u);
        // Номаълум сатр fromWire'да `fixed`га тушади — фақат ҳақиқий '' бўлса қабул қилинади.
        if (pu == PriceUnit.fixed && u.trim().isNotEmpty) continue;
        if (!units.contains(pu)) units.add(pu);
      }
    }
    return MarketDef(
      id: id.trim(),
      moduleId: moduleId,
      order: _int(raw['order']) ?? 0,
      names: _names(raw['names']),
      slogan: _names(raw['slogan']),
      categories: cats,
      fields: fields,
      priceUnits: units.isEmpty ? const [PriceUnit.fixed] : units,
    );
  }
}

class MarketTaxonomy {
  const MarketTaxonomy({required this.version, required this.markets});

  static const empty = MarketTaxonomy(version: 0, markets: {});

  /// Ҳужжат версияси (`taxonomyVersion` сифатида эълонга ёзилади; 0 — номаълум, ёзилмайди).
  final int version;
  final Map<String, MarketDef> markets;

  MarketDef? market(String id) => markets[id];

  /// `order` бўйича.
  List<MarketDef> get ordered => markets.values.toList()
    ..sort((a, b) {
      final c = a.order.compareTo(b.order);
      return c != 0 ? c : a.id.compareTo(b.id);
    });

  factory MarketTaxonomy.fromMap(Map<String, dynamic>? doc) {
    final raw = doc?['markets'];
    final out = <String, MarketDef>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is! String) return;
        final m = MarketDef.fromMap(k, v);
        if (m != null) out[m.id] = m;
      });
    }
    final v = _int(doc?['version']) ?? 0;
    return MarketTaxonomy(version: v >= 1 ? v : 0, markets: out);
  }
}

/// Клиент нарх филтри (бозор экрани, юкланган саҳифалар устида): чегара берилса, нархи кўрсатилмаган (0)
/// эълон ўтмайди.
bool priceInRange(int price, int? min, int? max) {
  if (min == null && max == null) return true;
  if (price <= 0) return false;
  if (min != null && price < min) return false;
  if (max != null && price > max) return false;
  return true;
}

/// Форма қийматлари → `attrs` харитаси: фақат шу бўлимга тегишли, тўлдирилган майдонлар (турли қийматлар).
/// Rules: `attrs` ≤ 20 калит — таксономия майдонлари ундан ошмайди (валидатор чеклайди).
Map<String, Object> serializeAttrs(MarketDef market, String category, Map<String, Object?> values) {
  final out = <String, Object>{};
  for (final f in market.fieldsFor(category)) {
    final v = f.serialize(values[f.key]);
    if (v != null) out[f.key] = v;
  }
  return out;
}

/// Барча майдон хатолари (калит → хато). Бўш — тўғри.
Map<String, MarketFieldError> validateAttrs(MarketDef market, String category, Map<String, Object?> values) {
  final out = <String, MarketFieldError>{};
  for (final f in market.fieldsFor(category)) {
    final e = f.validate(values[f.key]);
    if (e != null) out[f.key] = e;
  }
  return out;
}

/// Карточкадаги битта қисқа қатор: биринчи [maxParts] та тўлдирилган майдон («Зоти: Ҳисори · Ёши (ой): 24»).
/// bool — фақат номи («Бўғоз»). Номаълум майдонлар ташланади.
String marketAttrsLine(MarketDef market, String category, Map<String, Object?> attrs, String lang, {int maxParts = 3}) {
  final parts = <String>[];
  for (final f in market.fieldsFor(category)) {
    if (parts.length >= maxParts) break;
    final stored = attrs[f.key];
    if (stored == null) continue;
    if (f.type == MarketFieldType.bool) {
      if (stored == true) parts.add(f.label(lang));
      continue;
    }
    final s = f.display(stored, lang);
    if (s.isNotEmpty) parts.add('${f.label(lang)}: $s');
  }
  return parts.join(' · ');
}

/// Детал экрани учун қаторлар (ном, қиймат) — таксономия тартибида; [yes] — bool учун матн.
List<(String, String)> marketAttrRows(MarketDef market, String category, Map<String, Object?> attrs, String lang,
    {required String yes}) {
  final rows = <(String, String)>[];
  for (final f in market.fieldsFor(category)) {
    final s = f.display(attrs[f.key], lang, yes: yes);
    if (s.isNotEmpty) rows.add((f.label(lang), s));
  }
  return rows;
}
