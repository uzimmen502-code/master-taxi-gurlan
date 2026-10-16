import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/ev_route_progress.dart';
import '../controllers/ev_trip_planner.dart';
import '../models/ev_trip_plan.dart';
import 'ev_car_marker_icon.dart';

/// Харитадаги маркер тури.
enum EvTripMarkerKind {
  /// Режадаги асосий тўхташ — рақами билан.
  primary,

  /// Заҳира вариант.
  backup,

  /// Маршрут бўйидаги бошқа станция — режага кирмаган, лекин ҳайдовчи
  /// кўриб турсин (хотиржамлик учун).
  other,
}

/// ⚡ Сафар харитасининг ТОЗА ҳисоблари — виджетдан ажратилган, шунинг
/// учун `GoogleMap` платформа кўриниши керак бўлмайди ва тестланади.
class EvTripMapGeometry {
  const EvTripMapGeometry._();

  /// Маршрут чизиғини тўлиқ қамраб олувчи тўртбурчак.
  static LatLngBounds? boundsFor(List<EvRoutePoint> route) {
    if (route.isEmpty) return null;
    var minLat = route.first.lat;
    var maxLat = route.first.lat;
    var minLng = route.first.lng;
    var maxLng = route.first.lng;
    for (final p in route) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lng < minLng) minLng = p.lng;
      if (p.lng > maxLng) maxLng = p.lng;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  /// Чизиқни чизиш учун бўлаклар: босиб ўтилган (хира) ва қолган қисм.
  /// Машина йўлда эмас ([EvRouteProgress.isOnRoute]) ёки маълум эмас —
  /// хиралаштириш йўқ: бутун маршрут одатдаги рангда.
  static ({List<EvRoutePoint>? passed, List<EvRoutePoint> remaining})
      routeParts(List<EvRoutePoint> route, EvRouteProgress? progress) {
    if (progress == null || !progress.isOnRoute) {
      return (passed: null, remaining: route);
    }
    return (
      passed: progress.hasPassed ? progress.passed : null,
      remaining: progress.hasRemaining ? progress.remaining : const [],
    );
  }

  /// Станция ID → маркер тури. Асосий тўхташ заҳира сифатида ҳам
  /// кўрсатилмайди (асосий устун).
  static Map<String, EvTripMarkerKind> markerKinds(EvTripPlan plan) {
    final kinds = <String, EvTripMarkerKind>{};
    for (final stop in plan.stops) {
      for (final b in stop.backups) {
        kinds[b.station.id] = EvTripMarkerKind.backup;
      }
    }
    // Асосийлар охирида — заҳира белгисини босиб кетади.
    for (final stop in plan.stops) {
      kinds[stop.station.id] = EvTripMarkerKind.primary;
    }
    return kinds;
  }

  /// Асосий тўхташнинг рақами (1'дан бошлаб); тўхташ эмас — `null`.
  static Map<String, int> stopNumbers(EvTripPlan plan) {
    final numbers = <String, int>{};
    for (var i = 0; i < plan.stops.length; i++) {
      numbers[plan.stops[i].station.id] = i + 1;
    }
    return numbers;
  }
}

