import 'package:flutter/material.dart';

import '../../../core/geo/geo_names.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../ads/widgets/market_grid.dart';
import '../models/wholesale_product.dart';
import '../models/wholesale_seller.dart';
import '../repositories/wholesale_products_repository.dart';
import '../repositories/wholesale_sellers_repository.dart';
import '../utils/wholesale_store.dart';
import '../widgets/wholesale_product_card.dart';
import '../widgets/wholesale_stream_builder.dart';
import 'wholesale_product_detail_screen.dart';

/// Сотувчи магазини (эга, 2026-11-13, 1-босқич; аввал фақат «барча
/// маҳсулотлари» рўйхати эди): тепада ном, ✓ (тасдиқланган), тури, шаҳар,
/// маҳсулотлар сони ва AVA'даги санаси, қўнғироқ; пастда магазин ичида
/// қидириш ва маҳсулотлар (доим янгиси биринчи — тартиблаш тугмалари йўқ).
///
/// Аниқ манзил ва харита нуқтаси КЎРСАТИЛМАЙДИ — фақат вилоят/туман (40-банд).
/// [market] сотувчининг шу бозордаги товарларини қолдиради.
class WholesaleSellerProductsScreen extends StatefulWidget {
  const WholesaleSellerProductsScreen({
    super.key,
    required this.sellerId,
    required this.sellerName,
    this.market,
    this.streamFactory,
    this.sellerLoader,
  });

  final String sellerId;
  final String sellerName;
  final String? market;

  /// Тестда Firestore ўрнига сохта оқим учун (ҳар уланишда янги оқим).
  final Stream<List<WholesaleProduct>> Function()? streamFactory;

  /// Тестда сотувчи ҳужжати ўрнига.
  final Future<WholesaleSeller?> Function()? sellerLoader;

  @override
  State<WholesaleSellerProductsScreen> createState() =>
      _WholesaleSellerProductsScreenState();
}

