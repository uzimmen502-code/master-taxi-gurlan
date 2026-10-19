// Миқдорга чегирма поғоналари (D-REST-25; docs/kafe_restoran_taklifi_uz.md §10.1).
//
// Ресторан ўз таомига поғона қўяди (мисол: плов 35 000; 10 тадан 32 000; 30 тадан 30 000) ва чегирмани
// ЎЗ ҲИСОБИДАН беради. Ҳақиқий нарх серверда ҳисобланади (`functions/restaurant_qty_tiers.js`,
// `placeRestaurantOrder`); бу ерда фақат кўрсатиш ва форма текшируви — қоида серверники билан БИР ХИЛ
// (мослик `qty_tiers_test.dart` да қулфланган; `firestore.rules` `qtyTiersOk` ҳам шу қоидада).
//
// Маъно (PROPOSED — эга «10 тадан кўпга» деган, чегара тенглиги айтилмаган): буюртмадаги таом СОНИ
// `minQty` ВА УНДАН КЎП бўлса, ҳар бир дона поғона нархида. Форма шуни аниқ ёзиб туради.

class QtyTier {
  const QtyTier({required this.minQty, required this.price});

  final int minQty;
  final int price;

  Map<String, Object> toMap() => {'minQty': minQty, 'price': price};

  @override
  bool operator ==(Object other) => other is QtyTier && other.minQty == minQty && other.price == price;

  @override
  int get hashCode => Object.hash(minQty, price);

  @override
  String toString() => 'QtyTier($minQty → $price)';
}

/// Форма хатоси калитлари → `restaurants_m_tiers_err_<калит>` (3 тилда).
abstract final class QtyTiersError {
  static const incomplete = 'incomplete';
  static const order = 'order';
  static const price = 'price';
}

abstract final class QtyTiers {
  /// Серверда `MAX_TIERS`, `MAX_TIER_QTY` (мослик тест билан қулфланган).
  static const maxTiers = 3;
  static const maxMinQty = 500;

  /// Биринчи поғона учун энг кичик сон: 1 дона — оддий нарх, поғона эмас.
  static const minFirstQty = 2;

  /// Фақат ТЎҒРИ префикс: `minQty` бутун, олдингисидан катта (биринчиси ≥ 2) ва ≤ 500; `price` бутун, ≥ 1
  /// ва олдинги нархдан КАМ (биринчиси — асосий нархдан кам). Биринчи нотўғри поғонадан кейин тўхтайди
  /// (сервердаги `sanitizeTiers` билан бир хил) — бузилган ҳужжат нархни оширмайди.
  static List<QtyTier> sanitize(int basePrice, Object? raw) {
    if (raw is! List || basePrice < 1) return const [];
    final out = <QtyTier>[];
    var prevMin = 1;
    var prevPrice = basePrice;
    for (final t in raw.take(maxTiers)) {
      if (t is! Map) break;
      final minQty = t['minQty'];
      final price = t['price'];
      if (minQty is! num || minQty != minQty.truncate() || price is! num || price != price.truncate()) break;
      final q = minQty.toInt();
      final p = price.toInt();
      if (q <= prevMin || q > maxMinQty || p < 1 || p >= prevPrice) break;
      out.add(QtyTier(minQty: q, price: p));
      prevMin = q;
      prevPrice = p;
    }
    return out;
  }

  /// [count] дона учун бир дона нархи; `tierMinQty == 0` — поғона қўлланмади.
  static ({int unitPrice, int tierMinQty}) unitPriceFor(int basePrice, List<QtyTier> tiers, int count) {
    var unit = basePrice;
    var min = 0;
    for (final t in tiers) {
      if (count >= t.minQty) {
        unit = t.price;
        min = t.minQty;
      }
    }
    return (unitPrice: unit, tierMinQty: min);
  }

  /// Кейинги поғона: [count] дан катта энг кичик `minQty` («яна N та қўшсангиз…»); йўқ бўлса `null`.
  static QtyTier? nextTier(List<QtyTier> tiers, int count) {
    for (final t in tiers) {
      if (t.minQty > count) return t;
    }
    return null;
  }

  /// Форма текшируви (тўлиқ қаторлар учун): хато калитлари ([QtyTiersError]); бўш рўйхат — тўғри.
  static List<String> validate(int basePrice, List<QtyTier> tiers) {
    final errs = <String>[];
    if (tiers.length > maxTiers) errs.add(QtyTiersError.order);
    var prevMin = minFirstQty - 1;
    var prevPrice = basePrice;
    for (final t in tiers) {
      if (t.minQty <= prevMin || t.minQty > maxMinQty) {
        if (!errs.contains(QtyTiersError.order)) errs.add(QtyTiersError.order);
      }
      if (t.price < 1 || t.price >= prevPrice) {
        if (!errs.contains(QtyTiersError.price)) errs.add(QtyTiersError.price);
      }
      prevMin = t.minQty;
      prevPrice = t.price;
    }
    return errs;
  }
}
