import 'package:cloud_firestore/cloud_firestore.dart';

/// Фойдаланувчи яшаш манзили — курьер ва модулларда ишлатилади.
///
/// **Икки манба бирваракай мажбурий:**
///   - **GPS** (`lat/lng/accuracy/geoUpdatedAt`) — карта ва yo'l учун аниқ нуқта
///   - **Қўлда** (`mfy/street/house/district/note/manualUpdatedAt`) — GPS
///     нотўғри/мавжуд бўлмаганда курьер мўлжал қилади
///
/// `isComplete` иккаласи ҳам тўлдирилгандагина `true` qaytaradi.
class UserAddress {
  const UserAddress({
    this.mfy = '',
    this.street = '',
    this.house = '',
    this.district = '',
    this.note = '',
    this.lat,
    this.lng,
    this.accuracy,
    this.geoUpdatedAt,
    this.manualUpdatedAt,
  });

  /// Маҳалла фуқаролар йиғини (мажбурий).
  final String mfy;

  /// Кўча / гузар номи (мажбурий).
  final String street;

  /// Уй рақами (мажбурий).
  final String house;

  /// Туман (default: Гурлан).
  final String district;

  /// Қўшимча — подъезд, қават, ориентир.
  final String note;

  /// GPS координаталари — **мажбурий**, бирок Firestore тарихий ҳужжатларда
  /// `null` бўлиши мумкин (миграция учун).
  final double? lat;
  final double? lng;

  /// GPS аниқлиги (метрда). 0–20 — юқори, 20–100 — ўрта, >100 — паст.
  final double? accuracy;

  /// GPS қачон олинди.
  final DateTime? geoUpdatedAt;

  /// Қўлдаги манзил қачон ёзилди.
  final DateTime? manualUpdatedAt;

  /// Формат: `MFY, кўча, уй №X (туман)` — UI'да кўрсатиш учун.
  String get formatted {
    final parts = <String>[];
    if (mfy.isNotEmpty) parts.add(mfy);
    if (street.isNotEmpty) parts.add(street);
    if (house.isNotEmpty) parts.add('уй №$house');
    final base = parts.join(', ');
    if (district.isEmpty) return base;
    return base.isEmpty ? district : '$base ($district)';
  }

  /// Қўлдаги мажбурий 3 та майдон тўлдирилганми? (МФЙ + кўча + уй).
  bool get hasManualAddress =>
      mfy.trim().isNotEmpty &&
      street.trim().isNotEmpty &&
      house.trim().isNotEmpty;

  /// GPS координаталари мавжудми? (0,0 ҳам йўқ деб ҳисобланади)
  bool get hasGps {
    if (lat == null || lng == null) return false;
    if (lat!.abs() < 1e-6 && lng!.abs() < 1e-6) return false;
    return lat! >= -90 && lat! <= 90 && lng! >= -180 && lng! <= 180;
  }

  /// Сақлаш/буюртма учун валидация хабари (null = тўлиқ).
  String? get validationError {
    if (!hasManualAddress) {
      return 'МФЙ, кўча ва уй рақами мажбурий';
    }
    if (!hasGps) {
      return 'GPS координаталари мажбурий — «Жорий GPS манзилни олиш»';
    }
    return null;
  }

  /// **Тўлиқ манзил** — қўлда + GPS, иккаласи ҳам Firestore профилида сақланган.
  bool get isComplete => validationError == null;

  /// GPS аниқлиги категорияси (UI badge учун).
  /// `null` — GPS йўқ, `high` — <20m, `medium` — 20–100m, `low` — >100m.
  GpsQuality get gpsQuality {
    if (!hasGps || accuracy == null) {
      return hasGps ? GpsQuality.unknown : GpsQuality.none;
    }
    if (accuracy! <= 20) return GpsQuality.high;
    if (accuracy! <= 100) return GpsQuality.medium;
    return GpsQuality.low;
  }

  Map<String, dynamic> toMap() => {
        'mfy': mfy,
        'street': street,
        'house': house,
        'district': district,
        'note': note,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (accuracy != null) 'accuracy': accuracy,
        if (geoUpdatedAt != null)
          'geoUpdatedAt': Timestamp.fromDate(geoUpdatedAt!),
        if (manualUpdatedAt != null)
          'manualUpdatedAt': Timestamp.fromDate(manualUpdatedAt!),
      };

  factory UserAddress.fromMap(Map<String, dynamic>? d) {
    if (d == null) return const UserAddress();
    return UserAddress(
      mfy: (d['mfy'] ?? '') as String,
      street: (d['street'] ?? '') as String,
      house: (d['house'] ?? '') as String,
      district: (d['district'] ?? '') as String,
      note: (d['note'] ?? '') as String,
      lat: (d['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble(),
      accuracy: (d['accuracy'] as num?)?.toDouble(),
      geoUpdatedAt: (d['geoUpdatedAt'] as Timestamp?)?.toDate(),
      manualUpdatedAt: (d['manualUpdatedAt'] as Timestamp?)?.toDate(),
    );
  }

  UserAddress copyWith({
    String? mfy,
    String? street,
    String? house,
    String? district,
    String? note,
    double? lat,
    double? lng,
    double? accuracy,
    DateTime? geoUpdatedAt,
    DateTime? manualUpdatedAt,
  }) {
    return UserAddress(
      mfy: mfy ?? this.mfy,
      street: street ?? this.street,
      house: house ?? this.house,
      district: district ?? this.district,
      note: note ?? this.note,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      accuracy: accuracy ?? this.accuracy,
      geoUpdatedAt: geoUpdatedAt ?? this.geoUpdatedAt,
      manualUpdatedAt: manualUpdatedAt ?? this.manualUpdatedAt,
    );
  }
}

/// GPS аниқлиги категорияси — UI'да badge кўрсатиш учун.
enum GpsQuality {
  /// GPS координаталари йўқ.
  none,

  /// GPS бор, лекин аниқлик метрi номаълум.
  unknown,

  /// ≤ 20m — шаҳарда яшаш манзили учун аъло.
  high,

  /// 20–100m — қониқарли.
  medium,

  /// >100m — қониқарсиз, қайта олиш керак.
  low,
}
