import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/utils/formatters.dart';
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

  static const limit = 5;

  @override
  State<HomeMarketSection> createState() => _HomeMarketSectionState();
}

class _HomeMarketSectionState extends State<HomeMarketSection> {
  final _repo = AdsRepository();
  StreamSubscription<List<AdModel>>? _sub;

  AvaSectionStatus _status = AvaSectionStatus.loading;
  List<AdModel> _items = const [];

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _sub?.cancel();
    if (mounted) setState(() => _status = AvaSectionStatus.loading);
    _sub = _repo
        .watchForHome(
          districtId: ServiceConfigHolder.districtId,
          limit: HomeMarketSection.limit,
        )
        .listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _items = list;
          _status = list.isEmpty
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
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AvaSection(
      title: context.tr('home_module_cheap_products'),
      status: _status,
      onSeeAll: widget.onOpenAll,
      onRetry: _listen,
      skeletonRows: 1,
      child: SizedBox(
        // Бу бўлимда нарх изоҳи йўқ — қолгани `avaTileListHeight` изоҳида.
        height: avaTileListHeight(context, hasPriceNote: false),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: _items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
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
      ),
    );
  }
}
