import '../yuk_accept_radius.dart';
import '../yuk_vehicle_types.dart';

/// Туман ичида юк — live машина ҳолати (`yuk_local_drivers/{phoneUid}`).
enum YukLocalLoadStatus {
  empty,
  busy,
  offline;

  static YukLocalLoadStatus parse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'busy':
        return YukLocalLoadStatus.busy;
      case 'offline':
        return YukLocalLoadStatus.offline;
      default:
        return YukLocalLoadStatus.empty;
    }
  }

  String get wire => name;
}

class YukLocalDriver {
  const YukLocalDriver({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.phone,
    required this.vehicleType,
    required this.plateNumber,
    required this.capacityTons,
    required this.bodyLengthM,
    required this.bodyWidthM,
    required this.bodyHeightM,
    required this.acceptRadiusKm,
    required this.loadStatus,
    required this.online,
    required this.lat,
    required this.lng,
    required this.locationLabel,
    required this.rating,
    required this.completedLoads,
    required this.lastOnlineAt,
    required this.updatedAt,
  });

  final String id;
  final String ownerId;
  final String ownerName;
  final String phone;
  final String vehicleType;
  final String plateNumber;
  final double capacityTons;
  final double bodyLengthM;
  final double bodyWidthM;
  final double bodyHeightM;
  final int acceptRadiusKm;
  final YukLocalLoadStatus loadStatus;
  final bool online;
  final double? lat;
  final double? lng;
  final String locationLabel;
  final double rating;
  final int completedLoads;
  final DateTime? lastOnlineAt;
  final DateTime? updatedAt;

  bool get hasGps =>
      lat != null &&
      lng != null &&
      lat!.abs() > 0.000001 &&
      lng!.abs() > 0.000001;

  bool get isReady =>
      online && loadStatus == YukLocalLoadStatus.empty && hasGps;

  bool coversDistance(double straightKm) {
    if (YukAcceptRadius.isCitywide(acceptRadiusKm)) return true;
    return straightKm <= acceptRadiusKm;
  }

  factory YukLocalDriver.fromFirestore(String id, Map<String, dynamic> j) {
    DateTime? asDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      try {
        return (v as dynamic).toDate() as DateTime;
      } catch (_) {
        return null;
      }
    }

    double asDouble(dynamic v, [double d = 0]) {
      if (v is num) return v.toDouble();
      return double.tryParse('$v') ?? d;
    }

    int asInt(dynamic v, [int d = 0]) {
      if (v is num) return v.round();
      return int.tryParse('$v') ?? d;
    }

    return YukLocalDriver(
      id: id,
      ownerId: '${j['ownerId'] ?? id}'.trim(),
      ownerName: '${j['ownerName'] ?? ''}'.trim(),
      phone: '${j['phone'] ?? ''}'.trim(),
      vehicleType: normalizeYukVehicleType('${j['vehicleType'] ?? ''}'),
      plateNumber: '${j['plateNumber'] ?? ''}'.trim(),
      capacityTons: asDouble(j['capacityTons']),
      bodyLengthM: asDouble(j['bodyLengthM']),
      bodyWidthM: asDouble(j['bodyWidthM']),
      bodyHeightM: asDouble(j['bodyHeightM']),
      acceptRadiusKm: YukAcceptRadius.normalize(asInt(j['acceptRadiusKm'], 20)),
      loadStatus: YukLocalLoadStatus.parse('${j['loadStatus'] ?? ''}'),
      online: j['online'] == true,
      lat: j['lat'] is num ? (j['lat'] as num).toDouble() : null,
      lng: j['lng'] is num ? (j['lng'] as num).toDouble() : null,
      locationLabel: '${j['locationLabel'] ?? ''}'.trim(),
      rating: asDouble(j['rating'], 5),
      completedLoads: asInt(j['completedLoads']),
      lastOnlineAt: asDate(j['lastOnlineAt']),
      updatedAt: asDate(j['updatedAt']),
    );
  }

  YukLocalDriver copyWith({
    String? ownerName,
    String? phone,
    String? vehicleType,
    String? plateNumber,
    double? capacityTons,
    double? bodyLengthM,
    double? bodyWidthM,
    double? bodyHeightM,
    int? acceptRadiusKm,
    YukLocalLoadStatus? loadStatus,
    bool? online,
    double? lat,
    double? lng,
    String? locationLabel,
    double? rating,
    int? completedLoads,
    DateTime? lastOnlineAt,
    DateTime? updatedAt,
  }) {
    return YukLocalDriver(
      id: id,
      ownerId: ownerId,
      ownerName: ownerName ?? this.ownerName,
      phone: phone ?? this.phone,
      vehicleType: vehicleType ?? this.vehicleType,
      plateNumber: plateNumber ?? this.plateNumber,
      capacityTons: capacityTons ?? this.capacityTons,
      bodyLengthM: bodyLengthM ?? this.bodyLengthM,
      bodyWidthM: bodyWidthM ?? this.bodyWidthM,
      bodyHeightM: bodyHeightM ?? this.bodyHeightM,
      acceptRadiusKm: acceptRadiusKm ?? this.acceptRadiusKm,
      loadStatus: loadStatus ?? this.loadStatus,
      online: online ?? this.online,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      locationLabel: locationLabel ?? this.locationLabel,
      rating: rating ?? this.rating,
      completedLoads: completedLoads ?? this.completedLoads,
      lastOnlineAt: lastOnlineAt ?? this.lastOnlineAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Рўйхат сараланган қатор (фойдаланувчи GPS нисбатан).
class YukLocalDriverRanked {
  const YukLocalDriverRanked({
    required this.driver,
    required this.straightKm,
    required this.roadKm,
    required this.etaMinutes,
    required this.inRadius,
  });

  final YukLocalDriver driver;
  final double straightKm;
  final double roadKm;
  final int etaMinutes;
  final bool inRadius;
}
