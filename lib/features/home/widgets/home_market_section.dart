import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'dart:math';

import '../../../core/brand_labels.dart';
import '../../../core/geo/geo_names.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/geo/geo_context.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../core/utils/fair_mix.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/session_shuffle.dart';
import '../../../models/platform_product.dart';
import '../../../repositories/platform_products_repository.dart';
import '../../ads/models/ad_model.dart';
import '../../ads/repositories/ads_repository.dart';
import '../../ads/widgets/market_corner_badge.dart';
import '../../ads/widgets/platform_market_card.dart' show platformShelfPrice;
import '../../wholesale/models/wholesale_product.dart';
import '../../wholesale/repositories/wholesale_products_repository.dart';
import 'home_wholesale_section.dart' show formatShelfPrice;
import 'ava_list_row.dart';
import 'ava_section.dart';

/// 6-бўлим: «Аҳоли бозори» — ён томонга айланадиган расмли карточкалар.
///
/// 2-бўлим билан ТАКРОРЛАНМАЙДИ: у ерда `type` `ad`/`service`, бу ерда
/// `cheap_product` — битта ҳужжат иккала рўйхатга туша олмайди.
class HomeMarketSection extends StatefulWidget {
  const HomeMarketSection({
    super.key,
    required this.onOpenAll,
    required this.onOpenAd,
    this.onOpenPlatform,
    this.onOpenWholesale,
  });

  /// Улгуржи / Хитой бозори маҳсулоти босилди (эга, 2026-11-13: улар бош
  /// саҳифадаги Аралаш бўлимида ҳам; босилса — ўша бозор, орқага — асосий
  /// экран). [shelf] — шу бозорнинг бўлимдаги маҳсулотлари. `null` — кўрсатилмайди.
  final void Function(WholesaleProduct product, List<WholesaleProduct> shelf)? onOpenWholesale;

  /// Ҳар бир бозордан (Улгуржи, Хитой) олинадиган сони (бош саҳифа — енгил, 37-банд).
  static const wholesaleLimit = 10;

  final VoidCallback onOpenAll;
  /// Босилган эълон ва бўлимдаги БАРЧА эълонлар (тафсилотда суриб ўтиш учун).
  final void Function(AdModel ad, List<AdModel> shelf) onOpenAd;

  /// AVA маҳсулоти (`platform_products`) босилди (эга, 2026-11-03: AVA
  /// маҳсулотлари бош саҳифадаги Аралаш бўлимида ҳам). `null` — AVA йўқ.
  final void Function(PlatformProduct product)? onOpenPlatform;

  /// Икки қатор тўлиши учун 5 эмас, 10 та (қаранг: [AvaProductShelf]).
  static const limit = 10;

  /// AVA маҳсулотлари: индексли `active + sortOrder` сўрови (бош саҳифа бутун
  /// каталогни ўқимасин, 37-қоида); қоидаси Аралаш бозор экрани билан бир хил.
  static const platformLimit = 20;

  @override
  State<HomeMarketSection> createState() => _HomeMarketSectionState();
}

class _HomeMarketSectionState extends State<HomeMarketSection> {
  final _repo = AdsRepository();
  final _scroll = ScrollController();
  final Random _rnd = sessionRandom();
  StreamSubscription<List<AdModel>>? _sub;

  AvaSectionStatus _status = AvaSectionStatus.loading;
  List<AdModel> _items = const [];

  /// Чексиз скролл: охирига яқинлашганда яна шунча сўралади.
  int _limit = HomeMarketSection.limit;
  bool _endReached = false;

