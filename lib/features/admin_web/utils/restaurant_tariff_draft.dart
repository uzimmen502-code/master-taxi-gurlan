// Кафе-ресторан етказиш тарифи — админ формасининг СОФ мантиқи (тестланади):
// `settings/restaurant_delivery` → қоралама → валидация → callable payload
// (`adminSetRestaurantDeliveryPrices`). Рақамлар — эга қарори; форма
// стандарт қиймат ўйлаб топмайди (бўш майдон = сервердаги жорий/стандарт).
// Мантиқ сервер билан бир хил: base > 0, perKm ≥ 0 (бутун сўм), тун 1..3,
// соат 0..23, йўл коэф. 1..2, maxKm 1..100; мintaqa калитлари —
// `local_taxi.REGION_KEYS` (`TaxiPriceRegion` билан паритет).

/// Мintaqa калитлари ва ёрлиқлари (сервер `REGION_KEYS` билан бир хил).
const kRestaurantTariffRegions = <String, String>{
  'default': 'Default (бошқа ҳудудлар)',
  'tashkent': 'Тошкент',
  'xorazm': 'Хоразм',
  'samarqand': 'Самарқанд',
  'namangan': 'Наманган',
};

class RestaurantRegionDraft {
  RestaurantRegionDraft({this.enabled = false, this.base = '', this.perKm = '', this.nightCoef = '', this.maxKm = ''});

  bool enabled;
  String base;
  String perKm;
  String nightCoef;
  String maxKm;

  factory RestaurantRegionDraft.fromMap(Map<String, dynamic>? m) {
    if (m == null) return RestaurantRegionDraft();
    return RestaurantRegionDraft(
      enabled: true,
      base: _numText(m['base']),
      perKm: _numText(m['perKm']),
      nightCoef: _numText(m['nightCoef']),
      maxKm: _numText(m['maxKm']),
    );
  }
}

class RestaurantTariffDraft {
  RestaurantTariffDraft({
    this.base = '',
    this.perKm = '',
    this.nightCoef = '',
    this.nightStart = '',
    this.nightEnd = '',
    this.roadFactor = '',
    this.maxKm = '',
    Map<String, RestaurantRegionDraft>? regions,
    this.version = 0,
    this.updatedBy = '',
  }) : regions = regions ?? {for (final k in kRestaurantTariffRegions.keys) k: RestaurantRegionDraft()};

  String base;
  String perKm;
  String nightCoef;
  String nightStart;
  String nightEnd;
  String roadFactor;
  String maxKm;
  final Map<String, RestaurantRegionDraft> regions;
  final int version;
  final String updatedBy;

  /// Сервердаги ҳужжатдан (`null` — ҳали созланмаган → ҳамма майдон бўш).
  factory RestaurantTariffDraft.fromDoc(Map<String, dynamic>? d) {
    final data = d ?? const <String, dynamic>{};
    final rawRegions = data['regions'];
    return RestaurantTariffDraft(
      base: _numText(data['base']),
      perKm: _numText(data['perKm']),
      nightCoef: _numText(data['nightCoef']),
      nightStart: _numText(data['nightStart']),
      nightEnd: _numText(data['nightEnd']),
      roadFactor: _numText(data['roadFactor']),
      maxKm: _numText(data['maxKm']),
      regions: {
        for (final k in kRestaurantTariffRegions.keys)
          k: RestaurantRegionDraft.fromMap(
            rawRegions is Map && rawRegions[k] is Map ? Map<String, dynamic>.from(rawRegions[k] as Map) : null,
          ),
      },
      version: (data['version'] as num?)?.toInt() ?? 0,
      updatedBy: (data['updatedBy'] ?? '') as String,
    );
  }

  bool get isConfigured => version > 0;

