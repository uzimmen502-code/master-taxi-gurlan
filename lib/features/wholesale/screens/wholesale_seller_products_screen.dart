import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../ads/widgets/market_grid.dart';
import '../models/wholesale_product.dart';
import '../repositories/wholesale_products_repository.dart';
import '../widgets/wholesale_product_card.dart';
import '../widgets/wholesale_stream_builder.dart';
import 'wholesale_product_detail_screen.dart';

/// Сотувчининг барча ФАОЛ маҳсулотлари — Улгуржи ва Хитой бозори
/// тафсилотидаги «Сотувчининг барча маҳсулотлари» тугмасидан очилади
/// (Аҳоли бозоридаги дўкон саҳифасининг аналоги).
///
/// [market] сотувчининг шу бозордаги товарларини қолдиради: Хитой
/// товарини очган харидорга улгуржи товарлар аралашиб кетмайди.
class WholesaleSellerProductsScreen extends StatefulWidget {
  const WholesaleSellerProductsScreen({
    super.key,
    required this.sellerId,
    required this.sellerName,
    this.market,
    this.streamFactory,
  });

  final String sellerId;
  final String sellerName;
  final String? market;

  /// Тестда Firestore ўрнига сохта оқим учун (ҳар уланишда янги оқим).
  final Stream<List<WholesaleProduct>> Function()? streamFactory;

  @override
  State<WholesaleSellerProductsScreen> createState() =>
      _WholesaleSellerProductsScreenState();
}

class _WholesaleSellerProductsScreenState
    extends State<WholesaleSellerProductsScreen> {
  Stream<List<WholesaleProduct>>? _stream;

  Stream<List<WholesaleProduct>> _items() =>
      _stream ??= widget.streamFactory?.call() ??
          WholesaleProductsRepository()
              .watchActiveBySeller(widget.sellerId, market: widget.market);

  @override
  Widget build(BuildContext context) {
    final title = widget.sellerName.trim().isEmpty
        ? context.tr('wholesale_seller_label')
        : widget.sellerName.trim();
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: WholesaleStreamBuilder<List<WholesaleProduct>>(
        stream: _items(),
        // Firestore stream хатодан кейин ёпилади: қайта улаймиз.
        onRetry: () => setState(() => _stream = null),
        builder: (context, data) {
          final items = data ?? const <WholesaleProduct>[];
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.storefront_outlined,
                        size: 48, color: AppColors.sectionMuted),
                    const SizedBox(height: 12),
                    Text(
                      context.tr('wholesale_empty_products'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            );
          }
          return MarketProductGrid(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final p = items[i];
              return WholesaleProductCard(
                product: p,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WholesaleProductDetailScreen(
                      product: p,
                      catalog: items,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
