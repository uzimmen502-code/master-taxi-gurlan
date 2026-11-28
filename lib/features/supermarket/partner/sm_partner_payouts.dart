import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../admin_web/services/admin_sm_partner_payout_service.dart' show smBpToPercent;

/// «AVA Супермаркет» ҳамкорга тўлов (эга 2026-11-28) — ҳамкор ЎЗ балансини кўради (`partnerGetSmPayouts`).
/// Ҳисоб-китоб ФАҚАТ серверда (supermarket буюртмаси етказилганда, мавжуд ledger); бу ерда фақат кўрсатиш.
/// Босқич `public` бўлмаса сервер `enabled:false` қайтаради — карта кўринмайди.

int _i(Object? v) => v is num ? v.toInt() : 0;
int? _iN(Object? v) => v is num ? v.toInt() : null;
String _s(Object? v) => v == null ? '' : '$v';

class SmPartnerPayable {
  const SmPartnerPayable({
    required this.orderId,
    required this.slotDate,
    required this.status,
    required this.goodsBasis,
    this.commission,
    this.amount,
  });

  final String orderId;
  final String slotDate;

  /// accrued | paid | reversed | blocked | nothing_due | void
  final String status;
  final int goodsBasis;
  final int? commission;
  final int? amount;

  factory SmPartnerPayable.fromMap(Map m) => SmPartnerPayable(
        orderId: _s(m['orderId']),
        slotDate: _s(m['slotDate']),
        status: _s(m['status']),
        goodsBasis: _i(m['goodsBasis']),
        commission: _iN(m['commission']),
        amount: _iN(m['amount']),
      );
}

class SmPartnerPayment {
  const SmPartnerPayment({required this.amount, required this.method, this.reference = '', this.createdAtMs});
  final int amount;
  final String method;
  final String reference;
  final int? createdAtMs;

  factory SmPartnerPayment.fromMap(Map m) => SmPartnerPayment(
        amount: _i(m['amount']),
        method: _s(m['method']),
        reference: _s(m['reference']),
        createdAtMs: _iN(m['createdAtMs']),
      );
}

class SmPartnerPayouts {
  const SmPartnerPayouts({
    required this.enabled,
    this.balance = 0,
    this.accruedTotal = 0,
    this.paidTotal = 0,
    this.reversedTotal = 0,
    this.blockedCount = 0,
    this.commissionBp,
    this.payables = const [],
    this.payments = const [],
  });

  static const disabled = SmPartnerPayouts(enabled: false);

  final bool enabled;

  /// AVA ҳамкорга ҳозир қарздор (манфий — ҳамкор қайтариши керак, тўлангандан кейинги қайтариш).
  final int balance;
  final int accruedTotal;
  final int paidTotal;
  final int reversedTotal;
  final int blockedCount;
  final int? commissionBp;
  final List<SmPartnerPayable> payables;
  final List<SmPartnerPayment> payments;

  factory SmPartnerPayouts.fromMap(Map m) {
    if (m['enabled'] != true) return disabled;
    return SmPartnerPayouts(
      enabled: true,
      balance: _i(m['balance']),
      accruedTotal: _i(m['accruedTotal']),
      paidTotal: _i(m['paidTotal']),
      reversedTotal: _i(m['reversedTotal']),
      blockedCount: _i(m['blockedCount']),
      commissionBp: _iN(m['commissionBp']),
      payables: [for (final p in (m['payables'] is List ? m['payables'] as List : const [])) if (p is Map) SmPartnerPayable.fromMap(p)],
      payments: [for (final p in (m['payments'] is List ? m['payments'] as List : const [])) if (p is Map) SmPartnerPayment.fromMap(p)],
    );
  }
}

/// Ҳамкор «Тўловлар» картаси. [load] — `SmPartnerService.myPayouts`; хато ёки ўчиқ бўлса карта кўринмайди.
class SmPartnerPayoutsCard extends StatefulWidget {
  const SmPartnerPayoutsCard({super.key, required this.load});
  final Future<SmPartnerPayouts> Function() load;

