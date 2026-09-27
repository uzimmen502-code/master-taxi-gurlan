import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'dart:math';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/session_shuffle.dart';
import '../../ads/models/ad_model.dart';
import '../../ads/repositories/ads_repository.dart';
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
  });

  final VoidCallback onOpenAll;
  final void Function(AdModel ad) onOpenAd;

  /// Икки қатор тўлиши учун 5 эмас, 10 та (қаранг: [AvaProductShelf]).
  static const limit = 10;

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

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _listen();
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
    _sub = _repo
        .watchForHome(
          districtId: ServiceConfigHolder.districtId,
          limit: _limit,
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
            idOf: (a) => a.id,
            random: _rnd,
          );
          _endReached = list.length < _limit;
          _status = _items.isEmpty
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

  @override
  void dispose() {
    _scroll.dispose();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AvaSection(
      moduleId: 'cheap_products_home',
      title: context.tr('home_module_cheap_products'),
      status: _status,
      onSeeAll: widget.onOpenAll,
      onRetry: _listen,
      skeletonRows: 1,
      // Икки қатор, ёнга скролл (қаранг: [AvaProductShelf]).
      child: AvaProductShelf(
        // Бу бўлимда нарх изоҳи йўқ — қолгани `avaTileListHeight` изоҳида.
        rowHeight: avaTileListHeight(context, hasPriceNote: false),
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final ad = _items[i];
          final cover = ad.imageUrls.isEmpty ? '' : ad.imageUrls.first;
          return AvaTileCard(
            title: ad.title,
            price: ad.price > 0
                ? '${formatPrice(ad.price)} $kCurrencySum'
                : null,
            footnote: ServiceConfigHolder.districtLabel,
            onTap: () => widget.onOpenAd(ad),
            image: cover.startsWith('http')
                ? CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover)
                : null,
          );
        },
      ),
    );
  }
}
