import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/session_shuffle.dart';
import '../../../models/intercity_ride.dart';
import '../../../repositories/intercity_rides_repository.dart';
import '../home_demo_feed.dart';
import 'ava_section.dart';

/// «Бугун 14:30» / «Эртага 07:00» / «12.02 07:00».
String formatDepartureLabel(BuildContext context, DateTime at) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final time =
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  final diff = day.difference(today).inDays;
  if (diff == 0) return '${context.tr('home_today')} $time';
  if (diff == 1) return '${context.tr('home_tomorrow')} $time';
  return '${at.day.toString().padLeft(2, '0')}.'
      '${at.month.toString().padLeft(2, '0')} $time';
}

/// «Салонда: 1 аёл», «Салонда: 2 эркак, 1 аёл», ёки бўш (ҳеч ким йўқ).
///
/// ЙЎЛОВЧИЛАРНИНГ ИСМИ ВА РАСМИ КЎРСАТИЛМАЙДИ — тавсиф талаби. Фақат
/// жинс ва сон; бу маълумот `intercity_drivers` ҳужжатидаги йиғма
/// `maleCount` / `femaleCount` дан келади.
String formatCabinLabel(BuildContext context, IntercityRide r) {
  final parts = <String>[
    if (r.maleCount > 0)
      '${r.maleCount} ${context.tr('home_gender_male')}',
    if (r.femaleCount > 0)
      '${r.femaleCount} ${context.tr('home_gender_female')}',
  ];
  if (parts.isEmpty) return '';
  return '${context.tr('home_intercity_cabin')}: ${parts.join(', ')}';
}

/// 4-бўлим: шаҳарлараро такси.
class HomeIntercitySection extends StatefulWidget {
  const HomeIntercitySection({
    super.key,
    required this.onOpenAll,
    required this.onOpenRide,
  });

  final VoidCallback onOpenAll;
  final void Function(IntercityRide ride) onOpenRide;

  /// Реал сафарлар шунчагача; қолган жой намунавий йўналишларга
  /// берилади (қаранг: [HomeDemoFeed]).
  static const limit = HomeDemoFeed.capacity;

  @override
  State<HomeIntercitySection> createState() => _HomeIntercitySectionState();
}

class _HomeIntercitySectionState extends State<HomeIntercitySection> {
  final _repo = IntercityRidesRepository();
  final Random _rnd = sessionRandom();
  StreamSubscription<List<IntercityRide>>? _sub;

  AvaSectionStatus _status = AvaSectionStatus.loading;
  List<IntercityRide> _items = const [];

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _sub?.cancel();
    if (mounted) setState(() => _status = AvaSectionStatus.loading);
    _sub = _repo
        .watchNearbyForHome(
          districtId: ServiceConfigHolder.districtId,
          limit: HomeIntercitySection.limit,
        )
        .listen(
      (list) {
        if (!mounted) return;
        setState(() {
          // Ҳар очилишда бошқа тартиб; кўрилиб турганлар ўрнида қолади.
          _items = mergeShuffled(
            current: _items,
            incoming: list,
            idOf: (r) => r.id,
            random: _rnd,
          );
          // Намунавий қаторлар доим бор, шунинг учун «бўш» ҳолат йўқ.
          _status = AvaSectionStatus.ready;
        });
      },
      onError: (Object e) {
        debugPrint('[HomeIntercity] $e');
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
    // Реал сафарлардан кейин қолган жой намунавий йўналишларга берилади;
    // реал сафар 10 тага етганда улар ўз-ўзидан йўқолади.
    final demo = HomeDemoFeed.fill(
      context,
      keys: HomeDemoFeed.intercityKeys,
      realCount: _items.length,
      random: _rnd,
    );
    return AvaSection(
      moduleId: 'intercity',
      title: context.tr('home_module_intercity'),
      status: _status,
      onSeeAll: widget.onOpenAll,
      onRetry: _listen,
      // Ботиқ майдон — қаторлар унинг ичида (қаранг: [AvaInsetPanel]).
      child: AvaInsetPanel(
        child: AvaRowPager(
          rowHeight: AvaRowPager.textRowHeight(context),
          onOpenModule: widget.onOpenAll,
          rows: [
            for (final ride in _items)
              _BulletRow(
                title: ride.routeDisplayLabel(Localizations.localeOf(context)),
                onTap: () => widget.onOpenRide(ride),
              ),
            for (final label in demo)
              _BulletRow(title: label, onTap: widget.onOpenAll),
          ],
        ),
      ),
    );
  }
}

/// Битта сафар сарлавҳаси — қора нуқта (●) + матн, битта қатор.
class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    // Қаторлар ораси айнан 1px: ички вертикал чет йўқ.
    return InkWell(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
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
