import 'package:cloud_firestore/cloud_firestore.dart';

/// `circles/{circleId}/chat/{messageId}` — guruh chat xabari.
/// (Mavjud support chat naqshini guruh kontekstiga moslangan.)
class CircleChatMessage {
  const CircleChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    this.createdAt,
  });

  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime? createdAt;

  factory CircleChatMessage.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return CircleChatMessage(
      id: doc.id,
      senderId: (d['senderId'] ?? '') as String,
      senderName: (d['senderName'] ?? '') as String,
      text: (d['text'] ?? '') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'senderId': senderId,
        'senderName': senderName,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
