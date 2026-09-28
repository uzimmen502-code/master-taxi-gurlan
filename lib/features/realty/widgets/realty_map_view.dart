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

  /// Очилмаган объектлар — ҳар бири АЛОҲИДА, чунки серверда ҳар
  /// объектнинг ўз силкитилган нуқтаси бор (≈1.2 км). Аввал улар
  /// geohash4 катакчаси бўйича гуруҳланар ва бутун туман битта
  /// нуқтага йиғилиб қолар эди.
  List<RealtyListing> get _approx => widget.listings
      .where((r) => !widget.exactPoints.containsKey(r.id))
      .toList();

  List<LatLng> get _allPoints => [
        for (final e in widget.exactPoints.values) e,
        for (final r in _approx) LatLng(r.areaLat, r.areaLng),
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

    // Очилмаганлар — ҳар бири ўз пини билан, лекин пин ТАХМИНИЙ
    // нуқтада. Карточкани очиш мумкин: аниқ жой барибир кўрсатилмайди,
    // харидор ахборотни ичкарида сотиб олади.
    for (final r in _approx) {
      markers.add(Marker(
        markerId: MarkerId('approxPin_${r.id}'),
        position: LatLng(r.areaLat, r.areaLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          RealtyTabs.markerHueFor(r.tier),
        ),
        alpha: 0.75,
        infoWindow: InfoWindow(title: r.titleOrText),
        onTap: () => widget.onListingTap(r),
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
      // Пин атрофидаги «тахминий ҳудуд» доираси олиб ташланди (эга
      // қарори, 2026-09-28) — пинларнинг ўзи етарли, доира харитани
      // ифлослантирар эди. Нуқталарнинг тахминийлиги легендада ёзилган.
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
