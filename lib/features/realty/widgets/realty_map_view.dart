import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../models/realty_listing.dart';
import '../realty_tabs.dart';

/// Эълонлар остидаги умумий харита (концепция, 7-бўлим).
///
/// ИККИ РЕЖИМДА ишлайди — бу шу бўлимнинг пул топиш мантиғи:
///   • **Тахминий ҳудуд** (пакетсиз ёки очилмаган объект): бир geohash4
///     катакчасидаги объектлар БИТТА доира қилиб бирлаштирилади, доира
///     маркази катакча ўртаси (≈20 км), ичида объектлар сони. Аниқ
///     нуқта кўрсатилмайди — у пуллик ахборот (9-бўлим).
///   • **Аниқ пин**: фойдаланувчи ахборот пакетидан очган объектлар.
///     Уларнинг координатаси [exactPoints] орқали берилади.
///
/// Аниқ координата иловага умуман келмайди: у Firestore қоидаси билан
/// ёпилган `private/detail` ҳужжатида. Шунинг учун бу виджет «тахминий»
/// режимда аниқ нуқтани билмайди ҳам — яширмайди, эгаси йўқ.
class RealtyMapView extends StatefulWidget {
  const RealtyMapView({
    super.key,
    required this.listings,
    required this.onListingTap,
    this.exactPoints = const {},
    this.centerLat = 41.2995,
    this.centerLng = 69.2401,
    this.initialZoom = 10,
  });

  final List<RealtyListing> listings;
  final ValueChanged<RealtyListing> onListingTap;

  /// Очилган объектлар: `listingId` → аниқ координата.
  final Map<String, LatLng> exactPoints;

  final double centerLat;
  final double centerLng;
  final double initialZoom;

  @override
  State<RealtyMapView> createState() => _RealtyMapViewState();
}

class _RealtyMapViewState extends State<RealtyMapView> {
  /// Шундан кичик чегара «битта нуқта» деб ҳисобланади (≈2 км).
  static const double _minSpanDegrees = 0.02;

  /// Битта нуқта бўлганда камера зуми — тахминий катакча (≈20 км)
  /// атрофи кўриниб турсин.
  static const double _singlePointZoom = 11;

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

  /// Катакча бўйича гуруҳлаш — тахминий режим шу гуруҳлардан қурилади.
  Map<String, List<RealtyListing>> get _cells {
    final out = <String, List<RealtyListing>>{};
    for (final r in widget.listings) {
      if (widget.exactPoints.containsKey(r.id)) continue; // аниқ пин бўлади
      final key = r.geohash4.isEmpty ? '${r.areaLat},${r.areaLng}' : r.geohash4;
      (out[key] ??= []).add(r);
    }
    return out;
  }

  List<LatLng> get _allPoints => [
        for (final e in widget.exactPoints.values) e,
        for (final group in _cells.values)
          LatLng(group.first.areaLat, group.first.areaLng),
      ];

  LatLngBounds? _bounds() {
    final pts = _allPoints;
    if (pts.isEmpty) return null;
    double? minLat, maxLat, minLng, maxLng;
    for (final p in pts) {
      minLat = (minLat == null || p.latitude < minLat) ? p.latitude : minLat;
      maxLat = (maxLat == null || p.latitude > maxLat) ? p.latitude : maxLat;
      minLng = (minLng == null || p.longitude < minLng) ? p.longitude : minLng;
      maxLng = (maxLng == null || p.longitude > maxLng) ? p.longitude : maxLng;
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
      // Нуқталар битта бўлса (ёки ҳаммаси бир катакда) чегара нолга
      // тенг бўлиб қолади ва `newLatLngBounds` максимал зумга кетади —
      // экранда фақат бўш яшил майдон кўринади (қурилмада сезилди,
      // 2026-09-28). Шунинг учун бундай ҳолда белгиланган зум.
      final latSpan =
          (bounds.northeast.latitude - bounds.southwest.latitude).abs();
      final lngSpan =
          (bounds.northeast.longitude - bounds.southwest.longitude).abs();
      if (latSpan < _minSpanDegrees && lngSpan < _minSpanDegrees) {
        await map.animateCamera(CameraUpdate.newLatLngZoom(
          LatLng(
            (bounds.northeast.latitude + bounds.southwest.latitude) / 2,
            (bounds.northeast.longitude + bounds.southwest.longitude) / 2,
          ),
          _singlePointZoom,
        ));
      } else {
        await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 48));
      }
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

  /// Тахминий ҳудуд — катакча устидаги доира. Радиус 8 км: бу «объект
  /// шу атрофда» дегани, аниқ манзил эмас.
  Set<Circle> _circles() {
    return {
      for (final entry in _cells.entries)
        Circle(
          circleId: CircleId('cell_${entry.key}'),
          center: LatLng(entry.value.first.areaLat, entry.value.first.areaLng),
          radius: 8000,
          strokeWidth: 2,
          strokeColor: RealtyTabs.colorFor(_topTier(entry.value)),
          fillColor:
              RealtyTabs.colorFor(_topTier(entry.value)).withValues(alpha: 0.14),
        ),
    };
  }

  /// Катакчадаги энг «баланд» даража — доира ранги шунга қараб.
  RealtyTier _topTier(List<RealtyListing> group) {
    if (group.any((r) => r.tier == RealtyTier.urgent)) return RealtyTier.urgent;
    if (group.any((r) => r.tier == RealtyTier.promo)) return RealtyTier.promo;
    return RealtyTier.plain;
  }

  Set<Marker> _markers() {
    final markers = <Marker>{};

    // Очилган объектлар — аниқ пин.
    for (final r in widget.listings) {
      final point = widget.exactPoints[r.id];
      if (point == null) continue;
      markers.add(Marker(
        markerId: MarkerId(r.id),
        position: point,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          RealtyTabs.markerHueFor(r.tier),
        ),
        onTap: () => widget.onListingTap(r),
      ));
    }

    // Тахминий катакчалар — сони кўрсатилган битта белги.
    for (final entry in _cells.entries) {
      final group = entry.value;
      markers.add(Marker(
        markerId: MarkerId('cellPin_${entry.key}'),
        position: LatLng(group.first.areaLat, group.first.areaLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          RealtyTabs.markerHueFor(_topTier(group)),
        ),
        alpha: 0.75,
        infoWindow: InfoWindow(title: '${group.length} объект'),
        // Битта объект бўлса ҳам карточкани очамиз — аниқ жой барибир
        // кўрсатилмайди, харидор ахборотни ичкарида сотиб олади.
        onTap: group.length == 1 ? () => widget.onListingTap(group.first) : null,
      ));
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(widget.centerLat, widget.centerLng),
        zoom: widget.initialZoom,
      ),
      markers: _markers(),
      circles: _circles(),
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