  /// Хатолар (матн) — бўш рўйхат = юбориш мумкин.
  List<String> validate() {
    final errs = <String>[];
    void prices(String label, String base, String perKm, String nightCoef, String maxKm, {required bool required}) {
      final b = int.tryParse(base.trim());
      final p = int.tryParse(perKm.trim());
      if (required || base.trim().isNotEmpty || perKm.trim().isNotEmpty) {
        if (b == null || b <= 0 || b > 10000000) errs.add('$label: базавий нарх — бутун сўм, > 0');
        if (p == null || p < 0 || p > 10000000) errs.add('$label: ҳар км нархи — бутун сўм, ≥ 0');
      }
      if (nightCoef.trim().isNotEmpty) {
        final c = _parseDouble(nightCoef);
        if (c == null || c < 1 || c > 3) errs.add('$label: тун коэффициенти 1..3');
      }
      if (maxKm.trim().isNotEmpty) {
        final m = int.tryParse(maxKm.trim());
        if (m == null || m < 1 || m > 100) errs.add('$label: макс. масофа 1..100 км');
      }
    }

    // Умумий тун коэффициенти бу формада ТАҲРИРЛАНМАЙДИ ( `adminSetRestaurantFeeSettings`
    // — ягона таҳрирловчи) — шунинг учун текширилмайди ҳам, юборилмайди ҳам.
    prices('Умумий', base, perKm, '', maxKm, required: true);
    for (final h in [('тун бошланиши', nightStart), ('тун тугаши', nightEnd)]) {
      if (h.$2.trim().isEmpty) continue;
      final v = int.tryParse(h.$2.trim());
      if (v == null || v < 0 || v > 23) errs.add('Умумий: ${h.$1} — соат 0..23');
    }
    if (roadFactor.trim().isNotEmpty) {
      final rf = _parseDouble(roadFactor);
      if (rf == null || rf < 1 || rf > 2) errs.add('Умумий: йўл коэффициенти 1..2');
    }
    for (final e in regions.entries) {
      final r = e.value;
      if (!r.enabled) continue;
      prices(kRestaurantTariffRegions[e.key] ?? e.key, r.base, r.perKm, r.nightCoef, r.maxKm, required: true);
    }
    return errs;
  }

  /// `adminSetRestaurantDeliveryPrices` учун — фақат тўлдирилган майдонлар,
  /// рақамлар сон сифатида (сервер қайта текширади).
  ///
  /// Умумий `nightCoef` ЮБОРИЛМАЙДИ: сервер уни юборилмаса транзакция ичида
  /// ўқиган жорий қийматда қолдиради (`cur.nightCoef`), шу сабабли бу форма
  /// «AVA ҳақи» картасидаги янгироқ қийматни ҳеч қачон босиб ўтолмайди.
  /// ([nightCoef] майдони фақат кўрсатиш учун.) Ҳудуд `nightCoef`лари — бошқа
  /// майдон, ўзгармайди.
  Map<String, dynamic> toPayload({String reason = ''}) {
    final out = <String, dynamic>{
      'base': int.parse(base.trim()),
      'perKm': int.parse(perKm.trim()),
      'reason': reason.trim(),
    };
    if (nightStart.trim().isNotEmpty) out['nightStart'] = int.parse(nightStart.trim());
    if (nightEnd.trim().isNotEmpty) out['nightEnd'] = int.parse(nightEnd.trim());
    if (roadFactor.trim().isNotEmpty) out['roadFactor'] = _parseDouble(roadFactor);
    if (maxKm.trim().isNotEmpty) out['maxKm'] = int.parse(maxKm.trim());
    final regionsOut = <String, dynamic>{};
    for (final e in regions.entries) {
      final r = e.value;
      if (!r.enabled) continue;
      final m = <String, dynamic>{'base': int.parse(r.base.trim()), 'perKm': int.parse(r.perKm.trim())};
      if (r.nightCoef.trim().isNotEmpty) m['nightCoef'] = _parseDouble(r.nightCoef);
      if (r.maxKm.trim().isNotEmpty) m['maxKm'] = int.parse(r.maxKm.trim());
      regionsOut[e.key] = m;
    }
    out['regions'] = regionsOut;
    return out;
  }
}

/// Сон → майдон матни: бутун (шу жумладан `23.0`) → `23`, коэффициент → `1.5`.
String _numText(dynamic v) {
  if (v is int) return '$v';
  if (v is num) return v == v.roundToDouble() ? '${v.toInt()}' : '$v';
  return '';
}

double? _parseDouble(String s) => double.tryParse(s.trim().replaceAll(',', '.'));
