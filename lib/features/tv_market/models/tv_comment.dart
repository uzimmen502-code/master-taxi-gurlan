import 'package:cloud_firestore/cloud_firestore.dart';

/// Тайёр саволлар — тезкор, эркин матнга қараганда spam хавфи паст.
const tvCommentQuickKeys = ['price', 'location', 'delivery'];

/// Эркин матнли изоҳ учун лимит (spam/жой чегараси).
const tvCommentTextMaxLen = 140;

class TvComment {
  const TvComment({
    required this.id,
    required this.authorPhone,
    required this.authorName,
    this.type = 'quick',
    this.key = '',
    this.text = '',
    this.createdAt,
  });

  final String id;
  final String authorPhone;
  final String authorName;

  /// `quick` | `text`.
  final String type;

  /// `type == 'quick'` бўлса — `tvCommentQuickKeys`дан бири.
  final String key;

  /// `type == 'text'` бўлса — эркин матн (≤ [tvCommentTextMaxLen]).
  final String text;

  final DateTime? createdAt;

  bool get isFreeText => type == 'text';

  factory TvComment.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    final key = (d['key'] ?? '') as String;
    final rawType = (d['type'] ?? '') as String;
    // Eski yozuvlarda `type` yo'q edi — `key` bo'lsa quick, aks holda text.
    final type = rawType.isNotEmpty ? rawType : (key.isNotEmpty ? 'quick' : 'text');
    return TvComment(
      id: doc.id,
      authorPhone: (d['authorPhone'] ?? '') as String,
      authorName: (d['authorName'] ?? '') as String,
      type: type,
      key: key,
      text: (d['text'] ?? '') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'authorPhone': authorPhone,
        'authorName': authorName,
        'type': type,
        if (key.isNotEmpty) 'key': key,
        if (text.isNotEmpty) 'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
