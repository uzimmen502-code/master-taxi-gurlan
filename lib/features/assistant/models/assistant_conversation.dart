import 'package:cloud_firestore/cloud_firestore.dart';

/// `users/{uid}/assistant_conversations/{id}` — сервер ёзади (ChatGPT каби
/// ҳар суҳбат алоҳида, сарлавҳа автоматик, 365 кун TTL).
class AssistantConversation {
  const AssistantConversation({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.lastText,
    required this.messageCount,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final String lastText;
  final int messageCount;

  factory AssistantConversation.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const {};
    return AssistantConversation(
      id: doc.id,
      title: ((d['title'] ?? '') as String).trim(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ??
          (d['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastText: (d['lastText'] ?? '') as String,
      messageCount: (d['messageCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// `users/{uid}/assistant_memory/{id}` — аввалги суҳбатлардан факт.
class AssistantMemoryItem {
  const AssistantMemoryItem({
    required this.id,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String text;
  final DateTime createdAt;

  factory AssistantMemoryItem.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const {};
    return AssistantMemoryItem(
      id: doc.id,
      text: (d['text'] ?? '') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
