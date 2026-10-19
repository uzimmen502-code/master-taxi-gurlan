// Курьернинг жонли нуқтасини ёзиб турувчи ПАСТ-ВАЗНЛИ виджет (S6): курьер маршрутидаги фаол ресторан
// буюртмаси карточкасига қўйилади; карточка кўриниб турганда ёзади, йўқолганда (буюртма тугади/маршрут
// ёпилди) тўхтайди. Қоида (қачон ёзиш) — соф `CourierTracking.shouldPublish`; ёзиш — `order_courier_live`
// (фақат тайинланган курьер, `firestore.rules`). Хато (рухсат йўқ, тармоқ) асосий ишни тўхтатмайди.
//
// Чегара (ҳозирча): жойлашув оқими иловада ОЧИҚ турган пайтдагина ишлайди (фон хизмати йўқ) — курьер
// иловани ёпса нуқта янгиланмай «эскирган» бўлади ва кузатувчи шуни кўради.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../data/restaurants_repository.dart';
import '../domain/courier_tracking.dart';

/// Битта жойлашув ўлчови (тест учун содда тур).
class LivePosition {
  const LivePosition({required this.lat, required this.lng, this.heading, this.speed, this.accuracy});

  final double lat;
  final double lng;
  final double? heading;
  final double? speed;
  final double? accuracy;
}

/// Стандарт манба: `geolocator` оқими (рухсат бўлмаса бўш оқим).
Stream<LivePosition> defaultLivePositions() async* {
  try {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).map((p) => LivePosition(
          lat: p.latitude,
          lng: p.longitude,
          heading: p.heading >= 0 && p.heading <= 360 ? p.heading : null,
          speed: p.speed >= 0 ? p.speed : null,
          accuracy: p.accuracy >= 0 ? p.accuracy : null,
        ));
  } catch (_) {
    // GPS ўчиқ/рад — жимгина; кузатувчи «жойлашув йўқ» кўради.
  }
}

class CourierLivePublisher extends StatefulWidget {
  const CourierLivePublisher({
    super.key,
    required this.orderId,
    required this.courierId,
    required this.repository,
    this.positions,
    this.clock,
  });

  final String orderId;

  /// Курьернинг ўз идентификатори (буюртмадаги `courierId`).
  final String courierId;
  final RestaurantsRepository repository;

  /// Тест учун жойлашув манбаи ва соат; бўш бўлса ҳақиқий.
  final Stream<LivePosition> Function()? positions;
  final DateTime Function()? clock;

  @override
  State<CourierLivePublisher> createState() => _CourierLivePublisherState();
}

class _CourierLivePublisherState extends State<CourierLivePublisher> {
  StreamSubscription<LivePosition>? _sub;
  DateTime? _lastAt;
  double? _lastLat;
  double? _lastLng;
  bool _writing = false;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant CourierLivePublisher old) {
    super.didUpdateWidget(old);
    if (old.orderId != widget.orderId || old.courierId != widget.courierId) {
      _stop();
      _lastAt = _lastLat = _lastLng = null;
      _start();
    }
  }

  void _start() {
    _sub = (widget.positions ?? defaultLivePositions)().listen(_onPosition, onError: (Object _) {});
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _onPosition(LivePosition p) async {
    if (_writing) return;
    final now = _now;
    if (!CourierTracking.shouldPublish(now: now, lat: p.lat, lng: p.lng, lastAt: _lastAt, lastLat: _lastLat, lastLng: _lastLng)) return;
    _writing = true;
    try {
      await widget.repository.publishCourierLive(
        widget.orderId,
        courierId: widget.courierId,
        lat: p.lat,
        lng: p.lng,
        heading: p.heading,
        speed: p.speed,
        accuracy: p.accuracy,
      );
      _lastAt = now;
      _lastLat = p.lat;
      _lastLng = p.lng;
    } catch (_) {
      // Рухсат/тармоқ хатоси: кейинги нуқтада қайта уриниш (навбат бузилмайди).
    } finally {
      _writing = false;
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
