import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/map_launcher.dart';
import '../../../models/ev_charging_station.dart';
import '../../../repositories/ev_station_repository.dart';
import '../controllers/ev_car_tracker.dart';
import '../controllers/ev_drive_mode.dart';
import '../controllers/ev_trip_alternatives.dart';
import '../controllers/ev_trip_controller.dart';
import '../controllers/ev_trip_nav_relay.dart';
import '../controllers/ev_route_progress.dart';
import '../controllers/ev_trip_planner.dart';
import '../controllers/ev_trip_selection.dart';
import '../models/ev_trip_plan.dart';
import '../widgets/ev_drive_card.dart';
import '../widgets/ev_map_top_overlay.dart';
import '../widgets/ev_next_stops_card.dart';
import '../widgets/ev_trip_alternatives_sheet.dart';
import '../widgets/ev_trip_map_view.dart';
import '../widgets/ev_trip_dot_icon.dart';
import '../widgets/ev_trip_plan_view.dart';
import '../widgets/ev_trip_station_sheet.dart';
import '../widgets/ev_trip_undo_chip.dart';

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

/// «Банд» хабари: станция бандлигини жамоага юбориш. Ишлаб чиқаришда —
/// [EvStationRepository.setOccupancy] (харита экранидаги станция
/// карточкасидаги ЯГОНА чақирув); тестда сохта.
typedef EvBusyReporter = Future<void> Function(String stationId);

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
    this.controller,
    this.reportBusy,
    this.driveClock,
  });

  /// Yo'l rejimidagi "Банд" tugmasi chaqiradi. Berilmasa -
  /// `EvStationRepository.setOccupancy(id, busy: true)` (Provider orqali).
  final EvBusyReporter? reportBusy;

  /// Test uchun: yo'l rejimi (tezlik gisterezisi) soati. Berilmasa - `DateTime.now`.
  final DateTime Function()? driveClock;

  /// Reja holati (qayta hisob, "Almashtirish", "Qaytarish"). Berilmasa -
  /// ekran ichida [plan]/[corridorStations] dan tarmoqsiz kontroller quriladi.
  /// Berilsa (EvTripScreen) reja o'zgarishi o'sha ekranda ham ko'rinadi.
  final EvTripController? controller;

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
  late final EvTripController _trip;
  late final bool _ownsTrip;
  late EvTripSelection _selection;
  final _sheetCtrl = DraggableScrollableController();

  /// Oxirgi o'zgarishdan oldingi tanlov ("Қайтариш" uchun) va shu o'zgarish
  /// shu ekranda qilinganmi (umumiy kontrollerda oldingi seansdan qolgan
  /// qaytarish holati ko'rsatilmasin).
  EvTripSelection? _undoSelection;
  bool _undoArmed = false;

  /// "Навигация" kamida bir marta muvaffaqiyatli ochilgan: reja o'zgarsa
  /// haydovchiga Google Maps'da yo'lni yangilash eslatiladi.
  bool _navSent = false;

  // ---- Yo'l rejimi ----

  /// Tezlik gisterezisi (sof mantiq: `ev_drive_mode.dart`).
  late final EvDriveModeMachine _drive;

  /// GPS yangi nuqta bermasa (10 m filtr, mashina to'xtadi) "to'xtadi"
  /// holatini aniqlash uchun davriy tekshiruv.
  static const Duration _driveTick = Duration(seconds: 2);
  Timer? _driveTimer;

  /// Tezlik uchun bir nuqta ikki marta hisoblanmasin (ilova fondan qaytganda
  /// `_onCar` o'sha nuqta bilan qayta chaqiriladi).
  EvCarFix? _lastSpeedFix;

  /// Haydovchi "Зарядлаш бошланди" bosgan to'xtashlar: bu to'xtash uchun
  /// yo'l rejimi karточкаси qayta chiqmaydi.
  final Set<String> _ackedStops = <String>{};
  bool _reportingBusy = false;

  /// Yig'iq varaqa nisbati (build'da yangilanadi) - yo'l rejimi boshlanganda
  /// varaqa shunga tushiriladi va yashiriladi.
  double _peekFraction = 0.2;

  /// Yo'l rejimida pastki karточка uchun xarita paddingi (Google logotipi
  /// karточка tagida qolmasin).
  static const double _driveMapPaddingPx = 300;

  EvRouteProgress? _progress;
  int _segmentHint = 0;
  bool _follow = false;
  double _extent = 0;
  bool _launching = false;

  /// Бўлаклаб юбориш ҳолати (Google Maps чекловидан кўп тўхташ бўлса).
  final _relay = EvNavigationRelay();

  /// Режа/станциялар масштабидаги км ≈ маршрут чизиғи км × шу коэффициент
  /// (коридор масофалари Google йўл масофасига масштабланган).
  double _kmScale = 1;

  /// «Кейинги тўхташлар» карточкаси: ҳайдовчи чипни босиб очди / ёпди.
  bool _cardOpen = false;
  bool _cardDismissed = false;

  @override
  void initState() {
    super.initState();
    // Харита статус бар ва пастки соҳа остигача.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.addObserver(this);
    _ownsTrip = widget.controller == null;
    _trip = widget.controller ??
        EvTripController.seeded(
          plan: widget.plan,
          route: widget.route,
          corridor: widget.corridorStations,
          routeMinutes: widget.routeMinutes,
          destinationLat: widget.destinationLat,
          destinationLng: widget.destinationLng,
        );
    // Бошланғич танлов — тавсия этилган (асосий) тўхташлар; чеклов
    // платформага қараб (мобил веб 3, бошқа 9) - ЯГОНА манба.
    _selection = EvTripSelection.recommended(
      _plan,
      _trip.corridorStations,
      maxWaypoints: widget.maxWaypoints ?? mapsMaxWaypoints(),
    )..addListener(_onSelection);
    _drive = EvDriveModeMachine(clock: widget.driveClock);
    _driveTimer = Timer.periodic(_driveTick, (_) {
      if (mounted && _drive.tick()) setState(() {});
    });
    _car = EvCarTracker(
      source: widget.locationSource ?? const GeolocatorCarLocationSource(),
    )..addListener(_onCar);
    _car.start();
    _kmScale = _routeKmScale(widget.plan.totalKm, widget.route);
  }

  @override
  void dispose() {
    _driveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _car
      ..removeListener(_onCar)
      ..dispose();
    _selection
      ..removeListener(_onSelection)
      ..dispose();
    _undoSelection?.dispose();
    if (_ownsTrip) _trip.dispose();
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
      // Ҳайдовчи Google Maps'да юрган бўлиши мумкин: қайтганда ҳолат
      // (машина охирги юборилган тўхташдан ўтдими) қайта баҳоланади.
      _car.resume().then((_) {
        if (mounted) _onCar();
      });
      if (mounted) setState(() {});
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
    final wasDriving = _drive.driving;
    if (fix == null) {
      // GPS yo'q (ruxsat/o'chiq): yo'l rejimi ko'rsatilmaydi.
      if (_car.unavailable) _drive.reset();
    } else if (!identical(fix, _lastSpeedFix)) {
      _lastSpeedFix = fix;
      _drive.onFix(fix.speedMps);
    }
    if (!wasDriving && _drive.driving) _collapseSheet();
    setState(() => _progress = progress);
  }

  /// Yo'l rejimi boshlanganda og'ir reja varaqasi yig'iladi (keyin yashiriladi;
  /// to'xtaganda shu holatda qaytadi).
  void _collapseSheet() {
    if (_sheetCtrl.isAttached) {
      _sheetCtrl.jumpTo(_peekFraction);
    }
    _extent = _peekFraction;
  }

  void _toggleDriveMode() {
    final was = _drive.driving;
    _drive.toggleManual();
    if (!was && _drive.driving) _collapseSheet();
    setState(() {});
  }

  /// "Банд": станция бандлигини жамоага хабар қилиш (30 дақиқа амал қилади).
  /// Интернет йўқ/хато — дўстона хабар, илова қотмайди.
  Future<void> _reportBusy(EvChargingStation station) async {
    if (_reportingBusy) return;
    setState(() => _reportingBusy = true);
    try {
      final report = widget.reportBusy ??
          (String id) =>
              context.read<EvStationRepository>().setOccupancy(id, busy: true);
      await report(station.id);
      if (!mounted) return;
      _toast(context.tr('ev_occupancy_saved'));
    } catch (_) {
      if (!mounted) return;
      _toast(context.tr('ev_drive_busy_failed'));
    } finally {
      if (mounted) setState(() => _reportingBusy = false);
    }
  }

  /// "Зарядлаш бошланди": шу тўхташ учун карточка яширилади (бетараф тасдиқ,
  /// ҳеч нарса сақланмайди).
  void _confirmCharging(EvTripStop stop) {
    setState(() => _ackedStops.add(stop.station.id));
  }

  void _onSelection() {
    if (mounted) setState(() {});
  }

  /// Joriy reja: kontrollerdagi (almashtirish/qayta hisobdan keyin), yo'q
  /// bo'lsa - ekranga berilgan dastlabki reja.
  EvTripPlan get _plan => _trip.plan ?? widget.plan;

  /// Stansiyani almashtirish va qayta hisob: mashina ma'lum, reja boshlang'ich
  /// shartlari ma'lum.
  bool get _canReplace => widget.car != null && _plan.canReplan;

  /// Stansiya varag'ida "Almashtirish" ko'rsatiladigan reja to'xtashining
  /// indeksi (rejadagi to'xtash emas - `-1`).
  int _stopIndexOf(String stationId) =>
      _plan.stops.indexWhere((s) => s.station.id == stationId);

  /// Станция маркери босилди: ихчам варақа (тавсия/заҳира белгиси, масофа,
  /// зарядлаш маълумоти, қўшиш/олиб ташлаш).
  void _onStationTap(String id) {
    final candidate = _selection.candidateById(id);
    if (candidate == null || !mounted) return;
    final stopIndex = _stopIndexOf(id);
    EvTripStationSheet.show(
      context,
      selection: _selection,
      candidate: candidate,
      onReplace: _canReplace && stopIndex >= 0
          ? () => _openAlternatives(stopIndex)
          : null,
    );
  }

  // ---- Almashtirish (haydovchi qarori) va "Qaytarish" ----

  /// [stopIndex]-to'xtash uchun alternativalar varag'i. Tanlansa - stansiya
  /// almashtiriladi va reja qayta hisoblanadi. [large] - yo'lda: katta tugmalar.
  Future<void> _openAlternatives(int stopIndex, {bool large = false}) async {
    final car = widget.car;
    final plan = _plan;
    if (car == null || !plan.canReplan) return;
    if (stopIndex < 0 || stopIndex >= plan.stops.length) return;
    final rows = EvTripAlternatives.build(
      plan: plan,
      stopIndex: stopIndex,
      corridor: _trip.corridorStations,
      car: car,
      excludedStationIds: _trip.excludedStationIds,
      pinnedStationIds: _trip.pinnedStationIds,
      carAlongKm: _carAlongKm,
    );
    final picked = await EvTripAlternativesSheet.show(context,
        alternatives: rows, large: large);
    if (picked == null || !mounted) return;
    _replaceStop(stopIndex, picked.station.id);
  }

  void _replaceStop(int stopIndex, String newStationId) {
    final car = widget.car;
    if (car == null) return;
    final oldPlan = _plan;
    final oldSelection = _selection;
    if (stopIndex < 0 || stopIndex >= oldPlan.stops.length) return;
    final oldId = oldPlan.stops[stopIndex].station.id;

    final result = _trip.replaceStop(
        stopIndex: stopIndex, newStationId: newStationId, car: car);
    if (result == EvReplaceResult.unavailable) {
      _toast(context.tr('ev_replace_failed'));
      return;
    }
    _planChanged(
      previousPlan: oldPlan,
      previousSelection: oldSelection,
      replacedOldId: oldId,
      replacedNewId: newStationId,
    );
  }

  /// Reja o'zgardi (almashtirish yoki qayta hisob): tanlov yangi rejaga
  /// ergashadi, Google Maps'ga yuborish holati yangi tanlovdan qayta
  /// hisoblanadi, "Qaytarish" yoqiladi.
  void _planChanged({
    required EvTripPlan previousPlan,
    required EvTripSelection previousSelection,
    String? replacedOldId,
    String? replacedNewId,
  }) {
    final next = EvTripSelection.followPlan(
      previous: previousSelection,
      previousPlan: previousPlan,
      nextPlan: _plan,
      corridor: _trip.corridorStations,
      replacedOldId: replacedOldId,
      replacedNewId: replacedNewId,
    );
    previousSelection.removeListener(_onSelection);
    if (!identical(_undoSelection, previousSelection)) {
      _undoSelection?.dispose();
    }
    _undoSelection = previousSelection;
    _selection = next..addListener(_onSelection);

    // Google Maps'ga yuborilgan marshrut eskirdi: bo'laklab yuborish
    // holati yangi tanlovdan qayta boshlanadi.
    final hadNav = _navSent;
    _relay.reset();
    _cardOpen = false;
    _cardDismissed = false;
    _undoArmed = true;
    setState(() {});
    if (hadNav) _toast(context.tr('ev_replan_nav_hint'));
  }

  /// "Қайтариш": reja ham, tanlov ham o'zgarishdan oldingi holatga qaytadi.
  void _undoChange() {
    if (!_undoArmed || !_trip.undo()) return;
    final restored = _undoSelection;
    _undoSelection = null;
    if (restored != null) {
      _selection
        ..removeListener(_onSelection)
        ..dispose();
      _selection = restored..addListener(_onSelection);
    }
    _relay.reset();
    _cardOpen = false;
    _cardDismissed = false;
    _undoArmed = false;
    setState(() {});
  }

  void _dismissUndo() {
    _undoArmed = false;
    _undoSelection?.dispose();
    _undoSelection = null;
    _trip.discardUndo();
    setState(() {});
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
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
      (_plan.isOk || widget.route.isNotEmpty);

  /// Йўл бошидан машинанинг масофаси (км, режа масштабида); GPS йўқ ёки
  /// машина йўлда эмас — `null`.
  double? get _carAlongKm {
    final p = _progress;
    if (p == null || !p.isOnRoute) return null;
    return p.alongKm * _kmScale;
  }

  /// Машина ортида қолган станцияларни (шунча км дан кўпроқ) навигацияга
  /// қўшмаймиз: улар аллақачон ўтилган.
  static const double _behindToleranceKm = 0.5;

  List<EvTripCandidate> _ahead(List<EvTripCandidate> list) {
    final along = _carAlongKm;
    if (along == null) return list;
    return [
      for (final c in list)
        if (c.alongKm >= along - _behindToleranceKm) c,
    ];
  }

  /// Бошланғич нуқта: ҳозирги GPS, йўқ бўлса режа ҳисобланган нуқта.
  ({double lat, double lng}) get _origin {
    final fix = _car.fix;
    if (fix != null && fix.lat.isFinite && fix.lng.isFinite) {
      return (lat: fix.lat, lng: fix.lng);
    }
    return (lat: widget.originLat, lng: widget.originLng);
  }

  /// Ҳали Google Maps'га юборилмаган тўхташлар (йўл бўйича).
  List<EvTripCandidate> get _pending => _relay.active
      ? _ahead(_relay.pending(_selection.navigable))
      : const <EvTripCandidate>[];

  Future<bool> _open(List<EvTripCandidate> stops) async {
    final o = _origin;
    _launching = true;
    try {
      return await widget.routeLauncher(
        originLat: o.lat,
        originLng: o.lng,
        destinationLat: widget.destinationLat,
        destinationLng: widget.destinationLng,
        stops: evWaypointsOf(stops),
      );
    } catch (_) {
      return false;
    } finally {
      _launching = false;
    }
  }

  void _openFailedNotice() {
    // Аввалги хабар (мас. «N та тўхташ юборилди») навбатда ушлаб қолмасин.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.tr('maps_open_failed'))));
  }

  /// Блокламайдиган хабар: Google Maps'га нечта тўхташ юборилди.
  void _sentNotice(String key, int n) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const ValueKey('ev_trip_nav_notice'),
        duration: const Duration(seconds: 8),
        content: Text(context.tr(key).replaceAll('{n}', '$n')),
      ));
  }

  /// «Навигация»: Google Maps БУТУН маршрут учун бир марта очилади — манзил
  /// ҲАМИША охирги манзил, оралиқ нуқталар = ҲАЙДОВЧИ ТАНЛАГАН станциялар
  /// (йўл бўйича тартибда). Ҳеч нарса танланмаган бўлса — фақат манзилга.
  ///
  /// Google Maps'да оралиқ нуқталар сони чекланган (`mapsMaxWaypoints()`):
  /// танланганлар чекловдан кўп бўлса навигация БЛОКЛАНМАЙДИ — биринчи
  /// `limit` та (йўл бўйича энг яқинлари) юборилади, қолгани «кейинги
  /// тўхташлар» бўлиб сақланади ва машина охирги юборилганидан ўтгач
  /// «Давом этиш» таклиф қилинади ([_continueNavigation]).
  Future<void> _navigate() async {
    if (_launching || !_canNavigate) return;
    final chunk =
        evNavigationChunk(_ahead(_selection.navigable), _selection.maxWaypoints);
    final opened = await _open(chunk.sent);
    if (!mounted) return;
    if (!opened) {
      _openFailedNotice();
      return;
    }
    // Янги навигация — бўлаклаш қайтадан бошланади.
    _navSent = true;
    _relay.reset();
    _cardOpen = false;
    _cardDismissed = false;
    if (chunk.remaining.isNotEmpty) {
      _relay.markSent(chunk.sent);
      _sentNotice('ev_trip_nav_sent_first', chunk.sent.length);
    }
    setState(() {});
  }

  /// «Давом этиш»: ҳозирги GPS (йўқ бўлса — дастлабки нуқта) дан охирги
  /// манзилгача, навбатдаги `limit` та тўхташ билан Google Maps қайта
  /// очилади. Қолгани қолмагунча такрорланади.
  Future<void> _continueNavigation() async {
    if (_launching || !_canNavigate) return;
    final pending = _pending;
    if (pending.isEmpty) {
      setState(() {});
      return;
    }
    final chunk = evNavigationChunk(pending, _selection.maxWaypoints);
    final opened = await _open(chunk.sent);
    if (!mounted) return;
    if (!opened) {
      _openFailedNotice();
      return;
    }
    _relay.markSent(chunk.sent);
    _cardOpen = false;
    _cardDismissed = false;
    if (chunk.remaining.isEmpty) {
      _relay.reset();
      _sentNotice('ev_trip_nav_sent_last', chunk.sent.length);
    } else {
      _sentNotice('ev_trip_nav_sent_next', chunk.sent.length);
    }
    setState(() {});
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
    final plan = _plan;
    final peekPx = peekContentHeight(
            showTime: showsPeekTime(plan, widget.routeMinutes)) +
        mq.padding.bottom;

    // Yo'l rejimi: GPS bor va mashina marshrutda. Rejim tezlikdan (yoki qo'lda
    // chip bilan) yoqiladi; stansiyaga yetganda to'xtab qolsa ham "Yetib
    // keldingiz" holati ko'rinib turadi.
    final carAlong = _carAlongKm;
    EvDriveTarget? driveTarget;
    if (fix != null && carAlong != null) {
      driveTarget = EvDriveNext.next(
        plan: plan,
        carAlongKm: carAlong,
        carLat: fix.lat,
        carLng: fix.lng,
        acknowledgedIds: _ackedStops,
      );
    }
    final driveAvailable = fix != null && carAlong != null;
    final driveMode =
        driveAvailable && (_drive.driving || (driveTarget?.arrived ?? false));
    final showDriveCard = driveMode && driveTarget != null;

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
          // «Йўл режими» чипи — фақат GPS бор ва машина маршрутда бўлса
          // (бошқа вақтда юқори соҳада фақат орқага тугмаси).
          actions: driveAvailable
              ? [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Center(
                      child: _DriveModeChip(
                        active: _drive.driving,
                        onTap: _toggleDriveMode,
                      ),
                    ),
                  ),
                ]
              : null,
        ),
        body: LayoutBuilder(
          builder: (context, c) {
            final height = c.maxHeight;
            final peekFraction = (peekPx / height).clamp(0.08, 0.5).toDouble();
            _peekFraction = peekFraction;
            final data = EvTripMapRenderData(
              route: widget.route,
              corridorStations: _trip.corridorStations,
              plan: plan,
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
                bottom: driveMode
                    ? _driveMapPaddingPx + mq.padding.bottom
                    : peekPx + _navGap + _navHeight + 8,
              ),
              onUserGesture: _onUserGesture,
            );
            final showRecenter = fix != null && _extent < peekFraction + 0.15;
            // «Кейинги тўхташлар»: чип ҳар доим; катта карточка — машина
            // юборилган охирги тўхташдан ўтгач ёки ҳайдовчи чипни босса.
            final pending = _pending;
            final showUndo = _undoArmed && _trip.canUndo;
            final showCard = pending.isNotEmpty &&
                (_cardOpen ||
                    (!_cardDismissed && _relay.hasPassedLastSent(_carAlongKm)));
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
                // Йўл режимида оғир режа варақаси яширилади (ҳолати сақланади,
                // тўхтаганда қайтади).
                Offstage(
                  offstage: driveMode,
                  child: NotificationListener<DraggableScrollableNotification>(
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
                        plan: plan,
                        onReplaceStop: _canReplace ? _openAlternatives : null,
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
                ),
                if (driveMode)
                  // Йўл режими: пастда [қайтиш тугмаси] + карточка + катта
                  // «Навигация» (тугма ўз жойида қолади).
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: mq.padding.bottom + _navGap,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showRecenter)
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: _RecenterButton(
                              active: _follow,
                              onTap: _recenter,
                            ),
                          ),
                        if (showRecenter) const SizedBox(height: 8),
                        if (showDriveCard)
                          EvDriveCard(
                            target: driveTarget!,
                            busyInFlight: _reportingBusy,
                            onBusy: () => _reportBusy(driveTarget!.stop.station),
                            onAlternatives: _canReplace
                                ? () => _openAlternatives(
                                      driveTarget!.stopIndex,
                                      large: true,
                                    )
                                : null,
                            onConfirmCharging: () =>
                                _confirmCharging(driveTarget!.stop),
                          ),
                        if (showDriveCard) const SizedBox(height: _navGap),
                        SizedBox(
                          height: _navHeight,
                          child: _NavigateButton(
                            enabled: _canNavigate,
                            count: _selection.count,
                            onTap: _navigate,
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
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
                if (pending.isNotEmpty || showUndo)
                  Positioned(
                    top: mq.padding.top + kToolbarHeight + 4,
                    left: 12,
                    right: 12,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showUndo)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: EvTripUndoChip(
                              onUndo: _undoChange,
                              onClose: _dismissUndo,
                            ),
                          ),
                        if (showUndo && pending.isNotEmpty)
                          const SizedBox(height: 8),
                        if (pending.isNotEmpty)
                          showCard
                              ? EvNextStopsCard(
                                  count: pending.length,
                                  busy: _launching,
                                  onContinue: _continueNavigation,
                                  onClose: () => setState(() {
                                    _cardOpen = false;
                                    _cardDismissed = true;
                                  }),
                                )
                              : Align(
                                  alignment: Alignment.centerRight,
                                  child: EvNextStopsChip(
                                    count: pending.length,
                                    onTap: () => setState(() {
                                      _cardOpen = true;
                                      _cardDismissed = false;
                                    }),
                                  ),
                                ),
                      ],
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

