/// Етишмовчилик (2-босқич; сервер feat/supermarket-srv cd02561a, supermarket.js `applyShortageReport` /
/// `applyShortageChoice`, эга 2026-11-21).
///
/// Қатор: `items[i].shortage = {state 'pending'|'resolved'|'admin_removed', availableQty,
///   substitutes:[{offerId, name, price, smUnit, unit, qtyStep, weighed, packLabel?, imageUrl?}], reportedAtMs,
///   answerByMs, choice?, resolvedAtMs?}`; буюртма: `smShortagePending`.
/// Ҳал бўлгач қатор: `substitutedFrom{productId,name,price,qty,total}` | `reducedFrom{qty,total}` |
///   `removed{reason:'shortage'}`.
/// Мижоз `respondSupermarketShortage({orderId, productId, choice, offerId?, qty?, clientRequestId})` →
///   `{ok, refund, debit, total, duplicate?}`. Клиент ФАҚАТ кўрсатади; пул ҳисоби серверда (18-банд).
/// Ҳамёнга таъсир — ТАХМИНИЙ: қимматроқ алмаштиришда сервер фарқни етказиш ҳақи фоизи ва тортиш ушлаши
/// билан бирга ечади.
library;

import 'sm_qty.dart';
import 'sm_taxonomy.dart' show kSmUnits;

enum SmShortageChoice { substitute, reduce, remove }

String smShortageChoiceWire(SmShortageChoice c) => switch (c) {
      SmShortageChoice.substitute => 'substitute',
      SmShortageChoice.reduce => 'reduce',
      SmShortageChoice.remove => 'remove',
    };

/// Сервер `substituteView` нусхаси (жорий нарх ҳисобот пайтида олинган; якуний нарх — серверда).
class SmShortageSub {
  const SmShortageSub({
    required this.offerId,
    required this.name,
    required this.price,
    required this.unit,
    required this.stepMilli,
    this.weighed = false,
    this.packLabel = '',
    this.imageUrl = '',
  });

  final String offerId;
  final String name;
  final int price;

  /// `smUnit` (kg|l|piece|pack|bunch).
  final String unit;
  final int stepMilli;
  final bool weighed;
  final String packLabel;
  final String imageUrl;

  static SmShortageSub? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['offerId'];
    final price = raw['price'];
    if (id is! String || id.isEmpty || price is! num || price <= 0) return null;
    final unit = raw['smUnit'] is String && kSmUnits.contains(raw['smUnit']) ? raw['smUnit'] as String : 'piece';
    final step = raw['qtyStep'] is num ? smToMilli(raw['qtyStep'] as num) : 1000;
    String s(Object? v) => v is String ? v.trim() : '';
    return SmShortageSub(
      offerId: id,
      name: s(raw['name']).isEmpty ? id : s(raw['name']),
      price: price.toInt(),
      unit: unit,
      stepMilli: step > 0 ? step : 1000,
      weighed: raw['weighed'] == true,
      packLabel: s(raw['packLabel']),
      imageUrl: s(raw['imageUrl']),
    );
  }
}

class SmShortage {
  const SmShortage({
    required this.productId,
    required this.name,
    required this.price,
    required this.qtyMilli,
    required this.availableQtyMilli,
    this.stepMilli = 1000,
    this.substitutes = const [],
    this.answerBy,
  });

  final String productId;
  final String name;
  final int price;
  final int qtyMilli;
  final int availableQtyMilli;

  /// Қатор қадами (`qtyStep`) — камайтириш шунга мос (сервер текширади).
  final int stepMilli;
  final List<SmShortageSub> substitutes;

  /// Жавоб муддати (`answerByMs`); кейин AVA қаторни ўзи олиб ташлаши мумкин.
  final DateTime? answerBy;

  int get lineTotal => smLineTotal(price, qtyMilli);

  /// «Камайтириш» мумкинми (мавжуд миқдор 0 дан катта ва буюртмадагидан кам).
  bool get canReduce => availableQtyMilli > 0 && availableQtyMilli < qtyMilli;

  /// ФАҚАТ `shortage.state == 'pending'` ва олинмаган қатор → етишмовчилик; бошқаси — `null`.
  static SmShortage? fromItem(Map<String, dynamic> m) {
    final sh = m['shortage'];
    if (sh is! Map || sh['state'] != 'pending') return null;
    if (m['removed'] != null && m['removed'] != false) return null;
    final pid = m['productId'];
    if (pid is! String || pid.isEmpty) return null;
    final avail = sh['availableQty'];
    final subs = sh['substitutes'];
    final q = m['qty'];
    final step = m['qtyStep'] is num ? smToMilli(m['qtyStep'] as num) : 1000;
    final by = sh['answerByMs'];
    final seen = <String>{};
    return SmShortage(
      productId: pid,
      name: (m['name'] as String?)?.trim() ?? pid,
      price: (m['price'] as num?)?.toInt() ?? 0,
      qtyMilli: q is num ? smToMilli(q) : 0,
      availableQtyMilli: avail is num && avail > 0 ? smToMilli(avail) : 0,
      stepMilli: step > 0 ? step : 1000,
      substitutes: [
        if (subs is List)
          for (final s in subs.map(SmShortageSub.fromMap).whereType<SmShortageSub>())
            if (s.offerId != pid && seen.add(s.offerId)) s,
      ],
      answerBy: by is num ? DateTime.fromMillisecondsSinceEpoch(by.toInt()) : null,
    );
  }
}

