/// Юк / машина эълони ва фильтр учун бир хил машина турлари.
///
/// [labelKey] — `AppLocalizations` калити (`assets/lang/*.json`).
class YukVehicleType {
  const YukVehicleType(this.value, this.labelKey);

  /// Барқарор код (сақлаш / фильтр / Smart Match).
  final String value;

  /// Кўрсатиш учун i18n калити.
  final String labelKey;
}

/// Фақат «Туман ичида» (шаҳарлараро учун мос эмас).
const Set<String> kYukLocalOnlyVehicleValues = {'moto', 'traktor'};

const List<YukVehicleType> kYukVehicleTypes = [
  // Доимий биринчи: Юк Мотоцикли (Туман ичида рўйхат + танлов).
  YukVehicleType('moto', 'yuk_vehicle_moto'),
  YukVehicleType('traktor', 'yuk_vehicle_traktor'),
  YukVehicleType('fura', 'yuk_vehicle_fura'),
  YukVehicleType('ref', 'yuk_vehicle_ref'),
  YukVehicleType('isoterm', 'yuk_vehicle_isoterm'),
  YukVehicleType('bort', 'yuk_vehicle_bort'),
  YukVehicleType('samosval', 'yuk_vehicle_samosval'),
  YukVehicleType('gazel', 'yuk_vehicle_gazel'),
  YukVehicleType('labo', 'yuk_vehicle_labo'),
  YukVehicleType('isuzu', 'yuk_vehicle_isuzu'),
  YukVehicleType('furgon', 'yuk_vehicle_furgon'),
  YukVehicleType('container', 'yuk_vehicle_container'),
  YukVehicleType('cisterna', 'yuk_vehicle_cisterna'),
  YukVehicleType('avtovoz', 'yuk_vehicle_avtovoz'),
  YukVehicleType('tral', 'yuk_vehicle_tral'),
  YukVehicleType('manipulator', 'yuk_vehicle_manipulator'),
  YukVehicleType('kran', 'yuk_vehicle_kran'),
  YukVehicleType('evac', 'yuk_vehicle_evac'),
  YukVehicleType('shalanda', 'yuk_vehicle_shalanda'),
  YukVehicleType('pickup', 'yuk_vehicle_pickup'),
  YukVehicleType('other', 'yuk_vehicle_other'),
];

/// Туман ичида: тўлиқ рўйхат (moto биринчи).
List<YukVehicleType> yukVehicleTypesForLocal() => kYukVehicleTypes;

/// Шаҳарлараро: faqat йўл учун мос турлар (moto/traktor йўқ).
List<YukVehicleType> yukVehicleTypesForIntercity() => kYukVehicleTypes
    .where((t) => !kYukLocalOnlyVehicleValues.contains(t.value))
    .toList(growable: false);

/// Туман ичида яқин рўйхатда доимий устунлик (кичик → аввал).
int yukVehicleListPriority(String raw) {
  final code = normalizeYukVehicleType(raw);
  if (code == 'moto') return 0;
  return 1;
}

/// Эски кириллча қийматлар → янги барқарор код.
const Map<String, String> kYukVehicleLegacyMap = {
  'фура': 'fura',
  'рефрижератор': 'ref',
  'изотерм': 'isoterm',
  'борт': 'bort',
  'самосвал': 'samosval',
  'газель': 'gazel',
  'лабо': 'labo',
  'labo': 'labo',
  'исузу': 'isuzu',
  'исудзу': 'isuzu',
  'isuzi': 'isuzu',
  'isuzu': 'isuzu',
  'фургон': 'furgon',
  'контейнеровоз': 'container',
  'цистерна': 'cisterna',
  'автовоз': 'avtovoz',
  'трал': 'tral',
  'манипулятор': 'manipulator',
  'кран': 'kran',
  'эвакуатор': 'evac',
  'шаланда': 'shalanda',
  'пикап': 'pickup',
  'юк мотоцикли': 'moto',
  'юк мотоцикл': 'moto',
  'мотоцикл': 'moto',
  'moto': 'moto',
  'трактор': 'traktor',
  'traktor': 'traktor',
  'бошқа': 'other',
};

String normalizeYukVehicleType(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return 'fura';
  if (kYukVehicleLegacyMap.containsKey(v)) return kYukVehicleLegacyMap[v]!;
  for (final t in kYukVehicleTypes) {
    if (t.value == v) return v;
  }
  return 'other';
}

/// Шаҳарлараро сақлаш: local-only турларни fura га айлантиради.
String normalizeYukVehicleTypeForIntercity(String raw) {
  final code = normalizeYukVehicleType(raw);
  if (kYukLocalOnlyVehicleValues.contains(code)) return 'fura';
  return code;
}

String yukVehicleLabelKey(String value) {
  final code = normalizeYukVehicleType(value);
  for (final t in kYukVehicleTypes) {
    if (t.value == code) return t.labelKey;
  }
  return 'yuk_vehicle_other';
}
