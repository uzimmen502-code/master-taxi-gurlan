import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/map_launcher.dart';
import '../controllers/ev_car_tracker.dart';
import '../controllers/ev_route_progress.dart';
import '../controllers/ev_trip_planner.dart';
import '../controllers/ev_trip_selection.dart';
import '../models/ev_trip_plan.dart';
import '../widgets/ev_map_top_overlay.dart';
import '../widgets/ev_trip_map_view.dart';
import '../widgets/ev_trip_dot_icon.dart';
import '../widgets/ev_trip_plan_view.dart';
import '../widgets/ev_trip_station_sheet.dart';

/// Харитага узатиладиган ҳолат — `GoogleMap` платформа кўринишисиз
/// тестлаш учун харита ташқаридан қурилади ([EvTripMapBuilder]).
class EvTripMapRenderData {
  const EvTripMapRenderData({
    required this.route,
    required this.corridorStations,
    required this.plan,
    required this.candidates,
    required this.selectedNumbers,
    required this.onStationTap,
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

  /// Йўл бўйидаги барча станциялар (ҳаммаси чизилади) ва ҳайдовчи
  /// танлаганларининг тартиб рақамлари (id → 1, 2, ...).
  final List<EvTripCandidate> candidates;
  final Map<String, int> selectedNumbers;

  /// Станция маркери босилди (id) — станция варағи очилади.
  final ValueChanged<String> onStationTap;
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

/// Ташқи навигация иловасини очувчи — ишлаб чиқаришда
/// [openMapsEvTripRoute]; тестда сохта функция.
typedef EvRouteLauncher = Future<bool> Function({
  required double originLat,
  required double originLng,
  required double destinationLat,
  required double destinationLng,
  List<EvWaypoint> stops,
});

/// ⚡ Сафар режаси ҳисобланганидан кейин очиладиган ТЎЛИҚ ЭКРАНЛИ жонли
/// харита (эга қарори, 2026-10-16):
///  * харита бутун экранда (статус бар ва пастки соҳа остигача); юқорида
///    фақат думалоқ «орқага» тугмаси;
///  * маршрут, рақамланган тўхташлар, заҳиралар, йўл бўйидаги бошқа
///    станциялар, манзил — ва жонли машина маркери (GPS оқими);
///  * босиб ўтилган қисм хира, қолгани маршрут рангида;
///  * режанинг барча тафсилотлари ([EvTripPlanView]) — пастдан тортиб
///    очиладиган варақада (йиғиқ ҳолатда бир қатор хулоса);
///  * йўл бўйидаги БАРЧА станциялар кўринади; ҳар бири босилса станция
///    варағи очилади ва ҳайдовчи уни тўхташ режасига қўшади/олиб ташлайди
///    ([EvTripSelection]) — илова фақат тавсия қилади. «Навигация» Google
///    Maps'ни ҳайдовчи танлаган тўхташлар билан очади.
class EvTripMapScreen extends StatefulWidget {
  const EvTripMapScreen({
    super.key,
    required this.plan,
    required this.route,
    required this.corridorStations,
    required this.originLat,
    required this.originLng,
    required this.destinationLat,
    required this.destinationLng,
    required this.onOpenNavigator,
    this.locationSource,
    this.mapBuilder,
    this.routeLauncher = openMapsEvTripRoute,
    this.maxWaypoints,
    this.routeMinutes = 0,
    this.car,
  });

  final EvTripPlan plan;
  final List<EvRoutePoint> route;
  final List<EvCorridorStation> corridorStations;

  /// Режа ҳисобланган бошланиш нуқтаси (ҳозирги GPS).
  final double originLat;
  final double originLng;
  final double destinationLat;
  final double destinationLng;
  final VoidCallback onOpenNavigator;

  /// Google маршрутидаги жами йўл вақти (дақиқа); 0 — номаълум.
  final int routeMinutes;

  /// Режа тузилган автомобил (энергия ва «камида» зарядлаш вақти учун).
  final EvCarSpec? car;

  /// Харитадаги катта «Навигация» тугмаси чақирадиган очувчи. Бўлмаса —
  /// [openMapsEvTripRoute] (Google Maps → Яндекс → `geo:`).
  final EvRouteLauncher routeLauncher;

  /// Тест учун: оралиқ нуқталар чеклови. Бўлмаса — `mapsMaxWaypoints()`
  /// (мобил веб 3, бошқа 9).
  final int? maxWaypoints;

  /// Тест учун: GPS манбаси. Бўлмаса — қурилма GPS'и.
  final EvCarLocationSource? locationSource;

  /// Тест учун: харита. Бўлмаса — [EvTripMapView] (`GoogleMap`).
  final EvTripMapBuilder? mapBuilder;

  /// Йиғиқ варақадаги бир қатор хулоса: «N марта зарядлаш керак · X км».
  /// Йўл вақти ([routeMinutes]) алоҳида қаторда чиқади — катта шрифтда (1.3)
  /// бир қаторга қўшилса икки қаторга сиғмай қолар эди.
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
  /// Варақанинг йиғиқ (peek) баландлиги: тутқич + хулоса (катта шрифтда
  /// икки қатор).
  static const double _peekContentPx = 100;

  /// Йўл вақти қатори қўшилганда йиғиқ варақа шунча баландроқ (катта
  /// шрифтда хулоса 2 қатор + вақт сиғиши учун).
  static const double _peekTimeExtraPx = 16;

  /// Йиғиқ варақа мазмуни баландлиги: вақт қатори бор-йўқлигига қараб.
  static double peekContentHeight({required bool showTime}) =>
      _peekContentPx + (showTime ? _peekTimeExtraPx : 0);

  /// Йўл вақти қатори кўрсатиладими (узилишда йўқ).
  static bool showsPeekTime(EvTripPlan plan, int routeMinutes) =>
      routeMinutes > 0 && plan.status != EvTripPlanStatus.gapTooLarge;
  static const double _maxSheetFraction = 0.88;

  /// Катта «Навигация» тугмаси: баландлиги ва варақа/экран четидан бўшлиқ.
  static const double _navHeight = 56;
  static const double _navGap = 12;

  /// Варақа очилганда тугма пастга "ёпишади" — варақа мазмуни унинг
  /// тагида қолиб кетмаслиги учун охирига қўшимча жой.
  static const double _navReserve = _navHeight + 2 * _navGap;

  /// Машина "орқага сакрамаслиги" учун: охирги сегментдан шунча олдинга
  /// қайтишга рухсат (GPS шовқини).
  static const int _segmentBacktrack = 3;

  late final EvCarTracker _car;
  late final EvTripSelection _selection;
  final _sheetCtrl = DraggableScrollableController();

  EvRouteProgress? _progress;
  int _segmentHint = 0;
  bool _follow = false;
  double _extent = 0;
  bool _launching = false;

  @override
  void initState() {
    super.initState();
    // Харита статус бар ва пастки соҳа остигача.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.addObserver(this);
    // Бошланғич танлов — тавсия этилган (асосий) тўхташлар; чеклов
    // платформага қараб (мобил веб 3, бошқа 9) - ЯГОНА манба.
    _selection = EvTripSelection.recommended(
      widget.plan,
      widget.corridorStations,
      maxWaypoints: widget.maxWaypoints ?? mapsMaxWaypoints(),
    )..addListener(_onSelection);
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
    _selection
      ..removeListener(_onSelection)
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

  void _onSelection() {
    if (mounted) setState(() {});
  }

  /// Станция маркери босилди: ихчам варақа (тавсия/заҳира белгиси, масофа,
  /// зарядлаш маълумоти, қўшиш/олиб ташлаш).
  void _onStationTap(String id) {
    final candidate = _selection.candidateById(id);
    if (candidate == null || !mounted) return;
    EvTripStationSheet.show(context,
        selection: _selection, candidate: candidate);
  }

  void _onUserGesture() {
    if (_follow) setState(() => _follow = false);
  }

  void _recenter() => setState(() => _follow = true);

  /// Тугма ишлайди: манзил координатаси чекли ва (режа тайёр ёки маршрут
  /// чизиғи бор). Акс ҳолда тугма кулранг ва босилмайди.
  bool get _canNavigate =>
      widget.destinationLat.isFinite &&
      widget.destinationLng.isFinite &&
      widget.originLat.isFinite &&
      widget.originLng.isFinite &&
      (widget.plan.isOk || widget.route.isNotEmpty);

  /// «Навигация»: Google Maps'да бошидан охиригача йўл, оралиқ нуқталар =
  /// ҲАЙДОВЧИ ТАНЛАГАН станциялар (йўл бўйича тартибда). Ҳеч нарса
  /// танланмаган бўлса — фақат манзилга. Google Maps'да ҳар оралиқ нуқта
  /// мажбурий тўхташ ва сони чекланган: танланганлар чекловдан кўп бўлса,
  /// илова ўзбошимчалик билан қирқмайди — дўстона хабар чиқади ва
  /// ҳайдовчи камайтиргунча ҳеч нарса очилмайди.
  Future<void> _navigate() async {
    if (_launching || !_canNavigate) return;
    if (_selection.isOverLimit) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          key: const ValueKey('ev_trip_over_limit_message'),
          duration: const Duration(seconds: 6),
          content: Text(context
              .tr('ev_trip_sel_over_limit')
              .replaceAll('{n}', '${_selection.maxWaypoints}')
              .replaceAll('{c}', '${_selection.count}')),
        ));
      return;
    }
    _launching = true;
    var opened = false;
    try {
      opened = await widget.routeLauncher(
        originLat: widget.originLat,
        originLng: widget.originLng,
        destinationLat: widget.destinationLat,
        destinationLng: widget.destinationLng,
        stops: _selection.waypoints,
      );
    } catch (_) {
      opened = false;
    } finally {
      _launching = false;
    }
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.tr('maps_open_failed'))));
  }

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
      candidates: d.candidates,
      selectedNumbers: d.selectedNumbers,
      onStationTap: d.onStationTap,
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
    final peekPx = peekContentHeight(
            showTime: showsPeekTime(widget.plan, widget.routeMinutes)) +
        mq.padding.bottom;

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
              candidates: _selection.candidates,
              selectedNumbers: _selection.numbers,
              onStationTap: _onStationTap,
              destinationLat: widget.destinationLat,
              destinationLng: widget.destinationLng,
              progress: _progress,
              carLat: fix?.lat,
              carLng: fix?.lng,
              carHeading: _car.heading,
              follow: _follow,
              padding: EdgeInsets.only(
                top: mq.padding.top + kToolbarHeight,
                // Варақа + «Навигация» тугмаси: Google логотипи ва маршрут
                // тугма остида қолмасин.
                bottom: peekPx + _navGap + _navHeight + 8,
              ),
              onUserGesture: _onUserGesture,
            );
            final showRecenter = fix != null && _extent < peekFraction + 0.15;
            final navBottom = navButtonBottom(
              screenHeight: height,
              sheetFraction: math.max(_extent, peekFraction),
              topLimit: mq.padding.top + kToolbarHeight + 8,
              bottomInset: mq.padding.bottom,
            );

            return Stack(
              fit: StackFit.expand,
              children: [
                _buildMap(context, data),
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
                      routeMinutes: widget.routeMinutes,
                      car: widget.car,
                    ),
                  ),
                ),
                // Катта «Навигация» тугмаси варақанинг УСТИДА (Stack'да
                // охирида) — ҳар доим кўринади ва босилади.
                if (showRecenter)
                  Positioned(
                    right: 12,
                    bottom: navBottom + _navHeight + _navGap,
                    child: _RecenterButton(
                      active: _follow,
                      onTap: _recenter,
                    ),
                  ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: navBottom,
                  height: _navHeight,
                  child: _NavigateButton(
                    enabled: _canNavigate,
                    count: _selection.count,
                    onTap: _navigate,
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

/// «Навигация» тугмасининг экран тагидан масофаси (пикселда).
///
/// Тугма варақанинг юқори чеккасидан [_EvTripMapScreenState._navGap] юқорида
/// туради ва варақа билан бирга кўтарилади. Варақа шу қадар баланд
/// кўтарилсаки, тугма тулбар остидаги [topLimit]дан юқорига чиқиб кетадиган
/// бўлса — тугма экраннинг ПАСТИДА (хавфсиз соҳа устида) қотади ва варақа
/// устида туради; шунда у ҳеч қачон экрандан чиқиб кетмайди.
@visibleForTesting
double navButtonBottom({
  required double screenHeight,
  required double sheetFraction,
  required double topLimit,
  required double bottomInset,
}) {
  const h = _EvTripMapScreenState._navHeight;
  const gap = _EvTripMapScreenState._navGap;
  final follow = sheetFraction * screenHeight + gap;
  final maxBottom = screenHeight - topLimit - h;
  if (follow <= maxBottom) return follow;
  return bottomInset + gap;
}

/// Катта «Навигация» тугмаси: бренд ранги (primaryDark), матн/иконка
/// onPrimary, 56 dp. Ишламаса — кулранг, босилмайди. Танланган тўхташлар
/// бор бўлса сони ёнида: «Навигация · 3» (катта шрифтда FittedBox кичрайтиради).
class _NavigateButton extends StatelessWidget {
  const _NavigateButton({
    required this.enabled,
    required this.count,
    required this.onTap,
  });

  final bool enabled;
  final int count;
  final VoidCallback onTap;

  static const _disabledBg = Color(0xFFBDBDBD);
  static const _disabledFg = Color(0xFF616161);

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? AppColors.onPrimary : _disabledFg;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        key: const ValueKey('ev_trip_navigate_button'),
        color: enabled ? AppColors.primaryDark : _disabledBg,
        elevation: enabled ? 6 : 2,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.navigation_rounded, color: fg, size: 28),
                    const SizedBox(width: 10),
                    Text(
                      count > 0
                          ? '${context.tr('ev_trip_navigate')} · $count'
                          : context.tr('ev_trip_navigate'),
                      key: const ValueKey('ev_trip_navigate_label'),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
    required this.routeMinutes,
    required this.car,
  });

  final EvTripPlan plan;
  final ScrollController scrollController;
  final VoidCallback onHeaderTap;
  final bool expanded;
  final double bottomInset;
  final VoidCallback onOpenNavigator;
  final int routeMinutes;
  final EvCarSpec? car;

  @override
  Widget build(BuildContext context) {
    final gap = plan.status == EvTripPlanStatus.gapTooLarge;
    final showTime = _EvTripMapScreenState.showsPeekTime(plan, routeMinutes);
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
        padding: EdgeInsets.fromLTRB(
            16, 0, 16, 16 + bottomInset + _EvTripMapScreenState._navReserve),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: const ValueKey('ev_trip_sheet_header'),
              onTap: onHeaderTap,
              child: SizedBox(
                // Pastki tizim paneli (inset) ham peek'ga kiradi - varaqaning
                // yopiq holatida legend/reja ko'rinib qolmasin.
                height: _EvTripMapScreenState.peekContentHeight(
                        showTime: showTime) +
                    bottomInset,
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
                    // Йўл вақти қатори қўшилса — икки қатор хулоса + вақт
                    // сиғиши учун бўшлиқ камроқ.
                    SizedBox(height: showTime ? 8 : 14),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                EvTripMapScreen.peekText(context, plan),
                                key: const ValueKey('ev_trip_sheet_peek'),
                                // Катта шрифтда (1.3) қирқилмайди: икки
                                // қаторга ўтади, йиғиқ варақа шунга етарли
                                // баланд.
                                maxLines: 2,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onPrimary,
                                ),
                              ),
                              if (showTime)
                                Text(
                                  '${context.tr('ev_trip_drive_time')}: '
                                  '${evTripDurationText(context, routeMinutes)}',
                                  key: const ValueKey('ev_trip_sheet_peek_time'),
                                  maxLines: 2,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primaryText,
                                  ),
                                ),
                            ],
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
            EvTripPlanView(
              plan: plan,
              onOpenNavigator: onOpenNavigator,
              routeMinutes: routeMinutes,
              car: car,
            ),
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
        // Харитадаги хира нуқта билан бир хил нейтрал ранг.
        _dot(EvTripDotIcon.color, context.tr('ev_trip_legend_other')),
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
        // Катта шрифтда (1.3) узун изоҳ қаторга сиғмаса — кейинги қаторга
        // ўтади, ўнгга чиқиб кетмайди.
        Flexible(
          child: Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ),
      ],
    );
  }
}
