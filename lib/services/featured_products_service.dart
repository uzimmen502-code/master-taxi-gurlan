import 'package:cloud_firestore/cloud_firestore.dart';

import '../features/ads/models/ad_model.dart';
import '../models/bread_product.dart';
import '../models/food_product.dart';
import '../utils/food_catalog.dart';

/// Bosh ekran «Tavsiya etamiz» bo‘limi uchun mahsulot.
class FeaturedProduct {
  const FeaturedProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.source,
  });

  final String id;
  final String name;
  final int price;

  /// HTTP, data URL yoki bo‘sh.
  final String imageUrl;

  /// `bread` | `food` | `market`
  final String source;
}

/// Non, taom va bozor dan tavsiya mahsulotlarini yig‘adi.
class FeaturedProductsService {
  FeaturedProductsService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<List<FeaturedProduct>> getFeaturedProducts() async {
    final bread = await _fetchBread();
    final food = await _fetchFood();
    final market = await _fetchMarket();
    return [...bread, ...food, ...market];
  }

  Future<List<FeaturedProduct>> _fetchBread() async {
    try {
      final snap = await _db
          .collection('bread_products')
          .orderBy('soldToday', descending: true)
          .limit(12)
          .get();

      return snap.docs
          .map(BreadProduct.fromFirestore)
          .where(_breadInStock)
          .take(2)
          .map(
            (p) => FeaturedProduct(
              id: p.firestoreId ?? '${p.id}',
              name: p.name,
              price: p.price ?? 0,
              imageUrl: p.imageUrl.trim().isNotEmpty ? p.imageUrl : p.image,
              source: 'bread',
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  bool _breadInStock(BreadProduct p) {
    if (p.totalStock <= 0) return true;
    return p.totalStock - p.soldToday > 0;
  }

  Future<List<FeaturedProduct>> _fetchFood() async {
    try {
      final snap = await _db
          .collection('food_catalog')
          .orderBy('id')
          .limit(2)
          .get();

      List<FoodProduct> products;
      if (snap.docs.isEmpty) {
        products = FoodCatalog.products.take(2).toList(growable: false);
      } else {
        products = snap.docs
            .map((d) => FoodProduct.fromFirestore(d.data(), d.id))
            .take(2)
            .toList(growable: false);
      }

      return products
          .map(
            (p) => FeaturedProduct(
              id: '${p.id}',
              name: p.name,
              price: p.price,
              imageUrl: p.imageUrl,
              source: 'food',
            ),
          )
          .toList(growable: false);
    } catch (_) {
      try {
        return FoodCatalog.products
            .take(2)
            .map(
              (p) => FeaturedProduct(
                id: '${p.id}',
                name: p.name,
                price: p.price,
                imageUrl: p.imageUrl,
                source: 'food',
              ),
            )
            .toList(growable: false);
      } catch (_) {
        return const [];
      }
    }
  }

  Future<List<FeaturedProduct>> _fetchMarket() async {
    try {
      return await _marketQuery(orderField: 'createdAt');
    } catch (_) {
      try {
        return await _marketQuery(orderField: 'publishedAt');
      } catch (_) {
        return const [];
      }
    }
  }

  Future<List<FeaturedProduct>> _marketQuery({required String orderField}) async {
    final snap = await _db
        .collection('ads')
        .where('type', isEqualTo: AdModel.typeKey)
        .where('status', isEqualTo: 'active')
        .orderBy(orderField, descending: true)
        .limit(2)
        .get();

    return snap.docs.map((doc) {
      final ad = AdModel.fromFirestore(doc);
      final imageUrl =
          ad.imageUrls.isNotEmpty ? ad.imageUrls.first.trim() : '';
      return FeaturedProduct(
        id: ad.id,
        name: ad.title,
        price: ad.price,
        imageUrl: imageUrl,
        source: 'market',
      );
    }).toList(growable: false);
  }
}
