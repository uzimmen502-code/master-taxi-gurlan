import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../../realty/realty_tabs.dart';
import 'ava_section.dart';

/// 🏠 Бош саҳифадаги «Кўчмас мулк» бўлими.
///
/// Тузилиши эълон бўлимлари билан бир хил (`home_ads_section.dart`):
/// сарлавҳа + ботиқ майдондаги қаторлар. Фарқи — қатор бошидаги нуқта
/// эълон ДАРАЖАСИ рангида (ОДДИЙ яшил, РЕКЛАМА мандарин, СРОЧНО
/// қизил), шунда лента, харита ва бош саҳифада ранг маъноси бир хил
/// бўлади.
///
/// Туман бўйича филтрланади — бош саҳифа бўлимларининг умумий қоидаси.
class HomeRealtySection extends StatefulWidget {
  const HomeRealtySection({
    super.key,
    required this.onOpenAll,
    required this.onOpenListing,
  });

  final VoidCallback onOpenAll;
  final void Function(RealtyListing listing) onOpenListing;

  static const int limit = 10;

  @override
  State<HomeRealtySection> createState() => _HomeRealtySectionState();
}

class _HomeRealtySectionState extends State<HomeRealtySection> {
  final _repo = RealtyRepository();
  StreamSubscription<List<RealtyListing>>? _sub;

  AvaSectionStatus _status = AvaSectionStatus.loading;
  List<RealtyListing> _items = const [];

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
          limit: HomeRealtySection.limit,
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
        debugPrint('[HomeRealty] $e');
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
      moduleId: 'realty',
      title: context.tr('home_section_realty'),
      status: _status,
      onSeeAll: widget.onOpenAll,
      onRetry: _listen,
      child: AvaInsetPanel(
        child: AvaRowPager(
          rowHeight: AvaRowPager.textRowHeight(context),
          onOpenModule: widget.onOpenAll,
          rows: [
            for (final r in _items)
              _RealtyRow(
                listing: r,
                onTap: () => widget.onOpenListing(r),
              ),
          ],
        ),
      ),
    );
  }
}

/// Битта объект қатори — даража рангидаги нуқта + сарлавҳа + нарх.
class _RealtyRow extends StatelessWidget {
  const _RealtyRow({required this.listing, required this.onTap});

  final RealtyListing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return InkWell(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: RealtyTabs.colorFor(listing.tier),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              listing.titleOrText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AvaText.feedRow.copyWith(color: c.inkRow),
            ),
          ),
          if (listing.priceText.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              listing.priceText,
              maxLines: 1,
              style: AvaText.feedRow.copyWith(
                color: RealtyTabs.colorFor(listing.tier),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
