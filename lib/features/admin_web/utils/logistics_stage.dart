// Админ: AVA Logistics ишга тушириш босқичи (D8, 42-банд) — `module_config/
// logistics_all` (`logistics.stage`, `logistics.testerIds`) ни ҳимояланган
// ўқиш ва телефон киритишни текшириш. Ёзув — фақат `adminSetLogisticsStage`
// (сервер, audit). Бу ерда фақат КЎРСАТИШ учун.

/// Серверда рухсат этилган босқичлар (`core/logistics.js` → `STAGE`).
const kLogisticsStages = <String>['off', 'internal', 'pilot', 'public'];

/// Босқич → админ матни.
const kLogisticsStageLabels = <String, String>{
  'off': 'OFF — ёпиқ (ҳеч ким; янги LEG қабул қилиш ҳам тўхтайди)',
  'internal': 'INTERNAL — фақат синовчилар',
  'pilot': 'PILOT — фақат синовчилар (сервер ҳозир INTERNAL каби ҳисоблайди)',
  'public': 'PUBLIC — ҳамма',
};

class LogisticsStageConfig {
  const LogisticsStageConfig({required this.stage, required this.testerIds, required this.exists});

  final String stage;
  final List<String> testerIds;

  /// `module_config/logistics_all` ҳужжати бор-йўқлиги (йўқ бўлса сервер ёзмайди).
  final bool exists;

  /// Сервер `stageOf` билан бир хил: номаълум/йўқ қиймат — `internal`.
  static LogisticsStageConfig fromDoc(Map<String, dynamic>? doc, {required bool exists}) {
    final lg = doc?['logistics'];
    final map = lg is Map ? lg : const {};
    final s = map['stage'];
    final stage = s is String && kLogisticsStages.contains(s) ? s : 'internal';
    final raw = map['testerIds'];
    final ids = raw is List ? [for (final e in raw) e.toString()] : <String>[];
    return LogisticsStageConfig(stage: stage, testerIds: ids, exists: exists);
  }
}

/// Телефон матни → серверга юбориладиган рақамлар (9 ёки `998`+9 хона);
/// нотўғри бўлса `null`. Канон шаклни сервер ўзи қуради.
String? normalizeTesterPhone(String text) {
  final d = text.replaceAll(RegExp(r'\D'), '');
  if (d.length == 9) return d;
  if (d.length == 12 && d.startsWith('998')) return d;
  return null;
}

/// Рўйхатда шу телефон бор-йўқлиги (9 хонали ва `998…` шакллар тенг).
bool testerListContains(List<String> ids, String phone) {
  String canon(String v) {
    final d = v.replaceAll(RegExp(r'\D'), '');
    return d.length == 9 ? '998$d' : d;
  }

  final c = canon(phone);
  return ids.any((e) => canon(e) == c);
}
