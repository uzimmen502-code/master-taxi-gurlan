import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/pending_commerce_orders.dart';
import '../../../models/food_product.dart';
import '../../../repositories/inventory_repository.dart';
import '../../../repositories/orders_repository.dart';
import '../../../services/order_payment_service.dart';
import '../../../utils/food_catalog.dart';

/// Овqat sotib olish flow'i: категория танлаш, саватга маҳsулot қўшish ва
/// миқdorini ўzgartirish, buyurtma yuborish.
///
/// `cart` — `productId -> qty` (qty `0.5`-multiples).
class FoodController extends ChangeNotifier {
  FoodController({
    required OrdersRepository ordersRepo,
    required InventoryRepository inventoryRepo,
  })  : _ordersRepo = ordersRepo,
        _inventoryRepo = inventoryRepo;

  // ignore: unused_field — Provider контракти.
  final OrdersRepository _ordersRepo;
  final InventoryRepository _inventoryRepo;

  String selectedCategory = FoodCatalog.allCategoryKey;
  final Map<int, double> _cart = <int, double>{};
  Map<int, int> _stockMap = const {};
  bool stockLoading = false;
  int walletBalance = 0;
  bool isSubmitting = false;
  String? errorMessage;
  /// `delivery` | `pickup`
  String fulfillmentMode = 'delivery';
  bool hasInternet = true;
  int pendingCount = 0;

  List<FoodProduct> _products = List<FoodProduct>.from(FoodCatalog.products);
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _catalogSub;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  List<FoodProduct> get products => List.unmodifiable(_products);

  /// Категория чiplari: «Барчasi», кейin belgilash tartibidagi kategoriyalar.
  List<String> get categoryKeys {
    final present =
        _products.map((e) => e.category).where((e) => e.isNotEmpty).toSet();
    final out = <String>[FoodCatalog.allCategoryKey];
    for (final c in FoodCatalog.categories) {
      if (c != FoodCatalog.allCategoryKey && present.contains(c)) out.add(c);
    }
    for (final c in present) {
      if (!out.contains(c)) out.add(c);
    }
    return out;
  }

  int stockOf(int productId) => _stockMap[productId] ?? 999999;

  bool isOutOfStock(int productId) {
    final s = _stockMap[productId];
    return s != null && s <= 0;
  }

  bool _wouldExceedStock(int productId, double nextQty) {
    final remaining = stockOf(productId);
    if (remaining >= 999999) return false;
    return nextQty > remaining + 1e-9;
  }

  Future<void> init() async {
    _listenFoodCatalog();
    await _loadPendingOrder();
    await Future.wait([
      _loadWallet(),
      _initConnectivity(),
    ]);
  }

  void _listenFoodCatalog() {
    _catalogSub?.cancel();
    _catalogSub = FirebaseFirestore.instance
        .collection('food_catalog')
        .orderBy('id')
        .snapshots()
        .listen(
      (snap) async {
        if (snap.docs.isEmpty) {
          _products = List<FoodProduct>.from(FoodCatalog.products);
        } else {
          _products = snap.docs
              .map((d) => FoodProduct.fromFirestore(d.data(), d.id))
              .toList();
        }
        if (!_alive) return;
        notifyListeners();
        await _loadStock();
      },
      onError: (_) async {
        _products = List<FoodProduct>.from(FoodCatalog.products);
        if (!_alive) return;
        notifyListeners();
        await _loadStock();
      },
    );
  }

  bool _alive = true;

  @override
  void dispose() {
    _alive = false;
    _catalogSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  FoodProduct _productById(int id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return FoodCatalog.byId(id);
  }

  Future<void> _loadStock() async {
    stockLoading = true;
    notifyListeners();
    final list = _products.isEmpty
        ? List<FoodProduct>.from(FoodCatalog.products)
        : _products;
    final map = <int, int>{};
    try {
      final byInv = await _inventoryRepo.getRemainingMap(
        InventoryKind.food,
        list.map((p) => p.inventoryId),
      );
      for (final p in list) {
        map[p.id] = byInv[p.inventoryId] ?? 999999;
      }
    } catch (_) {
      for (final p in list) {
        map[p.id] = 999999;
      }
    }
    _stockMap = map;
    stockLoading = false;
    notifyListeners();
  }

  Future<void> _loadWallet() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_phone') ?? '';
    final uid12 = canonicalPhoneId(raw);
    final uid9 = phoneDigits(raw);
    if (phoneDigits(uid12).length < 9 && uid9.length < 9) return;
    try {
      DocumentSnapshot<Map<String, dynamic>>? u;
      if (uid12.length >= 12) {
        u = await FirebaseFirestore.instance.collection('users').doc(uid12).get();
      }
      if ((u == null || !u.exists) && uid9.length >= 9 && uid9 != uid12) {
        u = await FirebaseFirestore.instance.collection('users').doc(uid9).get();
      }
      walletBalance = (u?.data()?['bonusBalance'] as num?)?.toInt() ?? 0;
      notifyListeners();
    } catch (_) {}
  }

