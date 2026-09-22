import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/ev_charging_rules_holder.dart';
import '../../../models/ev_charging_station.dart';
import '../controllers/ev_cluster_calculator.dart';
import '../models/ev_cluster.dart';

/// `GoogleMap` chaqiruvlarini shu fayl ichiga izolyatsiya qiladigan thin
/// wrapper — repozitoriyda umumiy map-abstraksiya konventsiyasi yo'q
/// (`route_map_view.dart` ham to'g'ridan-to'g'ri `GoogleMap` ishlatadi),
/// lekin feature ichida bitta joyda ushlab turish provayderni kelajakda
/// almashtirishni osonlashtiradi (29-band).
class EvMapView extends StatefulWidget {
  const EvMapView({
    super.key,
    required this.centerLat,
    required this.centerLng,
    required this.stations,
    required this.onStationTap,
    this.initialZoom = 14,
  });

  final double centerLat;
  final double centerLng;
  final List<EvChargingStation> stations;
  final ValueChanged<EvChargingStation> onStationTap;
  final double initialZoom;

  @override
  State<EvMapView> createState() => _EvMapViewState();
}

class _EvMapViewState extends State<EvMapView> {
  GoogleMapController? _map;
  double _zoom = 14;

  /// Бир марта: биринчи нуқталар келганда бутун Ўзбекистон бўйлаб барча
  /// станциялар кўринадиган қилиб камерани мослаш (эга қарори, 2026-09-22
  /// — 456 та импорт нуқтаси фақат яқин атрофда эмас, ҳаммаси кўринсин).
  /// Кейин фойдаланувчи эркин суриши/яқинлаштириши мумкин.
  bool _didFitAll = false;

  @override
  void initState() {
    super.initState();
    _zoom = widget.initialZoom;
  }

  @override
  void didUpdateWidget(EvMapView old) {
    super.didUpdateWidget(old);
    if (old.centerLat != widget.centerLat || old.centerLng != widget.centerLng) {
      _map?.animateCamera(CameraUpdate.newLatLng(
        LatLng(widget.centerLat, widget.centerLng),
      ));
    }
    if (!_didFitAll && widget.stations.isNotEmpty) {
      _fitAllStations();
    }
  }

  LatLngBounds? _boundsForStations() {
    if (widget.stations.isEmpty) return null;
    double? minLat, maxLat, minLng, maxLng;
    for (final s in widget.stations) {
      minLat = (minLat == null || s.latitude < minLat) ? s.latitude : minLat;
      maxLat = (maxLat == null || s.latitude > maxLat) ? s.latitude : maxLat;
      minLng = (minLng == null || s.longitude < minLng) ? s.longitude : minLng;
      maxLng = (maxLng == null || s.longitude > maxLng) ? s.longitude : maxLng;
    }
    return LatLngBounds(
      southwest: LatLng(minLat!, minLng!),
      northeast: LatLng(maxLat!, maxLng!),
    );
  }

  Future<void> _fitAllStations() async {
    final bounds = _boundsForStations();
    final map = _map;
    if (bounds == null || map == null) return;
    _didFitAll = true;
    try {
      await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 40));
    } catch (_) {
      // Barcha nuqta bir joyda (bounds nol o'lchamli) — kamerani tegmaymiz.
    }
  }

  Set<Marker> _buildMarkers() {
    final threshold = EvChargingRulesHolder.current.clusteringThreshold;
    final clusters = EvClusterCalculator.build(
      widget.stations,
      threshold: threshold,
      zoom: _zoom,
    );
    return clusters.map(_markerFor).toSet();
  }

  Marker _markerFor(EvCluster cluster) {
    if (cluster.isSingle) {
      final station = cluster.stations.first;
      return Marker(
        markerId: MarkerId(cluster.id),
        position: LatLng(cluster.lat, cluster.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        onTap: () => widget.onStationTap(station),
      );
    }
    return Marker(
      markerId: MarkerId(cluster.id),
      position: LatLng(cluster.lat, cluster.lng),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      infoWindow: InfoWindow(title: '⚡ ${cluster.count} нуқта'),
      onTap: () => _map?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(cluster.lat, cluster.lng), _zoom + 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(widget.centerLat, widget.centerLng),
        zoom: widget.initialZoom,
      ),
      markers: _buildMarkers(),
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      onMapCreated: (c) {
        _map = c;
        if (!_didFitAll && widget.stations.isNotEmpty) {
          _fitAllStations();
        }
      },
      onCameraMove: (pos) => _zoom = pos.zoom,
      onCameraIdle: () => setState(() {}),
    );
  }
}
