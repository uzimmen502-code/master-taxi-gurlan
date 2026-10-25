import 'package:cloud_firestore/cloud_firestore.dart';

import 'business_category.dart';

/// `businesses/{id}` — тадбиркорлик объекти (эга ўзи қўшади; ёзув фақат Cloud Functions орқали).
///
/// Серверга ЮБОРИЛАДИГАН майдонлар [toCallable]да; `ownerId`, `status`, `geohash*` сервер томонидан
/// қўйилади ва клиентдан қабул қилинмайди (18-банд).
class Business {
  const Business({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.category,
    required this.phone,
    required this.lat,
    required this.lng,
    this.subtype = '',
    this.description = '',
    this.address = '',
    this.regionId = '',
    this.districtId = '',
    this.openingHours = '',
    this.website = '',
    this.createdAt,
    this.updatedAt,
    this.status = 'active',
    this.online = false,
    this.branchOf = '',
  });

  /// Фақат онлайн йўналиш (жисмоний жойи йўқ): координатасиз, харитада чизилмайди ([lat]/[lng] = 0).
  final bool online;

  /// Филиал: шу эганинг қайси йўналишининг яна бир жисмоний нуқтаси (`businesses/{id}`); бўш — алоҳида йўналиш.
  /// Филиалнинг ўз каталоги йўқ — харидор отанинг дўконига тушади (сервер ота/эгани текширади).
  final String branchOf;

  bool get isBranch => branchOf.isNotEmpty;

  /// `active` | `blocked` — фақат сервер (админ) ўрнатади; клиент [toCallable]да юбормайди.
  final String status;

  bool get isBlocked => status == 'blocked';

  final String id;
  final String ownerId;
  final String name;
  final BusinessCategory category;
  final String subtype;
  final String description;
  final String phone;
  final String address;
  final double lat;
  final double lng;
  final String regionId;
  final String districtId;
  final String openingHours;
  final String website;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// «Менинг дўконим»нинг ЎЗ дўкони (харитада жойи йўқ): эганинг usinessIdсиз маҳсулотлари.
  /// Харита объекти эмас — фақат шу каталог экранлари битта кодда ишлаши учун (id бўш).
  factory Business.ownShop({required String ownerId, required String name, String districtId = ''}) => Business(
        id: '',
        ownerId: ownerId,
        name: name,
        category: BusinessCategory.retail,
        phone: ownerId,
        lat: 0,
        lng: 0,
        districtId: districtId,
      );

  /// 	rue — харита объекти эмас, эганинг ўз дўкони ([Business.ownShop]).
  bool get isOwnShop => id.isEmpty;

  static String _s(Object? v) => v is String ? v.trim() : '';

  static DateTime? _t(Object? v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);

  /// Координатаси яроқсиз ҳужжат — `null` (харитада чизилмайди, синмайди).
  /// Блокланган объектнинг координатаси сервер томонидан `blockedGeo`га олинган (эски иловалар уни чизмасин) —
  /// эга ва админ рўйхатларида у шу ердан ўқилади; харита [isBlocked]ни ўзи чиқариб ташлайди.
  static Business? tryFromMap(String id, Map<String, dynamic> d) {
    final online = d['online'] == true;
    final hold = d['blockedGeo'];
    final geo = d['lat'] is num ? d : (hold is Map ? hold : d);
    final lat = online ? 0 : geo['lat'];
    final lng = online ? 0 : geo['lng'];
    if (lat is! num || lng is! num) return null;
    return Business(
      id: id,
      ownerId: _s(d['ownerId']),
      name: _s(d['name']),
      category: BusinessCategory.fromWire(d['category']),
      subtype: _s(d['subtype']),
      description: _s(d['description']),
      phone: _s(d['phone']),
      address: _s(d['address']),
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      regionId: _s(d['regionId']),
      districtId: _s(d['districtId']),
      openingHours: _s(d['openingHours']),
      website: _s(d['website']),
      createdAt: _t(d['createdAt']),
      updatedAt: _t(d['updatedAt']),
      status: d['status'] == 'blocked' ? 'blocked' : 'active',
      online: online,
      branchOf: _s(d['branchOf']),
    );
  }

  /// `upsertMyBusiness` / `adminUpdateBusiness` майдонлари (id, clientRequestId, reason — чақирувчида).
  Map<String, Object?> toCallable() => {
        'name': name,
        'category': category.wire,
        'subtype': subtype,
        'description': description,
        'phone': phone,
        'address': address,
        if (online) 'online': true else ...{'lat': lat, 'lng': lng},
        if (branchOf.isNotEmpty) 'branchOf': branchOf,
        'regionId': regionId,
        'districtId': districtId,
        'openingHours': openingHours,
        'website': website,
      };
}
