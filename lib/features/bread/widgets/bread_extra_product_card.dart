import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/bread_extra_product.dart';
import '../../../utils/app_theme.dart';

/// `extra_products` — қўшимча масаллиқлар / маҳсулотлар рўйхатидаги картаси.
class BreadExtraProductCard extends StatelessWidget {
  const BreadExtraProductCard({
    super.key,
    required this.product,
    required this.count,
    required this.onAdd,
    required this.onOpenCart,
  });

  final BreadExtraProduct product;
  final num count;
  final VoidCallback onAdd;
  final VoidCallback onOpenCart;

  static const _orange = Color(0xFFFF8F00);

  @override
  Widget build(BuildContext context) {
    final isSoldOut = product.isSoldOut;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
        ],
      ),
      child: Row(children: [
        _imageTile(product, isSoldOut),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(product.name,
                style: const TextStyle(
                    fontSize: AppText.bodyMedium,
                    fontWeight: FontWeight.bold)),
            Text(
              _cardSubtitle(product),
              style: TextStyle(
                  fontSize: AppText.labelSmall, color: Colors.grey.shade500),
            ),
            if (product.totalStock > 0)
              Text(
                product.remaining > 3
                    ? '📦 ${product.remaining} та қолди'
                    : product.remaining > 0
                        ? '⚠️ Охирги ${product.remaining} та!'
                        : '🔴 ТУГАДИ',
                style: TextStyle(
                  fontSize: AppText.labelTiny,
                  color: product.remaining > 3
                      ? Colors.green
                      : product.remaining > 0
                          ? Colors.orange
                          : Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ]),
        ),
        if (isSoldOut)
          const SizedBox.shrink()
        else if (count > 1e-9)
          GestureDetector(
            onTap: onOpenCart,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF2E7D32).withOpacity(0.3)),
              ),
              child: const Row(children: [
                Icon(Icons.check, size: 16, color: Color(0xFF2E7D32)),
                SizedBox(width: 4),
                Text('Қўшилди',
                    style: TextStyle(
                        fontSize: AppText.labelSmall,
                        color: Color(0xFF2E7D32),
                        fontWeight: FontWeight.bold)),
              ]),
            ),
          )
        else
          SizedBox(
            height: 32,
            child: ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Қўшиш',
                  style: TextStyle(fontSize: AppText.labelSmall)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
      ]),
    );
  }
}

Widget _imageTile(BreadExtraProduct product, bool isSoldOut) {
  final imageUrl = product.imageUrl.trim();
  final fallbackEmoji = isSoldOut ? '🚫' : product.displayEmoji;
  final bg = isSoldOut ? Colors.grey.shade200 : const Color(0xFFFFF3E0);

  return Container(
    width: 56,
    height: 56,
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    child: imageUrl.isEmpty
        ? Center(
            child: Text(fallbackEmoji, style: const TextStyle(fontSize: 24)),
          )
        : Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    fallbackEmoji,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
              if (isSoldOut)
                Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: const Center(
                    child: Text('🚫', style: TextStyle(fontSize: 22)),
                  ),
                ),
            ],
          ),
  );
}

String _cardSubtitle(BreadExtraProduct product) {
  final price = formatPrice(product.price);
  final cap = product.caption.trim();
  if (cap.isNotEmpty) return '$cap · $price сўм/${product.unitRu}';
  final q = product.qty;
  if (q != null && '$q'.trim().isNotEmpty) {
    return '${product.qty} ${product.unitRu} · $price сўм';
  }
  return '$price сўм/${product.unitRu}';
}
