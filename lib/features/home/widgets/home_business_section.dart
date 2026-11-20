import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/geo/viewport_cells.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../services/location_service.dart';
import '../../business_map/data/business_repository.dart';
import '../../business_map/domain/business_pin.dart';
import '../../business_map/widgets/business_marker_icons.dart';
import 'ava_section.dart';

/// Бош саҳифа бўлими «Яқиндаги бизнеслар» (B-7). Дарвоза: `business_map` модули (`HomeModuleGate.showInGrid`).
///
/// Телефонда (эга 2026-11-20): харита ОЧИҚ ва яққол кўринади — юқорида ~180 dp енгил «расм-харита» (Google lite
/// mode, суриб бўлмайди, устида матн/қатлам йўқ), устида яқиндаги бизнес объектлари белгилари. Матн ва тугмалар —
/// харита ТАГИДА. Харита босилса — тўлиқ бизнес харитаси.
///
/// Ўқиш (37-банд): бўлим яратилганда БИТТА сўров, кичик чеклов ([markerLimit]), тингловчи йўқ — мавжуд
/// [BusinessRepository] орқали: GPS бўлса шу атрофдаги `geohash4` катаклари ([BusinessRepository.fetchInCells]),
/// бўлмаса энг янги объектлар ([BusinessRepository.fetchRecent]). Марказ — GPS, фақат рухсат АЛЛАҚАЧОН берилган
/// бўлса ([LocationService.getCoordsIfAllowed] — бош экранда рухсат сўралмайди); бўлмаса бутун мамлакат (бизнес
/// харитаси билан бир хил, эга қарори 2026-10-23).
///
/// Вебда — аввалгидек харитасиз оқ карта (Maps JS пулли, вебда жойлашув ҳам аниқланмайди) ва сўров ҳам йўқ.
class HomeBusinessSection extends StatefulWidget {
  const HomeBusinessSection({
    super.key,
    required this.onOpenMap,
    required this.onAddMine,
    @visibleForTesting this.showMap,
    @visibleForTesting this.locate,
    @visibleForTesting this.mapBuilder,
    @visibleForTesting this.loadPins,
  });

  final VoidCallback onOpenMap;
  final VoidCallback onAddMine;

  /// Тест учун; `null` — телефонда ҳа, вебда йўқ.
  final bool? showMap;

  /// Тест учун: GPS ўрнига.
  final Future<LocationCoords?> Function()? locate;

  /// Тест учун: GoogleMap (платформа кўриниши) ўрнига; [pins] — харитадаги белгилар.
  final Widget Function(LatLng center, double zoom, List<BusinessPin> pins)? mapBuilder;

  /// Тест учун: белгилар сўрови ўрнига (`gps == false` — мамлакат кўриниши).
  final Future<List<BusinessPin>> Function(LatLng center, {required bool gps})? loadPins;

  /// Бизнес харитасининг бошланғич нуқтаси билан бир хил (`BusinessMapScreen._countryCenter`, zoom 5.6).
  static const countryCenter = LatLng(41.3, 64.6);
  static const countryZoom = 5.6;
  static const gpsZoom = 14.0;

  /// Харита баландлиги (эга 2026-11-20: ~180 dp, ҳеч нарса билан ёпилмайди).
  static const mapHeight = 180.0;

  /// Харитадаги белгилар чеклови — битта кичик сўров.
  static const markerLimit = 20;

  /// GPS атрофидаги сўров ҳудуди (±градус): zoom 14 да 180 dp баландликдаги харита кўринишидан сал кенг.
  static const gpsSpanDeg = 0.02;

  @override
  State<HomeBusinessSection> createState() => _HomeBusinessSectionState();
}

class _HomeBusinessSectionState extends State<HomeBusinessSection> {
  late final bool _showMap = widget.showMap ?? !kIsWeb;
  LatLng _center = HomeBusinessSection.countryCenter;
  double _zoom = HomeBusinessSection.countryZoom;
  List<BusinessPin> _pins = const [];
  Map<String, BitmapDescriptor> _icons = const {};

  @override
  void initState() {
    super.initState();
    if (_showMap) _init();
  }

