import 'shipping_dims.dart';
import '../../../models/price_tier.dart';

/// Битта маҳсулотнинг қадоғи (эга, 2026-10-31): «1 кг пакет», «5 кг қоп»,
/// «25 кг қоп» — ҳар бирининг ЎЗ нарх поғоналари, вазни ва ихтиёрий расми.
///
/// Маҳсулотда 1..[maxPacks] та. Қадоқсиз ESKI маҳсулот битта
/// [defaultId] қадоқ деб ҳисобланади ([WholesaleProduct.effectivePacks]) —
/// migration керак эмас.
///
/// Қолдиқ бу ерда ЭМАС: у `wholesale_stock/{productId}` да, фақат сервер
/// ёзади (сотувчи таҳрири буюртма камайтирган сонни босиб кетмаслиги учун).
class WholesalePack {
  const WholesalePack({
    required this.id,
    required this.label,
    required this.priceTiers,
    this.unitWeightG,
    this.unitDims,
    this.photoUrl = '',
  });

  static const maxPacks = 5;
  static const maxLabelLength = 40;

  /// Қадоқсиз эски маҳсулотнинг ягона қадоғи.
  static const defaultId = 'default';

  /// Барқарор ID (буюртма ва қолдиқ шу ID билан боғланади): `p1`..`p9`.
  final String id;
  final String label;
  final List<PriceTier> priceTiers;

  /// Бир дона ШУ қадоқнинг вазни (грамм) ва ўлчами — етказиш ҳақи учун.
  final int? unitWeightG;
  final ShippingDims? unitDims;

  /// Ихтиёрий: қадоқ танланганда асосий расм ўрнига кўрсатилади.
  final String photoUrl;

  bool get hasPhoto => photoUrl.trim().isNotEmpty;
  bool get hasShippingData => (unitWeightG ?? 0) > 0;

  /// Минимал буюртма — энг паст поғона.
  int get moq => priceTiers.isEmpty ? 1 : priceTiers.first.minQty;

  /// Бошланғич нарх («дан ...») — энг паст поғона нархи.
  int get basePrice => priceTiers.isEmpty ? 0 : priceTiers.first.price;

  /// [qty] даги бир дона нархи. Фақат кўрсатиш учун — буюртмада сервер ҳисоблайди.
  int priceForQty(int qty) => tierPriceForQty(priceTiers, qty) ?? 0;

  static bool isValidId(String id) => RegExp(r'^(p[1-9]|default)$').hasMatch(id);

  /// Ҳали банд бўлмаган биринчи ID (`p1`, `p2`, ...).
  static String nextId(Iterable<String> taken) {
    final used = taken.toSet();
    for (var i = 1; i <= 9; i++) {
      if (!used.contains('p$i')) return 'p$i';
    }
    throw StateError('pack ids exhausted');
  }

  static WholesalePack? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final id = (m['id'] as String?)?.trim() ?? '';
    final label = (m['label'] as String?)?.trim() ?? '';
    final tiers = parsePriceTiers(m['priceTiers']);
    if (!isValidId(id) || label.isEmpty || tiers.isEmpty) return null;
    final w = m['unitWeightG'];
    final weight = w is num && w.toInt() > 0 ? w.toInt() : null;
    return WholesalePack(
      id: id,
      label: label.length > maxLabelLength ? label.substring(0, maxLabelLength) : label,
      priceTiers: tiers,
      unitWeightG: weight,
      unitDims: ShippingDims.fromMap(m['unitDims']),
      photoUrl: (m['photoUrl'] as String?)?.trim() ?? '',
    );
  }

  /// Ҳужжатдаги `packs` рўйхати: нотўғри ёки такрорий ID'лилар ташланади.
  static List<WholesalePack> parseList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <WholesalePack>[];
    final seen = <String>{};
    for (final r in raw) {
      final p = fromMap(r);
      if (p == null || p.id == defaultId || !seen.add(p.id)) continue;
      out.add(p);
      if (out.length >= maxPacks) break;
    }
    return out;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label.trim(),
        'priceTiers': sortPriceTiers(priceTiers).take(5).map((t) => t.toMap()).toList(),
        if (unitWeightG != null && unitWeightG! > 0) 'unitWeightG': unitWeightG,
        if (unitDims != null) 'unitDims': unitDims!.toMap(),
        if (hasPhoto) 'photoUrl': photoUrl.trim(),
      };

  WholesalePack copyWith({
    String? label,
    List<PriceTier>? priceTiers,
    int? unitWeightG,
    ShippingDims? unitDims,
    String? photoUrl,
  }) =>
      WholesalePack(
        id: id,
        label: label ?? this.label,
        priceTiers: priceTiers ?? this.priceTiers,
        unitWeightG: unitWeightG ?? this.unitWeightG,
        unitDims: unitDims ?? this.unitDims,
        photoUrl: photoUrl ?? this.photoUrl,
      );
}

/// Қадоқлар бўйича қолдиқ — `wholesale_stock/{productId}` (фақат сервер ёзади).
///
/// Қадоқ учун қиймат йўқ бўлса (`null`) — сотувчи қолдиқ киритмаган:
/// харидорга ҳеч нарса кўрсатилмайди. `0` — «Тугаган».
class WholesaleStock {
  const WholesaleStock(this.byPack);

  static const empty = WholesaleStock({});
  static const maxQty = 1000000;

  final Map<String, int> byPack;

  int? of(String packId) => byPack[packId];

  bool isOut(String packId) => byPack[packId] == 0;

  factory WholesaleStock.fromMap(Map<String, dynamic>? d) {
    final raw = d?['packs'];
    if (raw is! Map) return empty;
    final out = <String, int>{};
    raw.forEach((k, v) {
      if (k is String && v is num && v >= 0) out[k] = v.toInt();
    });
    return WholesaleStock(out);
  }
}
