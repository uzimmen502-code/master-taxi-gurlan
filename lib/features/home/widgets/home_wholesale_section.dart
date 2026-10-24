import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'dart:math';

import '../../../core/brand_labels.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../core/utils/fair_mix.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/session_shuffle.dart';
import '../../../models/platform_product.dart';
import '../../../repositories/platform_products_repository.dart';
import '../../ads/widgets/platform_market_card.dart' show platformShelfPrice;
import '../../wholesale/models/wholesale_product.dart';
import '../../wholesale/repositories/wholesale_products_repository.dart';
import '../../wholesale/utils/wholesale_labels.dart';
import 'ava_list_row.dart';
import 'ava_section.dart';

/// Нарх поғонасининг қисқа кўриниши: «10+ дона».
///
/// Тавсиф талаби — «нарх поғонаси кўрсатилсин» ва Хитой бозорида
/// «минимал буюртма». Карточкада жой тор бўлгани учун ЭНГ ПАСТ поғона
/// (у айни пайтда минимал буюртма) кўрсатилади; тўлиқ поғоналар
/// маҳсулот саҳифасида.
String formatTierNote(BuildContext context, WholesaleProduct p) {
  if (p.priceTiers.isEmpty) return '';
  final t = p.priceTiers.first;
  return '${t.minQty}+ ${wholesaleUnitLabel(context, p.unit)}';
}

/// Бош саҳифа карточкасидаги нарх: «4 743 $» (нарх йўқ бўлса `null`).
///
/// «дан» ЙЎҚ (эга саволи, 2026-10-08): аввал «дан 4 743 $» ҳар доим
/// чиқарди — (1) ўзбекчада «-дан» қўшимча, сўздан кейин туради (русча
/// «от 4 743» кўчирмаси эди); (2) нарх — биринчи (энг кам миқдор) поғона,
/// яъни «...дан бошлаб» эмас: битта поғонада бошқа нарх йўқ, бир нечтада
/// эса бу энг қиммати. Миқдор остидаги изоҳда — «10+ дона»
/// ([formatTierNote]); тўлиқ поғоналар маҳсулот саҳифасида.
String? formatShelfPrice(WholesaleProduct p) {
  if (p.basePrice <= 0) return null;
  return '${formatPrice(p.basePrice)} ${p.currencyLabel}';
}

/// Хитой бозори учун етказиш муддати: «14 кун». Маълум бўлмаса бўш.
String formatDelivery(BuildContext context, WholesaleProduct p) {
  final d = p.deliveryDays;
  if (d == null || d <= 0) return '';
  return '$d ${context.tr('home_delivery_days')}';
}

/// 7 ва 8-бўлимлар: улгуржи бозори ва Хитой бозори.
///
/// Иккаласи ҳам БИР ХИЛ архитектурада (эга қарори): ўша коллекция, ўша
/// қоидалар, фақат `market` майдони билан ажралади — шунинг учун битта
/// виджет.
class HomeWholesaleSection extends StatefulWidget {
  const HomeWholesaleSection({
    super.key,
    required this.market,
    required this.titleKey,
    required this.onOpenAll,
    required this.onOpenProduct,
    this.onOpenPlatformProduct,
  });

  /// [WholesaleProduct.marketWholesale] ёки [WholesaleProduct.marketChina].
  final String market;
  final String titleKey;

  final VoidCallback onOpenAll;
  final void Function(WholesaleProduct product, List<WholesaleProduct> shelf)
      onOpenProduct;

  /// Берилса — бўлимда AVA товарлари ҳам чиқади (фақат Улгуржида; эга
  /// қарори 2026-10-07: «AVA дўкони энди Улгуржи бозор, бош саҳифада
  /// ҳам чиқсин»). Иккинчи аргумент — бўлимдаги AVA товарлари (тафсилотда
  /// суриб ўтиш учун).
  final void Function(PlatformProduct product, List<PlatformProduct> shelf)?
      onOpenPlatformProduct;

  /// Икки қатор тўлиши учун 5 эмас, 10 та (қаранг: [AvaProductShelf]).
  static const limit = 10;

