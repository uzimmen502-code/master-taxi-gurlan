import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/platform_product.dart';
import '../../../repositories/platform_products_repository.dart';
import '../models/ad_model.dart';
import '../repositories/ads_repository.dart';
import '../utils/ad_search_text.dart';
import '../widgets/ad_card.dart';
import '../widgets/platform_market_card.dart';
import 'create_ad_screen.dart';
import 'my_ads_screen.dart';

enum _MarketScope { all, platform, private }

/// Feed of cheap product listings with search, price filter and sort.
class CheapProductsScreen extends StatefulWidget {
  const CheapProductsScreen({super.key});

  @override
  State<CheapProductsScreen> createState() => _CheapProductsScreenState();
}

class _CheapProductsScreenState extends State<CheapProductsScreen> {
  final _searchCtrl = TextEditingController();
  final _minPriceCtrl = TextEditingController();
  final _maxPriceCtrl = TextEditingController();
  final _platformRepo = PlatformProductsRepository();
  Timer? _debounce;
  String _searchQuery = '';
  int? _minPrice;
  int? _maxPrice;
  AdSortMode _sort = AdSortMode.newest;
  bool _showPriceFilter = false;
  _MarketScope _scope = _MarketScope.all;
  List<PlatformProduct> _platform = const [];
  bool _platformLoaded = false;

  static const _loadErrorMessage =
      'Маълумотларни юклашда хатолик юз берди. Илтимос кейинроқ қайта уриниб кўринг.';

