import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../models/wholesale_order.dart';
import '../repositories/wholesale_orders_repository.dart';
import '../utils/wholesale_order_errors.dart';

/// Админ «Етказилмади — қарор» бўлимидаги УЛГУРЖИ қисми (эга, 2026-11-01). Сервер — demand codebase
/// (`listWholesaleDeliveryFailedPending`, `resolveWholesaleDeliveryFailed` — admin_audit, биринчи қарор
/// ютади). Сотувчи ҳам шу буюртма саҳифасида ҳал қила олади; бу ерда — захира (админ). Телефон кўринмайди.
class WholesaleDeliveryFailedAdminList extends StatefulWidget {
  const WholesaleDeliveryFailedAdminList({super.key, this.repository, this.now});

  final WholesaleOrdersRepository? repository;

  /// Тест учун соат.
  final DateTime Function()? now;

  @override
  State<WholesaleDeliveryFailedAdminList> createState() => _WholesaleDeliveryFailedAdminListState();
}

class _WholesaleDeliveryFailedAdminListState extends State<WholesaleDeliveryFailedAdminList> {
  late final WholesaleOrdersRepository _repo = widget.repository ?? WholesaleOrdersRepository();
  List<WholesaleDeliveryFailedItem> _items = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repo.listDeliveryFailedPending();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = wholesaleOrderErrorText(context, e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(WholesaleDeliveryFailedItem it, {required bool failed}) async {
    if (_busy.contains(it.orderId)) return;
    if (failed) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('delivery_failed_decide_failed_title')),
          content: Text(ctx.tr('wholesale_df_buyer_confirm_dialog')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
            FilledButton(
              key: const ValueKey('wdf-confirm-failed'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.tr('delivery_failed_btn_failed')),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _busy.add(it.orderId));
    String? err;
    try {
      await _repo.resolveDeliveryFailed(orderId: it.orderId, failed: failed);
    } catch (e) {
      if (mounted) err = wholesaleOrderErrorText(context, e);
    }
    if (!mounted) return;
    setState(() => _busy.remove(it.orderId));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(err ?? context.tr(failed ? 'wholesale_df_done_failed' : 'wholesale_df_decided_deliver')),
      backgroundColor: err == null ? null : Colors.red.shade700,
    ));
    await _load();
  }

  static String _hhmm(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final body = <Widget>[];
    if (_error != null) {
      body.add(Text(_error!, style: TextStyle(color: c.danger)));
    } else if (_loading && _items.isEmpty) {
      body.add(const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())));
    } else if (_items.isEmpty) {
      body.add(Text(context.tr('delivery_failed_decide_empty'), style: TextStyle(color: c.ink2)));
    } else {
      final now = (widget.now ?? DateTime.now)();
      for (final it in _items) {
        final canDecide = it.canDecide || (it.escalateAt != null && !now.isBefore(it.escalateAt!));
        final busy = _busy.contains(it.orderId);
        body.add(Container(
          key: ValueKey('wdf-item-${it.orderId}'),
          margin: const EdgeInsets.only(top: 8, right: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [it.productTitle, if (it.qty != null) '× ${it.qty}'].where((s) => s.isNotEmpty).join(' '),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink),
              ),
              Text(
                [
                  it.orderId,
                  if (it.buyerTail.isNotEmpty) '${context.tr('wholesale_df_buyer_label')} ***${it.buyerTail}',
                  if (it.sellerTail.isNotEmpty) '${context.tr('wholesale_seller_label')} ***${it.sellerTail}',
                ].join(' · '),
                style: TextStyle(fontSize: 12, color: c.ink2),
              ),
              if (it.total != null)
                Text('${formatPrice(it.total!)} ${context.tr('currency_sum')}', style: TextStyle(fontSize: 12, color: c.ink2)),
              const SizedBox(height: 4),
              Text(
                '${context.tr('customer_confirm_fail_reason')}: ${context.tr(wholesaleDeliveryFailedReasonKey(it.reasonCode))}',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.ink),
              ),
              Text(
                canDecide
                    ? context.tr('wholesale_df_stage_awaiting_decision')
                    : it.escalateAt == null
                        ? context.tr('wholesale_df_stage_awaiting_buyer')
                        : context.tr('delivery_failed_decide_wait_until').replaceAll('{time}', _hhmm(it.escalateAt!)),
                style: TextStyle(fontSize: 12, color: c.warn),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: ValueKey('wdf-deliver-${it.orderId}'),
                      onPressed: busy || !canDecide ? null : () => _decide(it, failed: false),
                      child: Text(context.tr('wholesale_df_btn_deliver'), textAlign: TextAlign.center),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: ValueKey('wdf-failed-${it.orderId}'),
                      onPressed: busy || !canDecide ? null : () => _decide(it, failed: true),
                      style: FilledButton.styleFrom(backgroundColor: c.danger),
                      child: busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(context.tr('delivery_failed_btn_failed'), textAlign: TextAlign.center),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ));
      }
    }
    return Container(
      key: const ValueKey('wholesale-df-admin-list'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        border: Border.all(color: c.warn, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping_outlined, size: 18, color: c.warn),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context.tr('wholesale_df_admin_title'),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink),
                ),
              ),
              IconButton(
                tooltip: context.tr('customer_confirm_refresh'),
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
          ...body,
        ],
      ),
    );
  }
}
