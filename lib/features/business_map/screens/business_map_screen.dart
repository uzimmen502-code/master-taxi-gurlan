import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/location_service.dart';
import '../data/business_pin_loader.dart';
import '../domain/business_category.dart';
import '../domain/business_pin.dart';
import '../domain/pin_filter.dart';
import '../widgets/business_detail_sheet.dart';
import 'my_businesses_screen.dart';

/// Бизнес харитаси: кафе-ресторан, улгуржи сотувчи, зарядка станцияси ва эгалар қўшган объектлар
/// БИР харитада (B-3). Кластерлаш йўқ (B-4): камера қоплаган ҳудуд ўқилади, жуда катта бўлса —
/// «яқинлаштиринг» (36-банд).
class BusinessMapScreen extends StatefulWidget {
  const BusinessMapScreen({super.key, this.initialLat, this.initialLng, this.loader});

  final double? initialLat;
  final double? initialLng;

  /// Тест учун.
  final BusinessPinLoader? loader;

  @override
  State<BusinessMapScreen> createState() => _BusinessMapScreenState();
}

class _BusinessMapScreenState extends State<BusinessMapScreen> {
  static const _fallbackCenter = LatLng(41.2995, 69.2401); // Тошкент (map_picker билан бир хил)
  static const _debounce = Duration(milliseconds: 450);

  late final BusinessPinLoader _loader = widget.loader ?? BusinessPinLoader();
  final _search = TextEditingController();

  GoogleMapController? _controller;
  Timer? _timer;
  int _seq = 0;

  List<BusinessPin> _pins = const [];
  Set<BusinessSource> _failed = const {};
  BusinessCategory? _category;
  bool _loading = false;
  bool _tooWide = false;
  bool _loadedOnce = false;
  LatLng? _gps;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  LatLng get _start {
    final lat = widget.initialLat;
    final lng = widget.initialLng;
    if (lat != null && lng != null) return LatLng(lat, lng);
    return _gps ?? _fallbackCenter;
  }

  /// GPS рухсатини СЎРАМАЙДИ (`getCoordsIfAllowed`): рухсат бўлса камера шу ерга боради.
  Future<void> _locate() async {
    try {
      final c = await context.read<LocationService>().getCoordsIfAllowed();
      if (c == null || !mounted) return;
      _gps = LatLng(c.lat, c.lng);
      if (widget.initialLat == null) {
        await _controller?.animateCamera(CameraUpdate.newLatLngZoom(_gps!, 13));
      }
    } catch (_) {
      // GPS йўқ — Тошкент/берилган марказ билан давом этамиз.
    }
  }

  void _onCameraIdle() {
    _timer?.cancel();
    _timer = Timer(_debounce, _reload);
  }

  Future<void> _reload() async {
    final c = _controller;
    if (c == null || !mounted) return;
    final seq = ++_seq;
    setState(() => _loading = true);
    try {
      final r = await c.getVisibleRegion();
      final res = await _loader.load(MapBounds(
        south: r.southwest.latitude,
        west: r.southwest.longitude,
        north: r.northeast.latitude,
        east: r.northeast.longitude,
      ));
      if (!mounted || seq != _seq) return; // янгироқ сўров келган
      setState(() {
        _pins = res.pins;
        _failed = res.failed;
        _tooWide = res.tooWide;
        _loading = false;
        _loadedOnce = true;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _loadedOnce = true;
        _failed = BusinessSource.values.toSet();
      });
    }
  }

  static double _hue(BusinessSource s) => switch (s) {
        BusinessSource.business => BitmapDescriptor.hueOrange,
        BusinessSource.restaurant => BitmapDescriptor.hueRed,
        BusinessSource.evStation => BitmapDescriptor.hueGreen,
        BusinessSource.wholesaleSeller => BitmapDescriptor.hueAzure,
      };

  @override
  Widget build(BuildContext context) {
    final visible = filterPins(_pins, category: _category, query: _search.text);
    final present = categoriesPresent(_pins);
    final markers = <Marker>{
      for (final p in visible)
        Marker(
          markerId: MarkerId(p.key),
          position: LatLng(p.lat, p.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(_hue(p.source)),
          onTap: () => BusinessDetailSheet.show(context, p),
        ),
    };

    String? hint;
    if (_tooWide) {
      hint = context.tr('bizmap_zoom_in');
    } else if (_loadedOnce && !_loading && visible.isEmpty) {
      hint = context.tr('bizmap_empty');
    } else if (_failed.isNotEmpty && !_loading) {
      hint = context.tr('bizmap_load_partial');
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('bizmap_title'))),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _start, zoom: 12),
            markers: markers,
            onMapCreated: (c) {
              _controller = c;
              _onCameraIdle();
            },
            onCameraIdle: _onCameraIdle,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            mapToolbarEnabled: false,
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Material(
                  elevation: 3,
                  borderRadius: BorderRadius.circular(12),
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: context.tr('bizmap_search_hint'),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(_search.clear),
                            ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                if (present.length > 1 || _category != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _chip(context.tr('bizmap_all'), null, Icons.apps_rounded),
                        for (final c in present) _chip(context.tr(c.labelKey), c, c.icon),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (hint != null)
            Positioned(
              left: 24,
              right: 24,
              bottom: 92,
              child: Material(
                elevation: 3,
                color: Colors.black87,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
          if (_loading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const MyBusinessesScreen())),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: AppColors.onPrimary,
        icon: const Icon(Icons.add_business_rounded),
        label: Text(context.tr('bizmap_add_mine')),
      ),
    );
  }

  Widget _chip(String label, BusinessCategory? value, IconData icon) {
    final selected = _category == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        avatar: Icon(icon, size: 16),
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _category = value),
        backgroundColor: Colors.white,
      ),
    );
  }
}
