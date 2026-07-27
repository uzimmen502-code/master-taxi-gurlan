import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/fair_mix.dart';
import '../features/ads/models/ad_model.dart';
import '../models/bread_product.dart';
import '../models/feed_item.dart';
import '../models/food_product.dart';

/// «Barcha mahsulotlar» cheksiz lenta — Firestore dan non, taom va bozor.
///
/// Audit (featured_products_service bilan mos):
/// - `bread_products`: `createdAt` (BreadRepository) — paginatsiya uchun
///   `createdAt` desc; xato bo‘lsa `FieldPath.documentId`.
/// - `food_catalog`: narx `price` maydonida (food_inventory emas);
///   `orderBy('id')` (FoodController / featured).
/// - `ads`: `type == cheap_product`, `status == active`, `price > 0`;
///   `orderBy('publishedAt', descending: true)` (AdsRepository); xato bo‘lsa
///   `createdAt` desc (featured fallback).
class ProductFeedService {
  ProductFeedService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentSnapshot<Map<String, dynamic>>? _breadCursor;
  DocumentSnapshot<Map<String, dynamic>>? _foodCursor;
  DocumentSnapshot<Map<String, dynamic>>? _marketCursor;

  bool _breadDone = false;
  bool _foodDone = false;
  bool _marketDone = false;

  bool _breadOrderByDocId = false;
  bool _marketOrderByCreatedAt = false;

  bool get isExhausted => _breadDone && _foodDone && _marketDone;

  Future<List<FeedItem>> loadNextBatch() async {
    final bread = <FeedItem>[];
    final food = <FeedItem>[];
    final market = <FeedItem>[];
    final rand = Random();

    if (!_breadDone) {
      final n = 2 + rand.nextInt(29);
      bread.addAll(await _fetchBreadBatch(n));
    }
    if (!_foodDone) {
      final n = 2 + rand.nextInt(29);
      food.addAll(await _fetchFoodBatch(n));
    }
    if (!_marketDone) {
      final n = 2 + rand.nextInt(29);
      market.addAll(await _fetchMarketBatch(n));
    }

    // Адолатли аралаш (shuffle ўрнига RR).
    return FairMix.roundRobin([bread, food, market]);
  }

  Future<List<FeedItem>> loadNextSourceBatch(
    FeedSource source, {
    int count = 12,
  }) async {
    switch (source) {
      case FeedSource.bread:
        return _fetchBreadBatch(count);
      case FeedSource.food:
        return _fetchFoodBatch(count);
      case FeedSource.market:
        return _fetchMarketBatch(count);
    }
  }

  void reset() {
    _breadCursor = null;
    _foodCursor = null;
    _marketCursor = null;
    _breadDone = false;
    _foodDone = false;
    _marketDone = false;
    _breadOrderByDocId = false;
    _marketOrderByCreatedAt = false;
  }

  Future<List<FeedItem>> _fetchBreadBatch(int n) async {
    if (_breadDone || n <= 0) return const [];

    try {
      Query<Map<String, dynamic>> q = _db.collection('bread_products');
      if (_breadOrderByDocId) {
        q = q.orderBy(FieldPath.documentId, descending: true);
      } else {
        q = q.orderBy('createdAt', descending: true);
      }
      if (_breadCursor != null) {
        q = q.startAfterDocument(_breadCursor!);
      }

      final snap = await q.limit(n).get();
      if (snap.docs.isEmpty) {
        _breadDone = true;
        return const [];
      }

      _breadCursor = snap.docs.last;
      if (snap.docs.length < n) {
        _breadDone = true;
      }

      return snap.docs
          .map(BreadProduct.fromFirestore)
          .where(_breadInStock)
          .where((p) => (p.price ?? 0) > 0)
          .map(_breadToFeedItem)
          .toList(growable: false);
    } catch (_) {
      if (!_breadOrderByDocId) {
        _breadOrderByDocId = true;
        _breadCursor = null;
        return _fetchBreadBatch(n);
      }
      _breadDone = true;
      return const [];
    }
  }

  Future<List<FeedItem>> _fetchFoodBatch(int n) async {
    if (_foodDone || n <= 0) return const [];

    try {
      Query<Map<String, dynamic>> q =
          _db.collection('food_catalog').orderBy('id');
      if (_foodCursor != null) {
        q = q.startAfterDocument(_foodCursor!);
      }

      final snap = await q.limit(n).get();
      if (snap.docs.isEmpty) {
        _foodDone = true;
        return const [];
      }

      _foodCursor = snap.docs.last;
      if (snap.docs.length < n) {
        _foodDone = true;
      }

      return snap.docs
          .map((d) => FoodProduct.fromFirestore(d.data(), d.id))
          .where((p) => p.price > 0)
          .map(_foodToFeedItem)
          .toList(growable: false);
    } catch (_) {
      _foodDone = true;
      return const [];
    }
  }

  Future<List<FeedItem>> _fetchMarketBatch(int n) async {
    if (_marketDone || n <= 0) return const [];

    try {
      final orderField =
          _marketOrderByCreatedAt ? 'createdAt' : 'publishedAt';
      Query<Map<String, dynamic>> q = _db
          .collection('ads')
          .where('type', isEqualTo: AdModel.typeKey)
          .where('status', isEqualTo: 'active')
          .orderBy(orderField, descending: true);
      if (_marketCursor != null) {
        q = q.startAfterDocument(_marketCursor!);
      }

      final snap = await q.limit(n).get();
      if (snap.docs.isEmpty) {
        _marketDone = true;
        return const [];
      }

      _marketCursor = snap.docs.last;
      if (snap.docs.length < n) {
        _marketDone = true;
      }

      return snap.docs
          .map(AdModel.fromFirestore)
          .where((ad) => ad.price > 0)
          .map(_marketToFeedItem)
          .toList(growable: false);
    } catch (_) {
      if (!_marketOrderByCreatedAt) {
        _marketOrderByCreatedAt = true;
        _marketCursor = null;
        return _fetchMarketBatch(n);
      }
      _marketDone = true;
      return const [];
    }
  }

  bool _breadInStock(BreadProduct p) {
    if (p.totalStock <= 0) return true;
    return p.totalStock - p.soldToday > 0;
  }

  FeedItem _breadToFeedItem(BreadProduct p) {
    final imageUrl =
        p.imageUrl.trim().isNotEmpty ? p.imageUrl.trim() : p.image.trim();
    return FeedItem(
      id: p.firestoreId ?? '${p.id}',
      name: p.name,
      price: p.price ?? 0,
      imageUrl: imageUrl,
      unit: p.unit,
      source: FeedSource.bread,
    );
  }

  FeedItem _foodToFeedItem(FoodProduct p) {
    return FeedItem(
      id: '${p.id}',
      name: p.name,
      price: p.price,
      imageUrl: p.imageUrl,
      unit: p.unit,
      source: FeedSource.food,
    );
  }

  FeedItem _marketToFeedItem(AdModel ad) {
    final imageUrl =
        ad.imageUrls.isNotEmpty ? ad.imageUrls.first.trim() : '';
    return FeedItem(
      id: ad.id,
      name: ad.title,
      price: ad.price,
      imageUrl: imageUrl,
      unit: '',
      source: FeedSource.market,
    );
  }
}
