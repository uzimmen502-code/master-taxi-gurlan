import 'package:flutter/material.dart';
import '../../core/l10n/l10n_extension.dart';
import '../../core/theme/app_theme.dart';

import '../../core/utils/order_receipt_format.dart';
import '../../models/order_model.dart';

/// Буюртма чеки — маҳсулотлар, сумма, манзил.
class OrderReceiptView extends StatelessWidget {
  const OrderReceiptView({
    super.key,
    required this.order,
    this.title,
  });

  final OrderModel order;
  final String? title;

  static const _border = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final lines = OrderReceiptFormat.lines(order, tr: context.trMsg);
    final module = context.tr(order.typeLabelKey);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long, color: AppColors.primaryText, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title ??
                      context.trMsg('misc_receipt_title',
                          params: {'module': module}),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          ...lines.map((l) => _receiptLine(context, l)),
        ],
      ),
    );
  }

  static bool _isTotalLine(BuildContext context, String line) =>
      OrderReceiptFormat.isTotalLine(line, tr: context.trMsg);

  Widget _receiptLine(BuildContext context, String line) {
    if (!_isTotalLine(context, line)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          line,
          style: const TextStyle(fontSize: 13, height: 1.35),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: _border.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _border.withValues(alpha: 0.45)),
        ),
        child: Text(
          line,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            height: 1.25,
            color: Color(0xFFBF360C),
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
