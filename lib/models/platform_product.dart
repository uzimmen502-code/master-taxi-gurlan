import 'package:cloud_firestore/cloud_firestore.dart';

/// Платформа дўкони товари (`platform_products`).
///
/// `totalStock <= 0` → лимитсиз. Қолдиқ = totalStock − soldToday.
class PlatformProduct {
  const PlatformProduct({
    required this.id,
    required this.name,
    required this.price,
    this.description = '',
    this.imageUrl = '',
    this.unit = 'дона',
    this.minQty = 1,
    this.step = 1,
    this.totalStock = 0,
    this.soldToday = 0,
    this.active = true,
    this.featuredOnHome = false,
    this.showInMarket = true,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String description;
  final int price;
  final String imageUrl;
  final String unit;
  final int minQty;
  final int step;
  final int totalStock;
  final int soldToday;
  final bool active;
  final bool featuredOnHome;
  final bool showInMarket;
  final int sortOrder;

  bool get isUnlimitedStock => totalStock <= 0;

  int get remaining {
    if (isUnlimitedStock) return 999999;
    final left = totalStock - soldToday;
    return left < 0 ? 0 : left;
  }

  bool get inStock => isUnlimitedStock || remaining > 0;

  factory PlatformProduct.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    return PlatformProduct(
      id: doc.id,
      name: (d['name'] as String?)?.trim() ?? '',
      description: (d['description'] as String?)?.trim() ?? '',
      price: (d['price'] as num?)?.toInt() ?? 0,
      imageUrl: (d['imageUrl'] as String?)?.trim() ?? '',
      unit: (d['unit'] as String?)?.trim().isNotEmpty == true
          ? (d['unit'] as String).trim()
          : 'дона',
      minQty: (d['minQty'] as num?)?.toInt() ?? 1,
      step: (d['step'] as num?)?.toInt() ?? 1,
      totalStock: (d['totalStock'] as num?)?.toInt() ?? 0,
      soldToday: (d['soldToday'] as num?)?.toInt() ?? 0,
      active: d['active'] as bool? ?? true,
      featuredOnHome: d['featuredOnHome'] as bool? ?? false,
      showInMarket: d['showInMarket'] as bool? ?? true,
      sortOrder: (d['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toFirestoreCreate() => {
        'name': name,
        'description': description,
        'price': price,
        'imageUrl': imageUrl,
        'unit': unit,
        'minQty': minQty,
        'step': step,
        'totalStock': totalStock,
        'soldToday': soldToday,
        'active': active,
        'featuredOnHome': featuredOnHome,
        'showInMarket': showInMarket,
        'sortOrder': sortOrder,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toFirestoreUpdate() => {
        'name': name,
        'description': description,
        'price': price,
        'imageUrl': imageUrl,
        'unit': unit,
        'minQty': minQty,
        'step': step,
        'totalStock': totalStock,
        'active': active,
        'featuredOnHome': featuredOnHome,
        'showInMarket': showInMarket,
        'sortOrder': sortOrder,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
