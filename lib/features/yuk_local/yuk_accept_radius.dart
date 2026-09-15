/// Туман ичида юк: ҳайдовчи қабул радиуси (км).
///
/// `citywide` = тумандаги бутун қамров (катта радиус белгиси).
class YukAcceptRadius {
  const YukAcceptRadius._(this.valueKm, this.labelKey);

  /// Сақланадиган қиймат. `citywide` учун [citywideKm].
  final int valueKm;
  final String labelKey;

  static const citywideKm = 999;

  static const options = <YukAcceptRadius>[
    YukAcceptRadius._(5, 'yuk_local_radius_5'),
    YukAcceptRadius._(10, 'yuk_local_radius_10'),
    YukAcceptRadius._(15, 'yuk_local_radius_15'),
    YukAcceptRadius._(20, 'yuk_local_radius_20'),
    YukAcceptRadius._(50, 'yuk_local_radius_50'),
    YukAcceptRadius._(citywideKm, 'yuk_local_radius_city'),
  ];

  static const defaultKm = 20;

  static bool isCitywide(int km) => km >= citywideKm;

  static int normalize(int? raw) {
    if (raw == null || raw <= 0) return defaultKm;
    for (final o in options) {
      if (o.valueKm == raw) return raw;
    }
    if (raw >= citywideKm) return citywideKm;
    return defaultKm;
  }
}
