import 'package:cloud_firestore/cloud_firestore.dart';

/// Профил исмидан биринчи сўз. Телефон / бўш / @nick — бўш қайтаради.
String tvOwnerGivenName(String raw) {
  var s = raw.trim();
  if (s.startsWith('@')) s = s.substring(1).trim();
  if (s.isEmpty) return '';
  final compact = s.replaceAll(RegExp(r'[\s+\-()]'), '');
  if (RegExp(r'^\d{7,}$').hasMatch(compact)) return '';
  return s.split(RegExp(r'\s+')).first;
}

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
    this.shopItemId = '',
    this.socialConsent = false,
    this.socialPostedAt,
    this.searchTokens = const [],
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

  /// Боғланган витрина товар/хизмати. Бўш = фақат ролик.
  final String shopItemId;
  final bool socialConsent;
  final DateTime? socialPostedAt;
  final List<String> searchTokens;

  bool get isActive => status == 'active';
  bool get hasPrice => price > 0;
  bool get hasShopItem => shopItemId.trim().isNotEmpty;
  bool get socialPosted => socialPostedAt != null;

  String displayOwnerName(String fallback) {
    final g = tvOwnerGivenName(ownerName);
    return g.isEmpty ? fallback : g;
  }

  TvClip copyWith({
    int? likeCount,
    String? shopItemId,
    bool? socialConsent,
    DateTime? socialPostedAt,
  }) {
    return TvClip(
      id: id,
      videoUrl: videoUrl,
      posterUrl: posterUrl,
      title: title,
      price: price,
      districtId: districtId,
      districtLabel: districtLabel,
      ownerPhone: ownerPhone,
      ownerName: ownerName,
      category: category,
      lat: lat,
      lng: lng,
      mfy: mfy,
      description: description,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount,
      viewCount: viewCount,
      status: status,
      createdAt: createdAt,
      shopItemId: shopItemId ?? this.shopItemId,
      socialConsent: socialConsent ?? this.socialConsent,
      socialPostedAt: socialPostedAt ?? this.socialPostedAt,
      searchTokens: searchTokens,
    );
  }

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
      shopItemId: (d['shopItemId'] ?? '') as String,
      socialConsent: d['socialConsent'] == true,
      socialPostedAt: (d['socialPostedAt'] as Timestamp?)?.toDate(),
      searchTokens: (d['searchTokens'] is List)
          ? (d['searchTokens'] as List)
              .map((e) => '$e')
              .where((e) => e.isNotEmpty)
              .toList()
          : const [],
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
        if (shopItemId.isNotEmpty) 'shopItemId': shopItemId,
        'socialConsent': socialConsent,
        if (socialPostedAt != null)
          'socialPostedAt': Timestamp.fromDate(socialPostedAt!),
        if (searchTokens.isNotEmpty) 'searchTokens': searchTokens,
      };
}
