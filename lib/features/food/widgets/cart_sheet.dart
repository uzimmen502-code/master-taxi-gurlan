import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/food_catalog.dart';
import '../../../utils/wallet_payment.dart';
import '../controllers/food_controller.dart';

/// Сават bottom-sheet'и — сават рўйхати + жами сумма + "Буюртма бериш" tugmasi.
class CartSheet extends StatelessWidget {
  const CartSheet({
    super.key,
    required this.controller,
    required this.onOrder,
    this.bonusBalanceStream,
  });

  final FoodController controller;
  final VoidCallback onOrder;

  /// Профил телефони бўйича — кошелёкдан тўлов таклифи.
  final Stream<int>? bonusBalanceStream;

  String _formatQty(double qty, String unit) {
    if (qty == qty.roundToDouble()) return '${qty.toInt()} $unit';
    return '$qty $unit';
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final cartEntries = controller.cart.entries.toList(growable: false);

    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        if (controller.cart.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.canPop(context)) Navigator.pop(context);
          });
          return const SizedBox.shrink();
        }
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              Row(children: [
                const Icon(Icons.shopping_basket, color: Colors.green),
                const SizedBox(width: 8),
                Text(loc.translate('cart'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${controller.cart.length}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500])),
              ]),
              const SizedBox(height: 12),
              const Divider(),
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.35),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: cartEntries.length,
                  itemBuilder: (_, index) {
                    final entry = cartEntries[index];
                    final product = FoodCatalog.byId(entry.key);
                    final qty = entry.value;
                    final itemTotal = (product.price * qty).round();
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(10)),
                        child: Center(
                            child: Text(product.emoji,
                                style: const TextStyle(fontSize: 24))),
                      ),
                      title: Text(product.name,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${formatPrice(itemTotal)} ${loc.translate("sum")}',
                          style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.w500)),
                      trailing:
                          Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          onPressed: () => controller.decrease(product.id),
                          icon: const Icon(Icons.remove_circle_outline,
                              color: Colors.red, size: 22),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 30, minHeight: 30),
                        ),
                        Text(_formatQty(qty, product.unit),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold)),
                        IconButton(
                          onPressed: () => controller.increase(product.id),
                          icon: const Icon(Icons.add_circle_outline,
                              color: Colors.green, size: 22),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 30, minHeight: 30),
                        ),
                      ]),
                    );
                  },
                ),
              ),
              const Divider(),
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${loc.translate("total")}:',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    Text(
                        '${formatPrice(controller.cartTotal)} ${loc.translate("sum")}',
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.green)),
                  ]),
              if (bonusBalanceStream != null) ...[
                const SizedBox(height: 10),
                StreamBuilder<int>(
                  stream: bonusBalanceStream,
                  builder: (_, snap) {
                    final bal = snap.data ?? 0;
                    final applied = WalletPayment.maxDebitFromWallet(
                      bal,
                      controller.cartTotal,
                    );
                    final rest =
                        (controller.cartTotal - applied).clamp(0, 999999999);
                    if (applied <= 0 && bal <= 0) {
                      return Text(
                        'Кошелёк: ${formatPrice(bal)} ${loc.translate("sum")} '
                        '(баланс бўлса, буюртмада ишлатилади)',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: Colors.grey.shade700,
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Кошелёкдан: ${formatPrice(applied)} ${loc.translate("sum")}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade800,
                          ),
                        ),
                        if (rest > 0)
                          Text(
                            'Қолдиқ тўлов (нақд/карта): ${formatPrice(rest)} ${loc.translate("sum")}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: onOrder,
                  icon: const Icon(Icons.delivery_dining),
                  label: Text(loc.translate('place_order'),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}
