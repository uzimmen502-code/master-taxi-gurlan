import 'package:cloud_firestore/cloud_firestore.dart';

/// Geografik ierarxiya: Region → District → ServiceArea (MFY).
///
/// Xizmat mavjudligi FAQAT [ServiceArea] (serviceAreaId) orqali aniqlanadi;
/// [GeoRegion]/[GeoDistrict] — hisobot, dashboard va reklama uchun.
/// Firestore: `geo_regions`, `geo_districts`, `service_areas`.

/// `geo_regions/{regionId}` — viloyat.
class GeoRegion {
  const GeoRegion({
    required this.id,
    required this.name,
    this.nameUz = '',
    this.code = '',
    this.active = true,
    this.order = 0,
  });

  final String id;
  final String name;
  final String nameUz;
  final String code;
  final bool active;
  final int order;

  static const String collection = 'geo_regions';

  String get displayName => nameUz.isNotEmpty ? nameUz : name;

  factory GeoRegion.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return GeoRegion(
      id: doc.id,
      name: (d['name'] ?? '') as String,
      nameUz: (d['nameUz'] ?? '') as String,
      code: (d['code'] ?? '') as String,
      active: d['active'] as bool? ?? true,
      order: (d['order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'nameUz': nameUz,
        'code': code,
        'active': active,
        'order': order,
      };
}

/// `geo_districts/{districtId}` — tuman. [regionId] ota-viloyat.
class GeoDistrict {
  const GeoDistrict({
    required this.id,
    required this.regionId,
    required this.name,
    this.nameUz = '',
    this.code = '',
    this.active = true,
    this.order = 0,
  });

  final String id;
  final String regionId;
  final String name;
  final String nameUz;
  final String code;
  final bool active;
  final int order;

  static const String collection = 'geo_districts';

  String get displayName => nameUz.isNotEmpty ? nameUz : name;

  factory GeoDistrict.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return GeoDistrict(
      id: doc.id,
      regionId: (d['regionId'] ?? '') as String,
      name: (d['name'] ?? '') as String,
      nameUz: (d['nameUz'] ?? '') as String,
      code: (d['code'] ?? '') as String,
      active: d['active'] as bool? ?? true,
      order: (d['order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'regionId': regionId,
        'name': name,
        'nameUz': nameUz,
        'code': code,
        'active': active,
        'order': order,
      };
}

/// `service_areas/{serviceAreaId}` — MFY yoki xizmat zonasi.
/// [districtId] ota-tuman, [regionId] denormalizatsiya (tez filter uchun).
class ServiceArea {
  const ServiceArea({
    required this.id,
    required this.districtId,
    required this.regionId,
    required this.name,
    this.nameUz = '',
    this.type = 'mfy',
    this.active = true,
    this.order = 0,
  });

  final String id;
  final String districtId;
  final String regionId;
  final String name;
  final String nameUz;

  /// `mfy` | `zone` | kelajakdagi turlar.
  final String type;
  final bool active;
  final int order;

  static const String collection = 'service_areas';

  String get displayName => nameUz.isNotEmpty ? nameUz : name;

  factory ServiceArea.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return ServiceArea(
      id: doc.id,
      districtId: (d['districtId'] ?? '') as String,
      regionId: (d['regionId'] ?? '') as String,
      name: (d['name'] ?? '') as String,
      nameUz: (d['nameUz'] ?? '') as String,
      type: (d['type'] ?? 'mfy') as String,
      active: d['active'] as bool? ?? true,
      order: (d['order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'districtId': districtId,
        'regionId': regionId,
        'name': name,
        'nameUz': nameUz,
        'type': type,
        'active': active,
        'order': order,
      };
}
