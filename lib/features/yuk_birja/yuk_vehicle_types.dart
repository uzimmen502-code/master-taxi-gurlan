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

const List<YukVehicleType> kYukVehicleTypes = [
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

String yukVehicleLabelKey(String value) {
  final code = normalizeYukVehicleType(value);
  for (final t in kYukVehicleTypes) {
    if (t.value == code) return t.labelKey;
  }
  return 'yuk_vehicle_other';
}
