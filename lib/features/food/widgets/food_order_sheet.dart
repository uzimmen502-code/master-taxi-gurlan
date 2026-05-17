import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/wallet_payment.dart';
import '../../../widgets/wallet_cash_split_panel.dart';
import '../controllers/food_controller.dart';

/// Тайёр овқат буюртмаси — манзил/телефон + [WalletCashSplitPanel] (нон савати билан бир мантиқ).
class FoodOrderSheet extends StatefulWidget {
  const FoodOrderSheet({
    super.key,
    required this.controller,
    required this.loc,
    required this.parentContext,
    required this.addressCtrl,
    required this.phoneCtrl,
    required this.onAfterSubmit,
  });

  final FoodController controller;
  final AppLocalizations loc;
  final BuildContext parentContext;
  final TextEditingController addressCtrl;
  final TextEditingController phoneCtrl;

  /// `success` — `submitOrder` натижаси.
  final void Function(BuildContext rootContext, bool success) onAfterSubmit;

  @override
  State<FoodOrderSheet> createState() => _FoodOrderSheetState();
}

class _FoodOrderSheetState extends State<FoodOrderSheet> {
  int _walletBal = 0;
  late final TextEditingController _cashCtrl;

  @override
  void initState() {
    super.initState();
    _cashCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadWallet());
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadWallet() async {
    final prefs = await SharedPreferences.getInstance();
    final userPhone = prefs.getString('user_phone') ?? '';
    final uid = userPhone.replaceAll(RegExp(r'[^\d]'), '');
    var bal = 0;
    if (uid.length >= 9) {
      try {
        final u = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        bal = (u.data()?['bonusBalance'] as num?)?.toInt() ?? 0;
      } catch (_) {}
    }
    if (!mounted) return;
    final total = widget.controller.cartTotal;
    final eff = WalletPayment.maxDebitFromWallet(bal, total);
    setState(() {
      _walletBal = bal;
      _cashCtrl.text = '${(total - eff).clamp(0, 999999999)}';
    });
  }

  int _parseCash() {
    final raw = _cashCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(raw) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final loc = widget.loc;
    final total = c.cartTotal;

    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '📋 ${loc.translate("order")}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: widget.addressCtrl,
              decoration: InputDecoration(
                labelText: '📍 ${loc.translate("delivery_address")}',
                hintText: loc.translate('delivery_address_hint'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon:
                    const Icon(Icons.location_on, color: Colors.green),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: widget.phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: '📞 ${loc.translate("phone_number")}',
                hintText: loc.translate('enter_phone'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.phone, color: Colors.green),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '💰 ${loc.translate("total")}:',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${formatPrice(total)} ${loc.translate("sum")}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
            WalletCashSplitPanel(
              orderTotal: total,
              walletBalance: _walletBal,
              cashPaidCtrl: _cashCtrl,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: c.isSubmitting
                    ? null
                    : () async {
                        final address = widget.addressCtrl.text.trim();
                        final phone = widget.phoneCtrl.text.trim();
                        if (address.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content:
                                  Text(loc.translate('enter_address'))));
                          return;
                        }
                        if (phone.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(loc.translate('phone_number'))));
                          return;
                        }
                        final cash = _parseCash();
                        if (!WalletPayment.orderPayableWithAutoWallet(
                          walletBalance: _walletBal,
                          orderTotal: total,
                          cashPaid: cash,
                        )) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Тўлов етишмади. Нақд ва кошелёкни текширинг.',
                              ),
                            ),
                          );
                          return;
                        }
                        Navigator.of(context).pop();
                        final ok = await c.submitOrder(
                          address: address,
                          phone: phone,
                          cashPaid: cash,
                        );
                        if (!widget.parentContext.mounted) return;
                        widget.onAfterSubmit(widget.parentContext, ok);
                      },
                icon: c.isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  loc.translate('confirm'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}
