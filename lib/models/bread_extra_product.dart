import 'package:cloud_firestore/cloud_firestore.dart';

/// `extra_products` Firestore collection — нон билан бирга сотиладиган
/// қўшимча маҳсулотлар.
///
/// Ихтиёрий: `emoji`, `caption`, `tieToYopishBread`.
class BreadExtraProduct {
  const BreadExtraProduct({
    required this.id,
    required this.firestoreId,
    required this.name,
    required this.price,
    required this.unit,
    this.qty,
    this.totalStock = 0,
    this.soldToday = 0,
    this.bonusEnabled = false,
    this.bonusThreshold = 0,
    this.bonusQty = 0,
    this.bonusPercent = 0,
    this.emoji = '',
    this.caption = '',
    this.imageUrl = '',
    this.tieToYopishBread = false,
  });

  final int id;
  final String firestoreId;
  final String name;
  final int price;
  final String unit;
  final dynamic qty;
  final int totalStock;
  final int soldToday;
  final bool bonusEnabled;
  final int bonusThreshold;
  final int bonusQty;
  final int bonusPercent;

  final String emoji;
  final String caption;
  final String imageUrl;
  final bool tieToYopishBread;

  String get displayEmoji {
    final t = emoji.trim();
    if (t.isNotEmpty) return t;
    return '🌿';
  }

  /// Дона: 1, кг/л: 0.5 қадам.
  double get qtyStep => unitCode == 'dona' ? 1.0 : 0.5;

  num get remainingNum {
    if (totalStock <= 0) return 999999;
    final r = totalStock - soldToday;
    return r < 0 ? 0 : r;
  }

  int get remaining {
    if (totalStock <= 0) return 999;
    final r = totalStock - soldToday;
    return r < 0 ? 0 : r;
  }

  bool get isSoldOut => totalStock > 0 && remaining <= 0;

  /// Максимал миқдор (бирликда) — `totalStock`/`soldToday` чегараси.
  double get maxQtyValue {
    if (totalStock <= 0) return 99;
    return (totalStock - soldToday).clamp(0, 999).toDouble();
  }

  /// [yopishBreadCount] — ёпиш нонлари сони (tie учун).
  double effectiveMaxQtyValue(int yopishBreadCount) {
    final cap = maxQtyValue;
    if (!tieToYopishBread) return cap;
    final y = yopishBreadCount.clamp(0, 999).toDouble();
    return cap < y ? cap : y;
  }

  String get unitCode {
    final raw = unit.toLowerCase();
    if (raw == 'kg' || raw == 'кг') return 'kg';
    if (raw == 'l' || raw == 'л' || raw == 'liter' || raw == 'litre') return 'l';
    final n = name.toLowerCase();
    if (RegExp(r'сут|қатиқ|шарбат|сок|ёгурт|ёғурт').hasMatch(n)) {
      return 'l';
    }
    return 'dona';
  }

  String get unitRu {
    switch (unitCode) {
      case 'kg':
        return 'кг';
      case 'l':
        return 'л';
      default:
        return 'дона';
    }
  }

  String qtyCaptionNum(num q) {
    if (q <= 0) return '0';
    final ru = unitRu;
    if (ru == 'дона') return '${q.round()} та';
    final v = (q * 2).round() / 2;
    final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '$s $ru';
  }

  int discountFor(num count) {
    if (count <= 0 || !bonusEnabled) return 0;
    if (bonusThreshold <= 0 ||
        bonusQty <= 0 ||
        bonusPercent <= 0 ||
        price <= 0) {
      return 0;
    }
    final c = count.toDouble();
    if (c + 1e-9 < bonusThreshold) return 0;
    final discounted = bonusQty > c ? c.toInt() : bonusQty;
    return (price * discounted * (bonusPercent / 100)).round();
  }

  int lineTotal(num qty) {
    final base = (price * qty.toDouble()).round();
    final d = discountFor(qty);
    final v = base - d;
    return v < 0 ? 0 : v;
  }

  factory BreadExtraProduct.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return BreadExtraProduct(
      id: doc.id.hashCode,
      firestoreId: doc.id,
      name: (d['name'] ?? '') as String,
      price: (d['price'] as num?)?.toInt() ?? 0,
      unit: (d['unit'] ?? 'dona') as String,
      qty: d['qty'],
      totalStock: (d['totalStock'] as num?)?.toInt() ?? 0,
      soldToday: (d['soldToday'] as num?)?.toInt() ?? 0,
      bonusEnabled: (d['bonusEnabled'] ?? false) as bool,
      bonusThreshold: (d['bonusThreshold'] as num?)?.toInt() ?? 0,
      bonusQty: (d['bonusQty'] as num?)?.toInt() ?? 0,
      bonusPercent: (d['bonusPercent'] as num?)?.toInt() ?? 0,
      emoji: (d['emoji'] ?? '') as String,
      caption: (d['caption'] ?? '') as String,
      imageUrl: (d['imageUrl'] ?? '') as String,
      tieToYopishBread: (d['tieToYopishBread'] ?? false) as bool,
    );
  }
}
