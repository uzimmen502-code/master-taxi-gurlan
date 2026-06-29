import 'package:cloud_firestore/cloud_firestore.dart';

/// `relatives/{userId}/people/{personId}/photos` — qarindosh fotoalbomi rasmi.
class RelativePhoto {
  const RelativePhoto({
    required this.id,
    required this.url,
    this.storagePath = '',
    this.caption = '',
    this.createdAt,
  });

  final String id;
  final String url;
  final String storagePath;
  final String caption;
  final DateTime? createdAt;

  factory RelativePhoto.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return RelativePhoto(
      id: doc.id,
      url: (d['url'] ?? '') as String,
      storagePath: (d['storagePath'] ?? '') as String,
      caption: (d['caption'] ?? '') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'url': url,
        'storagePath': storagePath,
        'caption': caption,
      };
}
