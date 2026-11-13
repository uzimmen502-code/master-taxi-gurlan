import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../models/wholesale_product.dart';
import '../models/wholesale_seller.dart';
import '../repositories/wholesale_sellers_repository.dart';
import '../screens/wholesale_seller_products_screen.dart' show WholesaleStoreHeader;
import '../utils/wholesale_store.dart';

/// Улгуржи «Сотувчилар» таби (эга, 2026-11-13, 2-босқич): фақат тасдиқланган
/// ва шу бозорда камида битта фаол маҳсулоти бор сотувчилар.
///
/// Сотувчилар бозор лентасидаги (аллақачон юкланган) фаол маҳсулотлардан
/// олинади — алоҳида «ҳамма сотувчилар» сўрови йўқ (37-банд); фақат етишмаган
/// сотувчи ҳужжатлари 30 тадан бир марта ўқилади ва шу экранда сақланади.
class WholesaleSellersList extends StatefulWidget {
  const WholesaleSellersList({
    super.key,
    required this.products,
    required this.market,
    required this.query,
    required this.onOpen,
    this.loader,
  });

  final List<WholesaleProduct> products;
  final String market;
  final String query;
  final ValueChanged<WholesaleSeller> onOpen;

  /// Тестда Firestore ўрнига.
  final Future<Map<String, WholesaleSeller>> Function(Iterable<String> ids)? loader;

  @override
  State<WholesaleSellersList> createState() => _WholesaleSellersListState();
}

class _WholesaleSellersListState extends State<WholesaleSellersList> {
  final Map<String, WholesaleSeller> _sellers = {};
  final Set<String> _requested = {};
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadMissing();
  }

  @override
  void didUpdateWidget(covariant WholesaleSellersList old) {
    super.didUpdateWidget(old);
    if (!identical(old.products, widget.products)) _loadMissing();
  }

  /// [initState]/[didUpdateWidget] дан чақирилганда ҳолат тўғридан-тўғри
  /// ёзилади (кейин build барибир бўлади), тугмадан — `setState` билан.
  Future<void> _loadMissing({bool fromLifecycle = true}) async {
    final ids = widget.products.map((p) => p.sellerId).where((id) => id.trim().isNotEmpty).toSet()
      ..removeAll(_requested);
    if (ids.isEmpty) return;
    _requested.addAll(ids);
    void mark() {
      _loading = true;
      _failed = false;
    }

    fromLifecycle ? mark() : setState(mark);
    try {
      final got = await (widget.loader ?? WholesaleSellersRepository().fetchByIds)(ids);
      if (!mounted) return;
      setState(() {
        _sellers.addAll(got);
        _loading = false;
      });
    } catch (e) {
      debugPrint('[WholesaleSellers] $e');
      _requested.removeAll(ids);
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stores = filterStores(
      buildStoreSummaries(widget.products, _sellers, market: widget.market),
      widget.query,
      (s) => WholesaleStoreHeader.metaLine(context, s),
    );
    if (stores.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront_outlined, size: 48, color: AppColors.sectionMuted),
              const SizedBox(height: 12),
              Text(
                context.tr(_failed ? 'wholesale_action_failed' : 'wholesale_sellers_empty'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (_failed)
                TextButton(
                  onPressed: () => _loadMissing(fromLifecycle: false),
                  child: Text(context.tr('home_section_retry')),
                ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
      itemCount: stores.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
      itemBuilder: (context, i) {
        final e = stores[i];
        final s = e.seller;
        final meta = WholesaleStoreHeader.metaLine(context, s);
        final count = context.tr('wholesale_store_products_count').replaceAll('{n}', '${e.productCount}');
        return ListTile(
          key: ValueKey('wholesale-seller-row-${s.phone}'),
          minVerticalPadding: 10,
          leading: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              storeInitials(s.companyName),
              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primaryText),
            ),
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  s.companyName.trim().isEmpty ? context.tr('wholesale_seller_label') : s.companyName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.verified, size: 16, color: Color(0xFF2E9E5B)),
            ],
          ),
          subtitle: Text(
            [if (meta.isNotEmpty) meta, count].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => widget.onOpen(s),
        );
      },
    );
  }
}
