import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../markets/data/market_taxonomy_repository.dart';
import '../../markets/domain/market_taxonomy.dart';
import '../../supermarket/data/supermarket_repository.dart';
import '../home_module_gate.dart';
import 'home_lite_cards.dart';

/// Бош саҳифадаги «Бозорлар» блоки (STAGE 12, эга 2026-11-16; «енгил дизайн» 2026-11-20).
///
/// Бозор карточкалари вертикал рўйхатда, эга белгилаган ТАРТИБДА (йиғилмайди —
/// эга рад этди). Ҳар карточка ўз модул дарвозаси билан ([HomeModuleGate.showInGrid]);
/// биронтаси кўринмаса — блок умуман йўқ. Босилганда очиш мантиғи чақирувчида
/// (`home_screen.dart`, мавжуд helper'лар: `openMarket`, `_openGated`, `_openWholesale`, `_openModule`).
class HomeMarketEntry {
  const HomeMarketEntry({
    required this.id,
    required this.moduleId,
    required this.titleKey,
    required this.sloganKey,
    this.imagePath,
    this.icon,
    this.taxonomyMarketId,
  });

  /// Блок ичидаги ID (тест/калит учун): `electronics` … `aralash`.
  final String id;

  /// Админ дарвозаси (`kKnownModuleIds`).
  final String moduleId;
  final String titleKey;

  /// Карточка расми (100×64, cover); `null` бўлса [icon] (вақтинча, эга расм бермагунча).
  final String? imagePath;
  final IconData? icon;

  /// Таксономиядаги бозор (`taxonomy/markets`) — [openMarket] шу ID билан очади.
  final String? taxonomyMarketId;

  /// Қисқа изоҳ — lang калити (эга 2026-11-20 матнлари).
  final String sloganKey;
}

