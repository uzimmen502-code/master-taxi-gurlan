import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/realty_listing.dart';
import '../../ads/models/ad_model.dart';
import '../../ads/screens/ad_details_route.dart';
import '../../realty/screens/realty_detail_screen.dart';
import '../../tv_market/domain/price_unit.dart';
import '../../tv_market/models/tv_shop.dart';
import '../../tv_market/screens/tv_shop_item_detail_screen.dart';
import '../../wholesale/models/wholesale_product.dart';
import '../../wholesale/screens/wholesale_product_detail_screen.dart';
import '../domain/favorite_ref.dart';
import '../favorites_controller.dart';
import '../widgets/favorite_heart.dart';

/// Фильтр чиплари (манба бўйича). Улгуржи ва Хитой — битта коллекция, `market` бўйича ажратилади.
enum FavoriteSource { markets, aralash, ulgurji, china, realty }

FavoriteSource favoriteSourceOf(FavoriteRef f) {
  switch (f.collection) {
    case FavoriteCollections.tvShopItems:
      return FavoriteSource.markets;
    case FavoriteCollections.wholesaleProducts:
      return f.market == WholesaleProduct.marketChina ? FavoriteSource.china : FavoriteSource.ulgurji;
    case FavoriteCollections.realtyListings:
      return FavoriteSource.realty;
    default:
      return FavoriteSource.aralash;
  }
}

String favoriteSourceKey(FavoriteSource s) => switch (s) {
      FavoriteSource.markets => 'fav_src_markets',
      FavoriteSource.aralash => 'fav_src_aralash',
      FavoriteSource.ulgurji => 'fav_src_ulgurji',
      FavoriteSource.china => 'fav_src_china',
      FavoriteSource.realty => 'fav_src_realty',
    };

/// Элемент ҳолати экранда: манба ҳужжати текширилмоқда / мавжуд / мавжуд эмас.
enum FavoriteAvailability { checking, available, unavailable }

FavoriteAvailability favoriteAvailabilityOf(String key, Map<String, Map<String, dynamic>?> sources, {DateTime? now}) {
  if (!sources.containsKey(key)) return FavoriteAvailability.checking;
  return favoriteSourceAvailable(sources[key], now: now)
      ? FavoriteAvailability.available
      : FavoriteAvailability.unavailable;
}

