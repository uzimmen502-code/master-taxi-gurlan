import 'dart:async';
import '../widgets/market_grid.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/geo/geo_context.dart';
import '../../../core/geo/geo_districts_cache.dart';
import '../../../core/geo/geo_tier_bar.dart';
import '../../../core/geo/module_geo_policy.dart';
import '../../../core/geo/relative_location.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/catalog_search.dart';
import '../../../shared/widgets/market_search_field.dart';
import '../../../core/utils/fair_mix.dart';
import '../../../models/platform_product.dart';
import '../../../models/realty_listing.dart';
import '../../../models/search_index_entry.dart';
import '../../../repositories/platform_products_repository.dart';
import '../../../repositories/realty_repository.dart';
import '../../../repositories/search_index_repository.dart';
import '../../../core/utils/formatters.dart';
import '../../home/home_market_nav.dart';
import '../../home/home_strip_mix.dart' show HomeShopFeed;
import '../../markets/widgets/market_form_fields.dart' show marketShortBadge;
import '../../my_shop/my_shop_entry.dart';
import '../../realty/screens/realty_detail_screen.dart';
import '../../realty/screens/realty_screen.dart';
import '../../realty/widgets/realty_grid_card.dart';
import '../../wholesale/models/wholesale_product.dart';
import '../../wholesale/repositories/wholesale_products_repository.dart';
import '../../wholesale/screens/wholesale_market_screen.dart';
import '../../wholesale/screens/wholesale_product_detail_screen.dart';
import '../../wholesale/widgets/wholesale_product_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../tv_market/models/tv_shop.dart';
import '../../tv_market/repositories/tv_shop_repository.dart';
import '../../tv_market/screens/tv_shop_item_swipe_screen.dart';
import '../../tv_market/screens/tv_shop_public_screen.dart';
import '../../tv_market/widgets/tv_shop_item_grid_card.dart';
import '../models/ad_model.dart';
import '../repositories/ads_repository.dart';
import '../utils/market_shop_items.dart';
import '../widgets/ad_card.dart';
import '../widgets/platform_market_card.dart';
import '../../supermarket/screens/supermarket_home_screen.dart' show openSupermarket;

/// Аралашдаги AVA маҳсулоти белгиси (lang калити): супермаркетга бириктирилган — «AVA Супермаркет»
/// (эга 2026-11-20), бошқаси — аввалгидек «Улгуржи».
String aralashPlatformBadgeKey(PlatformProduct p) => p.isSupermarket ? 'sm_badge' : 'wholesale_screen_title';

/// [pinned] ни рўйхат бошига қўяди, айнан шу ID'ли бошқа нусхаларни олиб
/// ташлайди (такрорланмасин). [pinned] `null` бўлса — рўйхат ўзгармайди.
@visibleForTesting
List<T> withPinnedFirst<T>(List<T> list, T? pinned, Object? Function(T) idOf) {
  if (pinned == null) return list;
  final id = idOf(pinned);
  return [pinned, ...list.where((e) => idOf(e) != id)];
}

/// Аҳоли бозори: қидирув + лента.
class CheapProductsScreen extends StatefulWidget {
  const CheapProductsScreen({
    super.key,
    this.initialQuery = '',
    this.pinnedAd,
    this.pinnedPlatform,
  });

  /// Бош саҳифадаги Аралаш бўлимида босилган AVA маҳсулоти — [pinnedAd] каби
  /// биринчи ўринда (эга, 2026-11-03).
  final PlatformProduct? pinnedPlatform;

  /// Қидирув сатри олдиндан тўлдирилган очилиш (мас. эълон тафсилотидаги
  /// «Ўхшаш маҳсулотлар → Барчаси»).
  final String initialQuery;

