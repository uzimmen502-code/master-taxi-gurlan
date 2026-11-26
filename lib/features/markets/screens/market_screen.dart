import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/geo/geo_context.dart';
import '../../../core/geo/geo_query.dart';
import '../../../core/geo/module_geo_policy.dart';
import '../../../core/geo/geo_tier_bar.dart';
import '../../../core/geo/relative_location.dart';
import '../../../core/geo/ring_query.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/catalog_search.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../../shared/widgets/market_search_field.dart';
import '../../business_orders/screens/business_cart_screen.dart';
import '../../home/home_strip_mix.dart' show HomeShopFeed;
import '../../my_shop/my_shop_entry.dart';
import '../../supermarket/data/holiday_repository.dart' show FirebaseHolidayApi, HolidayCatalogCache;
import '../../supermarket/domain/sm_holiday.dart'
    show kQurbonReadyAttr, qurbonMarketActive, qurbonReady, smTashkentDate;
import '../../tv_market/models/tv_shop.dart';
import '../../tv_market/screens/tv_shop_item_detail_screen.dart';
import '../../tv_market/widgets/tv_shop_photo_gallery.dart' show precacheCardCovers;
import '../data/market_listings_source.dart';
import '../data/market_search.dart';
import '../data/market_taxonomy_repository.dart';
import '../domain/market_taxonomy.dart';
import '../widgets/auto_parts_header.dart';
import '../widgets/market_listing_card.dart';

/// «Бозорлар» умумий экрани (6-босқич, эга 2026-11-15) — битта экран, таксономия бошқаради (Мол / Мошина /
/// Гўшт / Деҳқон).
///
/// * AppBar: бозор номи + қизил «+» (форма — бозор ва жорий бўлим олдиндан танланган).
/// * Бўлимлар: Мошина — 4 таб («Барчаси»сиз); Гўшт — Барчаси + бўлимлар + «Импорт» чипи (барча турлар бўйича
///   `imported == true`); Деҳқон — Барчаси + чиплар; Мол — йўқ (битта аралаш бўлим).
/// * Ҳудуд: сукут — Республика ҳалқалари (яқиндан узоққа, [RingPager]); вилоят/туман танланса — фақат шу ҳудуд.
///   Танлов САҚЛАНМАЙДИ (модул қоидаси `persistSelection: false`; экран ёпилганда тозаланади).
/// * Нарх филтри — КЛИЕНТДА (юкланган саҳифалар устида); тартиб — «Янгилар» (ҳалқа ичида `createdAt desc`).
/// * Сон («N та эълон») ва унинг `count()` сўрови олиб ташланди (эга, 2026-11-16).
/// * Қидирув (эга, 2026-11-16): шу бозор ичида. ≥2 белги — 350 мс дан кейин СЕРВЕР сўрови (`searchTokens`, биринчи
///   сўз, энг янгиси олдин, 40 тадан саҳифа; [MarketSearchRequest]) + юкланган саҳифалардаги клиент мослари, id бўйича
///   бирлаштирилади (эски эълонларда токен бўлмаслиги мумкин). Бўлим/«Импорт»/нарх/ҳудуд ва қолган сўзлар — клиентда.
///   Индекс хатоси — шу сессияда фақат клиент қидируви; бошқа хато — умумий хабар + лог.
/// * Тепа қисм ихчам: паст AppBar, қидирув, чиплар, ҳудуд ва филтр қаторлари орасида 1 px.
class MarketScreen extends StatefulWidget {
  const MarketScreen({
    super.key,
    required this.marketId,
    this.source,
    this.loadTaxonomy,
    this.openAdd,
    this.openDetail,
    this.pageSize = 20,
    this.initialCategory = '',
    this.partsHeader,
    this.cachedItems,
    this.qurbonCheck,
  });

  /// Қурбон ҳайит даври шу бозор учун фаолми (эга 2026-11-27). Тест учун; бўлмаса — байрам каталоги кешидан
  /// ([qurbonMarketActive]; бозор id байрам `target`идан).
  final Future<bool> Function(String marketId)? qurbonCheck;

  /// Дарҳол чизиш учун аллақачон юкланган маҳсулотлар (бўлмаса [HomeShopFeed.cachedItems] — уй тасмаси
  /// кеши). Сервер саҳифалари келгач алмаштирилади (эга 2026-11-19, тезлик).
  final List<TvShopItem>? Function()? cachedItems;

