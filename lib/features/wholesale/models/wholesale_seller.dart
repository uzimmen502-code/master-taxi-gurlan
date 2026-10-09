import 'package:cloud_firestore/cloud_firestore.dart';

/// Улгуржи сотувчи (ишлаб чиқарувчи/оптовик/ЯТТ) — `wholesale_sellers/{phone}`.
///
/// Ҳужжат ID — каноник телефон (`canonicalPhoneId`, 998XXXXXXXXX). Рўйхатдан
/// ўтиш MVP: фақат телефон + компания номи; admin тасдиғигача `pending`.
class WholesaleSeller {
  const WholesaleSeller({
    required this.phone,
    required this.companyName,
    this.ownerName = '',
    this.sellerType = '',
    this.approvalStatus = statusPending,
    this.createdAt,
    this.approvedAt,
    this.approvedBy = '',
    this.adminNote = '',
    this.regionId = '',
    this.districtId = '',
    this.address = '',
    this.lat,
    this.lng,
  });

  static const statusPending = 'pending';
  static const statusApproved = 'approved';
  static const statusRejected = 'rejected';

  /// Сотувчи тури — талабдаги учта категория.
  static const typeManufacturer = 'manufacturer';
  static const typeWholesaler = 'wholesaler';
  static const typeYatt = 'yatt';
  static const sellerTypes = [typeManufacturer, typeWholesaler, typeYatt];

  /// Сотувчи тури — матн калити (2026-09-29). Иловадаги экранлар шуни
  /// `context.tr` билан ишлатади: бўлим уч тилда чиқиши керак.
  /// [typeLabel] эса ўзгаришсиз қолди — уни админ веб-панели ишлатади,
  /// у ерда таржима қатлами йўқ.
  static String typeLabelKey(String type) {
    switch (type) {
      case typeManufacturer:
        return 'wholesale_seller_type_manufacturer';
      case typeWholesaler:
        return 'wholesale_seller_type_wholesaler';
      case typeYatt:
        return 'wholesale_seller_type_ip';
      default:
        return '';
    }
  }

  static String typeLabel(String type) {
    switch (type) {
      case typeManufacturer:
        return 'Ишлаб чиқарувчи';
      case typeWholesaler:
        return 'Оптовик';
      case typeYatt:
        return 'ЯТТ';
      default:
        return '';
    }
  }

  final String phone;
  final String companyName;
  final String ownerName;

  /// `manufacturer` | `wholesaler` | `yatt` | '' (кўрсатилмаган).
  final String sellerType;

  /// `pending` | `approved` | `rejected`.
  final String approvalStatus;
  final DateTime? createdAt;
  final DateTime? approvedAt;
  final String approvedBy;
  final String adminNote;

  /// Жўнатиш манзили (У1, 2026-10-09) — етказиш ҳақи учун зона
  /// `districtId` бўйича аниқланади (relay матрицаси). `geo_regions` /
  /// `geo_districts` ID'лари. Эски сотувчиларда бўш.
  final String regionId;
  final String districtId;
  final String address;
  final double? lat;
  final double? lng;

  /// Етказиш ҳақини ҳисоблаш учун манзил етарлими (вилоят + туман).
  bool get hasShipFrom => regionId.isNotEmpty && districtId.isNotEmpty;

  bool get isPending => approvalStatus == statusPending;
  bool get isApproved => approvalStatus == statusApproved;
  bool get isRejected => approvalStatus == statusRejected;

  static DateTime? _parseDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  factory WholesaleSeller.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    return WholesaleSeller(
      phone: (d['phone'] as String?) ?? doc.id,
      companyName: (d['companyName'] as String?)?.trim() ?? '',
      ownerName: (d['ownerName'] as String?)?.trim() ?? '',
      sellerType: (d['sellerType'] as String?)?.trim() ?? '',
      approvalStatus:
          (d['approvalStatus'] as String?)?.trim() ?? statusPending,
      createdAt: _parseDate(d['createdAt']),
      approvedAt: _parseDate(d['approvedAt']),
      approvedBy: (d['approvedBy'] as String?) ?? '',
      adminNote: (d['adminNote'] as String?) ?? '',
      regionId: (d['regionId'] as String?)?.trim() ?? '',
      districtId: (d['districtId'] as String?)?.trim() ?? '',
      address: (d['address'] as String?)?.trim() ?? '',
      lat: (d['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble(),
    );
  }

  /// Жўнатиш манзили майдонлари — Rules `wholesaleSellerShipFromOk` шакли:
  /// координата иккаласи бирга ёки умуман йўқ.
  Map<String, dynamic> shipFromFields() => {
        'regionId': regionId.trim(),
        'districtId': districtId.trim(),
        'address': address.trim(),
        if (lat != null && lng != null) 'lat': lat,
        if (lat != null && lng != null) 'lng': lng,
      };

  /// Рўйхатдан ўтиш учун — Firestore Rules текширади: `approvalStatus`
  /// фақат `pending`, ёки [autoApproved] (`settings/app.wholesaleSellerAutoApprove`
  /// ёқиқ бўлса) `approved` бўлиши мумкин.
  Map<String, dynamic> toFirestoreCreate({bool autoApproved = false}) => {
        'phone': phone,
        'companyName': companyName,
        'ownerName': ownerName,
        'sellerType': sellerType,
        'approvalStatus': autoApproved ? statusApproved : statusPending,
        'createdAt': FieldValue.serverTimestamp(),
        if (autoApproved) 'approvedAt': FieldValue.serverTimestamp(),
        if (autoApproved) 'approvedBy': 'auto',
        if (hasShipFrom || address.trim().isNotEmpty) ...shipFromFields(),
      };

  /// Эга жўнатиш манзилини ўзгартириши (`wholesaleSellerOwnerUpdateOk`).
  /// Координата олиб ташланса — ўчирилади (иккаласи бирга).
  Map<String, dynamic> toFirestoreShipFromUpdate() => {
        ...shipFromFields(),
        if (lat == null || lng == null) 'lat': FieldValue.delete(),
        if (lat == null || lng == null) 'lng': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
