import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/utils/formatters.dart';
import '../core/theme/app_theme.dart';
import '../utils/wallet_payment.dart';

/// Нақд + кошелёк: кошелёк **автоматик** `min(баланс, жами)` гача; слайдер йўқ.
/// Барча модуллар (нон, овқат) учун умумий UI.
class WalletCashSplitPanel extends StatefulWidget {
  const WalletCashSplitPanel({
    super.key,
    required this.orderTotal,
    required this.walletBalance,
    required this.cashPaidCtrl,
  });

  final int orderTotal;
  final int walletBalance;
  final TextEditingController cashPaidCtrl;

  @override
  State<WalletCashSplitPanel> createState() => _WalletCashSplitPanelState();
}

class _WalletCashSplitPanelState extends State<WalletCashSplitPanel> {
  bool _cashDirty = false;

  @override
  Widget build(BuildContext context) {
    final maxUse =
        WalletPayment.maxDebitFromWallet(widget.walletBalance, widget.orderTotal);
    final eff = maxUse;

    final cashParsed = int.tryParse(
          widget.cashPaidCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ??
        0;
    final cashPaid = cashParsed < 0 ? 0 : cashParsed;
    final cashDue = (widget.orderTotal - eff).clamp(0, 999999999);
    final change = (cashPaid - cashDue).clamp(0, 999999999);
    final postPayment =
        (widget.walletBalance - eff + change).clamp(0, 999999999);

    if (!_cashDirty && widget.orderTotal > 0) {
      final want = '${(widget.orderTotal - eff).clamp(0, 999999999)}';
      if (widget.cashPaidCtrl.text != want) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _cashDirty) return;
          if (widget.cashPaidCtrl.text != want) {
            widget.cashPaidCtrl.text = want;
            setState(() {});
          }
        });
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '💳 Кошелёк',
              style: TextStyle(
                fontSize: AppText.bodyMedium,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Жами: ${formatMoney(widget.orderTotal)} · мавжуд: ${formatMoney(widget.walletBalance)}',
              style: TextStyle(
                fontSize: AppText.labelSmall,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: widget.cashPaidCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) {
                setState(() => _cashDirty = true);
              },
              decoration: InputDecoration(
                labelText: 'Мижоз берган нақд (сўм)',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Ортиқча қайтим кошелёкка ёзилади.',
              style: TextStyle(
                fontSize: AppText.labelTiny,
                color: Colors.grey.shade600,
              ),
            ),
            if (eff > 0 || change > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Тўловдан кейин кошелёкда: ${formatMoney(postPayment)}',
                style: TextStyle(
                  fontSize: AppText.labelTiny,
                  color: Colors.blue.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
