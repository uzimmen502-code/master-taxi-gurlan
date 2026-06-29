import 'package:cloud_firestore/cloud_firestore.dart';

/// `circles/{circleId}/posts/{postId}` — lenta/e'lon.
class CirclePost {
  const CirclePost({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    this.mediaPaths = const [],
    this.pinned = false,
    this.createdAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String text;
  final List<String> mediaPaths;
  final bool pinned;
  final DateTime? createdAt;

  factory CirclePost.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return CirclePost(
      id: doc.id,
      authorId: (d['authorId'] ?? '') as String,
      authorName: (d['authorName'] ?? '') as String,
      text: (d['text'] ?? '') as String,
      mediaPaths: List<String>.from((d['mediaPaths'] as List?) ?? const []),
      pinned: d['pinned'] == true,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'authorId': authorId,
        'authorName': authorName,
        'text': text,
        'mediaPaths': mediaPaths,
        'pinned': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
