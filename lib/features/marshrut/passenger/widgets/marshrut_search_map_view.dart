import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../models/schedule_search_result.dart';

/// Marshrut qidiruv natijalarini xaritada ko'rsatish (Phase C).
class MarshrutSearchMapView extends StatefulWidget {
  const MarshrutSearchMapView({
    super.key,
    required this.userLat,
    required this.userLng,
    required this.results,
  });

  final double? userLat;
  final double? userLng;
  final List<ScheduleSearchResult> results;

  static const LatLng gurlanCenter = LatLng(41.6, 60.6);

  @override
  State<MarshrutSearchMapView> createState() => _MarshrutSearchMapViewState();
}

class _MarshrutSearchMapViewState extends State<MarshrutSearchMapView> {
  GoogleMapController? _mapController;
  bool _fitted = false;

  List<ScheduleSearchResult> get _withGps => widget.results
      .where((r) => r.schedule.lat != null && r.schedule.lng != null)
      .toList();

  Set<Marker> _buildMarkers(BuildContext context) {
    final markers = <Marker>{};
    for (final r in _withGps) {
      final s = r.schedule;
      final eta = r.etaMin;
      final hue = eta == null
          ? BitmapDescriptor.hueAzure
          : eta <= 3
              ? BitmapDescriptor.hueGreen
              : eta <= 7
                  ? BitmapDescriptor.hueOrange
                  : BitmapDescriptor.hueRose;
      markers.add(
        Marker(
          markerId: MarkerId(s.id),
          position: LatLng(s.lat!, s.lng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          infoWindow: InfoWindow(
            title: s.driverName,
            snippet: eta != null
                ? context
                    .tr('marshrut_map_marker_snippet')
                    .replaceAll('{eta}', '$eta')
                    .replaceAll('{seats}', '${s.seatsLeft}')
                : '🚗 ${s.car}',
          ),
        ),
      );
    }
    return markers;
  }

  Future<void> _fitCamera() async {
    final controller = _mapController;
    if (controller == null || _fitted) return;

    final points = <LatLng>[];
    if (widget.userLat != null && widget.userLng != null) {
      points.add(LatLng(widget.userLat!, widget.userLng!));
    }
    for (final r in _withGps) {
      points.add(LatLng(r.schedule.lat!, r.schedule.lng!));
    }
    if (points.isEmpty) return;

    _fitted = true;
    if (points.length == 1) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, 13),
      );
      return;
    }

    var minLat = points.first.latitude;
    var maxLat = minLat;
    var minLng = points.first.longitude;
    var maxLng = minLng;
    for (final p in points.skip(1)) {
      minLat = minLat < p.latitude ? minLat : p.latitude;
      maxLat = maxLat > p.latitude ? maxLat : p.latitude;
      minLng = minLng < p.longitude ? minLng : p.longitude;
      maxLng = maxLng > p.longitude ? maxLng : p.longitude;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 56),
      );
    } catch (_) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, 12),
      );
    }
  }

  @override
  void didUpdateWidget(covariant MarshrutSearchMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.results != widget.results ||
        oldWidget.userLat != widget.userLat ||
        oldWidget.userLng != widget.userLng) {
      _fitted = false;
      _fitCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_withGps.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            context.tr('marshrut_map_no_drivers_gps'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ),
      );
    }

    final initial = widget.userLat != null && widget.userLng != null
        ? LatLng(widget.userLat!, widget.userLng!)
        : LatLng(_withGps.first.schedule.lat!, _withGps.first.schedule.lng!);

    return GoogleMap(
      initialCameraPosition: CameraPosition(target: initial, zoom: 12),
      markers: _buildMarkers(context),
      myLocationEnabled: widget.userLat != null && widget.userLng != null,
      myLocationButtonEnabled: widget.userLat != null && widget.userLng != null,
      zoomControlsEnabled: false,
      onMapCreated: (controller) {
        _mapController = controller;
        _fitCamera();
      },
    );
  }
}
