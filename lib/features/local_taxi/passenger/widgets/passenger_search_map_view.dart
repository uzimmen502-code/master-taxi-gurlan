import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../models/nearby_driver.dart';

/// Yo'lovchi qidiruv xaritasi — radius halqasi + anonim mashina belgilari.
class PassengerSearchMapView extends StatefulWidget {
  const PassengerSearchMapView({
    super.key,
    required this.fromLat,
    required this.fromLng,
    required this.radiusKm,
    required this.drivers,
    required this.isSearching,
    required this.pickupLabel,
  });

  final double fromLat;
  final double fromLng;
  final double radiusKm;
  final List<NearbyDriver> drivers;
  final bool isSearching;
  final String pickupLabel;

  @override
  State<PassengerSearchMapView> createState() => _PassengerSearchMapViewState();
}

class _PassengerSearchMapViewState extends State<PassengerSearchMapView> {
  static const _defaultCenter = LatLng(41.4957, 60.5822);

  final _mapController = Completer<GoogleMapController>();
  double? _lastFittedRadiusKm;

  LatLng get _pickup => widget.fromLat != 0 || widget.fromLng != 0
      ? LatLng(widget.fromLat, widget.fromLng)
      : _defaultCenter;

  @override
  void didUpdateWidget(covariant PassengerSearchMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSearching && oldWidget.radiusKm != widget.radiusKm) {
      _fitRadius();
    }
  }

  Future<void> _fitRadius() async {
    if (!_mapController.isCompleted || !widget.isSearching) return;
    if (_lastFittedRadiusKm == widget.radiusKm) return;
    _lastFittedRadiusKm = widget.radiusKm;
    final ctrl = await _mapController.future;
    final bounds = _boundsForRadius(_pickup, widget.radiusKm);
    await ctrl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 48));
  }

  LatLngBounds _boundsForRadius(LatLng center, double radiusKm) {
    const kmPerDegLat = 111.0;
    final kmPerDegLng = 111.0 *
        math.cos(center.latitude * math.pi / 180).abs().clamp(0.01, 1.0);
    final dLat = radiusKm / kmPerDegLat;
    final dLng = radiusKm / kmPerDegLng;
    return LatLngBounds(
      southwest: LatLng(center.latitude - dLat, center.longitude - dLng),
      northeast: LatLng(center.latitude + dLat, center.longitude + dLng),
    );
  }

  Set<Circle> _circles() {
    if (!widget.isSearching) return const {};
    return {
      Circle(
        circleId: const CircleId('search_radius'),
        center: _pickup,
        radius: widget.radiusKm * 1000,
        fillColor: AppColors.primary.withValues(alpha: 0.08),
        strokeColor: AppColors.primary.withValues(alpha: 0.45),
        strokeWidth: 2,
      ),
    };
  }

  Set<Marker> _markers() {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: _pickup,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: widget.pickupLabel),
      ),
    };

    for (var i = 0; i < widget.drivers.length; i++) {
      final d = widget.drivers[i];
      if (d.driver.lat == 0 && d.driver.lng == 0) continue;
      markers.add(Marker(
        markerId: MarkerId('car_$i'),
        position: LatLng(d.driver.lat, d.driver.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow.noText,
        alpha: 0.9,
      ));
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: _pickup, zoom: 13),
      markers: _markers(),
      circles: _circles(),
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: false,
      onMapCreated: (c) {
        if (!_mapController.isCompleted) {
          _mapController.complete(c);
          WidgetsBinding.instance.addPostFrameCallback((_) => _fitRadius());
        }
      },
    );
  }
}
