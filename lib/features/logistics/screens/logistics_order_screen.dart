// AVA LOGISTICS — буюртма тафсилоти (мижоз).
//
// Ҳар жўнатма учун: ҳолат, нарх, «Ҳамёндан тўлаш» (эскроу, D-11,
// `fundShipmentEscrow` — default codebase), «Кодлар ва QR»
// (`getShipmentSecrets`), кузатув тасмаси (`custody_events`, ўзгармас
// тарих). Бекор қилиш — фақат custody бошланмагунча (сервер текширади).

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/wallet_topup_ui.dart';
import '../data/logistics_repository.dart';
import '../domain/logistics_models.dart';
import '../ui/logistics_text.dart';
import '../widgets/shipment_codes_sheet.dart';
import 'logistics_home_screen.dart' show LogisticsStatusChip;

class LogisticsOrderScreen extends StatefulWidget {
  const LogisticsOrderScreen({
    super.key,
    required this.orderId,
    required this.ownerId,
    this.repository,
  });

  final String orderId;
  final String ownerId;
  final LogisticsRepository? repository;

  @override
  State<LogisticsOrderScreen> createState() => _LogisticsOrderScreenState();
}

class _LogisticsOrderScreenState extends State<LogisticsOrderScreen> {
  late final LogisticsRepository _repo = widget.repository ?? LogisticsRepository();
  String? _busyShipmentId;
  bool _cancelling = false;
  String? _error;
  bool _errorTopUp = false;

  /// Сервер қайтарган етишмаётган сумма (ҳамён экранида таклиф бўлади).
  int? _shortfall;

  Future<void> _pay(Shipment s) => _withShipment(s, () async {
        await _repo.fundEscrow(s.id);
        _snack('logistics_pay_done');
      });

  Future<void> _codes(Shipment s) => _withShipment(s, () async {
        final secrets = await _repo.secrets(s.id);
        if (!mounted) return;
        await showShipmentCodesSheet(context, secrets);
      });

  Future<void> _withShipment(Shipment s, Future<void> Function() body) async {
    if (_busyShipmentId != null) return;
    setState(() {
      _busyShipmentId = s.id;
      _error = null;
    });
    try {
      await body();
    } catch (e) {
      if (mounted) _showError(e);
    } finally {
      if (mounted) setState(() => _busyShipmentId = null);
    }
  }

  /// Эскроуда ҳамён етмаса сервер `reason: insufficient` + `shortfall`
  /// қайтаради: аввал умумий хато чиқарди, энди етишмаган сумма ва
  /// «Ҳамённи тўлдириш» тугмаси кўрсатилади.
  void _showError(Object e) {
    if (e is LogisticsException && e.reason == 'insufficient') {
      final short = (e.details?['shortfall'] as num?)?.toInt();
      setState(() {
        _errorTopUp = true;
        _shortfall = short != null && short > 0 ? short : null;
        _error = short != null && short > 0
            ? context.trMsg('logistics_err_insufficient', params: {'amount': formatMoney(short)})
            : context.tr('assistant_insufficient');
      });
      return;
    }
    setState(() {
      _errorTopUp = false;
      _error = logisticsErrorText(context, e);
    });
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('logistics_cancel_order')),
        content: Text(ctx.tr('logistics_cancel_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(ctx.tr('consent_no'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(ctx.tr('logistics_confirm'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _cancelling = true;
      _error = null;
    });
    try {
      await _repo.cancelOrder(widget.orderId);
      _snack('logistics_cancelled_done');
    } catch (e) {
      if (mounted) _showError(e);
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  void _snack(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(key))));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface,
        elevation: 0,
        title: Text(
          context.tr('logistics_parcel'),
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink),
        ),
      ),
      body: StreamBuilder<LogisticsOrder?>(
        stream: _repo.watchOrder(widget.orderId),
        builder: (context, orderSnap) {
          final order = orderSnap.data;
          return StreamBuilder<List<Shipment>>(
            stream: _repo.watchShipmentsOfOrder(widget.orderId, ownerId: widget.ownerId),
            builder: (context, shipSnap) {
              if (order == null || shipSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final shipments = shipSnap.data ?? const <Shipment>[];
              final cancellable = shipments.isNotEmpty && shipments.every((s) => s.status.isCancellable);
              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _orderHeader(context, order),
                  const SizedBox(height: 12),
                  if (_error != null) ...[
                    WalletInlineError(
                      text: _error!,
                      onTopUp: _errorTopUp
                          ? () => openWalletTopUp(Navigator.of(context), suggestedAmount: _shortfall)
                          : null,
                    ),
                    const SizedBox(height: 2),
                  ],
                  for (final s in shipments) ...[
                    _ShipmentCard(
                      shipment: s,
                      ownerId: widget.ownerId,
                      repository: _repo,
                      busy: _busyShipmentId == s.id,
                      onPay: () => _pay(s),
                      onCodes: () => _codes(s),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (cancellable) ...[
                    const SizedBox(height: 6),
                    OutlinedButton(
                      onPressed: _cancelling ? null : _cancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.danger,
                        side: BorderSide(color: c.line),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(context.tr('logistics_cancel_order')),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _orderHeader(BuildContext context, LogisticsOrder order) {
    final c = context.ava;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${context.tr('logistics_price_total')}: '
                  '${logisticsMoney(order.customerPriceTotal)} ${context.tr('sum')}',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink),
                ),
              ),
              LogisticsStatusChip(labelKey: order.l10nStatusKey, status: order.status),
            ],
          ),
          const SizedBox(height: 8),
          _row(context, Icons.outbox_outlined, context.tr('logistics_from'), order.origin?.addressText ?? ''),
          _row(context, Icons.move_to_inbox_outlined, context.tr('logistics_to'), order.destination?.addressText ?? ''),
          _row(context, Icons.person_outline, context.tr('logistics_recipient'),
              '${order.recipientName} · +${order.recipientPhone}'),
          if (order.note.isNotEmpty) _row(context, Icons.notes_outlined, context.tr('logistics_note'), order.note),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    final c = context.ava;
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: c.ink3),
          const SizedBox(width: 6),
          Text('$label: ', style: TextStyle(fontSize: 12, color: c.ink3)),
          Expanded(child: Text(value, style: TextStyle(fontSize: 12, color: c.ink))),
        ],
      ),
    );
  }
}

