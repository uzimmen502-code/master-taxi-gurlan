/// `getSupermarketAccess` жавоби (сервер шартномаси, эга 2026-11-20):
/// `{allowed, reason, slots:[{id, names, startMin, endMin, day}], feePercent}`.
/// Ким кўради / қайси туман / қайси вақт — СЕРВЕР қарори (18, 44-банд); клиент фақат кўрсатади.
library;

import 'sm_taxonomy.dart';

class SmSlot {
  const SmSlot({
    required this.id,
    required this.names,
    required this.startMin,
    required this.endMin,
    required this.day,
  });

  final String id;
  final Map<String, String> names;
  final int startMin;
  final int endMin;

  /// Сервер қиймати (масалан `today` / `tomorrow` ёки сана) — клиент уни ўзгартирмай қайтаради.
  final String day;

  String label(String lang) {
    final n = localizedName(names, lang);
    return n.isNotEmpty ? n : '${smHhMm(startMin)}–${smHhMm(endMin)}';
  }

  static SmSlot? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    return SmSlot(
      id: id,
      names: smNames(raw['names']),
      startMin: (raw['startMin'] as num?)?.toInt() ?? 0,
      endMin: (raw['endMin'] as num?)?.toInt() ?? 0,
      day: raw['day']?.toString() ?? '',
    );
  }
}

String smHhMm(int min) =>
    '${(min ~/ 60).toString().padLeft(2, '0')}:${(min % 60).toString().padLeft(2, '0')}';

class SmAccess {
  const SmAccess({
    required this.allowed,
    this.reason = '',
    this.slots = const [],
    this.feePercent = 0,
  });

  static const denied = SmAccess(allowed: false, reason: 'unavailable');

  final bool allowed;
  final String reason;
  final List<SmSlot> slots;
  final num feePercent;

  /// Сервер берган кунлар (тартиб сақланади).
  List<String> get days {
    final out = <String>[];
    for (final s in slots) {
      if (!out.contains(s.day)) out.add(s.day);
    }
    return out;
  }

  factory SmAccess.fromMap(Object? raw) {
    if (raw is! Map) return denied;
    return SmAccess(
      allowed: raw['allowed'] == true,
      reason: raw['reason']?.toString() ?? '',
      slots: [
        if (raw['slots'] is List)
          ...(raw['slots'] as List).map(SmSlot.fromMap).whereType<SmSlot>(),
      ],
      feePercent: raw['feePercent'] is num ? raw['feePercent'] as num : 0,
    );
  }
}

/// `placeSupermarketOrder` натижаси.
class SmPlaceResult {
  const SmPlaceResult({required this.orderId, required this.goodsTotal, required this.fee, required this.hold});

  final String orderId;
  final int goodsTotal;
  final int fee;
  final int hold;

  factory SmPlaceResult.fromMap(Object? raw) {
    final m = raw is Map ? raw : const {};
    int i(String k) => (m[k] as num?)?.toInt() ?? 0;
    return SmPlaceResult(orderId: m['orderId']?.toString() ?? '', goodsTotal: i('goodsTotal'), fee: i('fee'), hold: i('hold'));
  }
}

/// Сервер хато коди → lang калити (25-банд: фойдаланувчига дўстона матн, логга — код).
///
/// NEEDS CONFIRMATION: аниқ кодлар сервер агенти билан келишилмаган; `details.code` (ёки
/// `details.errorCode`) шу рўйхатдан бўлса — аниқ матн, акс ҳолда gRPC коди бўйича умумий матн.
const kSmErrorKeys = <String, String>{
  'INSUFFICIENT_FUNDS': 'sm_err_insufficient_funds',
  'OUT_OF_STOCK': 'sm_err_out_of_stock',
  'PRICE_CHANGED': 'sm_err_price_changed',
  'DISTRICT_NOT_SERVED': 'sm_err_district',
  'SLOT_UNAVAILABLE': 'sm_err_slot',
  'INVALID_QTY': 'sm_err_qty',
  'NOT_ALLOWED': 'sm_err_not_allowed',
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
