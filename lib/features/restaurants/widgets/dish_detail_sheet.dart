// Таом тафсилоти варағи (эга 2026-10-23: «таом тафсилоти варағини амалга ошир»).
//
// Таом қаторини ёки лентадаги таом карточкасини босганда пастдан чиқади: катта расм (босилса — катталашади),
// тўлиқ тавсиф, нарх ва миқдорга чегирма поғоналари, порция/грамм/КБЖУ/кухна/теглар, ▶ видео, ★ баҳо,
// шу таомга алоҳида изоҳ ва «Саватга». Бутун қарор серверда (нарх, мавжудлик) — бу ерда фақат кўрсатиш
// ва киритиш (44-қоида); мижозга ички тушунчалар (бўлим, индекс) кўринмайди (45-қоида).

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../home/widgets/ava_chip.dart';
import '../../home/widgets/ava_section.dart';
import '../../tv_market/models/tv_clip.dart';
import '../domain/cuisine.dart';
import '../domain/dish_stats.dart';
import '../domain/qty_tiers.dart';
import '../domain/restaurant_models.dart';
import 'menu_item_video_badge.dart';
import 'restaurant_cart_actions.dart';

/// Варақни очади. [onOpenMenu] берилса (лентадан очилганда) — «Менюни кўриш» қатори чиқади; менюнинг ўзидан
/// очилганда `null` (мижоз аллақачон менюда).
Future<void> showDishDetailSheet(
  BuildContext context, {
  required MenuItem item,
  required Restaurant restaurant,
  required RestaurantCart cart,
  DishStats? stats,
  TvClip? clip,
  void Function(TvClip clip)? onPlayVideo,
  VoidCallback? onOpenMenu,
  Future<List<Cuisine>> Function()? cuisineLoader,
}) {
  final c = context.ava;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: c.surface,
    builder: (ctx) => DishDetailSheet(
      item: item,
      restaurant: restaurant,
      cart: cart,
      stats: stats,
      clip: clip,
      onPlayVideo: onPlayVideo,
      onOpenMenu: onOpenMenu,
      cuisineLoader: cuisineLoader,
    ),
  );
}

class DishDetailSheet extends StatefulWidget {
  const DishDetailSheet({
    super.key,
    required this.item,
    required this.restaurant,
    required this.cart,
    this.stats,
    this.clip,
    this.onPlayVideo,
    this.onOpenMenu,
    this.cuisineLoader,
  });

  final MenuItem item;
  final Restaurant restaurant;
  final RestaurantCart cart;
  final DishStats? stats;
  final TvClip? clip;
  final void Function(TvClip clip)? onPlayVideo;
  final VoidCallback? onOpenMenu;
  final Future<List<Cuisine>> Function()? cuisineLoader;

  @override
  State<DishDetailSheet> createState() => _DishDetailSheetState();
}

class _DishDetailSheetState extends State<DishDetailSheet> {
  late final TextEditingController _note = TextEditingController(text: _inCart ? widget.cart.noteOf(widget.item.id) : '');
  Future<String?>? _cuisineName;

  bool get _inCart => widget.cart.restaurantId == widget.restaurant.id && widget.cart.qtyOf(widget.item.id) > 0;

  int get _qty => widget.cart.restaurantId == widget.restaurant.id ? widget.cart.qtyOf(widget.item.id) : 0;

  /// Ресторан ҳозир очиқ ёки олдиндан буюртма олади (S4b) — ресторан экранидаги қоида билан бир хил.
  bool get _canOrder => widget.restaurant.isOpenNow || widget.restaurant.acceptsPreorder;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<String?> _loadCuisineName(String lang) async {
    final id = widget.item.facts.cuisineId;
    final loader = widget.cuisineLoader;
    if (id == null || loader == null) return null;
    try {
      for (final c in await loader()) {
        if (c.id == id) return c.displayName(lang);
      }
    } catch (_) {
      // Кухна номи — ихтиёрий қўшимча: ўқилмаса чип кўрсатилмайди, варақ ишлайверади.
    }
    return null;
  }

