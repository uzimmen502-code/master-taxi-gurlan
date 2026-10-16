import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/ev_car_tracker.dart';
import '../controllers/ev_route_progress.dart';
import '../controllers/ev_trip_planner.dart';
import '../models/ev_trip_plan.dart';
import '../widgets/ev_map_top_overlay.dart';
import '../widgets/ev_trip_map_view.dart';
import '../widgets/ev_trip_plan_view.dart';

/// Харитага узатиладиган ҳолат — `GoogleMap` платформа кўринишисиз
/// тестлаш учун харита ташқаридан қурилади ([EvTripMapBuilder]).
class EvTripMapRenderData {
  const EvTripMapRenderData({
    required this.route,
    required this.corridorStations,
    required this.plan,
    required this.destinationLat,
    required this.destinationLng,
    required this.progress,
    required this.carLat,
    required this.carLng,
    required this.carHeading,
    required this.follow,
    required this.padding,
    required this.onUserGesture,
  });

  final List<EvRoutePoint> route;
  final List<EvCorridorStation> corridorStations;
  final EvTripPlan plan;
  final double destinationLat;
  final double destinationLng;
  final EvRouteProgress? progress;
  final double? carLat;
  final double? carLng;
  final double carHeading;
  final bool follow;
  final EdgeInsets padding;
  final VoidCallback onUserGesture;
}

typedef EvTripMapBuilder = Widget Function(
  BuildContext context,
  EvTripMapRenderData data,
);

/// ⚡ Сафар режаси ҳисобланганидан кейин очиладиган ТЎЛИҚ ЭКРАНЛИ жонли
/// харита (эга қарори, 2026-10-16):
///  * харита бутун экранда (статус бар ва пастки соҳа остигача); юқорида
///    фақат думалоқ «орқага» тугмаси;
///  * маршрут, рақамланган тўхташлар, заҳиралар, йўл бўйидаги бошқа
///    станциялар, манзил — ва жонли машина маркери (GPS оқими);
///  * босиб ўтилган қисм хира, қолгани маршрут рангида;
///  * режанинг барча тафсилотлари ([EvTripPlanView]) — пастдан тортиб
///    очиладиган варақада (йиғиқ ҳолатда бир қатор хулоса).
class EvTripMapScreen extends StatefulWidget {
  const EvTripMapScreen({
    super.key,
    required this.plan,
    required this.route,
    required this.corridorStations,
    required this.destinationLat,
    required this.destinationLng,
    required this.onOpenNavigator,
    this.locationSource,
    this.mapBuilder,
  });

  final EvTripPlan plan;
  final List<EvRoutePoint> route;
  final List<EvCorridorStation> corridorStations;
  final double destinationLat;
  final double destinationLng;
  final VoidCallback onOpenNavigator;

  /// Тест учун: GPS манбаси. Бўлмаса — қурилма GPS'и.
  final EvCarLocationSource? locationSource;

  /// Тест учун: харита. Бўлмаса — [EvTripMapView] (`GoogleMap`).
  final EvTripMapBuilder? mapBuilder;

  /// Йиғиқ варақадаги бир қатор хулоса: «N марта зарядлаш керак · X км».
  static String peekText(BuildContext context, EvTripPlan plan) {
    final km = '${plan.totalKm.round()} ${context.tr('ev_trip_km')}';
    switch (plan.status) {
      case EvTripPlanStatus.noChargingNeeded:
        return '${context.tr('ev_trip_no_charging')} · $km';
      case EvTripPlanStatus.gapTooLarge:
        return context.tr('ev_trip_gap_title');
      default:
        return '${plan.chargeStopCount} ${context.tr('ev_trip_charge_stops')} · $km';
    }
  }

  @override
  State<EvTripMapScreen> createState() => _EvTripMapScreenState();
}