  /// Очилишда танланган бўлим (мас. «Менинг машинам» → Мошина бозори «Эҳтиёт қисмлар», 9-босқич).
  /// Таксономияда йўқ бўлса — сукут (биринчи таб / «Барчаси»).
  final String initialCategory;

  /// Тест учун: «Эҳтиёт қисмлар» тепасидаги AVA блоки (бўлмаса [AutoPartsAvaHeader]).
  final WidgetBuilder? partsHeader;

  final String marketId;

  /// Тест учун (бўлмаса [FirestoreMarketListingSource]).
  final MarketListingSource? source;
  final Future<MarketTaxonomy> Function()? loadTaxonomy;

  /// Тест учун: қизил «+» (бўлмаса [openNewProduct] бозор/бўлим билан).
  final Future<void> Function(BuildContext context, String market, String category)? openAdd;

  /// Тест учун: карточка босилганда (бўлмаса [TvShopItemDetailScreen]).
  final void Function(BuildContext context, TvShopItem item)? openDetail;

  final int pageSize;

  /// Биринчи саҳифа кичик ва биринчи бўш бўлмаган ҳалқадан кейиноқ қайтади ([RingPager.next] `firstNonEmpty`).
  static const firstPageSize = 8;

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  static const _addRed = Color(0xFFF44336); // Аралаш «+» билан бир хил (cheap_products_screen).

  late final MarketListingSource _source = widget.source ?? FirestoreMarketListingSource();

  MarketTaxonomy? _taxonomy;
  Object? _taxonomyError;
  MarketDef? get _def => _taxonomy?.market(widget.marketId);

  String _category = '';
  bool _importedOnly = false;

  // Қурбон ҳайит (эга 2026-11-27): давр фаол бўлса — баннер ва «Қурбонликка мос» чипи (клиент филтри).
  bool _qurbonPeriod = false;
  bool _qurbonOnly = false;

  bool _hasQurbonField(MarketDef m) => m.fields.any((f) => f.key == kQurbonReadyAttr);

  Future<void> _checkQurbon() async {
    try {
      final ok = await (widget.qurbonCheck ?? _defaultQurbonCheck)(widget.marketId);
      if (mounted && ok != _qurbonPeriod) setState(() => _qurbonPeriod = ok);
    } catch (e) {
      debugPrint('[MarketScreen] QURBON_CHECK_FAILED market=${widget.marketId}: $e');
    }
  }

  static Future<bool> _defaultQurbonCheck(String marketId) async {
    final cat = await HolidayCatalogCache.get(FirebaseHolidayApi());
    return qurbonMarketActive(cat.occasions, marketId, smTashkentDate());
  }

  void _toggleQurbon() => setState(() {
        _qurbonOnly = !_qurbonOnly;
        _emptyStreak = 0;
      });
  GeoScope? _scope;
  int? _minPrice;
  int? _maxPrice;

  RingPager<TvShopItem>? _pager;
  final List<RingItem<TvShopItem>> _items = [];

  /// Кешдан дарҳол чизилган элементлар ([marketSeedItems]); сервер ўша ҳалқани тугатгач — олиб ташланади.
  List<RingItem<TvShopItem>> _seed = const [];
  bool _loading = false;
  Object? _pageError;

  /// Ораларида кўринадиган эълон қўшмаган кетма-кет саҳифалар (нарх филтри) — 3 дан кейин автоматик юклаш
  /// тўхтайди, «Яна кўрсатиш» тугмаси чиқади (чексиз ўқиш бўлмасин, 37-банд).
  int _emptyStreak = 0;
  int _gen = 0;

  /// Бозор ичидаги қидирув: клиент филтри дарҳол ([_query]), сервер сўрови — debounce'дан кейин.
  final _searchCtrl = TextEditingController();
  String _query = '';
  Timer? _searchTimer;
  int _searchGen = 0;
  MarketSearchRequest? _searchReq;
  final List<TvShopItem> _serverHits = [];
  Object? _serverCursor;
  bool _serverHasMore = false;
  bool _serverLoading = false;

  /// Индекс йўқ (`failed-precondition`) — шу экран сессиясида фақат клиент қидируви.
  bool _serverSearchOff = false;

