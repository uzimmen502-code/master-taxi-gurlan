import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/geo/viewport_cells.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../models/ev_charging_station.dart';
import '../controllers/ev_station_cap.dart';

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

  /// Камера маркази: ≤400 нуқта «марказга яқинлари» шунга нисбатан (кластер йўқ).
  late LatLng _center = LatLng(widget.centerLat, widget.centerLng);

  /// Кўринган ҳудуд жуда катта (>30 geohash катакча — вилоят/мамлакат миқёси): «яқинлаштиринг» хабари.
  bool _tooWide = false;

  /// Бир марта: биринчи нуқталар келганда бутун Ўзбекистон бўйлаб барча
  /// станциялар кўринадиган қилиб камерани мослаш (эга қарори, 2026-09-22
  /// — 456 та импорт нуқтаси фақат яқин атрофда эмас, ҳаммаси кўринсин).
  /// Кейин фойдаланувчи эркин суриши/яқинлаштириши мумкин.
  bool _didFitAll = false;

  @override
  void initState() {
    super.initState();
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitAllStations());
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

  int _fitAttempts = 0;

  /// `newLatLngBounds` GoogleMap ҳали лейаут қилинмаган пайтда (масалан
  /// `onMapCreated`дан дарҳол кейин) `PlatformException`/`FlutterError`
  /// ташлаши мумкин — шунинг учун муваффақиятли бўлмагунча бир неча марта,
  /// қисқа кутиш билан қайта уринамиз (эски кодда бу хато жимгина
  /// ютилиб, камера ҳеч қачон мослашмас эди).
  Future<void> _fitAllStations() async {
    if (_didFitAll || !mounted) return;
    final bounds = _boundsForStations();
    final map = _map;
    if (bounds == null || map == null) return;
    try {
      await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 40));
      _didFitAll = true;
    } catch (e) {
      _fitAttempts += 1;
      debugPrint('EvMapView._fitAllStations: urinish $_fitAttempts muvaffaqiyatsiz — $e');
      if (_fitAttempts < 6) {
        await Future.delayed(const Duration(milliseconds: 350));
        if (mounted) await _fitAllStations();
      }
    }
  }

  /// Кластер ЙЎҚ (эга, 2026-10-23): ҳар станция — алоҳида маркер; бир вақтда ≤400 тасини, камера марказига яқинларини
  /// кўрсатади ([capNearestStations]). Бизнес харитаси билан бир хил қоида.
  Set<Marker> _buildMarkers() {
    final shown = capNearestStations(widget.stations, _center.latitude, _center.longitude);
    return {
      for (final s in shown)
        Marker(
          markerId: MarkerId(s.id),
          position: LatLng(s.latitude, s.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          onTap: () => widget.onStationTap(s),
        ),
    };
  }

  /// Камера тўхтагач: кўринган ҳудуд жуда катта эканини аниқлаб, «яқинлаштиринг» хабарини ёқади/ўчиради.
  Future<void> _onIdle() async {
    final map = _map;
    var wide = _tooWide;
    if (map != null) {
      try {
        final r = await map.getVisibleRegion();
        wide = ViewportCells.forBounds(
              south: r.southwest.latitude,
              west: r.southwest.longitude,
              north: r.northeast.latitude,
              east: r.northeast.longitude,
            ) ==
            null;
      } catch (_) {
        // Харита ҳали тайёр эмас — олдинги ҳолат қолади.
      }
    }
    if (mounted) setState(() => _tooWide = wide);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
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
              WidgetsBinding.instance.addPostFrameCallback((_) => _fitAllStations());
            }
          },
          onCameraMove: (pos) => _center = pos.target,
          onCameraIdle: _onIdle,
        ),
        if (_tooWide)
          Positioned(
            left: 24,
            right: 24,
            bottom: 92,
            child: IgnorePointer(
              child: Material(
                key: const ValueKey('ev_zoom_in_hint'),
                elevation: 3,
                color: Colors.black87,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(
                    context.tr('ev_map_zoom_in'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
