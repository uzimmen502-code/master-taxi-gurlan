import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../markets/data/market_taxonomy_repository.dart';
import '../../markets/domain/market_taxonomy.dart';
import '../home_module_gate.dart';
import 'ava_section.dart';

/// Бош саҳифадаги «Бозорлар» блоки (STAGE 12, эга 2026-11-16).
///
/// Хизматлар қаторидан кейин — бозор карточкалари вертикал рўйхатда, эга
/// белгилаган ТАРТИБДА. Ҳар карточка ўз модул дарвозаси билан
/// ([HomeModuleGate.showInGrid]); биронтаси кўринмаса — блок умуман йўқ.
/// Босилганда очиш мантиғи чақирувчида (`home_screen.dart`, мавжуд
/// helper'лар: `openMarket`, `_openGated`, `_openWholesale`, `_openModule`).
class HomeMarketEntry {
  const HomeMarketEntry({
    required this.id,
    required this.moduleId,
    required this.titleKey,
    required this.imagePath,
    this.taxonomyMarketId,
    this.sloganKey,
  });

  /// Блок ичидаги ID (тест/калит учун): `livestock` … `aralash`.
  final String id;

  /// Админ дарвозаси (`kKnownModuleIds`).
  final String moduleId;
  final String titleKey;
  final String imagePath;

  /// Таксономиядаги бозор (`taxonomy/markets`) — шиор шу ердан.
  final String? taxonomyMarketId;

  /// Таксономияда бўлмаган бозорлар шиори — lang калити.
  final String? sloganKey;
}

/// Эга тартиби: Мол, Мошина, Гўшт, Деҳқон, Уй-жой, Улгуржи, Хитой, Аралаш.
const kHomeMarketEntries = <HomeMarketEntry>[
  HomeMarketEntry(
    id: 'livestock',
    moduleId: 'livestock_market',
    titleKey: 'home_module_livestock_market',
    imagePath: 'assets/images/markets/market_livestock.webp',
    taxonomyMarketId: 'livestock',
    sloganKey: 'home_market_livestock_slogan',
  ),
  HomeMarketEntry(
    id: 'auto',
    moduleId: 'auto_market',
    titleKey: 'home_module_auto_market',
    imagePath: 'assets/images/markets/market_auto.webp',
    taxonomyMarketId: 'auto',
    sloganKey: 'home_market_auto_slogan',
  ),
  HomeMarketEntry(
    id: 'meat',
    moduleId: 'meat_market',
    titleKey: 'home_module_meat_market',
    imagePath: 'assets/images/markets/market_meat.webp',
    taxonomyMarketId: 'meat',
    sloganKey: 'home_market_meat_slogan',
  ),
  HomeMarketEntry(
    id: 'farm',
    moduleId: 'farm_market',
    titleKey: 'home_module_farm_market',
    imagePath: 'assets/images/markets/market_farm.webp',
    taxonomyMarketId: 'farm',
    sloganKey: 'home_market_farm_slogan',
  ),
  HomeMarketEntry(
    id: 'realty',
    moduleId: 'realty',
    titleKey: 'home_module_realty',
    imagePath: 'assets/images/markets/market_realty.webp',
    sloganKey: 'home_market_realty_slogan',
  ),
  HomeMarketEntry(
    id: 'wholesale',
    moduleId: 'wholesale_market',
    titleKey: 'home_module_wholesale',
    imagePath: 'assets/images/markets/market_wholesale.webp',
    sloganKey: 'home_market_wholesale_slogan',
  ),
  HomeMarketEntry(
    id: 'china',
    moduleId: 'china_market',
    titleKey: 'home_module_china',
    imagePath: 'assets/images/markets/market_china.webp',
    sloganKey: 'home_market_china_slogan',
  ),
  HomeMarketEntry(
    id: 'aralash',
    moduleId: 'cheap_products_home',
    titleKey: 'home_market_aralash_title',
    imagePath: 'assets/images/markets/market_aralash.webp',
    sloganKey: 'home_market_aralash_slogan',
  ),
];

/// Иловада бозор маҳсулотига буюртма бериш ёқилганми (Гўшт шиори танлови).
///
/// ALMASHTIRISH NUQTASI: ҳозир клиентда бизнес-буюртма учун дарвоза/флаг
/// ЙЎҚ — шунинг учун `false` ва Гўштда `sloganNoOrder` кўрсатилади. Буюртма
/// ёқилганда шу ерни сервер флагига улаш керак (таксономиядаги `slogan`
/// «етказиб беришдан фойдаланинг» матнига ўтади).
const bool kMarketInAppOrderingEnabled = false;

