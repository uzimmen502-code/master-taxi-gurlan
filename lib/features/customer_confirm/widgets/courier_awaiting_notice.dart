import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';

/// Курьер томонидаги «Мижоз тасдиғи кутилмоқда» ҳолати (D2/D7). Муваффақият
/// ҳам, хато ҳам эмас — кутиш: огоҳлантириш ранги ва қум соати. Курьер
/// экранлари (ресторан, гилам, сут, йиғиш) бир хил кўрсатади.
class CourierAwaitingNotice extends StatelessWidget {
  const CourierAwaitingNotice({super.key, this.showHint = true});

  /// Қисқа жойда (карточка ичида) изоҳни яшириш мумкин.
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.warnSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.hourglass_top_rounded, size: 18, color: c.warn),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('customer_confirm_waiting'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.warn,
                  ),
                ),
                if (showHint)
                  Text(
                    context.tr('customer_confirm_waiting_hint'),
                    style: TextStyle(fontSize: 12, color: c.ink2),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
