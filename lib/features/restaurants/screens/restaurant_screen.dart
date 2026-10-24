// Ресторан саҳифаси (店铺页, §12.4): сарлавҳа (муқова, логотип, эълон) +
// ИККИ УСТУНЛИ БОҒЛАНГАН МЕНЮ (左右联动) + ёпишқоқ сават панели.
//
// Боғланиш мантиғи — `MenuScrollSync` (соф, тестланган): ўнг рўйхатда
// ҳар бўлим ёпишқоқ сарлавҳа + қатъий баландликдаги таом қаторлари;
// скролл → фаол категория, категория босилди → скролл (қулф билан).
// Таблар («Меню / Шарҳлар / Маълумот») 1-босқичда йўқ: «Маълумот» —
// сарлавҳадаги тугма, «Шарҳлар» — 2-босқич.

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../home/widgets/ava_chip.dart';
import '../../home/widgets/ava_section.dart';
import '../data/restaurants_repository.dart';
import '../domain/bookings.dart';
import '../domain/menu_row_metrics.dart';
import '../domain/menu_scroll_sync.dart';
import '../domain/restaurant_models.dart';
import '../widgets/booking_sheet.dart';
import '../widgets/dish_detail_sheet.dart';
import '../widgets/menu_category_nav.dart';
import '../widgets/menu_item_video_badge.dart';
import '../widgets/restaurant_cart_actions.dart';
import '../widgets/restaurant_cart_sheet.dart';
import '../widgets/restaurant_checkout_sheet.dart';
import '../widgets/restaurant_row.dart';
import '../domain/dish_stats.dart';
import 'my_bookings_screen.dart';
import '../../tv_market/models/tv_clip.dart';
import '../../tv_market/repositories/tv_clips_repository.dart';
import '../../tv_market/services/tv_clip_link.dart';
import '../../tv_market/widgets/tv_clip_link_widgets.dart';

class RestaurantScreen extends StatefulWidget {
  const RestaurantScreen({
    super.key,
    required this.restaurant,
    this.userLat,
    this.userLng,
    this.repository,
    this.cart,
    this.itemClipsLoader,
    this.itemClipOpener,
    this.dishStatsLoader,
    this.restaurantVideoLoader,
    this.focusItemId,
    this.openCartOnStart = false,
  });

  /// Лентадан таом варағидаги «Буюртма бериш» босилганда: экран очилгач сават варағи ўзи очилади
  /// (лентада сават панели йўқ — мижоз саватини кўриб, расмийлаштиришга ўтади).
  final bool openCartOnStart;

  /// Лентадан «Менюни кўриш» босилганда: меню шу таомгача скролл қилинади ва қатор қисқа ёритилади.
  final String? focusItemId;

  /// Рестораннинг умумий обзор видеоси; бўш бўлса ҳақиқий репозиторий (тест учун алмаштирилади).
  final Future<TvClip?> Function()? restaurantVideoLoader;

  /// Таом баҳо агрегатлари (`itemId → DishStats`) — битта сўров; тест учун алмаштирилади.
  final Future<Map<String, DishStats>> Function(String restaurantId)? dishStatsLoader;

  /// Таом видеолари (`itemId → клип`) — битта сўров; тест учун алмаштирилади.
  final Future<Map<String, TvClip>> Function(String restaurantId)? itemClipsLoader;
  final void Function(BuildContext context, TvClip clip)? itemClipOpener;

  final Restaurant restaurant;
  final double? userLat;
  final double? userLng;
  final RestaurantsRepository? repository;
  final RestaurantCart? cart;

  @override
  State<RestaurantScreen> createState() => _RestaurantScreenState();
}

/// Меню бўлими: категория + унинг таомлари.
class _Section {
  const _Section({required this.id, required this.name, required this.items});

  final String id;
  final String name;
  final List<MenuItem> items;
}

class _RestaurantScreenState extends State<RestaurantScreen> {
  late final RestaurantsRepository _repo = widget.repository ?? RestaurantsRepository();
  late final RestaurantCart _cart = widget.cart ?? RestaurantCart.instance;
  final _right = ScrollController();
  final _left = ScrollController();

  late Restaurant _r = widget.restaurant;
  List<MenuCategory> _categories = const [];
  List<MenuItem> _menu = const [];
  bool _menuLoaded = false;
  StreamSubscription<Restaurant?>? _rSub;
  StreamSubscription<List<MenuCategory>>? _cSub;
  StreamSubscription<List<MenuItem>>? _mSub;

  /// Таом видеолари (`itemId → клип`): таом қаторида ▶ белгиси; видеоси бўлмаганда бўш.
  Map<String, TvClip> _itemClips = const {};

  /// Таом баҳолари (`itemId → агрегат`): ★ фақат етарли баҳо йиғилганда кўрсатилади.
  Map<String, DishStats> _dishStats = const {};

