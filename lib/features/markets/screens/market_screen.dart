import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/geo/geo_context.dart';
import '../../../core/geo/geo_tier_bar.dart';
import '../../../core/geo/relative_location.dart';
import '../../../core/geo/ring_query.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../my_shop/my_shop_entry.dart';
import '../../tv_market/models/tv_shop.dart';
import '../../tv_market/screens/tv_shop_item_detail_screen.dart';
import '../data/market_listings_source.dart';
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
/// * Сон: «N та эълон» — Республика бўйича битта `count()` (status + market [+ category/imported]).
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
  });

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
  GeoScope? _scope;
  int? _minPrice;
  int? _maxPrice;

  RingPager<TvShopItem>? _pager;
  final List<RingItem<TvShopItem>> _items = [];
  bool _loading = false;
  Object? _pageError;

  /// Ораларида кўринадиган эълон қўшмаган кетма-кет саҳифалар (нарх филтри) — 3 дан кейин автоматик юклаш
  /// тўхтайди, «Яна кўрсатиш» тугмаси чиқади (чексиз ўқиш бўлмасин, 37-банд).
  int _emptyStreak = 0;
  int _gen = 0;
  Future<int>? _count;

  @override
  void initState() {
    super.initState();
    _loadTaxonomy();
  }

  @override
  void dispose() {
    final m = _def;
    if (m != null) GeoContext.clearSessionScope(m.moduleId);
    super.dispose();
  }

  Future<void> _loadTaxonomy() async {
    setState(() => _taxonomyError = null);
    try {
      final t = await (widget.loadTaxonomy ?? MarketTaxonomyRepository.load)();
      if (!mounted) return;
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
    } catch (e) {
      debugPrint('[MarketScreen] MARKET_TAXONOMY_LOAD_FAILED market=${widget.marketId}: $e');
      if (mounted) setState(() => _taxonomyError = e);
    }
  }

  MarketFilter get _filter =>
      MarketFilter(market: widget.marketId, category: _category, importedOnly: _importedOnly);

  /// Филтр ёки ҳудуд ўзгарди — рўйхат ва сон қайтадан.
  void _restart({bool recount = true}) {
    final scope = _scope;
    if (scope == null) return;
    _gen++;
    _items.clear();
    _pageError = null;
    _loading = false;
    _emptyStreak = 0;
    _pager = RingPager<TvShopItem>(
      plan: ringPlanFor(scope),
      fetch: _source.fetcher(_filter),
      districtsOf: _source.districtsOf,
    );
    if (recount) _count = _source.count(_filter);
    setState(() {});
    _loadMore();
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
      final page = await pager.next(widget.pageSize);
      if (!mounted || gen != _gen) return;
      final visibleAdded = page.where((r) => priceInRange(r.item.price, _minPrice, _maxPrice)).length;
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

  List<TvShopItem> get _visible => [
        for (final r in _items)
          if (priceInRange(r.item.price, _minPrice, _maxPrice)) r.item,
      ];

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
      ),
    );
  }

  /// Гўшт/Деҳқон: Барчаси + бўлимлар (+ «Импорт»).
  Widget? _categoryChips(MarketDef m) {
    if (!m.hasCategoryChoice || m.usesTabs) {
      if (!m.hasImported) return null;
    }
    final lang = context.contentLang;
    return SingleChildScrollView(
      key: const ValueKey('market_categories'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Row(children: [
        if (m.hasCategoryChoice && !m.usesTabs) ...[
          _chip('market_cat_all', context.tr('market_all'), _category.isEmpty, () => _setCategory('')),
          for (final c in m.categories)
            _chip('market_cat_${c.id}', c.label(lang), _category == c.id, () => _setCategory(c.id)),
        ],
        if (m.hasImported)
          _chip('market_imported_chip', context.tr('market_imported'), _importedOnly, _toggleImported),
      ]),
    );
  }

  Widget _filterRow(MarketDef m) {
    final scope = _scope!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GeoTierBar(
          moduleId: m.moduleId,
          scope: scope,
          onChanged: (s) {
            _scope = s;
            // Сон Республика бўйича — ҳудуд ўзгарганда қайта саналмайди.
            _restart(recount: false);
          },
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            ActionChip(
              key: const ValueKey('market_price_chip'),
              avatar: const Icon(Icons.payments_outlined, size: 16),
              label: Text(_priceChipLabel()),
              onPressed: _editPrice,
            ),
            const SizedBox(width: 8),
            Chip(
              key: const ValueKey('market_sort_new'),
              avatar: const Icon(Icons.sort, size: 16),
              label: Text(context.tr('market_sort_new')),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: FutureBuilder<int>(
            future: _count,
            builder: (context, snap) {
              if (snap.hasError) debugPrint('[MarketScreen] MARKET_COUNT_FAILED: ${snap.error}');
              final n = snap.data;
              return Text(
                n == null ? ' ' : context.tr('market_count').replaceAll('{count}', formatPrice(n)),
                key: const ValueKey('market_count'),
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _list(MarketDef m) {
    final visible = _visible;
    final hasMore = _pager?.hasMore ?? false;
    // Мошина бозори «Эҳтиёт қисмлар»: тепада AVA сервис + AVA маҳсулотлари, остида эълонлар (9-босқич).
    final header = showsAutoPartsHeader(m.id, _category)
        ? (widget.partsHeader?.call(context) ?? const AutoPartsAvaHeader())
        : null;
    if (visible.isEmpty && _pageError != null) {
      final err = LoadErrorView(error: _pageError!, onRetry: _loadMore);
      if (header == null) return err;
      return ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [header, err]);
    }
    if (visible.isEmpty && !hasMore && !_loading) {
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
        if (_loading) {
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
                _loadMore();
              },
              child: Text(context.tr('market_load_more')),
            ),
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadMore();
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
          if (chips != null) chips,
          _filterRow(m),
          Expanded(child: _list(m)),
        ],
      );
    }
    final tabs = m != null && m.usesTabs;
    final scaffold = Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        actions: [if (m != null) _addButton()],
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
                  for (final c in m.categories) Tab(key: ValueKey('market_tab_${c.id}'), text: c.label(lang)),
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
