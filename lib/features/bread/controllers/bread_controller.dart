import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/bread_extra_product.dart';
import '../../../models/bread_product.dart';
import '../../../models/order_model.dart';
import '../../../repositories/bread_repository.dart';
import '../../../repositories/inventory_repository.dart';
import '../../../repositories/orders_repository.dart';
import '../../../services/order_payment_service.dart';

/// Нон каталоги, сават, тарих ва оффлайн-навбатни бирлаштирган
/// universal controller. Cart sheet ҳам шу controllerга боғлиқ —
/// flourMilkChoice ва wallet баланси шу йерда сақланади.
class BreadController extends ChangeNotifier {
  BreadController({
    required BreadRepository breadRepo,
    required OrdersRepository ordersRepo,
    required InventoryRepository inventoryRepo,
  })  : _breadRepo = breadRepo,
        _ordersRepo = ordersRepo,
        _inventoryRepo = inventoryRepo {
    _init();
  }

  final BreadRepository _breadRepo;
  final OrdersRepository _ordersRepo;
  // ignore: unused_field — createOrderAtomically endi CFда; DI сақланади.
  final InventoryRepository _inventoryRepo;

  // ─── Каталог ─────────────────────────────────────────────────────────
  Map<String, dynamic> _prices = const {};
  Map<String, dynamic> get prices => _prices;
  bool pricesLoading = true;

  List<BreadProduct> firestoreProducts = const [];
  bool firestoreLoading = true;

  List<BreadExtraProduct> extraProducts = const [];
  bool extraLoading = true;

  bool get isLoading => pricesLoading || firestoreLoading || extraLoading;

  // ─── Сават ───────────────────────────────────────────────────────────
  final Map<int, int> cart = {};
  final Map<int, double> extraProductsCart = {};

  /// Сават даги нон учун `ours` (бизнинг ун+сут) ёки `yours`.
  final Map<int, String> flourMilkChoice = {};

  // ─── Wallet/cash ────────────────────────────────────────────────────
  int walletBalance = 0;

  // ─── Тарих ──────────────────────────────────────────────────────────
  List<OrderModel> orderHistory = const [];
  bool historyLoading = false;
  bool showHistory = false;

  // ─── Connectivity ───────────────────────────────────────────────────
  bool hasInternet = true;
  int pendingCount = 0;

  // ─── Subscriptions ──────────────────────────────────────────────────
  StreamSubscription<List<BreadProduct>>? _productsSub;
  StreamSubscription<List<BreadExtraProduct>>? _extraSub;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  List<BreadProduct> get readyProducts =>
      firestoreProducts.where((p) => p.isReady).toList(growable: false);

  List<BreadProduct> get yopishProducts =>
      firestoreProducts.where((p) => p.isYopish).toList(growable: false);

  List<BreadProduct> get toyProducts =>
      firestoreProducts.where((p) => p.isToy).toList(growable: false);

  List<BreadProduct> get allProducts => firestoreProducts;

  /// Фақат нонлар (badge учун `extraLineCount` билан қўшилади).
  int get breadCartQty {
    int n = 0;
    for (final e in cart.entries) {
      if (_findProduct(e.key) != null) n += e.value;
    }
    return n;
  }

  int get extraLineCount =>
      extraProductsCart.entries.where((e) => e.value > 1e-9).length;

  int get cartCount => breadCartQty + extraLineCount;

  bool get hasCartItems =>
      breadCartQty > 0 ||
      extraProductsCart.entries.any((e) => e.value > 1e-9);

  // ─── Init ───────────────────────────────────────────────────────────
  Future<void> _init() async {
    await _loadPrices();
    _productsSub = _breadRepo.watchProducts().listen((list) {
      firestoreProducts = list;
      firestoreLoading = false;
      notifyListeners();
    });
    _extraSub = _breadRepo.watchExtraProducts().listen((list) {
      extraProducts = list;
      extraLoading = false;
      _clampTiedExtras();
      notifyListeners();
    });
    await _initConnectivity();
    await _loadPendingOrder();
  }