/// Ўрнини босувчи учун миқдор: буюртмадаги миқдор шу таклиф қадамига тўғриланади.
int smShortageSubstituteQty(SmShortage s, SmShortageSub sub) => smSnapQty(s.qtyMilli, sub.stepMilli);

/// ТАХМИНИЙ ҳамёнга таъсир (фақат маҳсулот суммаси фарқи): мусбат — яна ечилади, манфий — қайтади.
int smShortageWalletDelta(SmShortage s, SmShortageChoice choice, {SmShortageSub? substitute}) {
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

/// Жавоб муддатига қолган вақт (дақиқа, юқорига); муддат йўқ — `null`, ўтган — 0.
int? smShortageMinutesLeft(SmShortage s, DateTime now) {
  final by = s.answerBy;
  if (by == null) return null;
  final ms = by.difference(now).inMilliseconds;
  if (ms <= 0) return 0;
  return (ms + 59999) ~/ 60000;
}

/// `respondSupermarketShortage` payload (сервер шартномаси).
Map<String, dynamic> smShortagePayload({
  required String orderId,
  required SmShortage shortage,
  required SmShortageChoice choice,
  required String clientRequestId,
  SmShortageSub? substitute,
}) =>
    {
      'orderId': orderId,
      'productId': shortage.productId,
      'choice': smShortageChoiceWire(choice),
      if (choice == SmShortageChoice.substitute && substitute != null) ...{
        'offerId': substitute.offerId,
        'qty': smFromMilli(smShortageSubstituteQty(shortage, substitute)),
      },
      if (choice == SmShortageChoice.reduce) 'qty': smFromMilli(shortage.availableQtyMilli),
      'clientRequestId': clientRequestId,
    };

/// Жавоб натижаси: `{ok, refund, debit, total, duplicate?}`.
class SmShortageResult {
  const SmShortageResult({this.refund = 0, this.debit = 0, this.total = 0, this.duplicate = false});

  final int refund;
  final int debit;
  final int total;
  final bool duplicate;

  factory SmShortageResult.fromMap(Object? raw) {
    final m = raw is Map ? raw : const {};
    int i(String k) => (m[k] as num?)?.toInt() ?? 0;
    return SmShortageResult(refund: i('refund'), debit: i('debit'), total: i('total'), duplicate: m['duplicate'] == true);
  }
}

/// Ҳал бўлган етишмовчилик қатори (кўрсатиш учун).
enum SmShortageOutcome { substituted, reduced, removed }

typedef SmShortageResolution = ({
  SmShortageOutcome outcome,
  String name,
  String fromName,
  int fromQtyMilli,
  int toQtyMilli,
  int fromTotal,
  int toTotal,
});

/// `substitutedFrom` / `reducedFrom` / `removed{reason:'shortage'}` → кўриниш; бошқа қатор — `null`.
SmShortageResolution? smShortageResolutionOf(Map<String, dynamic> m) {
  int milli(Object? v) => v is num ? smToMilli(v) : 0;
  int money(Object? v) => v is num ? v.toInt() : 0;
  final name = (m['name'] as String?)?.trim() ?? '';
  final removed = m['removed'];
  if (removed is Map && removed['reason'] == 'shortage') {
    return (
      outcome: SmShortageOutcome.removed,
      name: name,
      fromName: name,
      fromQtyMilli: milli(m['qty']),
      toQtyMilli: 0,
      fromTotal: money(m['total']),
      toTotal: 0,
    );
  }
  final sf = m['substitutedFrom'];
  if (sf is Map) {
    return (
      outcome: SmShortageOutcome.substituted,
      name: name,
      fromName: (sf['name'] as String?)?.trim() ?? '',
      fromQtyMilli: milli(sf['qty']),
      toQtyMilli: milli(m['qty']),
      fromTotal: money(sf['total']),
      toTotal: money(m['total']),
    );
  }
  final rf = m['reducedFrom'];
  if (rf is Map) {
    return (
      outcome: SmShortageOutcome.reduced,
      name: name,
      fromName: name,
      fromQtyMilli: milli(rf['qty']),
      toQtyMilli: milli(m['qty']),
      fromTotal: money(rf['total']),
      toTotal: money(m['total']),
    );
  }
  return null;
}
