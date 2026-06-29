/// Maktab nomini (erkin matn) barqaror kalitga aylantiradi — avto-qo'shilish
/// uchun deterministik davra ID hosil qilish maqsadida.
///
/// Gurlan maktablari asosan raqamli ("1-maktab", "1 son maktab",
/// "Gurlan 1-maktab") → hammasi `school-1` ga keladi. Raqamsiz (litsey/nomli)
/// bo'lsa — qolgan so'zlardan slug.
///
/// Eslatma: erkin matnda 100% dublikatsizlik bo'lmaydi (imlo xatolari). Buni
/// UI'dagi "mavjud davra taklifi" qadami va keyinchalik admin "birlashtirish"
/// asbobi kamaytiradi.
class SchoolNormalizer {
  SchoolNormalizer._();

  static const _noise = <String>[
    'umumiy', 'umumta', 'umumtalim', 'maktabi', 'maktab', 'sonli', 'son',
    'ortacha', 'orta', 'school', 'shkola', 'litsey', 'lyceum', 'kollej',
    'college', 'imeni', 'nomli', 'nomidagi', 'tuman', 'shahar', 'qishloq',
    'мактаби', 'мактаб', 'сонли', 'сон', 'умумий', 'умумта', 'ўрта', 'урта',
    'школа', 'лицей', 'коллеж', 'номли', 'номидаги', 'туман', 'шаҳар', 'қишлоқ',
  ];

  /// Maktab matnidan barqaror kalit. Masalan: "Gurlan 1-son maktab" → "school-1".
  static String normalizeKey(String raw) {
    var s = raw.toLowerCase().trim();
    // Apostrof variantlari (oʻ/o' → o).
    s = s.replaceAll(RegExp("[’'`ʼ]"), '');
    // Yil ko'rinishidagi 4 xonali sonlarni olib tashlaymiz (19xx/20xx).
    s = s.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ');
    for (final w in _noise) {
      s = s.replaceAll(w, ' ');
    }
    // Maktab raqami bo'lsa — eng ishonchli kalit.
    final num = RegExp(r'\d+').firstMatch(s);
    if (num != null) {
      return 'school-${int.parse(num.group(0)!)}';
    }
    // Raqamsiz — qolgan harflardan slug.
    final slug = s
        .replaceAll(RegExp(r'[^a-z0-9а-яёўқғҳ]+', unicode: true), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'school' : slug;
  }

  /// Sinf davrasining deterministik ID'si: `class_{normalizedSchool}_{year}`.
  static String classCircleId(String school, int year) =>
      'class_${normalizeKey(school)}_$year';
}
