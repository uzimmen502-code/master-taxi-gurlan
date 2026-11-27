/// «Иш ўринлари — Вакансиялар» (эга 2026-11-28): `ads/{id}` (type `work`) нинг `vacancy` харитаси.
///
/// Ёзувчи — ФАҚАТ сервер `submitJobAd` (`functions/job_vacancy.js`); рўйхатлар ва чегаралар у ердаги
/// `SCHEDULES` / `EXPERIENCE` / `EMPLOYER_KINDS` / `LIMITS` билан АЙНАН бир хил (паритет тести қулфлайди).
/// Барчаси PROPOSED (47-банд), эга тасдиқлагунча.
class JobVacancy {
  const JobVacancy({
    required this.position,
    required this.requirements,
    this.salaryFrom,
    this.salaryTo,
    this.salaryNegotiable = false,
    this.schedule = '',
    this.experience = '',
    this.employerKind = '',
    this.employerId = '',
    this.employerName = '',
    this.employerKey = '',
    this.isFactory = false,
  });

  static const schedules = ['full_time', 'part_time', 'shift', 'remote', 'temporary'];
  static const experiences = ['none', '1', '3', '5'];
  static const employerKinds = ['business', 'restaurant', 'shop'];

  static const positionMin = 3;
  static const positionMax = 80;
  static const requirementsMin = 10;
  static const requirementsMax = 1000;
  static const salaryMax = 1000000000;

  /// Янги вакансия бош саҳифадаги «Янги эълонлар» тасмасида шунча вақт (эга: «1 кун»).
  static const newWindow = Duration(hours: 24);

  final String position;
  final String requirements;

  /// Бутун сўм (8-банд); `null` — кўрсатилмаган.
  final int? salaryFrom;
  final int? salaryTo;
  final bool salaryNegotiable;
  final String schedule;
  final String experience;
  final String employerKind;
  final String employerId;
  final String employerName;

  /// `'<kind>:<id>'` — завод саҳифаси шу калит билан ўқийди.
  final String employerKey;
  final bool isFactory;

  static String _s(Object? v) => v is String ? v.trim() : '';
  static int? _i(Object? v) => v is int && v > 0 ? v : (v is num && v > 0 && v == v.roundToDouble() ? v.toInt() : null);

  /// Бузуқ/эски ҳужжат (харита эмас ёки лавозим йўқ) — `null`: рўйхатга тушмайди.
  static JobVacancy? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final position = _s(raw['position']);
    if (position.isEmpty) return null;
    return JobVacancy(
      position: position,
      requirements: _s(raw['requirements']),
      salaryFrom: _i(raw['salaryFrom']),
      salaryTo: _i(raw['salaryTo']),
      salaryNegotiable: raw['salaryNegotiable'] == true,
      schedule: _s(raw['schedule']),
      experience: _s(raw['experience']),
      employerKind: _s(raw['employerKind']),
      employerId: _s(raw['employerId']),
      employerName: _s(raw['employerName']),
      employerKey: _s(raw['employerKey']),
      isFactory: raw['isFactory'] == true,
    );
  }

  static String employerKeyOf(String kind, String id) => kind.isEmpty || id.isEmpty ? '' : '$kind:$id';

  static String scheduleKey(String s) => 'vac_schedule_$s';
  static String experienceKey(String e) => 'vac_exp_$e';

  /// Маош ёрлиғи (3 тилда, [tr] — `context.tr`): «3 000 000 – 5 000 000 сўм», «… сўмдан», «… сўмгача»,
  /// «Келишилади». Сервер `salaryText` нинг тилли кўзгуси.
  String salaryLabel(String Function(String key) tr) {
    final f = salaryFrom;
    final t = salaryTo;
    if (salaryNegotiable || (f == null && t == null)) return tr('vac_salary_negotiable');
    final sum = tr('currency_sum');
    if (f != null && t != null) return f == t ? '${groupThousands(f)} $sum' : '${groupThousands(f)} – ${groupThousands(t)} $sum';
    if (f != null) return tr('vac_salary_from').replaceAll('{n}', groupThousands(f));
    return tr('vac_salary_to').replaceAll('{n}', groupThousands(t!));
  }

  static String groupThousands(int n) =>
      n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');

  /// Янги (≤ [newWindow]) — «Янги эълонлар» тасмаси учун.
  static bool isNew(DateTime? createdAt, DateTime now) =>
      createdAt != null && !createdAt.isAfter(now) && now.difference(createdAt) <= newWindow;

  /// `submitJobAd` учун `vacancy` харитаси (сервер яна текширади).
  static Map<String, Object?> payload({
    required String position,
    required String requirements,
    required bool negotiable,
    int? salaryFrom,
    int? salaryTo,
    required String schedule,
    required String experience,
    String districtId = '',
    String employerKind = '',
    String employerId = '',
  }) =>
      {
        'position': position.trim(),
        'requirements': requirements.trim(),
        'salaryNegotiable': negotiable,
        if (!negotiable && salaryFrom != null) 'salaryFrom': salaryFrom,
        if (!negotiable && salaryTo != null) 'salaryTo': salaryTo,
        'schedule': schedule,
        'experience': experience,
        if (districtId.isNotEmpty) 'districtId': districtId,
        if (employerKind.isNotEmpty && employerId.isNotEmpty) ...{
          'employerKind': employerKind,
          'employerId': employerId,
        },
      };

  /// Формадаги маош майдонини бутун сўмга: бўш — `null`; бўшлиқ/нуқта ажратувчилари олиб ташланади.
  /// Рақам эмас, 0 ёки чегарадан катта — `-1` (хато).
  static int? parseSalary(String raw) {
    final s = raw.replaceAll(RegExp(r'[\s.,]'), '');
    if (s.isEmpty) return null;
    final n = int.tryParse(s);
    if (n == null || n <= 0 || n > salaryMax) return -1;
    return n;
  }

  /// Форма текшируви (сервер билан бир хил) — хато матн калити ёки `null`.
  static String? validate({
    required String position,
    required String requirements,
    required bool negotiable,
    required String fromRaw,
    required String toRaw,
    required String schedule,
    required String experience,
  }) {
    final p = position.trim();
    if (p.length < positionMin || p.length > positionMax) return 'vac_err_position';
    if (!negotiable) {
      final f = parseSalary(fromRaw);
      final t = parseSalary(toRaw);
      if (f == -1 || t == -1 || (f == null && t == null) || (f != null && t != null && f > t)) return 'vac_err_salary';
    }
    if (!schedules.contains(schedule)) return 'vac_err_schedule';
    if (!experiences.contains(experience)) return 'vac_err_experience';
    final r = requirements.trim();
    if (r.length < requirementsMin || r.length > requirementsMax) return 'vac_err_requirements';
    return null;
  }
}

/// Сервер `details.code` → матн калити (`VACANCY_*`); бошқаси — `null` (чақирувчи умумий хатога тушади).
String? vacancyErrorKey(String? code) => switch (code) {
      'VACANCY_POSITION_INVALID' => 'vac_err_position',
      'VACANCY_SALARY_INVALID' => 'vac_err_salary',
      'VACANCY_SCHEDULE_INVALID' => 'vac_err_schedule',
      'VACANCY_EXPERIENCE_INVALID' => 'vac_err_experience',
      'VACANCY_REQUIREMENTS_INVALID' => 'vac_err_requirements',
      'VACANCY_EMPLOYER_INVALID' => 'vac_err_employer',
      'VACANCY_DISTRICT_INVALID' => 'vac_err_district',
      'VACANCY_REQUIRED' => 'vac_err_generic',
      _ => null,
    };
