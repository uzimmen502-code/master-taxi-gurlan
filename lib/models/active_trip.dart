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
  final String userName;
  final String userGender;
  final String userBirthDate;
  final String reservedBy;
  final String taxiType; // alone | marshrut | ...

  // ─── Manzil (alone-taxi uchun lat/lng, marshrut uchun MFY nomlari) ───
  final String fromAddr;
  final String toAddr;
  final double fromLat;
  final double fromLng;
  final double radiusKm;

  final String pickupMfy;
  final String dropoffMfy;

  final double? userLat;
  final double? userLng;
  final double? driverLat;
  final double? driverLng;

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
  final String cancelledBy;
  final String cancelReason;
  final int passengerWalletIntent;
  final int estimatedPrice;
  final double toLat;
  final double toLng;
  final int lockedFare;
  final double lockedDistanceKm;
  final int fareLockVersion;

  const ActiveTrip({
    required this.id,
    this.status = 'searching',
    this.userPhone = '',
    this.userName = '',
    this.userGender = '',
    this.userBirthDate = '',
    this.reservedBy = '',
    this.taxiType = 'alone',
    this.fromAddr = '',
    this.toAddr = '',
    this.fromLat = 0,
    this.fromLng = 0,
    this.radiusKm = 3,
    this.pickupMfy = '',
    this.dropoffMfy = '',
    this.userLat,
    this.userLng,
    this.driverLat,
    this.driverLng,
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
    this.cancelledBy = '',
    this.cancelReason = '',
    this.passengerWalletIntent = 0,
    this.estimatedPrice = 0,
    this.toLat = 0,
    this.toLng = 0,
    this.lockedFare = 0,
    this.lockedDistanceKm = 0,
    this.fareLockVersion = 0,
  });

  bool get isAccepted => status == 'accepted';
  bool get isCancelled => status == 'cancelled';
  bool get isPassengerCancelled =>
      isCancelled &&
      (cancelledBy == 'passenger' || cancelledBy == 'user');
  bool get isDriverNoRoomCancel =>
      isCancelled && cancelledBy == 'driver' && cancelReason == 'no_room';
  bool get isSearching => status == 'searching';
  /// Faol mahalliy qidiruv: `searching` va muddati o'tmagan.
  bool get isActiveSearchOffer => isSearching && !isExpired;
  bool get isReserved => status == 'reserved';
  bool get isRejected => status == 'rejected';
  bool get isNoSeats => status == 'no_seats';
  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now());
  bool get hasLockedFare => lockedFare > 0;
  /// UI uchun: qulflangan narx, yo'q bo'lsa legacy estimatedPrice.
  int get displayFare => lockedFare > 0 ? lockedFare : estimatedPrice;

  factory ActiveTrip.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return ActiveTrip(
      id: doc.id,
      status: d['status'] ?? 'searching',
      userPhone: d['userPhone'] ?? '',
      userName: d['userName'] ?? '',
      userGender: d['userGender'] ?? '',
      userBirthDate: d['userBirthDate'] ?? '',
      reservedBy: d['reservedBy'] ?? '',
      taxiType: d['taxiType'] ?? 'alone',
      fromAddr: d['fromAddr'] ?? d['from'] ?? d['pickupAddr'] ?? '',
      toAddr: d['toAddr'] ?? d['to'] ?? '',
      fromLat: (d['fromLat'] as num?)?.toDouble() ?? 0,
      fromLng: (d['fromLng'] as num?)?.toDouble() ?? 0,
      radiusKm: (d['radiusKm'] as num?)?.toDouble() ?? 3,
      pickupMfy: d['pickupMfy'] ?? '',
      dropoffMfy: d['dropoffMfy'] ?? '',
      userLat: (d['userLat'] as num?)?.toDouble(),
      userLng: (d['userLng'] as num?)?.toDouble(),
      driverLat: (d['driverLat'] as num?)?.toDouble(),
      driverLng: (d['driverLng'] as num?)?.toDouble(),
      driverId: d['driverId'] ?? d['acceptedDriverId'] ?? '',
      driverName: d['driverName'] ?? d['acceptedDriverName'] ?? '',
      driverPhone:
          d['driverPhone'] ?? d['acceptedDriverPhone'] ?? '',
      driverCar: d['driverCar'] ?? d['acceptedDriverCar'] ?? '',
      driverPlate: d['driverPlate'] ?? d['acceptedDriverPlate'] ?? '',
      fare: (d['fare'] as num?)?.toInt() ?? 0,
      targetDriverId: (d['targetDriverId'] ?? '') as String,
      scheduleId: (d['scheduleId'] ?? '') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
      offerTimeoutSeconds: (d['offerTimeoutSeconds'] as num?)?.toInt() ?? 0,
      cancelledBy: (d['cancelledBy'] ?? '') as String,
      cancelReason: (d['cancelReason'] ?? '') as String,
      passengerWalletIntent: (d['passengerWalletIntent'] as num?)?.toInt() ?? 0,
      estimatedPrice: (d['estimatedPrice'] as num?)?.toInt() ?? 0,
      toLat: (d['toLat'] as num?)?.toDouble() ?? 0,
      toLng: (d['toLng'] as num?)?.toDouble() ?? 0,
      lockedFare: (d['lockedFare'] as num?)?.toInt() ?? 0,
      lockedDistanceKm: (d['lockedDistanceKm'] as num?)?.toDouble() ?? 0,
      fareLockVersion: (d['fareLockVersion'] as num?)?.toInt() ?? 0,
    );
  }
}