  /// Асосий экрандаги «Аралаш бозор» бўлимида босилган эълон (эга, 2026-11-03):
  /// бозор рўйхати очилади, шу эълон БИРИНЧИ ўринда (ҳудуд фильтридан қатъи
  /// назар — босилган нарса йўқолмасин). Қидирувда — одатдагидек тартиб.
  final AdModel? pinnedAd;

  @override
  State<CheapProductsScreen> createState() => _CheapProductsScreenState();
}

class _CheapProductsScreenState extends State<CheapProductsScreen> {
  static const _addRed = Color(0xFFF44336);

  late final _searchCtrl = TextEditingController(text: widget.initialQuery);
  final _platformRepo = PlatformProductsRepository();
  final _shopRepo = TvShopRepository();
  late String _query = widget.initialQuery;

  /// Серверга кетадиган қидирув — ёзиш тўхтагандан кейингина янгиланади
  /// (аввал ҳар ҳарфда янги Firestore сўрови очиларди). Платформа ва дўкон
  /// рўйхатлари хотирада фильтрланади, улар `_query` билан дарҳол янгиланади.
  late String _streamQuery = widget.initialQuery;
  Timer? _debounce;
  static const _searchDebounce = Duration(milliseconds: 350);
  List<PlatformProduct> _platform = const [];
  List<TvShopItem> _shopItems = const [];
  bool _platformLoaded = false;
  bool _shopLoaded = false;

  /// Хитой бозори маҳсулотлари ҳам Аралашда (эга, 2026-11-13) — «Хитой» белгиси
  /// билан; босилса орқага Хитой бозорига. Бир марта юкланади (37-банд).
  List<WholesaleProduct> _china = const [];

  /// Улгуржи сотувчилари маҳсулотлари (AVA нусхаларисиз) — «Улгуржи» белгиси
  /// билан, орқага Улгуржи бозорга (эга, 2026-11-13).
  List<WholesaleProduct> _ulgurji = const [];

  /// Уй-жой бозори эълонлари (8-босқич, эга 2026-11-15) — «Уй-жой» белгиси билан; босилса — Уй-жой бозори
  /// устида тафсилот. Аралашнинг ҳудуд танлови бўйича, бир марта юкланади (ҳудуд ўзгарса — қайта).
  List<RealtyListing> _realty = const [];
  static const _realtyLimit = 40;

  /// Улгуржи/Хитой бозор экранига узатиш учун (HomeController бу маршрутда йўқ).
  String _myPhone = '';

  /// Қидирувда сервер топган онлайн дўкон маҳсулотлари (`searchTokens`, охирги 80 та билан чекланмайди) ва номи
  /// мос келган дўконлар (`search_index`, тури `shop`) — 2026-10-25, 4-босқич.
  List<TvShopItem> _searchedItems = const [];
  List<SearchIndexEntry> _shopHits = const [];
  late final SearchIndexRepository _searchIndex = SearchIndexRepository();

  /// Вилоят даражасида ҳудуд фильтри учун шу вилоят туманлари (эълонлар каби, `inGeoScope`).
  Set<String> _regionDistricts = const {};

  /// «Қайта уриниш»: эълонлар оқими қайтадан очилади.
  void _retryAds() => setState(() {
        _adsStream = null;
        _streamKey = '';
      });

  static const _moduleId = 'cheap_products_home';

  /// Ҳудуд даражаси (D-GEO-1): туман → вилоят → Республика, танлов
  /// сақланади. Аввал бу экран доим бутун Республикани кўрсатарди, бош
  /// саҳифа эса фақат туманни (geo аудит).
  GeoScope _scope = GeoContext.scopeFor(_moduleId);

  /// Оқим state'да — ҳар rebuild'да янги listener очилмасин.
  Stream<List<AdModel>>? _adsStream;
  String _streamKey = '';

  Stream<List<AdModel>> _adsFor(AdsRepository repo) {
    final key = '${_scope.key}|$_streamQuery';
    if (_adsStream == null || key != _streamKey) {
      _streamKey = key;
      _adsStream = repo.searchScoped(_streamQuery, _scope);
    }
    return _adsStream!;
  }

