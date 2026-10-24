import '../../../models/circle.dart';
import 'school_normalizer.dart';

/// Forma maydoni tavsifi (identity yoki profil).
class CircleFieldSpec {
  const CircleFieldSpec({
    required this.key,
    required this.labelKey,
    this.number = false,
    this.required = true,
  });

  final String key;

  /// l10n kaliti (ekranda `context.tr(labelKey)`); `key` — ma'lumot kaliti.
  final String labelKey;
  final bool number;
  final bool required;
}

/// Tipga bog'liq Circle (Davra) konfiguratsiyasi — bitta dvigatel ko'p tipni
/// qo'llashi uchun. Yangi tip qo'shish = shu yerga bitta `CircleTypeSpec`.
class CircleTypeSpec {
  const CircleTypeSpec({
    required this.type,
    required this.emoji,
    required this.titleKey,
    required this.subtitleKey,
    required this.identityFields,
    required this.profileFields,
  });

  final CircleType type;
  final String emoji;

  /// l10n kalitlari (ekranda `context.tr(titleKey)` / `context.tr(subtitleKey)`).
  final String titleKey;
  final String subtitleKey;

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
    titleKey: 'circ_classmates_title',
    subtitleKey: 'circ_classmates_subtitle',
    identityFields: [
      CircleFieldSpec(key: 'school', labelKey: 'circ_f_school'),
      CircleFieldSpec(
          key: 'year', labelKey: 'circ_f_grad_year_2008', number: true),
    ],
    profileFields: [
      CircleFieldSpec(
          key: 'classLabel', labelKey: 'circ_f_class_label', required: false),
      CircleFieldSpec(key: 'city', labelKey: 'circ_f_city', required: false),
      CircleFieldSpec(key: 'job', labelKey: 'circ_f_job', required: false),
    ],
  );

  static const coursemates = CircleTypeSpec(
    type: CircleType.coursemates,
    emoji: '🎓',
    titleKey: 'circ_coursemates_title',
    subtitleKey: 'circ_coursemates_subtitle',
    identityFields: [
      CircleFieldSpec(key: 'university', labelKey: 'circ_f_university'),
      CircleFieldSpec(key: 'faculty', labelKey: 'circ_f_faculty'),
      CircleFieldSpec(key: 'group', labelKey: 'circ_f_group'),
      CircleFieldSpec(
          key: 'year', labelKey: 'circ_f_grad_year_2015', number: true),
    ],
    profileFields: [
      CircleFieldSpec(key: 'course', labelKey: 'circ_f_course', required: false),
      CircleFieldSpec(key: 'city', labelKey: 'circ_f_city', required: false),
      CircleFieldSpec(key: 'job', labelKey: 'circ_f_job', required: false),
    ],
  );

  static const colleagues = CircleTypeSpec(
    type: CircleType.colleagues,
    emoji: '💼',
    titleKey: 'circ_colleagues_title',
    subtitleKey: 'circ_colleagues_subtitle',
    identityFields: [
      CircleFieldSpec(key: 'company', labelKey: 'circ_f_company'),
      CircleFieldSpec(
          key: 'department', labelKey: 'circ_f_department', required: false),
    ],
    profileFields: [
      CircleFieldSpec(
          key: 'position', labelKey: 'circ_f_position', required: false),
      CircleFieldSpec(key: 'email', labelKey: 'circ_f_email', required: false),
    ],
  );
}
