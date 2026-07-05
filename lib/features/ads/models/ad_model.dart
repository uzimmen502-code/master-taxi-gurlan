import 'package:cloud_firestore/cloud_firestore.dart';

/// Cheap product listing in Firestore `ads` (type == `cheap_product`).
class AdModel {
  const AdModel({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.titleLower,
    required this.description,
    required this.price,
    required this.phone,
    required this.sellerName,
    required this.imageUrls,
    required this.status,
    required this.views,
    this.createdAt,
    this.updatedAt,
    this.publishedAt,
    this.adminNote = '',
    this.moderatedAt,
    this.moderatedBy = '',
  });

  static const String typeKey = 'cheap_product';

  final String id;
  final String ownerId;
  final String title;
  final String titleLower;
  final String description;
  final int price;
  final String phone;
  final String sellerName;
  final List<String> imageUrls;

  /// `active` | `inactive`
  final String status;
  final int views;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? publishedAt;
  final String adminNote;
  final DateTime? moderatedAt;
  final String moderatedBy;

  bool get isActive => status == 'active';

  factory AdModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return AdModel.fromMap(doc.id, doc.data() ?? const <String, dynamic>{});
  }

  /// Admin CF `adminListMarketAds` javobi.
  factory AdModel.fromMap(String id, Map<String, dynamic> d) {
    final title = (d['title'] ?? '') as String;
    final rawLower = d['titleLower'] as String?;
    return AdModel(
      id: id,
      ownerId: (d['ownerId'] ?? '') as String,
      title: title,
      titleLower: rawLower?.isNotEmpty == true ? rawLower! : title.toLowerCase(),
      description: (d['description'] ?? '') as String,
      price: (d['price'] as num?)?.toInt() ?? 0,
      phone: (d['phone'] ?? '') as String,
      sellerName: (d['sellerName'] ?? '') as String,
      imageUrls: List<String>.from(d['imageUrls'] ?? const <String>[]),
      status: (d['status'] ?? 'active') as String,
      views: (d['views'] as num?)?.toInt() ?? 0,
      createdAt: _parseDate(d['createdAt']),
      updatedAt: _parseDate(d['updatedAt']),
      publishedAt: _parseDate(d['publishedAt']),
      adminNote: (d['adminNote'] ?? '') as String,
      moderatedAt: _parseDate(d['moderatedAt']),
      moderatedBy: (d['moderatedBy'] ?? '') as String,
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  Map<String, dynamic> toMap({bool forCreate = false}) {
    final map = <String, dynamic>{
      'type': typeKey,
      'ownerId': ownerId,
      'title': title,
      'titleLower': titleLower,
      'description': description,
      'price': price,
      'phone': phone,
      'sellerName': sellerName,
      'imageUrls': imageUrls,
      'status': status,
      'views': views,
    };
    if (forCreate) {
      map['createdAt'] = FieldValue.serverTimestamp();
      map['updatedAt'] = FieldValue.serverTimestamp();
      map['publishedAt'] = FieldValue.serverTimestamp();
    }
    return map;
  }
}
