import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/gurlan_places.dart';

/// `schedules/{id}` hujjati — marshrut taksi haydovchisining kunlik reysi.
///
/// `stops` — ketma-ket o'tadigan MFY nomlari (yo'nalishga qarab).
/// `direction == 'forward'` bo'lsa, fromIdx < toIdx bo'lishi shart.
class Schedule {
  const Schedule({
    required this.id,
    this.driverId = '',
    this.driverName = '',
    this.driverPhone = '',
    this.car = '',
    this.plate = '',
    this.taxiType = 'marshrut',
    this.date = '',
    this.isActive = true,
    this.seats = 0,
    this.seatsLeft = 0,
    this.price = 0,
    this.startTime = '',
    this.plannedStartAt,
    this.actualOnlineAt,
    this.queueEligibleAt,
    this.todayTrips = 0,
    this.todayRejects = 0,
    this.todayTimeouts = 0,
    this.from = '',
    this.to = '',
    this.direction = 'forward',
    this.stops = const [],
    this.lat,
    this.lng,
    this.onlineAt,
    this.expiresAt,
  });

  final String id;
  final String driverId;
  final String driverName;
  final String driverPhone;
  final String car;
  final String plate;
  final String taxiType;
  final String date;
  final bool isActive;

  /// Реjгистрация пайтидаги жами жойлар (totalSeats).
  final int seats;
  final int seatsLeft;
  final int price;
  final String startTime;
  final Timestamp? plannedStartAt;
  final Timestamp? actualOnlineAt;
  final Timestamp? queueEligibleAt;
  final int todayTrips;
  final int todayRejects;
  final int todayTimeouts;
  final String from;
  final String to;
  final String direction;
  final List<String> stops;
  final double? lat;
  final double? lng;
  final Timestamp? onlineAt;
  final Timestamp? expiresAt;

  bool get hasExpired {
    final e = expiresAt;
    if (e == null) return false;
    return e.compareTo(Timestamp.now()) < 0;
  }

  /// `from` MFY'dan `to` MFY ga yo'l reysning ketma-ketligida tushadiganligi.
  /// Stoplar bo'sh bo'lsa, eski free-text `from/to` maydonlarini tekshiradi.
  bool routeAllows(String fromMfy, String toMfy) {
    final normalize = GurlanPlaces.normalizeMfyName;
    final normFromMfy = normalize(fromMfy);
    final normToMfy = normalize(toMfy);

    if (stops.isEmpty) {
      if (normFromMfy.isEmpty || normToMfy.isEmpty) return true;
      final f = normalize(from).toLowerCase();
      final t = normalize(to).toLowerCase();
      return f.contains(normFromMfy.toLowerCase()) ||
          t.contains(normToMfy.toLowerCase());
    }
    final normalizedStops = stops.map(normalize).toList();
    if (normFromMfy.isNotEmpty && !normalizedStops.contains(normFromMfy)) {
      return false;
    }
    if (normToMfy.isEmpty) return true;
    if (!normalizedStops.contains(normToMfy)) return false;
    final fromIdx = normalizedStops.indexOf(normFromMfy);
    final toIdx = normalizedStops.indexOf(normToMfy);
    if (fromIdx == -1 || toIdx == -1) return false;
    return direction == 'forward' ? fromIdx < toIdx : fromIdx > toIdx;
  }

  factory Schedule.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return Schedule(
      id: doc.id,
      driverId: (d['driverId'] ?? '') as String,
      driverName: (d['driverName'] ?? '') as String,
      driverPhone: (d['driverPhone'] ?? '') as String,
      car: (d['car'] ?? '') as String,
      plate: (d['plate'] ?? '') as String,
      taxiType: (d['taxiType'] ?? 'marshrut') as String,
      date: (d['date'] ?? '') as String,
      isActive: d['isActive'] as bool? ?? true,
      seats: (d['seats'] as num?)?.toInt() ??
          (d['seatsLeft'] as num?)?.toInt() ??
          0,
      seatsLeft: (d['seatsLeft'] as num?)?.toInt() ?? 0,
      price: (d['price'] as num?)?.toInt() ?? 0,
      startTime: (d['startTime'] ?? '') as String,
      plannedStartAt: d['plannedStartAt'] as Timestamp?,
      actualOnlineAt: d['actualOnlineAt'] as Timestamp?,
      queueEligibleAt: d['queueEligibleAt'] as Timestamp?,
      todayTrips: (d['todayTrips'] as num?)?.toInt() ?? 0,
      todayRejects: (d['todayRejects'] as num?)?.toInt() ?? 0,
      todayTimeouts: (d['todayTimeouts'] as num?)?.toInt() ?? 0,
      from: (d['from'] ?? '') as String,
      to: (d['to'] ?? '') as String,
      direction: (d['direction'] ?? 'forward') as String,
      stops: List<String>.from(d['stops'] ?? const []),
      lat: (d['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble(),
      onlineAt: (d['onlineAt'] ?? d['createdAt']) as Timestamp?,
      expiresAt: d['expiresAt'] as Timestamp?,
    );
  }
}
