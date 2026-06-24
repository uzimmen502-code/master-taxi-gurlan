import 'package:cloud_firestore/cloud_firestore.dart';

/// Ҳайдовчи бош экранидаги "Янги буюртма" объекти.
///
/// `trips/{id}` хужжатидан таркибланади, лекин UI учун қулай форматда —
/// `secsLeft` (180 секунд ичида қабул қилиш кутилади), `typeLabel`
/// ("🚕 Алоҳида" / "🚐 Маршрут" / "🚌 Шаҳарлараро").
class TripRequest {
  const TripRequest({
    required this.id,
    required this.userPhone,
    required this.from,
    required this.to,
    required this.taxiType,
    required this.secsLeft,
    this.userName = '',
    this.userGender = '',
    this.userBirthDate = '',
    this.fromLat = 0,
    this.fromLng = 0,
    this.distanceKm = 0,
    this.scheduleId = '',
    this.targetDriverId = '',
  });

  final String id;
  final String userPhone;
  final String from;
  final String to;
  final String taxiType;
  final int secsLeft;
  final String userName;
  final String userGender;
  final String userBirthDate;
  final double fromLat;
  final double fromLng;
  final double distanceKm;
  final String scheduleId;
  final String targetDriverId;

  /// `userBirthDate` (YYYY-MM-DD) дан ёшни ҳисоблайди. Бўш бўлса `null`.
  int? get age {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(userBirthDate);
    if (m == null) return null;
    final y = int.tryParse(m.group(1)!);
    final mo = int.tryParse(m.group(2)!);
    final dd = int.tryParse(m.group(3)!);
    if (y == null || mo == null || dd == null) return null;
    final now = DateTime.now();
    var a = now.year - y;
    if (now.month < mo || (now.month == mo && now.day < dd)) a--;
    return (a >= 0 && a < 120) ? a : null;
  }

  String get typeLabel {
    switch (taxiType) {
      case 'marshrut':
        return '🚐 Маршрут';
      case 'intercity':
        return '🚌 Шаҳарлараро';
      default:
        return '🚕 Алоҳида';
    }
  }

  /// Doc'дан таркиблаш. `secsLeft` бугунги вақт фарқидан ҳисобланади.
  factory TripRequest.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    DateTime? now,
  }) {
    final d = doc.data() ?? const <String, dynamic>{};
    final createdAt = (d['createdAt'] as Timestamp?)?.toDate();
    final n = now ?? DateTime.now();
    int secsLeft = 180;
    if (createdAt != null) {
      final age = n.difference(createdAt).inSeconds;
      secsLeft = (180 - age).clamp(0, 180);
    }
    return TripRequest(
      id: doc.id,
      userPhone: (d['userPhone'] ?? '') as String,
      userName: (d['userName'] ?? '') as String,
      userGender: (d['userGender'] ?? '') as String,
      userBirthDate: (d['userBirthDate'] ?? '') as String,
      fromLat: (d['fromLat'] as num?)?.toDouble() ?? 0,
      fromLng: (d['fromLng'] as num?)?.toDouble() ?? 0,
      from: (d['from'] ?? d['fromAddr'] ?? d['pickupAddr'] ?? '') as String,
      to: (d['to'] ?? d['toAddr'] ?? '') as String,
      taxiType: (d['taxiType'] ?? 'alone') as String,
      secsLeft: secsLeft,
      scheduleId: (d['scheduleId'] ?? '') as String,
      targetDriverId: (d['targetDriverId'] ?? '') as String,
    );
  }
}
