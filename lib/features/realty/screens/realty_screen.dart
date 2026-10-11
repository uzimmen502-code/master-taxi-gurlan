import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/geo/geo_context.dart';
import '../../../core/geo/geo_tier_bar.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/realty_alert.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../../onboarding/screens/onboarding_screen.dart';
import '../realty_tabs.dart';
import '../widgets/realty_card.dart';
import '../widgets/realty_controls.dart';
import '../widgets/realty_package_sheet.dart';
import 'add_realty_listing_screen.dart';
import 'realty_detail_screen.dart';
import 'realty_alerts_screen.dart';
import 'realty_map_screen.dart';

/// 🏠 «Кўчмас мулк Кластери» — ЛЕНТА экрани.
///
/// Тузилиши концепциянинг 1-бўлимидан: учта TAB (ОДДИЙ / РЕКЛАМА /
/// СРОЧНО) ва танланган TAB лентаси.
///
/// Харита БУ ЕРДА ЙЎҚ (эга қарори, 2026-09-28) — у алоҳида тўлиқ
/// экранда (`RealtyMapScreen`), сарлавҳадаги харита тугмасидан ёки
/// бош саҳифадаги харита расмидан очилади. Аввал у пастда 260px тасма
/// эди ва «харитани босдим — рўйхат чиқди» деган ғализлик бор эди.
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

  /// Ҳудуд (D-GEO-11/15): исталган ҳудуддан қидириш, танлов сақланади.
  /// Аввал лента доим бутун Республика эди (бош саҳифа эса туман).
  GeoScope _scope = GeoContext.scopeFor('realty');

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

  /// Харита — алоҳида тўлиқ экран. Жорий Сотиш/Ижара филтри у ерга
  /// ҳам узатилади, шунда фойдаланувчи танловини қайта қилмайди.
  void _openMap() {
    if (_isGuest) return _requireRegistration();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RealtyMapScreen(deal: _deal)),
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
          // «Шундай уй чиқса, хабар бер» (эга қарори 2026-10-08, бепул).
          // Нишон — ҳали очилмаган мос эълонлар сони.
          if (!_isGuest)
            StreamBuilder<List<RealtyMatch>>(
              stream: _repo.watchMyMatches(limit: 20),
              builder: (context, snap) {
                final unseen =
                    (snap.data ?? const <RealtyMatch>[]).where((m) => !m.seen).length;
                return IconButton(
                  key: const ValueKey('realty_alerts_entry'),
                  tooltip: context.tr('realty_alerts_title'),
                  icon: Badge(
                    isLabelVisible: unseen > 0,
                    label: Text('$unseen'),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RealtyAlertsScreen()),
                  ),
                );
              },
            ),
          // Харита энди алоҳида тўлиқ экранда — бу ердан шу тугма
          // орқали очилади.
          if (!_isGuest)
            IconButton(
              tooltip: context.tr('realty_map_title'),
              icon: const Icon(Icons.map_outlined),
              onPressed: _openMap,
            ),
          // «Эълон қўшиш» — матнсиз, доира ичида, сарлавҳа қаторининг
          // ўнг бурчагида (эга қарори, 2026-09-28). Аввал сузувчи кенг
          // тугма эди ва пастдаги харитани доим ёпиб турарди.
          RealtyAddButton(onTap: _openAdd),
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
      body: Column(
        children: [
          RealtyDealFilter(
            deal: _deal,
            onChanged: (d) => setState(() => _deal = d),
          ),
          GeoTierBar(
            moduleId: 'realty',
            scope: _scope,
            onChanged: (s) => setState(() => _scope = s),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                for (final tier in RealtyTabs.order)
                  _TierFeed(
                    key: ValueKey('${tier.key}_${_deal?.key}_${_scope.key}'),
                    repo: _repo,
                    tier: tier,
                    deal: _deal,
                    scope: _scope,
                    onOpen: _openDetail,
                    onScope: (s) => setState(() => _scope = s),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _TierFeed extends StatefulWidget {
  const _TierFeed({
    super.key,
    required this.repo,
    required this.tier,
    required this.deal,
    required this.scope,
    required this.onOpen,
    required this.onScope,
  });

  final RealtyRepository repo;
  final RealtyTier tier;
  final RealtyDeal? deal;
  final GeoScope scope;
  final ValueChanged<RealtyListing> onOpen;
  final ValueChanged<GeoScope> onScope;

  @override
  State<_TierFeed> createState() => _TierFeedState();
}

class _TierFeedState extends State<_TierFeed> {
  // Оқим state'да (калит — тур/битим/ҳудуд): rebuild янги listener очмасин.
  late final Stream<List<RealtyListing>> _stream = widget.repo
      .watchScoped(widget.scope, tier: widget.tier, deal: widget.deal, limit: 50);

  RealtyTier get tier => widget.tier;
  ValueChanged<RealtyListing> get onOpen => widget.onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final wider = GeoWiderHint(
      moduleId: 'realty',
      scope: widget.scope,
      onChanged: widget.onScope,
    );
    return StreamBuilder<List<RealtyListing>>(
      stream: _stream,
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
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                context.tr(
                  tier == RealtyTier.plain
                      ? 'realty_feed_empty'
                      : 'realty_feed_paid_empty',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.ink2, fontSize: AppText.bodyMedium),
              ),
              wider,
            ],
          );
        }
        final showWider = items.length < 5;
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
          itemCount: items.length + (showWider ? 1 : 0),
          itemBuilder: (_, i) => i == items.length
              ? wider
              : RealtyCard(listing: items[i], onTap: () => onOpen(items[i])),
        );
      },
    );
  }
}