  /// Бош саҳифада AVA товарларидан нечтаси (тўлиқ рўйхат — «Ҳаммаси»).
  static const platformLimit = 20;

  @override
  State<HomeWholesaleSection> createState() => _HomeWholesaleSectionState();
}

class _HomeWholesaleSectionState extends State<HomeWholesaleSection> {
  final _repo = WholesaleProductsRepository();
  final _scroll = ScrollController();
  final Random _rnd = sessionRandom();
  StreamSubscription<List<WholesaleProduct>>? _sub;

  AvaSectionStatus _status = AvaSectionStatus.loading;
  List<WholesaleProduct> _items = const [];

  /// Чексиз скролл: охирига яқинлашганда яна шунча сўралади.
  int _limit = HomeWholesaleSection.limit;
  bool _endReached = false;

  /// Сотувчилар товари оқими биринчи жавоб бердими / хато бердими.
  bool _sellersLoaded = false;
  bool _sellersFailed = false;

  /// AVA товарлари — бир марта юкланади, тартиби админдаги `sortOrder`.
  final _platformRepo = PlatformProductsRepository();
  List<PlatformProduct> _platform = const [];
  bool _platformLoading = false;

  bool get _withPlatform =>
      widget.onOpenPlatformProduct != null &&
      widget.market == WholesaleProduct.marketWholesale;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _listen();
    if (_withPlatform) unawaited(_loadPlatform());
  }

  Future<void> _loadPlatform() async {
    _platformLoading = true;
    try {
      final list = await _platformRepo.fetchForWholesaleShelf(
        limit: HomeWholesaleSection.platformLimit,
      );
      if (!mounted) return;
      setState(() {
        _platform = list;
        _platformLoading = false;
        _status = _computeStatus();
      });
    } catch (e) {
      // AVA товарлари юкланмаса ҳам бўлим сотувчилар товари билан ишлайди.
      debugPrint('[HomeWholesale] platform $e');
      if (!mounted) return;
      setState(() {
        _platformLoading = false;
        _status = _computeStatus();
      });
    }
  }

  /// Бўлим ҳолати иккала манбадан: бирортасида товар бўлса — тайёр.
  AvaSectionStatus _computeStatus() {
    if (_items.isNotEmpty || _platform.isNotEmpty) {
      return AvaSectionStatus.ready;
    }
    final sellersPending = !_sellersLoaded && !_sellersFailed;
    if (sellersPending || _platformLoading) return AvaSectionStatus.loading;
    return _sellersFailed ? AvaSectionStatus.error : AvaSectionStatus.empty;
  }

  void _retry() {
    _listen();
    if (_withPlatform && _platform.isEmpty && !_platformLoading) {
      unawaited(_loadPlatform());
    }
  }

  void _onScroll() {
    if (_endReached || !_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels < pos.maxScrollExtent - 240) return;
    _limit += HomeWholesaleSection.limit;
    _listen(initial: false);
  }

  void _listen({bool initial = true}) {
    _sub?.cancel();
    if (initial && mounted) {
      setState(() {
        _sellersFailed = false;
        _sellersLoaded = false;
        _status = _computeStatus();
      });
    }
    // Улгуржи бозор ҳудудга боғланмаган — сотувчилар вилоятлараро
    // ишлайди, шунинг учун бу бўлимда туман филтри йўқ.
    _sub = _repo
        .getActiveProducts(
          limit: _limit,
          market: widget.market,
        )
        .listen(
      (list) {
        if (!mounted) return;
        setState(() {
          // Аввал кўрсатилганлар ўрнида қолади, янгилари аралашиб
          // охирига қўшилади (сеанс уруғи — ҳар очилишда бошқа тартиб).
          _items = mergeShuffled(
            current: _items,
            incoming: list,
            idOf: (p) => p.id,
            random: _rnd,
          );
          _endReached = list.length < _limit;
          _sellersLoaded = true;
          _status = _computeStatus();
        });
      },
      onError: (Object e) {
        debugPrint('[HomeWholesale] $e');
        if (!mounted) return;
        setState(() {
          _sellersFailed = true;
          _status = _computeStatus();
        });
      },
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Навбатма-навбат: AVA товари бошида тўпланиб қолмасин, сотувчилар
    // товари ҳам кўринсин — Улгуржи экранидаги лента билан бир хил қоида.
    final entries = FairMix.roundRobin<_ShelfEntry>([
      _platform.map(_ShelfEntry.platform).toList(growable: false),
      _items.map(_ShelfEntry.seller).toList(growable: false),
    ]);
    // Лента баландлиги ҲАҚИҚИЙ мазмундан ҳисобланади: ном ҳамма вақт 1 қатор
    // (кесилади), нарх изоҳи/пастки қатор йўқ бўлса улар учун жой захира
    // қилинмайди (карточка остидаги бўш жой, 2026-10-15).
    final hasNote = entries.any((e) => e.platform != null
        ? platformShelfPrice(e.platform!).note.isNotEmpty
        : formatTierNote(context, e.seller!).isNotEmpty);
    final hasFoot = entries.any((e) {
      if (e.platform != null) return true; // «AVA»
      final p = e.seller!;
      final text = p.isChina && formatDelivery(context, p).isNotEmpty
          ? formatDelivery(context, p)
          : p.sellerCompanyName;
      return text.isNotEmpty;
    });
    return AvaSection(
      // Хитой бўлимида ўз белгиси (аввал унда ҳам Улгуржи белгиси турарди).
      moduleId: WholesaleProduct.moduleIdFor(widget.market),
      title: context.tr(widget.titleKey),
      status: _status,
      onSeeAll: widget.onOpenAll,
      onRetry: _retry,
      skeletonRows: 1,
      // Икки қатор, ёнга скролл (қаранг: [AvaProductShelf]).
      child: AvaProductShelf(
        // Қатъий 214 эмас — шрифт 130% бўлганда матн карточкадан тошиб
        // кетарди (`avaTileListHeight` изоҳига қаранг).
        rowHeight: avaTileListHeight(
          context,
          titleLines: 1,
          hasPriceNote: hasNote,
          hasFootnote: hasFoot,
        ),
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final ava = entries[i].platform;
          if (ava != null) return _platformTile(ava);
          final p = entries[i].seller!;
          final cover = p.imageUrls.isEmpty ? '' : p.imageUrls.first;
          return AvaTileCard(
            titleMaxLines: 1,
            title: p.title,
            price: formatShelfPrice(p),
            priceNote: formatTierNote(context, p),
            // Хитой бозорида етказиш муддати, улгуржида сотувчи номи.
            footnote: p.isChina
                ? (formatDelivery(context, p).isNotEmpty
                    ? formatDelivery(context, p)
                    : p.sellerCompanyName)
                : p.sellerCompanyName,
            // Бош саҳифа қатори — «ўхшашлар» шу юкланган рўйхатдан олинади.
            onTap: () => widget.onOpenProduct(p, _items),
            image: cover.startsWith('http')
                ? ColoredBox(
                    color: context.ava.surface2,
                    child: CachedNetworkImage(
                      imageUrl: cover,
                      // contain: расм четлари қирқилмайди (ега 2026-10-19).
                      fit: BoxFit.contain,
                    ),
                  )
                : null,
          );
        },
      ),
    );
  }

  /// AVA товари — сотувчи номи ўрнида «AVA».
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
      priceNote: price.note,
      footnote: BrandLabels.brand,
      onTap: () => widget.onOpenPlatformProduct?.call(p, _platform),
      image: image,
    );
  }
}

/// Бўлимдаги битта катак: ё сотувчи товари, ё AVA товари.
class _ShelfEntry {
  const _ShelfEntry._({this.seller, this.platform});

  factory _ShelfEntry.seller(WholesaleProduct p) => _ShelfEntry._(seller: p);
  factory _ShelfEntry.platform(PlatformProduct p) =>
      _ShelfEntry._(platform: p);

  final WholesaleProduct? seller;
  final PlatformProduct? platform;
}