/// «Танланганлар» (эга 2026-11-15): барча бозорлар бир рўйхатда, манба чиплари; ўчирилган/муддати
/// ўтган/рад этилган/блокланган/нофаол элемент — «Мавжуд эмас» (кулранг) + олиб ташлаш.
/// Манба ҳужжатлари ФАҚАТ шу экран очилганда, бўлаклаб ўқилади.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key, this.controller});

  final FavoritesController? controller;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  FavoritesController get _c => widget.controller ?? FavoritesController.instance;

  final Map<String, Map<String, dynamic>?> _sources = {};
  final Set<String> _requested = {};
  FavoriteSource? _filter;

  @override
  void initState() {
    super.initState();
    _c.ensureStarted();
    _c.addListener(_fetchMissing);
    _fetchMissing();
  }

  @override
  void dispose() {
    _c.removeListener(_fetchMissing);
    super.dispose();
  }

  /// Рўйхатда янги пайдо бўлган (ёки аввал тармоқ хатоси бўлган) элементлар учунгина ўқиш.
  Future<void> _fetchMissing() async {
    final missing = _c.items.where((f) => !_requested.contains(f.key) && f.isValid).toList();
    if (missing.isEmpty) return;
    _requested.addAll(missing.map((f) => f.key));
    final got = await _c.fetchSources(missing);
    if (!mounted) return;
    setState(() {
      _sources.addAll(got);
      // Аниқланмаганлар (тармоқ) — кейинги ўзгаришда қайта уринилади.
      for (final f in missing) {
        if (!got.containsKey(f.key)) _requested.remove(f.key);
      }
    });
  }

  void _open(FavoriteRef f) {
    final d = _sources[f.key];
    if (d == null) return;
    final Widget page;
    switch (f.collection) {
      case FavoriteCollections.tvShopItems:
        page = TvShopItemDetailScreen(item: TvShopItem.fromMap(f.itemId, d), showShopButton: true);
      case FavoriteCollections.wholesaleProducts:
        page = WholesaleProductDetailScreen(product: WholesaleProduct.fromMap(f.itemId, d));
      case FavoriteCollections.realtyListings:
        page = RealtyDetailScreen(listing: RealtyListing.fromMap(f.itemId, d));
      default:
        page = adDetailsFor(AdModel.fromMap(f.itemId, d), const []);
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _remove(FavoriteRef f) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.tr('fav_toggle_failed');
    final ok = await _c.remove(f.key);
    if (!ok && mounted) messenger.showSnackBar(SnackBar(content: Text(failed)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('fav_title'))),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final all = _c.items.where((f) => _c.isFavorite(f.key)).toList();
          if (all.isEmpty) {
            return Center(
              key: const ValueKey('fav_empty'),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.favorite_border_rounded, size: 48),
                  const SizedBox(height: 12),
                  Text(context.tr('fav_empty'), textAlign: TextAlign.center),
                ]),
              ),
            );
          }
          final present = <FavoriteSource>{for (final f in all) favoriteSourceOf(f)};
          final filter = present.contains(_filter) ? _filter : null;
          final shown = filter == null ? all : all.where((f) => favoriteSourceOf(f) == filter).toList();
          return Column(children: [
            if (present.length > 1)
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: [
                    _chip('fav_chip_all', context.tr('fav_src_all'), filter == null, () => setState(() => _filter = null)),
                    for (final s in FavoriteSource.values)
                      if (present.contains(s))
                        _chip('fav_chip_${s.name}', context.tr(favoriteSourceKey(s)), filter == s,
                            () => setState(() => _filter = s)),
                  ],
                ),
              ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                itemCount: shown.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _row(shown[i]),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _chip(String key, String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(key: ValueKey(key), label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );

  String _priceLine(FavoriteRef f, Map<String, dynamic>? d) {
    final tr = context.tr;
    if (d != null) {
      switch (f.collection) {
        case FavoriteCollections.tvShopItems:
          return TvShopItem.fromMap(f.itemId, d).priceLabel(tr);
        case FavoriteCollections.wholesaleProducts:
          return WholesaleProduct.fromMap(f.itemId, d).priceLine;
        case FavoriteCollections.realtyListings:
          return RealtyListing.fromMap(f.itemId, d).priceText;
        default:
          final p = AdModel.fromMap(f.itemId, d).price;
          return p > 0 ? formatOfferPrice(p, PriceUnit.fixed, tr) : '';
      }
    }
    final p = f.price;
    return p == null || p <= 0 ? '' : formatOfferPrice(p, PriceUnit.fromWire(f.priceUnit), tr);
  }

  Widget _row(FavoriteRef f) {
    final c = context.ava;
    final state = favoriteAvailabilityOf(f.key, _sources);
    final unavailable = state == FavoriteAvailability.unavailable;
    final d = state == FavoriteAvailability.available ? _sources[f.key] : null;
    final price = unavailable ? '' : _priceLine(f, d);
    final photo = Opacity(
      opacity: unavailable ? 0.4 : 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 64,
          height: 64,
          child: f.photoUrl.isEmpty
              ? ColoredBox(color: c.surface2, child: const Icon(Icons.image_outlined))
              : CachedNetworkImage(
                  imageUrl: f.photoUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => ColoredBox(color: c.surface2, child: const Icon(Icons.image_outlined)),
                ),
        ),
      ),
    );
    return Card(
      key: ValueKey('fav_row_${f.key}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: state == FavoriteAvailability.available ? () => _open(f) : null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            photo,
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  f.title.isEmpty ? '—' : f.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, color: unavailable ? c.ink3 : c.ink),
                ),
                const SizedBox(height: 2),
                if (unavailable)
                  Text(context.tr('fav_unavailable'),
                      key: ValueKey('fav_unavailable_${f.key}'),
                      style: TextStyle(color: c.ink3, fontWeight: FontWeight.w700, fontSize: 12))
                else if (price.isNotEmpty)
                  Text(price, style: TextStyle(color: c.ink, fontWeight: FontWeight.w800)),
                Text(context.tr(favoriteSourceKey(favoriteSourceOf(f))),
                    style: TextStyle(color: c.ink2, fontSize: 11)),
              ]),
            ),
            if (unavailable)
              IconButton(
                key: ValueKey('fav_remove_${f.key}'),
                tooltip: context.tr('fav_remove'),
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => _remove(f),
              )
            else
              FavoriteHeart(favorite: f, overlay: false, controller: _c),
          ]),
        ),
      ),
    );
  }
}
