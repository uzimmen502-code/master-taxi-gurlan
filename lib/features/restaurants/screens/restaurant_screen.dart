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
import '../domain/menu_scroll_sync.dart';
import '../domain/restaurant_models.dart';
import '../widgets/menu_item_video_badge.dart';
import '../widgets/restaurant_cart_sheet.dart';
import '../widgets/restaurant_checkout_sheet.dart';
import '../widgets/restaurant_row.dart';
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
  });

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

  int _active = 0;
  bool _lock = false;

  static const double _leftWidth = 96;
  static const double _leftItemHeight = 56;

  @override
  void initState() {
    super.initState();
    _right.addListener(_onRightScroll);
    _loadItemClips();
    _rSub = _repo.watchRestaurant(_r.id).listen((r) {
      if (r != null && mounted) setState(() => _r = r);
    });
    _cSub = _repo.watchCategories(_r.id).listen((c) {
      if (mounted) setState(() => _categories = c);
    });
    _mSub = _repo.watchMenu(_r.id).listen((m) {
      if (mounted) {
        setState(() {
          _menu = m;
          _menuLoaded = true;
        });
      }
    }, onError: (Object e) {
      debugPrint('[RestaurantScreen] menu $e');
      if (mounted) setState(() => _menuLoaded = true);
    });
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

  double get _headerH => MediaQuery.textScalerOf(context).scale(13) * 1.3 + 16;

  double get _itemH {
    final ts = MediaQuery.textScalerOf(context);
    double line(double s) => ts.scale(s) * 1.3;
    final text = line(13) * 2 + 4 + line(12) + 6 + line(14);
    return 16 + (text > 72 ? text : 72);
  }

  MenuScrollSync _syncFor(List<_Section> sections) => MenuScrollSync(
        sectionItemCounts: [for (final s in sections) s.items.length],
        headerHeight: _headerH,
        itemHeight: _itemH,
      );

  void _onRightScroll() {
    if (_lock || !_right.hasClients) return;
    final sections = _sections;
    if (sections.isEmpty) return;
    final i = _syncFor(sections).sectionAt(_right.offset);
    if (i != _active) {
      setState(() => _active = i);
      _ensureLeftVisible(i);
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
    if (_cart.add(item, restaurant: _r)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('restaurants_cart_switch_title')),
        content: Text(
          ctx.tr('restaurants_cart_switch_body')
              .replaceAll('{old}', _cart.restaurantName)
              .replaceAll('{new}', _r.name),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('restaurants_cart_switch_ok'))),
        ],
      ),
    );
    if (ok == true) _cart.replaceWith(item, restaurant: _r);
  }

  void _openCart() {
    showRestaurantCartSheet(context, cart: _cart, restaurant: _r, onCheckout: _openCheckout);
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
                  onPressed: () => callPhone(_r.contactPhone),
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

  // ── UI ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final sections = _sections;
    final open = _r.isOpenNow;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface,
        elevation: 0,
        title: Text(_r.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
        actions: [
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
            _Header(restaurant: _r, distanceKm: _r.distanceKmFrom(widget.userLat, widget.userLng)),
            if (!open)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: AvaNoticeRow(
                  text: context.tr('restaurants_closed_now'),
                  icon: Icons.nightlight_round,
                  color: c.warn,
                ),
              ),
            Expanded(
              child: !_menuLoaded
                  ? const Center(child: CircularProgressIndicator())
                  : sections.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: AvaNoticeRow(
                            text: context.tr('restaurants_menu_empty'),
                            icon: Icons.restaurant_menu_rounded,
                            color: c.ink3,
                          ),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: _leftWidth,
                              child: ColoredBox(
                                color: c.surface2,
                                child: ListenableBuilder(
                                  listenable: _cart,
                                  builder: (context, _) => ListView.builder(
                                    controller: _left,
                                    itemExtent: _leftItemHeight,
                                    itemCount: sections.length,
                                    itemBuilder: (context, i) => _CategoryTile(
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
                                          pinned: true,
                                          delegate: _StickyHeader(title: s.name, height: _headerH),
                                        ),
                                        SliverFixedExtentList(
                                          itemExtent: _itemH,
                                          delegate: SliverChildBuilderDelegate(
                                            (context, i) => _MenuItemRow(
                                              item: s.items[i],
                                              videoClip: _itemClips[s.items[i].id],
                                              onPlayVideo: _playItemClip,
                                              qty: _cart.restaurantId == _r.id ? _cart.qtyOf(s.items[i].id) : 0,
                                              // «+» ресторан белгилаган чегарада ўчади (D-REST-26).
                                              enabled: open && (_cart.restaurantId != _r.id || _cart.canAddMore(s.items[i].id, _r)),
                                              onAdd: () => _add(s.items[i]),
                                              onRemove: () => _cart.decrement(s.items[i].id),
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
            _CartBar(
              cart: _cart,
              restaurant: _r,
              enabled: open,
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
  const _Header({required this.restaurant, this.distanceKm});

  final Restaurant restaurant;
  final double? distanceKm;

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
          SizedBox(
            height: 96,
            child: cover.startsWith('http')
                ? CachedNetworkImage(imageUrl: cover, fit: BoxFit.cover)
                : ColoredBox(color: c.brandSoft),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RestaurantLogo(restaurant: r, size: 48),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(meta.join(' · '), style: TextStyle(fontSize: 12, color: c.ink2)),
                      const SizedBox(height: 4),
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
                      if (r.announcement.trim().isNotEmpty) ...[
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

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.name,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? c.surface : Colors.transparent,
          border: Border(left: BorderSide(color: selected ? c.brand : Colors.transparent, width: 3)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? c.ink : c.ink2,
                ),
              ),
            ),
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: c.brand, borderRadius: BorderRadius.circular(8)),
                child: Text('$badge', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c.brandInk)),
              ),
          ],
        ),
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
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
    this.videoClip,
    this.onPlayVideo,
  });

  final MenuItem item;

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
    return Opacity(
      opacity: available ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                // Белгининг босиш майдони (44) расм чегарасидан 4 px чиқади — кесилмасин.
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: photo.startsWith('http')
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
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AvaText.productName.copyWith(color: c.ink, fontWeight: FontWeight.w600),
                  ),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AvaText.caption.copyWith(color: c.ink2),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${formatPrice(item.price)} ${context.tr('sum')}',
                    style: AvaText.price.copyWith(color: c.brandText),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!available)
              AvaChip(label: context.tr('restaurants_item_sold_out'), tone: AvaChipTone.warn)
            else
              _Stepper(qty: qty, enabled: enabled, onAdd: onAdd, onRemove: onRemove),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.qty, required this.enabled, required this.onAdd, required this.onRemove});

  final int qty;
  final bool enabled;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    Widget round(IconData icon, VoidCallback? onTap, {bool filled = true}) => Material(
          color: filled ? c.brand : c.surface2,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Icon(icon, size: 18, color: filled ? c.brandInk : c.ink),
            ),
          ),
        );
    if (qty <= 0) return round(Icons.add_rounded, enabled ? onAdd : null);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        round(Icons.remove_rounded, onRemove, filled: false),
        SizedBox(
          width: 28,
          child: Text('$qty', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink)),
        ),
        round(Icons.add_rounded, enabled ? onAdd : null),
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
              FilledButton(
                onPressed: canCheckout ? onCheckout : null,
                style: FilledButton.styleFrom(
                  backgroundColor: c.brand,
                  foregroundColor: c.brandInk,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  context.tr('restaurants_checkout'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
