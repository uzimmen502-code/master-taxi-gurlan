import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/platform_product.dart';
import '../ava_store_colors.dart';
import '../controllers/platform_store_controller.dart';

/// Тўловдан олдин қарама-қарши категория (озиқ↔но-озиқ) таклифи.
Future<bool> showPlatformCrossSellSheet(BuildContext context) async {
  final c = context.read<PlatformStoreController>();
  final suggestions = c.suggestOppositeProducts();
  if (suggestions.isEmpty) return true;

  final target = c.suggestOppositeKind!;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider<PlatformStoreController>.value(
      value: c,
      child: _CrossSellSheet(
        targetKind: target,
        initial: suggestions,
      ),
    ),
  );
  return result != false;
}

class _CrossSellSheet extends StatelessWidget {
  const _CrossSellSheet({
    required this.targetKind,
    required this.initial,
  });

  final String targetKind;
  final List<PlatformProduct> initial;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlatformStoreController>();
    final items = c.suggestOppositeProducts(take: 8);
    final list = items.isNotEmpty ? items : initial;
    final isFood = targetKind == PlatformProduct.kindFood;
    final title = isFood
        ? context.tr('platform_store_cross_sell_food_title')
        : context.tr('platform_store_cross_sell_non_food_title');
    final body = isFood
        ? context.tr('platform_store_cross_sell_food_body')
        : context.tr('platform_store_cross_sell_non_food_body');
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.72,
      decoration: const BoxDecoration(
        color: AvaStoreColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AvaStoreColors.softFill,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AvaStoreColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: AvaStoreColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      context.tr('platform_store_cross_sell_empty'),
                      style: const TextStyle(color: AvaStoreColors.muted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final p = list[i];
                      return _SuggestTile(product: p);
                    },
                  ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottom),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AvaStoreColors.deep,
                      side: const BorderSide(color: AvaStoreColors.border),
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      context.tr('platform_store_cross_sell_skip'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AvaStoreColors.brand,
                      foregroundColor: AvaStoreColors.onBrand,
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      context.tr('platform_store_cross_sell_continue'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestTile extends StatelessWidget {
  const _SuggestTile({required this.product});

  final PlatformProduct product;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlatformStoreController>();
    final qty = c.qtyOf(product.id);
    final priceText = context.tr('price_sum_short').replaceAll(
          '{price}',
          formatPrice(product.price),
        );

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AvaStoreColors.soft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AvaStoreColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 64,
              height: 64,
              child: ColoredBox(
                color: AvaStoreColors.surface,
                child: _Thumb(url: product.coverImageUrl),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AvaStoreColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  priceText,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AvaStoreColors.deep,
                  ),
                ),
              ],
            ),
          ),
          if (qty == 0)
            FilledButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                c.addToCart(product);
              },
              style: FilledButton.styleFrom(
                backgroundColor: AvaStoreColors.brand,
                foregroundColor: AvaStoreColors.onBrand,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 36),
              ),
              child: Text(
                context.tr('platform_store_add'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
              ),
            )
          else
            Container(
              height: 36,
              decoration: BoxDecoration(
                color: AvaStoreColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AvaStoreColors.brand),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      c.decrease(product.id);
                    },
                    child: const SizedBox(
                      width: 32,
                      height: 36,
                      child: Icon(Icons.remove, size: 18),
                    ),
                  ),
                  Text(
                    '$qty',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      c.increase(product.id);
                    },
                    child: const SizedBox(
                      width: 32,
                      height: 36,
                      child: Icon(Icons.add, size: 18),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final u = url.trim();
    if (u.startsWith('assets/')) {
      return Image.asset(u, fit: BoxFit.contain);
    }
    if (u.isNotEmpty && isHttpImageUrl(u)) {
      return CachedNetworkImage(
        imageUrl: u,
        fit: BoxFit.contain,
        memCacheWidth: 200,
        errorWidget: (_, __, ___) => const Icon(
          Icons.shopping_bag_outlined,
          color: AvaStoreColors.muted,
        ),
      );
    }
    if (u.isNotEmpty && isDataImageUrl(u)) {
      final bytes = decodeDataUrlImageBytes(u);
      if (bytes != null) return Image.memory(bytes, fit: BoxFit.contain);
    }
    return const Icon(
      Icons.shopping_bag_outlined,
      color: AvaStoreColors.muted,
    );
  }
}
