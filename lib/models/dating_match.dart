import 'package:cloud_firestore/cloud_firestore.dart';

/// `dating_matches/{matchId}` — o'zaro qiziqish (chat ochiq).
class DatingMatch {
  const DatingMatch({
    required this.id,
    required this.users,
    this.userNames = const {},
    this.lastMessage = '',
    this.lastMessageAt,
  });

  final String id;
  final List<String> users;
  final Map<String, String> userNames;
  final String lastMessage;
  final DateTime? lastMessageAt;

  String otherId(String me) =>
      users.firstWhere((u) => u != me, orElse: () => '');

  String otherName(String me) => userNames[otherId(me)] ?? '';

  factory DatingMatch.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return DatingMatch(
      id: doc.id,
      users: ((d['users'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      userNames: ((d['userNames'] as Map?) ?? const {})
          .map((k, v) => MapEntry(k.toString(), v.toString())),
      lastMessage: (d['lastMessage'] ?? '') as String,
      lastMessageAt: (d['lastMessageAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// `dating_matches/{matchId}/messages/{id}` — chat xabari.
class DatingMessage {
  const DatingMessage({
    required this.id,
    required this.senderId,
    required this.text,
    this.createdAt,
  });

  final String id;
  final String senderId;
  final String text;
  final DateTime? createdAt;

  factory DatingMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return DatingMessage(
      id: doc.id,
      senderId: (d['senderId'] ?? '') as String,
      text: (d['text'] ?? '') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
