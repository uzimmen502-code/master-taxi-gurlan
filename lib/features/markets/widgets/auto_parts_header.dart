import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../models/platform_product.dart';
import '../../../repositories/platform_products_repository.dart';
import '../../ads/widgets/market_grid.dart';
import '../../ads/widgets/platform_market_card.dart';
import '../../incentives/screens/auto_hub_screen.dart' show autoHubProducts;
import '../../incentives/widgets/ava_service_center_card.dart';
import '../domain/market_taxonomy.dart';

/// Мошина бозори «Эҳтиёт қисмлар» тасмасидаги AVA маҳсулотлари туркумлари (эга, 2026-11-15).
const List<String> kAutoPartsAvaCategories = ['tire', 'oil', 'battery'];

/// «Эҳтиёт қисмлар» таби тепасида AVA блоки (сервис + маҳсулотлар) чиқадими.
bool showsAutoPartsHeader(String marketId, String category) =>
    marketId == kAutoMarketId && category == kAutoPartsCategory;

/// AVA тасмаси: фаол, нархи бор, туркуми [kAutoPartsAvaCategories] ичида (`autoHubProducts` қоидаси).
List<PlatformProduct> autoPartsAvaProducts(List<PlatformProduct> all) => [
      for (final p in autoHubProducts(all, ''))
        if (kAutoPartsAvaCategories.contains(p.incentiveCategory)) p,
    ];

/// Мошина бозори «Эҳтиёт қисмлар» табининг тепаси (9-босқич): туман AVA сервис маркази картаси ва AVA
/// маҳсулотлари (шина / мой / аккумулятор) горизонтал тасмаси — «AVA» белгили [PlatformMarketCard] (босилса —
/// мавжуд AVA маҳсулот тафсилоти/сават оқими, «Менинг машинам»дагидек). Остида — фойдаланувчи эълонлари.
class AutoPartsAvaHeader extends StatefulWidget {
  const AutoPartsAvaHeader({super.key, this.loadService, this.loadProducts});

  /// Тест учун.
  final Future<AvaServiceInfo> Function()? loadService;
  final Future<List<PlatformProduct>> Function()? loadProducts;

  @override
  State<AutoPartsAvaHeader> createState() => _AutoPartsAvaHeaderState();
}

class _AutoPartsAvaHeaderState extends State<AutoPartsAvaHeader> {
  late final Future<AvaServiceInfo> _service = (widget.loadService ?? loadAvaServiceInfo)();
  late final Future<List<PlatformProduct>> _products =
      (widget.loadProducts ?? PlatformProductsRepository().fetchCatalog)();

  static const double _cardWidth = 150;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('auto_parts_header'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AvaServiceCenterCard(info: _service, margin: const EdgeInsets.fromLTRB(0, 4, 0, 0)),
        FutureBuilder<List<PlatformProduct>>(
          future: _products,
          builder: (context, snap) {
            if (snap.hasError) debugPrint('[AutoParts] AUTO_PARTS_AVA_LOAD_FAILED: ${snap.error}');
            final items = autoPartsAvaProducts(snap.data ?? const []);
            if (items.isEmpty) return const SizedBox(height: 8);
            final height = MarketGridMetrics.cellExtent(context, _cardWidth);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                  child: Text(
                    context.tr('auto_parts_ava_products'),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                SizedBox(
                  height: height,
                  child: ListView.separated(
                    key: const ValueKey('auto_parts_ava_strip'),
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => SizedBox(
                      width: _cardWidth,
                      child: PlatformMarketCard(
                        key: ValueKey('auto_parts_ava_${items[i].id}'),
                        product: items[i],
                        catalog: items,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Text(
            context.tr('auto_parts_listings'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
      ],
    );
  }
}