  /// Стол бронь (S5): созлама ёпиқ/ўқилмаса тугма кўринмайди.
  BookingConfig _bookingCfg = BookingConfig.off;
  String? _bookingUid;

  int _active = 0;
  bool _lock = false;

  /// Фокусланган таом ([RestaurantScreen.focusItemId]): ёритилган қатор ва бир марталик скролл.
  String? _highlightId;
  bool _focusDone = false;
  bool _categoriesLoaded = false;

  static const double _leftItemHeight = 56;

  /// Ҳедер скролда йиғилади: пастга [_collapseAt] dp дан кейин, тепага [_expandAt] dp дан кейин қайтади
  /// (гистерезис — чегарада милтиллаш йўқ).
  static const double _collapseAt = 48;
  static const double _expandAt = 8;
  bool _collapsed = false;
  final GlobalKey _headerKey = GlobalKey();

  /// Қатор ўлчамлари кеши: `_itemH` ҳар скролл ҳодисасида чақирилади, ўлчаш эса қиммат (TextPainter).
  MenuRowMetrics? _metrics;
  Object? _metricsKey;

  @override
  void initState() {
    super.initState();
    _right.addListener(_onRightScroll);
    if (widget.openCartOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _cart.isNotEmpty) _openCart();
      });
    }
    _loadItemClips();
    _loadDishStats();
    _loadBookingConfig();
    _rSub = _repo.watchRestaurant(_r.id).listen((r) {
      if (r != null && mounted) setState(() => _r = r);
    });
    _cSub = _repo.watchCategories(_r.id).listen((c) {
      if (mounted) {
        setState(() {
          _categories = c;
          _categoriesLoaded = true;
        });
        _tryFocus();
      }
    }, onError: (Object e) {
      debugPrint('[RestaurantScreen] categories $e');
      if (mounted) {
        setState(() => _categoriesLoaded = true);
        _tryFocus();
      }
    });
    _mSub = _repo.watchMenu(_r.id).listen((m) {
      if (mounted) {
        setState(() {
          _menu = m;
          _menuLoaded = true;
        });
        _tryFocus();
      }
    }, onError: (Object e) {
      debugPrint('[RestaurantScreen] menu $e');
      if (mounted) setState(() => _menuLoaded = true);
    });
  }

  /// Фокусланган таомгача БИР марта скролл: меню ҳам, категориялар ҳам келгандан кейин (категориясиз таом
  /// «Бошқалар»га тушиб, нотўғри жойга олиб бормасин). Таом топилмаса (ўчирилган) меню ўзгармайди.
  void _tryFocus() {
    final id = widget.focusItemId;
    if (id == null || _focusDone || !_menuLoaded || !_categoriesLoaded) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focusDone || !_right.hasClients) return;
      final sections = _sections;
      for (var s = 0; s < sections.length; s++) {
        final i = sections[s].items.indexWhere((m) => m.id == id);
        if (i < 0) continue;
        _focusDone = true;
        final target = _syncFor(sections).offsetOfItem(s, i, maxScrollExtent: _right.position.maxScrollExtent);
        setState(() {
          _active = s;
          _lock = true;
          _highlightId = id;
        });
        _ensureLeftVisible(s);
        _right
            .animateTo(target, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic)
            .whenComplete(() {
          if (mounted) setState(() => _lock = false);
        });
        return;
      }
      _focusDone = true;
    });
  }

  Future<void> _loadBookingConfig() async {
    try {
      final cfg = await _repo.getBookingsConfig();
      final uid = await RestaurantsRepository.currentUid();
      if (!mounted) return;
      setState(() {
        _bookingCfg = cfg;
        _bookingUid = uid;
      });
    } catch (e) {
      debugPrint('[RestaurantScreen] bookings config $e');
    }
  }

  bool get _canBook => _r.acceptsBookings && !_r.bookingsDisabled && _r.bookingSeats > 0 && _bookingCfg.visibleFor(_bookingUid);

  Future<void> _openBooking() async {
    final uid = _bookingUid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('restaurants_booking_login_needed'))));
      return;
    }
    final sent = await showBookingSheet(context, restaurant: _r, config: _bookingCfg, repository: _repo);
    if (sent != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('restaurants_booking_sent'))));
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MyBookingsScreen(uid: uid, repository: _repo)));
  }

  /// Рестораннинг БАРЧА таом видеолари БИР сўровда (ҳар таом учун алоҳида эмас, 36-қоида). Видео
  /// ихтиёрий қўшимча: юкланмаса меню ўзгаришсиз ишлайди.
  Future<void> _loadItemClips() async {
    try {
      final clips = await (widget.itemClipsLoader ?? (id) => TvClipsRepository().fetchRestaurantItemClips(id))(_r.id);
      if (mounted && clips.isNotEmpty) setState(() => _itemClips = clips);
    } catch (e) {
      debugPrint('[RestaurantScreen] item clips $e');
    }
  }

  /// Рестораннинг БАРЧА таом баҳо агрегатлари БИР сўровда. Баҳо ихтиёрий қўшимча: ўқилмаса меню
  /// баҳосиз ишлайверади.
  Future<void> _loadDishStats() async {
    try {
      final stats = await (widget.dishStatsLoader ?? _repo.getDishStats)(_r.id);
      if (mounted && stats.isNotEmpty) setState(() => _dishStats = stats);
    } catch (e) {
      debugPrint('[RestaurantScreen] dish stats $e');
    }
  }

  void _playItemClip(TvClip clip) {
    final opener = widget.itemClipOpener;
    if (opener != null) {
      opener(context, clip);
    } else {
      TvClipLink.open(context, clip);
    }
  }

  @override
  void dispose() {
    _right.removeListener(_onRightScroll);
    _right.dispose();
    _left.dispose();
    _rSub?.cancel();
    _cSub?.cancel();
    _mSub?.cancel();
    super.dispose();
  }

  // ── Бўлимлар ───────────────────────────────────────────────────────
  List<_Section> get _sections {
    final byCat = <String, List<MenuItem>>{};
    for (final m in _menu) {
      byCat.putIfAbsent(m.categoryId, () => []).add(m);
    }
    final out = <_Section>[];
    for (final c in _categories) {
      final items = byCat.remove(c.id);
      if (items == null || items.isEmpty) continue;
      out.add(_Section(id: c.id, name: c.displayName(context.contentLang), items: items));
    }
    // Категориясиз (ёки ўчирилган категория) таомлар — «Бошқалар».
    final rest = byCat.values.expand((e) => e).toList();
    if (rest.isNotEmpty) {
      out.add(_Section(id: '', name: context.tr('restaurants_menu_other'), items: rest));
    }
    return out;
  }

  bool get _hasTiers => _menu.any((m) => m.qtyTiers.isNotEmpty);

  double get _headerH => MediaQuery.textScalerOf(context).scale(13) * 1.3 + 16;

  /// Расм плиткаси бор қатор: расм ёки таом видеоси (▶ белгиси расмнинг устида туради).
  bool _hasTile(MenuItem m) => m.photoUrl.trim().startsWith('http') || _itemClips[m.id] != null;

  /// Намуна рестораннинг менюси фақат кўриш учун: «+» умуман кўрсатилмайди.
  bool get _showStepper => !_r.isDemo;

  /// Меню ҳудудининг ҲАҚИҚИЙ кенглиги (`build`даги LayoutBuilder ёзади): ландшафт/ўйиқ экранда
  /// SafeArea кенгликни кичрайтиради — ном қатори сони шунга қараб ўлчанади. Биринчи кадрдан олдин — экран кенглиги.
  double? _bodyWidth;

  /// Рўйхатнинг кенглиги: рейл бўлса унинг кенглиги айрилади.
  double _listWidth(int sectionCount) {
    final w = _bodyWidth ?? MediaQuery.sizeOf(context).width;
    return menuNavModeFor(sectionCount) == MenuNavMode.rail ? w - kMenuRailWidth : w;
  }

  /// Қатор ўлчамлари (кешланган): меню, кенглик, шрифт масштаби ёки видео/расм тўплами ўзгармаса қайта ўлчанмайди.
  MenuRowMetrics _rowMetrics(int sectionCount) {
    final scaler = MediaQuery.textScalerOf(context);
    final width = _listWidth(sectionCount);
    final key = Object.hash(
      identityHashCode(_menu),
      width.round(),
      scaler.scale(100).round(),
      _itemClips.length,
      _hasTiers,
      _showStepper,
      context.contentLang,
    );
    if (_metrics != null && _metricsKey == key) return _metrics!;
    _metricsKey = key;
    return _metrics = MenuRowMetrics.compute(
      items: [
        for (final m in _menu)
          MenuRowSample(
            name: m.name,
            priceText: '${formatPrice(m.price)} ${context.tr('sum')}',
            hasTile: _hasTile(m),
          ),
      ],
      listWidth: width,
      scaler: scaler,
      direction: Directionality.of(context),
      hasTiers: _hasTiers,
      showStepper: _showStepper,
      baseStyle: Theme.of(context).textTheme.bodyMedium,
    );
  }

  double _itemH(int sectionCount) => _rowMetrics(sectionCount).itemHeight;

  MenuScrollSync _syncFor(List<_Section> sections) => MenuScrollSync(
        sectionItemCounts: [for (final s in sections) s.items.length],
        headerHeight: _headerH,
        itemHeight: _itemH(sections.length),
      );

  void _onRightScroll() {
    if (!_right.hasClients) return;
    _updateCollapsed();
    if (_lock) return;
    final sections = _sections;
    if (sections.isEmpty) return;
    final i = _syncFor(sections).sectionAt(_right.offset);
    if (i != _active) {
      setState(() => _active = i);
      _ensureLeftVisible(i);
    }
  }

  /// Ҳедерни йиғиш/ёйиш. Йиғилгандан кейин рўйхат ҳам ҳедер баландлигича ўсади, шунинг учун скролл
  /// оралиғи шунга етарли бўлмаса йиғилмайди — акс ҳолда offset қисқариб, ҳедер қайта ёйилиб, милтилларди.
  void _updateCollapsed() {
    final pos = _right.position;
    final off = pos.pixels;
    if (!_collapsed) {
      if (off <= _collapseAt) return;
      final h = (_headerKey.currentContext?.size?.height) ?? 0;
      if (pos.maxScrollExtent - h <= off + 8) return;
      setState(() => _collapsed = true);
    } else if (off < _expandAt) {
      setState(() => _collapsed = false);
    }
  }

  Future<void> _tapCategory(int i) async {
    final sections = _sections;
    if (!_right.hasClients || i >= sections.length) return;
    setState(() {
      _active = i;
      _lock = true;
    });
    _ensureLeftVisible(i);
    final target = _syncFor(sections).offsetOf(i, maxScrollExtent: _right.position.maxScrollExtent);
    try {
      await _right.animateTo(target, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    } finally {
      if (mounted) setState(() => _lock = false);
    }
  }

  void _ensureLeftVisible(int i) {
    if (!_left.hasClients) return;
    final viewport = _left.position.viewportDimension;
    final target = (i * _leftItemHeight - viewport / 2 + _leftItemHeight / 2)
        .clamp(0.0, _left.position.maxScrollExtent);
    _left.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  // ── Сават ──────────────────────────────────────────────────────────
  Future<void> _add(MenuItem item) async {
    await addToCartOrAskSwitch(context, cart: _cart, item: item, restaurant: _r);
  }

  /// Таом тафсилоти варағи (қатор босилганда ёки сават варағидаги таом номи босилганда).
  void _openItem(MenuItem item) {
    showDishDetailSheet(
      context,
      item: item,
      restaurant: _r,
      cart: _cart,
      stats: _dishStats[item.id],
      clip: _itemClips[item.id],
      onPlayVideo: _playItemClip,
      cuisineLoader: () => _repo.listCuisines(),
    );
  }

  void _openCart() {
    showRestaurantCartSheet(context, cart: _cart, restaurant: _r, onCheckout: _openCheckout, onOpenItem: _openItem);
  }

  void _openCheckout() {
    showRestaurantCheckoutSheet(
      context,
      restaurant: _r,
      cart: _cart,
      repository: _repo,
      userLat: widget.userLat,
      userLng: widget.userLng,
    );
  }

  /// Қўнғироқ очилмаса (рақам нотўғри ёки телефон иловаси йўқ) жим қолмайди: варақ ёпилиб, хабар кўрсатилади
  /// (варақ SnackBar'ни тўсиб туради). Бошқа экранлар билан бир хил матн.
  Future<void> _callRestaurant(BuildContext sheetContext) async {
    final ok = await callPhone(_r.contactPhone);
    if (ok || !mounted) return;
    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('tv_market_call_failed'))),
    );
  }

  void _openInfo() {
    final c = context.ava;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: c.surface,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_r.name, style: AvaText.sectionTitle.copyWith(color: c.ink)),
            if (_r.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(_r.description, style: TextStyle(fontSize: 13, color: c.ink2)),
            ],
            const SizedBox(height: 12),
            if (_r.address.isNotEmpty) _InfoLine(icon: Icons.place_outlined, text: _r.address),
            _InfoLine(
              icon: Icons.schedule_rounded,
              text: _r.openingHours?.label ?? ctx.tr('restaurants_hours_always'),
            ),
            _InfoLine(
              icon: Icons.timer_outlined,
              text: ctx.tr('restaurants_prep_time').replaceAll('{min}', _r.prepTimeMin.toString()),
            ),
            if (_r.minOrderAmount > 0)
              _InfoLine(
                icon: Icons.shopping_basket_outlined,
                text: ctx.tr('restaurants_chip_min').replaceAll('{amount}', formatPrice(_r.minOrderAmount)),
              ),
            if (_r.contactPhone.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _callRestaurant(ctx),
                  icon: const Icon(Icons.call_outlined),
                  label: Text(ctx.tr('restaurants_call')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Меню ҳудуди: юкланиш · бўш · (чиплар ёки рейл) + таомлар рўйхати.
  Widget _menuBody(AvaColors c, List<_Section> sections, MenuNavMode mode, bool canOrder) {
    if (!_menuLoaded) return const Center(child: CircularProgressIndicator());
    if (sections.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: AvaNoticeRow(
          text: context.tr('restaurants_menu_empty'),
          icon: Icons.restaurant_menu_rounded,
          color: c.ink3,
        ),
      );
    }
    final metrics = _rowMetrics(sections.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 2…3 категория: юқорида чиплар (тўлиқ кенглик таомга қолади).
        if (mode == MenuNavMode.chips)
          ListenableBuilder(
            listenable: _cart,
            builder: (context, _) => MenuCategoryChips(
              names: [for (final s in sections) s.name],
              badges: [
                for (final s in sections) _cart.restaurantId == _r.id ? _cart.countInCategory(s.id) : 0,
              ],
              active: _active,
              onTap: _tapCategory,
            ),
          ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 4+ категория: чап рейл (左右联动).
              if (mode == MenuNavMode.rail)
                SizedBox(
                  width: kMenuRailWidth,
                  child: ColoredBox(
                    color: c.surface2,
                    child: ListenableBuilder(
                      listenable: _cart,
                      builder: (context, _) => ListView.builder(
                        controller: _left,
                        itemExtent: _leftItemHeight,
                        itemCount: sections.length,
                        itemBuilder: (context, i) => MenuCategoryTile(
                          name: sections[i].name,
                          selected: i == _active,
                          badge: _cart.restaurantId == _r.id ? _cart.countInCategory(sections[i].id) : 0,
                          onTap: () => _tapCategory(i),
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: ColoredBox(
                  color: c.surface,
                  child: ListenableBuilder(
                    listenable: _cart,
                    builder: (context, _) => CustomScrollView(
                      controller: _right,
                      slivers: [
                        for (final s in sections) ...[
                          SliverPersistentHeader(
                            // Чипларда фаол категория юқорида кўриниб турибди — сарлавҳа ёпишмайди.
                            pinned: mode != MenuNavMode.chips,
                            delegate: _StickyHeader(title: s.name, height: _headerH),
                          ),
                          SliverFixedExtentList(
                            itemExtent: metrics.itemHeight,
                            delegate: SliverChildBuilderDelegate(
                              (context, i) => _MenuItemRow(
                                item: s.items[i],
                                videoClip: _itemClips[s.items[i].id],
                                onPlayVideo: _playItemClip,
                                stats: _dishStats[s.items[i].id],
                                qty: _cart.restaurantId == _r.id ? _cart.qtyOf(s.items[i].id) : 0,
                                showStepper: _showStepper,
                                // «+» ресторан белгилаган чегарада ўчади (D-REST-26).
                                enabled: canOrder && (_cart.restaurantId != _r.id || _cart.canAddMore(s.items[i].id, _r)),
                                stacked: metrics.stackedWithTile && _hasTile(s.items[i]),
                              stackedMenu: metrics.stackedWithTile,
                                onAdd: () => _add(s.items[i]),
                                onRemove: () => _cart.decrement(s.items[i].id),
                                onOpen: () => _openItem(s.items[i]),
                                highlighted: _highlightId == s.items[i].id,
                              ),
                              childCount: s.items.length,
                            ),
                          ),
                        ],
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final sections = _sections;
    final open = _r.isOpenNow;
    // Буюртма мумкинми — ЯГОНА қоида: намуна ресторан ҳеч қачон; ёпиқ ресторан фақат олдиндан буюртма олса (S4b).
    final canOrder = _r.canTakeOrdersNow;
    final mode = menuNavModeFor(sections.length);
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        // Ном ҳедерда (катта, 2 қатор). Ҳедер йиғилгандан кейингина сарлавҳада ҳам чиқади.
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: _collapsed
              ? Text(
                  _r.name,
                  key: const ValueKey('appbar-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink),
                )
              : const SizedBox.shrink(key: ValueKey('appbar-title-empty')),
        ),
        actions: [
          if (_canBook)
            IconButton(
              key: const ValueKey('book-table'),
              tooltip: context.tr('restaurants_booking_action'),
              icon: const Icon(Icons.event_seat_rounded),
              onPressed: _openBooking,
            ),
          IconButton(
            tooltip: context.tr('restaurants_info'),
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: _openInfo,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Ҳедер скролда йиғилади (меню учун жой): бола монтаж қолади (видео тугмаси қайта юкланмайди),
            // фақат баландлик 0 га тушади ва қирқилади.
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: _collapsed ? 0.0 : 1.0,
                  child: ExcludeSemantics(
                    excluding: _collapsed,
                    child: _Header(
                      key: _headerKey,
                      restaurant: _r,
                      distanceKm: _r.distanceKmFrom(widget.userLat, widget.userLng),
                      videoLoader: widget.restaurantVideoLoader,
                    ),
                  ),
                ),
              ),
            ),
            // Намуна ресторан: ҳедер йиғилганда ҳам кўриниб туради (мижоз нега «+» йўқлигини билсин).
            if (_r.isDemo) const _DemoBanner(),
            if (!open && !_r.isDemo)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                child: AvaNoticeRow(
                  key: const ValueKey('closed-notice'),
                  text: context.tr(_r.acceptsPreorder ? 'restaurants_closed_preorder' : 'restaurants_closed_now'),
                  icon: Icons.nightlight_round,
                  color: c.warn,
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  _bodyWidth = box.maxWidth;
                  return _menuBody(c, sections, mode, canOrder);
                },
              ),
            ),
            _CartBar(
              cart: _cart,
              restaurant: _r,
              enabled: canOrder,
              onOpenCart: _openCart,
              onCheckout: _openCheckout,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({super.key, required this.restaurant, this.distanceKm, this.videoLoader});

  final Restaurant restaurant;
  final double? distanceKm;
  final Future<TvClip?> Function()? videoLoader;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final r = restaurant;
    final cover = r.coverUrl.trim();
    final meta = <String>[
      if (r.ratingCount >= 5) '★ ${r.ratingAvg.toStringAsFixed(1)} (${r.ratingCount})',
      if (r.ratingCount < 5) context.tr('restaurants_new'),
      context.tr('restaurants_eta').replaceAll('{min}', estimatedMinutes(r, distanceKm).toString()),
      if (distanceKm != null) formatDistanceLabel(context, distanceKm!),
    ];
    return ColoredBox(
      color: c.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Муқова расми бўлмаса блок ЧИЗИЛМАЙДИ (аввал бўш 96 dp тус эди).
          if (cover.startsWith('http'))
            SizedBox(
              key: const ValueKey('restaurant-cover'),
              height: 96,
              child: CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RestaurantLogo(restaurant: r, size: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.name,
                        key: const ValueKey('restaurant-name'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1.2, color: c.ink),
                      ),
                      const SizedBox(height: 4),
                      Text(meta.join(' · '), style: TextStyle(fontSize: 13, color: c.ink2)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (r.delivery.isAvaCourier)
                            AvaChip(label: context.tr('restaurants_chip_delivery'), tone: AvaChipTone.brand),
                          if (r.delivery.isOwnCourier)
                            AvaChip(label: context.tr('restaurants_chip_own_courier'), tone: AvaChipTone.brand),
                          if (r.delivery.pickup) AvaChip(label: context.tr('restaurants_chip_pickup')),
                          if (r.minOrderAmount > 0)
                            AvaChip(
                              label: context
                                  .tr('restaurants_chip_min')
                                  .replaceAll('{amount}', formatPrice(r.minOrderAmount)),
                            ),
                        ],
                      ),
                      // Намунада сервер ёзган «Намуна · Namuna · Пример — …» матни кўрсатилмайди: ўрнида тилга
                      // мосланган баннер ([_DemoBanner]) бор.
                      if (!r.isDemo && r.announcement.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.campaign_outlined, size: 14, color: c.brandText),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                r.announcement.trim(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: c.brandText),
                              ),
                            ),
                          ],
                        ),
                      ],
                      // Эгаси қўшган таомлар обзори видеоси (бор бўлсагина).
                      LinkedVideoButton(
                        linkId: r.id,
                        ownerPhone: r.ownerUid,
                        loader: videoLoader,
                        // Ходим юклаган видео ҳам: ваколатни қоида кафолатлайди.
                        trustLinkKind: TvClipLink.kindRestaurant,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.line),
        ],
      ),
    );
  }
}

/// Намуна ресторан: менюни кўриш мумкин, буюртма йўқ (сервер `RESTAURANT_DEMO` билан рад этади).
class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      key: const ValueKey('demo-banner'),
      width: double.infinity,
      color: c.warnSoft,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: c.warn),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr('restaurants_demo_banner'),
              style: TextStyle(fontSize: 13, height: 1.3, color: c.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c.ink3),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: c.ink))),
        ],
      ),
    );
  }
}