  final _platformRepo = PlatformProductsRepository();
  List<PlatformProduct> _platform = const [];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _listen();
    if (widget.onOpenPlatform != null) unawaited(_loadPlatform());
    if (widget.onOpenWholesale != null) {
      unawaited(_loadWholesale(WholesaleProduct.marketChina));
      unawaited(_loadWholesale(WholesaleProduct.marketWholesale));
    }
  }

  List<WholesaleProduct> _china = const [];
  List<WholesaleProduct> _ulgurji = const [];

  /// AVA нусхалари (`pp_*`) чиқариб ташланади — AVA асли [_platform] да бор.
  Future<void> _loadWholesale(String market) async {
    try {
      final list = await WholesaleProductsRepository()
          .getActiveProducts(limit: HomeMarketSection.wholesaleLimit, market: market)
          .first;
      if (!mounted) return;
      final eligible = WholesaleProduct.forAralash(list);
      setState(() {
        if (market == WholesaleProduct.marketChina) {
          _china = eligible;
        } else {
          _ulgurji = eligible;
        }
        if (eligible.isNotEmpty && _status == AvaSectionStatus.empty) {
          _status = AvaSectionStatus.ready;
        }
      });
    } catch (e) {
      // Юкланмаса ҳам бўлим эълонлар билан ишлайди.
      debugPrint('[HomeMarket] $market $e');
    }
  }

  Future<void> _loadPlatform() async {
    try {
      final list = await _platformRepo.fetchActive(limit: HomeMarketSection.platformLimit);
      if (!mounted) return;
      setState(() {
        _platform = PlatformProductsRepository.marketEligible(list);
        if (_platform.isNotEmpty && _status == AvaSectionStatus.empty) {
          _status = AvaSectionStatus.ready;
        }
      });
    } catch (e) {
      // AVA юкланмаса ҳам бўлим эълонлар билан ишлайди.
      debugPrint('[HomeMarket] platform $e');
    }
  }

  void _onScroll() {
    if (_endReached || !_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels < pos.maxScrollExtent - 240) return;
    _limit += HomeMarketSection.limit;
    _listen(initial: false);
  }

  void _listen({bool initial = true}) {
    _sub?.cancel();
    if (initial && mounted) {
      setState(() => _status = AvaSectionStatus.loading);
    }
    // Модул танлови (туман/вилоят/Республика, D-GEO-1) — модул экрани
    // билан бир хил. Аввал бош саҳифа туман, «Барчаси» Республика эди.
    _sub = _repo
        .watchScoped(GeoContext.homeScopeFor('cheap_products_home'), limit: _limit)
        .listen(
      (list) {
        if (!mounted) return;
        setState(() {
          // Аввал кўрсатилганлар ўрнида қолади, янгилари аралашиб
          // охирига қўшилади (сеанс уруғи — ҳар очилишда бошқа тартиб).
          _items = mergeShuffled(
            current: _items,
            incoming: list,
            idOf: (a) => a.id,
            random: _rnd,
          );
          _endReached = list.length < _limit;
          _status = _items.isEmpty && _platform.isEmpty && _china.isEmpty && _ulgurji.isEmpty
              ? AvaSectionStatus.empty
              : AvaSectionStatus.ready;
        });
      },
      onError: (Object e) {
        debugPrint('[HomeMarket] $e');
        if (mounted) setState(() => _status = AvaSectionStatus.error);
      },
    );
  }

  /// Эълон туманининг номи — фақат ўша туман кўриниб турган бўлса маълум.
  String? _districtNote(String districtId) {
    final area = GeoContext.homeScopeFor('cheap_products_home').area;
    return districtId.isNotEmpty && districtId == area.districtId
        ? GeoNames.district(districtId, context.contentLang, fallback: area.districtLabel)
        : null;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Баландлик ҳақиқий мазмундан (ном 1 қатор, туман изоҳи) ҳисобланади.
    // Навбатма-навбат: эълон ва AVA маҳсулоти (Аралаш бозор экранидаги каби).
    final entries = FairMix.roundRobin<Object>([
      _items,
      _platform,
      _china,
      _ulgurji,
    ]);
    final hasWholesale = _china.isNotEmpty || _ulgurji.isNotEmpty;
    final hasFoot = _platform.isNotEmpty ||
        hasWholesale ||
        _items.any((a) => (_districtNote(a.districtId) ?? '').isNotEmpty);
    final hasPrice = _platform.isNotEmpty || hasWholesale || _items.any((a) => a.price > 0);
    return AvaSection(
      moduleId: 'cheap_products_home',
      title: context.tr('home_section_cheap_products'),
      status: _status,
      onSeeAll: widget.onOpenAll,
      onRetry: _listen,
      skeletonRows: 1,
      // Икки қатор, ёнга скролл (қаранг: [AvaProductShelf]).
      child: AvaProductShelf(
        // Бу бўлимда нарх изоҳи йўқ — қолгани `avaTileListHeight` изоҳида.
        rowHeight: avaTileListHeight(
          context,
          titleLines: 1,
          hasPrice: hasPrice,
          hasPriceNote: false,
          hasFootnote: hasFoot,
        ),
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final e = entries[i];
          if (e is PlatformProduct) return _platformTile(e);
          if (e is WholesaleProduct) return _wholesaleTile(e);
          final ad = e as AdModel;
          final cover = ad.imageUrls.isEmpty ? '' : ad.imageUrls.first;
          return AvaTileCard(
            titleMaxLines: 1,
            title: ad.title,
            price: ad.price > 0
                ? '${formatPrice(ad.price)} $kCurrencySum'
                : null,
            // Эълоннинг ЎЗ тумани (аввал кўраётганнинг тумани ёзиларди —
            // ҳудудсиз эски эълонлар ҳам «Гурлан» кўринарди, geo аудит).
            footnote: _districtNote(ad.districtId),
            // Нусха: тафсилот очиқ турганда бўлим янги эълон қўшса, суриш
            // рўйхати силжиб кетмасин.
            onTap: () => widget.onOpenAd(ad, List<AdModel>.of(_items)),
            image: cover.startsWith('http')
                ? ColoredBox(
                    color: context.ava.surface2,
                    child: CachedNetworkImage(
                      imageUrl: cover,
                      // contain: расм четлари қирқилмайди (ега 2026-10-19).
                      fit: BoxFit.contain,
                      // Юкланмаса бўш жой эмас, ўрин эгаси (бозор лентасидаги каби).
                      errorWidget: (_, __, ___) => Icon(
                        Icons.broken_image,
                        color: context.ava.ink3,
                      ),
                    ),
                  )
                : null,
          );
        },
      ),
    );
  }

  /// AVA маҳсулоти — пастки қаторда «AVA» (Улгуржи бўлимидаги каби).
  Widget _platformTile(PlatformProduct p) {
    final price = platformShelfPrice(p);
    final cover = p.coverImageUrl.trim();
    Widget? image;
    if (isHttpImageUrl(cover)) {
      image = ColoredBox(
        color: context.ava.surface2,
        child: CachedNetworkImage(imageUrl: cover, fit: BoxFit.contain),
      );
    } else if (isDataImageUrl(cover)) {
      final bytes = decodeDataUrlImageBytes(cover);
      if (bytes != null) {
        image = ColoredBox(
          color: context.ava.surface2,
          child: Image.memory(bytes, fit: BoxFit.contain),
        );
      }
    }
    return AvaTileCard(
      titleMaxLines: 1,
      title: p.name,
      price: price.price,
      footnote: BrandLabels.brand,
      onTap: () => widget.onOpenPlatform?.call(p),
      // Аралаш бозор экранидаги каби тепа ўнгда «Улгуржи» (эга, 2026-11-13).
      image: _withBadge(image, context.tr('wholesale_screen_title')),
    );
  }

  /// Улгуржи / Хитой маҳсулоти — тепа ўнгда бозор номи, нархи ўз валютасида.
  Widget _wholesaleTile(WholesaleProduct p) {
    final isChina = p.market == WholesaleProduct.marketChina;
    final cover = p.imageUrls.isEmpty ? '' : p.imageUrls.first;
    final image = cover.startsWith('http')
        ? ColoredBox(
            color: context.ava.surface2,
            child: CachedNetworkImage(imageUrl: cover, fit: BoxFit.contain),
          )
        : null;
    return AvaTileCard(
      titleMaxLines: 1,
      title: p.title,
      price: formatShelfPrice(p),
      footnote: p.sellerCompanyName,
      onTap: () => widget.onOpenWholesale?.call(p, List<WholesaleProduct>.of(isChina ? _china : _ulgurji)),
      image: _withBadge(image, context.tr(isChina ? 'wholesale_screen_title_china' : 'wholesale_screen_title')),
    );
  }

  Widget _withBadge(Widget? image, String badge) => Stack(
        fit: StackFit.expand,
        children: [
          image ?? ColoredBox(color: context.ava.surface2),
          MarketCornerBadge(text: badge),
        ],
      );
}