/// Режа/станциялар км (Google йўл масофаси) ва маршрут чизиғининг геометрик
/// км нисбати. Иккаласи ҳам маълум ва мантиқий бўлмаса — 1.
@visibleForTesting
double evRouteKmScale(double planTotalKm, List<EvRoutePoint> route) =>
    _routeKmScale(planTotalKm, route);

double _routeKmScale(double planTotalKm, List<EvRoutePoint> route) {
  if (!(planTotalKm > 0) || route.length < 2) return 1;
  final geometry = EvTripPlanner.routeLengthKm(route);
  if (!(geometry > 0)) return 1;
  final scale = planTotalKm / geometry;
  return (scale >= 0.5 && scale <= 2) ? scale : 1;
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

/// «Йўл режими» чипи (юқори ўнг): тезликдан автоматик ёқилади, лекин
/// ҳайдовчи қўлда ёқиши/ўчириши ҳам мумкин. Ёқиқ — бренд рангида.
class _DriveModeChip extends StatelessWidget {
  const _DriveModeChip({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppColors.onPrimary : AppColors.primaryText;
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        key: const ValueKey('ev_trip_drive_chip'),
        color: active ? AppColors.primary : Colors.white.withValues(alpha: 0.95),
        elevation: 4,
        shape: const StadiumBorder(
          side: BorderSide(color: AppColors.primaryDark, width: 1.4),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions_car_rounded, size: 20, color: fg),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      context.tr('ev_drive_mode'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: fg,
                      ),
                    ),
                  ),
                ],
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
    this.onReplaceStop,
  });

  final EvTripPlan plan;

  /// To'xtash kartochkasidagi "Almashtirish" (null - tugma yo'q).
  final ValueChanged<int>? onReplaceStop;
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
              onReplaceStop: onReplaceStop,
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
