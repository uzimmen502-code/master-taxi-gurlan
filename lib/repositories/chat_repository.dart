import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat_message.dart';

/// `support_chats` collection — admin va foydalanuvchi orasidagi yordam chati.
class ChatRepository {
  ChatRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _chatRef(String chatId) =>
      _db.collection('support_chats').doc(chatId);

  /// Bitta chatdagi barcha xabarlar (real-time, vaqt bo'yicha tartiblangan).
  Stream<List<ChatMessage>> watchMessages(String chatId) => _chatRef(chatId)
      .collection('messages')
      .orderBy('createdAt')
      .snapshots()
      .map((q) => q.docs.map(ChatMessage.fromDoc).toList());

  /// [fromAdmin] фақат `support_chats` parent учун `lastFromAdmin` — хабар
  /// ҳужжатида client SDK `fromAdmin: false` ёзади (Firestore rules).
  Future<void> sendMessage({
    required String chatId,
    required String text,
    required bool fromAdmin,
    required String fromPhone,
    required String fromName,
  }) async {
    final chatRef = _chatRef(chatId);
    await chatRef.set({
      'userPhone': chatId,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessage': text,
      'lastFromAdmin': fromAdmin,
    }, SetOptions(merge: true));
    // `fromAdmin: true` фақат Admin SDK / Cloud Functions (Firestore rules).
    await chatRef.collection('messages').add({
      'text': text,
      'fromAdmin': false,
      'fromPhone': fromPhone,
      'fromName': fromName,
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });
  }
}
