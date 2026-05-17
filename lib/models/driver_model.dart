import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore'dagi `drivers/{uid}` hujjati (real schema'ga mos).
class DriverModel {
  final String id;
  final String name;
  final String phone;
  final String car;
  final String plate;
  final double lat;
  final double lng;
  final bool isOnline;
  final bool isBusy;
  final bool emptyTaxi;
  final double rating;
  final int ratingCount;
  final String destination;

  const DriverModel({
    required this.id,
    this.name = '',
    this.phone = '',
    this.car = '',
    this.plate = '',
    this.lat = 0,
    this.lng = 0,
    this.isOnline = false,
    this.isBusy = false,
    this.emptyTaxi = false,
    this.rating = 0,
    this.ratingCount = 0,
    this.destination = '',
  });

  factory DriverModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return DriverModel(
      id: doc.id,
      name: d['name'] ?? '',
      phone: d['phone'] ?? '',
      car: d['car'] ?? '',
      plate: d['plate'] ?? '',
      lat: (d['lat'] as num?)?.toDouble() ?? 0,
      lng: (d['lng'] as num?)?.toDouble() ?? 0,
      isOnline: (d['isOnline'] ?? false) as bool,
      isBusy: (d['isBusy'] ?? false) as bool,
      emptyTaxi: (d['emptyTaxi'] ?? false) as bool,
      rating: (d['rating'] as num?)?.toDouble() ?? 0,
      ratingCount: (d['ratingCount'] as num?)?.toInt() ?? 0,
      destination: d['destination'] ?? '',
    );
  }

  bool get hasCoordinates => lat != 0 || lng != 0;
}