class _EvTripMapScreenState extends State<EvTripMapScreen>
    with WidgetsBindingObserver {
  /// Варақанинг йиғиқ (peek) баландлиги: тутқич + бир қатор хулоса.
  static const double _peekContentPx = 84;
  static const double _maxSheetFraction = 0.88;

  /// Машина "орқага сакрамаслиги" учун: охирги сегментдан шунча олдинга
  /// қайтишга рухсат (GPS шовқини).
  static const int _segmentBacktrack = 3;

  late final EvCarTracker _car;
  final _sheetCtrl = DraggableScrollableController();

  EvRouteProgress? _progress;
  int _segmentHint = 0;
  bool _follow = false;
  double _extent = 0;

  @override
  void initState() {
    super.initState();
    // Харита статус бар ва пастки соҳа остигача.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.addObserver(this);
    _car = EvCarTracker(
      source: widget.locationSource ?? const GeolocatorCarLocationSource(),
    )..addListener(_onCar);
    _car.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _car
      ..removeListener(_onCar)
      ..dispose();
    _sheetCtrl.dispose();
    // Бошқа экранлар учун одатдаги тизим панелларига қайтарилади.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _car.pause();
    } else if (state == AppLifecycleState.resumed) {
      _car.resume();
    }
  }

  void _onCar() {
    if (!mounted) return;
    final fix = _car.fix;
    EvRouteProgress? progress;
    if (fix != null) {
      progress = EvRouteProgress.compute(
        route: widget.route,
        lat: fix.lat,
        lng: fix.lng,
        fromSegment: math.max(0, _segmentHint - _segmentBacktrack),
      );
      if (progress != null && progress.isOnRoute) {
        _segmentHint = progress.location.segmentIndex;
      }
    }
    setState(() => _progress = progress);
  }

  void _onUserGesture() {
    if (_follow) setState(() => _follow = false);
  }

  void _recenter() => setState(() => _follow = true);

  Future<void> _toggleSheet(double peekFraction) async {
    if (!_sheetCtrl.isAttached) return;
    final expanded = _sheetCtrl.size > peekFraction + 0.05;
    await _sheetCtrl.animateTo(
      expanded ? peekFraction : 0.6,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Widget _buildMap(BuildContext context, EvTripMapRenderData d) {
    final builder = widget.mapBuilder;
    if (builder != null) return builder(context, d);
    return EvTripMapView(
      route: d.route,
      corridorStations: d.corridorStations,
      plan: d.plan,
      destinationLat: d.destinationLat,
      destinationLng: d.destinationLng,
      progress: d.progress,
      carLat: d.carLat,
      carLng: d.carLng,
      carHeading: d.carHeading,
      follow: d.follow,
      padding: d.padding,
      onUserGesture: d.onUserGesture,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final fix = _car.fix;
    final peekPx = _peekContentPx + mq.padding.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Scaffold(
        backgroundColor: AppColors.scaffold,
        extendBodyBehindAppBar: true,
        // Юқори соҳада ФАҚАТ орқага тугмаси: сарлавҳа ҳам, амаллар ҳам йўқ.
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          leadingWidth: 64,
          leading: const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Center(child: EvMapBackButton()),
          ),
        ),
        body: LayoutBuilder(
          builder: (context, c) {
            final height = c.maxHeight;
            final peekFraction = (peekPx / height).clamp(0.08, 0.5).toDouble();
            final data = EvTripMapRenderData(
              route: widget.route,
              corridorStations: widget.corridorStations,
              plan: widget.plan,
              destinationLat: widget.destinationLat,
              destinationLng: widget.destinationLng,
              progress: _progress,
              carLat: fix?.lat,
              carLng: fix?.lng,
              carHeading: _car.heading,
              follow: _follow,
              padding: EdgeInsets.only(
                top: mq.padding.top + kToolbarHeight,
                bottom: peekPx,
              ),
              onUserGesture: _onUserGesture,
            );
            final showRecenter = fix != null && _extent < peekFraction + 0.15;

            return Stack(
              fit: StackFit.expand,
              children: [
                _buildMap(context, data),
                if (showRecenter)
                  Positioned(
                    right: 12,
                    bottom: peekPx + 12,
                    child: _RecenterButton(
                      active: _follow,
                      onTap: _recenter,
                    ),
                  ),
                NotificationListener<DraggableScrollableNotification>(
                  onNotification: (n) {
                    if ((n.extent - _extent).abs() > 0.01) {
                      setState(() => _extent = n.extent);
                    }
                    return false;
                  },
                  child: DraggableScrollableSheet(
                    controller: _sheetCtrl,
                    initialChildSize: peekFraction,
                    minChildSize: peekFraction,
                    maxChildSize: _maxSheetFraction,
                    snap: true,
                    snapSizes: [
                      0.6.clamp(peekFraction, _maxSheetFraction).toDouble()
                    ],
                    builder: (context, scroll) => _PlanSheet(
                      plan: widget.plan,
                      scrollController: scroll,
                      onHeaderTap: () => _toggleSheet(peekFraction),
                      expanded: _extent > peekFraction + 0.05,
                      bottomInset: mq.padding.bottom,
                      onOpenNavigator: widget.onOpenNavigator,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// «Машинага қайтиш» — кичик думалоқ тугма (пастки ўнг). Кузатув ёқиқ
/// бўлса бренд рангида.
class _RecenterButton extends StatelessWidget {
  const _RecenterButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color:
            active ? AppColors.primary : Colors.white.withValues(alpha: 0.95),
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Tooltip(
            message: context.tr('ev_trip_recenter'),
            child: Icon(
              active ? Icons.navigation_rounded : Icons.my_location_rounded,
              color: active ? AppColors.onPrimary : AppColors.primaryText,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

/// Пастдан тортиб очиладиган варақа: йиғиқ ҳолатда бир қатор хулоса,
/// очилганда — режанинг БАРЧА тафсилотлари (ўзгаришсиз [EvTripPlanView]).
class _PlanSheet extends StatelessWidget {
  const _PlanSheet({
    required this.plan,
    required this.scrollController,
    required this.onHeaderTap,
    required this.expanded,
    required this.bottomInset,
    required this.onOpenNavigator,
  });

  final EvTripPlan plan;
  final ScrollController scrollController;
  final VoidCallback onHeaderTap;
  final bool expanded;
  final double bottomInset;
  final VoidCallback onOpenNavigator;

  @override
  Widget build(BuildContext context) {
    final gap = plan.status == EvTripPlanStatus.gapTooLarge;
    return Material(
      color: AppColors.scaffold,
      elevation: 10,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        controller: scrollController,
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: const ValueKey('ev_trip_sheet_header'),
              onTap: onHeaderTap,
              child: SizedBox(
                // Pastki tizim paneli (inset) ham peek'ga kiradi - varaqaning
                // yopiq holatida legend/reja ko'rinib qolmasin.
                height: _EvTripMapScreenState._peekContentPx + bottomInset,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.primaryText.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(
                          gap
                              ? Icons.warning_amber_rounded
                              : Icons.ev_station_rounded,
                          size: 22,
                          color: gap
                              ? const Color(0xFFC62828)
                              : AppColors.primaryText,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            EvTripMapScreen.peekText(context, plan),
                            key: const ValueKey('ev_trip_sheet_peek'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onPrimary,
                            ),
                          ),
                        ),
                        Icon(
                          expanded
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.keyboard_arrow_up_rounded,
                          color: AppColors.primaryText,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const _MapLegend(),
            const SizedBox(height: 14),
            EvTripPlanView(plan: plan, onOpenNavigator: onOpenNavigator),
          ],
        ),
      ),
    );
  }
}

/// Харита белгилари изоҳи (аввал инлайн харита тагида эди).
class _MapLegend extends StatelessWidget {
  const _MapLegend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        _dot(const Color(0xFFD32F2F), context.tr('ev_trip_legend_primary')),
        _dot(const Color(0xFFF57C00), context.tr('ev_trip_legend_backup')),
        _dot(const Color(0xFF388E3C), context.tr('ev_trip_legend_other')),
      ],
    );
  }

  Widget _dot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }
}