/// Таксономия шиори: буюртма ёқилмаган бўлса ва `sloganNoOrder` бор бўлса — у,
/// акс ҳолда `slogan`. Таксономия йўқ/бузилган бўлса — бўш сатр (карточка сарлавҳа билан қолади).
String taxonomyMarketSlogan(
  MarketDef? def,
  String lang, {
  bool inAppOrdering = kMarketInAppOrderingEnabled,
}) {
  if (def == null) return '';
  if (!inAppOrdering && def.sloganNoOrder.isNotEmpty) {
    return localizedName(def.sloganNoOrder, lang);
  }
  return localizedName(def.slogan, lang);
}

/// Дарвоза бўйича кўринадиган карточкалар — [kHomeMarketEntries] тартибида.
List<HomeMarketEntry> visibleHomeMarkets(bool Function(String moduleId) isVisible) => [
      for (final e in kHomeMarketEntries)
        if (isVisible(e.moduleId)) e,
    ];

class HomeMarketsBlock extends StatefulWidget {
  const HomeMarketsBlock({
    super.key,
    required this.onOpen,
    this.isVisible,
    this.loadTaxonomy,
  });

  final void Function(HomeMarketEntry entry) onOpen;

  /// Тест учун; сукут — [HomeModuleGate.showInGrid].
  final bool Function(String moduleId)? isVisible;

  /// Тест учун; сукут — [MarketTaxonomyRepository.load] (сеансда бир марта ўқилади).
  final Future<MarketTaxonomy> Function()? loadTaxonomy;

  @override
  State<HomeMarketsBlock> createState() => _HomeMarketsBlockState();
}

class _HomeMarketsBlockState extends State<HomeMarketsBlock> {
  MarketTaxonomy? _taxonomy;

  @override
  void initState() {
    super.initState();
    _taxonomy = widget.loadTaxonomy == null ? MarketTaxonomyRepository.cached : null;
    if (_taxonomy == null) _load();
  }

  Future<void> _load() async {
    try {
      final t = await (widget.loadTaxonomy ?? MarketTaxonomyRepository.load)();
      if (mounted) setState(() => _taxonomy = t);
    } catch (e) {
      // Шиорсиз ҳам карточка ишлайди (сарлавҳа + расм); хато фақат логда (25-банд).
      debugPrint('[HomeMarketsBlock] MARKET_TAXONOMY_LOAD_FAILED: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = visibleHomeMarkets(widget.isVisible ?? HomeModuleGate.showInGrid);
    if (items.isEmpty) return const SizedBox.shrink();
    final lang = context.contentLang;
    return Padding(
      padding: const EdgeInsets.only(top: AvaSpace.sectionMin),
      child: AvaSection(
        key: const ValueKey('home_markets_block'),
        title: context.tr('home_markets_block_title'),
        status: AvaSectionStatus.ready,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: AvaSpace.gap),
              _MarketCard(
                entry: items[i],
                // Эга 2026-11-16: 8 та картанинг ҳаммасида қисқа шиор тил калитидан (таксономия шиори — фақат калит йўқ бўлса).
                slogan: items[i].sloganKey != null
                    ? context.tr(items[i].sloganKey!)
                    : taxonomyMarketSlogan(_taxonomy?.market(items[i].taxonomyMarketId!), lang),
                onTap: () => widget.onOpen(items[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MarketCard extends StatelessWidget {
  const _MarketCard({required this.entry, required this.slogan, required this.onTap});

  final HomeMarketEntry entry;
  final String slogan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final radius = BorderRadius.circular(AvaRadius.card);
    return Material(
      key: ValueKey('home_market_card_${entry.id}'),
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          // Эга 2026-11-16: карта баландлиги = расм баландлиги (64); матн катта тизим шрифтида ҳам сиғсин.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.0,
            child: SizedBox(
            height: 64,
            child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  entry.imagePath,
                  width: 100,
                  height: 64,
                  fit: BoxFit.cover,
                  cacheWidth: 300,
                  errorBuilder: (_, __, ___) => Container(width: 100, height: 64, color: c.surface2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      context.tr(entry.titleKey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink),
                    ),
                    if (slogan.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        slogan,
                        key: ValueKey('home_market_slogan_${entry.id}'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, height: 1.1, color: c.ink2),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 20, color: c.ink3),
            ],
          ),
          ),
          ),
        ),
      ),
    );
  }
}
