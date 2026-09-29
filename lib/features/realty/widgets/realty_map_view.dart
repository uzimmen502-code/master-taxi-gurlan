import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../models/realty_listing.dart';
import '../realty_tabs.dart';

/// Эълонлар остидаги умумий харита (концепция, 7-бўлим).
///
/// ИККИ РЕЖИМДА ишлайди — бу шу бўлимнинг пул топиш мантиғи:
///   • **Тахминий нуқта** (пакетсиз ёки очилмаган объект): серверда ҳар
///     объект учун ≈1.2 км радиусда БИР МАРТА силкитилган нуқта.
///   • **Аниқ пин**: фойдаланувчи ахборот пакетидан очган объектлар.
///     Уларнинг координатаси [exactPoints] орқали берилади.
///
/// Аниқ координата иловага умуман келмайди: у Firestore қоидаси билан
/// ёпилган `private/detail` ҳужжатида. Шунинг учун бу виджет «тахминий»
/// режимда аниқ нуқтани билмайди ҳам — яширмайди, эгаси йўқ.
///
/// Пин ўрнида НАРХ ЁРЛИҒИ чизилади (эга қарори, 2026-09-29). Бозор
/// стандарти шу: харидор харитага қараб дарҳол нарх тақсимотини кўради.
/// Тахминий объектда нарх олдида «~» туради — бу нархнинг эмас, ЖОЙнинг
/// тахминий эканини эслатади (изоҳ легендада).
class RealtyMapView extends StatefulWidget {
  const RealtyMapView({
    super.key,
    required this.listings,
    required this.onListingTap,
    this.exactPoints = const {},
    this.selectedId,
    this.onSelectionChanged,
    this.fitToken = 0,
    this.centerLat = 41.2995,
    this.centerLng = 69.2401,
    this.initialZoom = 10,
  });

  final List<RealtyListing> listings;

  /// Ёрлиқ босилганда — карточка очиш ёки пакет таклифи.
  final ValueChanged<RealtyListing> onListingTap;

  /// Очилган объектлар: `listingId` → аниқ координата.
  final Map<String, LatLng> exactPoints;

  /// Пастдаги карточка тасмасида турган объект — ёрлиғи катталашади.
  final String? selectedId;

  /// Харитадаги ёрлиқ босилганда тасма шунга сурилсин.
  final ValueChanged<RealtyListing>? onSelectionChanged;

  /// Бу сон ўзгарса камера рўйхатга ҚАЙТА мосланади. Филтр ёки ҳудуд
  /// алмашганда керак: аввал камера биринчи мослашдан кейин умуман
  /// ҳаракатланмас, Сотиш'дан Ижара'га ўтилганда экранда эски жой
  /// қолиб кетар эди.
  final int fitToken;

  final double centerLat;
  final double centerLng;
  final double initialZoom;

  @override
  State<RealtyMapView> createState() => RealtyMapViewState();
}

class RealtyMapViewState extends State<RealtyMapView> {
  /// Шундан кичик чегара «битта нуқта» деб ҳисобланади (≈2 км).
  static const double _minSpanDegrees = 0.02;

  /// Битта нуқта бўлганда камера зуми — тахминий ҳудуд атрофи кўринсин.
  static const double _singlePointZoom = 11;

  GoogleMapController? _map;
  bool _didFitAll = false;
  int _fitAttempts = 0;
  int _appliedFitToken = 0;

