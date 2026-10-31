import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/geo/geo_names.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/geo/geo_context.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/session_shuffle.dart';
import '../../yuk_local/models/yuk_local_driver.dart';
import '../../yuk_local/repositories/yuk_local_drivers_repository.dart';
import '../../yuk_shared/yuk_vehicle_types.dart';
import '../home_demo_feed.dart';
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
    this.isGuest = false,
    this.onRegister,
  });

  final VoidCallback onOpenAll;
  final void Function(YukLocalDriver driver) onOpenDriver;

  /// Телефонсиз меҳмон: рўйхат ўқилмайди (rules ҳам рад этади), ўрнида
  /// «Фойдаланиш учун Кабинетда рўйхатдан ўтинг» (эга, 2026-10-31).
  final bool isGuest;
  final VoidCallback? onRegister;

  /// Ойнада 5 таси кўринади, қолгани скролл ([AvaRowViewport]) — шунинг
  /// учун 5 эмас, 10 та юкланади. Бу бўлимда намунавий қатор йўқ.
  static const limit = HomeDemoFeed.capacity;

  @override
  State<HomeYukLocalSection> createState() => _HomeYukLocalSectionState();
}

class _HomeYukLocalSectionState extends State<HomeYukLocalSection> {
  // `late` — меҳмон ҳолатида Firestore'га мурожаат йўқ.
  late final _repo = YukLocalDriversRepository();
  final Random _rnd = sessionRandom();
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
    if (widget.isGuest) return;
    if (mounted) setState(() => _status = AvaSectionStatus.loading);
    // Модул экрани билан бир хил доира (D-GEO-6: туман ёки вилоят).
    _sub = _repo
        .watchScoped(GeoContext.scopeFor('yuk_local'))
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
          // Ҳар очилишда бошқа тартиб; кўрилиб турганлар ўрнида қолади.
          _items = mergeShuffled(
            current: _items,
            incoming: visible.take(HomeYukLocalSection.limit).toList(),
            idOf: (d) => d.id,
            random: _rnd,
          );
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
    return GeoNames.district(ServiceConfigHolder.districtId, context.contentLang,
        fallback: ServiceConfigHolder.districtLabel);
  }

  @override
  void didUpdateWidget(covariant HomeYukLocalSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Меҳмон рўйхатдан ўтди (ёки аксинча) — оқимни қайта улаймиз.
    if (oldWidget.isGuest != widget.isGuest) _listen();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isGuest) {
      return AvaSection(
        moduleId: 'yuk_local',
        title: context.tr('home_section_yuk_local'),
        status: AvaSectionStatus.ready,
        child: AvaNoticeRow(
          key: const ValueKey('home_yuk_local_guest'),
          text: context.tr('yuk_local_guest_message'),
          icon: Icons.lock_outline_rounded,
          color: context.ava.ink3,
          actionLabel: widget.onRegister == null
              ? null
              : context.tr('yuk_local_guest_cta'),
          onAction: widget.onRegister,
        ),
      );
    }
    return AvaSection(
      moduleId: 'yuk_local',
      title: context.tr('home_section_yuk_local'),
      status: _status,
      onSeeAll: widget.onOpenAll,
      onRetry: _listen,
      // Ботиқ майдон — қаторлар унинг ичида (қаранг: [AvaInsetPanel]).
      child: AvaInsetPanel(
        child: AvaRowPager(
          rowHeight: AvaRowPager.textRowHeight(context),
          onOpenModule: widget.onOpenAll,
          rows: [
            for (final driver in _items)
              _BulletRow(
                title: _titleOf(context, driver, _place(driver)),
                onTap: () => widget.onOpenDriver(driver),
              ),
          ],
        ),
      ),
    );
  }

  String _titleOf(BuildContext context, YukLocalDriver driver, String place) {
    final vehicle = context.tr(yukVehicleLabelKey(driver.vehicleType));
    final capacity = formatYukCapacity(context, driver.capacityKg);
    // «Лабо · 500 кг · Гурлан» — бўш қисмлар тушиб қолади. Намуна эълон
    // ҳақиқийдан ажралиб турсин (аудит O-4: бош саҳифада белгиси йўқ эди).
    final parts = <String>[
      if (driver.isDemo) context.tr('yuk_demo_badge'),
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
