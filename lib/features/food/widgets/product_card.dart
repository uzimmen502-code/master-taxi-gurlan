import 'package:flutter/material.dart';

import '../../../core/utils/data_url_image.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/food_product.dart';
import '../controllers/food_controller.dart';

/// Овqat маҳсулоти карточкаси — emoji, ном, изоҳ, нарх ва "Қўшиш" / Tanlandi.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.controller,
    this.grid = false,
  });

  final FoodProduct product;
  final FoodController controller;
  final bool grid;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final inCart = controller.isInCart(product.id);
    final outOfStock = controller.isOutOfStock(product.id);
    final stock = controller.stockOf(product.id);
    final localizedUnit = switch (product.unit) {
      'кг' => loc.translate('kg'),
      'литр' => loc.translate('litre'),
      'дона' => loc.translate('piece'),
      _ => product.unit,
    };

    if (grid) {
      return _gridCard(
        context,
        loc,
        localizedUnit,
        inCart,
        outOfStock,
        stock,
      );
    }
    return _listCard(
      context,
      loc,
      localizedUnit,
      inCart,
      outOfStock,
      stock,
    );
  }

  Widget _listCard(
    BuildContext context,
    AppLocalizations loc,
    String localizedUnit,
    bool inCart,
    bool outOfStock,
    int stock,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _imageBox(118, stock, outOfStock),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(product.desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 6),
                  Text(
                    '${formatPrice(product.price)} ${loc.translate("sum")} / $localizedUnit',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.green),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _action(loc, inCart, outOfStock),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gridCard(
    BuildContext context,
    AppLocalizations loc,
    String localizedUnit,
    bool inCart,
    bool outOfStock,
    int stock,
  ) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _imageBox(150, stock, outOfStock, rounded: false),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(product.desc,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const Spacer(),
                  Text(
                    '${formatPrice(product.price)} ${loc.translate("sum")} / $localizedUnit',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.green),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: _action(loc, inCart, outOfStock),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageBox(
    double size,
    int stock,
    bool outOfStock, {
    bool rounded = true,
  }) {
    final image =
        product.imageUrl.isNotEmpty && isHttpImageUrl(product.imageUrl)
            ? Image.network(
                product.imageUrl.trim(),
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Center(
                      child: Text(product.emoji,
                          style: TextStyle(fontSize: size < 130 ? 36 : 52)));
                },
                errorBuilder: (_, __, ___) => Center(
                  child: Text(product.emoji,
                      style: TextStyle(fontSize: size < 130 ? 36 : 52)),
                ),
              )
            : Center(
                child: Text(product.emoji,
                    style: TextStyle(fontSize: size < 130 ? 36 : 52)),
              );

    return ClipRRect(
      borderRadius: rounded ? BorderRadius.circular(16) : BorderRadius.zero,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.grey.shade100, child: image),
            if (stock < 999999 && stock <= 5)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: outOfStock
                        ? Colors.red.shade700
                        : Colors.orange.shade700,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    outOfStock ? 'Тугади' : '$stock қолди',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _action(
    AppLocalizations loc,
    bool inCart,
    bool outOfStock,
  ) {
    if (inCart) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green[300]!),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 16, color: Colors.green[700]),
            const SizedBox(width: 6),
            Text(
              loc.translate('selected'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.green[700],
              ),
            ),
          ],
        ),
      );
    }
    return ElevatedButton(
      onPressed: outOfStock ? null : () => controller.addToCart(product),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        minimumSize: Size.zero,
      ),
      child: Text(loc.translate('add'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }
}
