import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/ev_charging_station.dart';
import '../../../repositories/ev_station_repository.dart';
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
  const HomeEvSection({super.key, required this.onOpenMap});

  /// Босилганда ЖОНЛИ харита экрани очилади.
  final VoidCallback onOpenMap;

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

  @override
  void initState() {
    super.initState();
    _listen();
    _loadMapHeaders();
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

  ({int free, int busy, int unknown}) get _counts {
    var free = 0;
    var busy = 0;
    var unknown = 0;
    for (final s in _items) {
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
    final counts = _counts;
    final center = _items.isEmpty ? null : _items.first;

    return AvaSection(
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
                    if (center != null && _mapHeaders != null)
                      CachedNetworkImage(
                        imageUrl: staticMapUrl(
                          lat: center.latitude,
                          lng: center.longitude,
                          width: 400,
                          height: 140,
                          markers: _items,
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
