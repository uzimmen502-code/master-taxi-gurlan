import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../../onboarding/screens/onboarding_screen.dart';
import '../realty_tabs.dart';
import '../widgets/realty_card.dart';
import 'add_realty_listing_screen.dart';
import 'realty_detail_screen.dart';

/// 🏠 «Кўчмас мулк Кластери» — асосий экран.
///
/// Тузилиши концепциянинг 1-бўлимидан: учта TAB (ОДДИЙ / РЕКЛАМА /
/// СРОЧНО) ва танланган TAB лентаси.
///
/// ⚠️ ХАРИТА ҲОЗИР КЎРСАТИЛМАЙДИ (эга қарори, 2026-09-28). Концепция
/// бўйича пакети йўқ фойдаланувчига аниқ пин эмас, тахминий ҳудуд
/// кўриниши керак (9-бўлим) — аммо ахборот пакетлари 3-босқичда
/// қўшилади. Шунгача харитани кўрсатиш пулли ахборотни бепул бериб
/// қўяр эди, шунинг учун у бутунлай олиб турилди. Виджети тайёр:
/// `widgets/realty_map_view.dart` — 3-босқичда шу ерга қайтарилади.
///
/// Кириш қоидаси (9-бўлим): лентани меҳмон ҳам кўради, эълон
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
        bottom: TabBar(
          controller: _tabs,
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
          // Харита шу ерда турган эди — 3-босқичда (ахборот пакети
          // билан бирга) қайтади. Синф изоҳига қаранг.
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
