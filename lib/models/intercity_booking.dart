import 'package:cloud_firestore/cloud_firestore.dart';

/// Бронь ҳолатлари. Иккита терминал ҳолат — `completed` ва `cancelled`/`expired`.
class IntercityBookingStatus {
  IntercityBookingStatus._();

  /// Бронь яратилди, ҳайдовчи ҳали тасдиқламаган.
  /// (Hozircha intercity haydovchi-paneli yo'q — booking auto-confirm bo'ladi.)
  static const String pending = 'pending';

  /// Ҳайдовчи бронни тасдиқлади / auto-confirmed.
  static const String confirmed = 'confirmed';

  /// Сафар бажарилди.
  static const String completed = 'completed';

  /// Мижоз ёки ҳайдовчи бекор қилди.
  static const String cancelled = 'cancelled';

  /// Тасдиқланмай муддати ўтиб кетди.
  static const String expired = 'expired';

  /// "Тирик" ҳолатлар — бекор қилиш мумкин, мижозга кўрсатилади.
  static const Set<String> active = {pending, confirmed};
}

/// `intercity_bookings/{bookingId}` hujjati.
///
/// Шаҳарлараро такси учун **ишончли бронь** — реал Firestore ёзуви:
///   - тариfic-тариfic seat reservation (transactional)
///   - status machine (pending → confirmed → completed / cancelled)
///   - ҳар bron `driver+client` aggregation (`intercity_drivers/{id}/clients/{phone}`)
///     учун manba — "доимий мижоз" базаси шу ердан қурилади.
class IntercityBooking {
  const IntercityBooking({
    required this.id,
    required this.userPhone,
    required this.userName,
    required this.driverId,
    required this.driverPhone,
    required this.driverName,
    required this.carNumber,
    required this.fromCity,
    required this.toCity,
    required this.district,
    required this.passengers,
    required this.pricePerSeat,
    required this.totalAmount,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.departureTime,
    this.confirmedAt,
    this.completedAt,
    this.cancelledAt,
    this.cancelReason,
  });

  final String id;
  final String userPhone;
  final String userName;
  final String driverId;
  final String driverPhone;
  final String driverName;
  final String carNumber;
  final String fromCity;
  final String toCity;
  final String district;
  final int passengers;
  final int pricePerSeat;
  final int totalAmount;
  final String status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime departureTime;
  final DateTime? confirmedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;

  bool get isActive => IntercityBookingStatus.active.contains(status);
  bool get isCancellable => isActive;

  /// `bookingId` нинг охирги 6 та белгиси — мижозга кўрсатиш учун қисқа реф.
  String get shortRef =>
      id.length > 6 ? id.substring(id.length - 6).toUpperCase() : id.toUpperCase();

  /// Маршрут қисқача: "Хоразм → Тошкент".
  String get routeShort {
    final to = district.isNotEmpty ? '$toCity • $district' : toCity;
    return '$fromCity → $to';
  }

  factory IntercityBooking.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    DateTime ts(String k, {DateTime? fallback}) {
      final v = d[k];
      if (v is Timestamp) return v.toDate();
      return fallback ?? DateTime.now();
    }

    DateTime? tsOpt(String k) {
      final v = d[k];
      if (v is Timestamp) return v.toDate();
      return null;
    }

    return IntercityBooking(
      id: doc.id,
      userPhone: (d['userPhone'] ?? '') as String,
      userName: (d['userName'] ?? '') as String,
      driverId: (d['driverId'] ?? '') as String,
      driverPhone: (d['driverPhone'] ?? '') as String,
      driverName: (d['driverName'] ?? '') as String,
      carNumber: (d['carNumber'] ?? '') as String,
      fromCity: (d['fromCity'] ?? '') as String,
      toCity: (d['toCity'] ?? '') as String,
      district: (d['district'] ?? '') as String,
      passengers: (d['passengers'] as num?)?.toInt() ?? 1,
      pricePerSeat: (d['pricePerSeat'] as num?)?.toInt() ?? 0,
      totalAmount: (d['totalAmount'] as num?)?.toInt() ?? 0,
      status: (d['status'] ?? IntercityBookingStatus.pending) as String,
      createdAt: ts('createdAt'),
      expiresAt: ts('expiresAt',
          fallback: DateTime.now().add(const Duration(minutes: 30))),
      departureTime: ts('departureTime'),
      confirmedAt: tsOpt('confirmedAt'),
      completedAt: tsOpt('completedAt'),
      cancelledAt: tsOpt('cancelledAt'),
      cancelReason: d['cancelReason'] as String?,
    );
  }
}
