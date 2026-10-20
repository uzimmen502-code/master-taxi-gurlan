// «ТАЛАБ ЯДРОСИ» АДМИН ЭКРАНИ — тоза мантиқ (виджетсиз, Firebase'сиз).
//
// ҚОИДАНИ СЕРВЕР ҲАЛ ҚИЛАДИ (`functions_demand/api/core_config_admin.js`, 18 ва
// 44-банд): ёқиш учун ҳудудда ишлай оладиган таклифчи >= N, push учун чегара
// ўлчаб қўйилган бўлиши шарт. Бу файл фақат (1) сервер жавобини ўқийди,
// (2) тугмани олдиндан хира қилиб, сабабни кўрсатади, (3) чегара киритишни
// текширади. Экран қоидани ўйлаб топмайди: хира тугма хато бўлса ҳам сервер
// барибир рад этади.

/// Хира тугма сабаби.
enum CoreBlock { current, notEnoughProviders, minScoreMissing }

/// Битта ҳудуд қатори.
class CoreRegionRow {
  const CoreRegionRow({
    required this.regionId,
    required this.name,
    required this.state,
    required this.providers,
    required this.ready,
    required this.minScore,
    required this.ownConfig,
    required this.configErrors,
  });

  final String regionId;
  final String name;

  /// `off` | `shadow` | `push` | `matching_off`.
  final String state;

  /// Ҳудудда ишлай оладиган таклифчилар сони.
  final int providers;
  final bool ready;

  /// Амалдаги push чегараси (ҳудуд ёки `_all`дан), йўқ бўлса `null`.
  final double? minScore;
  final bool ownConfig;
  final List<String> configErrors;

  factory CoreRegionRow.fromMap(Map<dynamic, dynamic> m) {
    final errs = m['configErrors'];
    return CoreRegionRow(
      regionId: (m['regionId'] ?? '').toString(),
      name: (m['name'] ?? m['regionId'] ?? '').toString(),
      state: (m['state'] ?? 'off').toString(),
      providers: (m['providers'] as num?)?.toInt() ?? 0,
      ready: m['ready'] == true,
      minScore: (m['minScore'] as num?)?.toDouble(),
      ownConfig: m['ownConfig'] == true,
      configErrors: errs is List ? errs.map((e) => e.toString()).toList() : const [],
    );
  }
}

/// Аудит қатори (телефон серверда ниқобланган).
class CoreAuditEntry {
  const CoreAuditEntry({
    required this.id,
    required this.at,
    required this.actor,
    required this.regionId,
    required this.fromState,
    required this.toState,
    required this.fromMinScore,
    required this.toMinScore,
  });

  final String id;
  final DateTime? at;
  final String actor;
  final String regionId;
  final String fromState;
  final String toState;
  final double? fromMinScore;
  final double? toMinScore;

  factory CoreAuditEntry.fromMap(Map<dynamic, dynamic> m) {
    final from = m['from'] is Map ? m['from'] as Map : const {};
    final to = m['to'] is Map ? m['to'] as Map : const {};
    final at = (m['at'] as num?)?.toInt();
    return CoreAuditEntry(
      id: (m['id'] ?? '').toString(),
      at: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
      actor: (m['actor'] ?? '').toString(),
      regionId: (m['regionId'] ?? '').toString(),
      fromState: (from['state'] ?? '').toString(),
      toState: (to['state'] ?? '').toString(),
      fromMinScore: (from['minScore'] as num?)?.toDouble(),
      toMinScore: (to['minScore'] as num?)?.toDouble(),
    );
  }
}

/// `adminGetCoreOverview` жавоби.
class CoreOverview {
  const CoreOverview({
    required this.module,
    required this.mode,
    required this.minProviders,
    required this.minScoreAll,
    required this.globalKillActive,
    required this.globalKillReason,
    required this.rows,
    required this.audit,
  });

  final String module;

  /// Модул режими (`quote` | `dispatch` ...): `dispatch`да push учун чегара шарт эмас.
  final String mode;
  final int minProviders;

  /// Барча ҳудудлар учун умумий push чегараси (`service_all`).
  final double? minScoreAll;
  final bool globalKillActive;
  final String globalKillReason;
  final List<CoreRegionRow> rows;
  final List<CoreAuditEntry> audit;

  factory CoreOverview.fromMap(Map<dynamic, dynamic> m) {
    final gk = m['globalKill'] is Map ? m['globalKill'] as Map : const {};
    final rows = m['rows'];
    final audit = m['audit'];
    return CoreOverview(
      module: (m['module'] ?? 'service').toString(),
      mode: (m['mode'] ?? 'quote').toString(),
      minProviders: (m['minProviders'] as num?)?.toInt() ?? 5,
      minScoreAll: (m['minScoreAll'] as num?)?.toDouble(),
      globalKillActive: gk['active'] == true,
      globalKillReason: (gk['reason'] ?? '').toString(),
      rows: rows is List
          ? rows.whereType<Map>().map(CoreRegionRow.fromMap).toList()
          : const [],
      audit: audit is List
          ? audit.whereType<Map>().map(CoreAuditEntry.fromMap).toList()
          : const [],
    );
  }
}

/// Тугмани олдиндан хира қилиш сабаби; `null` — босиш мумкин.
/// Сабаблар тартиби серверники билан бир хил: аввал таклифчи сони, кейин чегара.
CoreBlock? blockReason(CoreRegionRow row, String target, CoreOverview o) {
  if (row.state == target) return CoreBlock.current;
  if (target == 'off') return null;
  if (row.providers < o.minProviders) return CoreBlock.notEnoughProviders;
  if (target == 'push' && o.mode != 'dispatch' && row.minScore == null) {
    return CoreBlock.minScoreMissing;
  }
  return null;
}

String stateLabel(String state) {
  switch (state) {
    case 'off':
      return 'Ўчиқ';
    case 'shadow':
      return 'Shadow';
    case 'push':
      return 'Push';
    case 'matching_off':
      return 'Matching ўчиқ';
    default:
      return state;
  }
}

/// Сервер рад этиш сабаби (`details.reason`) -> тушунарли матн; номаълум бўлса —
/// сервернинг ўз хабари.
String serverReasonText(String? reason, String serverMessage) {
  switch (reason) {
    case 'not_enough_providers':
      return 'Ҳудудда ишлай оладиган таклифчи етарли эмас';
    case 'min_score_not_calibrated':
      return 'Push чегараси ўрнатилмаган: аввал 50 мослик баҳоланиб, чегара танланади';
    default:
      return serverMessage;
  }
}

/// Чегара киритиш: `0.75` ёки `0,75`, оралиқ 0.01..1. Хато бўлса `null`
/// («90» (фоиз) жимгина қабул қилинмайди — сервер ҳам рад этади).
double? parseMinScoreInput(String raw) {
  final s = raw.trim().replaceAll(',', '.');
  if (s.isEmpty) return null;
  final n = double.tryParse(s);
  if (n == null || !n.isFinite || n < 0.01 || n > 1) return null;
  return n;
}
