import 'package:cloud_firestore/cloud_firestore.dart';

/// `circles/{circleId}/album/{photoId}` — fotoalbom yozuvi.
class CirclePhoto {
  const CirclePhoto({
    required this.id,
    required this.uploaderId,
    required this.uploaderName,
    required this.url,
    this.storagePath = '',
    this.caption = '',
    this.createdAt,
  });

  final String id;
  final String uploaderId;
  final String uploaderName;
  final String url;
  final String storagePath;
  final String caption;
  final DateTime? createdAt;

  factory CirclePhoto.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return CirclePhoto(
      id: doc.id,
      uploaderId: (d['uploaderId'] ?? '') as String,
      uploaderName: (d['uploaderName'] ?? '') as String,
      url: (d['url'] ?? '') as String,
      storagePath: (d['storagePath'] ?? '') as String,
      caption: (d['caption'] ?? '') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'uploaderId': uploaderId,
        'uploaderName': uploaderName,
        'url': url,
        'storagePath': storagePath,
        'caption': caption,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
