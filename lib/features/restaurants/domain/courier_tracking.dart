// Курьерни кузатиш (S6; эга буюртмаси 2026-10-19): курьер қабул қилган буюртманинг жонли жойи ва
// маълумоти мижоз ҳамда ресторан эгасига кўринади.
//
// Қаерда сақланади: `order_courier_live/{orderId}` — ФАҚАТ шу буюртмага тайинланган курьер ёзади, фақат
// буюртма фаол бўлганда (`firestore.rules`); мижоз, ресторан а'золари ва админ ўқийди. Курьернинг умумий
// жойлашуви (`provider_presence`) ёпиқ қолади (40-қоида). Бу файл — соф қоидалар (тестланади): қачон
// кузатиш мумкин, нуқта эскирдими, курьер ёзишни қачон такрорлайди.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/order_model.dart';
import 'restaurant_models.dart';

/// Курьернинг битта нуқтаси.
class CourierLive {
  const CourierLive({required this.lat, required this.lng, this.heading, this.speed, this.updatedAt});

  final double lat;
  final double lng;

  /// Йўналиш (градус, 0…360) ва тезлик (м/с) — бор бўлса.
  final double? heading;
  final double? speed;
  final DateTime? updatedAt;

  /// Нуқтанинг ёши; вақти йўқ (сервер вақти ҳали келмаган) — `null`.
  Duration? ageAt(DateTime now) {
    final t = updatedAt;
    if (t == null) return null;
    final d = now.difference(t);
    return d.isNegative ? Duration.zero : d;
  }

  /// Эскирган: [CourierTracking.staleAfter] дан кўп янгиланмаган (кузатувчи «аниқ эмас» деб кўрсатади).
  bool isStaleAt(DateTime now) {
    final a = ageAt(now);
    return a != null && a > CourierTracking.staleAfter;
  }

  /// Ҳужжатдан хавфсиз ўқиш: координата ё сон бўлмаса — `null` (экран синмайди).
  static CourierLive? fromMap(Map<String, dynamic>? d) {
    if (d == null) return null;
    final lat = d['lat'];
    final lng = d['lng'];
    if (lat is! num || lng is! num) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    double? opt(String k) => d[k] is num ? (d[k] as num).toDouble() : null;
    final u = d['updatedAt'];
    return CourierLive(
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      heading: opt('heading'),
      speed: opt('speed'),
      updatedAt: u is Timestamp ? u.toDate() : (u is DateTime ? u : null),
    );
  }

  /// Нуқтадан берилган жойгача тўғри чизиқ (км).
  double distanceKmTo(double lat2, double lng2) => haversineMeters(lat, lng, lat2, lng2) / 1000;
}

abstract final class CourierTracking {
  /// Шунча вақт янгиланмаса нуқта «эскирган» (курьер ёзиши 8–10 сония орасида; ~9 та ёзув ўтказиб юборилса).
  static const staleAfter = Duration(seconds: 90);

  /// Курьер ёзишлари орасидаги энг кичик вақт ва масофа: арзон (36-қоида) ва етарлича силлиқ.
  static const publishMinInterval = Duration(seconds: 8);
  static const publishMinMeters = 20.0;

  /// Тинч турганда ҳам шунча вақтдан кейин «тирикман» ёзуви (нуқта эскирмасин).
  static const publishHeartbeat = Duration(seconds: 45);

  /// Фаол ҳолатлар — `firestore.rules` `liveOrderActive` ва сервер билан бир хил.
  static const activeStatuses = [
    RestaurantOrderStatus.accepted,
    RestaurantOrderStatus.ready,
    RestaurantOrderStatus.picked,
    RestaurantOrderStatus.arrived,
  ];

  /// Мижоз/ресторан бу буюртмада курьерни кузата оладими: AVA курьери тайинланган ва буюртма фаол.
  static bool canTrack(OrderModel o) =>
      o.isRestaurant &&
      o.deliveryMode == 'ava_courier' &&
      (o.courierId ?? '').trim().isNotEmpty &&
      activeStatuses.contains(o.restaurantStatus);

  /// Курьер янги нуқтани ёзиши керакми (соф қоида): биринчи нуқта — ҳа; акс ҳолда ≥ [publishMinInterval]
  /// ўтган ва ≥ [publishMinMeters] силжиган, ёки тинч туриб [publishHeartbeat] ўтган бўлса.
  static bool shouldPublish({
    required DateTime now,
    required double lat,
    required double lng,
    DateTime? lastAt,
    double? lastLat,
    double? lastLng,
  }) {
    if (lastAt == null || lastLat == null || lastLng == null) return true;
    final since = now.difference(lastAt);
    if (since < publishMinInterval) return false;
    if (since >= publishHeartbeat) return true;
    return haversineMeters(lastLat, lastLng, lat, lng) >= publishMinMeters;
  }
}
