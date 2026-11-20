import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../domain/sm_order_progress.dart';

/// Супермаркет буюртмаси: 5 босқич (мавжуд «Хабарлар» буюртма тафсилоти ичида кўрсатилади).
/// Номаълум статус — ҳеч нарса (crash йўқ).
class SmOrderProgressView extends StatelessWidget {
  const SmOrderProgressView({super.key, required this.status, this.fulfillmentStatus = ''});

  final String status;
  final String fulfillmentStatus;

  @override
  Widget build(BuildContext context) {
    final step = smOrderStep(status, fulfillmentStatus: fulfillmentStatus);
    if (step == null) return const SizedBox.shrink();
    final c = context.ava;
    return Container(
      key: const ValueKey('sm_order_progress'),
      padding: const EdgeInsets.all(12),
      decoration:
          BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in SmOrderStep.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    s.index < step.index
                        ? Icons.check_circle_rounded
                        : (s == step ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
                    key: ValueKey('sm_step_${s.name}_${s.index <= step.index ? 'on' : 'off'}'),
                    color: s.index <= step.index ? c.ok : c.ink3,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr(kSmOrderStepKeys[s]!),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: s == step ? FontWeight.w700 : FontWeight.w400,
                        color: s.index <= step.index ? c.ink : c.ink2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
