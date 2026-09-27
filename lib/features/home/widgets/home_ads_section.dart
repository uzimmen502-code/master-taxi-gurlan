import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/session_shuffle.dart';
import '../../../models/job_ad.dart';
import '../../../repositories/jobs_repository.dart';
import '../home_demo_feed.dart';
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

  /// Реал эълонлар шунчагача кўрсатилади; қолган жой намунавий
  /// қаторларга берилади (қаранг: [HomeDemoFeed]).
  static const limit = HomeDemoFeed.capacity;

  @override
  State<HomeAdsSection> createState() => _HomeAdsSectionState();
}

class _HomeAdsSectionState extends State<HomeAdsSection> {
  final _repo = JobsRepository();
  final Random _rnd = sessionRandom();
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
          // Ҳар очилишда бошқа тартиб; кўрилиб турганлар ўрнида қолади.
          _items = mergeShuffled(
            current: _items,
            incoming: list,
            idOf: (a) => a.id,
            random: _rnd,
          );
          // Намунавий қаторлар доим бор, шунинг учун «бўш» ҳолат йўқ.
          _status = AvaSectionStatus.ready;
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
    // Реал эълонлардан кейин қолган жой намунавий қаторларга берилади;
    // реал эълон 10 тага етганда улар ўз-ўзидан йўқолади.
    final demo = HomeDemoFeed.fill(
      context,
      keys: widget.adType == 'service'
          ? HomeDemoFeed.serviceKeys
          : HomeDemoFeed.adKeys,
      realCount: _items.length,
      random: _rnd,
    );
    return AvaSection(
      moduleId: 'jobs',
      title: context.tr(widget.titleKey),
      status: _status,
      onSeeAll: widget.onOpenAll,
      onRetry: _listen,
      // Ботиқ майдон — қаторлар унинг ичида (қаранг: [AvaInsetPanel]).
      child: AvaInsetPanel(
        child: AvaRowPager(
          rowHeight: AvaRowPager.textRowHeight(context),
          onOpenModule: widget.onOpenAll,
          rows: [
            for (final ad in _items)
              _AdTitleRow(
                title: ad.titleOrText,
                onTap: () => widget.onOpenAd(ad),
              ),
            for (final label in demo)
              _AdTitleRow(title: label, onTap: widget.onOpenAll),
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
    // Қаторлар ораси айнан 1px: ички вертикал чет йўқ, масофани
    // `Column`даги 1px оралиқ беради.
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
              style: AvaText.feedRow.copyWith(color: c.inkRow),
            ),
          ),
        ],
      ),
    );
  }
}
