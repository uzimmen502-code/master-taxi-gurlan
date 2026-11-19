import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/geo/geo_context.dart';
import '../../../core/geo/geo_tier_bar.dart';
import '../../../core/geo/module_geo_policy.dart' show GeoLevel;
import '../../../core/geo/relative_location.dart';
import '../../../core/geo/ring_feed.dart';
import '../../../core/geo/ring_query.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/realty_alert.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../../../shared/widgets/market_add_button.dart';
import '../../../shared/widgets/market_search_field.dart';
import '../../onboarding/screens/onboarding_screen.dart';
import '../data/realty_ring_source.dart';
import '../realty_tabs.dart';
import '../widgets/realty_card.dart';
import '../widgets/realty_controls.dart';
import '../widgets/realty_package_sheet.dart';
import 'add_realty_listing_screen.dart';
import 'realty_detail_screen.dart';
import 'realty_alerts_screen.dart';
import 'realty_map_screen.dart';

/// 🏠 «Уй-жой бозори» (аввал «Кўчмас мулк Кластери») — ЛЕНТА экрани.
///
/// Тузилиши концепциянинг 1-бўлимидан: учта TAB (ОДДИЙ / РЕКЛАМА /
/// СРОЧНО) ва танланган TAB лентаси.
///
/// Харита БУ ЕРДА ЙЎҚ (эга қарори, 2026-09-28) — у алоҳида тўлиқ
/// экранда (`RealtyMapScreen`), сарлавҳадаги харита тугмасидан ёки
/// бош саҳифадаги харита расмидан очилади.
///
/// «Бозорлар» 7-босқич (эга, 2026-11-15): бозор кўриниши — қизил «+», ҳудуд қатори (сукут — Республика
/// ҳалқалари, яқиндан узоққа; вилоят/туман танланса — фақат шу ҳудуд; танлов САҚЛАНМАЙДИ), карточкада нисбий жой.
/// 2026-11-16: «N та эълон» (`count()`) олиб ташланди; ихчам тепа қўшилди; қидирув йўқ (эга 2026-11-16: филтрлар орқали). Таблар ва Сотиш/Ижара — аввалгидек.
///
/// Кириш қоидаси (9-бўлим): лентани меҳмон ҳам кўради, харита ва эълон
/// жойлаштириш — фақат рўйхатдан ўтганлар учун.
class RealtyScreen extends StatefulWidget {
  const RealtyScreen({super.key, this.source});

  /// Тест учун (бўлмаса [FirestoreRealtyListingSource]).
  final RealtyListingSource? source;

  @override
  State<RealtyScreen> createState() => _RealtyScreenState();
}

class _RealtyScreenState extends State<RealtyScreen>
    with SingleTickerProviderStateMixin {
  final _repo = RealtyRepository();
  late final RealtyListingSource _source =
      widget.source ?? FirestoreRealtyListingSource();
  late final TabController _tabs =
      TabController(length: RealtyTabs.count, vsync: this)..addListener(_onTab);

  /// null — иккови ҳам (Сотиш ҳам, Ижара ҳам).
  RealtyDeal? _deal;

  /// Объект тури (эга 2026-11-19); null — барчаси. Клиент филтри.
  String? _type;

  /// Ҳудуд (GeoMode.rings): сукут — Республика ҳалқалари; танлов фақат экран очиқ турганда.
  GeoScope _scope = GeoContext.scopeFor('realty');

  bool get _isGuest =>
      FirebaseAuth.instance.currentUser?.isAnonymous ?? false;

  void _onTab() {
    if (!_tabs.indexIsChanging && mounted) setState(() {});
  }

  @override
  void dispose() {
    GeoContext.clearSessionScope('realty');
    _tabs.removeListener(_onTab);
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
        toolbarHeight: kMarketAppBarHeight,
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
          // Бозорлар услуби: кичик ҚИЗИЛ «+» (7-босқич; аввал доира ичидаги [RealtyAddButton]).
          MarketAddButton(
            key: const ValueKey('realty-add-ad'),
            onTap: _openAdd,
            tooltip: context.tr('market_add'),
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
              Tab(height: kMarketTabHeight, text: context.tr(RealtyTabs.labelKey(tier))),
          ],
        ),
      ),
      // Ихчам тепа (эга, 2026-11-16): Сотиш/Ижара, ҳудуд — орасида 1 px; «N та эълон» олиб ташланди.
      // Қидирув йўқ (эга, 2026-11-16: уй-жой филтрлар орқали топилади) — бошқа бозорларда қидирув қолади.
      body: Column(
        children: [
          RealtyDealFilter(
            compact: true,
            deal: _deal,
            onChanged: (d) => setState(() => _deal = d),
          ),
          const SizedBox(height: kMarketTopRowGap),
          RealtyTypeFilter(
            type: _type,
            onChanged: (t) => setState(() => _type = t),
          ),
          const SizedBox(height: kMarketTopRowGap),
          GeoTierBar(
            compact: true,
            moduleId: 'realty',
            scope: _scope,
            onChanged: (s) => setState(() => _scope = s),
          ),
          const SizedBox(height: kMarketTopRowGap),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                for (final tier in RealtyTabs.order)
                  _TierFeed(
                    key: ValueKey('${tier.key}_${_deal?.key}_${_type}_${_scope.key}'),
                    source: _source,
                    filter: RealtyRingFilter(tier: tier, deal: _deal, propertyType: _type),
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
    required this.source,
    required this.filter,
    required this.scope,
    required this.onOpen,
    required this.onScope,
  });

  final RealtyListingSource source;
  final RealtyRingFilter filter;
  final GeoScope scope;
  final ValueChanged<RealtyListing> onOpen;
  final ValueChanged<GeoScope> onScope;

  @override
  State<_TierFeed> createState() => _TierFeedState();
}

