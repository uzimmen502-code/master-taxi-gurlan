import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/job_ad.dart';
import '../../../repositories/jobs_repository.dart';
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
    final c = context.ava;
    return AvaSection(
      title: context.tr(widget.titleKey),
      status: _status,
      onSeeAll: widget.onOpenAll,
      onRetry: _listen,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AvaRadius.card),
          border: Border.all(color: c.line),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          children: [
            for (var i = 0; i < _items.length; i++)
              _AdTitleRow(
                title: _items[i].titleOrText,
                onTap: () => widget.onOpenAd(_items[i]),
              ),
          ],
        ),
      ),
    );
  }
}

/// Битта эълон сарлавҳаси — қора нуқта (●) + матн, битта қатор.
class _AdTitleRow extends StatelessWidget {
  const _AdTitleRow({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: c.ink,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AvaText.body.copyWith(color: c.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
