import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/ev_charging_station.dart';
import '../../../repositories/ev_station_repository.dart';
import '../../../services/geo_math_service.dart';
import '../../../services/location_service.dart';
import 'ava_chip.dart';
import 'ava_section.dart';

/// Бош саҳифадаги ЖОНСИЗ харита расмининг манзили.
///
/// Тавсиф талаби: «Асосий экранда хаританинг статик расми туради. Жонли
/// харита фақат босилганда очилади». Жонли `GoogleMap` виджети оғир —
/// у бош саҳифада доим турса, хотира ва батареяни беҳуда ейди.
///
/// Расм Google'дан ТЎҒРИДАН-ТЎҒРИ олинмайди, балки `evStaticMap` Cloud
/// Function орқали келади. Сабаби: Maps Static API — веб-хизмат, унга
/// Android'га чекланган калит ярамайди, чекловсиз калитни эса APK ичига
/// солиб бўлмайди (уни ажратиб олиб, ҳисобимизга сўров юбориш мумкин).
/// Шунинг учун калит фақат серверда — `functions/.env`да.
String staticMapUrl({
  required double lat,
  required double lng,
  required int width,
  required int height,
  int zoom = 12,
  List<EvChargingStation> markers = const [],
}) {
  final params = <String>[
    'lat=$lat',
    'lng=$lng',
    'zoom=$zoom',
    'w=$width',
    'h=$height',
  ];
  // Маркерлар — кўпи билан 10 та (сервер ҳам шунча қабул қилади).
  final pts = markers.take(10).map((s) => '${s.latitude},${s.longitude}');
  if (pts.isNotEmpty) {
    params.add('markers=${Uri.encodeQueryComponent(pts.join('|'))}');
  }
  return '$kEvStaticMapEndpoint?${params.join('&')}';
}

/// Бош саҳифа блоки нимани кўрсатади (геo 4-босқич, «яқиндагилар»).
///
/// Координата бор: марказ — фойдаланувчи, маркерлар — энг яқин 10 та,
/// саноқ — [radiusKm] ичидагилар (ичида бўлмаса — марказ энг яқин станция,
/// саноқ бутун рўйхат). Координата йўқ — аввалги ҳолат (биринчи станция,
/// бутун рўйхат). Жонли харита ўзгармайди — эга қарори 2026-09-22: барча
/// нуқталар кўринади.
class EvHomeView {
  const EvHomeView({
    required this.centerLat,
    required this.centerLng,
    required this.markers,
    required this.counted,
    required this.nearby,
  });

  final double centerLat;
  final double centerLng;
  final List<EvChargingStation> markers;
  final List<EvChargingStation> counted;

  /// Саноқ [radiusKm] ичидагилар бўйича.
  final bool nearby;

  static const radiusKm = 20.0;

  static EvHomeView? of(
    List<EvChargingStation> all, {
    double? lat,
    double? lng,
  }) {
    if (all.isEmpty) return null;
    if (lat == null || lng == null) {
      return EvHomeView(
        centerLat: all.first.latitude,
        centerLng: all.first.longitude,
        markers: all,
        counted: all,
        nearby: false,
      );
    }
    final rows = [
      for (final s in all)
        (s, const GeoMathService().haversineKm(lat, lng, s.latitude, s.longitude)),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    final sorted = [for (final r in rows) r.$1];
    final inRadius = [for (final r in rows) if (r.$2 <= radiusKm) r.$1];
    if (inRadius.isEmpty) {
      return EvHomeView(
        centerLat: sorted.first.latitude,
        centerLng: sorted.first.longitude,
        markers: sorted,
        counted: all,
        nearby: false,
      );
    }
    return EvHomeView(
      centerLat: lat,
      centerLng: lng,
      markers: inRadius,
      counted: inRadius,
      nearby: true,
    );
  }
}

/// `evStaticMap` Cloud Function (us-central1).
const kEvStaticMapEndpoint =
    'https://us-central1-master-taxi-gurlan.cloudfunctions.net/evStaticMap';

/// Расм сўровига қўшиладиган сарлавҳа — функция Firebase ID токенини
/// талаб қилади (фақат илова фойдаланувчилари).
Future<Map<String, String>> evStaticMapHeaders() async {
  try {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) return const {};
    return {'Authorization': 'Bearer $token'};
  } catch (_) {
    return const {};
  }
}

/// 10-бўлим: EV зарядлаш станциялари.
class HomeEvSection extends StatefulWidget {
  const HomeEvSection({
    super.key,
    required this.onOpenMap,
    this.userLat,
    this.userLng,
    this.locate,
  });

  /// Босилганда ЖОНЛИ харита экрани очилади.
  final VoidCallback onOpenMap;

