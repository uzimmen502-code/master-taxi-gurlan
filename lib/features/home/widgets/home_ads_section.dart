import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/geo/geo_context.dart';
import '../../../core/geo/geo_names.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/fair_mix.dart';
import '../../../core/utils/session_shuffle.dart';
import '../../../models/job_ad.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/jobs_repository.dart';
import '../../../repositories/realty_repository.dart';
import '../../business_map/data/business_repository.dart';
import '../../jobs/jobs_sections.dart';
import '../../markets/data/market_taxonomy_repository.dart';
import '../../markets/domain/market_taxonomy.dart';
import '../../restaurants/data/restaurants_repository.dart';
import '../../restaurants/domain/restaurant_models.dart';
import '../../restaurants/domain/restaurants_access.dart';
import '../../tv_market/models/tv_shop.dart';
import '../home_demo_feed.dart';
import '../home_strip_mix.dart';
import 'ava_section.dart';
import 'home_row_badge.dart';

/// 2 ва 3-бўлимлар: «Яқинингиздаги эълонлар» ва «…хизмат таклифлари».
///
/// Иккаласи ҳам `ads` коллекциясидан, фақат `type` билан фарқланади —
/// шунинг учун битта виджет.
class HomeAdsSection extends StatefulWidget {
  const HomeAdsSection({
    super.key,
    required this.adType,
    required this.titleKey,
    required this.onOpenAll,
    required this.onOpenAd,
    this.onOpenShopItem,
    this.onOpenRealty,
    this.onOpenRestaurant,
  });

  /// «Яқиндаги эълонлар» қўшимчалари (фақат `adType == 'ad'`, эга 2026-11-16/17): мол/мошина (таксономия
  /// `showInNearbyAds`), деҳқон (дўкон эмас), ишлатилган хусусий электроника/маиший техника, ҳар қандай
  /// хусусий сотувчи маҳсулоти (гўштдан ташқари, Аралаш ҳам — эга 2026-11-19) — `tv_shop_items`;
  /// фаол уй-жой; янги уй ошпазлари. `null` — шу манба кўрсатилмайди.
  final void Function(TvShopItem item, List<TvShopItem> shelf)? onOpenShopItem;
  final void Function(RealtyListing listing)? onOpenRealty;
  final void Function(Restaurant restaurant)? onOpenRestaurant;

  /// Қўшимча қаторлар сони (маҳсулот + уй-жой).
  static const extrasLimit = 10;

  /// Уй-жой сўрови (тасма ҳудуди, енгил).
  static const realtyLimit = 10;

  /// «Янги уй ошпази» карточкалари сони.
  static const newCooksLimit = 2;

  /// Шу қурилмада очилган «Янги уй ошпази» карточкалари (бир марталик; сервер ёзуви йўқ).
  static const seenCooksPrefsKey = 'home_new_home_cook_seen';

  /// Эълонлар учун `ad`, хизмат таклифлари учун `service`.
  final String adType;
  final String titleKey;
  final VoidCallback onOpenAll;
  final void Function(JobAd ad) onOpenAd;

  /// Реал эълонлар шунчагача кўрсатилади; қолган жой намунавий
  /// қаторларга берилади (қаранг: [HomeDemoFeed]).
  static const limit = HomeDemoFeed.capacity;

  @override
  State<HomeAdsSection> createState() => _HomeAdsSectionState();
}

class _HomeAdsSectionState extends State<HomeAdsSection> {
  final _repo = JobsRepository();
  final Random _rnd = sessionRandom();
  StreamSubscription<List<JobAd>>? _sub;

  AvaSectionStatus _status = AvaSectionStatus.loading;
  List<JobAd> _items = const [];

  List<NearbyAdExtra> _extras = const [];
  List<Restaurant> _newCooks = const [];

  bool get _withExtras => widget.adType == 'ad';

  @override
  void initState() {
    super.initState();
    _listen();
    if (_withExtras && (widget.onOpenShopItem != null || widget.onOpenRealty != null)) unawaited(_loadExtras());
    if (_withExtras && widget.onOpenRestaurant != null) unawaited(_loadNewCooks());
  }

