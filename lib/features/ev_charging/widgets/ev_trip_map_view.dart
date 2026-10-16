import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/ev_route_progress.dart';
import '../controllers/ev_trip_planner.dart';
import '../controllers/ev_trip_selection.dart';
import '../models/ev_trip_plan.dart';
import 'ev_car_marker_icon.dart';
import 'ev_trip_dot_icon.dart';
import 'ev_trip_stop_icon.dart';

export '../controllers/ev_trip_selection.dart' show EvTripMarkerKind;

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
  static Map<String, EvTripMarkerKind> markerKinds(EvTripPlan plan) =>
      evTripMarkerKinds(plan);

  /// Маркер кўриниши: танланган — рақамли қизил доира; танланмаган асосий —
  /// қизил игна, заҳира — тўқ сариқ игна; режага кирмаган «бошқа» станция —
  /// кичик хира нуқта (тавсия этилганлар кўриниш марказида қолсин).
  static EvTripMarkerStyle markerStyle(
          EvTripMarkerKind kind, int? selectedNumber) =>
      selectedNumber != null
          ? EvTripMarkerStyle.numbered
          : switch (kind) {
              EvTripMarkerKind.primary => EvTripMarkerStyle.primaryPin,
              EvTripMarkerKind.backup => EvTripMarkerStyle.backupPin,
              EvTripMarkerKind.other => EvTripMarkerStyle.mutedDot,
            };
}

/// Станция маркерининг чизилиш тури ([EvTripMapGeometry.markerStyle]).
enum EvTripMarkerStyle { numbered, primaryPin, backupPin, mutedDot }

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
    required this.candidates,
    required this.destinationLat,
    required this.destinationLng,
    this.selectedNumbers = const {},
    this.onStationTap,
    this.progress,
    this.carLat,
    this.carLng,
    this.carHeading = 0,
    this.follow = false,
    this.padding = EdgeInsets.zero,
    this.onUserGesture,
  });

  final List<EvRoutePoint> route;

  /// Йўл бўйидаги БАРЧА станциялар (коридор) — ҳаммаси чизилади, яшириш ёки
  /// кластерлаш йўқ.
  final List<EvTripCandidate> candidates;
  final double destinationLat;
  final double destinationLng;

  /// Ҳайдовчи танлаган станциялар: id → йўл бўйича тартиб рақами. Танланган
  /// маркер рақамли қизил доира; қолганлар ўз тури рангида (асосий қизил,
  /// заҳира тўқ сариқ, бошқа — кичик хира нуқта).
  final Map<String, int> selectedNumbers;

  /// Станция маркери босилди (id).
  final ValueChanged<String>? onStationTap;

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
    final markers = <Marker>{};

    // БАРЧА коридор станциялари чизилади (яширилмайди, кластерланмайди).
    for (final c in widget.candidates) {
      final s = c.station;
      final number = widget.selectedNumbers[c.id];
      final style = EvTripMapGeometry.markerStyle(c.kind, number);
      final selectedIcon = number == null ? null : _numberIcons[number];
      final dot = style == EvTripMarkerStyle.mutedDot ? _dotIcon : null;

      // Танланган — рақамли қизил доира (иконка тайёр бўлгунча оддий
      // қизил маркер); танланмаган асосий қизил, заҳира тўқ сариқ игна;
      // «бошқа» — хира нуқта (иконка тайёр бўлгунча кўринмайди).
      final BitmapDescriptor icon = switch (style) {
        EvTripMarkerStyle.numbered => selectedIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        EvTripMarkerStyle.primaryPin =>
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        EvTripMarkerStyle.backupPin =>
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        EvTripMarkerStyle.mutedDot => dot ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
      };
      final centered = selectedIcon != null || dot != null;

      markers.add(Marker(
        markerId: MarkerId('ev_trip_${s.id}'),
        position: LatLng(s.latitude, s.longitude),
        icon: icon,
        visible: style != EvTripMarkerStyle.mutedDot || dot != null,
        anchor: centered ? const Offset(0.5, 0.5) : const Offset(0.5, 1.0),
        // Танланганлар устда, кейин асосий, заҳира, бошқалар.
        zIndexInt: number != null
            ? 4
            : switch (c.kind) {
                EvTripMarkerKind.primary => 3,
                EvTripMarkerKind.backup => 2,
                EvTripMarkerKind.other => 1,
              },
        // Босилганда ўз варағимиз очилади; хаританинг ўз ёзув ойнаси йўқ.
        onTap: () => widget.onStationTap?.call(s.id),
      ));
    }

    markers.add(Marker(
      markerId: const MarkerId('ev_trip_destination'),
      position: LatLng(widget.destinationLat, widget.destinationLng),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
      zIndexInt: 5,
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
        zIndexInt: 6,
      ));
    }

    return markers;
  }

  /// Танланган станциялар учун рақамли иконкалар (рақам → иконка). Кеш
  /// EvTripStopIconда; бу ерда фақат тайёр бўлганлари сақланади.
  final Map<int, BitmapDescriptor> _numberIcons = {};
  final Set<int> _numberRequested = {};

  void _ensureNumberIcons() {
    for (final n in widget.selectedNumbers.values) {
      if (!_numberRequested.add(n)) continue;
      EvTripStopIcon.load(n).then((icon) {
        if (mounted) setState(() => _numberIcons[n] = icon);
      });
    }
  }

  /// Хира нуқта иконкаси — бир марта чизилади ([EvTripDotIcon] кеши).
  BitmapDescriptor? _dotIcon;
  bool _dotRequested = false;

  void _ensureDotIcon() {
    if (_dotRequested) return;
    _dotRequested = true;
    EvTripDotIcon.load().then((icon) {
      if (mounted) setState(() => _dotIcon = icon);
    });
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
    _ensureNumberIcons();
    _ensureDotIcon();
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
