/// `settings/splash` — ochilish animatsiyasi tagline roʻyxati.
class SplashSettings {
  const SplashSettings({
    required this.taglines,
    required this.enabled,
  });

  static const List<String> defaultTaglines = [
    'ТАНИШУВ',
    'АРЗОН',
    'ҚУЛАЙ',
    'ТЕЗ',
    'ИШОНЧЛИ',
    '6 ХИЗМАТ',
  ];

  static const int maxTaglines = 24;
  static const int maxTaglineLength = 40;

  final List<String> taglines;
  final bool enabled;

  static SplashSettings get defaults =>
      const SplashSettings(taglines: defaultTaglines, enabled: true);

  factory SplashSettings.fromMap(Map<String, dynamic>? data) {
    if (data == null) return defaults;
    final raw = data['taglines'];
    final list = <String>[];
    if (raw is List) {
      for (final item in raw) {
        final text = (item ?? '').toString().trim();
        if (text.isNotEmpty) list.add(text);
      }
    }
    return SplashSettings(
      taglines: list.isEmpty ? defaultTaglines : list,
      enabled: data['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap({String? updatedBy}) => {
        'taglines': taglines,
        'enabled': enabled,
        if (updatedBy != null) 'updatedBy': updatedBy,
      };

  static List<String> sanitizeTaglines(List<String> input) {
    final out = <String>[];
    for (final raw in input) {
      final text = raw.trim();
      if (text.isEmpty) continue;
      out.add(text.length > maxTaglineLength
          ? text.substring(0, maxTaglineLength)
          : text);
      if (out.length >= maxTaglines) break;
    }
    return out;
  }
}
