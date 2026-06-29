import '../../../models/circle.dart';
import 'school_normalizer.dart';

/// Forma maydoni tavsifi (identity yoki profil).
class CircleFieldSpec {
  const CircleFieldSpec({
    required this.key,
    required this.label,
    this.number = false,
    this.required = true,
  });

  final String key;
  final String label;
  final bool number;
  final bool required;
}

/// Tipga bog'liq Circle (Davra) konfiguratsiyasi — bitta dvigatel ko'p tipni
/// qo'llashi uchun. Yangi tip qo'shish = shu yerga bitta `CircleTypeSpec`.
class CircleTypeSpec {
  const CircleTypeSpec({
    required this.type,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.identityFields,
    required this.profileFields,
  });

  final CircleType type;
  final String emoji;
  final String title;
  final String subtitle;

  /// Davrani aniqlovchi (kalit + meta) majburiy maydonlar.
  final List<CircleFieldSpec> identityFields;

  /// A'zoning tipga xos ixtiyoriy profil maydonlari (member.extra ga yoziladi).
  final List<CircleFieldSpec> profileFields;

  // ─────────────────── Kalit / sarlavha / meta ───────────────────

  /// Erkin matn → barqaror slug (raqam ustunligisiz — umumiy nomlar uchun).
  static String slug(String raw) {
    var s = raw.toLowerCase().trim();
    s = s.replaceAll(RegExp("[’'`ʼ]"), '');
    s = s
        .replaceAll(RegExp(r'[^a-z0-9а-яёўқғҳ]+', unicode: true), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return s.isEmpty ? 'x' : s;
  }

  String buildKey(Map<String, String> v) {
    switch (type) {
      case CircleType.classmates:
        return SchoolNormalizer.classCircleId(
            v['school'] ?? '', int.tryParse(v['year'] ?? '') ?? 0);
      case CircleType.coursemates:
        return 'course_${slug(v['university'] ?? '')}_'
            '${slug(v['faculty'] ?? '')}_${slug(v['group'] ?? '')}_'
            '${v['year'] ?? ''}';
      case CircleType.colleagues:
        final dept = (v['department'] ?? '').trim();
        return 'work_${slug(v['company'] ?? '')}_'
            '${dept.isEmpty ? 'all' : slug(dept)}';
      case CircleType.relatives:
        return '';
    }
  }

  String buildTitle(Map<String, String> v) {
    switch (type) {
      case CircleType.classmates:
        return '${(v['school'] ?? '').trim()}, ${v['year'] ?? ''}';
      case CircleType.coursemates:
        return '${(v['university'] ?? '').trim()}, '
            '${(v['group'] ?? '').trim()} (${v['year'] ?? ''})';
      case CircleType.colleagues:
        final dept = (v['department'] ?? '').trim();
        return dept.isEmpty
            ? (v['company'] ?? '').trim()
            : '${(v['company'] ?? '').trim()} — $dept';
      case CircleType.relatives:
        return '';
    }
  }

  Map<String, dynamic> buildMeta(Map<String, String> v) {
    final meta = <String, dynamic>{};
    for (final f in identityFields) {
      final raw = (v[f.key] ?? '').trim();
      meta[f.key] = f.number ? (int.tryParse(raw) ?? 0) : raw;
    }
    return meta;
  }

  // ─────────────────── Tip → spec ───────────────────

  static CircleTypeSpec of(CircleType type) {
    switch (type) {
      case CircleType.classmates:
        return classmates;
      case CircleType.coursemates:
        return coursemates;
      case CircleType.colleagues:
        return colleagues;
      case CircleType.relatives:
        return classmates; // relatives alohida modulda — bu yerda ishlatilmaydi
    }
  }

  static const classmates = CircleTypeSpec(
    type: CircleType.classmates,
    emoji: '🎓',
    title: 'Синфдошларим',
    subtitle: 'Мактаб + битирган йил бўйича давра',
    identityFields: [
      CircleFieldSpec(key: 'school', label: 'Мактаб * (масалан: 1-мактаб)'),
      CircleFieldSpec(
          key: 'year', label: 'Битирган йил * (масалан: 2008)', number: true),
    ],
    profileFields: [
      CircleFieldSpec(key: 'classLabel', label: 'Синф (масалан: А)', required: false),
      CircleFieldSpec(key: 'city', label: 'Ҳозирги шаҳар', required: false),
      CircleFieldSpec(key: 'job', label: 'Иш жойи', required: false),
    ],
  );

  static const coursemates = CircleTypeSpec(
    type: CircleType.coursemates,
    emoji: '🎓',
    title: 'Курсдошларим',
    subtitle: 'Университет + факультет + гуруҳ бўйича',
    identityFields: [
      CircleFieldSpec(key: 'university', label: 'Университет *'),
      CircleFieldSpec(key: 'faculty', label: 'Факультет *'),
      CircleFieldSpec(key: 'group', label: 'Гуруҳ *'),
      CircleFieldSpec(
          key: 'year', label: 'Битирган йил * (масалан: 2015)', number: true),
    ],
    profileFields: [
      CircleFieldSpec(key: 'course', label: 'Курс', required: false),
      CircleFieldSpec(key: 'city', label: 'Ҳозирги шаҳар', required: false),
      CircleFieldSpec(key: 'job', label: 'Иш жойи', required: false),
    ],
  );

  static const colleagues = CircleTypeSpec(
    type: CircleType.colleagues,
    emoji: '💼',
    title: 'Ҳамкасбларим',
    subtitle: 'Компания (+ бўлим) бўйича давра',
    identityFields: [
      CircleFieldSpec(key: 'company', label: 'Компания *'),
      CircleFieldSpec(key: 'department', label: 'Бўлим', required: false),
    ],
    profileFields: [
      CircleFieldSpec(key: 'position', label: 'Лавозим', required: false),
      CircleFieldSpec(key: 'email', label: 'Email', required: false),
    ],
  );
}
