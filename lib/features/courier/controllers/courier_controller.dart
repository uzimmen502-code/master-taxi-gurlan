import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
// `canonicalUserId` ва `DemandModule` — ядронинг иловадаги жуфти.
// Такрорланмасин (4-қоида): шу иккиси ядро билан бир хил бўлиши шарт.
import '../../demand_offer/domain/canonical_id.dart';
import '../../demand_offer/domain/demand_enums.dart';
import '../../../models/courier_status.dart';
import '../../../models/delivery_route.dart';
import '../../../models/order_model.dart';
import '../../../models/provider_presence.dart';
import '../../../repositories/couriers_repository.dart';
import '../../../repositories/delivery_routes_repository.dart';
import '../../../repositories/orders_repository.dart';
import '../../../repositories/provider_presence_repository.dart';
import '../../../services/courier_route_service.dart';
import '../../../services/order_payment_service.dart';
import '../../restaurants/courier/restaurant_courier_logic.dart';
import '../../restaurants/data/restaurants_repository.dart';

/// Kuryer paneli — marshrut + post-paid to'lov.
class CourierController extends ChangeNotifier {
  /// Modal bottom sheet Provider scope dan tashqarida — tasdiq ekrani uchun.
  static CourierController? active;

  CourierController({
    required DeliveryRoutesRepository routesRepo,
    required OrdersRepository ordersRepo,
    required CouriersRepository couriersRepo,
    ProviderPresenceRepository? presenceRepo,
    RestaurantsRepository? restaurantsRepo,
  })  : _routes = routesRepo,
        _orders = ordersRepo,
        _couriers = couriersRepo,
        _presence = presenceRepo ?? ProviderPresenceRepository(),
        _restaurantsRepo = restaurantsRepo;

  final DeliveryRoutesRepository _routes;
  final OrdersRepository _orders;
  final CouriersRepository _couriers;
  final RestaurantsRepository? _restaurantsRepo;

  /// Ресторан буюртмалари (Б3): callable'лар ва жонли буюртма оқими.
  late final RestaurantsRepository restaurants =
      _restaurantsRepo ?? RestaurantsRepository();

  /// 13.6.3 — ЎТИШ ДАВРИ: `couriers` ва `provider_presence` ИККАЛАСИГА
  /// ҳам ёзилади.
  ///
  /// Нега иккаласига: `couriers`ни ҳозир админ панели ва иккита Cloud
  /// Function ўқияпти (push токен), `provider_presence`ни эса янги
  /// matching ядроси (`sources/presence_geo.js`). Бирини ўчириб
  /// иккинчисига ўтиш — иловани янгилаган ва янгиламаган курьерлар
  /// бир вақтда ишлаётган пайтда кимнинг онлайн экани ЙЎҚОЛИШИ
  /// демакдир (15-қоида руҳи). Шунинг учун аввал иккаласи, кейин
  /// (4-босқич) ўқувчилар кўчирилади, сўнг `couriers` чиқарилади.
  final ProviderPresenceRepository _presence;
  final CourierRouteService _routeService = CourierRouteService();

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
  String? _pendingPaymentOrderId;

  String get courierName => _courierName;
  bool get isOnline => _isOnline;
  DeliveryRoute? get activeRoute => _activeRoute;
  List<OrderModel> get routeOrders => _routeOrders;
  int get currentOrderIndex => _currentOrderIndex;
  Position? get currentPos => _currentPos;
  String? get errorMessage => _errorMessage;
  String? get info => _info;
  bool get hasRoute => _activeRoute != null;

  /// `couriers/{uid}` калити — ХОМ рақамлар (эски ёзувлар шундай).
  String get courierUid => phoneDigits(_courierPhone);

  /// `provider_presence/{uid}` калити — КАНОН 12 хонали шакл.
  ///
  /// Ядро фақат шу шаклни ёзади ва ўқийди. Телефон нотўғри бўлса бўш
  /// сатр қайтади ва presence ёзуви умуман қилинмайди.
  String get presenceUid => canonicalUserId(_courierPhone);

  StreamSubscription<Position>? _gpsSub;
  StreamSubscription<DeliveryRoute?>? _routeSub;
  bool _disposed = false;
  bool _advancingRoute = false;

  /// Тўлов/етказилди бўлган, лекин reys индекси ҳали ўтмаган буюртма.
  /// Ресторан буюртмаси — фақат якуний `restaurantStatus`: олдиндан
  /// тўлангани етказилгунча `paid` бўлади, у ҳали тугамаган.
  static bool isOrderFinalized(OrderModel o) {
    if (o.isRestaurant) return isRestaurantOrderFinalized(o);
    return o.effectivePayment == 'paid' ||
        o.effectiveFulfillment == 'completed' ||
        o.status == 'delivered';
  }

