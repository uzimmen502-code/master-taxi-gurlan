import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Geolocator, ServiceStatus;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/geo/uz_bounds.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/business_map_gps_controller.dart';
import '../data/business_pin_loader.dart';
import '../domain/business_category.dart';
import '../domain/business_pin.dart';
import '../domain/pin_filter.dart';
import '../widgets/business_category_chips.dart';
import '../widgets/business_detail_sheet.dart';
import '../widgets/business_marker_icons.dart';
import 'my_businesses_screen.dart';

/// Бизнес харитаси: кафе-ресторан, улгуржи сотувчи, зарядка станцияси ва эгалар қўшган объектлар БИР харитада
/// (B-3). Тўлиқ экранли харита (AppBar йўқ — эга, 2026-10-23): юқорида қидирув ва БАРЧА 14 тур чиплари (ҳар бири ўз
/// рангида), маркерлар ҳам тур рангида. Кластер йўқ (B-4): камера қоплаган ҳудуд ўқилади, ≤400 нуқта (марказга
/// яқинлари); жуда катта ҳудудда чекланган намуна + «харитани яқинлаштиринг» (36-банд).
/// GPS бўлса — шу жой; бўлмаса — бутун мамлакат кўринадиган қилиб мослайди (EV харитаси каби); «GPS ўчиқ» хабари
/// GPS ёқилса кетади.
class BusinessMapScreen extends StatefulWidget {
  const BusinessMapScreen({super.key, this.loader, this.gps});

  /// Тест учун.
  final BusinessPinLoader? loader;
  final BusinessMapGpsController? gps;

  @override
  State<BusinessMapScreen> createState() => _BusinessMapScreenState();
}

class _BusinessMapScreenState extends State<BusinessMapScreen> with WidgetsBindingObserver {
  /// Бутун Ўзбекистон ва ҳамма нуқталар кўринадиган камера (GPS йўқ бўлганда).
  static final _countryBounds = LatLngBounds(
    southwest: const LatLng(kUzLatMin, kUzLngMin),
    northeast: const LatLng(kUzLatMax, kUzLngMax),
  );
  static const _countryCenter = LatLng(41.3, 64.6);
  static const _debounce = Duration(milliseconds: 450);

  late final BusinessPinLoader _loader = widget.loader ?? BusinessPinLoader();
  late final BusinessMapGpsController _gps = widget.gps ?? BusinessMapGpsController();
  final _search = TextEditingController();

  GoogleMapController? _controller;
  Timer? _timer;
  StreamSubscription<ServiceStatus>? _gpsStatusSub;
  int _seq = 0;

  List<BusinessPin> _pins = const [];
  Set<BusinessSource> _failed = const {};
  BusinessCategory? _category;
  bool _loading = false;
  bool _tooWide = false;
  bool _loadedOnce = false;

