import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../wholesale/models/wholesale_product.dart';
import '../../wholesale/repositories/wholesale_products_repository.dart';
import 'ava_list_row.dart';
import 'ava_section.dart';

/// Нарх поғонасининг қисқа кўриниши: «10+ дона: 9 000 сўм».
///
/// Тавсиф талаби — «нарх поғонаси кўрсатилсин». Карточкада жой тор
/// бўлгани учун ЭНГ ПАСТ поғона (минимал буюртма) кўрсатилади; тўлиқ
/// поғоналар маҳсулот саҳифасида.
String formatTierNote(BuildContext context, WholesaleProduct p) {
  if (p.priceTiers.isEmpty) return '';
  final t = p.priceTiers.first;
  return '${t.minQty}+ ${p.unit}';
}

/// 7-бўлим: улгуржи бозори.
class HomeWholesaleSection extends StatefulWidget {
  const HomeWholesaleSection({
    super.key,
    required this.onOpenAll,
    required this.onOpenProduct,
  });

  final VoidCallback onOpenAll;
  final void Function(WholesaleProduct product) onOpenProduct;

  static const limit = 5;

  @override
  State<HomeWholesaleSection> createState() => _HomeWholesaleSectionState();
}

class _HomeWholesaleSectionState extends State<HomeWholesaleSection> {
  final _repo = WholesaleProductsRepository();
  StreamSubscription<List<WholesaleProduct>>? _sub;

  AvaSectionStatus _status = AvaSectionStatus.loading;
  List<WholesaleProduct> _items = const [];

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _sub?.cancel();
    if (mounted) setState(() => _status = AvaSectionStatus.loading);
    // Улгуржи бозор ҳудудга боғланмаган — сотувчилар вилоятлараро
    // ишлайди, шунинг учун бу бўлимда туман филтри йўқ.
    _sub = _repo
        .getActiveProducts(limit: HomeWholesaleSection.limit)
        .listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _items = list;
          _status =
              list.isEmpty ? AvaSectionStatus.empty : AvaSectionStatus.ready;
        });
      },
      onError: (Object e) {
        debugPrint('[HomeWholesale] $e');
        if (mounted) setState(() => _status = AvaSectionStatus.error);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AvaSection(
      title: context.tr('home_module_wholesale'),
      status: _status,
      onSeeAll: widget.onOpenAll,
      onRetry: _listen,
      skeletonRows: 1,
      child: SizedBox(
        height: 214,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: _items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final p = _items[i];
            final cover = p.imageUrls.isEmpty ? '' : p.imageUrls.first;
            return AvaTileCard(
              title: p.title,
              price: p.basePrice > 0
                  ? '${context.tr('home_price_from')} '
                      '${formatPrice(p.basePrice)} $kCurrencySum'
                  : null,
              priceNote: formatTierNote(context, p),
              footnote: p.sellerCompanyName,
              onTap: () => widget.onOpenProduct(p),
              image: cover.startsWith('http')
                  ? CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover)
                  : null,
            );
          },
        ),
      ),
    );
  }
}
