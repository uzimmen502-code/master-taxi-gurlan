/// Етишмовчилик (2-босқич шартномаси, эга 2026-11-21): буюртма қатори `state: 'shortage'` ва
/// `options {availableQty, substitutes:[offerId]}` олади. Мижоз `respondSupermarketShortage({orderId,
/// productId, choice:'substitute'|'reduce'|'remove', offerId?, qty?, clientRequestId})` чақиради.
/// Клиент ФАҚАТ кўрсатади ва танловни юборади; пул ҳисоби серверда (18-банд). Ҳамёнга таъсир —
/// тахминий кўрсатиш (етказиш ҳақи улуши ва тортиш ушлаши серверда).
library;

import 'sm_offer.dart';
import 'sm_qty.dart';

enum SmShortageChoice { substitute, reduce, remove }

String smShortageChoiceWire(SmShortageChoice c) => switch (c) {
      SmShortageChoice.substitute => 'substitute',
      SmShortageChoice.reduce => 'reduce',
      SmShortageChoice.remove => 'remove',
    };

class SmShortage {
  const SmShortage({
    required this.productId,
    required this.name,
    required this.price,
    required this.qtyMilli,
    required this.availableQtyMilli,
    this.substitutes = const [],
  });

  final String productId;
  final String name;
  final int price;
  final int qtyMilli;
  final int availableQtyMilli;
  final List<String> substitutes;

  int get lineTotal => smLineTotal(price, qtyMilli);

  /// «Камайтириш» мумкинми (мавжуд миқдор 0 дан катта ва буюртмадагидан кам).
  bool get canReduce => availableQtyMilli > 0 && availableQtyMilli < qtyMilli;

  /// `orders.items[]` қатори → етишмовчилик; бошқа ҳолат / бузилган — `null`.
  /// `options` йўқ бўлса `shortage` калити ҳам ўқилади (шартнома ўзгарса — эски шакл).
  static SmShortage? fromItem(Map<String, dynamic> m) {
    if (m['state'] != 'shortage') return null;
    if (m['removed'] != null && m['removed'] != false) return null;
    final pid = m['productId'];
    if (pid is! String || pid.isEmpty) return null;
    final opt = m['options'] is Map ? m['options'] as Map : (m['shortage'] is Map ? m['shortage'] as Map : const {});
    final avail = opt['availableQty'];
    final subs = opt['substitutes'];
    final q = m['qty'];
    return SmShortage(
      productId: pid,
      name: (m['name'] as String?)?.trim() ?? pid,
      price: (m['price'] as num?)?.toInt() ?? 0,
      qtyMilli: q is num ? smToMilli(q) : 0,
      availableQtyMilli: avail is num && avail > 0 ? smToMilli(avail) : 0,
      substitutes: [
        if (subs is List)
          for (final s in subs.toSet())
            if (s is String && s.isNotEmpty && s != pid) s,
      ],
    );
  }
}

/// Тахминий ҳамёнга таъсир: мусбат — яна ечилади, манфий — қайтади (сўм, бутун).
int smShortageWalletDelta(SmShortage s, SmShortageChoice choice, {SmOffer? substitute}) {
  switch (choice) {
    case SmShortageChoice.remove:
      return -s.lineTotal;
    case SmShortageChoice.reduce:
      return smLineTotal(s.price, s.availableQtyMilli) - s.lineTotal;
    case SmShortageChoice.substitute:
      if (substitute == null) return 0;
      return smLineTotal(substitute.price, smShortageSubstituteQty(s, substitute)) - s.lineTotal;
  }
}

/// Ўрнини босувчи учун миқдор: буюртмадаги миқдор шу таклиф қадамига тўғриланади.
int smShortageSubstituteQty(SmShortage s, SmOffer sub) => smSnapQty(s.qtyMilli, sub.stepMilli);

/// `respondSupermarketShortage` payload (шартнома).
Map<String, dynamic> smShortagePayload({
  required String orderId,
  required SmShortage shortage,
  required SmShortageChoice choice,
  required String clientRequestId,
  SmOffer? substitute,
}) =>
    {
      'orderId': orderId,
      'productId': shortage.productId,
      'choice': smShortageChoiceWire(choice),
      if (choice == SmShortageChoice.substitute && substitute != null) ...{
        'offerId': substitute.id,
        'qty': smFromMilli(smShortageSubstituteQty(shortage, substitute)),
      },
      if (choice == SmShortageChoice.reduce) 'qty': smFromMilli(shortage.availableQtyMilli),
      'clientRequestId': clientRequestId,
    };
