/// «AVA Супермаркет» ўлчов бирликлари (эга 2026-11-28: «ҳақиқий маҳсулотлар учун дона, кг, литр ва бошқа ўлчов
/// бирликлар керак»; рўйхат PROPOSED: + g, ml, box, m).
///
/// ЯГОНА МАНБА — `functions/supermarket_units.json` (сервер `supermarket.js` UNITS/UNIT_LABELS шу файлдан ўқийди ва
/// текширади). Бу ер — мижоз нусхаси; `test/features/supermarket/sm_units_test.dart` уни JSON ва `assets/lang`
/// `sm_unit_<id>` калитлари билан солиштиради (ажралиб кетса тест йиқилади).
///
/// Номаълум бирлик (эски ҳужжат матни «дона», келажакдаги янги id) — ҲЕЧ НАРСА кўрсатилмайди, нотўғри бирлик эмас.
library;

/// Сервер тартибида (supermarket_units.json `units[].id`).
const kSmUnitIds = <String>['kg', 'l', 'piece', 'pack', 'bunch', 'g', 'ml', 'box', 'm'];

/// Шартномадаги бирликлар (тўплам).
const kSmUnits = <String>{'kg', 'l', 'piece', 'pack', 'bunch', 'g', 'ml', 'box', 'm'};

/// 3 тилдаги ёрлиқ (админ экранлари учун; харидор илова — `sm_unit_<id>` lang калити, қиймати бир хил).
const kSmUnitLabels = <String, Map<String, String>>{
  'kg': {'uz_Cyrl': 'кг', 'uz_Latn': 'kg', 'ru': 'кг'},
  'l': {'uz_Cyrl': 'л', 'uz_Latn': 'l', 'ru': 'л'},
  'piece': {'uz_Cyrl': 'дона', 'uz_Latn': 'dona', 'ru': 'шт'},
  'pack': {'uz_Cyrl': 'қадоқ', 'uz_Latn': 'qadoq', 'ru': 'уп.'},
  'bunch': {'uz_Cyrl': 'боғ', 'uz_Latn': 'boğ', 'ru': 'пучок'},
  'g': {'uz_Cyrl': 'г', 'uz_Latn': 'g', 'ru': 'г'},
  'ml': {'uz_Cyrl': 'мл', 'uz_Latn': 'ml', 'ru': 'мл'},
  'box': {'uz_Cyrl': 'қути', 'uz_Latn': 'quti', 'ru': 'кор.'},
  'm': {'uz_Cyrl': 'м', 'uz_Latn': 'm', 'ru': 'м'},
};

/// Маълум бирлик → ўзи; номаълум/бўш → '' (кўрсатилмайди).
String smKnownUnit(Object? raw) => raw is String && kSmUnits.contains(raw) ? raw : '';

/// Админ экранлари учун ёрлиқ (сукут uz_Cyrl); номаълум → '' (хом id ҳам кўрсатилмайди).
String smUnitText(String unit, [String lang = 'uz_Cyrl']) {
  final m = kSmUnitLabels[unit];
  if (m == null) return '';
  return m[lang] ?? m['uz_Cyrl'] ?? '';
}
