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
  });

  static const statusPending = 'pending';
  static const statusApproved = 'approved';
  static const statusRejected = 'rejected';

  /// Сотувчи тури — талабдаги учта категория.
  static const typeManufacturer = 'manufacturer';
  static const typeWholesaler = 'wholesaler';
  static const typeYatt = 'yatt';
  static const sellerTypes = [typeManufacturer, typeWholesaler, typeYatt];

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
    );
  }

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
      };
}
