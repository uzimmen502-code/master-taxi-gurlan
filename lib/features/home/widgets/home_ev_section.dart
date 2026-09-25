import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/ev_charging_station.dart';
import '../../../repositories/ev_station_repository.dart';
import 'ava_chip.dart';
import 'ava_section.dart';

/// Google Static Maps — бош саҳифадаги ЖОНСИЗ харита расми.
///
/// Тавсиф талаби: «Асосий экранда хаританинг статик расми туради. Жонли
/// харита фақат босилганда очилади». Жонли `GoogleMap` виджети оғир —
/// у бош саҳифада доим турса, хотира ва батареяни беҳуда ейди.
String staticMapUrl({
  required String apiKey,
  required double lat,
  required double lng,
  required int width,
  required int height,
  int zoom = 12,
  List<EvChargingStation> markers = const [],
}) {
  final params = <String>[
    'center=$lat,$lng',
    'zoom=$zoom',
    'size=${width}x$height',
    'scale=2',
    'maptype=roadmap',
    'key=$apiKey',
  ];
  // Маркерлар — кўпи билан 10 та, акс ҳолда URL узайиб кетади.
  final pts = markers.take(10).map((s) => '${s.latitude},${s.longitude}');
  if (pts.isNotEmpty) {
    params.add('markers=size:small%7Ccolor:0x1E4FD8%7C${pts.join('%7C')}');
  }
  return 'https://maps.googleapis.com/maps/api/staticmap?${params.join('&')}';
}

/// 10-бўлим: EV зарядлаш станциялари.
class HomeEvSection extends StatefulWidget {
  const HomeEvSection({
    super.key,
    required this.apiKey,
    required this.onOpenMap,
  });

  /// Google Maps калити (`AndroidManifest` даги билан бир хил).
  final String apiKey;

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

  @override
  void initState() {
    super.initState();
    _listen();
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
                    if (center != null && widget.apiKey.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: staticMapUrl(
                          apiKey: widget.apiKey,
                          lat: center.latitude,
                          lng: center.longitude,
                          width: 400,
                          height: 140,
                          markers: _items,
                        ),
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