  /// Чизилган ёрлиқлар: калит → расм. Ҳар кадрда қайта чизилмасин —
  /// бир ёрлиқни чизиш canvas + PNG кодлаш, бу арзон эмас.
  final Map<String, BitmapDescriptor> _iconCache = {};
  bool _iconsBuilding = false;
  bool _iconsDirty = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `initState` ЭМАС: ёрлиқни чизиш учун `devicePixelRatio` керак, у
    // эса `MediaQuery` дан олинади — `initState` да InheritedWidget'га
    // мурожаат қилиш ман этилган (debug'да assert тушади).
    _rebuildIcons();
  }

  @override
  void didUpdateWidget(RealtyMapView old) {
    super.didUpdateWidget(old);
    if (widget.fitToken != _appliedFitToken) {
      _appliedFitToken = widget.fitToken;
      _didFitAll = false;
      _fitAttempts = 0;
    }
    if (!_didFitAll && widget.listings.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll());
    }
    _rebuildIcons();
  }

  /// Очилмаган объектлар — ҳар бири АЛОҲИДА, чунки серверда ҳар
  /// объектнинг ўз силкитилган нуқтаси бор (≈1.2 км). Аввал улар
  /// geohash4 катакчаси бўйича гуруҳланар ва бутун туман битта
  /// нуқтага йиғилиб қолар эди.
  List<RealtyListing> get _approx => widget.listings
      .where((r) => !widget.exactPoints.containsKey(r.id))
      .toList();

  LatLng _pointOf(RealtyListing r) =>
      widget.exactPoints[r.id] ?? LatLng(r.areaLat, r.areaLng);

  List<LatLng> get _allPoints => [
        for (final r in widget.listings) _pointOf(r),
      ];

  // ───────────────────────── Ёрлиқ расмлари ─────────────────────────

  /// Харитада кўринадиган матн. Нарх ёзилмаган эълонда даража номи
  /// ўрнига қисқа белги — ёрлиқ бўш қолмасин.
  static String labelTextFor(RealtyListing r, {required bool approx}) {
    var p = r.priceText.trim();
    if (p.isEmpty) return approx ? '~ ?' : '?';
    // Узун матн харитани тўсиб қўймасин.
    if (p.length > 14) p = '${p.substring(0, 13)}…';
    return approx ? '~ $p' : p;
  }

  String _iconKey(RealtyListing r, {required bool approx}) {
    final selected = widget.selectedId == r.id;
    return '${r.tier.name}|$selected|${labelTextFor(r, approx: approx)}';
  }

  Future<void> _rebuildIcons() async {
    // Чизиш давом этаётган бўлса — белги қўйиб кетамиз, тугагач ўзи
    // яна бир айланади. Акс ҳолда чизиш вақтида келган янги эълонлар
    // ёрлиқсиз қолиб кетарди.
    if (_iconsBuilding) {
      _iconsDirty = true;
      return;
    }
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
    final needed = <String, ({RealtyListing r, bool approx})>{};
    for (final r in widget.listings) {
      final approx = !widget.exactPoints.containsKey(r.id);
      final key = _iconKey(r, approx: approx);
      if (!_iconCache.containsKey(key)) {
        needed[key] = (r: r, approx: approx);
      }
    }
    if (needed.isEmpty) return;
    _iconsBuilding = true;
    try {
      for (final e in needed.entries) {
        final bytes = await _drawLabel(
          text: labelTextFor(e.value.r, approx: e.value.approx),
          color: RealtyTabs.colorFor(e.value.r.tier),
          selected: widget.selectedId == e.value.r.id,
          dpr: dpr,
        );
        if (bytes == null) continue;
        _iconCache[e.key] = BitmapDescriptor.bytes(bytes, imagePixelRatio: dpr);
      }
    } catch (err) {
      // Чизиш бузилса хариталар барибир ишласин — стандарт пин қолади.
      debugPrint('RealtyMapView._rebuildIcons: $err');
    } finally {
      _iconsBuilding = false;
      if (mounted) setState(() {});
      if (_iconsDirty && mounted) {
        _iconsDirty = false;
        await _rebuildIcons();
      }
    }
  }

  /// Нарх ёрлиғини PNG қилиб чизади: тўлдирилган юмалоқ тўртбурчак,
  /// оқ матн ва пастда кичик учбурчак — у объект нуқтасини кўрсатади.
  Future<Uint8List?> _drawLabel({
    required String text,
    required Color color,
    required bool selected,
    required double dpr,
  }) async {
    final fontSize = selected ? 13.0 : 11.5;
    final padH = selected ? 10.0 : 8.0;
    final padV = selected ? 6.0 : 4.5;
    const tailH = 6.0;
    final border = selected ? 2.0 : 1.0;

    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final w = painter.width + padH * 2 + border * 2;
    final h = painter.height + padV * 2 + border * 2 + tailH;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(dpr);

    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h - tailH),
      const Radius.circular(7),
    );

    // Оқ ҳошия — ёрлиқ ҳар қандай харита фонида ажралиб турсин.
    canvas.drawRRect(
      bodyRect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(border, border, w - border * 2, h - tailH - border * 2),
        const Radius.circular(6),
      ),
      Paint()..color = color,
    );

    // Пастки учбурчак — аниқ нуқтани кўрсатади.
    final tail = Path()
      ..moveTo(w / 2 - 5, h - tailH - 0.5)
      ..lineTo(w / 2, h)
      ..lineTo(w / 2 + 5, h - tailH - 0.5)
      ..close();
    canvas.drawPath(tail, Paint()..color = Colors.white);
    final tailInner = Path()
      ..moveTo(w / 2 - 3.5, h - tailH - 1.5)
      ..lineTo(w / 2, h - 1.5)
      ..lineTo(w / 2 + 3.5, h - tailH - 1.5)
      ..close();
    canvas.drawPath(tailInner, Paint()..color = color);

    painter.paint(canvas, Offset(padH + border, padV + border));

    final image = await recorder
        .endRecording()
        .toImage((w * dpr).ceil(), (h * dpr).ceil());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    painter.dispose();
    return data?.buffer.asUint8List();
  }

  // ───────────────────────────── Камера ─────────────────────────────

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

  /// Танланган объектга камерани суриш — пастдаги тасма сурилганда.
  Future<void> focusOn(RealtyListing r) async {
    final map = _map;
    if (map == null) return;
    try {
      await map.animateCamera(CameraUpdate.newLatLng(_pointOf(r)));
    } catch (e) {
      debugPrint('RealtyMapView.focusOn: $e');
    }
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
        await map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 56));
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

  // ──────────────────────────── Маркерлар ───────────────────────────

  Set<Marker> _markers() {
    final markers = <Marker>{};
    for (final r in widget.listings) {
      final approx = !widget.exactPoints.containsKey(r.id);
      final icon = _iconCache[_iconKey(r, approx: approx)];
      markers.add(Marker(
        markerId: MarkerId(r.id),
        position: _pointOf(r),
        // Ёрлиқ ҳали чизилмаган бўлса стандарт пин — харита бўш
        // турмасин.
        icon: icon ??
            BitmapDescriptor.defaultMarkerWithHue(
              RealtyTabs.markerHueFor(r.tier),
            ),
        // Ёрлиқ пастки учи билан нуқтани кўрсатади (стандарт пиннинг
        // ҳам таянчи шу).
        anchor: const Offset(0.5, 1),
        zIndex: widget.selectedId == r.id ? 10 : (approx ? 1 : 2),
        onTap: () {
          widget.onSelectionChanged?.call(r);
          widget.onListingTap(r);
        },
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
      // Пин атрофидаги «тахминий ҳудуд» доираси олиб ташланган (эга
      // қарори, 2026-09-28) — доира харитани ифлослантирар эди.
      // Нуқталарнинг тахминийлиги ёрлиқдаги «~» ва легендада ёзилган.
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: false,
      // Пастдаги карточка тасмаси «менинг жойим» тугмасини тўсиб
      // қўймасин.
      padding: const EdgeInsets.only(bottom: 132),
      onMapCreated: (c) {
        _map = c;
        if (!_didFitAll && widget.listings.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll());
        }
      },
    );
  }
}
