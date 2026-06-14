import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat_message.dart';

/// `support_chats` collection — admin va foydalanuvchi orasidagi yordam chati.
class ChatRepository {
  ChatRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _chatRef(String chatId) =>
      _db.collection('support_chats').doc(chatId);

  /// Админдан ўқилмаган хабар борми (`support_chats.lastFromAdmin`).
  Stream<bool> watchUnreadFromAdmin(String chatId) => _chatRef(chatId)
      .snapshots()
      .map((s) {
        if (!s.exists) return false;
        return (s.data()?['lastFromAdmin'] ?? false) == true;
      });

  /// Мижоз чатни очганда — badge тушириш.
  Future<void> markUserRead(String chatId) async {
    if (chatId.isEmpty) return;
    await _chatRef(chatId).set(
      {'lastFromAdmin': false},
      SetOptions(merge: true),
    );
  }

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
