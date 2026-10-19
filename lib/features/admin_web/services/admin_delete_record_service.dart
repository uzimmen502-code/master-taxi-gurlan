// Админ — хабарни қайтариб олиш, чатни архивга олиш ва (фақат superadmin) ҲАҚИҚИЙ ўчириш.
// Callable'лар (default codebase, us-central1): `adminRetractNews`, `adminArchiveSupportChat`, `adminDeleteRecord`.
// Ҳамма амал ва audit СЕРВЕРДА (Admin SDK, `admin_audit`); client Firestore rules ўчиришга рухсат бермайди.
// Эга қарори 2026-10-20: `admin_news` ва мижоз чати админ томонидан ЎЧИРИЛМАЙДИ — хабар қайтариб олинади (90 кун
// сақланади), чат архивга олинади. Ҳақиқий ўчириш — фақат superadmin, шахсий маълумотни ўчириш талаби бўйича.
// Хато — `AdminRestaurantsService` каби: `details.code` (`PERSONAL_NEWS_NOT_RETRACTABLE`, `CHAT_NOT_ARCHIVED`, …) + хабар.

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

  Future<Map<String, dynamic>> _invoke(
      String name, Map<String, dynamic> data) async {
    try {
      final res = await _functions.httpsCallable(name).call<dynamic>(data);
      final raw = res.data;
      return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      final details =
          e.details is Map ? Map<String, dynamic>.from(e.details as Map) : null;
      throw AdminDeleteRecordException(
          e.code, (details?['code'] ?? '').toString(), e.message ?? e.code);
    }
  }

  /// Ҳақиқий ўчириш (`adminDeleteRecord`, фақат superadmin): мижознинг шахсий маълумотини ўчириш талаби.
  /// Чат аввал архивга олинган ва [reason] камида 10 белги бўлиши шарт (сервер текширади).
  Future<AdminDeleteResult> eraseSupportChat(String chatId,
      {required String reason}) async {
    final m = await _invoke('adminDeleteRecord',
        {'kind': 'support_chat', 'id': chatId, 'reason': reason});
    return AdminDeleteResult(
        deleted: m['deleted'] == true, partial: m['partial'] == true);
  }

  /// Хабарни қайтариб олиш (`adminRetractNews`). `true` = ҳозир қайтарилди, `false` = аллақачон қайтарилган.
  Future<bool> retractNews(String id, {String reason = ''}) async {
    final m = await _invoke('adminRetractNews', {'id': id, 'reason': reason});
    return m['changed'] == true;
  }

  /// Чатни архивга олиш / архивдан чиқариш (`adminArchiveSupportChat`). `true` = ҳолат ўзгарди.
  Future<bool> archiveSupportChat(String chatId,
      {required bool archived}) async {
    final m = await _invoke(
        'adminArchiveSupportChat', {'chatId': chatId, 'archived': archived});
    return m['changed'] == true;
  }
}
