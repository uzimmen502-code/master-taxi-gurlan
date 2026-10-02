import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/ev_trip_planner.dart';
import '../models/ev_trip_plan.dart';

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
class EvTripMapView extends StatefulWidget {
  const EvTripMapView({
    super.key,
    required this.route,
    required this.corridorStations,
    required this.plan,
    required this.destinationLat,
    required this.destinationLng,
  });

  final List<EvRoutePoint> route;
  final List<EvCorridorStation> corridorStations;
  final EvTripPlan plan;
  final double destinationLat;
  final double destinationLng;

  @override
  State<EvTripMapView> createState() => _EvTripMapViewState();
}

class _EvTripMapViewState extends State<EvTripMapView> {
  GoogleMapController? _map;
  bool _didFit = false;
  int _fitAttempts = 0;

  @override
  void didUpdateWidget(EvTripMapView old) {
    super.didUpdateWidget(old);
    // Янги режа/маршрут келди — камера қайта мосланади.
    if (old.route.length != widget.route.length) {
      _didFit = false;
      _fitAttempts = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitRoute());
    }
  }

  /// `newLatLngBounds` харита ҳали лейаут қилинмаган пайтда хато ташлаши
  /// мумкин — `EvMapView`даги нақш билан бир хил: муваффақиятли
  /// бўлмагунча бир неча марта қайта уринамиз.
  Future<void> _fitRoute() async {
    if (_didFit || !mounted) return;
    final bounds = EvTripMapGeometry.boundsFor(widget.route);
    final map = _map;
    if (bounds == null || map == null) return;
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

  Set<Polyline> _polylines() {
    if (widget.route.length < 2) return const {};
    return {
      Polyline(
        polylineId: const PolylineId('ev_trip_route'),
        points: widget.route.map((p) => LatLng(p.lat, p.lng)).toList(),
        color: AppColors.primaryDark,
        width: 5,
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

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.route.isNotEmpty
        ? LatLng(widget.route.first.lat, widget.route.first.lng)
        : LatLng(widget.destinationLat, widget.destinationLng);

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: first, zoom: 6),
      polylines: _polylines(),
      markers: _markers(context),
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      // Харита скролл қилинадиган рўйхат ичида турибди — ўз ҳаракатларини
      // ўзи қабул қилмаса, суриш/яқинлаштириш рўйхатга кетиб қолади.
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
      },
      onMapCreated: (c) {
        _map = c;
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitRoute());
      },
    );
  }
}