  /// Вилоят танланганда сервер натижаларини ҳудуд бўйича филтрлаш учун ([inGeoScope]).
  Set<String> _regionDistricts = const {};

  @override
  void initState() {
    super.initState();
    // Сеанс кешида таксономия бор — спиннерсиз, биринчи кадрдаёқ (эга 2026-11-19, тезлик).
    final cached = widget.loadTaxonomy == null ? MarketTaxonomyRepository.cached : null;
    if (cached != null) {
      _applyTaxonomy(cached);
    } else {
      _loadTaxonomy();
    }
    unawaited(_checkQurbon());
  }

  @override
  void dispose() {
    final m = _def;
    if (m != null) GeoContext.clearSessionScope(m.moduleId);
    _searchTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTaxonomy() async {
    setState(() => _taxonomyError = null);
    try {
      final t = await (widget.loadTaxonomy ?? MarketTaxonomyRepository.load)();
      if (!mounted) return;
      _applyTaxonomy(t);
    } catch (e) {
      debugPrint('[MarketScreen] MARKET_TAXONOMY_LOAD_FAILED market=${widget.marketId}: $e');
      if (mounted) setState(() => _taxonomyError = e);
    }
  }

  void _applyTaxonomy(MarketTaxonomy t) {
    final m = t.market(widget.marketId);
    setState(() {
      _taxonomy = t;
      if (m != null) {
        final initial = widget.initialCategory.trim();
        final hasInitial = initial.isNotEmpty && m.categories.any((c) => c.id == initial);
        _category = hasInitial ? initial : (m.usesTabs ? m.categories.first.id : '');
        _scope = GeoContext.scopeFor(m.moduleId);
      }
    });
    if (m != null) _restart();
  }

  /// Биринчи ~6 муқова олдиндан юкланади (карточка ўлчамида).
  void _precacheCovers(Iterable<TvShopItem> items) {
    final urls = [for (final i in items) i.coverPhotoUrl].where((u) => u.trim().isNotEmpty).toList();
    if (urls.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) precacheCardCovers(context, urls, MarketListingCard.photoSize);
    });
  }

  MarketFilter get _filter =>
      MarketFilter(market: widget.marketId, category: _category, importedOnly: _importedOnly);

  /// Филтр ёки ҳудуд ўзгарди — рўйхат қайтадан.
  void _restart() {
    final scope = _scope;
    if (scope == null) return;
    _gen++;
    _items.clear();
    _pageError = null;
    _loading = false;
    _emptyStreak = 0;
    final plan = ringPlanFor(scope);
    _pager = RingPager<TvShopItem>(
      plan: plan,
      fetch: _source.fetcher(_filter),
      districtsOf: _source.districtsOf,
    );
    _seed = marketSeedItems(
      (widget.cachedItems ?? HomeShopFeed.cachedItems)() ?? const [],
      filter: _filter,
      plan: plan,
    );
    _precacheCovers(_seed.map((r) => r.item));
    setState(() {});
    _loadMore();
    unawaited(_loadRegionDistricts(scope));
    if (_searchReq != null || _serverHits.isNotEmpty) _startServerSearch(_query);
  }

  Future<void> _loadRegionDistricts(GeoScope scope) async {
    final rid = scope.area.regionId.trim();
    if (scope.level != GeoLevel.region || rid.isEmpty) {
      _regionDistricts = const {};
      return;
    }
    try {
      final ids = await _source.districtsOf(rid);
      if (mounted && identical(scope, _scope)) setState(() => _regionDistricts = ids.toSet());
    } catch (e) {
      debugPrint('[MarketScreen] MARKET_REGION_DISTRICTS_FAILED region=$rid: $e');
    }
  }

  bool get _searchActive => _searchReq != null;

  /// Сервер қидирувини янгидан бошлайди (сўров/филтр/ҳудуд ўзгарди). Токен чиқмаса ёки индекс йўқ бўлса —
  /// фақат клиент.
  void _startServerSearch(String q) {
    _searchTimer?.cancel();
    _searchGen++;
    _serverHits.clear();
    _serverCursor = null;
    _serverLoading = false;
    _serverHasMore = false;
    _searchReq = _serverSearchOff ? null : MarketSearchRequest.forQuery(q, market: widget.marketId);
    if (mounted) setState(() {});
    if (_searchReq != null) {
      _serverHasMore = true;
      _loadServerPage();
    }
  }

  Future<void> _loadServerPage() async {
    final req = _searchReq;
    if (_serverLoading || req == null || !_serverHasMore) return;
    final gen = _searchGen;
    setState(() => _serverLoading = true);
    try {
      final page = await _source.search(req, startAfter: _serverCursor);
      if (!mounted || gen != _searchGen) return;
      final visibleAdded = page.items.where(_serverShows).length;
      setState(() {
        _serverHits.addAll(page.items);
        _serverCursor = page.cursor;
        _serverHasMore = page.hasMore;
        _serverLoading = false;
        _emptyStreak = visibleAdded == 0 ? _emptyStreak + 1 : 0;
      });
    } catch (e) {
      final code = marketSearchErrorCode(e);
      debugPrint('[MarketScreen] $code market=${widget.marketId} tokenLen=${req.token.length}: $e');
      if (!mounted || gen != _searchGen) return;
      final indexMissing = isMarketSearchIndexError(e);
      setState(() {
        _serverLoading = false;
        _serverHasMore = false;
        if (indexMissing) _serverSearchOff = true;
      });
      // Индекс хатоси — жим (клиент натижалари қолади); бошқа хато — умумий хабар.
      if (!indexMissing) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(context.tr('search_error_internet'))));
      }
    }
  }

  /// Сервер топган эълон шу экран филтрларига мосми (бўлим/«Импорт»/ҳудуд/нарх/барча сўзлар — клиентда).
  bool _serverShows(TvShopItem i) {
    final scope = _scope;
    if (!i.isActive || i.market != widget.marketId) return false;
    if (_category.isNotEmpty && i.category != _category) return false;
    if (_importedOnly && i.imported != true) return false;
    if (scope != null &&
        !(inGeoScope(i.districtId, scope, _regionDistricts) ||
            (scope.level == GeoLevel.region && i.regionId.isNotEmpty && i.regionId == scope.area.regionId))) {
      return false;
    }
    return priceInRange(i.price, _minPrice, _maxPrice) && marketServerItemMatches(i, _query) && _qurbonShows(i);
  }

  bool _qurbonShows(TvShopItem i) => !_qurbonOnly || qurbonReady(i.attrs);

  /// Рўйхат охири: қидирувда аввал сервер саҳифалари, кейин одатий ҳалқа саҳифалари (токенсиз эски эълонлар).
  void _loadNext() {
    if (_searchActive && _serverHasMore) {
      _loadServerPage();
    } else {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    final pager = _pager;
    if (_loading || pager == null || !pager.hasMore) return;
    final gen = _gen;
    setState(() {
      _loading = true;
      _pageError = null;
    });
    try {
      final first = _items.isEmpty;
      final page = await pager.next(
        first && widget.pageSize > MarketScreen.firstPageSize ? MarketScreen.firstPageSize : widget.pageSize,
        firstNonEmpty: first,
      );
      if (!mounted || gen != _gen) return;
      final visibleAdded = page.where((r) => _shows(r.item)).length;
      if (first && _seed.isEmpty) _precacheCovers(page.map((r) => r.item));
      setState(() {
        _items.addAll(page);
        _loading = false;
        _emptyStreak = visibleAdded == 0 ? _emptyStreak + 1 : 0;
      });
    } catch (e) {
      debugPrint('[MarketScreen] MARKET_LIST_LOAD_FAILED market=${widget.marketId} '
          'category=$_category imported=$_importedOnly: $e');
      if (!mounted || gen != _gen) return;
      setState(() {
        _loading = false;
        _pageError = e;
      });
    }
  }

  /// Нарх ва қидирув филтри (иккаласи ҳам клиентда).
  bool _shows(TvShopItem i) =>
      priceInRange(i.price, _minPrice, _maxPrice) && marketItemMatchesQuery(i, _query) && _qurbonShows(i);

  List<TvShopItem> get _visible {
    final local = [
      for (final r in mergeRingSeed(_items, _seed, currentRing: _pager?.currentRing, idOf: (i) => i.id))
        if (_shows(r.item)) r.item,
    ];
    if (!_searchActive) return local;
    // Қидирувда ҳалқа тартиби эмас — энг янгиси олдин (клиент + сервер, такрорсиз).
    return mergeMarketSearch(local, _serverHits.where(_serverShows));
  }

  void _onQuery(String v) {
    setState(() {
      _query = v;
      _emptyStreak = 0;
    });
    _searchTimer?.cancel();
    if (v.trim().length < kMarketSearchMinChars) {
      // Қисқа/бўш сўров — фақат клиент; эски сервер натижалари дарҳол тозаланади.
      if (_searchReq != null || _serverHits.isNotEmpty) _startServerSearch('');
      return;
    }
    _searchTimer = Timer(kMarketSearchDebounce, () {
      if (mounted) _startServerSearch(_query);
    });
  }

  void _clearQuery() {
    _searchCtrl.clear();
    _onQuery('');
  }

  void _setCategory(String c) {
    if (c == _category) return;
    _category = c;
    _restart();
  }

  void _toggleImported() {
    _importedOnly = !_importedOnly;
    _restart();
  }

  Future<void> _openAdd() async {
    final custom = widget.openAdd;
    if (custom != null) return custom(context, widget.marketId, _category);
    await openNewProduct(context, market: widget.marketId, category: _category.isEmpty ? null : _category);
  }

  void _openItem(TvShopItem item) {
    final custom = widget.openDetail;
    if (custom != null) return custom(context, item);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TvShopItemDetailScreen(
        item: item,
        showShopButton: true,
        similarPool: _visible,
        source: 'market',
      ),
    ));
  }

  Future<void> _editPrice() async {
    final res = await showModalBottomSheet<(int?, int?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PriceSheet(min: _minPrice, max: _maxPrice),
    );
    if (res == null || !mounted) return;
    setState(() {
      _minPrice = res.$1;
      _maxPrice = res.$2;
      _emptyStreak = 0;
    });
  }

  String _priceChipLabel() {
    if (_minPrice == null && _maxPrice == null) return context.tr('market_price_filter');
    final a = _minPrice == null ? '' : formatPrice(_minPrice!);
    final b = _maxPrice == null ? '' : formatPrice(_maxPrice!);
    return '$a – $b';
  }

  Widget _addButton() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Center(
          child: InkWell(
            key: const ValueKey('market-add-ad'),
            customBorder: const CircleBorder(),
            onTap: _openAdd,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: _addRed, borderRadius: BorderRadius.circular(9)),
                  child: Tooltip(
                    message: context.tr('market_add'),
                    child: const Icon(Icons.add, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _chip(String key, String label, bool selected, VoidCallback onTap) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: ValueKey(key),
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        selectedColor: c.brandSoft,
        backgroundColor: c.chip,
        side: BorderSide(color: selected ? c.brand : c.line, width: selected ? 1.5 : 1),
        labelStyle: TextStyle(fontSize: 13, color: c.ink, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  /// Гўшт/Деҳқон: Барчаси + бўлимлар (+ «Импорт»).
  Widget? _categoryChips(MarketDef m) {
    if (!m.hasCategoryChoice || m.usesTabs) {
      if (!m.hasImported) return null;
    }
    final lang = context.contentLang;
    return SizedBox(
      height: kMarketTopRowHeight,
      child: SingleChildScrollView(
      key: const ValueKey('market_categories'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
      child: Row(children: [
        if (m.hasCategoryChoice && !m.usesTabs) ...[
          _chip('market_cat_all', context.tr('market_all'), _category.isEmpty, () => _setCategory('')),
          for (final c in m.categories)
            _chip('market_cat_${c.id}', c.label(lang), _category == c.id, () => _setCategory(c.id)),
        ],
        if (m.hasImported)
          _chip('market_imported_chip', context.tr('market_imported'), _importedOnly, _toggleImported),
      ]),
      ),
    );
  }

  Widget _filterRow(MarketDef m) {
    final scope = _scope!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: kMarketTopRowGap),
        GeoTierBar(
          compact: true,
          moduleId: m.moduleId,
          scope: scope,
          onChanged: (s) {
            _scope = s;
            _restart();
          },
        ),
        const SizedBox(height: kMarketTopRowGap),
        SizedBox(
          height: kMarketTopRowHeight,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              // Қурбон даврида биринчи — кўзга ташлансин.
              if (_qurbonPeriod && _hasQurbonField(m)) ...[
                FilterChip(
                  key: const ValueKey('market_qurbon_chip'),
                  label: Text(context.tr('market_qurbon_chip')),
                  selected: _qurbonOnly,
                  onSelected: (_) => _toggleQurbon(),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: 8),
              ],
              ActionChip(
                key: const ValueKey('market_price_chip'),
                avatar: const Icon(Icons.payments_outlined, size: 16),
                label: Text(_priceChipLabel()),
                onPressed: _editPrice,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 8),
              Chip(
                key: const ValueKey('market_sort_new'),
                avatar: const Icon(Icons.sort, size: 16),
                label: Text(context.tr('market_sort_new')),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ]),
          ),
        ),
        const SizedBox(height: kMarketTopRowGap),
      ],
    );
  }

  Widget _list(MarketDef m) {
    final visible = _visible;
    final hasMore = (_pager?.hasMore ?? false) || (_searchActive && _serverHasMore);
    final loading = _loading || _serverLoading;
    // Мошина бозори «Эҳтиёт қисмлар»: тепада AVA сервис + AVA маҳсулотлари, остида эълонлар (9-босқич).
    final header = showsAutoPartsHeader(m.id, _category)
        ? (widget.partsHeader?.call(context) ?? const AutoPartsAvaHeader())
        : null;
    if (visible.isEmpty && _pageError != null) {
      final err = LoadErrorView(error: _pageError!, onRetry: _loadMore);
      if (header == null) return err;
      return ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [header, err]);
    }
    if (visible.isEmpty && !hasMore && !loading) {
      final empty = Padding(
        padding: const EdgeInsets.all(24),
        child: Text(context.tr('market_empty'),
            key: const ValueKey('market_empty'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700)),
      );
      if (header == null) return Center(child: empty);
      return ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [header, empty]);
    }
    final lead = header == null ? 0 : 1;
    final lang = context.contentLang;
    final user = GeoContext.active;
    return ListView.builder(
      key: const ValueKey('market_list'),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: visible.length + 1 + lead,
      itemBuilder: (context, index) {
        if (header != null && index == 0) return header;
        final i = index - lead;
        if (i < visible.length) {
          final item = visible[i];
          return MarketListingCard(
            item: item,
            market: m,
            locationLabel: relativeLocationLabel(
              itemDistrictId: item.districtId,
              itemRegionId: item.regionId,
              userDistrictId: user.districtId,
              userRegionId: user.regionId,
              lang: lang,
              districtFallback: item.districtLabel,
            ),
            onTap: () => _openItem(item),
          );
        }
        // Охир: юкланмоқда / хато / автоматик кейинги саҳифа / «Яна кўрсатиш».
        if (_pageError != null) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: LoadErrorView(error: _pageError!, onRetry: _loadMore),
          );
        }
        if (loading) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (!hasMore) return const SizedBox(height: 8);
        if (_emptyStreak >= 3) {
          return Center(
            child: TextButton(
              key: const ValueKey('market_load_more'),
              onPressed: () {
                _emptyStreak = 0;
                _loadNext();
              },
              child: Text(context.tr('market_load_more')),
            ),
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadNext();
        });
        return const SizedBox(height: 48);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = _def;
    final lang = context.contentLang;
    final title = m?.label(lang) ?? '';
    Widget body;
    if (_taxonomyError != null) {
      body = LoadErrorView(error: _taxonomyError!, onRetry: _loadTaxonomy);
    } else if (_taxonomy == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (m == null || _scope == null) {
      body = LoadErrorView(messageKey: 'market_unavailable', onRetry: null);
    } else {
      final chips = _categoryChips(m);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MarketSearchField(
            fieldKey: const ValueKey('market_search'),
            controller: _searchCtrl,
            hintText: context.tr('market_search_hint'),
            onChanged: _onQuery,
            onClear: _clearQuery,
          ),
          if (_qurbonPeriod)
            Container(
              key: const ValueKey('market_qurbon_banner'),
              margin: const EdgeInsets.fromLTRB(12, kMarketTopRowGap, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: context.ava.brandSoft, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Icon(Icons.mosque, size: 18, color: context.ava.brandText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(context.tr('market_qurbon_banner'),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.ava.ink)),
                ),
              ]),
            ),
          if (chips != null) ...[
            const SizedBox(height: kMarketTopRowGap),
            chips,
          ],
          _filterRow(m),
          Expanded(child: _list(m)),
        ],
      );
    }
    final tabs = m != null && m.usesTabs;
    final scaffold = Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        // Ихчам тепа (эга, 2026-11-16).
        toolbarHeight: kMarketAppBarHeight,
        title: Text(title),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        // «Сават» (STAGE 11) — саватда нарса бўлса кўринади.
        actions: [const BusinessCartButton(color: AppColors.onPrimary), if (m != null) _addButton()],
        bottom: tabs
            ? TabBar(
                key: const ValueKey('market_tabs'),
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppColors.onPrimary,
                unselectedLabelColor: AppColors.onPrimary.withValues(alpha: 0.75),
                indicatorColor: AppColors.onPrimary,
                onTap: (i) => _setCategory(m.categories[i].id),
                tabs: [
                  for (final c in m.categories)
                    Tab(key: ValueKey('market_tab_${c.id}'), height: kMarketTabHeight, text: c.label(lang)),
                ],
              )
            : null,
      ),
      body: body,
    );
    if (!tabs) return scaffold;
    return DefaultTabController(
      length: m.categories.length,
      initialIndex: m.categories.indexWhere((c) => c.id == _category).clamp(0, m.categories.length - 1),
      child: scaffold,
    );
  }
}

