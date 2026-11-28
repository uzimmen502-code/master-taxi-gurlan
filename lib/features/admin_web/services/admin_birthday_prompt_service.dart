import 'package:cloud_functions/cloud_functions.dart';

/// «Туғилган кунингизни киритинг» ҳафталик эслатмаси — админ манбаи (сервер `functions/birthday_prompt.js`).
/// Ўқиш ва ёзиш ФАҚАТ callable орқали (`settings/birthday_prompt` — мижозга ёпиқ, телефонлар бор):
/// `adminGetBirthdayPromptSettings()`, `adminSetBirthdayPromptSettings({settings, expectedVersion, reason?})` (admin_audit).
abstract class AdminBirthdayPromptApi {
  Future<BirthdayPromptAdminState> load();
  Future<void> save(BirthdayPromptSettings s, {required int expectedVersion, String reason = ''});
}

class FirebaseAdminBirthdayPromptApi implements AdminBirthdayPromptApi {
  FirebaseAdminBirthdayPromptApi({FirebaseFunctions? functions}) : _fns = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _fns;

  @override
  Future<BirthdayPromptAdminState> load() async {
    final r = (await _fns.httpsCallable('adminGetBirthdayPromptSettings').call<Object?>(const {})).data;
    return BirthdayPromptAdminState.fromMap(r is Map ? Map<String, dynamic>.from(r) : const {});
  }

  @override
  Future<void> save(BirthdayPromptSettings s, {required int expectedVersion, String reason = ''}) =>
      _fns.httpsCallable('adminSetBirthdayPromptSettings').call<Object?>({
        'settings': s.toMap(),
        'expectedVersion': expectedVersion,
        if (reason.trim().isNotEmpty) 'reason': reason.trim(),
      });
}

/// Сервер `SETTINGS_KEYS` (stage, internalPhones, pilotDistrictIds, maxSends). Ҳужжат йўқ = OFF.
class BirthdayPromptSettings {
  const BirthdayPromptSettings({
    this.stage = 'off',
    this.internalPhones = const [],
    this.pilotDistrictIds = const [],
    this.maxSends = kBirthdayPromptDefaultMaxSends,
    this.version = 0,
  });

  final String stage;
  final List<String> internalPhones;
  final List<String> pilotDistrictIds;
  final int maxSends;

  /// Фақат кўрсатиш/версия текшируви (сервер ҳисоблайди).
  final int version;

  factory BirthdayPromptSettings.fromMap(Map<String, dynamic> d) {
    List<String> l(Object? v) => [if (v is List) for (final x in v) '$x'];
    final stage = d['stage'];
    return BirthdayPromptSettings(
      stage: kBirthdayPromptStages.contains(stage) ? stage as String : 'off',
      internalPhones: l(d['internalPhones']),
      pilotDistrictIds: l(d['pilotDistrictIds']),
      maxSends: d['maxSends'] is num ? (d['maxSends'] as num).toInt() : kBirthdayPromptDefaultMaxSends,
      version: d['version'] is num ? (d['version'] as num).toInt() : 0,
    );
  }

  Map<String, Object> toMap() => {
        'stage': stage,
        'internalPhones': internalPhones,
        'pilotDistrictIds': pilotDistrictIds,
        'maxSends': maxSends,
      };
}

/// Охирги тарқатиш (birthday_prompt_runs): ҳафта, босқич, тугаганми, статистика (sent, scanned, …).
class BirthdayPromptRun {
  const BirthdayPromptRun({required this.id, required this.week, required this.stage, required this.done, required this.stats});

  final String id;
  final String week;
  final String stage;
  final bool done;
  final Map<String, int> stats;

  factory BirthdayPromptRun.fromMap(Map<String, dynamic> d) {
    final s = d['stats'] is Map ? d['stats'] as Map : const {};
    return BirthdayPromptRun(
      id: '${d['id'] ?? ''}',
      week: '${d['week'] ?? ''}',
      stage: '${d['stage'] ?? ''}',
      done: d['done'] == true,
      stats: {for (final e in s.entries) if (e.value is num) '${e.key}': (e.value as num).toInt()},
    );
  }
}

class BirthdayPromptAdminState {
  const BirthdayPromptAdminState({required this.settings, this.runs = const []});

  final BirthdayPromptSettings settings;
  final List<BirthdayPromptRun> runs;

  factory BirthdayPromptAdminState.fromMap(Map<String, dynamic> d) => BirthdayPromptAdminState(
        settings: BirthdayPromptSettings.fromMap(d['settings'] is Map ? Map<String, dynamic>.from(d['settings'] as Map) : const {}),
        runs: [
          if (d['runs'] is List)
            for (final r in d['runs'] as List)
              if (r is Map) BirthdayPromptRun.fromMap(Map<String, dynamic>.from(r)),
        ],
      );
}

const kBirthdayPromptStages = <String>['off', 'internal', 'pilot', 'public'];

/// Сервер сукути (PROPOSED, эга тасдиқлаши керак): 4 ҳафта — кейин тўхтайди.
const kBirthdayPromptDefaultMaxSends = 4;

/// Форма хатолари (сервер `validateSettings` нусхаси — тугма учун; ҳақиқий текширув серверда). Кирилл (админ).
List<String> birthdayPromptProblems(BirthdayPromptSettings s) {
  final phoneRe = RegExp(r'^998\d{9}$');
  final districtRe = RegExp(r'^[a-z0-9_-]{2,40}$');
  return [
    if (!kBirthdayPromptStages.contains(s.stage)) 'Босқич нотўғри.',
    if (s.internalPhones.length > 50 || !s.internalPhones.every(phoneRe.hasMatch) || s.internalPhones.toSet().length != s.internalPhones.length)
      'Ички синов рақамлари: 998XXXXXXXXX, 50 тагача, такрорсиз.',
    if (s.pilotDistrictIds.length > 30 || !s.pilotDistrictIds.every(districtRe.hasMatch) || s.pilotDistrictIds.toSet().length != s.pilotDistrictIds.length)
      'Пилот туман ID лари: 30 тагача, кичик лотин ҳарф/рақам, такрорсиз.',
    if (s.maxSends < 1 || s.maxSends > 12) 'Эслатмалар сони 1–12 бўлсин.',
    if (s.stage == 'pilot' && s.pilotDistrictIds.isEmpty && s.internalPhones.isEmpty) 'Пилот учун туман ёки синов рақами киритинг.',
  ];
}
