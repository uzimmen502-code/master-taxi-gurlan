import 'package:cloud_functions/cloud_functions.dart';

/// Mahalliy taksi yo'lkirasi — FAQAT server (`functions/local_taxi.js`).
///
/// Ega qarori (2026-10-07): narx serverda hisoblanadi va trip'ga
/// `tariffVersion` bilan qotiriladi; manzil majburiy; qo'shimcha koeffitsient
/// faqat tun (server vaqti). Klient narx hisoblamaydi va `lockedFare` yozmaydi.
class LocalTripFareLockService {
  LocalTripFareLockService({FirebaseFunctions? functions})
      : _fn = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _fn;

  /// Yangi buyurtma: server trip'ni narxi qotirilgan holda yaratadi.
  /// [requestId] — qayta urinishda dublikat bo'lmasligi uchun (bir buyurtma = bir id).
  Future<LocalTripCreateResult> createTrip({
    required String requestId,
    required String fromAddr,
    required double fromLat,
    required double fromLng,
    required String toAddr,
    required double toLat,
    required double toLng,
    String userName = '',
    String userGender = '',
    String userBirthDate = '',
    Map<String, dynamic> report = const {},
  }) async {
    final res = await _fn.httpsCallable('createLocalTaxiTrip').call(
      <String, dynamic>{
        'requestId': requestId,
        'fromAddr': fromAddr,
        'fromLat': fromLat,
        'fromLng': fromLng,
        'toAddr': toAddr,
        'toLat': toLat,
        'toLng': toLng,
        'userName': userName,
        'userGender': userGender,
        'userBirthDate': userBirthDate,
        'report': report,
      },
    );
    final map = Map<String, dynamic>.from(res.data as Map);
    return LocalTripCreateResult(
      tripId: (map['tripId'] ?? '') as String,
      fare: (map['fare'] as num?)?.toInt() ?? 0,
    );
  }

  /// Eski (narxsiz) trip'ga manzil qo'yish / manzilni o'zgartirish —
  /// narxni server qayta hisoblaydi. Pickup — trip'dagi `fromLat/fromLng`.
  Future<LocalTripFareLockResult> lockFare({
    required String tripId,
    required double toLat,
    required double toLng,
    required String toAddr,
  }) async {
    if (tripId.isEmpty) {
      throw ArgumentError('tripId kerak');
    }
    final res = await _fn.httpsCallable('lockLocalTripFare').call(
      <String, dynamic>{
        'tripId': tripId,
        'toLat': toLat,
        'toLng': toLng,
        'toAddr': toAddr,
      },
    );
    final map = Map<String, dynamic>.from(res.data as Map);
    return LocalTripFareLockResult(
      fare: (map['fare'] as num?)?.toInt() ?? 0,
      distanceKm: (map['distanceKm'] as num?)?.toDouble() ?? 0,
      polyline: (map['polyline'] ?? '') as String,
    );
  }

  /// Server diagnostika kodi → foydalanuvchi matni kaliti (uch tilda).
  static String errorKey(Object error) {
    if (error is FirebaseFunctionsException) {
      final details = error.details;
      final code = details is Map ? '${details['code'] ?? ''}' : '';
      switch (code) {
        case 'DESTINATION_REQUIRED':
          return 'local_destination_required';
        case 'ROUTE_NOT_FOUND':
        case 'ROUTE_UNAVAILABLE':
          return 'local_route_failed';
        case 'TARIFF_NOT_CONFIGURED':
          return 'local_tariff_missing';
        case 'LOCAL_TAXI_BLOCKED':
          return 'local_taxi_block_active|${details is Map ? details['minutes'] ?? 1 : 1}';
        case 'PICKUP_REQUIRED':
          return 'local_gps_required_for_search';
      }
    }
    return 'local_order_failed';
  }
}

class LocalTripCreateResult {
  const LocalTripCreateResult({required this.tripId, required this.fare});

  final String tripId;
  final int fare;
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