  /// Саватда ҳамёндан ечиладиган сумма (сервер ҳам шу clamp қилади).
  int get walletApplyAmount {
    if (walletBalance <= 0 || cartTotal <= 0) return 0;
    return walletBalance < cartTotal ? walletBalance : cartTotal;
  }

  int get cashDuePreview => cartTotal - walletApplyAmount;

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

  Future<void> _loadPendingOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final list = await PendingCommerceOrders.load(prefs);
    pendingCount = list.length;
    if (list.isNotEmpty) notifyListeners();
  }

  Future<int> _flushPendingOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = await PendingCommerceOrders.load(prefs);
      if (list.isEmpty) return 0;

      int sent = 0;
      final remaining = <Map<String, dynamic>>[];
      for (final data in list) {
        try {
          final payload = Map<String, dynamic>.from(data)
            ..removeWhere((k, _) =>
                k == 'createdAt' || k == 'idempotencyKey' || k == 'decrements');
          final phone = data['userPhone'] as String? ?? '';
          final idempotencyKey = data['idempotencyKey'] as String? ??
              _buildIdempotencyKey(
                phone,
                (payload['items'] as List?)
                        ?.map((e) => Map<String, dynamic>.from(e as Map))
                        .toList() ??
                    const [],
              );
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
      await PendingCommerceOrders.save(prefs, remaining);
      pendingCount = remaining.length;
      notifyListeners();
      return sent;
    } catch (_) {
      return 0;
    }
  }

  Future<int> flushPendingOrders() => _flushPendingOrders();

  void selectCategory(String c) {
    if (selectedCategory == c) return;
    selectedCategory = c;
    notifyListeners();
  }

  List<FoodProduct> get filteredProducts {
    if (selectedCategory == FoodCatalog.allCategoryKey) {
      return List<FoodProduct>.from(_products);
    }
    return _products.where((p) => p.category == selectedCategory).toList();
  }

  Map<int, double> get cart => Map.unmodifiable(_cart);

  int get cartItemCount => _cart.length;

  bool isInCart(int productId) => _cart.containsKey(productId);

  double qtyOf(int productId) => _cart[productId] ?? 0;

  int get cartTotal {
    var total = 0;
    for (final entry in _cart.entries) {
      final p = _productById(entry.key);
      total += (p.price * entry.value).round();
    }
    return total;
  }

  void addToCart(FoodProduct p) {
    if (isOutOfStock(p.id)) return;
    final current = _cart[p.id] ?? 0;
    final next = current + p.minQty;
    if (_wouldExceedStock(p.id, next)) return;
    _cart[p.id] = next;
    notifyListeners();
  }

  void increase(int productId) {
    final p = _productById(productId);
    final current = _cart[productId] ?? 0;
    final next = current + p.step;
    if (_wouldExceedStock(productId, next)) return;
    _cart[productId] = next;
    notifyListeners();
  }

  bool decrease(int productId) {
    final p = _productById(productId);
    final current = _cart[productId] ?? 0;
    if (current <= p.minQty) {
      _cart.remove(productId);
      notifyListeners();
      return false;
    }
    _cart[productId] = current - p.step;
    notifyListeners();
    return true;
  }

  void clearCart() {
    if (_cart.isEmpty) return;
    _cart.clear();
    notifyListeners();
  }

  void setFulfillmentMode(String mode) {
    final m = mode == 'pickup' ? 'pickup' : 'delivery';
    if (fulfillmentMode == m) return;
    fulfillmentMode = m;
    notifyListeners();
  }

  void clearError() {
    if (errorMessage == null) return;
    errorMessage = null;
    notifyListeners();
  }

  /// Натижа: `(success: bool, isOffline: bool, error: String?)`
  Future<({bool success, bool isOffline, String? error})> submitOrder({
    required String address,
    required String phone,
  }) async {
    if (_cart.isEmpty) {
      errorMessage = 'Сават бўш';
      notifyListeners();
      return (success: false, isOffline: false, error: errorMessage);
    }
    isSubmitting = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final userName = prefs.getString('user_name') ?? '';
      final userPhoneRaw = prefs.getString('user_phone') ?? '';
      final userPhone = canonicalPhoneId(userPhoneRaw);
      if (phoneDigits(userPhone).length < 9) {
        isSubmitting = false;
        errorMessage = 'Телефон рақamingizni profilда tўldiring.';
        notifyListeners();
        return (success: false, isOffline: false, error: errorMessage);
      }

      final items = <Map<String, dynamic>>[];
      final decrements = <StockChange>[];
      for (final entry in _cart.entries) {
        final p = _productById(entry.key);
        final qty = entry.value;
        items.add({
          'name': p.name,
          'emoji': p.emoji,
          'price': p.price,
          'qty': qty,
          'unit': p.unit,
          'total': (p.price * qty).round(),
          'inventoryId': p.inventoryId,
        });
        if (qty > 0) {
          decrements.add(StockChange(
            kind: InventoryKind.food,
            id: p.inventoryId,
            qty: qty,
            label: p.name,
          ));
        }
      }

      final apply = walletApplyAmount;
      final orderData = <String, dynamic>{
        'type': 'food',
        'userName': userName,
        'userPhone': userPhone,
        'address': address,
        'phone': phone.isNotEmpty ? phone : userPhone,
        'items': items,
        'total': cartTotal,
        'balanceApplied': apply,
        'useWallet': true,
        'cashDue': cartTotal - apply,
        'cashPaid': 0,
        'status': 'new',
        'fulfillmentStatus': 'pending',
        'paymentStatus': 'unpaid',
        'fulfillmentMode': fulfillmentMode,
      };

      final decMaps = <Map<String, dynamic>>[
        for (final e in decrements)
          {
            'kind': e.kind.name,
            'id': e.id,
            'qty': e.qty,
            'label': e.label,
          },
      ];
      final idempotencyKey = _buildIdempotencyKey(userPhone, items);

      if (!hasInternet) {
        try {
          final offline = Map<String, dynamic>.from(orderData);
          offline['createdAt'] = DateTime.now().toIso8601String();
          offline['idempotencyKey'] = idempotencyKey;
          offline['decrements'] = decMaps;
          await PendingCommerceOrders.add(prefs, offline);
          final queued = await PendingCommerceOrders.load(prefs);
          pendingCount = queued.length;
          clearCart();
          isSubmitting = false;
          notifyListeners();
          return (success: true, isOffline: true, error: null);
        } catch (e) {
          isSubmitting = false;
          errorMessage = 'Хатолик: $e';
          notifyListeners();
          return (success: false, isOffline: false, error: errorMessage);
        }
      }

      await OrderPaymentService.placeOrderPostPaid(
        userPhone: userPhone,
        idempotencyKey: idempotencyKey,
        orderBase: orderData,
        decrements: decMaps,
      );
      clearCart();
      await Future.wait([_loadStock(), _loadWallet()]);
      isSubmitting = false;
      notifyListeners();
      return (success: true, isOffline: false, error: null);
    } on FirebaseFunctionsException catch (e) {
      isSubmitting = false;
      final m = e.message ?? e.code;
      if (e.code == 'failed-precondition') {
        errorMessage = '⚠️ $m';
      } else {
        errorMessage = 'Хатолик: $m';
      }
      notifyListeners();
      return (success: false, isOffline: false, error: errorMessage);
    } catch (e) {
      isSubmitting = false;
      errorMessage = 'Хатолик: $e';
      notifyListeners();
      return (success: false, isOffline: false, error: errorMessage);
    }
  }

  String _buildIdempotencyKey(
    String phone,
    List<Map<String, dynamic>> items,
  ) {
    final parts = <String>[];
    for (final it in items) {
      parts.add('${it['inventoryId']}_${it['qty']}');
    }
    parts.sort();
    final cartSignature = parts.join('|');
    final dateStr = DateTime.now().toIso8601String().substring(0, 10);
    final raw = '$phone|$dateStr|$cartSignature';
    final hash = _stableHash(raw);
    return 'food_${dateStr}_$hash';
  }

  /// Бутун raw сатр бўйича барқарор (deterministic) hash — FNV-1a 64-bit.
  /// Эски base64Url.substring(0,16) фақат телефонни сақлар эди, сават
  /// таркиби hashга кирмасди — бир кунда бир телефондан барча буюртмалар
  /// бир хил key олиб, фақат биринчиси ёзилар, қолгани йўқоларди.
  static String _stableHash(String input) {
    var hash = BigInt.parse('14695981039346656037'); // FNV offset basis
    final prime = BigInt.parse('1099511628211'); // FNV prime
    final mask = (BigInt.one << 64) - BigInt.one;
    final bytes = utf8.encode(input);
    for (final b in bytes) {
      hash = (hash ^ BigInt.from(b)) & mask;
      hash = (hash * prime) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
