import 'package:cloud_firestore/cloud_firestore.dart';

/// ⚡ Электромобил зарядлаш нуқтаси — жамоа (foydalanuvchilar) tomonidan
/// to'ldiriladigan `ev_charging_stations` hujjati.
///
/// `name`, `workingHours`, `photo` — MVP modelga qo'shilmaydi (texnik
/// topshiriq 10-band). Koordinata majburiy, qolgan hamma maydon ixtiyoriy.
class EvChargingStation {
  const EvChargingStation({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.geohash,
    required this.chargingTypes,
    required this.connectors,
    required this.status,
    required this.verificationStatus,
    required this.confirmationCount,
    required this.reportCount,
    required this.createdBy,
    required this.isActive,
    this.powerKw,
    this.price,
    this.operatorName,
    this.note,
    this.createdAt,
    this.updatedAt,
    this.lastConfirmedAt,
  });

  final String id;
  final double latitude;
  final double longitude;
  final String geohash;

  /// `AC` / `DC` / `AC+DC` — bo'sh bo'lishi mumkin.
  final List<String> chargingTypes;

  /// `CCS2`, `Type 2`, `GB/T`, `CHAdeMO`, boshqa — bir nechta tanlash mumkin.
  final List<String> connectors;

  final num? powerKw;
  final num? price;
  final String? operatorName;
  final String? note;

  /// `working` | `partially_working` | `not_working` | `unknown`.
  final String status;

  /// `community` | `verified` | `operator_verified` (kelajak uchun).
  final String verificationStatus;

  final int confirmationCount;
  final int reportCount;

  /// `users/{phoneDigits}` hujjat ID'i — Firebase UID emas (24-bandga qarang).
  final String createdBy;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastConfirmedAt;

  final bool isActive;

  bool get hasChargingType => chargingTypes.isNotEmpty;
  bool get hasConnectors => connectors.isNotEmpty;
  bool get hasPowerKw => powerKw != null;
  bool get hasPrice => price != null;
  bool get hasOperatorName => (operatorName ?? '').trim().isNotEmpty;
  bool get hasNote => (note ?? '').trim().isNotEmpty;

  factory EvChargingStation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final location = (d['location'] as Map?) ?? const {};
    return EvChargingStation(
      id: doc.id,
      latitude: (location['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (location['longitude'] as num?)?.toDouble() ?? 0,
      geohash: (d['geohash'] ?? '') as String,
      chargingTypes: List<String>.from(d['chargingTypes'] as List? ?? const []),
      connectors: List<String>.from(d['connectors'] as List? ?? const []),
      powerKw: d['powerKw'] as num?,
      price: d['price'] as num?,
      operatorName: d['operatorName'] as String?,
      note: d['note'] as String?,
      status: (d['status'] ?? 'unknown') as String,
      verificationStatus: (d['verificationStatus'] ?? 'community') as String,
      confirmationCount: (d['confirmationCount'] as num?)?.toInt() ?? 0,
      reportCount: (d['reportCount'] as num?)?.toInt() ?? 0,
      createdBy: (d['createdBy'] ?? '') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      lastConfirmedAt: (d['lastConfirmedAt'] as Timestamp?)?.toDate(),
      isActive: d['isActive'] != false,
    );
  }
}
