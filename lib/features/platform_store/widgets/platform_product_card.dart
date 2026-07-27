import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/platform_product.dart';
import '../controllers/platform_store_controller.dart';
import '../screens/platform_product_detail_screen.dart';

class PlatformProductCard extends StatelessWidget {
  const PlatformProductCard({super.key, required this.product});

  final PlatformProduct product;

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: context.read<PlatformStoreController>(),
          child: PlatformProductDetailScreen(product: product),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlatformStoreController>();
    final qty = c.qtyOf(product.id);
    final out = c.isOutOfStock(product);
    final priceText = context.tr('price_sum_short').replaceAll(
          '{price}',
          formatPrice(product.price),
        );

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(13),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(context),
        borderRadius: BorderRadius.circular(13),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.cardBorderMuted, width: 0.5),
          ),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.hardEdge,
                  child: Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.hardEdge,
                    children: [
                      const ColoredBox(color: Color(0xFFE8F5E9)),
                      _ProductImages(urls: product.displayImages),
                      if (out)
                        ColoredBox(
                          color: Colors.black.withValues(alpha: 0.45),
                          child: Center(
                            child: Text(
                              context.tr('platform_store_out_of_stock'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      if (!out)
                        Positioned(
                          right: 5,
                          bottom: 5,
                          child: Material(
                            color: const Color(0xFFB39DDB), // очик бинафша
                            shape: const CircleBorder(),
                            elevation: 1.5,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                if (qty == 0) {
                                  c.addToCart(product);
                                } else {
                                  c.increase(product.id);
                                }
                              },
                              child: const SizedBox(
                                width: 26,
                                height: 26,
                                child: Icon(
                                  Icons.add,
                                  size: 15,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (qty > 0)
                        Positioned(
                          left: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$qty',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A3A20),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                priceText,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2E5C1E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductImages extends StatefulWidget {
  const _ProductImages({required this.urls});

  final List<String> urls;

  @override
  State<_ProductImages> createState() => _ProductImagesState();
}

class _ProductImagesState extends State<_ProductImages> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    if (urls.isEmpty) return const _Image(url: '');
    if (urls.length == 1) return _Image(url: urls.first);

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          itemCount: urls.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) => SizedBox.expand(child: _Image(url: urls[i])),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 6,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < urls.length; i++)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _page
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.45),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Image extends StatelessWidget {
  const _Image({required this.url});

  final String url;

  static const _bg = Color(0xFFE8F5E9);

  @override
  Widget build(BuildContext context) {
    final u = url.trim();
    Widget child;
    if (u.startsWith('assets/')) {
      child = Image.asset(u, fit: BoxFit.contain, alignment: Alignment.center);
    } else if (u.isNotEmpty && isHttpImageUrl(u)) {
      child = CachedNetworkImage(
        imageUrl: u,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        width: double.infinity,
        height: double.infinity,
        memCacheWidth: 600,
        placeholder: (_, __) => const Center(
          child: Text('🛒', style: TextStyle(fontSize: 28)),
        ),
        errorWidget: (_, __, ___) => const Center(
          child: Text('🛒', style: TextStyle(fontSize: 28)),
        ),
      );
    } else if (u.isNotEmpty && isDataImageUrl(u)) {
      final bytes = decodeDataUrlImageBytes(u);
      child = bytes != null
          ? Image.memory(
              bytes,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              width: double.infinity,
              height: double.infinity,
            )
          : const Center(child: Text('🛒', style: TextStyle(fontSize: 28)));
    } else {
      child = const Center(child: Text('🛒', style: TextStyle(fontSize: 28)));
    }

    return ColoredBox(
      color: _bg,
      child: SizedBox.expand(child: child),
    );
  }
}