class _ShipmentCard extends StatelessWidget {
  const _ShipmentCard({
    required this.shipment,
    required this.ownerId,
    required this.repository,
    required this.busy,
    required this.onPay,
    required this.onCodes,
  });

  final Shipment shipment;
  final String ownerId;
  final LogisticsRepository repository;
  final bool busy;
  final VoidCallback onPay;
  final VoidCallback onCodes;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final s = shipment;
    final p = s.parcel;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_post_office_rounded, size: 16, color: c.brand),
              const SizedBox(width: 6),
              Expanded(
                child: SelectableText(
                  s.trackingNumber,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink),
                ),
              ),
              LogisticsStatusChip(labelKey: s.status.l10nKey, status: s.status.wire),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${logisticsWeightLabel(p.actualWeightG)} · ${p.lengthCm}×${p.widthCm}×${p.heightCm} см'
            '${p.description.isNotEmpty ? ' · ${p.description}' : ''}',
            style: TextStyle(fontSize: 12, color: c.ink2),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              LogisticsStatusChip(labelKey: s.paymentStatus.l10nKey, status: s.paymentStatus.wire),
              const Spacer(),
              Text(
                '${logisticsMoney(s.priceSnapshot.customerPrice)} ${context.tr('sum')}',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: c.brand),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (s.needsPayment)
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : onPay,
                    style: FilledButton.styleFrom(
                      backgroundColor: c.brand,
                      foregroundColor: c.brandInk,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(context.tr('logistics_pay_wallet'), style: const TextStyle(fontSize: 12)),
                  ),
                ),
              if (s.needsPayment && s.secretsAvailable) const SizedBox(width: 8),
              if (s.secretsAvailable && !s.needsPayment)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onCodes,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.brand,
                      side: BorderSide(color: c.line),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.qr_code_2, size: 16),
                    label: Text(context.tr('logistics_codes'), style: const TextStyle(fontSize: 12)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              title: Text(
                context.tr('logistics_timeline'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.ink2),
              ),
              children: [
                StreamBuilder<List<CustodyEvent>>(
                  stream: repository.watchCustody(s.id, ownerId: ownerId),
                  builder: (context, snap) {
                    final events = snap.data ?? const <CustodyEvent>[];
                    if (events.isEmpty) {
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          context.tr('logistics_timeline_empty'),
                          style: TextStyle(fontSize: 11, color: c.ink3),
                        ),
                      );
                    }
                    return Column(
                      children: [for (final e in events) _TimelineRow(event: e)],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.event});

  final CustodyEvent event;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final damaged = event.conditionFlags.any((f) => f != ConditionFlags.intact);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            event.isDelivery ? Icons.check_circle : Icons.radio_button_checked,
            size: 14,
            color: event.isDelivery ? c.ok : c.brand,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr(event.l10nKey), style: TextStyle(fontSize: 12, color: c.ink)),
                Text(
                  logisticsDateLabel(event.timestamp),
                  style: TextStyle(fontSize: 11, color: c.ink3),
                ),
                if (damaged)
                  Text(
                    event.conditionFlags.map((f) => context.tr(ConditionFlags.l10nKey(f))).join(', '),
                    style: TextStyle(fontSize: 11, color: c.warn),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
