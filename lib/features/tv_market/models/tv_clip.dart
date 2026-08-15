import 'package:cloud_firestore/cloud_firestore.dart';

/// TV Market клипи — битта видео = битта таклиф (маҳсулот ёки хизмат).
class TvClip {
  const TvClip({
    required this.id,
    required this.videoUrl,
    required this.posterUrl,
    required this.title,
    required this.price,
    required this.districtId,
    required this.districtLabel,
    required this.ownerPhone,
    required this.ownerName,
    required this.category,
    this.lat,
    this.lng,
    this.mfy,
    this.description = '',
    this.likeCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
    this.status = 'active',
    this.createdAt,
  });

  final String id;
  final String videoUrl;
  final String posterUrl;
  final String title;
  final int price;
  final String districtId;
  final String districtLabel;
  final String ownerPhone;
  final String ownerName;

  /// `product` | `service`
  final String category;

  final double? lat;
  final double? lng;
  final String? mfy;
  final String description;
  final int likeCount;
  final int commentCount;
  final int viewCount;

  /// `pending` | `active` | `blocked`
  final String status;
  final DateTime? createdAt;

  bool get isActive => status == 'active';
  bool get hasPrice => price > 0;

  factory TvClip.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return TvClip(
      id: doc.id,
      videoUrl: (d['videoUrl'] ?? '') as String,
      posterUrl: (d['posterUrl'] ?? '') as String,
      title: (d['title'] ?? '') as String,
      price: (d['price'] ?? 0) as int,
      districtId: (d['districtId'] ?? '') as String,
      districtLabel: (d['districtLabel'] ?? '') as String,
      ownerPhone: (d['ownerPhone'] ?? '') as String,
      ownerName: (d['ownerName'] ?? '') as String,
      category: (d['category'] ?? 'product') as String,
      lat: (d['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble(),
      mfy: d['mfy'] as String?,
      description: (d['description'] ?? '') as String,
      likeCount: (d['likeCount'] ?? 0) as int,
      commentCount: (d['commentCount'] ?? 0) as int,
      viewCount: (d['viewCount'] ?? 0) as int,
      status: (d['status'] ?? 'active') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'videoUrl': videoUrl,
        'posterUrl': posterUrl,
        'title': title,
        'price': price,
        'districtId': districtId,
        'districtLabel': districtLabel,
        'ownerPhone': ownerPhone,
        'ownerName': ownerName,
        'category': category,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (mfy != null) 'mfy': mfy,
        'description': description,
        'likeCount': likeCount,
        'commentCount': commentCount,
        'viewCount': viewCount,
        'status': status,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };
}
