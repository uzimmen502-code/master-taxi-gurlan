import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../realty_tabs.dart';
import '../widgets/realty_map_view.dart';
import '../widgets/realty_package_sheet.dart';
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

  /// Пин босилганда — ҳимоя шу ерда ишлайди (эга қарори, 2026-09-29).
  ///
  /// Очилмаган объектда фойдаланувчи ТЎҒРИДАН-ТЎҒРИ карточкага тушмайди:
  /// аввал харитадаги нуқта тахминий экани айтилади ва пакет таклиф
  /// қилинади. Аввал пин ҳам, босилиши ҳам очилган объект билан бир хил
  /// эди — харидор пинни аниқ манзил деб ўйлар, ҳолбуки у ≈1.2 км
  /// силкитилган.
  Future<void> _onPinTap(RealtyListing listing, Set<String> unlocked) async {
    if (unlocked.contains(listing.id)) {
      _openDetail(listing);
      return;
    }
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ApproxPinSheet(listing: listing),
    );
    if (!mounted || action == null) return;
    if (action == 'detail') {
      _openDetail(listing);
      return;
    }
    // 'package' — пакет варағи. Олингач харитадаги оқим узилмасин:
    // фойдаланувчи ўша объект карточкасида очишни давом эттиради.
    final bought = await showRealtyPackageSheet(context);
    if (bought && mounted) _openDetail(listing);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(context.tr('realty_map_title')),
        actions: [
          _UnlocksLeftChip(stream: _repo.watchUnlocksLeft()),
          RealtyAddButton(onTap: _openAdd),
        ],
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
                      onListingTap: (r) => _onPinTap(r, unlocked),
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

/// Очилмаган пин босилганда чиқадиган варақ: нуқта тахминий экани ва
/// аниқ манзилни очиш таклифи.
class _ApproxPinSheet extends StatelessWidget {
  const _ApproxPinSheet({required this.listing});

  final RealtyListing listing;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 5, right: 8),
                  decoration: BoxDecoration(
                    color: RealtyTabs.colorFor(listing.tier),
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    listing.titleOrText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: AppText.bodyLarge,
                      color: c.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, size: 18, color: c.ink3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('realty_map_locked_body'),
                    style: TextStyle(
                      fontSize: AppText.labelLarge,
                      color: c.ink2,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop('package'),
              icon: const Icon(Icons.lock_open_outlined, size: 18),
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              label: Text(context.tr('realty_map_locked_cta')),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop('detail'),
              child: Text(context.tr('realty_map_locked_open_card')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Пакетда қолган объект сони — сарлавҳа қаторида.
/// Пакети йўқ фойдаланувчида умуман кўринмайди.
class _UnlocksLeftChip extends StatelessWidget {
  const _UnlocksLeftChip({required this.stream});

  final Stream<int> stream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, snap) {
        final left = snap.data ?? 0;
        if (left <= 0) return const SizedBox.shrink();
        return Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_open_outlined,
                    size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  '$left',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: AppText.labelLarge,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
