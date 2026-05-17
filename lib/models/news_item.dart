import 'package:cloud_firestore/cloud_firestore.dart';

/// Админ томонидан юбориладиган хабар/янгилик.
/// `admin_news` collection ҳужжати.
class NewsItem {
  const NewsItem({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.category = 'info',
    this.audience = 'all',
    this.imageUrl = '',
    this.ctaLabel = '',
    this.ctaUrl = '',
    this.priority = 0,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;

  /// `info` | `update` | `promo` | `warning` | `emergency`
  final String category;

  /// Маqсадли аудитория: `all` (барча) | `user` | `driver` | `courier`.
  /// `NewsScreen._audiences()` — `[all, <role>]` — мана шу қиймaт билан мос.
  final String audience;

  final String imageUrl;
  final String ctaLabel;
  final String ctaUrl;

  /// 0 — оддий, 10 — энг муҳим (рўйхатда юқорида).
  final int priority;

  factory NewsItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return NewsItem(
      id: doc.id,
      title: (d['title'] ?? '') as String,
      body: (d['body'] ?? '') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      category: (d['category'] ?? 'info') as String,
      audience: (d['audience'] ?? 'all') as String,
      imageUrl: (d['imageUrl'] ?? '') as String,
      ctaLabel: (d['ctaLabel'] ?? '') as String,
      ctaUrl: (d['ctaUrl'] ?? '') as String,
      priority: (d['priority'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'title': title,
        'body': body,
        'category': category,
        'audience': audience,
        if (imageUrl.isNotEmpty) 'imageUrl': imageUrl,
        if (ctaLabel.isNotEmpty) 'ctaLabel': ctaLabel,
        if (ctaUrl.isNotEmpty) 'ctaUrl': ctaUrl,
        'priority': priority,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
