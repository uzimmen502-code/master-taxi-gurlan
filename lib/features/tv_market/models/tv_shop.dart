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
/// Расмлар: `photoUrls` (1–5). `photoUrl` — қоплама (биринчи расм, back-compat).
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
    this.photoUrls = const [],
    this.description = '',
    this.clipIds = const [],
    this.viewCount = 0,
    this.boostUntil,
    this.socialConsent = false,
    this.socialPostedAt,
    this.status = 'active',
    this.createdAt,
  });

  static const maxPhotos = 5;

  final String id;
  final String ownerPhone;
  final String ownerName;
  final String title;
  final int price;

  /// Қоплама (биринчи расм).
  final String photoUrl;
  final List<String> photoUrls;

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

  static List<String> normalizePhotos({
    List<dynamic>? rawUrls,
    String photoUrl = '',
  }) {
    final out = <String>[];
    if (rawUrls != null) {
      for (final e in rawUrls) {
        final s = '$e'.trim();
        if (s.isEmpty || out.contains(s)) continue;
        out.add(s);
        if (out.length >= maxPhotos) return out;
      }
    }
    if (out.isEmpty) {
      final one = photoUrl.trim();
      if (one.isNotEmpty) out.add(one);
    }
    return out;
  }

  List<String> get displayPhotos {
    if (photoUrls.isNotEmpty) {
      return photoUrls
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .take(maxPhotos)
          .toList(growable: false);
    }
    final one = photoUrl.trim();
    return one.isEmpty ? const <String>[] : <String>[one];
  }

  String get coverPhotoUrl {
    final list = displayPhotos;
    return list.isEmpty ? '' : list.first;
  }

  bool get isActive => status == 'active';
  bool get hasVideo => clipIds.isNotEmpty;
  bool get hasPrice => price > 0;
  bool get isBoosted =>
      boostUntil != null && boostUntil!.isAfter(DateTime.now());
  bool get socialPosted => socialPostedAt != null;
  bool get isVitrineReady =>
      isActive && coverPhotoUrl.isNotEmpty && hasVideo;

  factory TvShopItem.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data()!;
    final rawClips = d['clipIds'];
    final photos = normalizePhotos(
      rawUrls: d['photoUrls'] as List?,
      photoUrl: (d['photoUrl'] ?? '') as String,
    );
    return TvShopItem(
      id: doc.id,
      ownerPhone: (d['ownerPhone'] ?? '') as String,
      ownerName: (d['ownerName'] ?? '') as String,
      title: (d['title'] ?? '') as String,
      price: (d['price'] ?? 0) as int,
      photoUrl: photos.isNotEmpty ? photos.first : '',
      photoUrls: photos,
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

  Map<String, dynamic> toMap() {
    final photos = normalizePhotos(rawUrls: photoUrls, photoUrl: photoUrl);
    return {
      'ownerPhone': ownerPhone,
      'ownerName': ownerName,
      'title': title,
      'price': price,
      'photoUrl': photos.isNotEmpty ? photos.first : photoUrl,
      'photoUrls': photos,
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
}