  /// GPS аниқланаётганда камера ўзгариши билан ортиқча (катта ҳудуд) сўров кетмасин.
  bool _locating = true;
  bool _iconsReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gps.addListener(_onGps);
    BusinessMarkerIcons.warmUp().then((_) {
      if (mounted) setState(() => _iconsReady = true);
    });
    // Тезкор панелдан GPS ёқилса — илова ёпилмайди, шунинг учун хизмат ҳолатини ҳам тинглаймиз.
    if (!kIsWeb) {
      try {
        _gpsStatusSub = Geolocator.getServiceStatusStream().listen(
          (s) {
            if (s == ServiceStatus.enabled) _retryGps();
          },
          onError: (Object _) {},
        );
      } catch (_) {
        // Қўллаб-қувватланмаса — фақат lifecycle ишлайди.
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gpsStatusSub?.cancel();
    _gps.removeListener(_onGps);
    if (widget.gps == null) _gps.dispose();
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onGps() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Созламалардан (GPS/рухсат) қайтганда.
    if (state == AppLifecycleState.resumed) _retryGps();
  }

  /// «GPS ўчиқ» хабари турган бўлса қайта аниқлайди; топилса хабар кетади ва камера шу жойга ўтади.
  Future<void> _retryGps() async {
    if (!mounted) return;
    if (await _gps.refresh() && mounted) _flyToGps();
  }

  void _flyToGps() {
    final c = _controller;
    if (c == null || !_gps.hasLocation) return;
    c.animateCamera(CameraUpdate.newLatLngZoom(LatLng(_gps.lat!, _gps.lng!), 14));
  }

  /// Харита тайёр: GPS бўлса шу жой, бўлмаса бутун мамлакат ва ҳамма нуқталар кўринадиган қилиб мослаш.
  Future<void> _start() async {
    final ok = await _gps.init();
    if (!mounted) return;
    _locating = false;
    if (ok) {
      _flyToGps();
    } else {
      await _fitCountry();
    }
    _onCameraIdle(); // камера ўзгармаса ҳам нуқталар юклансин
  }

  /// `newLatLngBounds` харита ҳали лейаут қилинмаган пайтда хато бериши мумкин — қайта уриниб кўрамиз (EV каби).
  Future<void> _fitCountry() async {
    for (var i = 0; i < 6 && mounted; i++) {
      try {
        await _controller?.animateCamera(CameraUpdate.newLatLngBounds(_countryBounds, 24));
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }
  }

  void _onCameraIdle() {
    if (_locating) return;
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

  Marker _marker(BusinessPin p) {
    final icon = _iconsReady ? BusinessMarkerIcons.ready[p.category] : null;
    return Marker(
      markerId: MarkerId(p.key),
      position: LatLng(p.lat, p.lng),
      icon: icon ?? BitmapDescriptor.defaultMarker,
      anchor: icon == null ? const Offset(0.5, 1) : const Offset(0.5, 0.5),
      onTap: () => BusinessDetailSheet.show(context, p),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = filterPins(_pins, category: _category, query: _search.text);
    final gpsError = _gps.error;
    final top = MediaQuery.paddingOf(context).top;
    // Хаританинг ўз тугмалари сузиб юрувчи панел тагидан чиқсин: орқага/қидирув (48) + чиплар (40) + оралиқлар.
    final overlayHeight = top + 12 + 48 + 8 + 40 + 8 + (gpsError != null ? 44 : 0);

    String? hint;
    if (_tooWide) {
      hint = context.tr('bizmap_zoom_in');
    } else if (_loadedOnce && !_loading && visible.isEmpty) {
      hint = context.tr('bizmap_empty');
    } else if (_failed.isNotEmpty && !_loading) {
      hint = context.tr('bizmap_load_partial');
    }

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(target: _countryCenter, zoom: 5.6),
            markers: {for (final p in visible) _marker(p)},
            padding: EdgeInsets.only(top: overlayHeight, bottom: 84),
            onMapCreated: (c) {
              _controller = c;
              _start();
            },
            onCameraIdle: _onCameraIdle,
            myLocationEnabled: _gps.hasLocation,
            myLocationButtonEnabled: _gps.hasLocation,
            zoomControlsEnabled: true,
            mapToolbarEnabled: false,
          ),
          Positioned(
            left: 12,
            right: 12,
            top: top + 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Material(
                      key: const ValueKey('biz_back'),
                      elevation: 3,
                      shape: const CircleBorder(),
                      color: Colors.white,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.of(context).maybePop(),
                        child: const SizedBox(width: 48, height: 48, child: Icon(Icons.arrow_back_rounded)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Material(
                        elevation: 3,
                        borderRadius: BorderRadius.circular(24),
                        child: SizedBox(
                          height: 48,
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
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                BusinessCategoryChips(selected: _category, onChanged: (c) => setState(() => _category = c)),
                if (gpsError != null) ...[
                  const SizedBox(height: 8),
                  _GpsBanner(text: context.trMsg(gpsError)),
                ],
              ],
            ),
          ),
          if (hint != null)
            Positioned(
              left: 24,
              right: 24,
              bottom: 92,
              child: IgnorePointer(
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
}

/// «GPS ўчиқ» — сузиб юрувчи огоҳлантириш (EV харитасидаги `EvMapGpsBanner` каби; босилмайди, харитани тўсмайди).
class _GpsBanner extends StatelessWidget {
  const _GpsBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        key: const ValueKey('biz_gps_banner'),
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_off_outlined, size: 18, color: AppColors.primaryText),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
          ],
        ),
      ),
    );
  }
}