  Future<void> _loadPrices() async {
    _prices = await _breadRepo.getPrices();
    pricesLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _productsSub?.cancel();
    _extraSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  // ─── Connectivity ───────────────────────────────────────────────────
  Future<void> _initConnectivity() async {
    final initial = await Connectivity().checkConnectivity();
    _onConnectivity(initial);
    _connSub = Connectivity().onConnectivityChanged.listen(_onConnectivity);
  }

  void _onConnectivity(List<ConnectivityResult> results) {
    final connected = results.any((r) => r != ConnectivityResult.none);
    hasInternet = connected;
    notifyListeners();
    if (connected && pendingCount > 0) {
      _flushPendingOrders();
    }
  }

  // ─── Pending orders queue ───────────────────────────────────────────
  Future<void> _loadPendingOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString('pending_orders');
    if (pending == null) return;
    try {
      final list = jsonDecode(pending) as List;
      pendingCount = list.length;
      notifyListeners();
    } catch (_) {}
  }

  /// `_flushPendingOrders` муваффақиятли юборилган сонни қайтаради
  /// (caller тарафда SnackBar учун).
  Future<int> _flushPendingOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getString('pending_orders');
      if (pending == null) return 0;
      final list = jsonDecode(pending) as List;
      if (list.isEmpty) return 0;

