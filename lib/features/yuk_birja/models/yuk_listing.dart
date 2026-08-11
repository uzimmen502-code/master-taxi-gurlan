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
    this.weightKg,
    this.capacityKg,
    this.freeSpaceKg,
    this.price = 0,
    this.comment = '',
    this.stars = 5.0,
    this.isDemo = false,
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

  /// Оғирлик/юк кўтариши/бўш жой — ҳаммаси **килограмм**.
  /// Firestore'да майдон номлари ўзгармаган (`weight`/`capacity`/`freeSpace`),
  /// бирлик `unit` майдони билан белгиланади: `kg`. Эски (`unit` йўқ)
  /// эълонлардаги қийматлар тонна деб қабул қилиниб, ўқишда ×1000 бўлади.
  final double? weightKg;
  final double? capacityKg;
  final double? freeSpaceKg;
  final double price;
  final String comment;
  final double stars;

  /// Намойиш (сийд) эълони — картада «Намойиш» белгиси кўринади.
  /// Ҳақиқий фойдаланувчилар етарли бўлганда бу ёзувлар ўчирилади.
  final bool isDemo;
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
        'unit': 'kg',
        'weight': weightKg,
        'capacity': capacityKg,
        'freeSpace': freeSpaceKg,
        'price': price,
        'comment': comment,
        'stars': stars,
        'isDemo': isDemo,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
      };

  /// `unit == 'kg'` бўлмаса — эски эълон (тонна), кг га айлантирамиз.
  static double? _asKg(dynamic v, Map<String, dynamic> j) {
    final n = (v as num?)?.toDouble();
    if (n == null) return null;
    return j['unit']?.toString() == 'kg' ? n : n * 1000;
  }

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
      weightKg: _asKg(j['weight'], j),
      capacityKg: _asKg(j['capacity'], j),
      freeSpaceKg: _asKg(j['freeSpace'], j),
      price: (j['price'] as num?)?.toDouble() ?? 0,
      comment: (j['comment'] ?? '').toString(),
      stars: (j['stars'] as num?)?.toDouble() ?? 5,
      isDemo: j['isDemo'] == true,
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
    double? weightKg,
    double? capacityKg,
    double? freeSpaceKg,
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
      weightKg: weightKg ?? this.weightKg,
      capacityKg: capacityKg ?? this.capacityKg,
      freeSpaceKg: freeSpaceKg ?? this.freeSpaceKg,
      price: price ?? this.price,
      comment: comment ?? this.comment,
      stars: stars ?? this.stars,
      isDemo: isDemo,
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