  @override
  void initState() {
    super.initState();
    unawaited(_loadPlatform());
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
    _minPriceCtrl.dispose();
    _maxPriceCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _searchQuery = value.trim());
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    setState(() => _searchQuery = '');
  }

  void _applyPriceFilter() {
    int? parse(String raw) {
      final t = raw.trim().replaceAll(RegExp(r'\s+'), '');
      if (t.isEmpty) return null;
      return int.tryParse(t);
    }

    var minP = parse(_minPriceCtrl.text);
    var maxP = parse(_maxPriceCtrl.text);
    if (minP != null && maxP != null && minP > maxP) {
      final tmp = minP;
      minP = maxP;
      maxP = tmp;
      _minPriceCtrl.text = '$minP';
      _maxPriceCtrl.text = '$maxP';
    }
    setState(() {
      _minPrice = minP;
      _maxPrice = maxP;
    });
  }

  void _clearPriceFilter() {
    _minPriceCtrl.clear();
    _maxPriceCtrl.clear();
    setState(() {
      _minPrice = null;
      _maxPrice = null;
    });
  }

  bool get _hasPriceFilter => _minPrice != null || _maxPrice != null;

  List<PlatformProduct> _filteredPlatform() {
    var list = _platform.where((p) {
      if (p.price <= 0) return false;
      if (_minPrice != null && p.price < _minPrice!) return false;
      if (_maxPrice != null && p.price > _maxPrice!) return false;
      if (_searchQuery.length >= 2) {
        final hay = '${p.name} ${p.description}'.toLowerCase();
        final tokens = AdSearchText.queryTokens(_searchQuery);
        if (tokens.isEmpty) return true;
        return tokens.every((t) => hay.contains(t.toLowerCase()));
      }
      return true;
    }).toList();

    switch (_sort) {
      case AdSortMode.cheapest:
        list.sort((a, b) => a.price.compareTo(b.price));
      case AdSortMode.expensive:
        list.sort((a, b) => b.price.compareTo(a.price));
      case AdSortMode.mostViewed:
      case AdSortMode.newest:
        list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AdsRepository>();

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: const Text('Арзон маҳсулотлар'),
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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Қидириш (масалан: олма, kartoshka)...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: _clearSearch,
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: _hasPriceFilter || _showPriceFilter
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () =>
                        setState(() => _showPriceFilter = !_showPriceFilter),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(
                        Icons.tune,
                        color: _hasPriceFilter
                            ? AppColors.primary
                            : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: AppColors.primary,
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
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary,
                          width: 1,
                        ),
                      ),
                      child: const Icon(
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
          if (_showPriceFilter)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minPriceCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        hintText: 'Мин нарх',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _applyPriceFilter(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _maxPriceCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        hintText: 'Макс нарх',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _applyPriceFilter(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: _applyPriceFilter,
                    child: const Text('OK'),
                  ),
                  if (_hasPriceFilter)
                    IconButton(
                      tooltip: 'Нархни тозалаш',
                      onPressed: _clearPriceFilter,
                      icon: const Icon(Icons.clear, size: 20),
                    ),
                ],
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Row(
              children: [
                _SortChip(
                  label: 'Ҳаммаси',
                  selected: _scope == _MarketScope.all,
                  onTap: () => setState(() => _scope = _MarketScope.all),
                ),
                _SortChip(
                  label: 'AVA',
                  selected: _scope == _MarketScope.platform,
                  onTap: () => setState(() => _scope = _MarketScope.platform),
                ),
                _SortChip(
                  label: 'Хусусий',
                  selected: _scope == _MarketScope.private,
                  onTap: () => setState(() => _scope = _MarketScope.private),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                _SortChip(
                  label: 'Янги',
                  selected: _sort == AdSortMode.newest,
                  onTap: () => setState(() => _sort = AdSortMode.newest),
                ),
                _SortChip(
                  label: 'Арзон',
                  selected: _sort == AdSortMode.cheapest,
                  onTap: () => setState(() => _sort = AdSortMode.cheapest),
                ),
                _SortChip(
                  label: 'Қиммат',
                  selected: _sort == AdSortMode.expensive,
                  onTap: () => setState(() => _sort = AdSortMode.expensive),
                ),
                _SortChip(
                  label: 'Кўп кўрилган',
                  selected: _sort == AdSortMode.mostViewed,
                  onTap: () => setState(() => _sort = AdSortMode.mostViewed),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<AdModel>>(
              stream: repo.searchActiveAds(
                _searchQuery,
                minPrice: _minPrice,
                maxPrice: _maxPrice,
                sort: _sort,
              ),
              builder: (context, snap) {
                if ((snap.connectionState == ConnectionState.waiting &&
                        !snap.hasData) ||
                    !_platformLoaded) {
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
                final showPlatform = _scope != _MarketScope.private;
                final showPrivate = _scope != _MarketScope.platform;
                final platformItems =
                    showPlatform ? platform : const <PlatformProduct>[];
                final privateItems = showPrivate ? ads : const <AdModel>[];

                if (platformItems.isEmpty && privateItems.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _searchQuery.isEmpty && !_hasPriceFilter
                            ? 'Ҳозирча эълонлар йўқ'
                            : 'Қидирув бўйича ҳеч қандай эълон топилмади',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: AppText.bodyLarge,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  );
                }

                // AVA юқорида (витрина), кейин хусусий.
                final entries = <_MarketEntry>[
                  ...platformItems.map(_MarketEntry.platform),
                  ...privateItems.map(_MarketEntry.ad),
                ];

                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                    return AdCard(ad: e.ad!);
                  },
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
  const _MarketEntry._({this.ad, this.platform});
  factory _MarketEntry.ad(AdModel ad) => _MarketEntry._(ad: ad);
  factory _MarketEntry.platform(PlatformProduct p) =>
      _MarketEntry._(platform: p);

  final AdModel? ad;
  final PlatformProduct? platform;
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.primary.withValues(alpha: 0.2),
        labelStyle: TextStyle(
          color: selected ? AppColors.primary : Colors.grey.shade800,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
        side: BorderSide(
          color: selected ? AppColors.primary : Colors.grey.shade300,
        ),
        backgroundColor: Colors.white,
      ),
    );
  }
}
