import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../yuk_local/models/yuk_local_driver.dart';
import '../../yuk_local/repositories/yuk_local_drivers_repository.dart';
import '../../yuk_shared/yuk_vehicle_types.dart';
import 'ava_section.dart';

/// Юк сиғими — «500 кг» ёки «3.5 т».
String formatYukCapacity(BuildContext context, double kg) {
  if (kg <= 0) return '';
  if (kg < 1000) return '${kg.round()} ${context.tr('yuk_unit_kg')}';
  final tons = kg / 1000;
  final text = tons % 1 == 0
      ? tons.round().toString()
      : tons.toStringAsFixed(1).replaceAll('.', ',');
  return '$text ${context.tr('yuk_unit_ton')}';
}

/// 5-бўлим: туман ичидаги юк машиналари.
///
/// Шаҳарлараро юк (`yuk_listings`) бу рўйхатга АРАЛАШМАЙДИ — у бошқа
/// коллекция ва бошқа модул (тавсиф талаби).
class HomeYukLocalSection extends StatefulWidget {
  const HomeYukLocalSection({
    super.key,
    required this.onOpenAll,
    required this.onOpenDriver,
  });

  final VoidCallback onOpenAll;
  final void Function(YukLocalDriver driver) onOpenDriver;

  static const limit = 5;

  @override
  State<HomeYukLocalSection> createState() => _HomeYukLocalSectionState();
}

class _HomeYukLocalSectionState extends State<HomeYukLocalSection> {
  final _repo = YukLocalDriversRepository();
  StreamSubscription<List<YukLocalDriver>>? _sub;

  AvaSectionStatus _status = AvaSectionStatus.loading;
  List<YukLocalDriver> _items = const [];

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _sub?.cancel();
    if (mounted) setState(() => _status = AvaSectionStatus.loading);
    _sub = _repo
        .watchCatalog(districtId: ServiceConfigHolder.districtId)
        .listen(
      (all) {
        if (!mounted) return;
        // `isVisibleInSearch` — GPS бор, муддати ўтмаган ва иш вақтида.
        final visible = all.where((d) => d.isVisibleInSearch).toList()
          ..sort((a, b) {
            final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
            final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
            return bt.compareTo(at);
          });
        setState(() {
          _items = visible.take(HomeYukLocalSection.limit).toList();
          _status = _items.isEmpty
              ? AvaSectionStatus.empty
              : AvaSectionStatus.ready;
        });
      },
      onError: (Object e) {
        debugPrint('[HomeYukLocal] $e');
        if (mounted) setState(() => _status = AvaSectionStatus.error);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _place(YukLocalDriver d) {
    final label = d.locationLabel.trim();
    if (label.isNotEmpty) return label;
    return ServiceConfigHolder.districtLabel;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return AvaSection(
      title: context.tr('home_section_yuk_local'),
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
              _BulletRow(
                title: _titleOf(context, _items[i], _place(_items[i])),
                onTap: () => widget.onOpenDriver(_items[i]),
              ),
          ],
        ),
      ),
    );
  }

  String _titleOf(BuildContext context, YukLocalDriver driver, String place) {
    final vehicle = context.tr(yukVehicleLabelKey(driver.vehicleType));
    final capacity = formatYukCapacity(context, driver.capacityKg);
    // «Лабо · 500 кг · Гурлан» — бўш қисмлар тушиб қолади.
    final parts = <String>[
      vehicle,
      if (capacity.isNotEmpty) capacity,
      if (place.trim().isNotEmpty) place.trim(),
    ];
    return parts.join(' · ');
  }
}

/// Битта юк машинаси сарлавҳаси — қора нуқта (●) + матн, битта қатор.
class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.title, required this.onTap});

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
              decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
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
