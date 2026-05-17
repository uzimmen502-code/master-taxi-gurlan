import 'package:cloud_firestore/cloud_firestore.dart';

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
  final DateTime? expiresAt;
  final String taxiType;
  final String scheduleId;

  bool get hasExpired {
    final e = expiresAt;
    if (e == null) return false;
    return e.isBefore(DateTime.now());
  }

  bool routeAllows(String fromMfy, String toMfy) {
    if (stops.isEmpty) {
      if (fromMfy.isEmpty || toMfy.isEmpty) return true;
      final f = from.toLowerCase();
      final t = to.toLowerCase();
      return f.contains(fromMfy.toLowerCase()) ||
          t.contains(toMfy.toLowerCase());
    }
    if (fromMfy.isNotEmpty && !stops.contains(fromMfy)) return false;
    if (toMfy.isEmpty) return true;
    if (!stops.contains(toMfy)) return false;
    final fromIdx = stops.indexOf(fromMfy);
    final toIdx = stops.indexOf(toMfy);
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
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
      taxiType: (d['taxiType'] ?? '') as String,
      scheduleId: (d['scheduleId'] ?? '') as String,
    );
  }
}
