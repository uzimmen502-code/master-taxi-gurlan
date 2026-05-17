import 'package:cloud_firestore/cloud_firestore.dart';

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
