import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/job_ad.dart';
import '../../../repositories/jobs_repository.dart';
import 'ava_chip.dart';
import 'ava_list_row.dart';
import 'ava_section.dart';

/// 2 ва 3-бўлимлар: «Яқинингиздаги эълонлар» ва «…хизмат таклифлари».
///
/// Иккаласи ҳам `ads` коллекциясидан, фақат `type` билан фарқланади —
/// шунинг учун битта виджет.
class HomeAdsSection extends StatefulWidget {
  const HomeAdsSection({
    super.key,
    required this.adType,
    required this.titleKey,
    required this.onOpenAll,
    required this.onOpenAd,
  });

  /// Эълонлар учун `ad`, хизмат таклифлари учун `service`.
  final String adType;
  final String titleKey;
  final VoidCallback onOpenAll;
  final void Function(JobAd ad) onOpenAd;

  static const limit = 5;

  @override
  State<HomeAdsSection> createState() => _HomeAdsSectionState();
}

class _HomeAdsSectionState extends State<HomeAdsSection> {
  final _repo = JobsRepository();
  StreamSubscription<List<JobAd>>? _sub;

  AvaSectionStatus _status = AvaSectionStatus.loading;
  List<JobAd> _items = const [];

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
          widget.adType,
          districtId: ServiceConfigHolder.districtId,
          limit: HomeAdsSection.limit,
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
        debugPrint('[HomeAds ${widget.adType}] $e');
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
      title: context.tr(widget.titleKey),
      status: _status,
      onSeeAll: widget.onOpenAll,
      onRetry: _listen,
      child: Column(
        children: [
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == _items.length - 1 ? 0 : 8),
              child: _AdRow(
                ad: _items[i],
                onTap: () => widget.onOpenAd(_items[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _AdRow extends StatelessWidget {
  const _AdRow({required this.ad, required this.onTap});

  final JobAd ad;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;

    // Тавсиф: тур, сарлавҳа, нарх ва жойланган вақт.
    final meta = <Widget>[
      AvaChip(
        label: ad.kind.label,
        tone: ad.isUrgent ? AvaChipTone.warn : AvaChipTone.neutral,
      ),
      if (ad.timeAgo.isNotEmpty)
        Text(
          ad.timeAgo,
          style: AvaText.caption.copyWith(color: c.ink3),
        ),
    ];

    return AvaListRow(
      title: ad.titleOrText,
      subtitle: ad.address,
      meta: meta,
      // Нарх `priceText` — эркин матн («200 000 сўм», «Шартномавий»).
      price: ad.priceText.trim().isEmpty ? null : ad.priceText.trim(),
      onTap: onTap,
    );
  }
}
