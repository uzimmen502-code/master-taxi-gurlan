import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/intercity_ride.dart';
import '../../../repositories/intercity_rides_repository.dart';
import 'ava_chip.dart';
import 'ava_list_row.dart';
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

  static const limit = 5;

  @override
  State<HomeIntercitySection> createState() => _HomeIntercitySectionState();
}

class _HomeIntercitySectionState extends State<HomeIntercitySection> {
  final _repo = IntercityRidesRepository();
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
          _items = list;
          _status =
              list.isEmpty ? AvaSectionStatus.empty : AvaSectionStatus.ready;
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
    return AvaSection(
      title: context.tr('home_module_intercity'),
      status: _status,
      onSeeAll: widget.onOpenAll,
      onRetry: _listen,
      child: Column(
        children: [
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == _items.length - 1 ? 0 : 8),
              child: _RideRow(
                ride: _items[i],
                onTap: () => widget.onOpenRide(_items[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _RideRow extends StatelessWidget {
  const _RideRow({required this.ride, required this.onTap});

  final IntercityRide ride;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final cabin = formatCabinLabel(context, ride);

    return AvaListRow(
      title: ride.routeDisplayLabel(Localizations.localeOf(context)),
      // Машина — ҳайдовчининг исми ва телефони ЭМАС.
      subtitle: ride.carDisplay,
      price: ride.price > 0
          ? '${formatPrice(ride.price)} $kCurrencySum'
          : null,
      priceNote: context.tr('home_intercity_per_seat'),
      onTap: onTap,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: c.brandSoft,
          borderRadius: BorderRadius.circular(AvaRadius.card - 2),
        ),
        child: Icon(Icons.alt_route_rounded, size: 20, color: c.brand),
      ),
      meta: [
        AvaChip(
          label: formatDepartureLabel(context, ride.departureTime),
          icon: Icons.schedule_rounded,
          tone: AvaChipTone.brand,
        ),
        if (ride.availableSeats > 0)
          AvaChip(
            label: '${context.tr('home_seats_free')}: ${ride.availableSeats}',
            tone: AvaChipTone.ok,
          ),
        if (cabin.isNotEmpty)
          Text(cabin, style: AvaText.caption.copyWith(color: c.ink3)),
      ],
    );
  }
}
