import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/courier_status.dart';
import '../../../models/delivery_route.dart';
import '../../../models/order_model.dart';
import '../../../repositories/couriers_repository.dart';
import '../../../repositories/delivery_routes_repository.dart';
import '../../../repositories/orders_repository.dart';

/// Kuryer paneli state mashinasi:
/// - Profil yuklash (SharedPreferences)
/// - Aktiv/tayyor marshrutni topish va order'larini ko'tarish
/// - Online toggle (GPS stream + Firestore heartbeat)
/// - Buyurtmani "yetkazildi" qilish va indeks/marshrut yangilash
class CourierController extends ChangeNotifier {
  CourierController({
    required DeliveryRoutesRepository routesRepo,
    required OrdersRepository ordersRepo,
    required CouriersRepository couriersRepo,
  })  : _routes = routesRepo,
        _orders = ordersRepo,
        _couriers = couriersRepo;

  final DeliveryRoutesRepository _routes;
  final OrdersRepository _orders;
  final CouriersRepository _couriers;

  // ─── State ──────────────────────────────────────────────────────────
  String _courierPhone = '';
  String _courierName = 'Курьер';
  String _fcmToken = '';
  bool _isOnline = false;
  DeliveryRoute? _activeRoute;
  List<OrderModel> _routeOrders = const [];
  int _currentOrderIndex = 0;
  Position? _currentPos;
  String? _errorMessage;
  String? _info;

  String get courierName => _courierName;
  bool get isOnline => _isOnline;
  DeliveryRoute? get activeRoute => _activeRoute;
  List<OrderModel> get routeOrders => _routeOrders;
  int get currentOrderIndex => _currentOrderIndex;
  Position? get currentPos => _currentPos;
  String? get errorMessage => _errorMessage;
  String? get info => _info;
  bool get hasRoute => _activeRoute != null;

  String get courierUid => phoneDigits(_courierPhone);

  // ─── Internals ──────────────────────────────────────────────────────
  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<DeliveryRoute?>? _routeSub;
  bool _disposed = false;

  // ─── Lifecycle ──────────────────────────────────────────────────────

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _courierPhone = prefs.getString('user_phone') ?? '';
    _courierName = prefs.getString('user_name') ?? 'Курьер';
    _fcmToken = prefs.getString('fcm_token') ?? '';
    _safeNotify();
    await loadActiveRoute();
    _subscribeToRoute();
  }

  @override
  void dispose() {
    _disposed = true;
    _routeSub?.cancel();
    _gpsSub?.cancel();
    super.dispose();
  }

  void clearTransient() {
    _errorMessage = null;
    _info = null;
    _safeNotify();
  }

  // ─── Route loading ──────────────────────────────────────────────────

  Future<void> loadActiveRoute() async {
    try {
      final uid = courierUid;
      var route = await _routes.getActiveForCourier(uid);
      route ??= await _routes.getNextReady();
      await _applyRoute(route);
    } catch (e) {
      _errorMessage = 'Хатолик: $e';
      _safeNotify();
    }
  }

  Future<void> _applyRoute(DeliveryRoute? route) async {
    if (route == null) {
      _activeRoute = null;
      _routeOrders = const [];
      _currentOrderIndex = 0;
      _safeNotify();
      return;
    }
    final orders = await _orders.getByIds(route.orderIds);
    _activeRoute = route;
    _routeOrders = orders;
    _currentOrderIndex = route.currentIndex;
    _safeNotify();
  }

  /// Real-time stream — admin reys o'zgartirsa kuryer darhol ko'radi.
  void _subscribeToRoute() {
    _routeSub?.cancel();
    _routeSub = _routes.watchActiveForCourier(courierUid).listen(
      (route) async {
        if (_disposed) return;
        if (route == null) {
          // Stream faqat courierId == men bo'lgan reyslarni kuzatadi;
          // tayinlanmagan `getNextReady` previewini bu yerda o'chirmaymiz.
          final uid = courierUid;
          final cur = _activeRoute;
          if (uid.isNotEmpty &&
              cur != null &&
              cur.courierId == uid) {
            await _applyRoute(null);
          }
          return;
        }
        await _applyRoute(route);
      },
      onError: (_) {},
    );
  }

  // ─── Online toggle ──────────────────────────────────────────────────

  Future<void> toggleOnline() async {
    final newStatus = !_isOnline;
    _isOnline = newStatus;
    _info = newStatus ? '🟢 Онлайн' : '⚫ Оффлайн';
    _safeNotify();

    if (newStatus) {
      final prefs = await SharedPreferences.getInstance();
      _fcmToken = prefs.getString('fcm_token') ?? '';
      _startGpsStream();
      if (_activeRoute == null) await loadActiveRoute();
      final route = _activeRoute;
      if (route != null && route.isReady) {
        final claimed = await _routes.startRoute(
          routeId: route.id,
          courierId: courierUid,
        );
        if (!claimed) {
          _info = '⚠️ Reys band qilindi. Boshqa reys qidirilmoqda...';
          _safeNotify();
          await loadActiveRoute();
          final nextRoute = _activeRoute;
          if (nextRoute != null && nextRoute.isReady) {
            await _routes.startRoute(
              routeId: nextRoute.id,
              courierId: courierUid,
            );
            await loadActiveRoute();
          }
        } else {
          await loadActiveRoute();
        }
      }
    } else {
      await _gpsSub?.cancel();
      _gpsSub = null;
      try {
        await _couriers.goOffline(courierUid);
      } catch (_) {}
    }
  }

  void _startGpsStream() {
    _gpsSub?.cancel();
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 20),
    ).listen((pos) async {
      if (_disposed) return;
      _currentPos = pos;
      _safeNotify();
      try {
        await _couriers.upsertStatus(CourierStatus(
          uid: courierUid,
          name: _courierName,
          phone: _courierPhone,
          isOnline: true,
          lat: pos.latitude,
          lng: pos.longitude,
          fcmToken: _fcmToken,
        ));
      } catch (_) {
        // Heartbeat xatosini yutamiz — keyingi tick davom etaveradi.
      }
    });
  }

  // ─── Deliver ────────────────────────────────────────────────────────

  Future<void> markDelivered(String orderId) async {
    final route = _activeRoute;
    if (route == null) return;
    try {
      await _orders.markDelivered(
          orderId: orderId, courierId: courierUid);

      final nextIndex = _currentOrderIndex + 1;
      await _routes.advanceIndex(route.id, nextIndex);

      if (nextIndex >= _routeOrders.length) {
        await _routes.completeRoute(route.id);
        _activeRoute = null;
        _routeOrders = const [];
        _currentOrderIndex = 0;
        _info = '🎉 Маршрут якунланди!';
      } else {
        _currentOrderIndex = nextIndex;
        _info = '✅ Етказилди!';
      }
      _safeNotify();
    } catch (e) {
      _errorMessage = 'Хатолик: $e';
      _safeNotify();
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }
}
