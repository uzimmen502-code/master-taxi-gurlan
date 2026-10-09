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
import '../../restaurants/data/restaurants_repository.dart';
import '../../restaurants/domain/restaurant_models.dart';
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

  static const moduleId = 'restaurants';
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

  @override
  void initState() {
    super.initState();
    ServiceConfigHolder.revision.addListener(_resolveGate);
    _resolveGate();
  }

  Future<void> _resolveGate() async {
    final id = HomeRestaurantsSection.moduleId;
    if (ServiceConfigHolder.isOpenable(id)) {
      _setAllowed(true);
      return;
    }
    if (!ServiceConfigHolder.isVisible(id)) {
      _setAllowed(false);
      return;
    }
    final ok = await (widget.accessCheck ?? _repo.hasAccess)();
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
    _sub = _repo.watchApproved(limit: HomeRestaurantsSection.limit).listen(
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
      final da = a.distanceKmFrom(widget.userLat, widget.userLng);
      final db = b.distanceKmFrom(widget.userLat, widget.userLng);
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
    // Табиий баландликдаги устун (саҳифаловчи `AvaRowPager` ЭМАС): қатор
    // ичида чиплар катта шрифтда иккинчи қаторга тушиши мумкин — қатъий
    // баландлик уни кесарди. Кўрсатиладигани — [visibleRows] та, қолгани
    // «Барчаси →» да.
    final shown = _items.take(HomeRestaurantsSection.visibleRows).toList(growable: false);
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                RestaurantRow(
                  restaurant: shown[i],
                  distanceKm: shown[i].distanceKmFrom(widget.userLat, widget.userLng),
                  onTap: () => widget.onOpenRestaurant(shown[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