      int sent = 0;
      final remaining = <Map<String, dynamic>>[];
      for (final order in list) {
        final data = Map<String, dynamic>.from(order as Map<String, dynamic>);
        try {
          final payload = Map<String, dynamic>.from(data)
            ..removeWhere((k, _) =>
                k == 'createdAt' || k == 'idempotencyKey' || k == 'decrements');
          final phone = data['userPhone'] as String? ?? '';
          final idempotencyKey = data['idempotencyKey'] as String? ??
              _buildIdempotencyKey(phone, data);
          await OrderPaymentService.placeOrderPostPaid(
            userPhone: phone,
            idempotencyKey: idempotencyKey,
            orderBase: payload,
            decrements: (data['decrements'] as List?)
                    ?.map((e) => Map<String, dynamic>.from(e as Map))
                    .toList() ??
                [],
          );
          sent++;
        } on FirebaseFunctionsException {
          remaining.add(data);
        } catch (_) {
          remaining.add(data);
        }
      }
      if (remaining.isEmpty) {
        await prefs.remove('pending_orders');
      } else {
        await prefs.setString('pending_orders', jsonEncode(remaining));
      }
      pendingCount = remaining.length;
      notifyListeners();
      return sent;
    } catch (_) {
      return 0;
    }
  }

  /// Cart sheet'дан чақирилади — UI'да SnackBar кўрсатиш учун натижани кутади.
  Future<int> flushPendingOrders() => _flushPendingOrders();

  // ─── Каталог ёрдамчилари ────────────────────────────────────────────
  int productPrice(BreadProduct p) {
    if (p.price != null && p.price! > 0) return p.price!;
    final key = p.priceKey;
    if (key != null && _prices.containsKey(key)) {
      return (_prices[key] as num).toInt();
    }
    return 1000;
  }

  void addProductToCart(int id) {
    cart[id] = 1;
    notifyListeners();
  }

  void incrementProduct(int id) {
    cart[id] = (cart[id] ?? 0) + 1;
    notifyListeners();
  }

  void decrementProduct(int id) {
    final v = cart[id] ?? 0;
    if (v > 1) {
      cart[id] = v - 1;
    } else {
      cart.remove(id);
    }
    _clampTiedExtras();
    notifyListeners();
  }

  void setExtraProductQty(int id, double raw) {
    final p = _findExtra(id);
    if (p == null) return;
    final q = _roundExtraQty(p, raw);
    final maxV = p.effectiveMaxQtyValue(yopishTotalCount);
    if (q <= 0 || maxV <= 0) {
      extraProductsCart.remove(id);
    } else {
      final capped = q > maxV ? maxV : q;
      final finalQ = _roundExtraQty(p, capped);
      if (finalQ <= 0) {
        extraProductsCart.remove(id);
      } else {
        extraProductsCart[id] = finalQ;
      }
    }
    notifyListeners();
  }

  /// [direction]: +1 ёки −1 — бирлик бўйича бир қадам.
  void bumpExtraQty(int id, int direction) {
    final p = _findExtra(id);
    if (p == null || direction == 0) return;
    final cur = extraProductsCart[id] ?? 0;
    setExtraProductQty(id, cur + direction * p.qtyStep);
  }

  void setFlourMilkChoice(int id, String choice) {
    flourMilkChoice[id] = choice;
    notifyListeners();
  }

  void clearCart() {
    cart.clear();
    extraProductsCart.clear();
    flourMilkChoice.clear();
    notifyListeners();
  }

  // ─── Тарих ──────────────────────────────────────────────────────────
  Future<void> toggleHistory() async {
    showHistory = !showHistory;
    notifyListeners();
    if (showHistory && orderHistory.isEmpty) {
      await _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    historyLoading = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('user_phone') ?? '';
      if (phone.isEmpty) {
        historyLoading = false;
        notifyListeners();
        return;
      }
      orderHistory = await _ordersRepo.recentByPhone(phone, limit: 20);
    } catch (_) {
      orderHistory = const [];
    }
    historyLoading = false;
    notifyListeners();
  }

  // ─── Pricing ────────────────────────────────────────────────────────
  int flourMilkCost(BreadProduct p, int count) {
    final flourG = p.flourG ?? 300;
    final milkMl = p.milkMl ?? ((p.milkRatio ?? 0.575) * flourG).round();
    final flourPrice = (_prices['flour_price'] as num?)?.toInt() ?? 8000;
    final milkPrice = (_prices['milk_price'] as num?)?.toInt() ?? 7000;
    return (flourG / 1000 * flourPrice * count).round() +
        (milkMl / 1000 * milkPrice * count).round();
  }

  int get yopishTotalCount {
    int c = 0;
    cart.forEach((id, count) {
      final p = _findProduct(id);
      if (p != null && p.isYopish) c += count;
    });
    return c;
  }

  int get saltYeastCost {
    int total = 0;
    cart.forEach((id, c) {
      final p = _findProduct(id);
      if (p != null && (p.isYopish || p.isToy)) total += c;
    });
    return total * 50;
  }

  bool get cartHasYopishBread {
    for (final id in cart.keys) {
      final p = _findProduct(id);
      if (p != null && p.isYopish) return true;
    }
    return false;
  }

  int get breadTotal {
    int total = 0;
    cart.forEach((id, count) {
      final p = _findProduct(id);
      if (p == null) return;
      final basePrice = productPrice(p) * count;
      if (p.isYopish || p.isToy) {
        final choice = flourMilkChoice[id] ?? 'ours';
        total += choice == 'ours' ? basePrice + flourMilkCost(p, count) : basePrice;
      } else {
        total += basePrice;
      }
    });
    return total;
  }

  int get extrasTotal {
    int total = 0;
    for (final p in extraProducts) {
      final qty = extraProductsCart[p.id] ?? 0;
      if (qty > 1e-9) total += p.lineTotal(qty);
    }
    return total;
  }

  int get grandTotal => breadTotal + extrasTotal + saltYeastCost;

  BreadProduct? _findProduct(int id) {
    for (final p in allProducts) {
      if (p.id == id) return p;
    }
    return null;
  }

  BreadExtraProduct? _findExtra(int id) {
    for (final p in extraProducts) {
      if (p.id == id) return p;
    }
    return null;
  }

  double _roundExtraQty(BreadExtraProduct p, double raw) {
    if (raw <= 0) return 0;
    final s = p.qtyStep;
    final n = (raw / s).round() * s;
    if (s >= 1) return n.roundToDouble();
    return ((n * 2).round() / 2);
  }

  /// `tieToYopishBread` қаторларни ёпиш нони озайганда чеклаймиз.
  void _clampTiedExtras() {
    if (extraProductsCart.isEmpty) return;
    final y = yopishTotalCount;
    final keys = List<int>.from(extraProductsCart.keys);
    for (final id in keys) {
      final p = _findExtra(id);
      if (p == null || !p.tieToYopishBread) continue;
      final q = extraProductsCart[id] ?? 0;
      if (q <= 1e-9) continue;
      final cap = p.effectiveMaxQtyValue(y);
      if (q > cap + 1e-9) {
        if (cap <= 0) {
          extraProductsCart.remove(id);
        } else {
          extraProductsCart[id] = _roundExtraQty(p, cap);
        }
      }
    }
  }

  /// Cart sheet очилгандан кейин фойдаланувчи маълумотларини
  /// SharedPreferences'дан ва кошелёк баланси Firestore'дан юкланади.
  Future<({String name, String phone, String address})> loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name') ?? '';
    final phone = prefs.getString('user_phone') ?? '';
    final address = prefs.getString('user_address') ?? '';
    final uid = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (uid.length >= 9) {
      try {
        final doc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        walletBalance = (doc.data()?['bonusBalance'] as num?)?.toInt() ?? 0;
        notifyListeners();
      } catch (_) {}
    }
    return (name: name, phone: phone, address: address);
  }

  // ─── Buyurtma юбориш ────────────────────────────────────────────────
  /// Натижа: `(success: bool, isOffline: bool, error: String?)`
  Future<({bool success, bool isOffline, String? error})> sendOrder({
    required String name,
    required String phone,
    required String address,
    double? deliveryLat,
    double? deliveryLng,
  }) async {
    final orderData = await _buildOrderPayload(
      name: name,
      phone: phone,
      address: address,
      deliveryLat: deliveryLat,
      deliveryLng: deliveryLng,
    );

    final decrements = _inventoryDecrementsForCart();
    final decMaps = <Map<String, dynamic>>[
      for (final e in decrements)
        {
          'kind': e.kind.name,
          'id': e.id,
          'qty': e.qty,
          'label': e.label,
        },
    ];
    final idempotencyKey = _buildIdempotencyKey(phone, orderData);

    if (!hasInternet) {
      try {
        final offline = Map<String, dynamic>.from(orderData);
        offline['createdAt'] = DateTime.now().toIso8601String();
        offline['idempotencyKey'] = idempotencyKey;
        offline['decrements'] = decMaps;
        final prefs = await SharedPreferences.getInstance();
        final existing =
            jsonDecode(prefs.getString('pending_orders') ?? '[]') as List;
        existing.add(offline);
        await prefs.setString('pending_orders', jsonEncode(existing));
        pendingCount = existing.length;
        notifyListeners();
        return (success: true, isOffline: true, error: null);
      } catch (e) {
        return (success: false, isOffline: false, error: 'Хатолик: $e');
      }
    }

    try {
      final payload = Map<String, dynamic>.from(orderData)
        ..removeWhere((k, _) => k == 'createdAt');
      await OrderPaymentService.placeOrderPostPaid(
        userPhone: phone,
        idempotencyKey: idempotencyKey,
        orderBase: payload,
        decrements: decMaps,
      );
      return (success: true, isOffline: false, error: null);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition' &&
          (e.message ?? '').contains('insufficient_cash')) {
        return (
          success: false,
          isOffline: false,
          error:
              'Тўлов етишмади. Кошелёк ва нақд миқдорини текширинг (сервер талаби).',
        );
      }
      final msg = _mapFunctionError(e.code, e.message);
      return (success: false, isOffline: false, error: msg);
    } catch (e) {
      return (success: false, isOffline: false, error: 'Хатолик: $e');
    }
  }

  String _buildIdempotencyKey(String phone, Map<String, dynamic> orderData) {
    final parts = <String>[];
    for (final it in orderData['items'] as List? ?? const []) {
      final m = Map<String, dynamic>.from(it as Map);
      parts.add('${m['id']}_${m['count']}_${m['flourMilk']}');
    }
    for (final ex in orderData['extras'] as List? ?? const []) {
      final m = Map<String, dynamic>.from(ex as Map);
      parts.add('x_${m['name']}_${m['count']}');
    }
    if (orderData['saltYeastCost'] != null) {
      parts.add('salt_${orderData['saltYeastCost']}');
    }
    parts.sort();
    final cartSignature = parts.join('|');
    final dateStr = DateTime.now().toIso8601String().substring(0, 10);
    final hash = base64Url
        .encode(utf8.encode('$phone|$dateStr|$cartSignature'))
        .substring(0, 16);
    return 'bread_${phone}_${dateStr}_$hash';
  }

  String _mapFunctionError(String code, String? message) {
    switch (code) {
      case 'unauthenticated':
        return 'Буюртма учун тизимга кириш талаб этилади';
      case 'permission-denied':
        return 'Телефон рақамингиз тасдиқланмаган';
      case 'not-found':
        return 'Фойдаланувчи топилмади. Профилингизни текширинг';
      case 'invalid-argument':
        return 'Буюртма маълумотлари нотўғри';
      case 'failed-precondition':
        return message ?? 'Буюртма юборилмади. Қайта уриниб кўринг';
      default:
        return 'Хатолик: ${message ?? code}';
    }
  }

  /// Saвatdaги pozitsiyalardan inventory dekrement ro'yxati.
  List<StockChange> _inventoryDecrementsForCart() {
    final list = <StockChange>[];

    // 1. Тайёр нонлар (бакердан) — firestoreId бўлса инвентаризацияланади.
    cart.forEach((id, count) {
      final p = _findProduct(id);
      if (p == null) return;
      if (!p.isReady) return; // йопиш/той учун inventory йўқ
      final fid = p.firestoreId;
      if (fid == null || fid.isEmpty) return;
      list.add(StockChange(
        kind: InventoryKind.bread,
        id: fid,
        qty: count,
        label: p.name,
      ));
    });

    // 2. Қўшимча маҳсулотлар.
    for (final ep in extraProducts) {
      final qty = extraProductsCart[ep.id] ?? 0;
      if (qty <= 1e-9) continue;
      if (ep.firestoreId.isEmpty) continue;
      list.add(StockChange(
        kind: InventoryKind.extra,
        id: ep.firestoreId,
        qty: qty,
        label: ep.name,
      ));
    }

    return list;
  }

  Future<Map<String, dynamic>> _buildOrderPayload({
    required String name,
    required String phone,
    required String address,
    double? deliveryLat,
    double? deliveryLng,
  }) async {
    final items = <Map<String, dynamic>>[];
    cart.forEach((id, count) {
      final p = _findProduct(id);
      if (p == null) return;
      final choice = flourMilkChoice[id] ?? 'ours';
      final unit = productPrice(p);
      final baseLineTotal = unit * count;
      final fmCost = (p.isYopish || p.isToy) && choice == 'ours'
          ? flourMilkCost(p, count)
          : 0;
      final lineTotal = (p.isYopish || p.isToy) && choice == 'ours'
          ? baseLineTotal + fmCost
          : baseLineTotal;
      items.add({
        'id': id,
        if (p.emoji.trim().isNotEmpty) 'emoji': p.emoji.trim(),
        'name': p.name,
        'count': count,
        'type': p.type,
        'flourMilk': (p.isYopish || p.isToy) ? choice : 'none',
        'price': unit,
        'baseLineTotal': baseLineTotal,
        if (fmCost > 0) 'flourMilkCost': fmCost,
        'lineTotal': lineTotal,
      });
    });

    final extras = <Map<String, dynamic>>[];
    for (final p in extraProducts) {
      final qty = extraProductsCart[p.id] ?? 0;
      if (qty > 1e-9) {
        final discount = p.discountFor(qty);
        extras.add({
          if (p.emoji.trim().isNotEmpty) 'emoji': p.emoji.trim(),
          if (p.caption.trim().isNotEmpty) 'caption': p.caption.trim(),
          'name': p.name,
          'count': qty,
          'unit': p.unitCode,
          'qtyLabel': p.qtyCaptionNum(qty),
          if (discount > 0) 'bonusDiscount': discount,
          if (discount > 0) 'bonusPercent': p.bonusPercent,
          if (p.firestoreId.isNotEmpty) 'firestoreId': p.firestoreId,
          'total': p.lineTotal(qty),
        });
      }
    }

    double? orderLat;
    double? orderLng;
    final uid = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (deliveryLat != null && deliveryLng != null) {
      orderLat = deliveryLat;
      orderLng = deliveryLng;
    } else if (uid.length >= 9) {
      try {
        final doc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final addr = doc.data()?['address'];
        if (addr is Map) {
          orderLat = (addr['lat'] as num?)?.toDouble();
          orderLng = (addr['lng'] as num?)?.toDouble();
        }
      } catch (_) {}
    }

    return {
      'type': 'bread',
      'userName': name,
      'userPhone': phone,
      'address': address,
      'phone': phone,
      'items': items,
      'extras': extras,
      if (saltYeastCost > 0) 'saltYeastCost': saltYeastCost,
      if (saltYeastCost > 0) 'cartHadYopishBread': cartHasYopishBread,
      'total': grandTotal,
      'balanceApplied': 0,
      'cashDue': grandTotal,
      'cashPaid': 0,
      'status': 'new',
      'fulfillmentStatus': 'pending',
      'paymentStatus': 'unpaid',
      'fulfillmentMode': 'delivery',
      if (orderLat != null) 'lat': orderLat,
      if (orderLng != null) 'lng': orderLng,
    };
  }
}