class _TierFeedState extends State<_TierFeed> {
  // Калит — тур/битим/ҳудуд: ўзгарса янги state (ва янги ҳалқа режаси).
  late final RingFeed<RealtyListing> _feed = RingFeed<RealtyListing>(tag: 'RealtyFeed')
    ..addListener(_changed)
    ..restart(
      RingPager<RealtyListing>(
        plan: ringPlanFor(widget.scope),
        fetch: widget.source.fetcher(widget.filter),
        districtsOf: widget.source.districtsOf,
      ),
      visibleWhere: widget.filter.shows,
    );

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _feed.removeListener(_changed);
    _feed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final tier = widget.filter.tier;
    // Аниқ танланган ҳудудда кам бўлса — кенгроқ ҳудуд таклифи (ҳалқаларда керак эмас: бутун Республика).
    final wider = widget.scope.level == GeoLevel.nation
        ? const SizedBox.shrink()
        : GeoWiderHint(moduleId: 'realty', scope: widget.scope, onChanged: widget.onScope);
    final items = _feed.visible();
    if (items.isEmpty && _feed.error != null) {
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
    if (items.isEmpty && (_feed.loading || !_feed.started)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty && !_feed.hasMore) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            context.tr(
              tier == RealtyTier.plain ? 'realty_feed_empty' : 'realty_feed_paid_empty',
            ),
            key: const ValueKey('realty_feed_empty'),
            textAlign: TextAlign.center,
            style: TextStyle(color: c.ink2, fontSize: AppText.bodyMedium),
          ),
          wider,
        ],
      );
    }
    final lang = context.contentLang;
    final user = GeoContext.active;
    return ListView.builder(
      key: ValueKey('realty_feed_${tier?.key}'),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
      itemCount: items.length + 1,
      itemBuilder: (_, i) {
        if (i == items.length) {
          if (!_feed.hasMore && !_feed.loading && items.length < 5) return wider;
          return RingFeedFooter(feed: _feed);
        }
        final r = items[i];
        return RealtyCard(
          listing: r,
          locationLabel: realtyLocationLabel(r, user, lang),
          onTap: () => widget.onOpen(r),
        );
      },
    );
  }
}

/// Уй-жой эълонининг НИСБИЙ жойи — фақат туман/вилоят даражаси (аниқ манзил ЭМАС: у пуллик ахборот).
String realtyLocationLabel(RealtyListing r, GeoArea user, String lang) => relativeLocationLabel(
      itemDistrictId: r.districtId,
      itemRegionId: r.regionId,
      userDistrictId: user.districtId,
      userRegionId: user.regionId,
      lang: lang,
    );
