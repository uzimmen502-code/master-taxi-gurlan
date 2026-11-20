import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/order_model.dart';
import '../../../services/order_payment_service.dart';

/// Супермаркет буюртмасини мижоз бекор қилиши (эга 2026-11-20): ФАҚАТ `status == 'new'` (AVA ҳали
/// қабул қилмаган). Кейин — тугма йўқ, дўстона изоҳ. Қоида серверда ҳам текширилиши шарт (18-банд);
/// бу ер — фақат кўриниш ([OrderModel.canCustomerCancel]).
class SmOrderCancelBar extends StatefulWidget {
  const SmOrderCancelBar({super.key, required this.order, this.cancel});

  final OrderModel order;

  /// Тест учун; бўлмаса — мавжуд `customerCancelOrder` (ҳамён қайтими серверда).
  final Future<void> Function(String orderId)? cancel;

  @override
  State<SmOrderCancelBar> createState() => _SmOrderCancelBarState();
}

class _SmOrderCancelBarState extends State<SmOrderCancelBar> {
  bool _busy = false;
  bool _done = false;

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('order_cancel')),
        content: Text(ctx.tr('order_cancel_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          TextButton(
            key: const ValueKey('sm_cancel_confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('order_cancel')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final okText = context.tr('order_cancel_ok');
    final failText = context.tr('order_cancel_fail');
    try {
      await (widget.cancel ?? (id) => OrderPaymentService.customerCancelOrder(orderId: id))(widget.order.id);
      if (!mounted) return;
      setState(() => _done = true);
      messenger.showSnackBar(SnackBar(content: Text(okText)));
    } catch (e) {
      debugPrint('[Supermarket] SUPERMARKET_CANCEL_FAILED: $e');
      messenger.showSnackBar(SnackBar(content: Text(failText)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    if (_done) {
      return Text(context.tr('order_cancel_ok'), key: const ValueKey('sm_cancel_done'), style: TextStyle(fontSize: 15, color: c.ink2));
    }
    if (widget.order.canCustomerCancel) {
      return OutlinedButton(
        key: const ValueKey('sm_cancel_btn'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: _busy ? null : _cancel,
        child: Text(context.tr('sm_cancel_order'), style: const TextStyle(fontSize: 16)),
      );
    }
    final s = widget.order.status;
    if (s == 'delivered' || s == 'rejected' || s == 'cancelled') return const SizedBox.shrink();
    return Text(context.tr('sm_cancel_unavailable'),
        key: const ValueKey('sm_cancel_unavailable'), style: TextStyle(fontSize: 14, color: c.ink2));
  }
}
