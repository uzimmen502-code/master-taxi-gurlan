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

/// Мошина бозорининг «Эҳтиёт қисмлар» бўлими (таксономия v1, `functions/tools/data/market_taxonomy_v1.json`) —
/// тепасида туман AVA сервиси ва AVA маҳсулотлари (9-босқич, эга 2026-11-15).
const String kAutoMarketId = 'auto';
const String kAutoPartsCategory = 'parts';

/// Эга 2026-11-19 (AVA_DECIDED): Мошина бозорининг шу бўлимларида «Номи» майдони йўқ — марка ва модель тепада,
/// сарлавҳа ўзи тузилади ([composeAutoTitle]). Эҳтиёт қисмларда — аввалгидек «Номи».
const Set<String> kAutoTitleCategories = {'cars', 'moto', 'tech'};
const String kAutoOwnCarCategory = 'cars';

/// Эга 2026-11-19: шу бозорларда умумий «Тахминий вазн» (`unitWeightG`) майдони йўқ (Мол бозорида ўз `weight_kg`
/// майдони бор — дубликат; Гўшт/Деҳқон — эга олиб ташлади). Электроника/Маиший техникада қолади.
const Set<String> kMarketsWithoutUnitWeight = {'livestock', 'meat', 'farm'};

/// Ёш майдони (Мол бозори): ҳужжатда бутун ой (`attrs.age_months`), формада «йил + ой», кўрсатишда «1 йилу 7 ойлик».
const String kAgeMonthsKey = 'age_months';

/// Каробка ўлчамлари (таксономия v5, Электроника/Маиший техника): учаласи бир қаторда; ё учаласи, ё ҳеч бири.
const List<String> kBoxDimKeys = ['box_w_cm', 'box_l_cm', 'box_h_cm'];

/// [fields] ичида учала каробка майдони борми (v4 да йўқ — махсус қатор кўрсатилмайди).
bool hasBoxDims(Iterable<MarketField> fields) {
  final keys = {for (final f in fields) f.key};
  return kBoxDimKeys.every(keys.contains);
}

/// Мошина сарлавҳаси: «<марка> <модель> <йил>» (йил тўлдирилган бўлса), ортиқча бўшлиқсиз.
String composeAutoTitle({required String brand, required String model, Object? year}) {
  final y = '${year ?? ''}'.trim();
  return [brand.trim(), model.trim(), if (y.isNotEmpty && y != '0') y]
      .where((s) => s.isNotEmpty)
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// Профилдаги ёқилғи (`users.carFuelType`: petrol/cng/lpg/ev — `OilVehicle.fuelLabelUz`) → таксономия option id.
const Map<String, String> _profileFuelAlias = {'cng': 'methane', 'lpg': 'propane', 'ev': 'electric'};

/// «Ўз автомобилим» (эга 2026-11-19): профиль ([UserRepository.getCarInfo] харитаси) → форма қийматлари
/// (`brand`, `model`, `year`, `fuel`) — фақат шу бўлимда бор майдонларга ва бўш бўлмаган қийматлар. Ёқилғи —
/// таксономия вариантига мос келса (тўғридан-тўғри ёки [_profileFuelAlias]), акс ҳолда ёзилмайди.
Map<String, Object?> ownCarFormValues(MarketDef market, String category, Map<String, String> car) {
  final out = <String, Object?>{};
  for (final f in market.fieldsFor(category)) {
    switch (f.key) {
      case 'brand':
      case 'model':
        final v = (car[f.key == 'brand' ? 'carBrand' : 'carModel'] ?? '').trim();
        if (v.isNotEmpty) out[f.key] = v;
      case 'year':
        final y = int.tryParse((car['carYear'] ?? '').trim());
        if (y != null && y > 0) out[f.key] = '$y';
      case 'fuel':
        final raw = (car['carFuelType'] ?? '').trim().toLowerCase();
        final id = f.option(raw) != null ? raw : (_profileFuelAlias[raw] ?? '');
        if (id.isNotEmpty && f.option(id) != null) out[f.key] = id;
    }
  }
  return out;
}

/// Марка + модель биргаликда камида 2 белги (бўшлиқсиз).
bool autoBrandModelValid(String brand, String model) => (brand.trim().length + model.trim().length) >= 2;

/// Рус тили кўплик шакли: 1 год · 2–4 года · 5+ лет (11–14 — `many`).
String _ruPlural(int n) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return 'one';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'few';
  return 'many';
}

/// Ой → «1 йилу 7 ойлик» / «2 ёшли» / «7 ойлик» (матнлар lang файлларида: `market_age_*`). Манфий — бўш.
String formatAgeMonths(int months, String Function(String key) tr) {
  if (months < 0) return '';
  final y = months ~/ 12, m = months % 12;
  if (y == 0) return tr('market_age_m').replaceAll('{m}', '$m');
  final form = _ruPlural(y);
  if (m == 0) return tr('market_age_y_$form').replaceAll('{y}', '$y');
  return tr('market_age_ym_$form').replaceAll('{y}', '$y').replaceAll('{m}', '$m');
}

