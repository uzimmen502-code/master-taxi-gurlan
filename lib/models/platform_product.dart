import 'package:cloud_firestore/cloud_firestore.dart';

/// Платформа дўкони товари (`platform_products`).
///
/// `totalStock <= 0` → лимитсиз. Қолдиқ = totalStock − soldToday.
/// Расмлар: `imageUrls` (1–5). `imageUrl` — қоплама (биринчи расм, back-compat).
/// `goodsKind`: `food` | `non_food` | '' (белгиланмаган).
class PlatformProduct {
  const PlatformProduct({
    required this.id,
    required this.name,
    required this.price,
    this.description = '',
    this.imageUrl = '',
    this.imageUrls = const [],
    this.unit = 'дона',
    this.minQty = 1,
    this.step = 1,
    this.totalStock = 0,
    this.soldToday = 0,
    this.active = true,
    this.featuredOnHome = false,
    this.showInMarket = true,
    this.sortOrder = 0,
    this.goodsKind = '',
  });

  static const maxImages = 5;
  static const kindFood = 'food';
  static const kindNonFood = 'non_food';

  final String id;
  final String name;
  final String description;
  final int price;
  final String imageUrl;
  final List<String> imageUrls;
  final String unit;
  final int minQty;
  final int step;
  final int totalStock;
  final int soldToday;
  final bool active;
  final bool featuredOnHome;
  final bool showInMarket;
  final int sortOrder;

  /// `food` | `non_food` | ''.
  final String goodsKind;

  bool get isFood => goodsKind == kindFood;
  bool get isNonFood => goodsKind == kindNonFood;
  bool get isKindSet => isFood || isNonFood;

  static String normalizeKind(String? raw) {
    final k = (raw ?? '').trim().toLowerCase();
    if (k == kindFood || k == 'oziq' || k == 'озиқ') return kindFood;
    if (k == kindNonFood ||
        k == 'nonfood' ||
        k == 'non-food' ||
        k == 'no_oziq' ||
        k == 'но-озиқ' ||
        k == 'ноозиқ') {
      return kindNonFood;
    }
    return '';
  }

  /// UI учун: imageUrls ёки эски imageUrl.
  List<String> get displayImages {
    if (imageUrls.isNotEmpty) {
      return imageUrls
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .take(maxImages)
          .toList(growable: false);
    }
    final one = imageUrl.trim();
    return one.isEmpty ? const <String>[] : <String>[one];
  }

  String get coverImageUrl {
    final list = displayImages;
    return list.isEmpty ? '' : list.first;
  }

  bool get isUnlimitedStock => totalStock <= 0;

  int get remaining {
    if (isUnlimitedStock) return 999999;
    final left = totalStock - soldToday;
    return left < 0 ? 0 : left;
  }

  bool get inStock => isUnlimitedStock || remaining > 0;

  static List<String> _parseUrls(Map<String, dynamic> d) {
    final out = <String>[];
    final raw = d['imageUrls'];
    if (raw is List) {
      for (final x in raw) {
        final s = x?.toString().trim() ?? '';
        if (s.isNotEmpty) out.add(s);
      }
    }
    if (out.isEmpty) {
      final one = (d['imageUrl'] as String?)?.trim() ?? '';
      if (one.isNotEmpty) out.add(one);
    }
    if (out.length > maxImages) {
      return out.sublist(0, maxImages);
    }
    return out;
  }

  factory PlatformProduct.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final urls = _parseUrls(d);
    return PlatformProduct(
      id: doc.id,
      name: (d['name'] as String?)?.trim() ?? '',
      description: (d['description'] as String?)?.trim() ?? '',
      price: (d['price'] as num?)?.toInt() ?? 0,
      imageUrl: urls.isNotEmpty
          ? urls.first
          : ((d['imageUrl'] as String?)?.trim() ?? ''),
      imageUrls: urls,
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
      goodsKind: normalizeKind(d['goodsKind']?.toString()),
    );
  }

  PlatformProduct copyWith({
    String? id,
    String? name,
    String? description,
    int? price,
    String? imageUrl,
    List<String>? imageUrls,
    String? unit,
    int? minQty,
    int? step,
    int? totalStock,
    int? soldToday,
    bool? active,
    bool? featuredOnHome,
    bool? showInMarket,
    int? sortOrder,
    String? goodsKind,
  }) {
    return PlatformProduct(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      imageUrl: imageUrl ?? this.imageUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      unit: unit ?? this.unit,
      minQty: minQty ?? this.minQty,
      step: step ?? this.step,
      totalStock: totalStock ?? this.totalStock,
      soldToday: soldToday ?? this.soldToday,
      active: active ?? this.active,
      featuredOnHome: featuredOnHome ?? this.featuredOnHome,
      showInMarket: showInMarket ?? this.showInMarket,
      sortOrder: sortOrder ?? this.sortOrder,
      goodsKind: goodsKind ?? this.goodsKind,
    );
  }

  Map<String, dynamic> _imageFields() {
    final urls = imageUrls
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(maxImages)
        .toList(growable: false);
    final cover = urls.isNotEmpty ? urls.first : imageUrl.trim();
    return {
      'imageUrl': cover,
      'imageUrls': urls.isNotEmpty
          ? urls
          : (cover.isEmpty ? <String>[] : <String>[cover]),
    };
  }

  Map<String, dynamic> toFirestoreCreate() => {
        'name': name,
        'description': description,
        'price': price,
        ..._imageFields(),
        'unit': unit,
        'minQty': minQty,
        'step': step,
        'totalStock': totalStock,
        'soldToday': soldToday,
        'active': active,
        'featuredOnHome': featuredOnHome,
        'showInMarket': showInMarket,
        'sortOrder': sortOrder,
        'goodsKind': normalizeKind(goodsKind),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toFirestoreUpdate() => {
        'name': name,
        'description': description,
        'price': price,
        ..._imageFields(),
        'unit': unit,
        'minQty': minQty,
        'step': step,
        'totalStock': totalStock,
        'active': active,
        'featuredOnHome': featuredOnHome,
        'showInMarket': showInMarket,
        'sortOrder': sortOrder,
        'goodsKind': normalizeKind(goodsKind),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
