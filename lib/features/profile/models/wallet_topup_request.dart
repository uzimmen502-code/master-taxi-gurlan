import 'package:cloud_firestore/cloud_firestore.dart';

/// Эганинг ўз тўлдириш сўрови (`wallet_topup_requests`, Telegram бот орқали).
///
/// Қоида эгага ўз сўровини ўқишга рухсат беради, лекин аввал иловада кўриниш
/// йўқ эди — эга «чек қабул қилинди, текширувда» ҳолатини фақат ботдаги
/// `/status` орқали билар эди.
class WalletTopUpRequest {
  const WalletTopUpRequest({
    required this.id,
    required this.amount,
    required this.status,
    this.createdAt,
    this.expiresAt,
    this.rejectReason = '',
  });

  final String id;
  final int amount;

  /// `awaiting_transfer` | `awaiting_review` | `credited` | `rejected` |
  /// `expired` | `cancelled`.
  final String status;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final String rejectReason;

  factory WalletTopUpRequest.fromMap(String id, Map<String, dynamic> d) {
    DateTime? ts(Object? v) => v is Timestamp ? v.toDate() : null;
    return WalletTopUpRequest(
      id: id,
      amount: (d['amount'] as num?)?.toInt() ?? 0,
      status: (d['status'] ?? '').toString(),
      createdAt: ts(d['createdAt']),
      expiresAt: ts(d['expiresAt']),
      rejectReason: (d['rejectReason'] ?? '').toString().trim(),
    );
  }

  /// Сервер ҳали муддати ўтганларни `expired` қилмайди (`expiresAt` ёзилади,
  /// лекин ёпувчи жараён йўқ) — «чек кутилмоқда» деб абадий туриб қолмаслиги
  /// учун кўрсатишда ҳисобга олинади. Чек юборилган (`awaiting_review`)
  /// сўров муддатдан қатъи назар текширувда ҳисобланади.
  String effectiveStatus(DateTime now) {
    if (status == 'awaiting_transfer' && expiresAt != null && now.isAfter(expiresAt!)) {
      return 'expired';
    }
    return status;
  }

  /// Эгадан ҳали ҳаракат ёки жавоб кутилаётган сўров.
  bool isOpen(DateTime now) {
    final s = effectiveStatus(now);
    return s == 'awaiting_transfer' || s == 'awaiting_review';
  }
}

/// Экранда кўрсатиладиганлари: очиқлари ҳар доим (энг янгиси биринчи), ёпиқлари
/// ([keep] ичида, энг кўпи [max] тагача). Қолгани — тарихда, шовқин қилмайди.
List<WalletTopUpRequest> visibleTopUpRequests(
  Iterable<WalletTopUpRequest> all,
  DateTime now, {
  int max = 5,
  Duration keep = const Duration(days: 7),
}) {
  final list = all.toList()
    ..sort((a, b) {
      final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
  final out = <WalletTopUpRequest>[];
  for (final r in list) {
    final recent = r.createdAt != null && now.difference(r.createdAt!) <= keep;
    if (r.isOpen(now) || recent) out.add(r);
    if (out.length >= max) break;
  }
  return out;
}
