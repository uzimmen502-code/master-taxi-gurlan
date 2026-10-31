import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/delivery_failed.dart';

/// Курьер «етказиб бўлмади» сабабини танлайди. `pickup` — олиб кетиш (мижоз берадиган) вазифаси.
/// Бекор қилинса `null`.
Future<String?> showDeliveryFailedReasonSheet(BuildContext context, {bool pickup = false}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              ctx.tr(pickup ? 'delivery_failed_title_pickup' : 'restaurants_courier_fail_title'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          for (final r in deliveryFailedReasons)
            ListTile(
              key: ValueKey('df-reason-$r'),
              dense: true,
              leading: const Icon(Icons.radio_button_unchecked),
              title: Text(ctx.tr(deliveryFailedReasonKey(r))),
              onTap: () => Navigator.pop(ctx, r),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(ctx.tr('delivery_failed_note_confirm'), style: TextStyle(fontSize: 12, color: ctx.ava.ink2)),
          ),
        ],
      ),
    ),
  );
}

/// Курьер карточкасидаги «Етказиб бўлмади» тугмаси ва кутиш блоки (нон, гилам, сут, йиғиш).
///
/// [state.pending] — курьер аллақачон юборган: мижоз (муддатгача) ёки [decider]
/// (`seller` | `admin`) қарорини кутяпмиз; тугма кўринмайди. Акс ҳолда [canReport] бўлса — тугма.
/// Қоида ва ҳолат СЕРВЕРДА (`courierReportDeliveryFailed`).
class DeliveryFailedCourierControls extends StatefulWidget {
  const DeliveryFailedCourierControls({
    super.key,
    required this.state,
    required this.canReport,
    required this.onReport,
    this.decider = 'admin',
    this.pickup = false,
  });

  final DeliveryFailedState state;
  final bool canReport;
  final Future<void> Function(String reason) onReport;
  final String decider;
  final bool pickup;

  @override
  State<DeliveryFailedCourierControls> createState() => _DeliveryFailedCourierControlsState();
}

class _DeliveryFailedCourierControlsState extends State<DeliveryFailedCourierControls> {
  bool _busy = false;

  static String _hhmm(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _report() async {
    final reason = await showDeliveryFailedReasonSheet(context, pickup: widget.pickup);
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onReport(reason);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final s = widget.state;
    if (s.pending) {
      final d = s.deadline;
      final text = s.escalated
          ? context.tr(widget.decider == 'seller' ? 'delivery_failed_wait_seller' : 'delivery_failed_wait_admin')
          : d == null
              ? context.tr('restaurants_courier_failed_wait_customer')
              : context.tr('delivery_failed_wait_until').replaceAll('{time}', _hhmm(d));
      return Container(
        key: const ValueKey('df-waiting'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(10)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.hourglass_top_rounded, size: 18, color: c.warn),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.warn)),
                  if (s.reason.isNotEmpty)
                    Text(
                      '${context.tr('customer_confirm_fail_reason')}: ${context.tr(deliveryFailedReasonKey(s.reason))}',
                      style: TextStyle(fontSize: 12, color: c.ink2),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    if (!widget.canReport) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        key: const ValueKey('df-report'),
        onPressed: _busy ? null : _report,
        style: TextButton.styleFrom(foregroundColor: c.danger),
        child: Text(
          context.tr(widget.pickup ? 'delivery_failed_btn_pickup' : 'restaurants_courier_fail_btn'),
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}
