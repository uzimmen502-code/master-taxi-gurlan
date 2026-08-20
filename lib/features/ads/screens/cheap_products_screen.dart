import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/catalog_search.dart';
import '../../../core/utils/fair_mix.dart';
import '../../../models/platform_product.dart';
import '../../../repositories/platform_products_repository.dart';
import '../../tv_market/models/tv_shop.dart';
import '../../tv_market/repositories/tv_shop_repository.dart';
import '../../tv_market/screens/tv_shop_item_detail_screen.dart';
import '../../tv_market/screens/tv_shop_public_screen.dart';
import '../../tv_market/widgets/tv_shop_item_grid_card.dart';
import '../models/ad_model.dart';
import '../repositories/ads_repository.dart';
import '../widgets/ad_card.dart';
import '../widgets/platform_market_card.dart';
import 'create_ad_screen.dart';
import 'my_ads_screen.dart';

/// Аҳоли бозори: қидирув + лента.
class CheapProductsScreen extends StatefulWidget {
  const CheapProductsScreen({super.key});

  @override
  State<CheapProductsScreen> createState() => _CheapProductsScreenState();
}

class _CheapProductsScreenState extends State<CheapProductsScreen> {
  static const _addRed = Color(0xFFF44336);

  final _searchCtrl = TextEditingController();
  final _platformRepo = PlatformProductsRepository();
  final _shopRepo = TvShopRepository();
  String _query = '';
  List<PlatformProduct> _platform = const [];
  List<TvShopItem> _shopItems = const [];
  bool _platformLoaded = false;
  bool _shopLoaded = false;

  static const _loadErrorMessage =
      'Маълумотларни юклашда хатолик юз берди. Илтимос кейинроқ қайта уриниб кўринг.';

  @override
  void initState() {
    super.initState();
    unawaited(_loadPlatform());
    unawaited(_loadShopItems());
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
    _searchCtrl.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchCtrl.clear();
    setState(() => _query = '');
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
    var list = List<TvShopItem>.from(_shopItems);
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
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Менинг эълонларим',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyAdsScreen()),
              );
            },
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
                    onChanged: (v) => setState(() => _query = v),
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
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: _addRed,
                  elevation: 4,
                  shadowColor: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CreateAdScreen(),
                        ),
                      );
                    },
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<AdModel>>(
              stream: repo.searchActiveAds(_query),
              builder: (context, snap) {
                if ((snap.connectionState == ConnectionState.waiting &&
                        !snap.hasData) ||
                    !_platformLoaded ||
                    !_shopLoaded) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  _logFirestoreError(snap.error!, snap.stackTrace);
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _loadErrorMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: AppText.bodyLarge,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  );
                }

                final ads = snap.data ?? const <AdModel>[];
                final platform = _filteredPlatform();
                final shop = _filteredShop();
                final found = platform.length + ads.length + shop.length;

                if (platform.isEmpty && ads.isEmpty && shop.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        CatalogSearch.normalize(_query).isEmpty
                            ? 'Ҳозирча эълонлар йўқ'
                            : context
                                .tr('platform_store_search_none')
                                .replaceAll('{query}', _query.trim()),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: AppText.bodyLarge,
                          color: Colors.grey.shade700,
                        ),
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
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.75,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: entries.length,
                        itemBuilder: (_, i) {
                          final e = entries[i];
                          if (e.platform != null) {
                            return PlatformMarketCard(product: e.platform!);
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
                                    builder: (_) => TvShopItemDetailScreen(
                                      item: item,
                                      onOpenShop: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => TvShopPublicScreen(
                                              ownerPhone: item.ownerPhone,
                                              highlightItemId: item.id,
                                              ownerDisplayName: item.ownerName,
                                              districtLabel: item.districtLabel,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                );
                              },
                            );
                          }
                          return AdCard(ad: e.ad!);
                        },
                      ),
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
