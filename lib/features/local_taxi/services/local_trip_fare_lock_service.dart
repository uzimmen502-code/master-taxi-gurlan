import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../services/google_directions_service.dart';
import '../../../utils/fare_calculator.dart';

/// Mahalliy taksi yo'lkira qulfi.
///
/// Destination bo'lganda Directions (oddiy/optimal marshrut) bo'yicha
/// masofa hisoblanadi, [FareCalculator] bilan narx yoziladi va
/// `lockedFare` sifatida qotiriladi. Trafik / yo'ldan og'ish narxni
/// o'zgartirmaydi — faqat destination o'zgarsa qayta qulflanadi.
class LocalTripFareLockService {
  LocalTripFareLockService({
    FirebaseFirestore? db,
    GoogleDirectionsService? directions,
  })  : _trips = (db ?? FirebaseFirestore.instance).collection('trips'),
        _directions = directions ?? GoogleDirectionsService();

  final CollectionReference<Map<String, dynamic>> _trips;
  final GoogleDirectionsService _directions;

  Future<LocalTripFareLockResult> lockFare({
    required String tripId,
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    required String toAddr,
  }) async {
    if (tripId.isEmpty) {
      throw ArgumentError('tripId kerak');
    }
    if (fromLat.abs() < 1e-6 && fromLng.abs() < 1e-6) {
      throw StateError('Pickup koordinatasi yo\'q');
    }
    if (toLat.abs() < 1e-6 && toLng.abs() < 1e-6) {
      throw StateError('Destination koordinatasi yo\'q');
    }

    await FareCalculator.loadPrices(lat: fromLat, lng: fromLng);
    final route = await _directions.fetchSimpleRoute(
      originLat: fromLat,
      originLng: fromLng,
      destinationLat: toLat,
      destinationLng: toLng,
    );
    final fare = FareCalculator.calculate(distanceKm: route.distanceKm);
    if (fare <= 0) {
      throw StateError('Yo\'lkira hisoblanmadi');
    }

    await _trips.doc(tripId).update({
      'toAddr': toAddr,
      'toLat': toLat,
      'toLng': toLng,
      'lockedDistanceKm': route.distanceKm,
      'lockedFare': fare,
      'lockedPolyline': route.polyline,
      'fareLockedAt': FieldValue.serverTimestamp(),
      'fareLockVersion': FieldValue.increment(1),
      // UI mosligi: eski estimatedPrice o'qiydigan joylar locked ni ko'rsatadi.
      'estimatedPrice': fare,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return LocalTripFareLockResult(
      fare: fare,
      distanceKm: route.distanceKm,
      polyline: route.polyline,
    );
  }
}

class LocalTripFareLockResult {
  const LocalTripFareLockResult({
    required this.fare,
    required this.distanceKm,
    required this.polyline,
  });

  final int fare;
  final double distanceKm;
  final String polyline;
}