  void _setScope(GeoScope s) {
    setState(() => _scope = s);
    unawaited(_loadRegionDistricts());
    unawaited(_loadRealty());
  }

  Future<void> _loadRegionDistricts() async {
    final scope = _scope;
    final rid = scope.area.regionId.trim();
    if (scope.level != GeoLevel.region || rid.isEmpty) {
      if (mounted && _regionDistricts.isNotEmpty) setState(() => _regionDistricts = const {});
      return;
    }
    try {
      final ids = await GeoDistrictsCache.districtIdsOf(rid);
      if (mounted && identical(scope, _scope)) setState(() => _regionDistricts = ids.toSet());
    } catch (e) {
      debugPrint('[CheapProducts] region districts: $e');
    }
  }

  /// Дўкон маҳсулотлари ва дўкон номлари бўйича сервер қидируви (ёзиш тўхтагач, эълонлар оқими билан бирга).
  Future<void> _runShopSearch(String q) async {
    final token = CatalogSearch.normalize(q).split(' ').firstWhere((w) => w.length >= 2, orElse: () => '');
    if (token.isEmpty) {
      if (mounted) {
        setState(() {
          _searchedItems = const [];
          _shopHits = const [];
        });
      }
      return;
    }
    final results = await Future.wait<Object>([
      // Сервер `searchTokens` (status=active, энг янгилари; индекс хатосида — аввалги сўров), 2026-11-16.
      _shopRepo.searchForMarket(q).catchError((Object e) {
        debugPrint('[CheapProducts] MARKET_SEARCH_FAILED scope=all: $e');
        return const <TvShopItem>[];
      }),
      _searchIndex.searchShops(q).catchError((Object e) {
        debugPrint('[CheapProducts] shop search: $e');
        return const <SearchIndexEntry>[];
      }),
    ]);
    if (!mounted || q != _streamQuery) return;
    setState(() {
      _searchedItems = results[0] as List<TvShopItem>;
      _shopHits = results[1] as List<SearchIndexEntry>;
    });
  }

  @override
  void initState() {
    super.initState();
    // Уй тасмаси аллақачон юклаган маҳсулотлар (бир хил `fetchForMarket` сўрови, 60 та) — дарҳол чизиш учун;
    // 80 талик тўлиқ рўйхат келгач алмаштирилади (эга 2026-11-19, тезлик).
    final cachedShop = HomeShopFeed.cachedItems();
    if (cachedShop != null) _shopItems = cachedShop;
    unawaited(_loadPlatform());
    unawaited(_loadShopItems());
    unawaited(_loadChina());
    unawaited(_loadUlgurji());
    unawaited(_loadRealty());
    unawaited(_loadMyPhone());
    unawaited(_loadRegionDistricts());
    if (CatalogSearch.normalize(_streamQuery).isNotEmpty) unawaited(_runShopSearch(_streamQuery));
  }

  Future<void> _loadShopItems() async {
    try {
      final list = await _shopRepo.fetchForMarket(limit: 80);
      if (!mounted) return;
      setState(() {
        _shopItems = list;
        _shopLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _shopItems = const [];
        _shopLoaded = true;
      });
    }
  }

  Future<void> _loadPlatform() async {
    try {
      final list = await _platformRepo.fetchForMarket(limit: 80);
      if (!mounted) return;
      setState(() {
        _platform = list;
        _platformLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _platform = const [];
        _platformLoaded = true;
      });
    }
  }

  Future<void> _loadChina() async {
    try {
      final list = await WholesaleProductsRepository()
          .getActiveProducts(limit: 80, market: WholesaleProduct.marketChina)
          .first;
      if (mounted) setState(() => _china = WholesaleProduct.forAralash(list));
    } catch (e) {
      // Хитой юкланмаса ҳам Аралаш бозор ишлайверсин.
      debugPrint('[CheapProducts] china $e');
    }
  }

