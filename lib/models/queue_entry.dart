import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/gurlan_places.dart';

/// `queue/{driverId}` ҳужжатини ифодалайди.
class QueueEntry {
  const QueueEntry({
    required this.driverId,
    required this.driverName,
    required this.car,
    this.driverPhone = '',
    this.plate = '',
    required this.from,
    required this.to,
    required this.seatsLeft,
    this.price = 0,
    this.direction = 'forward',
    this.stops = const [],
    this.lat,
    this.lng,
    this.onlineAt,
    this.plannedStartAt,
    this.actualOnlineAt,
    this.queueEligibleAt,
    this.todayTrips = 0,
    this.todayRejects = 0,
    this.todayTimeouts = 0,
    this.expiresAt,
    this.taxiType = '',
    this.scheduleId = '',
  });

  final String driverId;
  final String driverName;
  final String driverPhone;
  final String car;
  final String plate;
  final String from;
  final String to;
  final int seatsLeft;
  final int price;
  final String direction;
  final List<String> stops;
  final double? lat;
  final double? lng;
  final DateTime? onlineAt;
  final DateTime? plannedStartAt;
  final DateTime? actualOnlineAt;
  final DateTime? queueEligibleAt;
  final int todayTrips;
  final int todayRejects;
  final int todayTimeouts;
  final DateTime? expiresAt;
  final String taxiType;
  final String scheduleId;

  bool get hasExpired {
    final e = expiresAt;
    if (e == null) return false;
    return e.isBefore(DateTime.now());
  }

  bool get isTimeEligible {
    if (actualOnlineAt != null) return true;
    final eligible = queueEligibleAt;
    if (eligible == null) return false;
    return !eligible.isAfter(DateTime.now());
  }

  int get todayMisses => todayRejects + todayTimeouts;

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

  factory QueueEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return QueueEntry(
      driverId: doc.id,
      driverName: (d['driverName'] ?? '') as String,
      driverPhone: (d['driverPhone'] ?? '') as String,
      car: (d['car'] ?? '') as String,
      plate: (d['plate'] ?? '') as String,
      from: (d['from'] ?? '') as String,
      to: (d['to'] ?? '') as String,
      seatsLeft: (d['seatsLeft'] as num?)?.toInt() ?? 0,
      price: (d['price'] as num?)?.toInt() ?? 0,
      direction: (d['direction'] ?? 'forward') as String,
      stops: List<String>.from(d['stops'] ?? const []),
      lat: (d['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble(),
      onlineAt: (d['onlineAt'] as Timestamp?)?.toDate(),
      plannedStartAt: (d['plannedStartAt'] as Timestamp?)?.toDate(),
      actualOnlineAt: (d['actualOnlineAt'] as Timestamp?)?.toDate(),
      queueEligibleAt: (d['queueEligibleAt'] as Timestamp?)?.toDate(),
      todayTrips: (d['todayTrips'] as num?)?.toInt() ?? 0,
      todayRejects: (d['todayRejects'] as num?)?.toInt() ?? 0,
      todayTimeouts: (d['todayTimeouts'] as num?)?.toInt() ?? 0,
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
      taxiType: (d['taxiType'] ?? '') as String,
      scheduleId: (d['scheduleId'] ?? '') as String,
    );
  }
}
