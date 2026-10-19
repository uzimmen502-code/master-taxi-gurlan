// Админ — yozuvni o'chirish (callable `adminDeleteRecord`, default codebase, us-central1).
// O'chirish va audit SERVERDA (Admin SDK, `admin_audit`); client Firestore rules o'chirishga ruxsat bermaydi.
// Xato — `AdminRestaurantsService` kabi: `details.code` (`KIND_INVALID`, `DELETE_FAILED`, …) + xabar.

import 'package:cloud_functions/cloud_functions.dart';

class AdminDeleteRecordException implements Exception {
  const AdminDeleteRecordException(this.code, this.reason, this.message);

  final String code;

  /// Сервер `details.code`.
  final String reason;
  final String message;

  @override
  String toString() => reason.isNotEmpty ? '$reason ($message)' : message;
}

/// `adminDeleteRecord` натижаси: [deleted] `false` = ёзув аллақачон йўқ; [partial] = чат катта,
/// қолган хабарларни ўчириш учун яна босинг.
class AdminDeleteResult {
  const AdminDeleteResult({required this.deleted, this.partial = false});

  final bool deleted;
  final bool partial;
}

class AdminDeleteRecordService {
  AdminDeleteRecordService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<AdminDeleteResult> _call(Map<String, dynamic> data) async {
    try {
      final res = await _functions
          .httpsCallable('adminDeleteRecord')
          .call<dynamic>(data);
      final raw = res.data;
      final m =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      return AdminDeleteResult(
          deleted: m['deleted'] == true, partial: m['partial'] == true);
    } on FirebaseFunctionsException catch (e) {
      final details =
          e.details is Map ? Map<String, dynamic>.from(e.details as Map) : null;
      throw AdminDeleteRecordException(
          e.code, (details?['code'] ?? '').toString(), e.message ?? e.code);
    }
  }

  Future<AdminDeleteResult> deleteRiskEvent(String id, {String reason = ''}) =>
      _call({'kind': 'risk_event', 'id': id, 'reason': reason});

  Future<AdminDeleteResult> deleteNews(String id, {String reason = ''}) =>
      _call({'kind': 'admin_news', 'id': id, 'reason': reason});

  Future<AdminDeleteResult> deleteSupportMessage(
          String chatId, String messageId, {String reason = ''}) =>
      _call({
        'kind': 'support_message',
        'chatId': chatId,
        'id': messageId,
        'reason': reason
      });

  Future<AdminDeleteResult> deleteSupportChat(String chatId,
          {String reason = ''}) =>
      _call({'kind': 'support_chat', 'id': chatId, 'reason': reason});
}