/// Ёпишқоқ бўлим сарлавҳаси — қатъий баландлик ([MenuScrollSync] учун).
class _StickyHeader extends SliverPersistentHeaderDelegate {
  const _StickyHeader({required this.title, required this.height});

  final String title;
  final double height;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final c = context.ava;
    return Container(
      height: height,
      color: c.surface,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink),
      ),
    );
  }

  @override
  bool shouldRebuild(_StickyHeader old) => old.title != title || old.height != height;
}

class _MenuItemRow extends StatelessWidget {
  const _MenuItemRow({
    required this.item,
    required this.qty,
    required this.showStepper,
    required this.enabled,
    required this.stacked,
    required this.stackedMenu,
    required this.onAdd,
    required this.onRemove,
    required this.onOpen,
    this.highlighted = false,
    this.videoClip,
    this.onPlayVideo,
    this.stats,
  });

  final MenuItem item;

  /// Қатор (расм, ном, нарх) босилди — таом тафсилоти варағи. «+/−» ва ▶ ўз босишларига эга (улар ютади).
  final VoidCallback onOpen;

  /// Намунада «+» умуман йўқ (менюни фақат кўриш).
  final bool showStepper;

  /// Расмли қаторда нарх ва степпер бир қаторга сиғмайди — степпер нархнинг остида ([MenuRowMetrics.stackedWithTile]).
  final bool stacked;

