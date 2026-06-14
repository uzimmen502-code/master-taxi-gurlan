import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../repositories/ads_repository.dart';
import '../widgets/ad_card.dart';
import 'create_ad_screen.dart';
import 'my_ads_screen.dart';

/// Feed of cheap product listings with search.
class CheapProductsScreen extends StatefulWidget {
  const CheapProductsScreen({super.key});

  @override
  State<CheapProductsScreen> createState() => _CheapProductsScreenState();
}

class _CheapProductsScreenState extends State<CheapProductsScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _searchQuery = '';

  static const _migrationPrefsKey = 'cheap_product_title_lower_migrated_v1';

  static const _loadErrorMessage =
      'Маълумотларни юклашда хатолик юз берди. Илтимос кейинроқ қайта уриниб кўринг.';

  void _logFirestoreError(Object error, [StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('CheapProducts Firestore error: $error');
      if (stackTrace != null) {
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runTitleLowerMigration());
  }

  Future<void> _runTitleLowerMigration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_migrationPrefsKey) == true) return;
      if (!mounted) return;
      final n = await context
          .read<AdsRepository>()
          .migrateTitleLowerForCheapProducts();
      await prefs.setBool(_migrationPrefsKey, true);
      if (n > 0 && mounted) {
        debugPrint('Cheap ads titleLower migrated: $n');
      }
    } catch (_) {
      // Non-blocking; admin can run Cloud Function migrateCheapProductTitleLower.
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
                      hintText: 'Қидириш...',
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
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CreateAdScreen()),
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
          Expanded(
            child: StreamBuilder(
              stream: repo.searchActiveAds(_searchQuery),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
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
                final ads = snap.data ?? const [];
                if (ads.isEmpty) {
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
                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: ads.length,
                  itemBuilder: (_, i) => AdCard(ad: ads[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