  OrderModel? get currentOrder {
    if (_currentOrderIndex < 0 || _currentOrderIndex >= _routeOrders.length) {
      return null;
    }
    return _routeOrders[_currentOrderIndex];
  }

  Future<void> init() async {
    active = this;
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
    if (active == this) active = null;
    _routeSub?.cancel();
    _gpsSub?.cancel();
    super.dispose();
  }

  void clearTransient() {
    _errorMessage = null;
    _info = null;
    _safeNotify();
  }

  Future<void> loadActiveRoute() async {
    try {
      final uid = courierUid;
      var route = await _routes.getActiveForCourier(uid);
      if (route == null && _courierPhone.trim().isNotEmpty) {
        // Хавфсизлик тўри: етим қолган in_delivery буюртмаларни тиклаш.
        final recovered =
            await _routeService.recoverOrphanRoute(courierPhone: _courierPhone);
        if (recovered.revived) {
          route = await _routes.getActiveForCourier(uid);
          _info = 'courier_info_orders_revived';
        }
      }
      await _applyRoute(route);
    } catch (e) {
      _errorMessage = 'courier_error_generic|$e';
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
    // Бажариладиган бекат қолмаган «фаол» маршрут (масалан, ресторан
    // олинган охирги буюртмани рад этган) — ёпамиз; акс ҳолда курьер
    // бўш маршрутда қолиб, янгисини ололмайди.
    if (route.isActive && route.currentIndex >= route.orderIds.length) {
      try {
        await _routes.completeRoute(route.id);
      } catch (_) {}
      await _applyRoute(null);
      return;
    }
    final orders = await _orders.getByIds(route.orderIds);
    _activeRoute = route;
    _routeOrders = orders;
    _currentOrderIndex = route.currentIndex;
    _safeNotify();
    await _syncStuckCurrentOrderIfNeeded();
  }

  void _subscribeToRoute() {
    _routeSub?.cancel();
    _routeSub = _routes.watchActiveForCourier(courierUid).listen(
      (route) async {
        if (_disposed) return;
        if (route == null) {
          final uid = courierUid;
          final cur = _activeRoute;
          if (uid.isNotEmpty && cur != null && cur.courierId == uid) {
            await _applyRoute(null);
          }
          return;
        }
        await _applyRoute(route);
      },
      onError: (_) {},
    );
  }

  Future<void> toggleOnline() async {
    final newStatus = !_isOnline;
    _isOnline = newStatus;
    _info = newStatus ? 'courier_info_online' : 'courier_info_offline';
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
          _info = 'courier_reys_busy';
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
      try {
        await _presence.goOffline(presenceUid);
      } catch (_) {}
    }
  }