  /// Менюда расмли қаторлар учун степпер остига ўтган: расмсиз қаторлар баландликни тўлдирмай, вертикал марказда.
  final bool stackedMenu;

  /// Лентадан келган таом: фон бренд рангидан шаффофга секин сўнади (бир марта).
  final bool highlighted;

  /// Баҳо агрегати (бўлса): етарли баҳо йиғилган бўлсагина нархнинг ёнида ★ кўрсатилади.
  final DishStats? stats;

  /// Таомнинг ФАОЛ видеоси (бўлса) — расм устида ▶; босилса АВАГрам лентасида очилади.
  final TvClip? videoClip;
  final void Function(TvClip clip)? onPlayVideo;
  final int qty;
  final bool enabled;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final available = item.isAvailable;
    final photo = item.photoUrl.trim();
    final hasPhoto = photo.startsWith('http');
    // Расм ҳам, видео ҳам йўқ таомда бўш «санчқи» плиткаси чизилмайди: матн тўлиқ кенгликни олади.
    final hasTile = hasPhoto || videoClip != null;

    // Қатор баландлиги қотирилган (SliverFixedExtentList). Нарх ҳар доим тўлиқ ўлчамда: нарх + ★ битта
    // [FittedBox] да (нарх + чегирма + ★ ни битта қаторга сиғдириш қаторни ~10 px гача кичрайтирган эди).
    final price = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${formatPrice(item.price)} ${context.tr('sum')}',
            maxLines: 1,
            style: AvaText.price.copyWith(fontSize: MenuRowMetrics.priceFont, fontWeight: FontWeight.w800, color: c.brandText),
          ),
          if (stats != null && stats!.showRating) ...[
            const SizedBox(width: 8),
            Icon(Icons.star_rounded, size: 14, color: c.brand),
            const SizedBox(width: 2),
            Text(
              '${stats!.average.toStringAsFixed(1)} (${stats!.ratingCount})',
              key: Key('dish-rating-${item.id}'),
              maxLines: 1,
              style: AvaText.dishNote.copyWith(color: c.ink2),
            ),
          ],
        ],
      ),
    );

    // Нарх (+ ★) ва унинг тагида миқдорга чегирма ҳинти (D-REST-25: биринчи поғона — «10 тадан 32 000»).
    final priceWithHint = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        price,
        if (item.qtyTiers.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            context
                .tr('restaurants_tier_from')
                .replaceAll('{min}', '${item.qtyTiers.first.minQty}')
                .replaceAll('{price}', formatPrice(item.qtyTiers.first.price)),
            key: Key('tier-hint-${item.id}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AvaText.dishNote.copyWith(color: c.ok),
          ),
        ],
      ],
    );

    final Widget? control = !available
        ? AvaChip(label: context.tr('restaurants_item_sold_out'), tone: AvaChipTone.warn)
        : showStepper
            ? _Stepper(name: item.name, qty: qty, enabled: enabled, onAdd: onAdd, onRemove: onRemove)
            : null;

    final Widget bottom;
    if (control == null) {
      bottom = Align(alignment: AlignmentDirectional.centerStart, child: priceWithHint);
    } else if (stacked) {
      bottom = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          priceWithHint,
          Align(alignment: AlignmentDirectional.centerEnd, child: control),
        ],
      );
    } else {
      bottom = Row(
        children: [
          Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: priceWithHint)),
          const SizedBox(width: 8),
          control,
        ],
      );
    }

    Widget row(Color? bg) => InkWell(
          key: ValueKey('menu-row-${item.id}'),
          onTap: onOpen,
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              MenuRowMetrics.padLeft,
              MenuRowMetrics.padTop,
              MenuRowMetrics.padRight,
              MenuRowMetrics.padBottom,
            ),
            decoration: BoxDecoration(color: bg, border: Border(bottom: BorderSide(color: c.line))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasTile) ...[
                  SizedBox(
                    width: MenuRowMetrics.tileSize,
                    height: MenuRowMetrics.tileSize,
                    child: Stack(
                      // Белгининг босиш майдони (44) расм чегарасидан 4 px чиқади — кесилмасин.
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: hasPhoto
                                ? CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover)
                                : ColoredBox(
                                    color: c.surface2,
                                    child: Icon(Icons.restaurant_rounded, color: c.ink3),
                                  ),
                          ),
                        ),
                        if (videoClip != null)
                          Positioned(
                            right: -4,
                            bottom: -4,
                            child: MenuItemVideoBadge(itemId: item.id, onTap: () => onPlayVideo?.call(videoClip!)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: MenuRowMetrics.tileGap),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: stackedMenu && !hasTile ? MainAxisAlignment.center : MainAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: MenuRowMetrics.nameFont,
                          fontWeight: FontWeight.w700,
                          height: MenuRowMetrics.nameLineHeight,
                          color: c.ink,
                        ),
                      ),
                      if (item.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        // Тўлиқ тавсиф — таом варағида; қаторда бир қатор.
                        Text(
                          item.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AvaText.dishNote.copyWith(color: c.ink2),
                        ),
                      ],

                      // Нарх ва степпер доим қаторнинг пастида — қаторлар бўйлаб бир чизиқда.
                      // (Расмли қаторлар степпери остига ўтган менюда расмсиз қатор — марказда, катта бўшлиқсиз.)
                      if (stackedMenu && !hasTile) const SizedBox(height: 6) else const Spacer(),
                      bottom,
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    return Opacity(
      opacity: available ? 1 : 0.5,
      child: highlighted
          ? TweenAnimationBuilder<Color?>(
              key: ValueKey('menu-highlight-${item.id}'),
              tween: ColorTween(begin: c.brandSoft, end: c.brandSoft.withValues(alpha: 0)),
              duration: const Duration(milliseconds: 2200),
              curve: Curves.easeIn,
              builder: (context, bg, _) => row(bg),
            )
          : row(null),
    );
  }
}

