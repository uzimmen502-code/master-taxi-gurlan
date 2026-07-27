import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/fair_mix.dart';
import '../models/bread_product.dart';
import '../models/food_product.dart';
import '../repositories/platform_products_repository.dart';
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

  /// `bread` | `food` | `platform`
  final String source;
}

/// Non, taom va platforma do‘konidan tavsiya mahsulotlarini yig‘adi.
class FeaturedProductsService {
  FeaturedProductsService({
    FirebaseFirestore? db,
    PlatformProductsRepository? platformRepo,
  })  : _db = db ?? FirebaseFirestore.instance,
        _platformRepo = platformRepo ?? PlatformProductsRepository(db: db);

  final FirebaseFirestore _db;
  final PlatformProductsRepository _platformRepo;

  Future<List<FeaturedProduct>> getFeaturedProducts() async {
    final bread = await _fetchBread();
    final food = await _fetchFood();
    final platform = await _fetchPlatform();
    // Адолатли: non / taom / platforma навбатма-навбат.
    return FairMix.roundRobin([bread, food, platform]);
  }

  List<FeaturedProduct> _positivePrice(Iterable<FeaturedProduct> items,
      {int take = 2}) {
    return items.where((e) => e.price > 0).take(take).toList(growable: false);
  }

  Future<List<FeaturedProduct>> _fetchBread() async {
    try {
      final snap = await _db
          .collection('bread_products')
          .orderBy('soldToday', descending: true)
          .limit(12)
          .get();

      final items = snap.docs
          .map(BreadProduct.fromFirestore)
          .where(_breadInStock)
          .map(
            (p) => FeaturedProduct(
              id: p.firestoreId ?? '${p.id}',
              name: p.name,
              price: p.price ?? 0,
              imageUrl: p.imageUrl.trim().isNotEmpty ? p.imageUrl : p.image,
              source: 'bread',
            ),
          );

      return _positivePrice(items);
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
          .limit(12)
          .get();

      List<FoodProduct> products;
      if (snap.docs.isEmpty) {
        products = FoodCatalog.products;
      } else {
        products = snap.docs
            .map((d) => FoodProduct.fromFirestore(d.data(), d.id))
            .toList(growable: false);
      }

      final items = products.map(
        (p) => FeaturedProduct(
          id: '${p.id}',
          name: p.name,
          price: p.price,
          imageUrl: p.imageUrl,
          source: 'food',
        ),
      );

      return _positivePrice(items);
    } catch (_) {
      try {
        final items = FoodCatalog.products.map(
          (p) => FeaturedProduct(
            id: '${p.id}',
            name: p.name,
            price: p.price,
            imageUrl: p.imageUrl,
            source: 'food',
          ),
        );
        return _positivePrice(items);
      } catch (_) {
        return const [];
      }
    }
  }

  Future<List<FeaturedProduct>> _fetchPlatform() async {
    try {
      final products = await _platformRepo.fetchForHomeFeatured(take: 2);
      return products
          .map(
            (p) => FeaturedProduct(
              id: p.id,
              name: p.name,
              price: p.price,
              imageUrl: p.coverImageUrl,
              source: 'platform',
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
