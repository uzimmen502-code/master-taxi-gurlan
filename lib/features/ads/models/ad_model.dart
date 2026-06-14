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

  bool get isActive => status == 'active';

  factory AdModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final title = (d['title'] ?? '') as String;
    final rawLower = d['titleLower'] as String?;
    return AdModel(
      id: doc.id,
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
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      publishedAt: (d['publishedAt'] as Timestamp?)?.toDate(),
    );
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
