import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';

/// Буюртма беришда: кошелёк баланси + жами сумма. Тўлов майдони йўқ.
class OrderCheckoutWalletBanner extends StatelessWidget {
  const OrderCheckoutWalletBanner({
    super.key,
    required this.orderTotal,
    required this.walletBalance,
  });

  final int orderTotal;
  final int walletBalance;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  loc
                      .translate('bread_wallet_balance')
                      .replaceAll('{balance}', formatPrice(walletBalance)),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            loc
                .translate('bread_wallet_order_total')
                .replaceAll('{total}', formatPrice(orderTotal)),
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            loc.translate('bread_wallet_payment_note'),
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
