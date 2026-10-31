import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/delivery_failed.dart';
import '../../../services/delivery_failed_service.dart';

/// «Етказилмади» — қарор кутаётганлар (эга қарорлари 2026-10-31): мижоз муддатда жавоб бермаса
/// нон/бозорда сотувчи (`seller`), бошқа турларда админ ҳал қилади. Рўйхат ва рухсат — серверда
/// (`listDeliveryFailedPending`, `resolveDeliveryFailed`); бу ерда фақат кўрсатиш ва 2 та тугма.
///
/// [hideWhenEmpty] — сотувчи кассасида: кутаётган бўлмаса (ёки рўйхат юкланмаса) ҳеч нарса кўринмайди.
class DeliveryFailedDecisionList extends StatefulWidget {
  const DeliveryFailedDecisionList({
    super.key,
    this.service,
    this.hideWhenEmpty = false,
    this.now,
  });

  final DeliveryFailedService? service;
  final bool hideWhenEmpty;

  /// Тест учун соат.
  final DateTime Function()? now;

  @override
  State<DeliveryFailedDecisionList> createState() => _DeliveryFailedDecisionListState();
}

class _DeliveryFailedDecisionListState extends State<DeliveryFailedDecisionList> {
  late final DeliveryFailedService _service = widget.service ?? DeliveryFailedService();
  List<DeliveryFailedPendingItem> _items = const [];
  bool _loading = true;
  String? _errorKey;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      final items = await _service.listPending();
      if (!mounted) return;
      setState(() => _items = items);
    } on DeliveryFailedException catch (e) {
      if (mounted) setState(() => _errorKey = deliveryFailedErrorKey(e.reason));
    } catch (_) {
      if (mounted) setState(() => _errorKey = 'delivery_failed_err_generic');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(DeliveryFailedPendingItem it, {required bool failed}) async {
    if (_busy.contains(it.key)) return;
    if (failed) {
      // Пул қайтиши / навбатга қайтиш — қайтариб бўлмайдиган амал: тасдиқ сўралади.
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('delivery_failed_decide_failed_title')),
          content: Text(ctx.tr(it.module == DeliveryFailedModule.order
              ? 'delivery_failed_decide_failed_body_order'
              : 'delivery_failed_decide_failed_body_task')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
            FilledButton(
              key: const ValueKey('df-confirm-failed'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.tr('delivery_failed_btn_failed')),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _busy.add(it.key));
    String? errKey;
    try {
      await _service.resolve(module: it.module, id: it.id, failed: failed);
    } on DeliveryFailedException catch (e) {
      errKey = deliveryFailedErrorKey(e.reason);
    } catch (_) {
      errKey = 'delivery_failed_err_generic';
    }
    if (!mounted) return;
    setState(() => _busy.remove(it.key));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(context.tr(errKey ?? (failed ? 'delivery_failed_decided_failed' : 'delivery_failed_decided_continue'))),
      backgroundColor: errKey == null ? null : Colors.red.shade700,
    ));
    await _load();
  }

  static String _hhmm(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hideWhenEmpty && (_items.isEmpty || _errorKey != null)) {
      return const SizedBox.shrink();
    }
    final c = context.ava;
    final header = Row(
      children: [
        Icon(Icons.report_problem_outlined, size: 18, color: c.warn),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            context.tr('delivery_failed_decide_title'),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink),
          ),
        ),
        IconButton(
          tooltip: context.tr('customer_confirm_refresh'),
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh, size: 20),
        ),
      ],
    );
    final body = <Widget>[];
    if (_errorKey != null) {
      body.add(Text(context.tr(_errorKey!), style: TextStyle(color: c.danger)));
    } else if (_loading && _items.isEmpty) {
      body.add(const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())));
    } else if (_items.isEmpty) {
      body.add(Text(context.tr('delivery_failed_decide_empty'), style: TextStyle(color: c.ink2)));
    } else {
      final now = (widget.now ?? DateTime.now)();
      for (final it in _items) {
        body.add(_ItemCard(
          key: ValueKey('df-item-${it.key}'),
          item: it,
          busy: _busy.contains(it.key),
          canDecide: it.canDecide || (it.escalateAt != null && !now.isBefore(it.escalateAt!)),
          hhmm: _hhmm,
          onFailed: () => _decide(it, failed: true),
          onContinue: () => _decide(it, failed: false),
        ));
      }
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        border: Border.all(color: c.warn, width: 1.2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [header, ...body]),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    super.key,
    required this.item,
    required this.busy,
    required this.canDecide,
    required this.hhmm,
    required this.onFailed,
    required this.onContinue,
  });

  final DeliveryFailedPendingItem item;
  final bool busy;
  final bool canDecide;
  final String Function(DateTime) hhmm;
  final VoidCallback onFailed;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final who = [
      if (item.customerName.isNotEmpty) item.customerName,
      if (item.customerPhoneTail.isNotEmpty) '***${item.customerPhoneTail}',
    ].join(' · ');
    final wait = item.escalateAt;
    return Container(
      margin: const EdgeInsets.only(top: 8, right: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr(deliveryFailedModuleKey(item.module, item.leg)),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
          if (who.isNotEmpty) Text(who, style: TextStyle(fontSize: 12.5, color: c.ink)),
          if (item.address.isNotEmpty)
            Text(item.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.ink2)),
          if (item.total != null)
            Text('${formatPrice(item.total!)} ${context.tr('currency_sum')}', style: TextStyle(fontSize: 12, color: c.ink2)),
          const SizedBox(height: 4),
          Text(
            '${context.tr('customer_confirm_fail_reason')}: ${context.tr(deliveryFailedReasonKey(item.failReason))}',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.ink),
          ),
          if (!canDecide)
            Text(
              wait == null
                  ? context.tr('restaurants_courier_failed_wait_customer')
                  : context.tr('delivery_failed_decide_wait_until').replaceAll('{time}', hhmm(wait)),
              style: TextStyle(fontSize: 12, color: c.warn),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: ValueKey('df-continue-${item.key}'),
                  onPressed: busy || !canDecide ? null : onContinue,
                  child: Text(context.tr('delivery_failed_btn_continue'), textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: ValueKey('df-failed-${item.key}'),
                  onPressed: busy || !canDecide ? null : onFailed,
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
    );
  }
}