  @override
  State<SmPartnerPayoutsCard> createState() => _SmPartnerPayoutsCardState();
}

class _SmPartnerPayoutsCardState extends State<SmPartnerPayoutsCard> {
  SmPartnerPayouts _p = SmPartnerPayouts.disabled;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await widget.load();
      if (mounted) setState(() => _p = p);
    } catch (e) {
      debugPrint('[SmPartnerPayouts] load failed: $e');
    }
  }

  String _status(String s) => context.tr(switch (s) {
        'paid' => 'smp_pay_status_paid',
        'reversed' => 'smp_pay_status_reversed',
        'blocked' => 'smp_pay_status_blocked',
        'nothing_due' => 'smp_pay_status_nothing_due',
        'void' => 'smp_pay_status_void',
        _ => 'smp_pay_status_accrued',
      });

  String _method(String m) => context.tr(switch (m) {
        'bank_transfer' => 'smp_pay_method_bank_transfer',
        'offset' => 'smp_pay_method_offset',
        _ => 'smp_pay_method_cash',
      });

  Widget _kv(String label, int v, {Key? key, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(formatMoney(v), key: key, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (!p.enabled) return const SizedBox.shrink();
    final neg = p.balance < 0;
    return Card(
      key: const ValueKey('smp_pay_card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('smp_pay_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          _kv(context.tr(neg ? 'smp_pay_balance_negative' : 'smp_pay_balance'), neg ? -p.balance : p.balance,
              key: const ValueKey('smp_pay_balance'), color: neg ? Colors.red : Colors.green.shade700),
          _kv(context.tr('smp_pay_accrued'), p.accruedTotal),
          _kv(context.tr('smp_pay_paid'), p.paidTotal),
          if (p.reversedTotal > 0) _kv(context.tr('smp_pay_reversed'), p.reversedTotal),
          if (p.commissionBp != null)
            Text(context.tr('smp_pay_commission').replaceAll('{pct}', smBpToPercent(p.commissionBp!)),
                key: const ValueKey('smp_pay_commission'), style: TextStyle(color: Colors.grey.shade700)),
          if (p.blockedCount > 0)
            Text(context.tr('smp_pay_blocked').replaceAll('{n}', '${p.blockedCount}'), style: TextStyle(color: Colors.orange.shade800)),
          Text(context.tr('smp_pay_note'), style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
          if (p.payables.isEmpty)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(context.tr('smp_pay_empty'), key: const ValueKey('smp_pay_empty'))),
          if (p.payables.isNotEmpty)
            TextButton(
              key: const ValueKey('smp_pay_toggle'),
              onPressed: () => setState(() => _open = !_open),
              child: Text(context.tr('smp_pay_details')),
            ),
          if (_open) ...[
            for (final x in p.payables)
              ListTile(
                key: ValueKey('smp_pay_row_${x.orderId}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('smp_pay_order').replaceAll('{id}', x.orderId.length > 6 ? x.orderId.substring(0, 6) : x.orderId).replaceAll('{date}', x.slotDate)),
                subtitle: Text([
                  if (x.amount != null)
                    context
                        .tr('smp_pay_line')
                        .replaceAll('{goods}', formatMoney(x.goodsBasis))
                        .replaceAll('{fee}', formatMoney(x.commission ?? 0))
                        .replaceAll('{amount}', formatMoney(x.amount!)),
                  _status(x.status),
                ].join('\n')),
              ),
            if (p.payments.isNotEmpty) ...[
              const Divider(),
              Text(context.tr('smp_pay_payments'), style: const TextStyle(fontWeight: FontWeight.w600)),
              for (final pay in p.payments)
                Text(
                  [
                    formatMoney(pay.amount),
                    _method(pay.method),
                    if (pay.reference.isNotEmpty) pay.reference,
                    if (pay.createdAtMs != null) formatDateShort(DateTime.fromMillisecondsSinceEpoch(pay.createdAtMs!)),
                  ].join(' · '),
                ),
            ],
          ],
        ]),
      ),
    );
  }
}
