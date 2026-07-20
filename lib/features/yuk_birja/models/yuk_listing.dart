import 'package:cloud_firestore/cloud_firestore.dart';

import '../yuk_vehicle_types.dart';

enum YukListingType { cargo, truck }

enum YukListingStatus { active, closed }

class YukListing {
  YukListing({
    required this.id,
    required this.type,
    required this.from,
    required this.to,
    required this.stops,
    required this.vehicleType,
    required this.ownerId,
    required this.ownerName,
    required this.phone,
    required this.status,
    this.cargo,
    this.weight,
    this.capacity,
    this.freeSpace,
    this.price = 0,
    this.comment = '',
    this.stars = 5.0,
    DateTime? createdAt,
    DateTime? expiresAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        expiresAt = expiresAt ??
            (createdAt ?? DateTime.now()).add(ttl);

  /// Эълон актив муддати.
  static const Duration ttl = Duration(hours: 48);

  final String id;
  final YukListingType type;
  final String from;
  final String to;
  final List<String> stops;
  final String vehicleType;
  final String ownerId;
  final String ownerName;
  final String phone;
  YukListingStatus status;
  final String? cargo;
  final double? weight;
  final double? capacity;
  final double? freeSpace;
  final double price;
  final String comment;
  final double stars;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool get isCargo => type == YukListingType.cargo;
  bool get isActive => status == YukListingStatus.active;

  bool isExpired([DateTime? now]) =>
      (now ?? DateTime.now()).isAfter(expiresAt);

  Duration remaining([DateTime? now]) {
    final left = expiresAt.difference(now ?? DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  List<String> get routeCities => [from, ...stops, to];

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'from': from,
        'to': to,
        'stops': stops,
        'vehicleType': vehicleType,
        'ownerId': ownerId,
        'ownerName': ownerName,
        'phone': phone,
        'status': status.name,
        'cargo': cargo,
        'weight': weight,
        'capacity': capacity,
        'freeSpace': freeSpace,
        'price': price,
        'comment': comment,
        'stars': stars,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
      };

  static DateTime _asDate(dynamic v, DateTime fallback) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.tryParse(v?.toString() ?? '') ?? fallback;
  }

  factory YukListing.fromFirestore(String id, Map<String, dynamic> j) {
    final created = _asDate(j['createdAt'], DateTime.now());
    final expires = _asDate(j['expiresAt'], created.add(ttl));
    return YukListing(
      id: id,
      type: (j['type']?.toString() == 'truck')
          ? YukListingType.truck
          : YukListingType.cargo,
      from: (j['from'] ?? '').toString(),
      to: (j['to'] ?? '').toString(),
      stops: (j['stops'] is List)
          ? (j['stops'] as List).map((e) => e.toString()).toList()
          : const [],
      vehicleType:
          normalizeYukVehicleType((j['vehicleType'] ?? 'fura').toString()),
      ownerId: (j['ownerId'] ?? '').toString(),
      ownerName: (j['ownerName'] ?? '').toString(),
      phone: (j['phone'] ?? '').toString(),
      status: (j['status']?.toString() == 'closed')
          ? YukListingStatus.closed
          : YukListingStatus.active,
      cargo: j['cargo']?.toString(),
      weight: (j['weight'] as num?)?.toDouble(),
      capacity: (j['capacity'] as num?)?.toDouble(),
      freeSpace: (j['freeSpace'] as num?)?.toDouble(),
      price: (j['price'] as num?)?.toDouble() ?? 0,
      comment: (j['comment'] ?? '').toString(),
      stars: (j['stars'] as num?)?.toDouble() ?? 5,
      createdAt: created,
      expiresAt: expires,
    );
  }

  factory YukListing.fromJson(Map<String, dynamic> j) {
    return YukListing.fromFirestore((j['id'] ?? '').toString(), j);
  }

  YukListing copyWith({
    YukListingType? type,
    String? from,
    String? to,
    List<String>? stops,
    String? vehicleType,
    String? ownerId,
    String? ownerName,
    String? phone,
    YukListingStatus? status,
    String? cargo,
    double? weight,
    double? capacity,
    double? freeSpace,
    double? price,
    String? comment,
    double? stars,
    DateTime? createdAt,
    DateTime? expiresAt,
  }) {
    return YukListing(
      id: id,
      type: type ?? this.type,
      from: from ?? this.from,
      to: to ?? this.to,
      stops: stops ?? this.stops,
      vehicleType: vehicleType ?? this.vehicleType,
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
      phone: phone ?? this.phone,
      status: status ?? this.status,
      cargo: cargo ?? this.cargo,
      weight: weight ?? this.weight,
      capacity: capacity ?? this.capacity,
      freeSpace: freeSpace ?? this.freeSpace,
      price: price ?? this.price,
      comment: comment ?? this.comment,
      stars: stars ?? this.stars,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}

class YukMatchPair {
  const YukMatchPair({
    required this.cargo,
    required this.truck,
    required this.score,
  });

  final YukListing cargo;
  final YukListing truck;
  final int score;
}
