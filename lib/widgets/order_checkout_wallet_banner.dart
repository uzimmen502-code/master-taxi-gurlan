import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';

/// Буюртма checkout: ҳамён **opt-in** (default off).
/// Мижоз switch ёндирмаса ҳамён тегилмайди; сервер ҳам `useWallet === true` талаб қилади.
class OrderCheckoutWalletBanner extends StatelessWidget {
  const OrderCheckoutWalletBanner({
    super.key,
    required this.orderTotal,
    required this.walletBalance,
    this.useWallet = false,
    this.onUseWalletChanged,
    this.walletApply = 0,
    this.cashDue,
  });

  final int orderTotal;
  final int walletBalance;
  /// Мижоз ҳамёндан тўлашни танладими (default false).
  final bool useWallet;
  final ValueChanged<bool>? onUseWalletChanged;
  final int walletApply;
  final int? cashDue;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final canToggle = onUseWalletChanged != null && walletBalance > 0;
    final apply = useWallet ? walletApply.clamp(0, orderTotal) : 0;
    final due = cashDue ?? (orderTotal - apply);
    final remainingAfter = (walletBalance - apply).clamp(0, walletBalance);
    final willZero = useWallet && apply > 0 && remainingAfter == 0;

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
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  loc.translate('wallet_pay_toggle'),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Switch.adaptive(
                value: useWallet && walletBalance > 0,
                onChanged: canToggle ? onUseWalletChanged : null,
              ),
            ],
          ),
          const SizedBox(height: 4),
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
          if (!useWallet || apply <= 0) ...[
            const SizedBox(height: 4),
            Text(
              loc.translate('wallet_not_used'),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              loc
                  .translate('bread_wallet_cash_due')
                  .replaceAll('{amount}', formatPrice(orderTotal)),
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else ...[
            const SizedBox(height: 4),
            Text(
              loc
                  .translate('bread_wallet_will_apply')
                  .replaceAll('{amount}', formatPrice(apply)),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              loc
                  .translate('bread_wallet_cash_due')
                  .replaceAll('{amount}', formatPrice(due < 0 ? 0 : due)),
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (willZero) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.45)),
                ),
                child: Text(
                  loc.translate('wallet_will_zero'),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              loc.translate('bread_wallet_payment_note_applied'),
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
