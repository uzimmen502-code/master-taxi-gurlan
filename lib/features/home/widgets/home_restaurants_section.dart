// Бош экран бўлими «Яқиндаги Кафе-Ресторанлар» (D-REST-6, D-REST-13):
// «Яқиндаги хизматлар»дан кейин, рўйхат кўринишида, энг яқин
// ресторанлар; «Барчаси →» — тўлиқ рўйхат.
//
// Кўриниш дарвозаси ШУ ЕРДА: модул очиқ бўлса — ҳамма; «Тез кунда»/
// «Ҳамкорлик» бўлса — фақат INTERNAL синовчи (сервер `testerIds`,
// logistics намунаси, 42-банд); яширин бўлса — йўқ.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../services/location_service.dart';
import '../../restaurants/data/restaurants_repository.dart';
import '../../restaurants/domain/restaurant_models.dart';
import '../../restaurants/domain/restaurants_access.dart';
import '../../restaurants/widgets/restaurant_row.dart';
import 'ava_section.dart';

class HomeRestaurantsSection extends StatefulWidget {
  const HomeRestaurantsSection({
    super.key,
    required this.onOpenAll,
    required this.onOpenRestaurant,
    this.userLat,
    this.userLng,
    this.repository,
    this.accessCheck,
    this.locate,
  });

  final VoidCallback onOpenAll;
  final void Function(Restaurant restaurant) onOpenRestaurant;

  /// Фойдаланувчи манзили (профил) — масофа ва тартиб учун; йўқ бўлса
  /// ном бўйича.
  final double? userLat;
  final double? userLng;
  final RestaurantsRepository? repository;

  /// Тестда алмаштириш учун; стандарт — [RestaurantsRepository.hasAccess].
  final Future<bool> Function()? accessCheck;

  /// GPS (D-GEO-4: биринчи) — стандарт рухсат сўрамайдиган
  /// [LocationService.getCoordsIfAllowed]; тестда алмаштирилади.
  final Future<LocationCoords?> Function()? locate;

  static const moduleId = kRestaurantsModuleId;
  static const limit = 20;
  static const visibleRows = 4;

  @override
  State<HomeRestaurantsSection> createState() => _HomeRestaurantsSectionState();
}

class _HomeRestaurantsSectionState extends State<HomeRestaurantsSection> {
  late final RestaurantsRepository _repo = widget.repository ?? RestaurantsRepository();
  StreamSubscription<List<Restaurant>>? _sub;

  /// `null` — ҳали аниқланмаган (синовчи текшируви кетмоқда).
  bool? _allowed;
  AvaSectionStatus _status = AvaSectionStatus.loading;
  List<Restaurant> _items = const [];

  /// Масофа нуқтаси: GPS (бўлса) → профил манзили.
  double? _lat;
  double? _lng;
  bool _fromGps = false;

  @override
  void initState() {
    super.initState();
    _lat = widget.userLat;
    _lng = widget.userLng;
    ServiceConfigHolder.revision.addListener(_resolveGate);
    _resolveGate();
    _loadGps();
  }

  @override
  void didUpdateWidget(covariant HomeRestaurantsSection old) {
    super.didUpdateWidget(old);
    // Профил кечроқ юкланади — GPS бўлмаса шу манзилга ўтамиз.
    if (_fromGps) return;
    if (old.userLat == widget.userLat && old.userLng == widget.userLng) return;
    _lat = widget.userLat;
    _lng = widget.userLng;
    if (_allowed == true) _listen();
  }

  Future<void> _loadGps() async {
    final locate = widget.locate ?? const LocationService().getCoordsIfAllowed;
    final c = await locate();
    if (!mounted || c == null) return;
    _lat = c.lat;
    _lng = c.lng;
    _fromGps = true;
    if (_allowed == true) _listen();
  }

  Future<void> _resolveGate() async {
    final ok = await resolveRestaurantsAccess(
      accessCheck: widget.accessCheck ?? _repo.hasAccess,
    );
    _setAllowed(ok);
  }

  void _setAllowed(bool v) {
    if (!mounted) return;
    if (_allowed == v) return;
    setState(() => _allowed = v);
    if (v) {
      _listen();
    } else {
      _sub?.cancel();
      _sub = null;
    }
  }

