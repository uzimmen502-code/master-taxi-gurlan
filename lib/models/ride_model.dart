enum RideStatus {
  pending,
  accepted,
  arrived,
  started,
  completed,
  cancelled,
}

enum RideType {
  economy,
  comfort,
}

class LocationModel {
  final double latitude;
  final double longitude;
  final String address;

  LocationModel({
    required this.latitude,
    required this.longitude,
    required this.address,
  });

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
    };
  }

  factory LocationModel.fromMap(Map<String, dynamic> map) {
    return LocationModel(
      latitude: map['latitude']?.toDouble() ?? 0.0,
      longitude: map['longitude']?.toDouble() ?? 0.0,
      address: map['address'] ?? '',
    );
  }
}

class RideModel {
  final String id;
  final String userId;
  final String? driverId;
  final RideType type;
  final RideStatus status;
  final LocationModel pickup;
  final LocationModel destination;
  final double distance;
  final int duration;
  final double price;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final double? rating;
  final int passengers;

  RideModel({
    required this.id,
    required this.userId,
    this.driverId,
    required this.type,
    required this.status,
    required this.pickup,
    required this.destination,
    required this.distance,
    required this.duration,
    required this.price,
    required this.createdAt,
    this.acceptedAt,
    this.startedAt,
    this.completedAt,
    this.rating,
    required this.passengers,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'driverId': driverId,
      'type': type.name,
      'status': status.name,
      'pickup': pickup.toMap(),
      'destination': destination.toMap(),
      'distance': distance,
      'duration': duration,
      'price': price,
      'createdAt': createdAt.toIso8601String(),
      'acceptedAt': acceptedAt?.toIso8601String(),
      'startedAt': startedAt?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'rating': rating,
      'passengers': passengers,
    };
  }

  factory RideModel.fromMap(Map<String, dynamic> map) {
    return RideModel(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      driverId: map['driverId'],
      type: RideType.values.firstWhere(
            (e) => e.name == map['type'],
        orElse: () => RideType.economy,
      ),
      status: RideStatus.values.firstWhere(
            (e) => e.name == map['status'],
        orElse: () => RideStatus.pending,
      ),
      pickup: LocationModel.fromMap(map['pickup'] ?? {}),
      destination: LocationModel.fromMap(map['destination'] ?? {}),
      distance: map['distance']?.toDouble() ?? 0.0,
      duration: map['duration'] ?? 0,
      price: map['price']?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(map['createdAt']),
      acceptedAt: map['acceptedAt'] != null ? DateTime.parse(map['acceptedAt']) : null,
      startedAt: map['startedAt'] != null ? DateTime.parse(map['startedAt']) : null,
      completedAt: map['completedAt'] != null ? DateTime.parse(map['completedAt']) : null,
      rating: map['rating']?.toDouble(),
      passengers: map['passengers'] ?? 1,
    );
  }
}