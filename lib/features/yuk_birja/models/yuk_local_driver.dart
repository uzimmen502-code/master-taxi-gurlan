import '../yuk_accept_radius.dart';
import '../yuk_local_schedule.dart';
import '../yuk_vehicle_types.dart';

/// Туман ичида юк эълони (`yuk_local_drivers/{autoId}`).
/// Жойлашув + иш вақти; «онлайн» присутствие йўқ.
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
    required this.capacityKg,
    required this.bodyLengthM,
    required this.bodyWidthM,
    required this.bodyHeightM,
    required this.acceptRadiusKm,
    required this.loadStatus,
    required this.lat,
    required this.lng,
    required this.locationLabel,
    required this.workStartMinutes,
    required this.workEndMinutes,
    required this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
    this.rating = 0,
    this.completedLoads = 0,
    this.isDemo = false,
    // Эски майдонлар — ўқиш учун (UI ишлатмайди).
    this.online = false,
    this.lastOnlineAt,
  });

  final String id;
  final String ownerId;
  final String ownerName;
  final String phone;
  final String vehicleType;
  final String plateNumber;

  /// Юк кўтариши — **килограмм**.
  final double capacityKg;
  final double bodyLengthM;
  final double bodyWidthM;
  final double bodyHeightM;
  final int acceptRadiusKm;
  final YukLocalLoadStatus loadStatus;
  final double? lat;
  final double? lng;
  final String locationLabel;

  /// Иш вақти — кун бошидан дақиқа (0…1440).
  final int workStartMinutes;
  final int workEndMinutes;

  final DateTime? expiresAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  final double rating;
  final int completedLoads;
  final bool isDemo;

  @Deprecated('Онлайн модель олиб ташланди — жой + иш вақти')
  final bool online;
  @Deprecated('Онлайн модель олиб ташланди')
  final DateTime? lastOnlineAt;

  bool get hasGps =>
      lat != null &&
      lng != null &&
      lat!.abs() > 0.000001 &&
      lng!.abs() > 0.000001;

  bool isExpired([DateTime? now]) {
    if (isDemo) return false;
    final exp = expiresAt;
    if (exp == null) return false;
    return (now ?? DateTime.now()).isAfter(exp);
  }

  bool isWithinWorkHours([DateTime? now]) => YukLocalSchedule.isWithinWorkHours(
        workStartMinutes: workStartMinutes,
        workEndMinutes: workEndMinutes,
        now: now,
      );

  /// Қидирувчига кўринадими.
  bool get isVisibleInSearch =>
      hasGps && !isExpired() && isWithinWorkHours();

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

    final created = asDate(j['createdAt']);
    final expires = asDate(j['expiresAt']);

    return YukLocalDriver(
      id: id,
      ownerId: '${j['ownerId'] ?? id}'.trim(),
      ownerName: '${j['ownerName'] ?? ''}'.trim(),
      phone: '${j['phone'] ?? ''}'.trim(),
      vehicleType: normalizeYukVehicleType('${j['vehicleType'] ?? ''}'),
      plateNumber: '${j['plateNumber'] ?? ''}'.trim(),
      capacityKg: j['capacityKg'] != null
          ? asDouble(j['capacityKg'])
          : asDouble(j['capacityTons']) * 1000,
      bodyLengthM: asDouble(j['bodyLengthM']),
      bodyWidthM: asDouble(j['bodyWidthM']),
      bodyHeightM: asDouble(j['bodyHeightM']),
      acceptRadiusKm: YukAcceptRadius.normalize(asInt(j['acceptRadiusKm'], 20)),
      loadStatus: YukLocalLoadStatus.parse('${j['loadStatus'] ?? ''}'),
      lat: j['lat'] is num ? (j['lat'] as num).toDouble() : null,
      lng: j['lng'] is num ? (j['lng'] as num).toDouble() : null,
      locationLabel: '${j['locationLabel'] ?? ''}'.trim(),
      workStartMinutes: asInt(
        j['workStartMinutes'],
        YukLocalSchedule.defaultWorkStartMinutes,
      ),
      workEndMinutes: asInt(
        j['workEndMinutes'],
        YukLocalSchedule.defaultWorkEndMinutes,
      ),
      expiresAt: expires,
      createdAt: created,
      updatedAt: asDate(j['updatedAt']),
      rating: asDouble(j['rating'], 0),
      completedLoads: asInt(j['completedLoads']),
      isDemo: j['isDemo'] == true,
      online: j['online'] == true,
      lastOnlineAt: asDate(j['lastOnlineAt']),
    );
  }

  YukLocalDriver copyWith({
    String? ownerName,
    String? phone,
    String? vehicleType,
    String? plateNumber,
    double? capacityKg,
    double? bodyLengthM,
    double? bodyWidthM,
    double? bodyHeightM,
    int? acceptRadiusKm,
    YukLocalLoadStatus? loadStatus,
    double? lat,
    double? lng,
    String? locationLabel,
    int? workStartMinutes,
    int? workEndMinutes,
    DateTime? expiresAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return YukLocalDriver(
      id: id,
      ownerId: ownerId,
      ownerName: ownerName ?? this.ownerName,
      phone: phone ?? this.phone,
      vehicleType: vehicleType ?? this.vehicleType,
      plateNumber: plateNumber ?? this.plateNumber,
      capacityKg: capacityKg ?? this.capacityKg,
      bodyLengthM: bodyLengthM ?? this.bodyLengthM,
      bodyWidthM: bodyWidthM ?? this.bodyWidthM,
      bodyHeightM: bodyHeightM ?? this.bodyHeightM,
      acceptRadiusKm: acceptRadiusKm ?? this.acceptRadiusKm,
      loadStatus: loadStatus ?? this.loadStatus,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      locationLabel: locationLabel ?? this.locationLabel,
      workStartMinutes: workStartMinutes ?? this.workStartMinutes,
      workEndMinutes: workEndMinutes ?? this.workEndMinutes,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rating: rating,
      completedLoads: completedLoads,
      isDemo: isDemo,
      online: online,
      lastOnlineAt: lastOnlineAt,
    );
  }
}

/// Рўйхат сараланган қатор (қидирувчи GPS нисбатан эълон жойи).
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
