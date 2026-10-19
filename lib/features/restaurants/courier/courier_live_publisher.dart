// Курьернинг жонли нуқтасини ёзиб турувчи ПАСТ-ВАЗНЛИ виджет (S6): курьер маршрутидаги фаол ресторан
// буюртмаси карточкасига қўйилади; карточка кўриниб турганда ёзади, йўқолганда (буюртма тугади/маршрут
// ёпилди) тўхтайди. Қоида (қачон ёзиш) — соф `CourierTracking.shouldPublish`; ёзиш — `order_courier_live`
// (фақат тайинланган курьер, `firestore.rules`). Хато (рухсат йўқ, тармоқ) асосий ишни тўхтатмайди.
//
// Фон: Android иловада буюртма CourierLiveBackground орқали ишлаб турган GPS хизматига (foreground service)
// топширилади — илова ёпилса ҳам нуқта ёзилаверади; хизмат тирик бўлса бу виджет қўш ёзмайди. Веб/тест/iOS
// да (фон йўқ) ёзув фақат шу виджетдан, илова очиқ турганда.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../services/courier_live_background.dart';
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

  /// Фон хизмати фақат ҳақиқий жойлашув манбасида; тестда (positions берилган) илова ичидаги оқимгина.
  bool get _useBackground => widget.positions == null;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant CourierLivePublisher old) {
    super.didUpdateWidget(old);
    if (old.orderId != widget.orderId || old.courierId != widget.courierId) {
      _stop(old.orderId);
      _lastAt = _lastLat = _lastLng = null;
      _start();
    }
  }

  void _start() {
    if (_useBackground) CourierLiveBackground.register(widget.orderId, widget.courierId);
    _sub = (widget.positions ?? defaultLivePositions)().listen(_onPosition, onError: (Object _) {});
  }

  void _stop([String? orderId]) {
    _sub?.cancel();
    _sub = null;
    if (_useBackground) CourierLiveBackground.unregister(orderId ?? widget.orderId);
  }

  Future<void> _onPosition(LivePosition p) async {
    if (_writing) return;
    // Фон хизмати ёзиб турса — қўш ёзув керак эмас (36-қоида); хизмат ўчиб қолса, ёзув шу ерда давом этади.
    if (_useBackground && await CourierLiveBackground.serviceCovers(clock: widget.clock)) return;
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
