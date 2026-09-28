import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../../onboarding/screens/onboarding_screen.dart';
import '../realty_tabs.dart';
import '../widgets/realty_card.dart';
import '../widgets/realty_map_view.dart';
import '../widgets/realty_package_sheet.dart';
import 'add_realty_listing_screen.dart';
import 'realty_detail_screen.dart';

/// 🏠 «Кўчмас мулк Кластери» — асосий экран.
///
/// Тузилиши концепциянинг 1-бўлимидан: учта TAB (ОДДИЙ / РЕКЛАМА /
/// СРОЧНО) ва танланган TAB лентаси.
///
/// Харита лента остида (3-босқичдан бошлаб). Пакети йўқ фойдаланувчи
/// объектнинг аниқ жойини эмас, тахминий ҳудуд доирасини кўради —
/// аниқ координата иловага умуман келмайди, у Firestore қоидаси билан
/// ёпилган (9-бўлим).
///
/// Кириш қоидаси (9-бўлим): лентани меҳмон ҳам кўради, харита ва эълон
/// жойлаштириш — фақат рўйхатдан ўтганлар учун.
class RealtyScreen extends StatefulWidget {
  const RealtyScreen({super.key});

  @override
  State<RealtyScreen> createState() => _RealtyScreenState();
}

class _RealtyScreenState extends State<RealtyScreen>
    with SingleTickerProviderStateMixin {
  final _repo = RealtyRepository();
  late final TabController _tabs =
      TabController(length: RealtyTabs.count, vsync: this);

  /// null — иккови ҳам (Сотиш ҳам, Ижара ҳам).
  RealtyDeal? _deal;

  bool get _isGuest =>
      FirebaseAuth.instance.currentUser?.isAnonymous ?? false;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _requireRegistration() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      (_) => false,
    );
  }

  Future<void> _openAdd() async {
    if (_isGuest) return _requireRegistration();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddRealtyListingScreen()),
    );
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
        title: Text(context.tr('realty_title')),
        actions: [
          // Пакетни олдиндан ҳам олиш мумкин — объект очишда кутиб
          // қолмасин. Қолган ўринлар шу ерда кўринади.
          if (!_isGuest)
            StreamBuilder<int>(
              stream: _repo.watchUnlocksLeft(),
              builder: (context, snap) => TextButton.icon(
                onPressed: () => showRealtyPackageSheet(context),
                icon: const Icon(Icons.confirmation_number_outlined, size: 18),
                label: Text('${snap.data ?? 0}'),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          // Ранглар АНИҚ берилади: иловада `TabBarTheme` йўқ, Material 3
          // эса стандарт ҳолда `colorScheme` дан тус олади ва кўк
          // AppBar устида ёзув деярли ўқилмай қолади (қурилмада
          // текширилди, 2026-09-28 — танланган таб умуман кўринмасди).
          labelColor: c.brandInk,
          unselectedLabelColor: c.brandInk.withValues(alpha: 0.65),
          indicatorColor: c.brandInk,
          indicatorWeight: 3,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelStyle: const TextStyle(
            fontSize: AppText.bodyMedium,
            fontWeight: FontWeight.w700,
          ),
          tabs: [
            for (final tier in RealtyTabs.order)
              Tab(text: context.tr(RealtyTabs.labelKey(tier))),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAdd,
        backgroundColor: c.brand,
        foregroundColor: c.brandInk,
        icon: const Icon(Icons.add_home_outlined),
        label: Text(context.tr('realty_add_cta')),
      ),
      body: Column(
        children: [
          _DealFilter(
            deal: _deal,
            onChanged: (d) => setState(() => _deal = d),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                for (final tier in RealtyTabs.order)
                  _TierFeed(
                    repo: _repo,
                    tier: tier,
                    deal: _deal,
                    onOpen: _openDetail,
                  ),
              ],
            ),
          ),
          if (!_isGuest)
            _MapPanel(repo: _repo, deal: _deal, onOpen: _openDetail),
        ],
      ),
    );
  }
}

/// Лента остидаги умумий харита.
///
/// Очилмаган объектлар катакча доираси бўлиб кўринади, пакетдан
/// очилганлари аниқ пин билан. Аниқ координата фақат очилганлар учун
/// сўралади — қолгани иловага умуман келмайди.
class _MapPanel extends StatefulWidget {
  const _MapPanel({
    required this.repo,
    required this.deal,
    required this.onOpen,
  });

  final RealtyRepository repo;
  final RealtyDeal? deal;
  final ValueChanged<RealtyListing> onOpen;

  @override
  State<_MapPanel> createState() => _MapPanelState();
}

class _MapPanelState extends State<_MapPanel> {
  static const double _height = 260;

  /// `listingId` → аниқ координата. Бир марта ўқилгач кешда қолади.
  final Map<String, LatLng> _exact = {};
  final Set<String> _requested = {};

  Future<void> _loadExact(Iterable<String> ids) async {
    final missing = ids.where((id) => !_requested.contains(id)).toList();
    if (missing.isEmpty) return;
    _requested.addAll(missing);
    for (final id in missing) {
      final detail = await widget.repo.fetchDetail(id);
      if (!mounted) return;
      if (detail != null) {
        setState(() => _exact[id] = LatLng(detail.lat, detail.lng));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: StreamBuilder<Set<String>>(
        stream: widget.repo.watchUnlockedIds(),
        builder: (context, unlockedSnap) {
          final unlocked = unlockedSnap.data ?? const <String>{};
          return StreamBuilder<List<RealtyListing>>(
            stream: widget.repo.watchForMap(deal: widget.deal),
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
              // Легенда ХАРИТА УСТИДА: пастда турганда «Эълон қўшиш»
              // тугмаси уни ёпиб қўяр эди (қурилмада текширилди,
              // 2026-09-28).
              return Column(
                children: [
                  const _MapLegend(),
                  Expanded(
                    child: RealtyMapView(
                      listings: listings,
                      exactPoints: _exact,
                      onListingTap: widget.onOpen,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend();

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
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

/// Сотиш / Ижара филтри — харитага ҳам таъсир қилади (7-бўлим).
class _DealFilter extends StatelessWidget {
  const _DealFilter({required this.deal, required this.onChanged});

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

class _TierFeed extends StatelessWidget {
  const _TierFeed({
    required this.repo,
    required this.tier,
    required this.deal,
    required this.onOpen,
  });

  final RealtyRepository repo;
  final RealtyTier tier;
  final RealtyDeal? deal;
  final ValueChanged<RealtyListing> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return StreamBuilder<List<RealtyListing>>(
      stream: repo.watchByTier(tier, deal: deal),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                context.tr('realty_feed_error'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.ink2),
              ),
            ),
          );
        }
        final items = snap.data ?? const <RealtyListing>[];
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                context.tr(
                  tier == RealtyTier.plain
                      ? 'realty_feed_empty'
                      : 'realty_feed_paid_empty',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.ink2, fontSize: AppText.bodyMedium),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
          itemCount: items.length,
          itemBuilder: (_, i) =>
              RealtyCard(listing: items[i], onTap: () => onOpen(items[i])),
        );
      },
    );
  }
}
