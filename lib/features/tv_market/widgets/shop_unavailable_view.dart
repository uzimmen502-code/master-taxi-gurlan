import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';

/// Блокланган ёки мавжуд бўлмаган дўкон/маҳсулот: техник тафсилотсиз битта жумла (45-банд). Сабаб (блок, ўчирилган)
/// харидорга айтилмайди.
class ShopUnavailableView extends StatelessWidget {
  const ShopUnavailableView({super.key, required this.textKey});

  /// `shop_unavailable` | `product_unavailable`
  final String textKey;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined, size: 56, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            Text(
              context.tr(textKey),
              key: ValueKey('unavailable_$textKey'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
