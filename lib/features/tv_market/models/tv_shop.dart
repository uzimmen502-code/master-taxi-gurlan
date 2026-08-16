import 'package:cloud_firestore/cloud_firestore.dart';

/// Сотувчи мини-дўкони — `tv_shops/{ownerPhone}`.
class TvShop {
  const TvShop({
    required this.ownerPhone,
    required this.name,
    this.createdAt,
  });

  final String ownerPhone;
  final String name;
  final DateTime? createdAt;

  factory TvShop.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return TvShop(
      ownerPhone: doc.id,
      name: (d['name'] ?? '') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'ownerPhone': ownerPhone,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };
}

/// Витрина товар/хизмати — `tv_shop_items/{id}`.
class TvShopItem {
  const TvShopItem({
    required this.id,
    required this.ownerPhone,
    required this.ownerName,
    required this.title,
    required this.price,
    required this.photoUrl,
    required this.kind,
    required this.districtId,
    required this.districtLabel,
    this.description = '',
    this.clipIds = const [],
    this.viewCount = 0,
    this.boostUntil,
    this.socialConsent = false,
    this.socialPostedAt,
    this.status = 'active',
    this.createdAt,
  });

  final String id;
  final String ownerPhone;
  final String ownerName;
  final String title;
  final int price;
  final String photoUrl;

  /// `product` | `service`
  final String kind;
  final String districtId;
  final String districtLabel;
  final String description;
  final List<String> clipIds;
  final int viewCount;
  final DateTime? boostUntil;
  final bool socialConsent;
  final DateTime? socialPostedAt;

  /// `pending` | `active` | `blocked`
  final String status;
  final DateTime? createdAt;

  bool get isActive => status == 'active';
  bool get hasVideo => clipIds.isNotEmpty;
  bool get isBoosted =>
      boostUntil != null && boostUntil!.isAfter(DateTime.now());
  bool get socialPosted => socialPostedAt != null;
  bool get isVitrineReady =>
      isActive && photoUrl.isNotEmpty && price > 0 && hasVideo;

  factory TvShopItem.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data()!;
    final rawClips = d['clipIds'];
    return TvShopItem(
      id: doc.id,
      ownerPhone: (d['ownerPhone'] ?? '') as String,
      ownerName: (d['ownerName'] ?? '') as String,
      title: (d['title'] ?? '') as String,
      price: (d['price'] ?? 0) as int,
      photoUrl: (d['photoUrl'] ?? '') as String,
      kind: (d['kind'] ?? 'product') as String,
      districtId: (d['districtId'] ?? '') as String,
      districtLabel: (d['districtLabel'] ?? '') as String,
      description: (d['description'] ?? '') as String,
      clipIds: rawClips is List
          ? rawClips.map((e) => '$e').where((e) => e.isNotEmpty).toList()
          : const [],
      viewCount: (d['viewCount'] ?? 0) as int,
      boostUntil: (d['boostUntil'] as Timestamp?)?.toDate(),
      socialConsent: d['socialConsent'] == true,
      socialPostedAt: (d['socialPostedAt'] as Timestamp?)?.toDate(),
      status: (d['status'] ?? 'active') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'ownerPhone': ownerPhone,
        'ownerName': ownerName,
        'title': title,
        'price': price,
        'photoUrl': photoUrl,
        'kind': kind,
        'districtId': districtId,
        'districtLabel': districtLabel,
        'description': description,
        'clipIds': clipIds,
        'viewCount': viewCount,
        if (boostUntil != null) 'boostUntil': Timestamp.fromDate(boostUntil!),
        'socialConsent': socialConsent,
        if (socialPostedAt != null)
          'socialPostedAt': Timestamp.fromDate(socialPostedAt!),
        'status': status,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };
}