/// Кешдаги маҳсулотлардан дарҳол чизиш (эга 2026-11-19, тезлик): фаол, шу бозор (+бўлим, «Импорт»), режа
/// ҳалқасига тушадиганлар ([ringOfItem]); ҳалқа бўйича, ҳалқа ичида энг янгиси олдин; id бўйича такрорсиз.
List<RingItem<TvShopItem>> marketSeedItems(
  Iterable<TvShopItem> items, {
  required MarketFilter filter,
  required List<RingStepSpec> plan,
}) {
  final seen = <String>{};
  final out = <RingItem<TvShopItem>>[];
  for (final i in items) {
    if (!i.isActive || i.market.trim() != filter.market) continue;
    if (filter.category.isNotEmpty && i.category.trim() != filter.category) continue;
    if (filter.importedOnly && i.imported != true) continue;
    final ring = ringOfItem(plan, districtId: i.districtId, regionId: i.regionId);
    if (ring == null || !seen.add(i.id)) continue;
    out.add(RingItem<TvShopItem>(i, ring));
  }
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  out.sort((a, b) {
    final byRing = a.ring.compareTo(b.ring);
    if (byRing != 0) return byRing;
    final byTime = (b.item.createdAt ?? epoch).compareTo(a.item.createdAt ?? epoch);
    if (byTime != 0) return byTime;
    return a.item.id.compareTo(b.item.id);
  });
  return out;
}

