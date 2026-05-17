import 'package:cloud_firestore/cloud_firestore.dart';

/// Нон каталоги — `bread_products` Firestore (ёпиш / тайёр / той — бари dynamic).
///
/// `type`: `'ёпиш'` | `'тайёр'` | `'той'`.
class BreadProduct {
  const BreadProduct({
    required this.id,
    required this.name,
    required this.type,
    this.firestoreId,
    this.emoji = '🫓',
    this.image = '',
    this.imageUrl = '',
    this.desc = '',
    this.category = '',
    this.unit = 'дона',
    this.priceKey,
    this.price,
    this.flourG,
    this.milkMl,
    this.milkRatio,
    this.totalStock = 0,
    this.soldToday = 0,
  });

  final int id;
  final String? firestoreId;
  final String name;
  final String type;
  final String emoji;
  final String image;
  final String imageUrl;
  final String desc;
  final String category;
  /// Кўрсатиш учун (масалан «дона», «та»).
  final String unit;
  final String? priceKey;
  final int? price;
  final int? flourG;
  final int? milkMl;
  final double? milkRatio;

  final int totalStock;
  final int soldToday;

  bool get isYopish => type == 'ёпиш';
  bool get isToy => type == 'той';
  bool get isReady => type == 'тайёр';

  int get remaining {
    if (totalStock <= 0) return 999999;
    final r = totalStock - soldToday;
    return r < 0 ? 0 : r;
  }

  bool get isSoldOut => totalStock > 0 && remaining <= 0;

  static String _stringField(dynamic v) {
    if (v == null) return '';
    if (v is String) return v.trim();
    return '$v'.trim();
  }

  factory BreadProduct.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final descRaw = data['description'] ?? data['desc'] ?? '';
    final imageUrlRaw = data['imageUrl'] ??
        data['imageURL'] ??
        data['image_url'] ??
        data['photoUrl'] ??
        '';
    return BreadProduct(
      id: doc.id.hashCode,
      firestoreId: doc.id,
      name: (data['name'] ?? '') as String,
      type: _mapType((data['type'] ?? 'tayyor') as String),
      price: (data['price'] as num?)?.toInt() ?? 0,
      emoji: (data['emoji'] ?? '🫓') as String,
      imageUrl: _stringField(imageUrlRaw),
      image: _stringField(data['image']),
      desc: descRaw is String ? descRaw : '$descRaw',
      category: (data['category'] ?? '') as String,
      unit: (data['unit'] ?? 'дона') as String,
      priceKey: data['priceKey'] as String?,
      flourG: (data['flourG'] as num?)?.toInt(),
      milkMl: (data['milkMl'] as num?)?.toInt(),
      milkRatio: (data['milkRatio'] as num?)?.toDouble(),
      totalStock: (data['totalStock'] as num?)?.toInt() ?? 0,
      soldToday: (data['soldToday'] as num?)?.toInt() ?? 0,
    );
  }

  static String _mapType(String t) {
    switch (t) {
      case 'yopish':
        return 'ёпиш';
      case 'toy':
        return 'той';
      default:
        return 'тайёр';
    }
  }
}