  static Future<T> _safe<T>(Future<T> Function() f, T fallback, String code) async {
    try {
      return await f();
    } catch (e) {
      debugPrint('[HomeAds] $code: $e');
      return fallback;
    }
  }

  Future<void> _loadExtras() async {
    final scope = GeoContext.homeScopeFor('jobs');
    final user = GeoContext.active;
    final shopF = widget.onOpenShopItem == null
        ? Future.value(const <TvShopItem>[])
        : _safe(HomeShopFeed.recent, const <TvShopItem>[], 'HOME_ADS_SHOP_FAILED');
    final taxF = _safe<MarketTaxonomy?>(MarketTaxonomyRepository.load, null, 'HOME_ADS_TAXONOMY_FAILED');
    final realtyF = widget.onOpenRealty == null
        ? Future.value(const <RealtyListing>[])
        : _safe(() => RealtyRepository().watchScoped(scope, limit: HomeAdsSection.realtyLimit).first,
            const <RealtyListing>[], 'HOME_ADS_REALTY_FAILED');
    final shop = await shopF;
    final tax = await taxF;
    final realty = await realtyF;
    // Деҳқон маҳсулоти объектлари — сеанс кешидан, янгилари ≤30 талик whereIn бўлаклари билан.
    final farmIds = farmBusinessIds(shop);
    final cats = farmIds.isEmpty
        ? const <String, String?>{}
        : await HomeBusinessCategoryCache.resolve(farmIds, BusinessRepository().fetchCategoriesByIds);
    if (!mounted) return;
    setState(() {
      _extras = buildNearbyAdExtras(
        shop: shop,
        realty: realty,
        categories: nearbyAdsCategories(tax),
        businessCategories: cats,
        scope: scope,
        userDistrictId: user.districtId,
        userRegionId: user.regionId,
        limit: HomeAdsSection.extrasLimit,
      );
    });
  }