  void _listen() {
    _sub?.cancel();
    if (mounted) setState(() => _status = AvaSectionStatus.loading);
    final lat = _lat;
    final lng = _lng;
    // Координата бор — яқиндагилар сервер сўрови (D-GEO-4); йўқ — аввалги
    // умумий рўйхат (ном бўйича).
    final stream = lat != null && lng != null
        ? _repo.watchNearby(lat: lat, lng: lng)
        : _repo.watchApproved(limit: HomeRestaurantsSection.limit);
    _sub = stream.listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _items = _sorted(list);
          _status = _items.isEmpty ? AvaSectionStatus.empty : AvaSectionStatus.ready;
        });
      },
      onError: (Object e) {
        debugPrint('[HomeRestaurants] $e');
        if (mounted) setState(() => _status = AvaSectionStatus.error);
      },
    );
  }

  /// Очиқлар олдин, кейин масофа (координата бўлса) ёки ном бўйича.
  List<Restaurant> _sorted(List<Restaurant> list) {
    final out = List<Restaurant>.from(list);
    final now = DateTime.now();
    out.sort((a, b) {
      final oa = a.isOpenAt(now) ? 0 : 1;
      final ob = b.isOpenAt(now) ? 0 : 1;
      if (oa != ob) return oa - ob;
      final da = a.distanceKmFrom(_lat, _lng);
      final db = b.distanceKmFrom(_lat, _lng);
      if (da != null && db != null && da != db) return da.compareTo(db);
      if (da == null && db != null) return 1;
      if (da != null && db == null) return -1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  @override
  void dispose() {
    ServiceConfigHolder.revision.removeListener(_resolveGate);
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed != true) return const SizedBox.shrink();
    // Бошқа бўлимлардагидек (Танишув, Эълонлар): ботиқ майдонча + саҳифаланувчи
    // бир қаторли рўйхат. Логотип ва чиплар — «Барчаси →» даги тўлиқ рўйхатда.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AvaSpace.sectionMin),
        AvaSection(
          moduleId: HomeRestaurantsSection.moduleId,
          title: context.tr('home_section_restaurants'),
          status: _status,
          onSeeAll: widget.onOpenAll,
          onRetry: _listen,
          emptyLabel: context.tr('restaurants_empty_nearby'),
          child: AvaInsetPanel(
            child: AvaRowPager(
              rowHeight: AvaRowPager.textRowHeight(context),
              onOpenModule: widget.onOpenAll,
              rows: [
                for (final r in _items)
                  _RestaurantTextRow(
                    restaurant: r,
                    distanceKm: r.distanceKmFrom(_lat, _lng),
                    onTap: () => widget.onOpenRestaurant(r),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Битта ресторан: ● ном · ошхона ........ ~1.2 км. Ёпиқ ресторан хира,
/// нуқтаси бўш ва «Ёпиқ» ёрлиғи билан. Масофа тўғри чизиқ бўйича (шунинг учун
/// «~»); координата йўқ бўлса масофа кўрсатилмайди, қатор қолади.
class _RestaurantTextRow extends StatelessWidget {
  const _RestaurantTextRow({
    required this.restaurant,
    required this.distanceKm,
    required this.onTap,
  });

  final Restaurant restaurant;
  final double? distanceKm;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final r = restaurant;
    final open = r.isOpenNow;
    final textColor = open ? c.inkRow : c.ink3;
    final cuisine = r.cuisineTags.isEmpty ? '' : r.cuisineTags.first;
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
              color: open ? c.ink : Colors.transparent,
              shape: BoxShape.circle,
              border: open ? null : Border.all(color: c.ink3),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              r.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AvaText.feedRow.copyWith(color: textColor),
            ),
          ),
          if (cuisine.isNotEmpty)
            Flexible(
              child: Text(
                ' · $cuisine',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AvaText.feedRow.copyWith(color: c.ink3),
              ),
            ),
          const Spacer(),
          if (!open)
            Text(
              context.tr('restaurants_closed'),
              style: AvaText.feedRow.copyWith(color: c.ink3),
            ),
          if (!open && distanceKm != null)
            Text(' · ', style: AvaText.feedRow.copyWith(color: c.ink3)),
          if (distanceKm != null)
            Text(
              '~${formatDistanceLabel(context, distanceKm!)}',
              style: AvaText.feedRow
                  .copyWith(color: c.brandText, fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }
}