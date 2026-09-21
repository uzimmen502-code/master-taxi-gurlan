import 'package:cloud_firestore/cloud_firestore.dart';

/// `users/{uid}/assistant_messages/{id}` — сервер ёзади.
class AssistantMessage {
  const AssistantMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.webSearches = 0,
    this.pending = false,
  });

  final String id;

  /// `user` | `assistant`.
  final String role;
  final String text;
  final DateTime createdAt;
  final int webSearches;

  /// Ҳали серверга етиб бормаган (локал кўрсатиш учун).
  final bool pending;

  bool get isUser => role == 'user';

  factory AssistantMessage.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const {};
    return AssistantMessage(
      id: doc.id,
      role: (d['role'] ?? 'assistant') as String,
      text: (d['text'] ?? '') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      webSearches: (d['webSearches'] as num?)?.toInt() ?? 0,
    );
  }

  factory AssistantMessage.localUser(String text) => AssistantMessage(
        id: 'local_${DateTime.now().microsecondsSinceEpoch}',
        role: 'user',
        text: text,
        createdAt: DateTime.now(),
        pending: true,
      );
}
