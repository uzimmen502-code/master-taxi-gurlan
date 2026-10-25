import 'dart:async';
import '../widgets/market_grid.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/geo/geo_context.dart';
import '../../../core/geo/geo_districts_cache.dart';
import '../../../core/geo/geo_tier_bar.dart';
import '../../../core/geo/module_geo_policy.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/catalog_search.dart';
import '../../../core/utils/fair_mix.dart';
import '../../../models/platform_product.dart';
import '../../../models/search_index_entry.dart';
import '../../../repositories/platform_products_repository.dart';
import '../../../repositories/search_index_repository.dart';
import '../../my_shop/my_shop_entry.dart';
import '../../tv_market/models/tv_shop.dart';
import '../../tv_market/repositories/tv_shop_repository.dart';
import '../../tv_market/screens/tv_shop_item_detail_screen.dart';
import '../../tv_market/screens/tv_shop_public_screen.dart';
import '../../tv_market/widgets/tv_shop_item_grid_card.dart';
import '../models/ad_model.dart';
import '../repositories/ads_repository.dart';
import '../utils/market_shop_items.dart';
import '../widgets/ad_card.dart';
import '../widgets/platform_market_card.dart';

/// Аҳоли бозори: қидирув + лента.
class CheapProductsScreen extends StatefulWidget {
  const CheapProductsScreen({super.key, this.initialQuery = ''});

  /// Қидирув сатри олдиндан тўлдирилган очилиш (мас. эълон тафсилотидаги
  /// «Ўхшаш маҳсулотлар → Барчаси»).
  final String initialQuery;

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
      _shopRepo.searchForMarket(token).catchError((Object e) {
        debugPrint('[CheapProducts] item search: $e');
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
    unawaited(_loadPlatform());
    unawaited(_loadShopItems());
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
  ) {
    final q = _query;
    if (CatalogSearch.normalize(q).isEmpty) {
      return FairMix.roundRobin([
        platform.map(_MarketEntry.platform).toList(growable: false),
        ads.map(_MarketEntry.ad).toList(growable: false),
        shop.map(_MarketEntry.shop).toList(growable: false),
      ]);
    }

    final scored = <_MarketEntry>[
      ...platform.map(_MarketEntry.platform),
      ...ads.map(_MarketEntry.ad),
      ...shop.map(_MarketEntry.shop),
    ];
    return FairMix.byScoreThenFair(
      scored,
      (e) {
        if (e.platform != null) {
          return CatalogSearch.scoreProduct(e.platform!, q);
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onQueryChanged,
                    decoration: InputDecoration(
                      hintText: context.tr('platform_store_search_hint'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.trim().isEmpty
                          ? null
                          : IconButton(
                              tooltip:
                                  context.tr('platform_store_search_clear'),
                              icon: const Icon(Icons.clear),
                              onPressed: _clearSearch,
                            ),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          GeoTierBar(moduleId: _moduleId, scope: _scope, onChanged: _setScope),
          Expanded(
            child: StreamBuilder<List<AdModel>>(
              stream: _adsFor(repo),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData &&
                    !snap.hasError) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  _logFirestoreError(snap.error!, snap.stackTrace);
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

                final ads = snap.data ?? const <AdModel>[];
                final platform = _filteredPlatform();
                final shop = _filteredShop();
                final found = platform.length + ads.length + shop.length;

                // Эълонлар келди, платформа/дўкон ҳали юкланяпти: бирорта ҳам
                // карта йўқ бўлса «бўш» эмас — юкланиш (аввал учаласи
                // кутилар эди; энди биринчи келган кўрсатилади).
                if (found == 0 && (!_platformLoaded || !_shopLoaded)) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (platform.isEmpty && ads.isEmpty && shop.isEmpty) {
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

                final entries = _mixedEntries(platform, ads, shop);

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
                            return PlatformMarketCard(
                              product: e.platform!,
                              catalog: platform,
                            );
                          }
                          if (e.shop != null) {
                            final item = e.shop!;
                            return TvShopItemGridCard(
                              item: item,
                              showShopBadge: true,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    // Дўкон тугмаси маҳсулотнинг ЎЗ йўналишини очади; ўхшашлар — шу лентадан
                                    // (янги ўқиш йўқ).
                                    builder: (_) => TvShopItemDetailScreen(
                                      item: item,
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
  const _MarketEntry._({this.ad, this.platform, this.shop});
  factory _MarketEntry.ad(AdModel ad) => _MarketEntry._(ad: ad);
  factory _MarketEntry.platform(PlatformProduct p) =>
      _MarketEntry._(platform: p);
  factory _MarketEntry.shop(TvShopItem item) => _MarketEntry._(shop: item);

  final AdModel? ad;
  final PlatformProduct? platform;
  final TvShopItem? shop;
}
