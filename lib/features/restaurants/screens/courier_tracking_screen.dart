// Курьерни кузатиш экрани (S6; эга буюртмаси 2026-10-19): мижоз ва ресторан (уй ошпази) эгаси курьер
// маълумотини ва ЖОНЛИ ҳаракатини харитада кўради. Маълумот: буюртма (`watchOrder`: исм, ҳолат) ва
// `order_courier_live/{orderId}` (нуқта). Мантиқ — соф (`CourierTracking`, `CourierLive`); харита —
// алмаштириладиган (`mapBuilder`): тестда Google Maps platform view керак эмас.
//
// Ҳолатлар: курьер жойи ҳали йўқ («у йўлга чиққач кўринади»); нуқта эскирган (>90 с — «янгиланмаяпти»);
// буюртма фаол эмас (етказилди/бекор — «кузатув тугади»). Курьернинг умумий жойлашуви кўрсатилмайди —
// фақат шу буюртма давомидаги нуқта (40-қоида).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../models/order_model.dart';
import '../data/restaurants_repository.dart';
import '../domain/courier_tracking.dart';
import '../domain/restaurant_models.dart';
import '../widgets/restaurant_row.dart' show formatDistanceLabel;

/// Харитага берилади: рестораннинг ва етказиш манзилининг (бор бўлса) нуқталари ва курьернинг жонли нуқтаси.
class CourierMapData {
  const CourierMapData({this.restaurant, this.restaurantName = '', this.destination, this.courier});

  final LatLng? restaurant;
  final String restaurantName;
  final LatLng? destination;
  final CourierLive? courier;
}

typedef CourierMapBuilder = Widget Function(BuildContext context, CourierMapData data);

class CourierTrackingScreen extends StatefulWidget {
  const CourierTrackingScreen({
    super.key,
    required this.orderId,
    required this.repository,
    this.initial,
    this.mapBuilder,
    this.clock,
  });

  final String orderId;
  final RestaurantsRepository repository;

  /// Босилган пайтдаги буюртма (дарҳол кўрсатиш учун); жонли ҳолат `watchOrder` дан.
  final OrderModel? initial;
  final CourierMapBuilder? mapBuilder;

  /// Тест учун соат.
  final DateTime Function()? clock;

  @override
  State<CourierTrackingScreen> createState() => _CourierTrackingScreenState();
}

class _CourierTrackingScreenState extends State<CourierTrackingScreen> {
  late final Stream<OrderModel?> _order = widget.repository.watchOrder(widget.orderId);
  late final Stream<CourierLive?> _live = widget.repository.watchCourierLive(widget.orderId);
  Timer? _tick;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    // «N сония олдин» ёзуви ўзи янгиланиб турсин (нуқта келмаса ҳам).
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface,
        elevation: 0,
        title: Text(context.tr('restaurants_track_title'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
      ),
      body: StreamBuilder<OrderModel?>(
        stream: _order,
        initialData: widget.initial,
        builder: (context, os) {
          final o = os.data;
          if (o == null) {
            return Center(child: os.connectionState == ConnectionState.waiting ? const CircularProgressIndicator() : _Notice(text: context.tr('home_section_error')));
          }
          if (!CourierTracking.canTrack(o)) {
            return Center(child: _Notice(text: context.tr('restaurants_track_finished'), icon: Icons.check_circle_outline_rounded));
          }
          return StreamBuilder<CourierLive?>(
            stream: _live,
            builder: (context, ls) => _body(context, o, ls.data),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, OrderModel o, CourierLive? live) {
    final data = CourierMapData(
      restaurant: o.hasRestaurantCoordinates ? LatLng(o.restaurantLat!, o.restaurantLng!) : null,
      restaurantName: o.restaurantName,
      destination: o.hasCoordinates ? LatLng(o.lat!, o.lng!) : null,
      courier: live,
    );
    final map = (widget.mapBuilder ?? _defaultMap)(context, data);
    return Column(
      children: [
        Expanded(child: KeyedSubtree(key: const ValueKey('track-map'), child: map)),
        _InfoPanel(order: o, live: live, now: _now),
      ],
    );
  }

  static Widget _defaultMap(BuildContext context, CourierMapData d) => _TrackMap(data: d);
}

/// Курьер маълумоти ва ҳолати (харита остида).
class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.order, required this.live, required this.now});