  void _startGpsStream() {
    _gpsSub?.cancel();
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      ),
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
      } catch (_) {}
      // Иккинчи ёзув — ЯНГИ ядро учун. Биринчиси хато бўлса ҳам бу
      // уриниб кўрилади ва тескариси ҳам: битта коллекция ишламаётгани
      // иккинчисини тўхтатмайди.
      //
      // ДИҚҚАТ: `isOnline: true` ҳар heartbeat'да келади — sweep
      // эскирган ёзувни offline қилиб қўйган бўлиши мумкин
      // (`presenceSweeper`, ҳар 2 дақиқада) ва фақат координата
      // янгиланса курьер қайтиб онлайн бўлмайди.
      try {
        await _presence.upsert(ProviderPresence(
          providerId: presenceUid,
          module: DemandModule.courier.wire,
          isOnline: true,
          lat: pos.latitude,
          lng: pos.longitude,
        ));
      } catch (_) {}
    });
  }

  Future<void> _refreshOrder(String orderId) async {
    final o = await _orders.getById(orderId);
    if (o == null) return;
    final list = List<OrderModel>.from(_routeOrders);
    final i = list.indexWhere((e) => e.id == orderId);
    if (i >= 0) {
      list[i] = o;
      _routeOrders = list;
      _safeNotify();
    }
  }

  Future<void> markPicked(String orderId) async {
    try {
      await OrderPaymentService.courierMarkPicked(
        orderId: orderId,
        courierPhone: _courierPhone,
        lat: _currentPos?.latitude,
        lng: _currentPos?.longitude,
      );
      await _refreshOrder(orderId);
      _info = 'courier_info_picked';
      _safeNotify();
    } catch (e) {
      _errorMessage = 'courier_error_generic|$e';
      _safeNotify();
    }
  }

  Future<void> markArrived(String orderId) async {
    try {
      await OrderPaymentService.courierMarkArrived(
        orderId: orderId,
        courierPhone: _courierPhone,
        lat: _currentPos?.latitude,
        lng: _currentPos?.longitude,
      );
      await _refreshOrder(orderId);
      _info = 'courier_info_arrived';
      _safeNotify();
    } catch (e) {
      _errorMessage = 'courier_error_generic|$e';
      _safeNotify();
    }
  }

  // ── Ресторан буюртмалари (Б3). Хато чақирувчига қайтади: карточка
  // матнини ўзи кўрсатади (код нотўғри → диалог очиқ қолади). ──────────

  Future<void> restaurantPickup(String orderId, String code) async {
    await restaurants.pickup(orderId, pickupCode: code);
    await _refreshOrder(orderId);
    _info = 'courier_info_picked';
    _safeNotify();
  }

  Future<void> restaurantArrive(String orderId) async {
    await restaurants.arrive(orderId);
    await _refreshOrder(orderId);
    _info = 'courier_info_arrived';
    _safeNotify();
  }

  /// `delivered` ёки `delivery_failed`. Натижа — курьерга кўрсатиш учун;
  /// ҳамён етмаганини аниқлаш учун буюртманинг ЯКУНДАН ОЛДИНГИ ҳолати
  /// керак (сервер `deliveryPaymentMethod`ни `cash`га алмаштиради).
  Future<CourierCompletionSummary> restaurantComplete(
    String orderId, {
    required bool delivered,
    required String failReason,
  }) async {
    OrderModel? before = _routeOrders
        .cast<OrderModel?>()
        .firstWhere((o) => o!.id == orderId, orElse: () => null);
    before ??= await _orders.getById(orderId);
    final res = await restaurants.complete(
      orderId,
      delivered: delivered,
      failReason: failReason,
    );
    await _refreshOrder(orderId);
    return CourierCompletionSummary.fromMap(
      res,
      order: before ??
          OrderModel(id: orderId, type: 'restaurant', total: 0, status: '', items: const []),
    );
  }

  Future<Map<String, dynamic>> submitPayment(
    String orderId,
    List<Map<String, dynamic>> lines,
  ) async {
    try {
      final result = await OrderPaymentService.courierSubmitPayment(
        orderId: orderId,
        courierPhone: _courierPhone,
        lines: lines,
        lat: _currentPos?.latitude,
        lng: _currentPos?.longitude,
      );
      await _refreshOrder(orderId);
      _pendingPaymentOrderId = orderId;
      _info = 'courier_info_payment_accepted';
      _safeNotify();
      return result;
    } catch (e) {
      _errorMessage = 'courier_error_generic|$e';
      _safeNotify();
      rethrow;
    }
  }

  /// Тўловдан кейин reys индексини олдинга сурish (якунлаш тугмаси ёки тиклаш).
  Future<void> confirmAndAdvance({String? orderId}) async {
    if (_advancingRoute) return;

    var oid = orderId ?? _pendingPaymentOrderId;
    if (oid == null) {
      final cur = currentOrder;
      if (cur != null && isOrderFinalized(cur)) oid = cur.id;
    }
    if (oid == null) return;

    _pendingPaymentOrderId = null;
    _advancingRoute = true;
    try {
      final route = _activeRoute;
      if (route != null &&
          _currentOrderIndex < _routeOrders.length &&
          _routeOrders[_currentOrderIndex].id == oid) {
        final nextIndex = _currentOrderIndex + 1;
        await _routes.advanceIndex(route.id, nextIndex);

        if (nextIndex >= _routeOrders.length) {
          await _routes.completeRoute(route.id);
          _activeRoute = null;
          _routeOrders = const [];
          _currentOrderIndex = 0;
          _info = 'courier_info_route_done';
        } else {
          _currentOrderIndex = nextIndex;
          _info = 'courier_info_order_done';
        }
        await loadActiveRoute();
      } else {
        _info = 'courier_info_order_done';
      }
      _safeNotify();
    } catch (e) {
      _errorMessage = 'courier_error_generic|$e';
      _safeNotify();
      rethrow;
    } finally {
      _advancingRoute = false;
    }
  }

  /// Тўлов sheet ёпилганда ёки илова қайта очилганда — «осilib qolgan» буюртмани сурish.
  Future<void> finalizeCurrentOrderIfPaid() async {
    await _syncStuckCurrentOrderIfNeeded();
  }

  Future<void> _syncStuckCurrentOrderIfNeeded() async {
    if (_advancingRoute || _pendingPaymentOrderId != null) return;
    final cur = currentOrder;
    if (cur == null || !isOrderFinalized(cur)) return;
    await confirmAndAdvance(orderId: cur.id);
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }
}