/// «+» / «− n +». Кўриниш 34 dp, босиш майдони 44 dp ([MenuRowMetrics.hit]); экран ўқувчи учун таом номи билан.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.name,
    required this.qty,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  final String name;
  final int qty;
  final bool enabled;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    Widget round(IconData icon, VoidCallback? onTap, String label, {bool filled = true}) {
      final on = onTap != null;
      // Ўчиқ ҳолат кўринишда ҳам ажралади (аввал ўчиқ «+» фаолидан фарқ қилмасди).
      final bg = !on ? c.surface2 : (filled ? c.brand : c.surface2);
      final fg = !on ? c.ink3 : (filled ? c.brandInk : c.ink);
      return Semantics(
        button: true,
        enabled: on,
        label: label,
        child: ExcludeSemantics(
          child: SizedBox(
            width: MenuRowMetrics.hit,
            height: MenuRowMetrics.hit,
            // Ўз Materialи: Ink ранги ва ripple орқадаги ColoredBox остида қолмасин (аввал доира кўринмай қолган эди).
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Center(
                  child: Ink(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                    child: Icon(icon, size: 20, color: fg),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final addLabel = context.tr('restaurants_a11y_add').replaceAll('{name}', name);
    if (qty <= 0) return round(Icons.add_rounded, enabled ? onAdd : null, addLabel);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        round(
          Icons.remove_rounded,
          onRemove,
          context.tr('restaurants_a11y_remove').replaceAll('{name}', name),
          filled: false,
        ),
        SizedBox(
          width: MenuRowMetrics.qtySlot,
          child: Text(
            '$qty',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c.ink),
          ),
        ),
        round(Icons.add_rounded, enabled ? onAdd : null, addLabel),
      ],
    );
  }
}

/// Ёпишқоқ сават панели (§12.4): жами · минимумга етмаса «яна N сўм» ·
/// «Буюртма бериш →».
class _CartBar extends StatelessWidget {
  const _CartBar({
    required this.cart,
    required this.restaurant,
    required this.enabled,
    required this.onOpenCart,
    required this.onCheckout,
  });

  final RestaurantCart cart;
  final Restaurant restaurant;
  final bool enabled;
  final VoidCallback onOpenCart;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) {
        if (cart.isEmpty || cart.restaurantId != restaurant.id) return const SizedBox.shrink();
        final total = cart.itemsTotal;
        final missing = restaurant.minOrderAmount - cart.itemsTotal;
        final canCheckout = enabled && missing <= 0;
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(top: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onOpenCart,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Badge(
                          label: Text('${cart.count}'),
                          backgroundColor: c.brand,
                          textColor: c.brandInk,
                          child: Icon(Icons.shopping_basket_rounded, color: c.ink),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${formatPrice(total)} ${context.tr('sum')}',
                                style: AvaText.price.copyWith(color: c.ink),
                              ),
                              Text(
                                missing > 0
                                    ? context
                                        .tr('restaurants_min_more')
                                        .replaceAll('{amount}', formatPrice(missing))
                                    : context.tr('restaurants_cart_hint'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AvaText.caption.copyWith(color: missing > 0 ? c.warn : c.ink3),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Катта тизим шрифти + тор экранда тугма қаторни тошириб юбормасин: кенглиги чекланган, матн кичраяди.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.5),
                child: FilledButton(
                  onPressed: canCheckout ? onCheckout : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: c.brand,
                    foregroundColor: c.brandInk,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      context.tr('restaurants_checkout'),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
