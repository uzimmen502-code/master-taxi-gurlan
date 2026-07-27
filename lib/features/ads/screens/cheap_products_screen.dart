import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

/// Онлайн бозор / Арзон маҳсулотлар: қидирув + лента (AVA + хусусий).
class CheapProductsScreen extends StatefulWidget {
  const CheapProductsScreen({super.key});

  @override
  State<CheapProductsScreen> createState() => _CheapProductsScreenState();
}

class _CheapProductsScreenState extends State<CheapProductsScreen> {
  static const _addRed = Color(0xFFF44336);

  final _searchCtrl = TextEditingController();
  final _platformRepo = PlatformProductsRepository();
  Timer? _debounce;
  String _searchQuery = '';
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

  List<PlatformProduct> _filteredPlatform() {
    final list = _platform.where((p) {
      if (p.price <= 0) return false;
      if (_searchQuery.length >= 2) {
        final hay = '${p.name} ${p.description}'.toLowerCase();
        final tokens = AdSearchText.queryTokens(_searchQuery);
        if (tokens.isEmpty) return true;
        return tokens.every((t) => hay.contains(t.toLowerCase()));
      }
      return true;
    }).toList();
    list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
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
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
              stream: repo.searchActiveAds(_searchQuery),
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

                if (platform.isEmpty && ads.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _searchQuery.isEmpty
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
                  ...platform.map(_MarketEntry.platform),
                  ...ads.map(_MarketEntry.ad),
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
