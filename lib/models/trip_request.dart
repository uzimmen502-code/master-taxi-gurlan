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
    this.scheduleId = '',
    this.targetDriverId = '',
  });

  final String id;
  final String userPhone;
  final String from;
  final String to;
  final String taxiType;
  final int secsLeft;
  final String scheduleId;
  final String targetDriverId;

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
      from: (d['from'] ?? d['fromAddr'] ?? d['pickupAddr'] ?? '') as String,
      to: (d['to'] ?? d['toAddr'] ?? '') as String,
      taxiType: (d['taxiType'] ?? 'alone') as String,
      secsLeft: secsLeft,
      scheduleId: (d['scheduleId'] ?? '') as String,
      targetDriverId: (d['targetDriverId'] ?? '') as String,
    );
  }
}