  /// Профил манзили (захира); GPS рухсати бўлса GPS устун.
  final double? userLat;
  final double? userLng;

  /// Стандарт — рухсат сўрамайдиган [LocationService.getCoordsIfAllowed].
  final Future<LocationCoords?> Function()? locate;

  @override
  State<HomeEvSection> createState() => _HomeEvSectionState();
}

class _HomeEvSectionState extends State<HomeEvSection> {
  final _repo = EvStationRepository();
  StreamSubscription<List<EvChargingStation>>? _sub;

  AvaSectionStatus _status = AvaSectionStatus.loading;
  List<EvChargingStation> _items = const [];

  /// `null` — токен ҳали олинмаган; расм фақат шундан кейин сўралади.
  Map<String, String>? _mapHeaders;

  /// GPS'дан олинган нуқта (бўлса) — профилдан устун.
  LocationCoords? _gps;

  double? get _lat => _gps?.lat ?? widget.userLat;
  double? get _lng => _gps?.lng ?? widget.userLng;

  @override
  void initState() {
    super.initState();
    _listen();
    _loadMapHeaders();
    _loadGps();
  }

  Future<void> _loadGps() async {
    final locate = widget.locate ?? const LocationService().getCoordsIfAllowed;
    final c = await locate();
    if (mounted && c != null) setState(() => _gps = c);
  }

  Future<void> _loadMapHeaders() async {
    final h = await evStaticMapHeaders();
    if (mounted) setState(() => _mapHeaders = h);
  }

  void _listen() {
    _sub?.cancel();
    if (mounted) setState(() => _status = AvaSectionStatus.loading);
    _sub = _repo.watchAllActive().listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _items = list;
          _status =
              list.isEmpty ? AvaSectionStatus.empty : AvaSectionStatus.ready;
        });
      },
      onError: (Object e) {
        // Меҳмон (анонимный) фойдаланувчида `permission-denied` —
        // станциялар фақат телефон тасдиқлангандан кейин кўринади.
        debugPrint('[HomeEv] $e');
        if (mounted) setState(() => _status = AvaSectionStatus.error);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  ({int free, int busy, int unknown}) _countsOf(List<EvChargingStation> list) {
    var free = 0;
    var busy = 0;
    var unknown = 0;
    for (final s in list) {
      switch (s.occupancyState) {
        case 'free':
          free++;
        case 'busy':
          busy++;
        default:
          unknown++;
      }
    }
    return (free: free, busy: busy, unknown: unknown);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final view = EvHomeView.of(_items, lat: _lat, lng: _lng);
    final counts = _countsOf(view?.counted ?? const []);

    return AvaSection(
      moduleId: 'ev_charging',
      title: context.tr('home_module_ev_charging'),
      status: _status,
      onSeeAll: widget.onOpenMap,
      onRetry: _listen,
      skeletonRows: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: widget.onOpenMap,
            borderRadius: BorderRadius.circular(AvaRadius.card),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AvaRadius.card),
              child: SizedBox(
                height: 140,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: c.surface2),
                    if (view != null && _mapHeaders != null)
                      CachedNetworkImage(
                        imageUrl: staticMapUrl(
                          lat: view.centerLat,
                          lng: view.centerLng,
                          width: 400,
                          height: 140,
                          markers: view.markers,
                        ),
                        httpHeaders: _mapHeaders,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Center(
                          child: Icon(Icons.map_outlined,
                              color: c.ink3, size: 28),
                        ),
                      ),
                    // «Босилса жонли харита очилади» белгиси.
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius:
                              BorderRadius.circular(AvaRadius.chip),
                          border: Border.all(color: c.line),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.open_in_full_rounded,
                                  size: 12, color: c.brand),
                              const SizedBox(width: 4),
                              Text(
                                context.tr('home_ev_open_map'),
                                style:
                                    AvaText.caption.copyWith(color: c.brand),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AvaSpace.gap),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              // Саноқ яқиндагилар бўйича эканини айтамиз (бутун республика
              // эмас).
              if (view != null && view.nearby)
                AvaChip(
                  key: const ValueKey('home_ev_nearby'),
                  label: context.tr('home_ev_nearby_radius').replaceAll(
                      '{n}', EvHomeView.radiusKm.round().toString()),
                ),
              if (counts.free > 0)
                AvaChip(
                  label: '${context.tr('home_ev_free')}: ${counts.free}',
                  tone: AvaChipTone.ok,
                ),
              if (counts.busy > 0)
                AvaChip(
                  label: '${context.tr('home_ev_busy')}: ${counts.busy}',
                  tone: AvaChipTone.warn,
                ),
              if (counts.unknown > 0)
                AvaChip(
                  label:
                      '${context.tr('home_ev_unknown')}: ${counts.unknown}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}
