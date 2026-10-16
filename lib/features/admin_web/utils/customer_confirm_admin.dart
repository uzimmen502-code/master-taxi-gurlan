// Админ: «Мижоз тасдиғи» (D2/D7) — модуллар бўйича ишга тушириш босқичи ва
// синовчилар. Сервер (default, us-central1): `adminGetCustomerConfirmation`
// (ўқиш) ва `adminSetCustomerConfirmation` (ёзув, audit). Қоида ва ҳолат —
// серверда; бу ерда фақат жавобни ўқиш (ҳимояли: майдон йўқ/нотўғри бўлса
// ҳам экран йиқилмайди) ва кўрсатиш.

import 'logistics_stage.dart' show normalizeTesterPhone;

export 'logistics_stage.dart' show normalizeTesterPhone;

/// Сервер қабул қиладиган босқичлар (`off` | `internal` | `public`).
const kCustomerConfirmStages = <String>['off', 'internal', 'public'];

/// Босқич → админ матни.
const kCustomerConfirmStageLabels = <String, String>{
  'off': 'OFF — ўчиқ',
  'internal': 'INTERNAL — фақат синовчилар',
  'public': 'PUBLIC — ҳамма',
};

/// Модул калити → админ матни (сервердаги тартиб).
const kCustomerConfirmModules = <String, String>{
  'restaurant': 'Ресторан',
  'carpet': 'Гилам ювиш',
  'agro': 'Сут / агро',
  'collection': 'Йиғиш',
};

/// PUBLIC ёқишдан олдинги огоҳлантириш (экран тепасида ва тасдиқ ойнасида).
const kCustomerConfirmPublicWarning =
    'PUBLIC учун курьерлар ВА мижозлар илованинг ЯНГИ версиясидан фойдаланиши шарт: '
    'эски иловада мижоз тасдиқлай олмайди, курьер эса «мижоз тасдиғи кутилмоқда» '
    'ҳолатини кўрмайди.';

/// Номаълум/йўқ қиймат → `null` (экран «—» кўрсатади, тахмин қилмайди).
String? parseCustomerConfirmStage(Object? v) {
  if (v is! String) return null;
  final s = v.trim().toLowerCase();
  return kCustomerConfirmStages.contains(s) ? s : null;
}

class CustomerConfirmState {
  const CustomerConfirmState({
    this.stages = const {},
    this.testerCount,
  });

  /// Модул → босқич (`null` = сервер бермаган / номаълум).
  final Map<String, String?> stages;

  /// Синовчилар сони (сервер бермаган бўлса `null`).
  final int? testerCount;

  /// `{ok, modules:{restaurant:{stage}, …}, testerCount}`.
  static CustomerConfirmState fromMap(Map<String, dynamic> m) {
    final raw = m['modules'];
    final modules = raw is Map ? raw : const {};
    final stages = <String, String?>{};
    for (final k in kCustomerConfirmModules.keys) {
      final e = modules[k];
      stages[k] = e is Map ? parseCustomerConfirmStage(e['stage']) : null;
    }
    final tc = m['testerCount'];
    return CustomerConfirmState(stages: stages, testerCount: tc is num ? tc.toInt() : null);
  }
}

class CustomerConfirmSetResult {
  const CustomerConfirmSetResult({this.unchanged = false, this.stage, this.testerCount});

  final bool unchanged;
  final String? stage;
  final int? testerCount;

  /// `{ok, unchanged, stage, testerCount}`.
  static CustomerConfirmSetResult fromMap(Map<String, dynamic> m) {
    final tc = m['testerCount'];
    return CustomerConfirmSetResult(
      unchanged: m['unchanged'] == true,
      stage: parseCustomerConfirmStage(m['stage']),
      testerCount: tc is num ? tc.toInt() : null,
    );
  }

  String describe() {
    final st = stage == null ? '' : ' · босқич: ${stage!.toUpperCase()}';
    final tc = testerCount == null ? '' : ' · синовчилар: $testerCount';
    return unchanged ? 'Ўзгариш йўқ$st$tc' : 'Сақланди$st$tc';
  }
}