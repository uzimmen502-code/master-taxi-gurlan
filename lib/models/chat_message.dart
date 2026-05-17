import 'package:cloud_firestore/cloud_firestore.dart';

/// `support_chats/{chatId}/messages` subcollection elementi.
class ChatMessage {
  final String id;
  final String text;
  final bool fromAdmin;
  final String fromPhone;
  final String fromName;
  final DateTime? createdAt;
  final bool read;

  const ChatMessage({
    required this.id,
    required this.text,
    this.fromAdmin = false,
    this.fromPhone = '',
    this.fromName = '',
    this.createdAt,
    this.read = false,
  });

  factory ChatMessage.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return ChatMessage(
      id: doc.id,
      text: d['text'] ?? '',
      fromAdmin: (d['fromAdmin'] ?? false) as bool,
      fromPhone: d['fromPhone'] ?? '',
      fromName: d['fromName'] ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      read: (d['read'] ?? false) as bool,
    );
  }
}
