import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../realty_tabs.dart';
import '../widgets/realty_map_view.dart';
import 'add_realty_listing_screen.dart';
import 'realty_detail_screen.dart';

/// 🗺 Кўчмас мулк — ТЎЛИҚ ЭКРАНЛИ харита.
///
/// Нега алоҳида экран (эга қарори, 2026-09-28): аввал харита лента
/// экранининг пастида 260px тасма эди. Бош саҳифадаги харита расми
/// босилганда фойдаланувчи ХАРИТА кутади, лекин рўйхатга тушиб қолар,
/// харита эса пастда сиқилиб турар эди. EV бўлимида бу масала аллақачон
/// шундай ечилган: статик расм → тўлиқ экранли харита.
///
/// Очилмаган объектлар тахминий доира билан, пакетдан очилганлари
/// аниқ пин билан кўринади.
class RealtyMapScreen extends StatefulWidget {
  const RealtyMapScreen({super.key, this.deal});

  /// Лента экранидан келган филтр — харита ҳам шунга бўйсунсин.
  final RealtyDeal? deal;

  @override
  State<RealtyMapScreen> createState() => _RealtyMapScreenState();
}

class _RealtyMapScreenState extends State<RealtyMapScreen> {
  final _repo = RealtyRepository();

  /// `listingId` → аниқ координата. Бир марта ўқилгач кешда қолади.
  final Map<String, LatLng> _exact = {};
  final Set<String> _requested = {};

  late RealtyDeal? _deal = widget.deal;

  Future<void> _loadExact(Iterable<String> ids) async {
    final missing = ids.where((id) => !_requested.contains(id)).toList();
    if (missing.isEmpty) return;
    _requested.addAll(missing);
    for (final id in missing) {
      final detail = await _repo.fetchDetail(id);
      if (!mounted) return;
      if (detail != null) {
        setState(() => _exact[id] = LatLng(detail.lat, detail.lng));
      }
    }
  }

  void _openDetail(RealtyListing listing) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RealtyDetailScreen(listing: listing)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(context.tr('realty_map_title')),
        actions: [RealtyAddButton(onTap: _openAdd)],
      ),
      body: Column(
        children: [
          RealtyDealFilter(
            deal: _deal,
            onChanged: (d) => setState(() => _deal = d),
          ),
          const RealtyMapLegend(),
          Expanded(
            child: StreamBuilder<Set<String>>(
              stream: _repo.watchUnlockedIds(),
              builder: (context, unlockedSnap) {
                final unlocked = unlockedSnap.data ?? const <String>{};
                return StreamBuilder<List<RealtyListing>>(
                  stream: _repo.watchForMap(deal: _deal),
                  builder: (context, snap) {
                    final listings = snap.data ?? const <RealtyListing>[];
                    final visibleUnlocked = listings
                        .map((r) => r.id)
                        .where(unlocked.contains)
                        .toList();
                    if (visibleUnlocked.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _loadExact(visibleUnlocked),
                      );
                    }
                    return RealtyMapView(
                      listings: listings,
                      exactPoints: _exact,
                      onListingTap: _openDetail,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAdd() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddRealtyListingScreen()),
    );
  }
}

/// «Эълон қўшиш» — матнсиз, доира ичида, сарлавҳа қаторининг ўнг
/// бурчагида (эга қарори, 2026-09-28). Икки экранда ҳам бир хил
/// бўлиши учун алоҳида виджет.
class RealtyAddButton extends StatelessWidget {
  const RealtyAddButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.only(right: 8, left: 4),
      child: Tooltip(
        message: context.tr('realty_add_cta'),
        child: Material(
          color: c.brandInk,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(Icons.add_home_outlined, size: 20, color: c.brand),
            ),
          ),
        ),
      ),
    );
  }
}

/// Сотиш / Ижара филтри — лента ва харита экранларида бир хил.
class RealtyDealFilter extends StatelessWidget {
  const RealtyDealFilter({
    super.key,
    required this.deal,
    required this.onChanged,
  });

  final RealtyDeal? deal;
  final ValueChanged<RealtyDeal?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    Widget chip(String labelKey, RealtyDeal? value) {
      final selected = deal == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(context.tr(labelKey)),
          selected: selected,
          onSelected: (_) => onChanged(value),
          labelStyle: TextStyle(
            fontSize: AppText.bodySmall,
            fontWeight: FontWeight.w600,
            color: selected ? c.brandInk : c.ink2,
          ),
          selectedColor: c.brand,
          backgroundColor: c.chip,
          side: BorderSide(color: c.line),
          showCheckmark: false,
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      color: c.bg,
      child: Row(
        children: [
          chip('realty_deal_all', null),
          chip('realty_deal_sale', RealtyDeal.sale),
          chip('realty_deal_rent', RealtyDeal.rent),
        ],
      ),
    );
  }
}

/// Харита легендаси — ранг маъноси ва «нуқталар тахминий» огоҳлантириши.
class RealtyMapLegend extends StatelessWidget {
  const RealtyMapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          for (final tier in RealtyTabs.order) ...[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: RealtyTabs.colorFor(tier),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              context.tr(RealtyTabs.labelKey(tier)),
              style: TextStyle(fontSize: AppText.labelTiny, color: c.ink2),
            ),
            const SizedBox(width: 10),
          ],
          const Spacer(),
          Expanded(
            flex: 3,
            child: Text(
              context.tr('realty_map_approx_hint'),
              textAlign: TextAlign.right,
              maxLines: 2,
              style: TextStyle(fontSize: AppText.labelTiny, color: c.ink3),
            ),
          ),
        ],
      ),
    );
  }
}