/// Бозор ичидаги қидирув (клиентда, эга 2026-11-16): сарлавҳа, тавсиф, сотувчи номи — [CatalogSearch]
/// (кирилл/лотин шакллари). Бўш сўров — ҳаммаси.
bool marketItemMatchesQuery(TvShopItem i, String query) {
  if (CatalogSearch.normalize(query).isEmpty) return true;
  return CatalogSearch.matches(query, [i.title, i.description, i.ownerName]);
}

/// Нарх филтри (дан / гача, бутун сўм).
class _PriceSheet extends StatefulWidget {
  const _PriceSheet({this.min, this.max});
  final int? min;
  final int? max;

  @override
  State<_PriceSheet> createState() => _PriceSheetState();
}

class _PriceSheetState extends State<_PriceSheet> {
  late final _min = TextEditingController(text: widget.min?.toString() ?? '');
  late final _max = TextEditingController(text: widget.max?.toString() ?? '');

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  int? _parse(TextEditingController c) {
    final s = c.text.replaceAll(' ', '').trim();
    final n = int.tryParse(s);
    return (n == null || n <= 0) ? null : n;
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String key) =>
        InputDecoration(labelText: context.tr(key), border: const OutlineInputBorder());
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('market_price_filter'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('market_price_min'),
                controller: _min,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: deco('market_price_from'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const ValueKey('market_price_max'),
                controller: _max,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: deco('market_price_to'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('market_price_clear'),
                onPressed: () => Navigator.pop(context, (null, null)),
                child: Text(context.tr('market_price_clear')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const ValueKey('market_price_apply'),
                onPressed: () => Navigator.pop<(int?, int?)>(context, (_parse(_min), _parse(_max))),
                child: Text(context.tr('market_price_apply')),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
