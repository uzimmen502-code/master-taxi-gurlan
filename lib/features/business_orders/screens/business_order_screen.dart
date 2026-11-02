// Харидор: «Менинг бизнесим» буюртмаси кузатуви — ҳолат вақт чизиғи, қаторлар, ҳисоб, тўлов изоҳи ва
// (фақат сотувчи қабул қилгунча) «Бекор қилиш». Ҳужжат жонли (`orders/{id}`, rules: харидорнинг ўзи).
// Мижоз тасдиғи («Олдим» / «етказилмади») — мавжуд умумий [CustomerConfirmScreen] (`module: business`).

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../customer_confirm/screens/customer_confirm_screen.dart';
import '../data/business_orders_repository.dart';
import '../domain/business_order.dart';
import '../widgets/business_order_widgets.dart';

class BusinessOrderScreen extends StatefulWidget {
  const BusinessOrderScreen({super.key, required this.orderId, this.repository, @visibleForTesting this.openConfirm});

  final String orderId;
  final BusinessOrdersRepository? repository;

  /// Тест учун: «Олдим» экрани ўрнига.
  final Future<void> Function(BuildContext context)? openConfirm;

  @override
  State<BusinessOrderScreen> createState() => _BusinessOrderScreenState();
}

class _BusinessOrderScreenState extends State<BusinessOrderScreen> {
  late final BusinessOrdersRepository _repo = widget.repository ?? BusinessOrdersRepository();
  late final Stream<BusinessOrder?> _stream = _repo.watchOrder(widget.orderId);
  bool _cancelling = false;

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('biz_order_cancel')),
        content: Text(ctx.tr('biz_order_cancel_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(
            key: const ValueKey('biz_order_cancel_yes'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('biz_order_cancel')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cancelling = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.cancel(widget.orderId);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(context.tr('biz_order_cancel_ok'))));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(bizOrderErrorText(context, e)), backgroundColor: context.ava.danger));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Future<void> _openConfirm() async {
    final custom = widget.openConfirm;
    if (custom != null) return custom(context);
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const CustomerConfirmScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.tr('biz_order_title'))),
      body: StreamBuilder<BusinessOrder?>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(bizOrderErrorText(context, snap.error!), textAlign: TextAlign.center),
              ),
            );
          }
          if (!snap.hasData && snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final o = snap.data;
          if (o == null) {
            return Center(child: Text(context.tr('err_not_found'), textAlign: TextAlign.center));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(AvaSpace.screen, 12, AvaSpace.screen, 24),
            children: [
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            o.businessName.isEmpty ? context.tr('biz_order_module') : o.businessName,
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.ink),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(child: BusinessOrderStatusPill(status: o.status)),
                      ],
                    ),
                    if (o.createdAt != null)
                      Text(bizOrderDateLabel(o.createdAt!), style: TextStyle(fontSize: 12, color: c.ink2)),
                    if (o.status == BusinessOrderStatus.placed && o.acceptDeadlineAt != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        context.tr('biz_order_accept_by').replaceAll('{time}', bizOrderTimeLabel(o.acceptDeadlineAt!)),
                        key: const ValueKey('biz_order_accept_by'),
                        style: TextStyle(fontSize: 13, color: c.warn, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _Card(child: BusinessOrderTimeline(order: o)),
              if (o.awaitingStep == 'received' || o.deliveryFailedPending) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const ValueKey('biz_order_open_confirm'),
                  onPressed: _openConfirm,
                  icon: const Icon(Icons.task_alt_rounded),
                  label: Text(context.tr(o.deliveryFailedPending ? 'biz_order_confirm_failed_cta' : 'biz_order_confirm_received_cta')),
                  style: FilledButton.styleFrom(
                    backgroundColor: c.brand,
                    foregroundColor: c.brandInk,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(context.tr('biz_order_items_title'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink)),
                    const SizedBox(height: 6),
                    BusinessOrderSummary(order: o),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              BizOrderNotice(
                icon: Icons.payments_outlined,
                text: context.tr('biz_order_goods_cash_explain'),
                color: c.brandText,
                background: c.brandSoft,
              ),
              if (o.address.isNotEmpty) ...[
                const SizedBox(height: 10),
                _Card(
                  child: Row(
                    children: [
                      Icon(Icons.place_outlined, size: 18, color: c.ink2),
                      const SizedBox(width: 8),
                      Expanded(child: Text(o.address, style: TextStyle(fontSize: 13, color: c.ink))),
                    ],
                  ),
                ),
              ],
              if (o.canCustomerCancel) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  key: const ValueKey('biz_order_cancel'),
                  onPressed: _cancelling ? null : _cancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.danger,
                    side: BorderSide(color: c.danger),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: _cancelling
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(context.tr('biz_order_cancel')),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        border: Border.all(color: c.line),
      ),
      child: child,
    );
  }
}
