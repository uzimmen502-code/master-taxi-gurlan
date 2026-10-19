// Бўлим кўриниши (S3, D-REST-33): танланган бўлимдаги таомлар — мижоз яқинидаги тасдиқланган
// ресторанлардан, «Янги» тепада. Тартиб ва қоида — соф функцияларда (`rankSectionDishes`), бу ерда
// фақат юклаш ва кўрсатиш (44-қоида). Мижозга ички тушунчалар (индекс, geo4, тартиб қоидаси)
// кўринмайди — оддий таом рўйхати (45-қоида).

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../home/widgets/ava_section.dart';
import '../data/restaurants_repository.dart';
import '../domain/cuisine.dart';
import '../domain/restaurant_sections.dart';
import '../domain/seasons.dart';
import 'restaurant_row.dart' show formatDistanceLabel;

/// Бўлим белгиси (иконка — эмодзи эмас: қурилмага қараб ҳар хил чизилмасин).
IconData sectionIcon(RestaurantSection s) => switch (s) {
      RestaurantSection.all => Icons.restaurant_menu_rounded,
      RestaurantSection.cheap => Icons.savings_outlined,
      RestaurantSection.national => Icons.rice_bowl_outlined,
      RestaurantSection.world => Icons.public_rounded,
      RestaurantSection.fast => Icons.bolt_rounded,
      RestaurantSection.light => Icons.eco_outlined,
      RestaurantSection.kids => Icons.child_care_rounded,
      RestaurantSection.breakfast => Icons.free_breakfast_outlined,
      RestaurantSection.night => Icons.nightlight_outlined,
      RestaurantSection.office => Icons.business_center_outlined,
      RestaurantSection.dastarxon => Icons.table_restaurant_outlined,
      RestaurantSection.seasonal => Icons.celebration_outlined,
    };

class SectionDishesView extends StatefulWidget {
  const SectionDishesView({
    super.key,
    required this.section,
    required this.config,
    required this.repository,
    required this.lat,
    required this.lng,
    required this.onOpenRestaurant,
    this.now,
    this.seasons = const [],
    this.ramadan = RamadanConfig.none,
    this.regionId,
    this.onShowNation,
  });

  final RestaurantSection section;
  final RestaurantSectionsConfig config;
  final RestaurantsRepository repository;

  /// Мижоз нуқтаси; `null` — бўлим кўрсатилмайди (яқинини аниқлаб бўлмайди).
  final double? lat;
  final double? lng;

  /// Таом босилди: ресторан идентификатори.
  final void Function(String restaurantId) onOpenRestaurant;

  /// Тест учун соат.
  final DateTime Function()? now;

  /// «Мавсумий» бўлим: ҳозир очиқ мавсумлар (бўш бўлса бўлим бўш), Рамазон жадвали ва фойдаланувчи ҳудуди
  /// (geo_regions id; ифтор/саҳарлик вақти шу ҳудуд жадвалда бўлсагина кўрсатилади).
  final List<ActiveSeason> seasons;
  final RamadanConfig ramadan;
  final String? regionId;

  /// Яқин атрофда таом йўқ бўлганда «Бутун Ўзбекистон» тугмаси (ресторанлар рўйхатини кенгроқ очади); null — тугма йўқ.
  final VoidCallback? onShowNation;
  @override
  State<SectionDishesView> createState() => _SectionDishesViewState();
}