class _WholesaleSellerProductsScreenState
    extends State<WholesaleSellerProductsScreen> {
  Stream<List<WholesaleProduct>>? _stream;
  // Future.sync — Firestore синхрон хатоси (масалан, ишга туширилмаган) ҳам ушлансин.
  late final Future<WholesaleSeller?> _seller = Future<WholesaleSeller?>.sync(widget.sellerLoader ??
          () => WholesaleSellersRepository().fetchByPhone(widget.sellerId))
      .catchError((Object e) {
    // Сотувчи ўқилмаса ҳам маҳсулотлар кўринаверсин (тепада фақат ном).
    debugPrint('[WholesaleStore] seller $e');
    return null;
  });

  String _query = '';

  Stream<List<WholesaleProduct>> _items() =>
      _stream ??= widget.streamFactory?.call() ??
          WholesaleProductsRepository()
              .watchActiveBySeller(widget.sellerId, market: widget.market);

  Future<void> _call() async {
    final ok = await callPhone(widget.sellerId);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('wholesale_call_failed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.sellerName.trim().isEmpty
        ? context.tr('wholesale_seller_label')
        : widget.sellerName.trim();
    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: WholesaleStreamBuilder<List<WholesaleProduct>>(
        stream: _items(),
        // Firestore stream хатодан кейин ёпилади: қайта улаймиз.
        onRetry: () => setState(() => _stream = null),
        builder: (context, data) {
          // Тартиблаш тугмалари йўқ (эга, 2026-11-13, «В»): доим янгиси биринчи —
          // оқим ўзи шу тартибда (`watchActiveBySeller` → `sortActiveSellerProducts`).
          final all = data ?? const <WholesaleProduct>[];
          final shown = WholesaleProductsRepository.filterBySearch(all, _query, limit: all.length);
          return Column(
            children: [
              FutureBuilder<WholesaleSeller?>(
                future: _seller,
                builder: (context, snap) => WholesaleStoreHeader(
                  seller: snap.data,
                  fallbackName: title,
                  productCount: all.length,
                  onCall: widget.sellerId.trim().isEmpty ? null : _call,
                  china: widget.market == WholesaleProduct.marketChina,
                  currencies: {
                    for (final p in all)
                      if (p.currency.trim().isNotEmpty) p.currency.trim(),
                  },
                ),
              ),
              if (all.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                  child: TextField(
                    key: const ValueKey('wholesale-store-search'),
                    onChanged: (v) => setState(() => _query = v),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: context.tr('wholesale_store_search_hint'),
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              Expanded(
                child: shown.isEmpty
                    ? _Empty(textKey: all.isEmpty ? 'wholesale_empty_products' : 'wholesale_store_search_none')
                    : MarketProductGrid(
                        itemCount: shown.length,
                        itemBuilder: (_, i) {
                          final p = shown[i];
                          return WholesaleProductCard(
                            product: p,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => WholesaleProductDetailScreen(
                                  product: p,
                                  catalog: shown,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.textKey});

  final String textKey;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined, size: 48, color: AppColors.sectionMuted),
            const SizedBox(height: 12),
            Text(
              context.tr(textKey),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Магазин тепа қисми. Сотувчи ҳужжати ҳали келмаган/ўқилмаган бўлса —
/// фақат ном ва маҳсулотлар сони (бўш жой эмас).
class WholesaleStoreHeader extends StatelessWidget {
  const WholesaleStoreHeader({
    super.key,
    required this.seller,
    required this.fallbackName,
    required this.productCount,
    this.onCall,
    this.china = false,
    this.currencies = const {},
  });

  final WholesaleSeller? seller;
  final String fallbackName;
  final int productCount;
  final VoidCallback? onCall;

  /// Хитой бозори магазини (эга, 2026-11-13): «🇨🇳 Хитойдан келтириш ·
  /// Ўзбекистонда қабул: …» ва «Нархлар $ да». Етказиш муддати КЎРСАТИЛМАЙДИ —
  /// иловадан ташқарида келишилади (эга).
  final bool china;

  /// Магазиндаги маҳсулотлар валюталари (Хитойда «Нархлар … да» учун).
  final Set<String> currencies;

  static String _place(BuildContext context, WholesaleSeller s) {
    final lang = context.contentLang;
    final region = GeoNames.region(s.regionId, lang);
    final district = GeoNames.district(s.districtId, lang);
    return [region, district].where((e) => e.trim().isNotEmpty).join(', ');
  }

  /// «Ишлаб чиқарувчи · Тошкент шаҳри, Яшнобод» — тури ва ҳудуди (бор бўлгани).
  /// Хитойда: «🇨🇳 Хитойдан келтириш · Ўзбекистонда қабул: Тошкент шаҳри, Яшнобод»
  /// (манзил — мол Ўзбекистонда қабул қилинадиган жой, ишлаб чиқариш жойи эмас).
  static String metaLine(BuildContext context, WholesaleSeller s, {bool china = false}) {
    final place = _place(context, s);
    if (china) {
      // Хитойдаги тури (эга, «Б», алоҳида майдон) бўлса — шу; бўлмаса умумий ёзув.
      final chinaKey = WholesaleSeller.chinaTypeLabelKey(s.chinaSellerType);
      return [
        '🇨🇳 ${context.tr(chinaKey.isNotEmpty ? chinaKey : 'wholesale_store_china_import')}',
        if (place.isNotEmpty) context.tr('wholesale_store_china_receive').replaceAll('{place}', place),
      ].join(' · ');
    }
    final typeKey = WholesaleSeller.typeLabelKey(s.sellerType);
    return [if (typeKey.isNotEmpty) context.tr(typeKey), if (place.isNotEmpty) place].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final s = seller;
    final name = (s?.companyName.trim().isNotEmpty ?? false) ? s!.companyName.trim() : fallbackName;
    final since = storeSinceLabel(s?.approvedAt ?? s?.createdAt);
    final trust = [
      context.tr('wholesale_store_products_count').replaceAll('{n}', '$productCount'),
      if (since.isNotEmpty) context.tr('wholesale_store_since').replaceAll('{date}', since),
    ].join(' · ');
    final meta = s == null ? '' : metaLine(context, s, china: china);
    final currencyNote = china && currencies.isNotEmpty
        ? context.tr('wholesale_store_currency_note').replaceAll('{cur}', (currencies.toList()..sort()).join(', '))
        : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              storeInitials(name),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primaryText),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        key: const ValueKey('wholesale-store-name'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (s?.isApproved ?? false) ...[
                      const SizedBox(width: 4),
                      Tooltip(
                        message: context.tr('wholesale_store_verified'),
                        child: const Icon(
                          Icons.verified,
                          key: ValueKey('wholesale-store-verified'),
                          size: 18,
                          color: Color(0xFF2E9E5B),
                        ),
                      ),
                    ],
                  ],
                ),
                if (meta.isNotEmpty)
                  Text(meta,
                      key: const ValueKey('wholesale-store-meta'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppColors.sectionMuted)),
                Text(trust,
                    key: const ValueKey('wholesale-store-trust'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.sectionMuted)),
                if (currencyNote.isNotEmpty)
                  Text(currencyNote,
                      key: const ValueKey('wholesale-store-currency'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppColors.sectionMuted)),
              ],
            ),
          ),
          if (onCall != null)
            IconButton.outlined(
              key: const ValueKey('wholesale-store-call'),
              tooltip: context.tr('wholesale_call'),
              onPressed: onCall,
              icon: const Icon(Icons.call),
            ),
        ],
      ),
    );
  }
}
