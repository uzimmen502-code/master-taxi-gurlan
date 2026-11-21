/// `getSupermarketAccess({districtId?})` жавоби — сервер (supermarket.js, feat/supermarket-srv 48a7d45f):
/// `{allowed, reason, messages?{uz_Cyrl,uz_Latn,ru}, districtId, slots:{today[], tomorrow[]},
///   feePercent|null, weighHoldPercent, tariffVersion}`; слот: `{id, names, startMin, endMin, date}`.
/// Ким кўради / қайси туман / қайси вақт — СЕРВЕР қарори (18, 44-банд); клиент фақат кўрсатади.
library;

import 'sm_cart.dart' show kSmWeighedHoldPercent;
import 'sm_taxonomy.dart';

class SmSlot {
  const SmSlot({
    required this.id,
    required this.names,
    required this.startMin,
    required this.endMin,
    required this.day,
    this.date = '',
  });

  final String id;
  final Map<String, String> names;
  final int startMin;
  final int endMin;

  /// `today` | `tomorrow` (сервер `DAYS`) — буюртмада шу қиймат қайтарилади.
  final String day;

  /// Тошкент санаси `YYYY-MM-DD` (кўрсатиш учун).
  final String date;

  String label(String lang) {
    final n = localizedName(names, lang);
    return n.isNotEmpty ? n : '${smHhMm(startMin)}–${smHhMm(endMin)}';
  }

  static SmSlot? fromMap(Object? raw, {String? day}) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    return SmSlot(
      id: id,
      names: smNames(raw['names']),
      startMin: (raw['startMin'] as num?)?.toInt() ?? 0,
      endMin: (raw['endMin'] as num?)?.toInt() ?? 0,
      day: day ?? raw['day']?.toString() ?? '',
      date: raw['date']?.toString() ?? '',
    );
  }
}

String smHhMm(int min) =>
    '${(min ~/ 60).toString().padLeft(2, '0')}:${(min % 60).toString().padLeft(2, '0')}';

/// Сервер `messages` (3 тил) → жорий тилдаги матн; йўқ бўлса бўш.
String smServerMessage(Map<String, String> messages, String lang) => localizedName(messages, lang);

class SmAccess {
  const SmAccess({
    required this.allowed,
    this.reason = '',
    this.messages = const {},
    this.districtId = '',
    this.slots = const [],
    this.feePercent = 0,
    this.weighHoldPercent = kSmWeighedHoldPercent,
    this.tariffVersion = '',
  });

  static const denied = SmAccess(allowed: false, reason: 'unavailable');

  final bool allowed;
  final String reason;
  final Map<String, String> messages;
  final String districtId;
  final List<SmSlot> slots;
  final num feePercent;
  final int weighHoldPercent;
  final String tariffVersion;

  /// Бўш вақти бор кунлар (тартиб: today, tomorrow).
  List<String> get days {
    final out = <String>[];
    for (final s in slots) {
      if (!out.contains(s.day)) out.add(s.day);
    }
    return out;
  }

  factory SmAccess.fromMap(Object? raw) {
    if (raw is! Map) return denied;
    final slots = <SmSlot>[];
    final s = raw['slots'];
    if (s is Map) {
      for (final day in const ['today', 'tomorrow']) {
        final list = s[day];
        if (list is List) slots.addAll(list.map((e) => SmSlot.fromMap(e, day: day)).whereType<SmSlot>());
      }
    } else if (s is List) {
      // Эски шартнома шакли (рўйхат, ҳар бирида `day`).
      slots.addAll(s.map((e) => SmSlot.fromMap(e)).whereType<SmSlot>());
    }
    return SmAccess(
      allowed: raw['allowed'] == true,
      reason: raw['reason']?.toString() ?? '',
      messages: smNames(raw['messages']),
      districtId: raw['districtId']?.toString() ?? '',
      slots: slots,
      feePercent: raw['feePercent'] is num ? raw['feePercent'] as num : 0,
      weighHoldPercent: raw['weighHoldPercent'] is num ? (raw['weighHoldPercent'] as num).toInt() : kSmWeighedHoldPercent,
      tariffVersion: raw['tariffVersion']?.toString() ?? '',
    );
  }
}

/// `placeSupermarketOrder` натижаси (сервер: `{orderId, itemsTotal, weighHold, deliveryFee, total, duplicate?}`).
class SmPlaceResult {
  const SmPlaceResult({
    required this.orderId,
    required this.goodsTotal,
    required this.fee,
    required this.hold,
    this.weighHold = 0,
    this.duplicate = false,
  });

  final String orderId;
  final int goodsTotal;
  final int fee;

  /// Ҳамёндан ечилган (вақтинча ушланган) жами.
  final int hold;
  final int weighHold;
  final bool duplicate;

  factory SmPlaceResult.fromMap(Object? raw) {
    final m = raw is Map ? raw : const {};
    int i(String a, [String? b]) => ((m[a] ?? (b == null ? null : m[b])) as num?)?.toInt() ?? 0;
    return SmPlaceResult(
      orderId: m['orderId']?.toString() ?? '',
      goodsTotal: i('itemsTotal', 'goodsTotal'),
      fee: i('deliveryFee', 'fee'),
      hold: i('total', 'hold'),
      weighHold: i('weighHold'),
      duplicate: m['duplicate'] == true,
    );
  }
}

/// Сервер хато коди (`details.code`) → lang калити (25-банд). Сервер `details.messages` берса — экран
/// аввал ўшани кўрсатади ([SmCallError.messages]); калит — захира.
const kSmErrorKeys = <String, String>{
  'INSUFFICIENT_BALANCE': 'sm_err_insufficient_funds',
  // 2-босқич шартномаси (respondSupermarketShortage): ҳамён етмаса — тўлдириш кўрсатилади.
  'INSUFFICIENT_FUNDS': 'sm_err_insufficient_funds',
  'LINE_SHORTAGE_RESOLVED': 'sm_err_shortage_resolved',
  'LINE_NO_SHORTAGE': 'sm_err_shortage_resolved',
  'SUBSTITUTE_INVALID': 'sm_err_substitute',
  'LAST_LINE': 'sm_err_last_line',
  'ORDER_STATE_LOCKED': 'sm_err_order_locked',
  'OUT_OF_STOCK': 'sm_err_out_of_stock',
  'PRODUCT_UNAVAILABLE': 'sm_err_out_of_stock',
  'PRODUCT_NOT_FOUND': 'sm_err_out_of_stock',
  'PRICE_MISSING': 'sm_err_price_changed',
  'DISTRICT_NOT_SERVED': 'sm_err_district',
  'DISTRICT_REQUIRED': 'sm_err_district',
  'SLOT_UNAVAILABLE': 'sm_err_slot',
  'QTY_STEP_INVALID': 'sm_err_qty',
  'DUPLICATE_ITEM': 'sm_err_qty',
  'STAGE_OFF': 'sm_err_not_allowed',
  'NOT_TESTER': 'sm_err_not_allowed',
  'PERMISSION_DENIED': 'sm_err_not_allowed',
};

String smErrorKey({required String grpcCode, Object? details}) {
  if (details is Map) {
    final c = (details['code'] ?? details['errorCode'])?.toString() ?? '';
    final k = kSmErrorKeys[c];
    if (k != null) return k;
  }
  switch (grpcCode) {
    case 'unavailable':
    case 'deadline-exceeded':
      return 'sm_err_network';
    case 'permission-denied':
    case 'unauthenticated':
      return 'sm_err_not_allowed';
    default:
      return 'sm_err_generic';
  }
}
