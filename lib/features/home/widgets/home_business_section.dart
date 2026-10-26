import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../services/location_service.dart';
import 'ava_section.dart';

/// Бош саҳифа бўлими «Яқиндаги бизнеслар» (B-7). Firestore'дан маълумот ЮКЛАМАЙДИ: бош саҳифа ҳар очилишида
/// ўқиш бўлмасин (37-банд) — бизнес харитаси ўзи фақат босилганда ўқийди.
/// Дарвоза: `business_map` модули (`HomeModuleGate.showInGrid`).
///
/// Фон — харита (эга, 2026-10-26: «оқ фонни харитага алмаштир, маркази фойдаланувчи жойи»; танлов — «фақат
/// телефонда»): Android'да енгил «расм-харита» (Google lite mode, суриб бўлмайди, босилса тўлиқ харита очилади).
/// Марказ — GPS, фақат рухсат АЛЛАҚАЧОН берилган бўлса ([LocationService.getCoordsIfAllowed] — бош экранда рухсат
/// сўралмайди); бўлмаса бутун мамлакат (бизнес харитаси билан бир хил, эга қарори 2026-10-23). Вебда — аввалги оқ
/// карта (харита юкланиши пулли, вебда жойлашув ҳам аниқланмайди).
class HomeBusinessSection extends StatefulWidget {
  const HomeBusinessSection({
    super.key,
    required this.onOpenMap,
    required this.onAddMine,
    @visibleForTesting this.showMap,
    @visibleForTesting this.locate,
    @visibleForTesting this.mapBuilder,
  });

  final VoidCallback onOpenMap;
  final VoidCallback onAddMine;

  /// Тест учун; `null` — телефонда ҳа, вебда йўқ.
  final bool? showMap;

  /// Тест учун: GPS ўрнига.
  final Future<LocationCoords?> Function()? locate;

  /// Тест учун: GoogleMap (платформа кўриниши) ўрнига.
  final Widget Function(LatLng center, double zoom)? mapBuilder;

  /// Бизнес харитасининг бошланғич нуқтаси билан бир хил (`BusinessMapScreen._countryCenter`, zoom 5.6).
  static const countryCenter = LatLng(41.3, 64.6);
  static const countryZoom = 5.6;
  static const gpsZoom = 14.0;
  /// Харитали карточка баландлиги: пастдаги панел (~100 px) + харита кўринадиган қисм.
  static const mapHeight = 190.0;

  @override
  State<HomeBusinessSection> createState() => _HomeBusinessSectionState();
}

class _HomeBusinessSectionState extends State<HomeBusinessSection> {
  late final bool _showMap = widget.showMap ?? !kIsWeb;
  LatLng _center = HomeBusinessSection.countryCenter;
  double _zoom = HomeBusinessSection.countryZoom;

  @override
  void initState() {
    super.initState();
    if (_showMap) _locate();
  }

  Future<void> _locate() async {
    try {
      final c = await (widget.locate ?? () => const LocationService().getCoordsIfAllowed())();
      if (c == null || !mounted) return;
      setState(() {
        _center = LatLng(c.lat, c.lng);
        _zoom = HomeBusinessSection.gpsZoom;
      });
    } catch (e) {
      debugPrint('[HomeBusinessSection] locate: $e'); // мамлакат маркази қолади
    }
  }

  Widget _map() =>
      widget.mapBuilder?.call(_center, _zoom) ??
      GoogleMap(
        // Марказ ўзгарса (GPS топилди) — қайта яратилади: lite mode камерани анимация қилмайди.
        key: ValueKey('${_center.latitude},${_center.longitude},$_zoom'),
        initialCameraPosition: CameraPosition(target: _center, zoom: _zoom),
        liteModeEnabled: true,
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
      child: InkWell(
        onTap: widget.onOpenMap,
        borderRadius: radius,
        child: !_showMap
            ? Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.surface, borderRadius: radius, border: Border.all(color: c.line)),
                child: _content(c),
              )
            : Container(
                key: const ValueKey('home_business_map_card'),
                // Қатъий баландлик: Stack'да фақат жойлаштирилган болалар — рўйхат ичида баландлик чексиз бўлмасин.
                height: HomeBusinessSection.mapHeight,
                decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: c.line)),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // Харита — фақат фон: босиш карточкага (тўлиқ харита) ўтади.
                    Positioned.fill(child: IgnorePointer(child: _map())),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: c.surface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(AvaRadius.card - 2),
                        ),
                        child: _content(c),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
