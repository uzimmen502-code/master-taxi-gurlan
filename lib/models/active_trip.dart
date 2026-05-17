import 'package:cloud_firestore/cloud_firestore.dart';

/// `trips/{id}` hujjati "qidiruv" yoki "qabul qilingan" holatida.
///
/// `TripModel` esa **yakunlangan** safarlar uchun ishlatiladi.
/// Ikki model — bir collection, lekin lifecycle'ga qarab turli yaqinlashish.
class ActiveTrip {
  final String id;
  final String status; // searching | pending | accepted | rejected |
  // no_seats | expired | completed | cancelled
  final String userPhone;
  final String taxiType; // alone | marshrut | ...

  // ─── Manzil (alone-taxi uchun lat/lng, marshrut uchun MFY nomlari) ───
  final String fromAddr;
  final String toAddr;
  final double fromLat;
  final double fromLng;
  final double radiusKm;

  final String pickupMfy;
  final String dropoffMfy;

  // ─── Haydovchi ──────────────────────────────────────────────────────
  final String driverId;
  final String driverName;
  final String driverPhone;
  final String driverCar;
  final String driverPlate;
  final int fare;

  /// Marshrut trip yo'naltirilган target driverID (pending uchun).
  final String targetDriverId;

  /// Bog'liq schedule (seatsLeft transaction'da kerак).
  final String scheduleId;

  final DateTime? createdAt;
  final DateTime? expiresAt;
  final int offerTimeoutSeconds;

  const ActiveTrip({
    required this.id,
    this.status = 'searching',
    this.userPhone = '',
    this.taxiType = 'alone',
    this.fromAddr = '',
    this.toAddr = '',
    this.fromLat = 0,
    this.fromLng = 0,
    this.radiusKm = 3,
    this.pickupMfy = '',
    this.dropoffMfy = '',
    this.driverId = '',
    this.driverName = '',
    this.driverPhone = '',
    this.driverCar = '',
    this.driverPlate = '',
    this.fare = 0,
    this.targetDriverId = '',
    this.scheduleId = '',
    this.createdAt,
    this.expiresAt,
    this.offerTimeoutSeconds = 0,
  });

  bool get isAccepted => status == 'accepted';
  bool get isSearching => status == 'searching';
  bool get isRejected => status == 'rejected';
  bool get isNoSeats => status == 'no_seats';
  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now());

  factory ActiveTrip.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return ActiveTrip(
      id: doc.id,
      status: d['status'] ?? 'searching',
      userPhone: d['userPhone'] ?? '',
      taxiType: d['taxiType'] ?? 'alone',
      fromAddr: d['fromAddr'] ?? d['from'] ?? d['pickupAddr'] ?? '',
      toAddr: d['toAddr'] ?? d['to'] ?? '',
      fromLat: (d['fromLat'] as num?)?.toDouble() ?? 0,
      fromLng: (d['fromLng'] as num?)?.toDouble() ?? 0,
      radiusKm: (d['radiusKm'] as num?)?.toDouble() ?? 3,
      pickupMfy: d['pickupMfy'] ?? '',
      dropoffMfy: d['dropoffMfy'] ?? '',
      driverId: d['driverId'] ?? d['acceptedDriverId'] ?? '',
      driverName: d['driverName'] ?? d['acceptedDriverName'] ?? '',
      driverPhone: d['driverPhone'] ?? '',
      driverCar: d['driverCar'] ?? d['acceptedDriverCar'] ?? '',
      driverPlate: d['driverPlate'] ?? d['acceptedDriverPlate'] ?? '',
      fare: (d['fare'] as num?)?.toInt() ?? 0,
      targetDriverId: (d['targetDriverId'] ?? '') as String,
      scheduleId: (d['scheduleId'] ?? '') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
      offerTimeoutSeconds: (d['offerTimeoutSeconds'] as num?)?.toInt() ?? 0,
    );
  }
}
