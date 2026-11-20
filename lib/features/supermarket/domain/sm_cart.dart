/// Супермаркет савати (битта сотувчи — AVA). Фақат `productId + qtyMilli` сақланади —
/// нарх ЭМАС: нарх ҳар сафар каталогдан, якуний сумма серверда (18-банд).
///
/// Қоидалар (эга 2026-11-20): бир хил таклиф қайта қўшилса — миқдор ошади; бошқа таклиф —
/// алоҳида қатор.
library;

import 'sm_offer.dart';
import 'sm_qty.dart';

class SmCartLine {
  const SmCartLine(this.productId, this.qtyMilli);

  final String productId;
  final int qtyMilli;

  Map<String, Object> toJson() => {'p': productId, 'q': qtyMilli};

  static SmCartLine? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final p = raw['p'];
    final q = raw['q'];
    if (p is! String || p.isEmpty || q is! int || q <= 0) return null;
    return SmCartLine(p, q);
  }
}

class SmCart {
  const SmCart([this.lines = const []]);

  static const empty = SmCart();

  final List<SmCartLine> lines;

  bool get isEmpty => lines.isEmpty;
  int get count => lines.length;

  int qtyOf(String productId) {
    for (final l in lines) {
      if (l.productId == productId) return l.qtyMilli;
    }
    return 0;
  }

  /// Қўшиш: бир хил таклиф — миқдор қўшилади; янги — охирига алоҳида қатор.
  SmCart add(String productId, int qtyMilli) {
    if (qtyMilli <= 0) return this;
    final has = lines.any((l) => l.productId == productId);
    final next = [
      for (final l in lines) l.productId == productId ? SmCartLine(productId, l.qtyMilli + qtyMilli) : l,
      if (!has) SmCartLine(productId, qtyMilli),
    ];
    return SmCart(List.unmodifiable(next));
  }

  /// Миқдорни қўйиш; `<= 0` — қатор олиб ташланади.
  SmCart setQty(String productId, int qtyMilli) {
    if (qtyMilli <= 0) return remove(productId);
    return SmCart(List.unmodifiable([
      for (final l in lines) l.productId == productId ? SmCartLine(productId, qtyMilli) : l,
    ]));
  }

  SmCart remove(String productId) =>
      SmCart(List.unmodifiable(lines.where((l) => l.productId != productId)));

  /// Таклифни алмаштириш (масалан бошқа нав/сифат). Янгиси саватда бўлса — бирлашади, жойи
  /// эскисининг ўрнида қолади.
  SmCart replaceOffer(String oldId, String newId, int qtyMilli) {
    if (oldId == newId) return setQty(oldId, qtyMilli);
    final existing = qtyOf(newId);
    final out = <SmCartLine>[];
    for (final l in lines) {
      if (l.productId == newId) continue;
      out.add(l.productId == oldId ? SmCartLine(newId, qtyMilli + existing) : l);
    }
    return SmCart(List.unmodifiable(out));
  }

  List<Map<String, Object>> toJson() => [for (final l in lines) l.toJson()];

  factory SmCart.fromJson(Object? raw) {
    if (raw is! List) return empty;
    final seen = <String>{};
    final out = <SmCartLine>[];
    for (final r in raw) {
      final l = SmCartLine.fromJson(r);
      if (l != null && seen.add(l.productId)) out.add(l);
    }
    return SmCart(List.unmodifiable(out));
  }
}

/// Кўрсатиш учун йиғинди (сервер жавоби келгач — сервер рақамлари кўрсатилади).
class SmCartTotals {
  const SmCartTotals({
    required this.goodsTotal,
    required this.weighedTotal,
    required this.weighedHold,
    required this.feeEstimate,
    required this.unavailableIds,
  });

  final int goodsTotal;
  final int weighedTotal;

  /// Тортиладиган маҳсулот учун +10% вақтинча ушлаш (эга 2026-11-20).
  final int weighedHold;
  final int feeEstimate;

  /// Каталогда йўқ / яширин / тугаган таклифлар — суммага кирмайди.
  final List<String> unavailableIds;

  int get holdEstimate => goodsTotal + weighedHold + feeEstimate;
}

/// Сукут (сервер settings/supermarket.weighHoldPercent йўқ бўлса — 10, эга 2026-11-20).
const int kSmWeighedHoldPercent = 10;

/// Сервер computeCharge кўзгуси (supermarket.js): ушлаш ҲАР тортиладиган қаторда алоҳида юқорига
/// яхлитланади; ҳақ = floor((goods × bps + 5000) / 10000). Якуний рақам — сервер жавоби.
SmCartTotals smCartTotals(
  SmCart cart,
  Map<String, SmOffer> offers, {
  num feePercent = 0,
  int weighHoldPercent = kSmWeighedHoldPercent,
}) {
  var goods = 0;
  var weighed = 0;
  var hold = 0;
  final bad = <String>[];
  for (final l in cart.lines) {
    final o = offers[l.productId];
    if (o == null || !o.available) {
      bad.add(l.productId);
      continue;
    }
    final t = smLineTotal(o.price, l.qtyMilli);
    goods += t;
    if (o.weighed) {
      weighed += t;
      hold += smPercentCeil(t, weighHoldPercent);
    }
  }
  return SmCartTotals(
    goodsTotal: goods,
    weighedTotal: weighed,
    weighedHold: hold,
    feeEstimate: smPercentOf(goods, feePercent),
    unavailableIds: List.unmodifiable(bad),
  );
}