  final OrderModel order;
  final CourierLive? live;
  final DateTime now;

  String _age(BuildContext context, Duration a) {
    if (a.inSeconds < 60) return context.tr('restaurants_track_updated').replaceAll('{s}', '${a.inSeconds}');
    return context.tr('restaurants_track_updated_min').replaceAll('{m}', '${a.inMinutes}');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final l = live;
    final name = order.courierName.trim().isEmpty ? context.tr('restaurants_courier_default_name') : order.courierName.trim();
    final stale = l != null && l.isStaleAt(now);
    final age = l?.ageAt(now);
    final dest = order.hasCoordinates && l != null ? l.distanceKmTo(order.lat!, order.lng!) : null;
    return Material(
      color: c.surface,
      elevation: 6,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.delivery_dining_rounded, color: c.brandText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, key: const ValueKey('track-name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
                        Text(context.tr(RestaurantOrderStatus.labelKey(order.restaurantStatus)), style: TextStyle(fontSize: 12, color: c.ink2)),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    key: const ValueKey('track-call'),
                    tooltip: context.tr('restaurants_track_call'),
                    icon: const Icon(Icons.call_rounded),
                    onPressed: (order.courierId ?? '').isEmpty ? null : () => callPhone(order.courierId!),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (l == null)
                _line(c, Icons.location_searching_rounded, context.tr('restaurants_track_waiting'), c.ink2, const ValueKey('track-waiting'))
              else if (stale)
                _line(c, Icons.signal_wifi_statusbar_connected_no_internet_4_rounded, context.tr('restaurants_track_stale'), c.warn, const ValueKey('track-stale'))
              else if (age != null)
                _line(c, Icons.my_location_rounded, _age(context, age), c.ok, const ValueKey('track-updated')),
              if (dest != null && !stale)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _line(c, Icons.flag_outlined, context.tr('restaurants_track_distance').replaceAll('{km}', formatDistanceLabel(context, dest)), c.ink, const ValueKey('track-distance')),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(AvaColors c, IconData icon, String text, Color color, Key key) => Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(text, key: key, style: TextStyle(fontSize: 13, color: color))),
        ],
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.icon = Icons.info_outline_rounded});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: c.ink3),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, key: const ValueKey('track-notice'), style: TextStyle(fontSize: 14, color: c.ink2)),
        ],
      ),
    );
  }
}

/// Google Maps: ресторан (тўқ сариқ), манзил (қизил), курьер (кўк); курьер ҳаракатланса камера унга эргашади.
class _TrackMap extends StatefulWidget {
  const _TrackMap({required this.data});

  final CourierMapData data;

  @override
  State<_TrackMap> createState() => _TrackMapState();
}

class _TrackMapState extends State<_TrackMap> {
  GoogleMapController? _controller;

  LatLng get _center {
    final d = widget.data;
    final cr = d.courier;
    if (cr != null) return LatLng(cr.lat, cr.lng);
    return d.restaurant ?? d.destination ?? const LatLng(41.3111, 69.2797);
  }

  @override
  void didUpdateWidget(covariant _TrackMap old) {
    super.didUpdateWidget(old);
    final a = old.data.courier;
    final b = widget.data.courier;
    if (b != null && (a == null || a.lat != b.lat || a.lng != b.lng)) {
      _controller?.animateCamera(CameraUpdate.newLatLng(LatLng(b.lat, b.lng)));
    }
  }

  Set<Marker> _markers() {
    final d = widget.data;
    return {
      if (d.restaurant != null)
        Marker(
          markerId: const MarkerId('restaurant'),
          position: d.restaurant!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(title: d.restaurantName),
        ),
      if (d.destination != null)
        Marker(
          markerId: const MarkerId('destination'),
          position: d.destination!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      if (d.courier != null)
        Marker(
          markerId: const MarkerId('courier'),
          position: LatLng(d.courier!.lat, d.courier!.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          rotation: d.courier!.heading ?? 0,
          zIndexInt: 2,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: _center, zoom: 14),
      markers: _markers(),
      onMapCreated: (c) => _controller = c,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: true,
    );
  }
}
