import 'package:cloud_functions/cloud_functions.dart';

/// «Туғилган кунингизни киритинг» эслатмаси (4 кун кунига бир марта → 7 кун танаффус → ҳар якшанба) — админ манбаи (сервер `functions/birthday_prompt.js`).
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

/// Сервер `SETTINGS_KEYS` (stage, internalPhones, pilotDistrictIds, dailyCount, weeklySunday). Ҳужжат йўқ = OFF.
class BirthdayPromptSettings {
  const BirthdayPromptSettings({
    this.stage = 'off',
    this.internalPhones = const [],
    this.pilotDistrictIds = const [],
    this.dailyCount = kBirthdayPromptDefaultDailyCount,
    this.weeklySunday = true,
    this.version = 0,
  });

  final String stage;
  final List<String> internalPhones;
  final List<String> pilotDistrictIds;

  /// 1-фаза: биринчи N кунда кунига бир марта (эга 2026-11-28: 4).
  final int dailyCount;

  /// 2-фаза: 7 кун танаффусдан кейин ҳар якшанба (эга 2026-11-28: ёқиқ), чегарасиз.
  final bool weeklySunday;

  /// Фақат кўрсатиш/версия текшируви (сервер ҳисоблайди).
  final int version;

  factory BirthdayPromptSettings.fromMap(Map<String, dynamic> d) {
    List<String> l(Object? v) => [if (v is List) for (final x in v) '$x'];
    final stage = d['stage'];
    return BirthdayPromptSettings(
      stage: kBirthdayPromptStages.contains(stage) ? stage as String : 'off',
      internalPhones: l(d['internalPhones']),
      pilotDistrictIds: l(d['pilotDistrictIds']),
      dailyCount: d['dailyCount'] is num ? (d['dailyCount'] as num).toInt() : kBirthdayPromptDefaultDailyCount,
      weeklySunday: d['weeklySunday'] is bool ? d['weeklySunday'] as bool : true,
      version: d['version'] is num ? (d['version'] as num).toInt() : 0,
    );
  }

  Map<String, Object> toMap() => {
        'stage': stage,
        'internalPhones': internalPhones,
        'pilotDistrictIds': pilotDistrictIds,
        'dailyCount': dailyCount,
        'weeklySunday': weeklySunday,
      };
}

/// Охирги тарқатиш (birthday_prompt_runs/{day}_{stage}): кун, ҳафта, босқич, тугаганми, статистика (sent, sentDaily, sentWeekly, scanned, …).
class BirthdayPromptRun {
  const BirthdayPromptRun({required this.id, this.day = '', required this.week, required this.stage, required this.done, required this.stats});

  final String id;
  final String day;
  final String week;
  final String stage;
  final bool done;
  final Map<String, int> stats;

  factory BirthdayPromptRun.fromMap(Map<String, dynamic> d) {
    final s = d['stats'] is Map ? d['stats'] as Map : const {};
    return BirthdayPromptRun(
      id: '${d['id'] ?? ''}',
      day: '${d['day'] ?? ''}',
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

/// Сервер сукути (эга 2026-11-28: «4 кун давомида кунига бир мартада»). Чегара 1–14.
const kBirthdayPromptDefaultDailyCount = 4;
const kBirthdayPromptDailyCountMin = 1;
const kBirthdayPromptDailyCountMax = 14;

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
    if (s.dailyCount < kBirthdayPromptDailyCountMin || s.dailyCount > kBirthdayPromptDailyCountMax)
      'Кунлик эслатмалар сони $kBirthdayPromptDailyCountMin–$kBirthdayPromptDailyCountMax бўлсин.',
    if (s.stage == 'pilot' && s.pilotDistrictIds.isEmpty && s.internalPhones.isEmpty) 'Пилот учун туман ёки синов рақами киритинг.',
  ];
}
