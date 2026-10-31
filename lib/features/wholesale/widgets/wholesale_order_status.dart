import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../logistics/screens/logistics_home_screen.dart' show LogisticsStatusChip;
import '../models/wholesale_order.dart';

/// Ҳолат чипи — relay'нинг [LogisticsStatusChip] ранглари қайта ишлатилади
/// (иккинчи палитра ёзилмайди): буюртма ҳолати relay ранг сатрига мосланади.
class WholesaleOrderStatusChip extends StatelessWidget {
  const WholesaleOrderStatusChip({super.key, required this.status});

  final String status;

  static String colorWire(String status) => switch (status) {
        WholesaleOrderStatus.placed => 'pending',
        WholesaleOrderStatus.inDelivery || WholesaleOrderStatus.returning => 'in_transit',
        WholesaleOrderStatus.delivered => 'delivered',
        WholesaleOrderStatus.refused || WholesaleOrderStatus.paymentDispute => 'disputed',
        _ => 'other',
      };

  @override
  Widget build(BuildContext context) => LogisticsStatusChip(
        labelKey: WholesaleOrderStatus.l10nKey(status),
        status: colorWire(status),
      );
}

enum WholesaleStepState { done, current, upcoming, failed }

class WholesaleTimelineStep {
  const WholesaleTimelineStep(this.status, this.state);

  /// Ҳолат сатри — матн калити шундан ([WholesaleOrderStatus.l10nKey]).
  final String status;
  final WholesaleStepState state;
}

/// Ҳолат → кўрсатиладиган қадамлар (соф, тестланади). Асосий йўл:
/// қабул қилинди → етказилмоқда → етказилди; якуний тармоқлар: бекор,
/// рад → қайтарилмоқда → қайтарилди, тўлов низоси.
List<WholesaleTimelineStep> wholesaleTimelineSteps(String status) {
  const s = WholesaleOrderStatus.placed;
  const d = WholesaleOrderStatus.inDelivery;
  const ok = WholesaleOrderStatus.delivered;
  WholesaleTimelineStep st(String x, WholesaleStepState y) => WholesaleTimelineStep(x, y);
  const done = WholesaleStepState.done;
  const cur = WholesaleStepState.current;
  const up = WholesaleStepState.upcoming;
  const bad = WholesaleStepState.failed;
  return switch (status) {
    WholesaleOrderStatus.placed => [st(s, cur), st(d, up), st(ok, up)],
    WholesaleOrderStatus.inDelivery => [st(s, done), st(d, cur), st(ok, up)],
    WholesaleOrderStatus.delivered => [st(s, done), st(d, done), st(ok, done)],
    WholesaleOrderStatus.cancelled => [st(s, done), st(WholesaleOrderStatus.cancelled, bad)],
    WholesaleOrderStatus.refused => [st(s, done), st(d, done), st(WholesaleOrderStatus.refused, bad)],
    WholesaleOrderStatus.returning => [
        st(s, done),
        st(d, done),
        st(WholesaleOrderStatus.refused, bad),
        st(WholesaleOrderStatus.returning, cur),
        st(WholesaleOrderStatus.returned, up),
      ],
    WholesaleOrderStatus.returned => [
        st(s, done),
        st(d, done),
        st(WholesaleOrderStatus.refused, bad),
        st(WholesaleOrderStatus.returning, done),
        st(WholesaleOrderStatus.returned, done),
      ],
    WholesaleOrderStatus.paymentDispute => [
        st(s, done),
        st(d, done),
        st(WholesaleOrderStatus.paymentDispute, bad),
      ],
    _ => [st(status, cur)],
  };
}

class WholesaleOrderTimeline extends StatelessWidget {
  const WholesaleOrderTimeline({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final steps = wholesaleTimelineSteps(status);
    return Column(
      key: const ValueKey('wholesale-order-timeline'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, step) in steps.indexed)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Icon(
                    switch (step.state) {
                      WholesaleStepState.done => Icons.check_circle,
                      WholesaleStepState.current => Icons.radio_button_checked,
                      WholesaleStepState.upcoming => Icons.radio_button_unchecked,
                      WholesaleStepState.failed => Icons.cancel,
                    },
                    size: 18,
                    color: switch (step.state) {
                      WholesaleStepState.done => c.ok,
                      WholesaleStepState.current => c.brand,
                      WholesaleStepState.upcoming => c.ink3,
                      WholesaleStepState.failed => c.danger,
                    },
                  ),
                  if (i < steps.length - 1) Container(width: 2, height: 14, color: c.line),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr(WholesaleOrderStatus.l10nKey(step.status)),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: step.state == WholesaleStepState.current ? FontWeight.w700 : FontWeight.w500,
                    color: step.state == WholesaleStepState.upcoming ? c.ink3 : c.ink,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