  Future<void> _loadNewCooks() async {
    final repo = RestaurantsRepository();
    final ok = await _safe(() => resolveRestaurantsAccess(accessCheck: repo.hasAccess), false,
        'HOME_ADS_RESTAURANTS_ACCESS_FAILED');
    if (!ok) return;
    final now = DateTime.now();
    final list = await _safe(() => repo.fetchRecentApproved(since: now.subtract(kNewHomeCookWindow)),
        const <Restaurant>[], 'HOME_ADS_NEW_COOKS_FAILED');
    if (list.isEmpty) return;
    final seen = await _safe(() async {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(HomeAdsSection.seenCooksPrefsKey) ?? const <String>[]).toSet();
    }, <String>{}, 'HOME_ADS_SEEN_COOKS_READ_FAILED');
    if (!mounted) return;
    setState(() => _newCooks = newHomeCooks(list, now, dismissed: seen).take(HomeAdsSection.newCooksLimit).toList());
  }

  /// Бир марталик: очилгач шу қурилмада қайта кўрсатилмайди.
  void _openNewCook(Restaurant r) {
    setState(() => _newCooks = [for (final x in _newCooks) if (x.id != r.id) x]);
    unawaited(_safe(() async {
      final prefs = await SharedPreferences.getInstance();
      final seen = (prefs.getStringList(HomeAdsSection.seenCooksPrefsKey) ?? const <String>[]).toList();
      if (!seen.contains(r.id)) {
        seen.add(r.id);
        // Чексиз ўсмасин: охирги 50 таси (7 кунлик ойна учун етарли).
        await prefs.setStringList(HomeAdsSection.seenCooksPrefsKey, seen.length > 50 ? seen.sublist(seen.length - 50) : seen);
      }
    }, null, 'HOME_ADS_SEEN_COOKS_WRITE_FAILED'));
    widget.onOpenRestaurant?.call(r);
  }

  void _openExtra(NearbyAdExtra e) {
    final shop = e.shop;
    if (shop != null) {
      widget.onOpenShopItem?.call(shop, [for (final x in _extras) if (x.shop != null) x.shop!]);
    } else {
      widget.onOpenRealty?.call(e.realty!);
    }
  }

  void _listen() {
    _sub?.cancel();
    if (mounted) setState(() => _status = AvaSectionStatus.loading);
    _sub = _repo
        // `jobs` модули танлови (туман/вилоят/Республика) — экран билан
        // бир хил (D-GEO-1).
        .watchScoped(
          GeoContext.homeScopeFor('jobs'),
          types: [widget.adType],
          limit: HomeAdsSection.limit,
        )
        .listen(
      (list) {
        if (!mounted) return;
        setState(() {
          // Ҳар очилишда бошқа тартиб; кўрилиб турганлар ўрнида қолади.
          _items = mergeShuffled(
            current: _items,
            incoming: list,
            idOf: (a) => a.id,
            random: _rnd,
          );
          // Намунавий қаторлар доим бор, шунинг учун «бўш» ҳолат йўқ.
          _status = AvaSectionStatus.ready;
        });
      },
      onError: (Object e) {
        debugPrint('[HomeAds ${widget.adType}] $e');
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
    // Реал эълонлардан кейин қолган жой намунавий қаторларга берилади;
    // реал эълон 10 тага етганда улар ўз-ўзидан йўқолади.
    final demo = HomeDemoFeed.fill(
      context,
      keys: widget.adType == 'service'
          ? HomeDemoFeed.serviceKeys
          : HomeDemoFeed.adKeys,
      realCount: _items.length + _extras.length + _newCooks.length,
      random: _rnd,
    );
    return AvaSection(
      // Сарлавҳа доираси — бренд рангида (эга қарори 2026-10-18; аввал
      // «Эълонлар» яшил, «Хизматлар» жигарранг эди).
      moduleId: JobsSections.tileIdFor(AdKindX.parse(widget.adType)),
      title: context.tr(widget.titleKey),
      status: _status,
      onSeeAll: widget.onOpenAll,
      onRetry: _listen,
      // Ботиқ майдон — қаторлар унинг ичида (қаранг: [AvaInsetPanel]).
      child: AvaInsetPanel(
        child: AvaRowPager(
          rowHeight: AvaRowPager.textRowHeight(context),
          onOpenModule: widget.onOpenAll,
          rows: [
            for (final r in _newCooks)
              _AdTitleRow(
                key: ValueKey('home_ads_new_cook_${r.id}'),
                title: newHomeCookTitle(context.tr('home_ads_new_home_cook'), r),
                badge: context.tr('home_badge_home_food'),
                onTap: () => _openNewCook(r),
              ),
            // Иш/хизмат эълонлари аввалгидек; қўшимчалар навбатма-навбат аралашади.
            for (final entry in FairMix.roundRobin<Object>([_items, _extras]))
              if (entry is NearbyAdExtra)
                _AdTitleRow(
                  key: ValueKey('home_ads_extra_${entry.id}'),
                  title: entry.shop == null
                      ? entry.title
                      : nearbyShopRowText(
                          title: entry.title,
                          price: entry.shop!.priceLabel(context.tr),
                          district: GeoNames.district(entry.shop!.districtId, context.contentLang,
                              fallback: entry.shop!.districtLabel),
                        ),
                  badge: context.tr(entry.badgeKey) == entry.badgeKey ? '' : context.tr(entry.badgeKey),
                  onTap: () => _openExtra(entry),
                )
              else
                _AdTitleRow(
                  title: (entry as JobAd).titleOrText,
                  onTap: () => widget.onOpenAd(entry),
                ),
            for (final label in demo)
              _AdTitleRow(title: label, onTap: widget.onOpenAll),
          ],
        ),
      ),
    );
  }
}

/// Битта эълон сарлавҳаси — қора нуқта (●) + матн, битта қатор.
class _AdTitleRow extends StatelessWidget {
  const _AdTitleRow({super.key, required this.title, required this.onTap, this.badge = ''});

  final String title;

  /// Бозор белгиси («Мол», «Уй-жой», «Уй таоми»); бўш — йўқ.
  final String badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    // Қаторлар ораси айнан 1px: ички вертикал чет йўқ, масофани
    // `Column`даги 1px оралиқ беради.
    return InkWell(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: c.ink,
              shape: BoxShape.circle,
            ),
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
          if (badge.isNotEmpty) HomeRowBadge(badge),
        ],
      ),
    );
  }
}