/// ⚡ Сафар режасининг харитаси: маршрут чизиғи, рақамланган асосий
/// тўхташлар, заҳиралар ва йўл бўйидаги қолган станциялар.
///
/// Тўлиқ экранли сафар харитаси учун кенгайтирилган (барчаси ихтиёрий —
/// эски чақирув ўзгаришсиз ишлайди):
///  * [carLat]/[carLng]/[carHeading] — машинанинг жонли маркери;
///  * [progress] — босиб ўтилган қисм хира, қолгани маршрут рангида;
///  * [follow] — камера машина изидан боради; фойдаланувчи харитани сурса
///    [onUserGesture] чақирилади (камера у билан "курашмайди");
///  * [padding] — Google логотипи/тугмалари варақа остида қолмасин.
class EvTripMapView extends StatefulWidget {
  const EvTripMapView({
    super.key,
    required this.route,
    required this.corridorStations,
    required this.plan,
    required this.destinationLat,
    required this.destinationLng,
    this.progress,
    this.carLat,
    this.carLng,
    this.carHeading = 0,
    this.follow = false,
    this.padding = EdgeInsets.zero,
    this.onUserGesture,
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
  final VoidCallback? onUserGesture;

  bool get hasCar => carLat != null && carLng != null;

  @override
  State<EvTripMapView> createState() => _EvTripMapViewState();
}

class _EvTripMapViewState extends State<EvTripMapView> {
  GoogleMapController? _map;
  bool _didFit = false;
  int _fitAttempts = 0;

  double _zoom = 6;
  BitmapDescriptor? _carIcon;
  bool _carIconRequested = false;

  /// Камерани ўзимиз ҳаракатлантирган пайт — шу вақтдаги `onCameraMoveStarted`
  /// фойдаланувчи ҳаракати ҳисобланмайди.
  DateTime _lastProgrammaticAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _programmaticWindow = Duration(milliseconds: 1200);

  /// Бармоқ шунча пикселдан кўп сурилса — фойдаланувчи харитани суряпти.
  static const double _dragSlopPx = 8;
  final Map<int, Offset> _pointerStart = {};
  final Set<int> _pointerMoved = {};

  @override
  void didUpdateWidget(EvTripMapView old) {
    super.didUpdateWidget(old);
    // Янги режа/маршрут келди — камера қайта мосланади.
    if (old.route.length != widget.route.length) {
      _didFit = false;
      _fitAttempts = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitRoute());
    }

    if (widget.follow && widget.hasCar) {
      final moved = old.carLat != widget.carLat || old.carLng != widget.carLng;
      if (moved || !old.follow) _followCar(fresh: !old.follow);
    }
  }

  void _markProgrammatic() => _lastProgrammaticAt = DateTime.now();

  bool get _isProgrammatic =>
      DateTime.now().difference(_lastProgrammaticAt) < _programmaticWindow;

  /// Камерани машинага олиб бориш. "Янги кузатув" (тугма босилди) —
  /// яқинлаштириб; кейинги сурилишларда фойдаланувчи танлаган масштаб
  /// сақланади.
  Future<void> _followCar({required bool fresh}) async {
    final map = _map;
    if (map == null || !widget.hasCar) return;
    _markProgrammatic();
    final target = LatLng(widget.carLat!, widget.carLng!);
    try {
      await map.animateCamera(fresh && _zoom < 14.5
          ? CameraUpdate.newLatLngZoom(target, 16)
          : CameraUpdate.newLatLng(target));
    } catch (e) {
      debugPrint('EvTripMapView._followCar: $e');
    }
  }

  void _userMoved() {
    if (widget.follow) widget.onUserGesture?.call();
  }

  /// `newLatLngBounds` харита ҳали лейаут қилинмаган пайтда хато ташлаши
  /// мумкин — `EvMapView`даги нақш билан бир хил: муваффақиятли
  /// бўлмагунча бир неча марта қайта уринамиз.
  Future<void> _fitRoute() async {
    if (_didFit || !mounted) return;
    final bounds = EvTripMapGeometry.boundsFor(widget.route);
    final map = _map;
    if (bounds == null || map == null) return;
    _markProgrammatic();
    try {
      await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 36));
      _didFit = true;
    } catch (e) {
      _fitAttempts += 1;
      debugPrint('EvTripMapView._fitRoute: urinish $_fitAttempts — $e');
      if (_fitAttempts < 6) {
        await Future.delayed(const Duration(milliseconds: 350));
        if (mounted) await _fitRoute();
      }
    }
  }

  List<LatLng> _latLngs(List<EvRoutePoint> pts) =>
      pts.map((p) => LatLng(p.lat, p.lng)).toList();

  Set<Polyline> _polylines(BuildContext context) {
    if (widget.route.length < 2) return const {};
    final parts = EvTripMapGeometry.routeParts(widget.route, widget.progress);
    return {
      if (parts.passed != null)
        Polyline(
          polylineId: const PolylineId('ev_trip_route_passed'),
          points: _latLngs(parts.passed!),
          color: context.ava.ink3.withValues(alpha: 0.85),
          width: 5,
          zIndex: 1,
        ),
      if (parts.remaining.length >= 2)
        Polyline(
          polylineId: const PolylineId('ev_trip_route'),
          points: _latLngs(parts.remaining),
          color: AppColors.primaryDark,
          width: 5,
          zIndex: 2,
        ),
    };
  }

  Set<Marker> _markers(BuildContext context) {
    final km = context.tr('ev_trip_km');
    final offRoute = context.tr('ev_trip_off_route');
    final kinds = EvTripMapGeometry.markerKinds(widget.plan);
    final numbers = EvTripMapGeometry.stopNumbers(widget.plan);
    final markers = <Marker>{};

    for (final c in widget.corridorStations) {
      final s = c.station;
      final kind = kinds[s.id] ?? EvTripMarkerKind.other;
      final number = numbers[s.id];
      final name = s.hasName ? s.name!.trim() : '⚡';

      markers.add(Marker(
        markerId: MarkerId('ev_trip_${s.id}'),
        position: LatLng(s.latitude, s.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(switch (kind) {
          EvTripMarkerKind.primary => BitmapDescriptor.hueRed,
          EvTripMarkerKind.backup => BitmapDescriptor.hueOrange,
          EvTripMarkerKind.other => BitmapDescriptor.hueGreen,
        }),
        // Асосий тўхташлар устда турсин — рақамлари босилиб кетмасин.
        zIndexInt: switch (kind) {
          EvTripMarkerKind.primary => 3,
          EvTripMarkerKind.backup => 2,
          EvTripMarkerKind.other => 1,
        },
        infoWindow: InfoWindow(
          title: number != null ? '$number. $name' : name,
          snippet: '${c.alongKm.round()} $km'
              '${c.offRouteKm >= 1 ? ' · $offRoute ${c.offRouteKm.round()} $km' : ''}',
        ),
      ));
    }

    markers.add(Marker(
      markerId: const MarkerId('ev_trip_destination'),
      position: LatLng(widget.destinationLat, widget.destinationLng),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
      zIndexInt: 4,
    ));

    if (widget.hasCar) {
      markers.add(Marker(
        markerId: const MarkerId('ev_trip_car'),
        position: LatLng(widget.carLat!, widget.carLng!),
        icon: _carIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        // Ўқ шимолга қараб чизилган — йўналиш бўйича айлантирилади.
        rotation: widget.carHeading,
        flat: true,
        anchor: const Offset(0.5, 0.5),
        zIndexInt: 5,
      ));
    }

    return markers;
  }

  void _ensureCarIcon() {
    if (_carIconRequested || !widget.hasCar) return;
    _carIconRequested = true;
    EvCarMarkerIcon.load().then((icon) {
      if (mounted) setState(() => _carIcon = icon);
    });
  }

  @override
  Widget build(BuildContext context) {
    _ensureCarIcon();
    final first = widget.route.isNotEmpty
        ? LatLng(widget.route.first.lat, widget.route.first.lng)
        : LatLng(widget.destinationLat, widget.destinationLng);

    // Listener — фақат кузатади (translucent): харита ҳаракатларини
    // ютмайди. Бармоқ сурилса ва кузатув ёқиқ бўлса — "фойдаланувчи
    // сурди" деб хабар берилади.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _pointerStart[e.pointer] = e.position,
      onPointerMove: (e) {
        final start = _pointerStart[e.pointer];
        if (start == null || _pointerMoved.contains(e.pointer)) return;
        if ((e.position - start).distance > _dragSlopPx) {
          _pointerMoved.add(e.pointer);
          _userMoved();
        }
      },
      onPointerUp: (e) {
        _pointerStart.remove(e.pointer);
        _pointerMoved.remove(e.pointer);
      },
      onPointerCancel: (e) {
        _pointerStart.remove(e.pointer);
        _pointerMoved.remove(e.pointer);
      },
      child: GoogleMap(
        initialCameraPosition: CameraPosition(target: first, zoom: 6),
        polylines: _polylines(context),
        markers: _markers(context),
        padding: widget.padding,
        myLocationEnabled: false,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        // Харита скролл қилинадиган рўйхат ичида ҳам ишлатилиши мумкин —
        // ўз ҳаракатларини ўзи қабул қилади.
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
        },
        onMapCreated: (c) {
          _map = c;
          WidgetsBinding.instance.addPostFrameCallback((_) => _fitRoute());
        },
        onCameraMove: (pos) => _zoom = pos.zoom,
        // Иккинчи сигнал: ўзимиз ҳаракатлантирмаган камера ҳаракати.
        onCameraMoveStarted: () {
          if (!_isProgrammatic) _userMoved();
        },
      ),
    );
  }
}