/// Учала каробка ўлчами тўлдирилган бўлса — «40 × 30 × 25 см», акс ҳолда бўш.
String formatBoxDims(Map<String, Object?> attrs, String Function(String key) tr) {
  final v = [for (final k in kBoxDimKeys) _int(attrs[k])];
  if (v.any((x) => x == null)) return '';
  return tr('market_box_value').replaceAll('{w}', '${v[0]}').replaceAll('{l}', '${v[1]}').replaceAll('{h}', '${v[2]}');
}

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
  const MarketCategory({required this.id, required this.names, this.orderable = false, this.showInNearbyAds});
  final String id;
  final Map<String, String> names;
  final bool orderable;

  /// Уйдаги «Яқиндаги эълонлар» тасмасида ҳам чиқадими (таксономия v4, эга 2026-11-16). `null` — калит йўқ
  /// (эски таксономия; чақирувчи `kNearbyAdsFallbackCategories` га тушади).
  final bool? showInNearbyAds;

  String label(String lang) => localizedName(names, lang, fallback: id);
}

/// Майдон текширув хатоси (кодлар — lang калитларига `market_err_*` орқали боғланади).
/// [incomplete] — гуруҳ майдони (каробка ўлчамлари) қисман тўлдирилган.
enum MarketFieldError { required, number, min, max, maxLen, option, incomplete }

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
    this.sloganNoOrder = const {},
    this.categories = const [],
    this.fields = const [],
    this.priceUnits = const [PriceUnit.fixed],
  });

  final String id;
  final String moduleId;
  final int order;
  final Map<String, String> names;
  final Map<String, String> slogan;

  /// Иловада буюртма йўқ пайтдаги шиор (ихтиёрий; сервер валидатори `sloganNoOrder`, ҳозир фақат Гўшт).
  final Map<String, String> sloganNoOrder;
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
        final nearby = c['showInNearbyAds'];
        cats.add(MarketCategory(
          id: cid,
          names: _names(c['names']),
          orderable: c['orderable'] == true,
          showInNearbyAds: nearby is bool ? nearby : null,
        ));
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
      sloganNoOrder: _names(raw['sloganNoOrder']),
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
  final fields = market.fieldsFor(category);
  for (final f in fields) {
    final e = f.validate(values[f.key]);
    if (e != null) out[f.key] = e;
  }
  // Каробка ўлчамлари: ё учаласи, ё ҳеч бири (эга 2026-11-19) — бўш қолганлари белгиланади.
  if (hasBoxDims(fields)) {
    bool filled(String k) => '${values[k] ?? ''}'.trim().isNotEmpty;
    final n = kBoxDimKeys.where(filled).length;
    if (n > 0 && n < kBoxDimKeys.length) {
      for (final k in kBoxDimKeys) {
        if (!filled(k)) out[k] ??= MarketFieldError.incomplete;
      }
    }
  }
  return out;
}

/// Махсус кўриниш (эга 2026-11-19): ёш — «1 йилу 7 ойлик», каробка — «40 × 30 × 25 см» (учала майдон битта
/// бўлак). [tr] берилмаса — аввалги умумий кўриниш. Қайтаради: (ном, қиймат) ёки `null` (умумий йўл); бўш қиймат —
/// ташланади. [fields] — бўлим майдонлари.
(String, String)? _specialDisplay(MarketField f, List<MarketField> fields, Map<String, Object?> attrs,
    String Function(String key)? tr) {
  if (tr == null) return null;
  if (f.key == kAgeMonthsKey && f.type == MarketFieldType.int) {
    final n = _int(attrs[f.key]);
    return (tr('market_age_label'), n == null ? '' : formatAgeMonths(n, tr));
  }
  if (kBoxDimKeys.contains(f.key) && hasBoxDims(fields)) {
    // Бўлак биринчи каробка майдонида; қолган иккитаси ташланади.
    return (tr('market_box_dims'), f.key == kBoxDimKeys.first ? formatBoxDims(attrs, tr) : '');
  }
  return null;
}

/// Карточкадаги битта қисқа қатор: биринчи [maxParts] та тўлдирилган майдон («Зоти: Ҳисори · Ёши (ой): 24»).
/// bool — фақат номи («Бўғоз»). Номаълум майдонлар ташланади. [tr] — ёш/каробка махсус кўриниши (фақат қиймат).
String marketAttrsLine(MarketDef market, String category, Map<String, Object?> attrs, String lang,
    {int maxParts = 3, String Function(String key)? tr}) {
  final parts = <String>[];
  final fields = market.fieldsFor(category);
  for (final f in fields) {
    if (parts.length >= maxParts) break;
    final stored = attrs[f.key];
    if (stored == null) continue;
    final special = _specialDisplay(f, fields, attrs, tr);
    if (special != null) {
      if (special.$2.isNotEmpty) parts.add(special.$2);
      continue;
    }
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
    {required String yes, String Function(String key)? tr}) {
  final rows = <(String, String)>[];
  final fields = market.fieldsFor(category);
  for (final f in fields) {
    final special = _specialDisplay(f, fields, attrs, tr);
    if (special != null) {
      if (special.$2.isNotEmpty) rows.add(special);
      continue;
    }
    final s = f.display(attrs[f.key], lang, yes: yes);
    if (s.isNotEmpty) rows.add((f.label(lang), s));
  }
  return rows;
}
