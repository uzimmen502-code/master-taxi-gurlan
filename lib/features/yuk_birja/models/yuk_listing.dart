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
  }) : createdAt = createdAt ?? DateTime.now();

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

  bool get isCargo => type == YukListingType.cargo;
  bool get isActive => status == YukListingStatus.active;

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
      };

  factory YukListing.fromJson(Map<String, dynamic> j) {
    return YukListing(
      id: (j['id'] ?? '').toString(),
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
      createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  YukListing copyWith({YukListingStatus? status}) {
    return YukListing(
      id: id,
      type: type,
      from: from,
      to: to,
      stops: stops,
      vehicleType: vehicleType,
      ownerId: ownerId,
      ownerName: ownerName,
      phone: phone,
      status: status ?? this.status,
      cargo: cargo,
      weight: weight,
      capacity: capacity,
      freeSpace: freeSpace,
      price: price,
      comment: comment,
      stars: stars,
      createdAt: createdAt,
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
