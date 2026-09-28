import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../../realty/realty_tabs.dart';
import 'ava_section.dart';
import 'home_ev_section.dart' show kEvStaticMapEndpoint, evStaticMapHeaders;

/// Бош саҳифадаги ЖОНСИЗ харита расмининг манзили.
///
/// EV бўлимидаги ечим қайта ишлатилади (`home_ev_section.dart:17`):
/// жонли `GoogleMap` бош саҳифада доим турса, хотира ва батареяни
/// беҳуда ейди. Расм `evStaticMap` Cloud Function орқали келади —
/// функция EV'га боғлиқ эмас, оддий Static Maps сўровини йиғади
/// (калит фақат серверда).
///
/// Юбориладиган нуқталар ТАХМИНИЙ (серверда силкитилган, ≈1.2 км) —
/// иловада объектнинг аниқ координатаси умуман йўқ, шунинг учун бу
/// расм пулли ахборотни очиб қўймайди.
String realtyStaticMapUrl({
  required double lat,
  required double lng,
  required int width,
  required int height,
  required List<RealtyListing> listings,
  int zoom = 11,
}) {
  final params = <String>[
    'lat=$lat',
    'lng=$lng',
    'zoom=$zoom',
    'w=$width',
    'h=$height',
    // Даража ранги: рўйхатдаги энг «баланд»и бўйича.
    'color=${_markerColorParam(listings)}',
  ];
  // Сервер 60 тагача қабул қилади — расм жонсиз, пин сони
  // ишлашга таъсир қилмайди (эга қарори, 2026-09-28).
  final pts = listings.take(60).map((r) => '${r.areaLat},${r.areaLng}');
  if (pts.isNotEmpty) {
    params.add('markers=${Uri.encodeQueryComponent(pts.join('|'))}');
  }
  return '$kEvStaticMapEndpoint?${params.join('&')}';
}

String _markerColorParam(List<RealtyListing> listings) {
  final tier = listings.any((r) => r.tier == RealtyTier.urgent)
      ? RealtyTier.urgent
      : listings.any((r) => r.tier == RealtyTier.promo)
          ? RealtyTier.promo
          : RealtyTier.plain;
  final v = RealtyTabs.colorFor(tier).toARGB32() & 0xFFFFFF;
  return '0x${v.toRadixString(16).padLeft(6, '0')}';
}

/// 🏠 Бош саҳифадаги «Кўчмас мулк» бўлими.
///
/// Тузилиши эълон бўлимлари билан бир хил (`home_ads_section.dart`):
/// сарлавҳа + ботиқ майдондаги қаторлар. Фарқи — қатор бошидаги нуқта
/// эълон ДАРАЖАСИ рангида (ОДДИЙ яшил, РЕКЛАМА мандарин, СРОЧНО
/// қизил), шунда лента, харита ва бош саҳифада ранг маъноси бир хил
/// бўлади.
///
/// Туман бўйича филтрланади — бош саҳифа бўлимларининг умумий қоидаси.
class HomeRealtySection extends StatefulWidget {
  const HomeRealtySection({
    super.key,
    required this.onOpenAll,
    required this.onOpenListing,
  });

  final VoidCallback onOpenAll;
  final void Function(RealtyListing listing) onOpenListing;

  static const int limit = 10;

  @override
  State<HomeRealtySection> createState() => _HomeRealtySectionState();
}

class _HomeRealtySectionState extends State<HomeRealtySection> {
  final _repo = RealtyRepository();
  StreamSubscription<List<RealtyListing>>? _sub;

  AvaSectionStatus _status = AvaSectionStatus.loading;
  List<RealtyListing> _items = const [];

  /// `null` — токен ҳали олинмаган; расм фақат шундан кейин сўралади
  /// (`evStaticMap` Firebase ID токенини талаб қилади).
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

  /// Расм маркази — объектларнинг ўртача нуқтаси.
  ({double lat, double lng})? get _center {
    if (_items.isEmpty) return null;
    var lat = 0.0;
    var lng = 0.0;
    for (final r in _items) {
      lat += r.areaLat;
      lng += r.areaLng;
    }
    return (lat: lat / _items.length, lng: lng / _items.length);
  }

  void _listen() {
    _sub?.cancel();
    if (mounted) setState(() => _status = AvaSectionStatus.loading);
    _sub = _repo
        .watchForHome(
          districtId: ServiceConfigHolder.districtId,
          limit: HomeRealtySection.limit,
        )
        .listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _items = list;
          _status = list.isEmpty
              ? AvaSectionStatus.empty
              : AvaSectionStatus.ready;
        });
      },
      onError: (Object e) {
        debugPrint('[HomeRealty] $e');
        if (mounted) setState(() => _status = AvaSectionStatus.error);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AvaSection(
      moduleId: 'realty',
      title: context.tr('home_section_realty'),
      status: _status,
      onSeeAll: widget.onOpenAll,
      onRetry: _listen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AvaInsetPanel(
            child: AvaRowPager(
              rowHeight: AvaRowPager.textRowHeight(context),
              onOpenModule: widget.onOpenAll,
              rows: [
                for (final r in _items)
                  _RealtyRow(
                    listing: r,
                    onTap: () => widget.onOpenListing(r),
                  ),
              ],
            ),
          ),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 8),
            _StaticMapStrip(
              items: _items,
              center: _center,
              headers: _mapHeaders,
              onTap: widget.onOpenAll,
            ),
          ],
        ],
      ),
    );
  }
}

/// Бўлим тагидаги жонсиз харита тасмаси — босилса жонли харита
/// («Кўчмас мулк» экрани) очилади.
class _StaticMapStrip extends StatelessWidget {
  const _StaticMapStrip({
    required this.items,
    required this.center,
    required this.headers,
    required this.onTap,
  });

  static const double _height = 140;

  final List<RealtyListing> items;
  final ({double lat, double lng})? center;
  final Map<String, String>? headers;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final ctr = center;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AvaRadius.card),
        child: SizedBox(
          height: _height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: c.surface2),
              if (ctr != null && headers != null)
                CachedNetworkImage(
                  imageUrl: realtyStaticMapUrl(
                    lat: ctr.lat,
                    lng: ctr.lng,
                    width: 400,
                    height: 140,
                    listings: items,
                  ),
                  httpHeaders: headers,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Center(
                    child: Icon(Icons.map_outlined, color: c.ink3, size: 28),
                  ),
                ),
              // «Нуқталар тахминий» — харидор аниқ жой сотиб олинишини
              // шу ердаёқ билсин.
              Positioned(
                left: 8,
                bottom: 8,
                child: _Badge(
                  text: '${items.length} ${context.tr('realty_package_objects')}'
                      ' · ${context.tr('realty_map_approx_short')}',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line),
      ),
      child: Text(
        text,
        style: AvaText.caption.copyWith(color: c.ink2),
      ),
    );
  }
}

/// Битта объект қатори — даража рангидаги нуқта + сарлавҳа + нарх.
class _RealtyRow extends StatelessWidget {
  const _RealtyRow({required this.listing, required this.onTap});

  final RealtyListing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return InkWell(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: RealtyTabs.colorFor(listing.tier),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              listing.titleOrText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AvaText.feedRow.copyWith(color: c.inkRow),
            ),
          ),
          if (listing.priceText.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              listing.priceText,
              maxLines: 1,
              style: AvaText.feedRow.copyWith(
                color: RealtyTabs.colorFor(listing.tier),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