class _SectionDishesViewState extends State<SectionDishesView> {
  SectionDishesResult? _result;
  Object? _error;
  bool _loading = false;
  String? _cuisineId;
  String? _seasonKey;
  Map<String, Cuisine> _cuisines = const {};

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SectionDishesView old) {
    super.didUpdateWidget(old);
    final moved = old.lat != widget.lat || old.lng != widget.lng;
    if (old.section != widget.section || (moved && _result == null)) {
      _cuisineId = null;
      _seasonKey = null;
      _load();
    }
  }

  Future<void> _load() async {
    final lat = widget.lat;
    final lng = widget.lng;
    // Юклаш кетяпти — қайта-қайта босилса (қайта уриниш + тортиб янгилаш) иккинчи сўров очилмайди.
    if (lat == null || lng == null || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final section = widget.section;
    try {
      final res = await widget.repository
          .fetchSectionDishes(section, lat: lat, lng: lng);
      Map<String, Cuisine> cuisines = _cuisines;
      if (section.hasCuisineFilter) {
        // Кухна номлари — ихтиёрий қўшимча: ўқилмаса чип номи ўрнига id кўрсатилмайди (чип яширилади).
        try {
          cuisines = {
            for (final c in await widget.repository.listCuisines()) c.id: c
          };
        } catch (_) {}
      }
      if (!mounted || section != widget.section) return;
      setState(() {
        _result = res;
        _cuisines = cuisines;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[SectionDishes] ${section.key} $e');
      if (!mounted || section != widget.section) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    if (widget.lat == null || widget.lng == null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: AvaNoticeRow(
            text: context.tr('restaurants_dish_no_location'),
            icon: Icons.location_off_outlined,
            color: c.warn),
      );
    }
    final res = _result;
    if (res == null) {
      if (_error != null) return _errorView(context);
      return const Center(child: CircularProgressIndicator());
    }
    final activeKeys = {for (final s in widget.seasons) s.key};
    // Мавсумий бўлим: фақат ҳозир ОЧИҚ мавсум тегли таомлар (бошқа мавсум таоми кўринмайди); танланган мавсум чипи бўйича.
    final base = widget.section.hasSeasonFilter
        ? res.dishes.where((d) => d.seasons.any(activeKeys.contains)).toList()
        : res.dishes;
    final filtered = widget.section.hasSeasonFilter
        ? (_seasonKey == null ? base : base.where((d) => d.seasons.contains(_seasonKey)).toList())
        : _cuisineId == null
            ? base
            : base.where((d) => d.cuisineId == _cuisineId).toList();
    final ranked = rankSectionDishes(
      filtered,
      section: widget.section,
      config: widget.config,
      now: _now,
      lat: widget.lat,
      lng: widget.lng,
    );
    final lang = context.contentLang;
    // Кухна чиплари: фақат камида битта таоми борлар (D-REST-24); номи маълум бўлганлар.
    final cuisineChips = widget.section.hasCuisineFilter
        ? [
            for (final e in cuisinesIn(res.dishes))
              if (_cuisines[e.id] != null)
                (cuisine: _cuisines[e.id]!, count: e.count),
          ]
        : const <({Cuisine cuisine, int count})>[];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: ValueKey('section-list-${widget.section.key}'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        children: [
          if (widget.section.hasSeasonFilter) ..._seasonHeader(context, base),
          if (cuisineChips.length > 1)
            SizedBox(
              height: 40,
              child: ListView(
                key: const ValueKey('cuisine-chips'),
                scrollDirection: Axis.horizontal,
                children: [
                  ChoiceChip(
                    label: Text(context.tr('restaurants_cuisine_all')),
                    selected: _cuisineId == null,
                    onSelected: (_) => setState(() => _cuisineId = null),
                  ),
                  for (final e in cuisineChips) ...[
                    const SizedBox(width: 6),
                    ChoiceChip(
                      key: ValueKey('cuisine-${e.cuisine.id}'),
                      label:
                          Text('${e.cuisine.displayName(lang)} · ${e.count}'),
                      selected: _cuisineId == e.cuisine.id,
                      onSelected: (v) =>
                          setState(() => _cuisineId = v ? e.cuisine.id : null),
                    ),
                  ],
                ],
              ),
            ),
          if (res.truncated)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: AvaNoticeRow(
                  text: context.tr('restaurants_dish_truncated'),
                  icon: Icons.info_outline_rounded,
                  color: c.ink3),
            ),
          if (ranked.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AvaNoticeRow(
                      text: context.tr('restaurants_dish_empty'),
                      icon: Icons.restaurant_outlined,
                      color: c.ink3),
                  if (widget.onShowNation != null)
                    Align(
                      child: OutlinedButton.icon(
                        key: const ValueKey('dishes_show_nation'),
                        icon: const Icon(Icons.public, size: 16),
                        label: Text(context.tr('geo_show_nation')),
                        onPressed: widget.onShowNation,
                      ),
                    ),
                ],
              ),
            )
          else
            // Катта расмли карточкалар: кенг экранда 2 устун, тор экранда (< 340) битта (D-REST-40, эга: «2-чисини қил»).
            LayoutBuilder(
              builder: (context, box) {
                final cols = box.maxWidth >= 340 ? 2 : 1;
                Widget card(RankedDish r) => SectionDishCard(
                      key: ValueKey('dish-${r.dish.key}'),
                      ranked: r,
                      section: widget.section,
                      config: widget.config,
                      distanceKm: r.dish.distanceKmFrom(widget.lat, widget.lng),
                      onTap: () => widget.onOpenRestaurant(r.dish.restaurantId),
                    );
                return Column(
                  children: [
                    for (var i = 0; i < ranked.length; i += cols)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var j = 0; j < cols; j++) ...[
                                if (j > 0) const SizedBox(width: 8),
                                Expanded(child: i + j < ranked.length ? card(ranked[i + j]) : const SizedBox.shrink()),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  /// Мавсумий бўлим боши: Рамазонда бугунги саҳарлик/ифтор (ҳудуд жадвалда бўлсагина — тахмин қилинмайди) ва
  /// бир нечта мавсум очиқ бўлса мавсум чиплари (камида битта таоми борлар).
  List<Widget> _seasonHeader(BuildContext context, List<SectionDish> base) {
    final c = context.ava;
    final out = <Widget>[];
    final ramadanOpen = widget.seasons.any((s) => s.key == SeasonKey.ramadan);
    final times = ramadanOpen ? widget.ramadan.timesFor(tashkentDay(_now), widget.regionId) : null;
    if (times != null) {
      out.add(Container(
        key: const ValueKey('ramadan-times'),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(AvaRadius.card)),
        child: Row(
          children: [
            Icon(Icons.nightlight_round, color: c.brandText, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr('restaurants_ramadan_today').replaceAll('{sahar}', times.sahar).replaceAll('{iftar}', times.iftar),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink),
              ),
            ),
          ],
        ),
      ));
    }
    final counts = <String, int>{
      for (final s in widget.seasons) s.key: base.where((d) => d.seasons.contains(s.key)).length,
    };
    final chips = [for (final s in widget.seasons) if ((counts[s.key] ?? 0) > 0) s];
    if (chips.length > 1) {
      out.add(SizedBox(
        height: 40,
        child: ListView(
          key: const ValueKey('season-chips'),
          scrollDirection: Axis.horizontal,
          children: [
            ChoiceChip(
              label: Text(context.tr('restaurants_cuisine_all')),
              selected: _seasonKey == null,
              onSelected: (_) => setState(() => _seasonKey = null),
            ),
            for (final s in chips) ...[
              const SizedBox(width: 6),
              ChoiceChip(
                key: ValueKey('season-${s.key}'),
                label: Text('${context.tr('restaurants_season_${s.key}')} · ${counts[s.key]}'),
                selected: _seasonKey == s.key,
                onSelected: (v) => setState(() => _seasonKey = v ? s.key : null),
              ),
            ],
          ],
        ),
      ));
    }
    return out;
  }

  Widget _errorView(BuildContext context) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AvaNoticeRow(
              text: context.tr('home_section_error'),
              icon: Icons.cloud_off_rounded,
              color: c.warn),
          const SizedBox(height: 8),
          Align(
            child: OutlinedButton.icon(
              key: const ValueKey('section-retry'),
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(context.tr('home_section_retry')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Бўлимдаги битта таом карточкаси — КАТТА расм тепада (+«Янги»), остида ном, ресторан · масофа, нарх (+бир кишилик),
/// рейтинг ва бўлимга хос чип (КБЖУ / тайёрлаш вақти / олдиндан буюртма). Ёпиқ ресторан — хира.
class SectionDishCard extends StatelessWidget {
  const SectionDishCard({
    super.key,
    required this.ranked,
    required this.section,
    required this.config,
    required this.onTap,
    this.distanceKm,
  });

  final RankedDish ranked;
  final RestaurantSection section;
  final RestaurantSectionsConfig config;
  final double? distanceKm;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final d = ranked.dish;
    final photo = d.photoUrl.trim();
    final perPerson = section == RestaurantSection.cheap ? d.pricePerPerson : null;
    final showRating = d.ratingCount >= config.newMaxRatings;
    final meta = <String>[
      d.restaurantName,
      if (distanceKm != null) formatDistanceLabel(context, distanceKm!),
    ].where((s) => s.isNotEmpty).join(' · ');
    return Opacity(
      opacity: ranked.isClosed ? 0.55 : 1,
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AvaRadius.card),
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 1.25,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      photo.startsWith('http')
                          ? CachedNetworkImage(imageUrl: photo, fit: BoxFit.cover, errorWidget: (_, __, ___) => _Placeholder(c))
                          : _Placeholder(c),
                      if (ranked.isNew)
                        Positioned(
                          left: 6,
                          top: 6,
                          child: Container(
                            key: ValueKey('new-${d.key}'),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: c.brand, borderRadius: BorderRadius.circular(8)),
                            child: Text(
                              context.tr('restaurants_dish_new'),
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.brandInk),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AvaText.productName.copyWith(color: c.ink, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ranked.isClosed ? '$meta · ${context.tr('restaurants_closed')}' : meta,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AvaText.caption.copyWith(color: ranked.isClosed ? c.warn : c.ink2),
                      ),
                      const SizedBox(height: 6),
                      // Нарх, рейтинг ва чиплар тор катакда ва катта шрифтда сиғмаса — Wrap кейинги қаторга ўтказади.
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (perPerson != null)
                            Text(
                              context.tr('restaurants_dish_per_person').replaceAll('{price}', '${formatPrice(perPerson)} ${context.tr('sum')}'),
                              key: ValueKey('pp-${d.key}'),
                              style: AvaText.price.copyWith(color: c.brandText),
                            )
                          else
                            Text('${formatPrice(d.price)} ${context.tr('sum')}', style: AvaText.price.copyWith(color: c.brandText)),
                          if (perPerson != null)
                            Text('${formatPrice(d.price)} ${context.tr('sum')}', style: AvaText.caption.copyWith(color: c.ink3)),
                          if (showRating)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star_rounded, size: 14, color: c.brand),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    '${d.ratingAvg.toStringAsFixed(1)} (${d.ratingCount})',
                                    key: ValueKey('rating-${d.key}'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AvaText.caption.copyWith(color: c.ink2),
                                  ),
                                ),
                              ],
                            ),
                          if (section == RestaurantSection.light && d.kcal != null)
                            Text(
                              context.tr('restaurants_dish_kcal').replaceAll('{kcal}', '${d.kcal}'),
                              key: ValueKey('kcal-${d.key}'),
                              style: AvaText.caption.copyWith(color: c.ink2),
                            ),
                          if (section.isPreorderBased)
                            Text(
                              context.tr('restaurants_dish_preorder'),
                              key: ValueKey('pre-${d.key}'),
                              style: AvaText.caption.copyWith(color: c.brandText),
                            ),
                          if (section == RestaurantSection.dastarxon && d.servings != null)
                            Text(
                              context.tr('restaurants_dish_serves').replaceAll('{n}', '${d.servings}'),
                              key: ValueKey('serves-${d.key}'),
                              style: AvaText.caption.copyWith(color: c.ink2),
                            ),
                          if (section == RestaurantSection.fast)
                            Text(
                              context.tr('restaurants_dish_prep').replaceAll('{min}', '${d.prepTimeMin}'),
                              key: ValueKey('prep-${d.key}'),
                              style: AvaText.caption.copyWith(color: c.ink2),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
class _Placeholder extends StatelessWidget {
  const _Placeholder(this.c);

  final AvaColors c;

  @override
  Widget build(BuildContext context) => ColoredBox(
      color: c.surface2, child: Icon(Icons.restaurant_rounded, color: c.ink3));
}