  Future<void> _init() async {
    var gps = false;
    try {
      final c = await (widget.locate ?? () => const LocationService().getCoordsIfAllowed())();
      if (c != null && mounted) {
        gps = true;
        setState(() {
          _center = LatLng(c.lat, c.lng);
          _zoom = HomeBusinessSection.gpsZoom;
        });
      }
    } catch (e) {
      debugPrint('[HomeBusinessSection] locate: $e'); // мамлакат маркази қолади
    }
    if (!mounted) return;
    try {
      final pins = await (widget.loadPins ?? _defaultLoadPins)(_center, gps: gps);
      if (!mounted) return;
      setState(() => _pins = pins.take(HomeBusinessSection.markerLimit).toList(growable: false));
      if (widget.mapBuilder == null) await _loadIcons();
    } catch (e) {
      // Белгисиз ҳам харита ишлайди; хато фақат логда (25-банд).
      debugPrint('[HomeBusinessSection] HOME_BIZ_PINS_FAILED: $e');
    }
  }

  /// Мавжуд репозиторий, БИТТА сўров, тингловчи йўқ.
  static Future<List<BusinessPin>> _defaultLoadPins(LatLng c, {required bool gps}) async {
    final repo = BusinessRepository();
    final cells = gps
        ? ViewportCells.forBounds(
            south: c.latitude - HomeBusinessSection.gpsSpanDeg,
            west: c.longitude - HomeBusinessSection.gpsSpanDeg,
            north: c.latitude + HomeBusinessSection.gpsSpanDeg,
            east: c.longitude + HomeBusinessSection.gpsSpanDeg,
          )
        : null;
    final rows = cells != null
        ? await repo.fetchInCells(cells, limit: HomeBusinessSection.markerLimit)
        : await repo.fetchRecent(limit: HomeBusinessSection.markerLimit);
    // Бизнес харитаси билан бир хил қоида: блокланган ва фақат онлайн (жойсиз) объект чизилмайди.
    return [for (final b in rows) if (!b.isBlocked && !b.online) BusinessPin.fromBusiness(b)];
  }

  Future<void> _loadIcons() async {
    final icons = <String, BitmapDescriptor>{};
    for (final p in _pins) {
      try {
        icons[p.id] = await BusinessMarkerIcons.of(p.category);
      } catch (_) {
        // Стандарт белги қолади.
      }
    }
    if (mounted) setState(() => _icons = icons);
  }

  Widget _map() =>
      widget.mapBuilder?.call(_center, _zoom, _pins) ??
      GoogleMap(
        // Марказ ёки белгилар ўзгарса — қайта яратилади: lite mode камерани анимация қилмайди.
        key: ValueKey('${_center.latitude},${_center.longitude},$_zoom,${_pins.length},${_icons.length}'),
        initialCameraPosition: CameraPosition(target: _center, zoom: _zoom),
        liteModeEnabled: true,
        markers: {
          for (final p in _pins)
            Marker(
              markerId: MarkerId(p.id),
              position: LatLng(p.lat, p.lng),
              icon: _icons[p.id] ?? BitmapDescriptor.defaultMarker,
            ),
        },
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
        compassEnabled: false,
        myLocationButtonEnabled: false,
        rotateGesturesEnabled: false,
        scrollGesturesEnabled: false,
        tiltGesturesEnabled: false,
        zoomGesturesEnabled: false,
      );

  Widget _content(AvaColors c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.map_rounded, color: c.brand, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(context.tr('bizmap_home_sub'), style: AvaText.caption.copyWith(color: c.ink3)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Wrap: тор экранда ва катта шрифтда иккинчи тугма пастга тушади (карточка четидан чиқмайди).
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: widget.onOpenMap,
                icon: const Icon(Icons.map_outlined, size: 18),
                label: Text(context.tr('bizmap_open_map')),
              ),
              TextButton(
                onPressed: widget.onAddMine,
                child: Text(context.tr('bizmap_add_mine')),
              ),
            ],
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final radius = BorderRadius.circular(AvaRadius.card);
    return AvaSection(
      moduleId: 'business_map',
      title: context.tr('bizmap_home_title'),
      status: AvaSectionStatus.ready,
      onSeeAll: widget.onOpenMap,
      child: !_showMap
          ? InkWell(
              onTap: widget.onOpenMap,
              borderRadius: radius,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.surface, borderRadius: radius, border: Border.all(color: c.line)),
                child: _content(c),
              ),
            )
          : Container(
              decoration: BoxDecoration(color: c.surface, borderRadius: radius, border: Border.all(color: c.line)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Харита — устида ҳеч нарса йўқ; босилса тўлиқ бизнес харитаси.
                  GestureDetector(
                    key: const ValueKey('home_business_map_card'),
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onOpenMap,
                    child: SizedBox(
                      height: HomeBusinessSection.mapHeight,
                      child: IgnorePointer(child: _map()),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: _content(c),
                  ),
                ],
              ),
            ),
    );
  }
}