  Future<void> _zoom() {
    final photo = widget.item.photoUrl.trim();
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                key: const ValueKey('dish-photo-zoom'),
                maxScale: 5,
                child: CachedNetworkImage(imageUrl: photo, fit: BoxFit.contain),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  tooltip: ctx.tr('close'),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final lang = context.contentLang;
    _cuisineName ??= _loadCuisineName(lang);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ListenableBuilder(
        listenable: widget.cart,
        builder: (context, _) {
          final qty = _qty;
          // Саватдан чиқарилса изоҳ ҳам кетади — майдон бўш бошлансин.
          if (qty == 0 && _note.text.isNotEmpty) _note.clear();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _photo(context, c),
                      const SizedBox(height: 12),
                      Text(
                        widget.item.name,
                        key: const ValueKey('dish-sheet-name'),
                        style: AvaText.sectionTitle.copyWith(color: c.ink),
                      ),
                      if (widget.onOpenMenu != null) _restaurantRow(context, c),
                      const SizedBox(height: 8),
                      _priceRow(context, c),
                      ..._notices(context, c),
                      if (widget.item.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          widget.item.description.trim(),
                          key: const ValueKey('dish-sheet-description'),
                          style: AvaText.dishNote.copyWith(fontSize: 13, height: 1.45, color: c.ink2),
                        ),
                      ],
                      ..._facts(context, c, lang),
                      ..._tiers(context, c, qty),
                      if (qty > 0) ..._noteField(context, c),
                    ],
                  ),
                ),
              ),
              _bottomBar(context, c, qty),
            ],
          );
        },
      ),
    );
  }

  // ── Қисмлар ────────────────────────────────────────────────────────

  Widget _photo(BuildContext context, AvaColors c) {
    final photo = widget.item.photoUrl.trim();
    final hasPhoto = photo.startsWith('http');
    final clip = widget.clip;
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(AvaRadius.card),
      child: AspectRatio(
        aspectRatio: hasPhoto ? 4 / 3 : 16 / 7,
        child: hasPhoto
            ? CachedNetworkImage(
                imageUrl: photo,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _photoPlaceholder(c),
              )
            : _photoPlaceholder(c),
      ),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        hasPhoto
            ? InkWell(
                key: const ValueKey('dish-sheet-photo'),
                borderRadius: BorderRadius.circular(AvaRadius.card),
                onTap: _zoom,
                child: image,
              )
            : image,
        if (clip != null && widget.onPlayVideo != null)
          Positioned(
            right: 4,
            bottom: 4,
            child: MenuItemVideoBadge(itemId: widget.item.id, onTap: () => widget.onPlayVideo!(clip)),
          ),
      ],
    );
  }

  Widget _photoPlaceholder(AvaColors c) =>
      ColoredBox(color: c.surface2, child: Icon(Icons.restaurant_rounded, size: 40, color: c.ink3));

  Widget _restaurantRow(BuildContext context, AvaColors c) {
    return InkWell(
      key: const ValueKey('dish-sheet-open-menu'),
      onTap: widget.onOpenMenu,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AvaTap.minSize),
        // «Менюни кўриш» ўз кенглигини олади (экраннинг ярмигача), ресторан номи қолганини; катта шрифтда ҳам
        // overflow йўқ — иккаласи ҳам `…` билан қисқаради.
        child: LayoutBuilder(
          builder: (context, box) => Row(
            children: [
              Icon(Icons.storefront_outlined, size: 18, color: c.ink2),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.restaurant.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AvaText.dishNote.copyWith(fontSize: 13, color: c.ink2),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box.maxWidth * 0.5),
                child: Text(
                  context.tr('restaurants_dish_view_menu'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AvaText.dishNote.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: c.brandText),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: c.brandText),
            ],
          ),
        ),
      ),
    );
  }

  Widget _priceRow(BuildContext context, AvaColors c) {
    final item = widget.item;
    final stats = widget.stats;
    final perPerson = (item.facts.servings ?? 0) > 1 ? item.pricePerPerson : null;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${formatPrice(item.price)} ${context.tr('sum')}',
          key: const ValueKey('dish-sheet-price'),
          style: AvaText.price.copyWith(color: c.brandText, fontSize: 20),
        ),
        if (perPerson != null)
          Text(
            context.tr('restaurants_dish_per_person').replaceAll('{price}', '${formatPrice(perPerson)} ${context.tr('sum')}'),
            key: const ValueKey('dish-sheet-per-person'),
            style: AvaText.dishNote.copyWith(color: c.ink2),
          ),
        if (stats != null && stats.showRating)
          Row(
            key: const ValueKey('dish-sheet-rating'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star_rounded, size: 18, color: c.brand),
              const SizedBox(width: 2),
              Text(
                '${stats.average.toStringAsFixed(1)} · ${context.tr('restaurants_dish_rating_count').replaceAll('{n}', '${stats.ratingCount}')}',
                style: TextStyle(fontSize: 13, color: c.ink2),
              ),
            ],
          )
        else
          AvaChip(key: const ValueKey('dish-sheet-new'), label: context.tr('restaurants_new'), tone: AvaChipTone.brand),
      ],
    );
  }

  List<Widget> _notices(BuildContext context, AvaColors c) {
    if (!widget.item.isAvailable) {
      return [
        const SizedBox(height: 8),
        AvaNoticeRow(
          key: const ValueKey('dish-sheet-sold-out'),
          text: context.tr('restaurants_item_sold_out'),
          icon: Icons.remove_shopping_cart_outlined,
          color: c.warn,
        ),
      ];
    }
    if (!_canOrder) {
      return [
        const SizedBox(height: 8),
        AvaNoticeRow(
          key: const ValueKey('dish-sheet-closed'),
          text: context.tr('restaurants_closed_now'),
          icon: Icons.nightlight_round,
          color: c.warn,
        ),
      ];
    }
    return const [];
  }

  List<Widget> _facts(BuildContext context, AvaColors c, String lang) {
    final f = widget.item.facts;
    if (f.isEmpty) return const [];
    final chips = <Widget>[
      if (f.servings != null)
        AvaChip(label: context.tr('restaurants_dish_serves').replaceAll('{n}', '${f.servings}'), icon: Icons.people_outline_rounded),
      if (f.weightG != null)
        AvaChip(label: context.tr('restaurants_dish_grams').replaceAll('{n}', '${f.weightG}'), icon: Icons.scale_outlined),
      for (final t in f.tags) AvaChip(label: context.tr('restaurants_m_dish_tag_$t')),
    ];
    return [
      const SizedBox(height: 12),
      Wrap(
        key: const ValueKey('dish-sheet-facts'),
        spacing: 6,
        runSpacing: 6,
        children: [
          ...chips,
          if (f.hasCuisine)
            FutureBuilder<String?>(
              future: _cuisineName,
              builder: (context, snap) {
                final name = snap.data;
                if (name == null || name.trim().isEmpty) return const SizedBox.shrink();
                return AvaChip(key: const ValueKey('dish-sheet-cuisine'), label: name, icon: Icons.public_rounded);
              },
            ),
        ],
      ),
      if (f.hasNutrition) ...[
        const SizedBox(height: 12),
        Text(context.tr('restaurants_dish_nutrition_title'), style: AvaText.dishNote.copyWith(color: c.ink2)),
        const SizedBox(height: 6),
        Row(
          key: const ValueKey('dish-sheet-nutrition'),
          children: [
            _NutritionCell(label: context.tr('restaurants_m_dish_kcal_short').replaceAll('{n}', '${f.kcal}'), strong: true),
            _NutritionCell(label: context.tr('restaurants_m_dish_protein_short'), value: context.tr('restaurants_dish_grams').replaceAll('{n}', '${f.protein}')),
            _NutritionCell(label: context.tr('restaurants_m_dish_fat_short'), value: context.tr('restaurants_dish_grams').replaceAll('{n}', '${f.fat}')),
            _NutritionCell(label: context.tr('restaurants_m_dish_carbs_short'), value: context.tr('restaurants_dish_grams').replaceAll('{n}', '${f.carbs}')),
          ],
        ),
      ],
    ];
  }

  List<Widget> _tiers(BuildContext context, AvaColors c, int qty) {
    final tiers = widget.item.qtyTiers;
    if (tiers.isEmpty) return const [];
    final applied = QtyTiers.unitPriceFor(widget.item.price, tiers, qty).tierMinQty;
    final next = qty > 0 ? QtyTiers.nextTier(tiers, qty) : null;
    return [
      const SizedBox(height: 16),
      Text(context.tr('restaurants_dish_tiers_title'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
      const SizedBox(height: 6),
      Container(
        key: const ValueKey('dish-sheet-tiers'),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(AvaRadius.card),
        ),
        child: Column(
          children: [
            for (final t in tiers)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  key: ValueKey('dish-sheet-tier-${t.minQty}'),
                  children: [
                    Expanded(
                      child: Text(
                        context
                            .tr('restaurants_tier_from')
                            .replaceAll('{min}', '${t.minQty}')
                            .replaceAll('{price}', '${formatPrice(t.price)} ${context.tr('sum')}'),
                        style: AvaText.dishNote.copyWith(
                          fontSize: 13,
                          fontWeight: applied == t.minQty ? FontWeight.w700 : FontWeight.w400,
                          color: applied == t.minQty ? c.ok : c.ink,
                        ),
                      ),
                    ),
                    if (applied == t.minQty) Icon(Icons.check_circle_rounded, size: 18, color: c.ok),
                  ],
                ),
              ),
          ],
        ),
      ),
      if (next != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            context
                .tr('restaurants_tier_next')
                .replaceAll('{n}', '${next.minQty - qty}')
                .replaceAll('{price}', '${formatPrice(next.price)} ${context.tr('sum')}'),
            key: const ValueKey('dish-sheet-tier-next'),
            style: AvaText.dishNote.copyWith(color: c.brandText),
          ),
        ),
    ];
  }

  List<Widget> _noteField(BuildContext context, AvaColors c) {
    return [
      const SizedBox(height: 16),
      Text(context.tr('restaurants_dish_note_title'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
      const SizedBox(height: 6),
      TextField(
        key: const ValueKey('dish-sheet-note'),
        controller: _note,
        maxLength: RestaurantCart.maxItemNote,
        maxLines: 2,
        minLines: 1,
        textInputAction: TextInputAction.done,
        onChanged: (v) => widget.cart.setNote(widget.item.id, v),
        // Киритилаётган матн ўқилсин (14 px), маслаҳат — иккинчи даража (контраст ≥ 4.5:1).
        style: AvaText.dishNote.copyWith(fontSize: 14, color: c.ink),
        decoration: InputDecoration(
          hintText: context.tr('restaurants_dish_note_hint'),
          hintStyle: AvaText.dishNote.copyWith(fontSize: 13, color: c.ink2),
          counterText: '',
          filled: true,
          fillColor: c.surface2,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AvaRadius.search), borderSide: BorderSide.none),
        ),
      ),
    ];
  }

  Widget _bottomBar(BuildContext context, AvaColors c, int qty) {
    final item = widget.item;
    final restaurant = widget.restaurant;
    final orderable = item.isAvailable && _canOrder;
    final canAdd = orderable && (widget.cart.restaurantId != restaurant.id || widget.cart.canAddMore(item.id, restaurant));
    final style = FilledButton.styleFrom(
      backgroundColor: c.brand,
      foregroundColor: c.brandInk,
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    final Widget action;
    if (!item.isAvailable) {
      action = FilledButton(
        key: const ValueKey('dish-sheet-add'),
        onPressed: null,
        style: style,
        child: Text(context.tr('restaurants_item_sold_out')),
      );
    } else if (!_canOrder) {
      action = FilledButton(
        key: const ValueKey('dish-sheet-add'),
        onPressed: null,
        style: style,
        child: Text(context.tr('restaurants_closed')),
      );
    } else if (qty == 0) {
      action = FilledButton(
        key: const ValueKey('dish-sheet-add'),
        onPressed: () => addToCartOrAskSwitch(context, cart: widget.cart, item: item, restaurant: restaurant),
        style: style,
        child: Text(
          '${context.tr('restaurants_dish_add_cart')} · ${formatPrice(item.price)} ${context.tr('sum')}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      );
    } else {
      final line = CartLine(item: item, qty: qty);
      action = Row(
        children: [
          _RoundButton(
            key: const ValueKey('dish-sheet-minus'),
            icon: Icons.remove_rounded,
            filled: false,
            onTap: () => widget.cart.decrement(item.id),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$qty',
              key: const ValueKey('dish-sheet-qty'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink),
            ),
          ),
          _RoundButton(
            key: const ValueKey('dish-sheet-plus'),
            icon: Icons.add_rounded,
            onTap: canAdd ? () => addToCartOrAskSwitch(context, cart: widget.cart, item: item, restaurant: restaurant) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              key: const ValueKey('dish-sheet-done'),
              onPressed: () => Navigator.of(context).pop(),
              style: style,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${context.tr('restaurants_dish_done')} · ${formatPrice(line.lineTotal)} ${context.tr('sum')}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
      child: SizedBox(width: double.infinity, child: action),
    );
  }
}

class _NutritionCell extends StatelessWidget {
  const _NutritionCell({required this.label, this.value, this.strong = false});

  final String label;
  final String? value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Expanded(
      child: Container(
        margin: const EdgeInsetsDirectional.only(end: 6),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(color: strong ? c.brandSoft : c.surface2, borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            Text(
              value ?? label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: strong ? c.brandText : c.ink),
            ),
            if (value != null) Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AvaText.dishNote.copyWith(color: c.ink2)),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({super.key, required this.icon, required this.onTap, this.filled = true});

  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Material(
      color: filled ? c.brand : c.surface2,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: AvaTap.minSize,
          height: AvaTap.minSize,
          child: Icon(icon, size: 22, color: filled ? c.brandInk : c.ink),
        ),
      ),
    );
  }
}