/// Эга тартиби (2026-11-20): Электроника, Мошина, Мол, Гўшт, Деҳқон, Маиший техника,
/// Хизматлар, Уй-жой, Улгуржи, Хитой товарлари, Аралаш.
const kHomeMarketEntries = <HomeMarketEntry>[
  // «AVA Супермаркет» (эга 2026-11-20): блок ТЕПАСИДА. Дарвоза: модул ёқилган ВА сервер
  // `getSupermarketAccess.allowed` ([visibleHomeMarkets] `supermarketAllowed`). Расм — эга берган (2026-11-20).
  HomeMarketEntry(
    id: 'supermarket',
    moduleId: 'supermarket',
    titleKey: 'home_market_supermarket_title',
    imagePath: 'assets/images/markets/market_supermarket_v1.webp',
    icon: Icons.local_grocery_store_rounded,
    sloganKey: 'home_market_supermarket_slogan',
  ),
  HomeMarketEntry(
    id: 'electronics',
    moduleId: 'electronics_market',
    titleKey: 'home_module_electronics_market',
    imagePath: 'assets/images/markets/market_electronics_v2.webp',
    taxonomyMarketId: 'electronics',
    sloganKey: 'home_market_electronics_slogan',
  ),
  HomeMarketEntry(
    id: 'auto',
    moduleId: 'auto_market',
    titleKey: 'home_module_auto_market',
    imagePath: 'assets/images/markets/market_auto_v3.webp',
    taxonomyMarketId: 'auto',
    sloganKey: 'home_market_auto_slogan',
  ),
  HomeMarketEntry(
    id: 'livestock',
    moduleId: 'livestock_market',
    titleKey: 'home_module_livestock_market',
    imagePath: 'assets/images/markets/market_livestock_v3.webp',
    taxonomyMarketId: 'livestock',
    sloganKey: 'home_market_livestock_slogan',
  ),
  HomeMarketEntry(
    id: 'meat',
    moduleId: 'meat_market',
    titleKey: 'home_module_meat_market',
    imagePath: 'assets/images/markets/market_meat_v2.webp',
    taxonomyMarketId: 'meat',
    sloganKey: 'home_market_meat_slogan',
  ),
  HomeMarketEntry(
    id: 'farm',
    moduleId: 'farm_market',
    titleKey: 'home_module_farm_market',
    imagePath: 'assets/images/markets/market_farm_v2.webp',
    taxonomyMarketId: 'farm',
    sloganKey: 'home_market_farm_slogan',
  ),
  HomeMarketEntry(
    id: 'appliances',
    moduleId: 'appliances_market',
    titleKey: 'home_module_appliances_market',
    imagePath: 'assets/images/markets/market_appliances_v2.webp',
    taxonomyMarketId: 'appliances',
    sloganKey: 'home_market_appliances_slogan',
  ),
  // Эга 2026-11-20: бош саҳифадаги «Яқиндаги хизматлар» бўлими ўрнига — мавжуд хизматлар
  // рўйхати (jobs, kind=service), дарвоза `jobs`. Расм — эга чизгани (2026-11-20, 3-тур).
  HomeMarketEntry(
    id: 'services',
    moduleId: 'jobs',
    titleKey: 'home_market_services_title',
    imagePath: 'assets/images/home/card_services_market_v1.webp',
    icon: Icons.handyman_rounded,
    sloganKey: 'home_market_services_slogan',
  ),
  HomeMarketEntry(
    id: 'realty',
    moduleId: 'realty',
    titleKey: 'home_module_realty',
    imagePath: 'assets/images/markets/market_realty_v2.webp',
    sloganKey: 'home_market_realty_slogan',
  ),
  HomeMarketEntry(
    id: 'wholesale',
    moduleId: 'wholesale_market',
    titleKey: 'home_module_wholesale',
    imagePath: 'assets/images/markets/market_wholesale_v2.webp',
    sloganKey: 'home_market_wholesale_slogan',
  ),
  HomeMarketEntry(
    id: 'china',
    moduleId: 'china_market',
    titleKey: 'home_market_china_title',
    imagePath: 'assets/images/markets/market_china_v2.webp',
    sloganKey: 'home_market_china_slogan',
  ),
  HomeMarketEntry(
    id: 'aralash',
    moduleId: 'cheap_products_home',
    titleKey: 'home_market_aralash_title',
    imagePath: 'assets/images/markets/market_aralash_v2.webp',
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
/// Супермаркет — модул дарвозаси ВА [supermarketAllowed] (сервер рухсати) бирга.
List<HomeMarketEntry> visibleHomeMarkets(
  bool Function(String moduleId) isVisible, {
  bool supermarketAllowed = false,
}) =>
    [
      for (final e in kHomeMarketEntries)
        if (isVisible(e.moduleId) && (e.moduleId != 'supermarket' || supermarketAllowed)) e,
    ];

class HomeMarketsBlock extends StatefulWidget {
  const HomeMarketsBlock({
    super.key,
    required this.onOpen,
    this.isVisible,
    this.loadTaxonomy,
    this.loadSupermarketAccess,
  });

  /// Тест учун; сукут — [SupermarketAccessCache.get] (`getSupermarketAccess`, 5 дақ кеш).
  /// Фақат `supermarket` модули дарвозадан ўтса чақирилади (37-банд).
  final Future<bool> Function()? loadSupermarketAccess;

  final void Function(HomeMarketEntry entry) onOpen;

  /// Тест учун; сукут — [HomeModuleGate.showInGrid].
  final bool Function(String moduleId)? isVisible;

  /// Тест учун; сукут — [MarketTaxonomyRepository.load]. Карточка матни lang калитидан;
  /// таксономия бу ерда фақат олдиндан юкланади (бозор экрани тез очилсин).
  final Future<MarketTaxonomy> Function()? loadTaxonomy;

  @override
  State<HomeMarketsBlock> createState() => _HomeMarketsBlockState();
}

class _HomeMarketsBlockState extends State<HomeMarketsBlock> {
  bool _smAllowed = SupermarketAccessCache.cached?.allowed ?? false;
  bool _smRequested = false;

  @override
  void initState() {
    super.initState();
    if (widget.loadTaxonomy != null || MarketTaxonomyRepository.cached == null) _load();
  }

  Future<void> _loadSmAccess() async {
    try {
      final ok = await (widget.loadSupermarketAccess?.call() ??
          SupermarketAccessCache.get(FirebaseSupermarketApi()).then((a) => a.allowed));
      if (mounted && ok != _smAllowed) setState(() => _smAllowed = ok);
    } catch (e) {
      debugPrint('[HomeMarketsBlock] SUPERMARKET_ACCESS_FAILED: $e');
    }
  }

  Future<void> _load() async {
    try {
      await (widget.loadTaxonomy ?? MarketTaxonomyRepository.load)();
    } catch (e) {
      // Карточка таксономиясиз ҳам ишлайди; хато фақат логда (25-банд).
      debugPrint('[HomeMarketsBlock] MARKET_TAXONOMY_LOAD_FAILED: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVisible = widget.isVisible ?? HomeModuleGate.showInGrid;
    // Сервер рухсати фақат модул дарвозадан ўтса сўралади (дарвоза кейинроқ юкланса ҳам — шу build'да).
    if (!_smRequested && isVisible('supermarket')) {
      _smRequested = true;
      _loadSmAccess();
    }
    final items = visibleHomeMarkets(isVisible, supermarketAllowed: _smAllowed);
    if (items.isEmpty) return const SizedBox.shrink();
    return HomeLiteSection(
      key: const ValueKey('home_markets_block'),
      title: context.tr('home_markets_block_title'),
      cards: [
        for (final e in items)
          HomeLiteCardData(
            id: 'market_${e.id}',
            title: context.tr(e.titleKey),
            caption: context.tr(e.sloganKey),
            imagePath: e.imagePath,
            icon: e.icon,
            onTap: () => widget.onOpen(e),
          ),
      ],
    );
  }
}