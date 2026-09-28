import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../models/realty_listing.dart';
import '../realty_tabs.dart';

/// Эълонлар остидаги умумий харита (концепция, 7-бўлим).
///
/// ⚠️ 1-босқичда бу виджет ЭКРАНГА УЛАНМАГАН. Пакети йўқ фойдаланувчига
/// аниқ пин кўрсатиш пулли ахборотни бепул бериб қўяди, шунинг учун
/// харита ахборот пакетлари билан бирга, 3-босқичда ёқилади. Файл
/// ўшангача тайёр ҳолда турибди (қаранг: `screens/realty_screen.dart`).
///
/// `ev_map_view.dart` билан бир хил нақш: `GoogleMap` чақируви шу файл
/// ичида изоляция қилинади, биринчи нуқталар келганда камера ҳаммасини
/// қамраб оладиган қилиб мосланади.
///
/// Кластерлаш ҳозир йўқ — объектлар сони кўпайганда `EvClusterCalculator`
/// нақши шу ерга кўчирилади.
class RealtyMapView extends StatefulWidget {
  const RealtyMapView({
    super.key,
    required this.listings,
    required this.onListingTap,
    this.centerLat = 41.2995,
    this.centerLng = 69.2401,
    this.initialZoom = 12,
  });

  final List<RealtyListing> listings;
  final ValueChanged<RealtyListing> onListingTap;
  final double centerLat;
  final double centerLng;
  final double initialZoom;

  @override
  State<RealtyMapView> createState() => _RealtyMapViewState();
}

class _RealtyMapViewState extends State<RealtyMapView> {
  GoogleMapController? _map;
  bool _didFitAll = false;
  int _fitAttempts = 0;

  @override
  void didUpdateWidget(RealtyMapView old) {
    super.didUpdateWidget(old);
    if (!_didFitAll && widget.listings.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll());
    }
  }

  LatLngBounds? _bounds() {
    if (widget.listings.isEmpty) return null;
    double? minLat, maxLat, minLng, maxLng;
    for (final r in widget.listings) {
      minLat = (minLat == null || r.lat < minLat) ? r.lat : minLat;
      maxLat = (maxLat == null || r.lat > maxLat) ? r.lat : maxLat;
      minLng = (minLng == null || r.lng < minLng) ? r.lng : minLng;
      maxLng = (maxLng == null || r.lng > maxLng) ? r.lng : maxLng;
    }
    return LatLngBounds(
      southwest: LatLng(minLat!, minLng!),
      northeast: LatLng(maxLat!, maxLng!),
    );
  }

  /// `newLatLngBounds` харита ҳали лейаут қилинмаганда хато ташлаши
  /// мумкин — `ev_map_view.dart`даги каби бир неча марта уринамиз.
  Future<void> _fitAll() async {
    if (_didFitAll || !mounted) return;
    final bounds = _bounds();
    final map = _map;
    if (bounds == null || map == null) return;
    try {
      await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 48));
      _didFitAll = true;
    } catch (e) {
      _fitAttempts += 1;
      debugPrint('RealtyMapView._fitAll: $_fitAttempts — $e');
      if (_fitAttempts < 6) {
        await Future.delayed(const Duration(milliseconds: 350));
        if (mounted) await _fitAll();
      }
    }
  }

  Set<Marker> _markers() {
    return widget.listings
        .map((r) => Marker(
              markerId: MarkerId(r.id),
              position: LatLng(r.lat, r.lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                RealtyTabs.markerHueFor(r.tier),
              ),
              onTap: () => widget.onListingTap(r),
            ))
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(widget.centerLat, widget.centerLng),
        zoom: widget.initialZoom,
      ),
      markers: _markers(),
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      onMapCreated: (c) {
        _map = c;
        if (!_didFitAll && widget.listings.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll());
        }
      },
    );
  }
}