  /// Барча Улгуржи сотувчилари маҳсулотлари (эга, 2026-11-13) — AVA нусхалари
  /// (`pp_*`) бундан мустасно, улар `platform_products` орқали аллақачон бор.
  Future<void> _loadUlgurji() async {
    try {
      final list = await WholesaleProductsRepository()
          .getActiveProducts(limit: 80, market: WholesaleProduct.marketWholesale)
          .first;
      if (mounted) setState(() => _ulgurji = WholesaleProduct.forAralash(list));
    } catch (e) {
      debugPrint('[CheapProducts] ulgurji $e');
    }
  }

  /// Фаол Уй-жой эълонлари (муддати ўтганлари репозиторийда чиқарилади), Аралаш ҳудуди бўйича.
  Future<void> _loadRealty() async {
    final scope = _scope;
    try {
      final list = await RealtyRepository().watchScoped(scope, limit: _realtyLimit).first;
      if (mounted && identical(scope, _scope)) setState(() => _realty = list);
    } catch (e) {
      // Юкланмаса ҳам Аралаш бозор ишлайверсин.
      debugPrint('[CheapProducts] ARALASH_REALTY_LOAD_FAILED: $e');
    }
  }

  Future<void> _loadMyPhone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final p = canonicalPhoneId(prefs.getString('user_phone') ?? '');
      if (mounted) _myPhone = p;
    } catch (_) {}
  }

  /// Улгуржи (AVA) маҳсулоти: орқага — Улгуржи бозор, яна орқага — асосий
  /// экран (эга, 2026-11-13). Аралаш экрани стекдан олинади.
  void _openWholesaleAva(PlatformProduct p, List<PlatformProduct> catalog) {
    unawaited(openDetailOverOtherMarket(
      Navigator.of(context),
      market: WholesaleMarketScreen(userPhone: _myPhone, market: WholesaleProduct.marketWholesale),
      detail: platformProductDetailRoute(p, catalog),
    ));
  }

  /// Улгуржи/Хитой маҳсулоти: орқага — ўша бозор, яна орқага — асосий экран.
  void _openWholesale(WholesaleProduct p, List<WholesaleProduct> catalog) {
    unawaited(openDetailOverOtherMarket(
      Navigator.of(context),
      market: WholesaleMarketScreen(userPhone: _myPhone, market: p.market),
      detail: MaterialPageRoute<void>(
        builder: (_) => WholesaleProductDetailScreen(product: p, catalog: catalog),
      ),
    ));
  }

  /// Уй-жой эълони: Аралаш стекдан олинади, ўрнига Уй-жой бозори, тафсилот унинг устида (Улгуржи каби;
  /// орқага — Уй-жой бозори, яна орқага — асосий экран).
  void _openRealty(RealtyListing r) {
    unawaited(openDetailOverOtherMarket(
      Navigator.of(context),
      market: const RealtyScreen(),
      detail: MaterialPageRoute<void>(builder: (_) => RealtyDetailScreen(listing: r)),
    ));
  }

  void _logFirestoreError(Object error, [StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('CheapProducts Firestore error: $error');
      if (stackTrace != null) {
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    setState(() => _query = v);
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, () {
      if (!mounted) return;
      setState(() => _streamQuery = _query);
      unawaited(_runShopSearch(_query));
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    setState(() {
      _query = '';
      _streamQuery = '';
      _searchedItems = const [];
      _shopHits = const [];
    });
  }

  List<PlatformProduct> _filteredPlatform() {
    final priced = _platform.where((p) => p.price > 0).toList();
    var list =
        priced.where((p) => CatalogSearch.matchesProduct(p, _query)).toList();
    if (CatalogSearch.normalize(_query).isNotEmpty) {
      list.sort((a, b) {
        final byScore = CatalogSearch.scoreProduct(b, _query)
            .compareTo(CatalogSearch.scoreProduct(a, _query));
        if (byScore != 0) return byScore;
        return a.sortOrder.compareTo(b.sortOrder);
      });
    } else {
      list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    return list;
  }

  /// Қидирувга мос Уй-жой эълонлари (сарлавҳа, матн, нарх).
  List<RealtyListing> _filteredRealty() {
    final q = _query;
    if (CatalogSearch.normalize(q).isEmpty) return _realty;
    return _realty
        .where((r) => CatalogSearch.matches(q, [r.titleOrText, r.text, r.priceText]))
        .toList(growable: false);
  }

  List<TvShopItem> _filteredShop() {
    var list = marketShopPool(_shopItems, _searchedItems, _scope, _regionDistricts);
    final q = _query;
    if (CatalogSearch.normalize(q).isEmpty) return list;
    list = list.where((i) {
      return CatalogSearch.matches(q, [
        i.title,
        i.description,
        '${i.price}',
        i.ownerName,
        i.districtLabel,
        i.kind,
      ]);
    }).toList();
    list.sort((a, b) {
      final byScore = CatalogSearch.score(
        q,
        title: b.title,
        extra: [b.description, '${b.price}', b.ownerName, b.districtLabel],
      ).compareTo(CatalogSearch.score(
        q,
        title: a.title,
        extra: [a.description, '${a.price}', a.ownerName, a.districtLabel],
      ));
      if (byScore != 0) return byScore;
      return (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
    });
    return list;
  }

  List<_MarketEntry> _mixedEntries(
    List<PlatformProduct> platform,
    List<AdModel> ads,
    List<TvShopItem> shop,
    List<WholesaleProduct> china,
    List<WholesaleProduct> ulgurji,
    List<RealtyListing> realty,
  ) {
    final q = _query;
    if (CatalogSearch.normalize(q).isEmpty) {
      return FairMix.roundRobin([
        platform.map(_MarketEntry.platform).toList(growable: false),
        ads.map(_MarketEntry.ad).toList(growable: false),
        shop.map(_MarketEntry.shop).toList(growable: false),
        china.map(_MarketEntry.wholesale).toList(growable: false),
        ulgurji.map(_MarketEntry.wholesale).toList(growable: false),
        realty.map(_MarketEntry.realty).toList(growable: false),
      ]);
    }

    final scored = <_MarketEntry>[
      ...platform.map(_MarketEntry.platform),
      ...ads.map(_MarketEntry.ad),
      ...shop.map(_MarketEntry.shop),
      ...china.map(_MarketEntry.wholesale),
      ...ulgurji.map(_MarketEntry.wholesale),
      ...realty.map(_MarketEntry.realty),
    ];
    return FairMix.byScoreThenFair(
      scored,
      (e) {
        if (e.platform != null) {
          return CatalogSearch.scoreProduct(e.platform!, q);
        }
        if (e.realty != null) {
          final r = e.realty!;
          return CatalogSearch.score(q, title: r.titleOrText, extra: [r.text, r.priceText]);
        }
        if (e.wholesale != null) {
          final c = e.wholesale!;
          return CatalogSearch.score(q, title: c.title, extra: [c.description, c.sellerCompanyName]);
        }
        if (e.shop != null) {
          final i = e.shop!;
          return CatalogSearch.score(
            q,
            title: i.title,
            extra: [i.description, '${i.price}', i.ownerName, i.districtLabel],
          );
        }
        final ad = e.ad!;
        return CatalogSearch.score(
          q,
          title: ad.title,
          extra: [ad.description, '${ad.price}', ...ad.searchTokens],
        );
      },
      laneKey: (e) {
        if (e.platform != null) return 'platform';
        if (e.shop != null) return 'shop';
        if (e.wholesale != null) return e.wholesale!.market;
        if (e.realty != null) return 'realty';
        return 'ad';
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AdsRepository>();

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        toolbarHeight: kMarketAppBarHeight,
        title: Text(context.tr('cheap_products_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.storefront_outlined),
            tooltip: context.tr('my_shop_title'),
            onPressed: () => openMyShopFromMarket(context),
          ),
          // «+» — юқоридаги барнинг ўнг томонида, ихчам (эга, 2026-10-19; аввал қидирув қаторининг ёнида эди).
          Padding(
            padding: const EdgeInsets.only(right: 2, left: 2),
            child: Center(
              // Кўриниши 32×32, босиш майдони 48×48 (≥48dp қоидаси).
              child: InkWell(
                key: const ValueKey('cheap-add-ad'),
                customBorder: const CircleBorder(),
                onTap: () => openNewProduct(context),

                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _addRed,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      // Ихчам тепа (эга, 2026-11-16): ягона қидирув майдони (барча манбалар: эълонлар, дўкон/бозор
      // маҳсулотлари, Улгуржи/Хитой, AVA, Уй-жой — мавжуд қидирув мантиғи), ҳудуд — орасида 1 px.
      body: Column(
        children: [
          MarketSearchField(
            fieldKey: const ValueKey('cheap_search'),
            controller: _searchCtrl,
            hintText: context.tr('platform_store_search_hint'),
            onChanged: _onQueryChanged,
            onClear: _clearSearch,
          ),
          const SizedBox(height: kMarketTopRowGap),
          GeoTierBar(compact: true, moduleId: _moduleId, scope: _scope, onChanged: _setScope),
          const SizedBox(height: kMarketTopRowGap),
          Expanded(
            child: StreamBuilder<List<AdModel>>(
              stream: _adsFor(repo),
              builder: (context, snap) {
                // Эълонлар оқими бутун рўйхатни тўсмайди (эга 2026-11-19, тезлик): қайси манба аввал келса —
                // шу кўрсатилади; эълонлар келгач қўшилади.
                final adsWaiting =
                    snap.connectionState == ConnectionState.waiting && !snap.hasData && !snap.hasError;
                final platform = _filteredPlatform();
                final shop = _filteredShop();
                // Босилган Хитой маҳсулоти рўйхат юкланмасдан ҳам кўринсин.
                final china = WholesaleProductsRepository.filterBySearch(_china, _query, limit: _china.length);
                final ulgurji = WholesaleProductsRepository.filterBySearch(_ulgurji, _query, limit: _ulgurji.length);
                final realty = _filteredRealty();
                final others = platform.length + shop.length + china.length + ulgurji.length + realty.length;
                if (snap.hasError) _logFirestoreError(snap.error!, snap.stackTrace);
                // Эълонлар хатоси — бошқа манбалар бўлса улар кўрсатилади (хато логда).
                final view = aralashListView(
                  adsWaiting: adsWaiting,
                  adsError: snap.hasError,
                  ads: snap.data?.length ?? 0,
                  others: others,
                  platformLoaded: _platformLoaded,
                  shopLoaded: _shopLoaded,
                );
                if (view == AralashListView.error) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.tr('cheap_products_load_error'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: AppText.bodyLarge,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            key: const ValueKey('cheap-retry'),
                            onPressed: _retryAds,
                            child: Text(context.tr('home_section_retry')),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final pinned = CatalogSearch.normalize(_query).isEmpty ? widget.pinnedAd : null;
                final ads = withPinnedFirst(snap.data ?? const <AdModel>[], pinned, (a) => a.id);
                final found = others + ads.length;

                // Эълонлар келди, платформа/дўкон ҳали юкланяпти: бирорта ҳам
                // карта йўқ бўлса «бўш» эмас — юкланиш (аввал учаласи
                // кутилар эди; энди биринчи келган кўрсатилади).
                if (view == AralashListView.loading && found == 0) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (found == 0) {
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            CatalogSearch.normalize(_query).isEmpty
                                ? context.tr('cheap_products_empty')
                                : context
                                    .tr('platform_store_search_none')
                                    .replaceAll('{query}', _query.trim()),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: AppText.bodyLarge,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          GeoWiderHint(
                            moduleId: _moduleId,
                            scope: _scope,
                            onChanged: _setScope,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final mixed = _mixedEntries(platform, ads, shop, china, ulgurji, realty);
                final lang = context.contentLang;
                final user = GeoContext.active;
                // Босилган эълон / AVA маҳсулоти — аралаш тўрнинг БИРИНЧИ катагида.
                final pinnedAva = CatalogSearch.normalize(_query).isEmpty ? widget.pinnedPlatform : null;
                final entries = pinned != null
                    ? withPinnedFirst(mixed, _MarketEntry.ad(pinned), (e) => e.ad?.id)
                    : pinnedAva != null
                        ? withPinnedFirst(mixed, _MarketEntry.platform(pinnedAva), (e) => e.platform?.id)
                        : mixed;
                // Свайп лентадаги барча дўкон маҳсулотлари бўйлаб, экрандаги тартибда
                // (эга, 2026-10-31 ва 2026-11-13 «А»: сотувчи бўйича ажратилмайди;
                // сотувчининг ҳаммаси — тафсилотдаги «Сотувчининг барча маҳсулотлари»).
                final shopInGrid = [
                  for (final e in entries)
                    if (e.shop != null) e.shop!,
                ];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        CatalogSearch.normalize(_query).isEmpty
                            ? context
                                .tr('platform_store_search_total')
                                .replaceAll('{count}', '$found')
                            : context
                                .tr('platform_store_search_found_n')
                                .replaceAll('{found}', '$found'),
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_shopHits.isNotEmpty && CatalogSearch.normalize(_query).isNotEmpty)
                      _ShopHitsStrip(hits: _shopHits),
                    Expanded(
                      child: MarketProductGrid(
                        itemCount: entries.length,
                        itemBuilder: (_, i) {
                          final e = entries[i];
                          if (e.platform != null) {
                            // «AVA Супермаркет» (эга 2026-11-20): AVA маҳсулоти Улгуржидан Супермаркетга
                            // кўчди — Аралашда «AVA Супермаркет» белгиси билан қолади, босилса Супермаркет
                            // гуруҳи. Супермаркетга бириктирилмаган (smGroupId йўқ) — аввалгидек «Улгуржи».
                            final p = e.platform!;
                            return PlatformMarketCard(
                              product: p,
                              catalog: platform,
                              cornerBadge: context.tr(aralashPlatformBadgeKey(p)),
                              onTap: () => p.isSupermarket
                                  ? openSupermarket(context, initialGroupId: p.supermarketGroupId)
                                  : _openWholesaleAva(p, platform),
                            );
                          }
                          if (e.wholesale != null) {
                            // Улгуржи / Хитой маҳсулоти: тепа ўнгда бозор номи;
                            // орқага — ўша бозор.
                            final w = e.wholesale!;
                            final isChina = w.market == WholesaleProduct.marketChina;
                            return WholesaleProductCard(
                              product: w,
                              cornerBadge: context.tr(isChina ? 'wholesale_screen_title_china' : 'wholesale_screen_title'),
                              onTap: () => _openWholesale(w, isChina ? china : ulgurji),
                            );
                          }
                          if (e.realty != null) {
                            final r = e.realty!;
                            return RealtyGridCard(
                              listing: r,
                              locationLabel: realtyLocationLabel(r, user, lang),
                              onTap: () => _openRealty(r),
                            );
                          }
                          if (e.shop != null) {
                            final item = e.shop!;
                            return TvShopItemGridCard(
                              item: item,
                              showShopBadge: true,
                              cornerBadge: marketShortBadge(context.tr, item.market),
                              locationLabel: relativeLocationLabel(
                                itemDistrictId: item.districtId,
                                itemRegionId: item.regionId,
                                userDistrictId: user.districtId,
                                userRegionId: user.regionId,
                                lang: lang,
                                districtFallback: item.districtLabel,
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    // Дўкон тугмаси маҳсулотнинг ЎЗ йўналишини очади; ўхшашлар — шу лентадан
                                    // (янги ўқиш йўқ). Маҳсулотдан маҳсулотга свайп (эга, 2026-10-31).
                                    builder: (_) => TvShopItemSwipeScreen(
                                      items: shopInGrid,
                                      initialIndex: shopInGrid.indexWhere((s) => s.id == item.id),
                                      showShopButton: true,
                                      similarPool: _shopItems,
                                      source: CatalogSearch.normalize(_query).isEmpty ? 'market' : 'search',
                                    ),
                                  ),
                                );
                              },
                            );
                          }
                          return AdCard(ad: e.ad!, catalog: ads);
                        },
                      ),
                    ),
                    // Ҳудудда эълон кам — кенгроқ ҳудуд таклифи (автоматик
                    // ўтиб кетмайди, 2-такомиллаштириш).
                    if (ads.length < 5)
                      GeoWiderHint(
                        moduleId: _moduleId,
                        scope: _scope,
                        onChanged: _setScope,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Қидирувда номи мос келган онлайн дўконлар (`search_index`, тури `shop`): босилса айнан шу дўкон ва йўналиш.
class _ShopHitsStrip extends StatelessWidget {
  const _ShopHitsStrip({required this.hits});

  final List<SearchIndexEntry> hits;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        key: const ValueKey('market_shop_hits'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        itemCount: hits.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final e = hits[i];
          return ActionChip(
            key: ValueKey('market_shop_hit_${e.id}'),
            avatar: const Icon(Icons.storefront_rounded, size: 18),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => TvShopPublicScreen(ownerPhone: e.targetOwner, businessId: e.targetBusinessId, source: 'search'),
            )),
          );
        },
      ),
    );
  }
}

class _MarketEntry {
  const _MarketEntry._({this.ad, this.platform, this.shop, this.wholesale, this.realty});
  factory _MarketEntry.ad(AdModel ad) => _MarketEntry._(ad: ad);
  factory _MarketEntry.platform(PlatformProduct p) =>
      _MarketEntry._(platform: p);
  factory _MarketEntry.shop(TvShopItem item) => _MarketEntry._(shop: item);
  factory _MarketEntry.wholesale(WholesaleProduct p) => _MarketEntry._(wholesale: p);
  factory _MarketEntry.realty(RealtyListing r) => _MarketEntry._(realty: r);

  /// Уй-жой бозори эълони (8-босқич).
  final RealtyListing? realty;

  final AdModel? ad;
  final PlatformProduct? platform;
  final TvShopItem? shop;

  /// Улгуржи ёки Хитой бозори маҳсулоти (`market` майдони бўйича).
  final WholesaleProduct? wholesale;
}

/// Аралаш рўйхати ҳолати (эга 2026-11-19, тезлик): эълонлар оқими бутун рўйхатни тўсмайди — бирорта манбада
/// элемент бўлса рўйхат; эълонлар хатоси фақат бошқа ҳеч нарса бўлмаса кўрсатилади; ҳали келмаган манба бўлса —
/// юкланиш; акс ҳолда бўш.
enum AralashListView { loading, error, empty, list }

AralashListView aralashListView({
  required bool adsWaiting,
  required bool adsError,
  required int ads,
  required int others,
  required bool platformLoaded,
  required bool shopLoaded,
}) {
  if (adsError && others == 0) return AralashListView.error;
  if (ads + others > 0) return AralashListView.list;
  if (adsWaiting || !platformLoaded || !shopLoaded) return AralashListView.loading;
  return AralashListView.empty;
}
