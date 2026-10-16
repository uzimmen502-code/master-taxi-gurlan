// Админ callable ёрдамчиси — битта жойда: чақириш + хато шакли.
//
// Ҳамма ёзув/ҳисоб СЕРВЕРДА; экран фақат чақиради ва натижани кўрсатади
// (44-банд). Регион чақирувчи томонидан берилади:
//   • default codebase — `FirebaseFunctions.instance` (us-central1);
//   • demand codebase (logistics) — `FirebaseFunctions.instanceFor(region:
//     kDemandCoreRegion)` (europe-west1).

import 'package:cloud_functions/cloud_functions.dart';

class AdminCallableException implements Exception {
  const AdminCallableException(this.code, this.reason, this.message, {this.details});

  /// Firebase код: `permission-denied`, `failed-precondition`, …
  final String code;

  /// Сервер `details.reason` ёки `details.code` (`shipment_not_lossable`,
  /// `HOURS_INVALID`, …); бўлмаса бўш.
  final String reason;
  final String message;
  final Map<String, dynamic>? details;

  @override
  String toString() => 'AdminCallableException($code/$reason): $message';
}

class AdminCallable {
  AdminCallable(this._functions);

  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> payload) async {
    try {
      final res = await _functions.httpsCallable(name).call<Object?>(payload);
      final d = res.data;
      return d is Map ? d.map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      final raw = e.details;
      final details = raw is Map ? raw.map((k, v) => MapEntry(k.toString(), v)) : null;
      final reason = (details?['reason'] ?? details?['code'] ?? '').toString();
      throw AdminCallableException(e.code, reason, e.message ?? e.code, details: details);
    }
  }
}

/// Бутун сон (JSON `num`) → `int`; бошқа ҳолда `null`.
int? adminInt(Object? v) => v is num ? v.toInt() : null;

/// Сервер `details.reason` → админ учун қисқа матн (Кирилл, `logistics_admin_screen`
/// каби). Матни йўқ код — `message (reason)`.
String adminErrorText(Object error) {
  if (error is! AdminCallableException) return '$error';
  const byReason = <String, String>{
    'declared_value_missing': 'Посилка қиймати ёзилмаган (эски жўнатма) — қўлда ҳал қилинади',
    'shipment_not_lossable': 'Фақат йўлдаги ёки низоли жўнатма «йўқолди» деб белгиланади',
    'payment_not_lossable': 'Тўлов ҳолати йўқолишга мос эмас',
    'custodian_not_provider': 'Посилка ижрочи қўлида эмас',
    'courier_account_missing': 'Курьер ҳисоби (accountId) топилмади',
    'loss_reason_required': 'Йўқолиш сабабини ёзинг (камида 3 белги)',
    'loss_op_id': 'Амал идентификатори хато — қайта уриниб кўринг',
    'stage_invalid': 'Босқич номаълум',
    'tester_invalid': 'Телефон рақами нотўғри',
    'testers_limit': 'Синовчилар сони чегарадан ошди',
    'module_config_missing': 'Логистика модули конфиги йўқ',
    'HOURS_INVALID': 'Соат 1..168 оралиғида бўлиши керак',
  };
  final mapped = byReason[error.reason];
  if (mapped != null) return mapped;
  if (error.code == 'permission-denied' || error.code == 'unauthenticated') {
    return 'Рухсат йўқ (фақат admin/superadmin)';
  }
  final r = error.reason.isEmpty ? '' : ' (${error.reason})';
  return '${error.message}$r';
}
