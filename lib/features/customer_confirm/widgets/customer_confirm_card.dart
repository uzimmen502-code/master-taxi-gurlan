import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/customer_confirm.dart';

/// Миқдорни кўрсатиш: бутун бўлса «5», каср бўлса «5.5» (ортиқча нол йўқ).
String customerConfirmQtyText(num qty) {
  if (qty == qty.roundToDouble()) return qty.toInt().toString();
  final s = qty.toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// Битта «тасдиқлаш кутилмоқда» карточкаси: сарлавҳа, изоҳ, (йиғишда) курьер
/// киритган рақамлар ва тасдиқлаш тугмаси. Ички терминлар (LEG, escrow …)
/// кўрсатилмайди (45-қоида).
class CustomerConfirmCard extends StatelessWidget {
  const CustomerConfirmCard({
    super.key,
    required this.item,
    required this.busy,
    required this.onConfirm,
  });

  final CustomerConfirmation item;
  final bool busy;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final title = item.title.isNotEmpty
        ? item.title
        : context.tr(customerConfirmModuleKey(item.module));
    final summary = item.summary.isNotEmpty
        ? item.summary
        : context.tr(customerConfirmHintKey(item.step));
    final d = item.details;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        border: Border.all(color: c.warn, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.hourglass_top_rounded, size: 20, color: c.warn),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(summary, style: TextStyle(fontSize: 12.5, color: c.ink2)),
          if (d != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (d.productLabel.isNotEmpty)
                    Text(
                      d.productLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                  if (d.qty != null)
                    Text(
                      context
                          .tr('customer_confirm_details_qty')
                          .replaceAll('{qty}', customerConfirmQtyText(d.qty!))
                          .replaceAll('{unit}', d.unit)
                          .trim(),
                      style: TextStyle(fontSize: 13, color: c.ink),
                    ),
                  if (d.amount != null)
                    Text(
                      context
                          .tr('customer_confirm_details_amount')
                          .replaceAll('{amount}', formatPrice(d.amount!)),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: c.brandText,
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy ? null : onConfirm,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 46),
                textStyle:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      context.tr(customerConfirmButtonKey(item.step)),
                      textAlign: TextAlign.center,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
