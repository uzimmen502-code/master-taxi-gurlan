import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

import '../models/assistant_message.dart';
import '../models/assistant_status.dart';

/// «AVA ёрдамчиси» — Cloud Functions wrapper (`functions/assistant_chat.js`).
///
/// Тариф/лимит мантиғи фақат серверда; бу класс сўров юборади ва
/// [AssistantStatus]ни қайтаради. Хатолар [AssistantException] сифатида
/// (`code` — сервер `HttpsError` message/details.reason).
class AssistantService {
  AssistantService({FirebaseFunctions? functions, FirebaseFirestore? db})
      : _functions = functions ?? FirebaseFunctions.instance,
        _db = db ?? FirebaseFirestore.instance;

  final FirebaseFunctions _functions;
  final FirebaseFirestore _db;
  static const _uuid = Uuid();

  /// Суҳбат тарихи — фақат сервер ёзади (`firestore.rules`).
  Stream<List<AssistantMessage>> watchMessages(String uid, {int limit = 200}) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('assistant_messages')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(AssistantMessage.fromDoc).toList().reversed.toList());
  }

  Future<AssistantStatus> getStatus() async {
    final res = await _call('assistantGetStatus', const {});
    return AssistantStatus.fromMap(res);
  }

  /// Хабар юбориш → жавоб матни + янгиланган ҳолат.
  Future<AssistantReply> send(String text) async {
    final res = await _call('assistantChat', {'text': text.trim()});
    return AssistantReply(
      reply: (res['reply'] ?? '') as String,
      status: AssistantStatus.fromMap(
          Map<String, dynamic>.from(res['status'] as Map? ?? const {})),
    );
  }

  /// Pro пакетни ҳамёндан сотиб олиш (идемпотент).
  Future<AssistantPurchaseResult> buyPackage(String packageId) async {
    final res = await _call('assistantBuyPackage', {
      'packageId': packageId,
      'idempotencyKey': _uuid.v4(),
    });
    return AssistantPurchaseResult(
      paidUntil: DateTime.fromMillisecondsSinceEpoch(
          (res['paidUntil'] as num?)?.toInt() ?? 0),
      balance: (res['balance'] as num?)?.toInt() ?? 0,
      debited: (res['debited'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> clearHistory() async {
    await _call('assistantClearHistory', const {});
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final result = await _functions
          .httpsCallable(
            name,
            options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
          )
          .call(data);
      return Map<String, dynamic>.from(result.data as Map? ?? const {});
    } on FirebaseFunctionsException catch (e) {
      final details = e.details is Map
          ? Map<String, dynamic>.from(e.details as Map)
          : const <String, dynamic>{};
      final reason = (details['reason'] ?? e.message ?? e.code).toString();
      throw AssistantException(reason, details: details, firebaseCode: e.code);
    }
  }
}

class AssistantReply {
  const AssistantReply({required this.reply, required this.status});
  final String reply;
  final AssistantStatus status;
}

class AssistantPurchaseResult {
  const AssistantPurchaseResult({
    required this.paidUntil,
    required this.balance,
    required this.debited,
  });
  final DateTime paidUntil;
  final int balance;
  final int debited;
}

/// Сервер хатоси. [code] қийматлари: `daily_limit`, `too_fast`,
/// `insufficient_balance`, `assistant_disabled`, `api_key_missing`,
/// `upstream_unavailable`, `upstream_rate_limited`, `text_too_long`, …
class AssistantException implements Exception {
  const AssistantException(
    this.code, {
    this.details = const {},
    this.firebaseCode = '',
  });

  final String code;
  final Map<String, dynamic> details;
  final String firebaseCode;

  bool get isDailyLimit => code == 'daily_limit';
  bool get isInsufficientBalance => code == 'insufficient_balance';

  @override
  String toString() => 'AssistantException($code)';
}
