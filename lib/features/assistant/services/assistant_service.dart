import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

import '../models/assistant_conversation.dart';
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

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _db.collection('users').doc(uid);

  /// Суҳбатлар рўйхати (ChatGPT чап панели) — охирги янгиланган биринчи.
  Stream<List<AssistantConversation>> watchConversations(String uid) {
    return _user(uid)
        .collection('assistant_conversations')
        .orderBy('updatedAt', descending: true)
        .limit(300)
        .snapshots()
        .map((s) => s.docs.map(AssistantConversation.fromDoc).toList());
  }

  /// Битта суҳбат хабарлари — фақат сервер ёзади (`firestore.rules`).
  Stream<List<AssistantMessage>> watchMessages(
    String uid,
    String conversationId, {
    int limit = 400,
  }) {
    return _user(uid)
        .collection('assistant_conversations')
        .doc(conversationId)
        .collection('assistant_messages')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(AssistantMessage.fromDoc).toList().reversed.toList());
  }

  /// Хотира — аввалги суҳбатлардан сақланган фактлар.
  Stream<List<AssistantMemoryItem>> watchMemory(String uid) {
    return _user(uid)
        .collection('assistant_memory')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(AssistantMemoryItem.fromDoc).toList());
  }

  Future<AssistantStatus> getStatus() async {
    final res = await _call('assistantGetStatus', const {});
    return AssistantStatus.fromMap(res);
  }

  /// Хабар юбориш → жавоб матни + янгиланган ҳолат. [conversationId] бўш
  /// бўлса сервер янги суҳбат очади (id жавобда).
  Future<AssistantReply> send(String text, {String? conversationId}) async {
    final res = await _call('assistantChat', {
      'text': text.trim(),
      if (conversationId != null && conversationId.isNotEmpty)
        'conversationId': conversationId,
    });
    return AssistantReply(
      reply: (res['reply'] ?? '') as String,
      messageId: (res['messageId'] ?? '') as String,
      conversationId: (res['conversationId'] ?? '') as String,
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

  Future<void> deleteConversation(String conversationId) async {
    await _call('assistantDeleteConversation', {'conversationId': conversationId});
  }

  Future<void> renameConversation(String conversationId, String title) async {
    await _call('assistantRenameConversation', {
      'conversationId': conversationId,
      'title': title.trim(),
    });
  }

  /// [memoryId] = `*` — ҳаммасини ўчириш.
  Future<void> deleteMemory(String memoryId) async {
    await _call('assistantDeleteMemory', {'memoryId': memoryId});
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
  const AssistantReply({
    required this.reply,
    required this.messageId,
    required this.conversationId,
    required this.status,
  });
  final String reply;
  final String conversationId;

  /// `users/{uid}/assistant_messages/{messageId}` — typewriter учун.
  final String messageId;
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
