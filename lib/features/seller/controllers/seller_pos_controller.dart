import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/bread_product.dart';
import '../../../models/food_product.dart';
import '../../../models/order_model.dart';
import '../../../repositories/bread_repository.dart';
import '../../../repositories/inventory_repository.dart';
import '../../../services/seller_sale_service.dart';
import '../../../utils/food_catalog.dart';
import '../../../utils/wallet_payment.dart';

enum SellerPayMode { cash, wallet, mixed }

enum SellerMainTab { tezkor, orders }

enum SellerOrderFilter { ready, waiting, all }

/// Sotuvdan keyingi chek (UI dialog).
class SellerSaleReceipt {
  const SellerSaleReceipt({
    required this.result,
    required this.lines,
    required this.customerPhone,
    required this.payMode,
    required this.pickup,
  });

  final SellerSaleResult result;
  final List<SellerCartLine> lines;
  final String customerPhone;
  final SellerPayMode payMode;
  final bool pickup;
}

class SellerCartLine {
  SellerCartLine({
    required this.key,
    required this.kind,
    required this.inventoryId,
    required this.name,
    required this.emoji,
    required this.unitPrice,
    required this.unit,
    required this.qty,
  });

  final String key;
  final String kind;
  final String inventoryId;
  final String name;
  final String emoji;
  final int unitPrice;
  final String unit;
  double qty;

  int get lineTotal => (unitPrice * qty).round();
}

/// Sotuvchi mini-kassa holati.
class SellerPosController extends ChangeNotifier {
  SellerPosController({
    BreadRepository? breadRepo,
    InventoryRepository? inventoryRepo,
  })  : _breadRepo = breadRepo ?? BreadRepository(),
        _inventoryRepo = inventoryRepo ?? InventoryRepository() {
    _init();
  }

  final BreadRepository _breadRepo;
  final InventoryRepository _inventoryRepo;

  StreamSubscription? _foodSub;
  StreamSubscription? _foodInvSub;
  StreamSubscription? _breadSub;
  StreamSubscription? _ordersSub;

  static const _uuid = Uuid();

  SellerMainTab mainTab = SellerMainTab.tezkor;
  SellerOrderFilter orderFilter = SellerOrderFilter.waiting;
  String orderSearch = '';

  List<FoodProduct> foodProducts = const [];
  List<BreadProduct> breadProducts = const [];
  final Map<String, int> foodStock = {};
  final Map<String, SellerCartLine> cart = {};
  List<OrderModel> pickupOrders = const [];
  String? ordersLoadError;
  String? walletLoadError;

  String customerPhone = '';
  int walletBalance = 0;
  bool walletLoading = false;
  SellerPayMode payMode = SellerPayMode.cash;
  int cashPaid = 0;
  bool busy = false;
  String? lastError;
  String? _dailyTotalKey;
  int sessionTotal = 0;
  SellerShiftSummary? shiftSummary;
  bool shiftLoading = false;
  String? shiftLoadError;
  SellerSaleReceipt? lastReceipt;

  /// Bir checkout urinishi uchun barqaror (retry / double-tap).
  String? _pendingSaleIdem;

  OrderModel? payingOrder;

  int get cartCount => cart.values.fold(0, (s, l) => s + l.qty.round());
  int get cartTotal => cart.values.fold(0, (s, l) => s + l.lineTotal);

  int get maxWallet {
    final total = payingOrder?.total ?? cartTotal;
    return WalletPayment.maxDebitFromWallet(walletBalance, total);
  }

  int get walletPaid {
    final total = payingOrder?.total ?? cartTotal;
    if (payMode == SellerPayMode.cash || total <= 0) return 0;
    return maxWallet;
  }

  int get cashDue {
    final total = payingOrder?.total ?? cartTotal;
    return (total - walletPaid).clamp(0, 999999999);
  }

  /// Buyurtmalar tabi — kutilmoqda + tayyor (to'lanmagan).
  int get queueBadgeCount => pickupOrders
      .where((o) =>
          o.effectivePayment != 'paid' &&
          o.effectiveFulfillment != 'completed')
      .length;

  int get readyBadgeCount => pickupOrders
      .where((o) =>
          o.effectivePayment != 'paid' && o.effectiveFulfillment == 'ready')
      .length;

  int get waitingBadgeCount => pickupOrders
      .where((o) =>
          o.effectivePayment != 'paid' &&
          o.effectiveFulfillment != 'ready' &&
          o.effectiveFulfillment != 'completed')
      .length;

  List<OrderModel> get filteredPickupOrders {
    var list = pickupOrders;
    switch (orderFilter) {
      case SellerOrderFilter.ready:
        list = list
            .where((o) =>
                o.effectivePayment != 'paid' &&
                o.effectiveFulfillment == 'ready')
            .toList();
        break;
      case SellerOrderFilter.waiting:
        list = list
            .where((o) =>
                o.effectivePayment != 'paid' &&
                o.effectiveFulfillment != 'ready' &&
                o.effectiveFulfillment != 'completed')
            .toList();
        break;
      case SellerOrderFilter.all:
        break;
    }
    final q = orderSearch.trim().toLowerCase();
    if (q.isEmpty) return list;
    final digits = phoneDigits(q);
    return list.where((o) {
      final name = o.userName.toLowerCase();
      final phone = phoneDigits(o.userPhone);
      return name.contains(q) ||
          (digits.isNotEmpty && phone.contains(digits));
    }).toList();
  }

  /// Rasta: tayyor non + ёпишдан қолган (zahirasi bor) nonlar.
  static bool isPosSellableBread(BreadProduct p) {
    if ((p.price ?? 0) <= 0) return false;
    if (p.isReady) return !p.isSoldOut;
    if (p.isYopish) return p.totalStock > 0 && p.remaining > 0;
    return false;
  }

  Future<void> _init() async {
    await _loadDailyTotal();
    unawaited(refreshShiftSummary());

    _foodSub = FirebaseFirestore.instance
        .collection('food_catalog')
        .orderBy('id')
        .snapshots()
        .listen((snap) async {
      if (snap.docs.isEmpty) {
        foodProducts = List<FoodProduct>.from(FoodCatalog.products);
      } else {
        foodProducts = snap.docs
            .map((d) => FoodProduct.fromFirestore(d.data(), d.id))
            .toList();
      }
      notifyListeners();
    }, onError: (_) {
      foodProducts = List<FoodProduct>.from(FoodCatalog.products);
      notifyListeners();
    });

    _foodInvSub = FirebaseFirestore.instance
        .collection('food_inventory')
        .snapshots()
        .listen((snap) {
      for (final d in snap.docs) {
        final data = d.data();
        final total = (data['totalStock'] as num?)?.toInt() ?? 0;
        final sold = (data['soldToday'] as num?)?.toInt() ?? 0;
        if (total <= 0) {
          foodStock[d.id] = 999999;
        } else {
          final r = total - sold;
          foodStock[d.id] = r < 0 ? 0 : r;
        }
      }
      notifyListeners();
    }, onError: (e) {
      debugPrint('seller food_inventory: $e');
    });

    _breadSub = _breadRepo.watchProducts().listen((list) {
      breadProducts = list.where(isPosSellableBread).toList();
      notifyListeners();
    });

    _ordersSub = FirebaseFirestore.instance
        .collection('orders')
        .where('fulfillmentMode', isEqualTo: 'pickup')
        .where('paymentStatus', isEqualTo: 'unpaid')
        .orderBy('createdAt', descending: true)
        .limit(60)
        .snapshots()
        .listen((snap) {
      ordersLoadError = null;
      pickupOrders = snap.docs.map(OrderModel.fromDoc).toList();
      notifyListeners();
    }, onError: (e) {
      debugPrint('seller pickup orders: $e');
      ordersLoadError = 'Buyurtmalar yuklanmadi';
      notifyListeners();
    });
  }

  Future<void> _loadDailyTotal() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = canonicalPhoneId(prefs.getString('user_phone') ?? '');
    final now = DateTime.now();
    final day =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _dailyTotalKey = 'seller_pos_daily_${phone}_$day';
    sessionTotal = prefs.getInt(_dailyTotalKey!) ?? 0;
    notifyListeners();
  }

  Future<void> _persistDailyTotal() async {
    final key = _dailyTotalKey;
    if (key == null || key.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, sessionTotal);
  }

  void setMainTab(SellerMainTab tab) {
    if (mainTab == tab) return;
    mainTab = tab;
    if (tab == SellerMainTab.tezkor) {
      cancelPayingOrder();
    }
    notifyListeners();
  }

  void setOrderFilter(SellerOrderFilter f) {
    orderFilter = f;
    notifyListeners();
  }

  void setOrderSearch(String q) {
    orderSearch = q;
    notifyListeners();
  }

  Future<void> refreshShiftSummary() async {
    shiftLoading = true;
    shiftLoadError = null;
    notifyListeners();
    try {
      final s = await SellerSaleService.getShiftSummary();
      shiftSummary = s;
      sessionTotal = s.total;
      await _persistDailyTotal();
    } catch (e) {
      shiftLoadError = 'Smena yuklanmadi';
      debugPrint('seller shift: $e');
    } finally {
      shiftLoading = false;
      notifyListeners();
    }
  }

  void startPayingOrder(OrderModel order) {
    payingOrder = order;
    payMode = SellerPayMode.cash;
    customerPhone = order.userPhone;
    cashPaid = order.total;
    lastError = null;
    notifyListeners();
    setCustomerPhone(order.userPhone);
  }

  void cancelPayingOrder() {
    payingOrder = null;
    payMode = SellerPayMode.cash;
    cashPaid = cashDue;
    lastError = null;
    notifyListeners();
  }

  Future<void> _loadFoodStock() async {
    for (final p in foodProducts) {
      try {
        foodStock[p.inventoryId] =
            await _inventoryRepo.getRemaining(InventoryKind.food, p.inventoryId);
      } catch (_) {
        foodStock[p.inventoryId] = 999999;
      }
    }
    notifyListeners();
  }

  int stockForFood(FoodProduct p) => foodStock[p.inventoryId] ?? 999999;

  void addFood(FoodProduct p) {
    final stock = stockForFood(p);
    if (stock <= 0) return;
    final key = 'food_${p.id}';
    final existing = cart[key];
    final nextQty = (existing?.qty ?? 0) + (p.step > 0 ? p.step : 1);
    if (stock < 999999 && nextQty > stock) return;
    _pendingSaleIdem = null;
    cart[key] = SellerCartLine(
      key: key,
      kind: 'food',
      inventoryId: p.inventoryId,
      name: p.name,
      emoji: p.emoji,
      unitPrice: p.price,
      unit: p.unit,
      qty: nextQty,
    );
    _syncCashDefault();
    notifyListeners();
  }

  void addBread(BreadProduct p) {
    if (p.isSoldOut || (p.price ?? 0) <= 0) return;
    final id = p.firestoreId ?? '';
    if (id.isEmpty) return;
    final key = 'bread_$id';
    final existing = cart[key];
    final nextQty = (existing?.qty ?? 0) + 1;
    if (p.totalStock > 0 && nextQty > p.remaining) return;
    _pendingSaleIdem = null;
    cart[key] = SellerCartLine(
      key: key,
      kind: 'bread',
      inventoryId: id,
      name: p.name,
      emoji: p.emoji,
      unitPrice: p.price ?? 0,
      unit: p.unit,
      qty: nextQty,
    );
    _syncCashDefault();
    notifyListeners();
  }

  void setQty(String key, double qty) {
    final line = cart[key];
    if (line == null) return;
    _pendingSaleIdem = null;
    if (qty <= 0) {
      cart.remove(key);
    } else {
      var next = qty;
      if (line.kind == 'food') {
        final stock = foodStock[line.inventoryId] ?? 999999;
        if (stock < 999999 && next > stock) next = stock.toDouble();
      } else if (line.kind == 'bread') {
        BreadProduct? bread;
        for (final p in breadProducts) {
          if (p.firestoreId == line.inventoryId) {
            bread = p;
            break;
          }
        }
        if (bread != null &&
            bread.totalStock > 0 &&
            next > bread.remaining) {
          next = bread.remaining.toDouble();
        }
      }
      if (next <= 0) {
        cart.remove(key);
      } else {
        line.qty = next;
      }
    }
    _syncCashDefault();
    notifyListeners();
  }

  void clearCart() {
    cart.clear();
    cashPaid = 0;
    lastError = null;
    _pendingSaleIdem = null;
    notifyListeners();
  }

  void setPayMode(SellerPayMode mode) {
    payMode = mode;
    _syncCashDefault();
    notifyListeners();
  }

  void setCashPaid(int v) {
    cashPaid = v < 0 ? 0 : v;
    notifyListeners();
  }

  void _syncCashDefault() {
    cashPaid = cashDue;
  }

  Future<void> setCustomerPhone(String raw) async {
    customerPhone = raw.trim();
    walletBalance = 0;
    walletLoadError = null;
    if (canonicalPhoneId(customerPhone).length < 12 &&
        phoneDigits(customerPhone).length < 9) {
      notifyListeners();
      return;
    }
    walletLoading = true;
    notifyListeners();
    try {
      final res =
          await SellerSaleService.getCustomerWalletBalance(customerPhone);
      if (!res.ok) {
        walletBalance = 0;
        walletLoadError = 'Hamyon o\'qilmadi (tarmoq)';
      } else if (!res.found) {
        walletBalance = 0;
        walletLoadError = 'Mijoz topilmadi';
      } else {
        walletBalance = res.balance;
        walletLoadError = null;
      }
    } catch (e) {
      walletBalance = 0;
      walletLoadError = 'Hamyon xatosi';
      debugPrint('seller wallet: $e');
    }
    walletLoading = false;
    _syncCashDefault();
    notifyListeners();
  }

  Future<bool> markReady(OrderModel order) async {
    busy = true;
    lastError = null;
    notifyListeners();
    try {
      await SellerSaleService.markPickupReady(order.id);
      return true;
    } catch (e) {
      lastError = '$e';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  ({int w, int c})? _resolvePaymentAmounts(int total) {
    var w = walletPaid;
    var c = cashPaid;
    if (payMode == SellerPayMode.cash) {
      w = 0;
      if (c < total) c = total;
      if (c > total && customerPhone.trim().isEmpty) c = total;
    } else if (payMode == SellerPayMode.wallet) {
      w = maxWallet;
      c = (total - w).clamp(0, 999999999);
      if (w <= 0) {
        lastError = 'Hamyon bo\'sh yoki telefon kiritilmagan';
        notifyListeners();
        return null;
      }
      if (customerPhone.trim().isEmpty) {
        lastError = 'Hamyon uchun mijoz telefonini kiriting';
        notifyListeners();
        return null;
      }
    } else {
      w = maxWallet;
      if (c + w < total) {
        lastError = 'To\'lov yetarli emas';
        notifyListeners();
        return null;
      }
      if (w > 0 && customerPhone.trim().isEmpty) {
        lastError = 'Hamyon uchun mijoz telefonini kiriting';
        notifyListeners();
        return null;
      }
    }
    return (w: w, c: c);
  }

  Future<SellerSaleResult?> checkout() async {
    if (payingOrder != null) return checkoutPickupPayment();
    if (cart.isEmpty || busy) return null;
    lastError = null;
    final amounts = _resolvePaymentAmounts(cartTotal);
    if (amounts == null) return null;

    busy = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final sellerPhone = prefs.getString('user_phone') ?? '';
      _pendingSaleIdem ??=
          'seller_${canonicalPhoneId(sellerPhone)}_${_uuid.v4()}';
      final idem = _pendingSaleIdem!;

      final receiptLines = cart.values
          .map(
            (l) => SellerCartLine(
              key: l.key,
              kind: l.kind,
              inventoryId: l.inventoryId,
              name: l.name,
              emoji: l.emoji,
              unitPrice: l.unitPrice,
              unit: l.unit,
              qty: l.qty,
            ),
          )
          .toList();

      final items = receiptLines
          .map((l) => <String, dynamic>{
                'kind': l.kind,
                'inventoryId': l.inventoryId,
                'name': l.name,
                'emoji': l.emoji,
                'unitPrice': l.unitPrice,
                'qty': l.qty,
                'unit': l.unit,
              })
          .toList();

      final result = await SellerSaleService.placeSale(
        idempotencyKey: idem,
        items: items,
        cashPaid: amounts.c,
        walletPaid: amounts.w,
        customerPhone: customerPhone,
      );
      lastReceipt = SellerSaleReceipt(
        result: result,
        lines: receiptLines,
        customerPhone: customerPhone,
        payMode: payMode,
        pickup: false,
      );
      _pendingSaleIdem = null;
      sessionTotal += result.total;
      await _persistDailyTotal();
      clearCart();
      unawaited(_loadFoodStock());
      unawaited(refreshShiftSummary());
      return result;
    } catch (e) {
      lastError = '$e';
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<SellerSaleResult?> checkoutPickupPayment() async {
    final order = payingOrder;
    if (order == null || busy) return null;
    lastError = null;
    final amounts = _resolvePaymentAmounts(order.total);
    if (amounts == null) return null;

    busy = true;
    notifyListeners();
    try {
      final result = await SellerSaleService.submitPickupPayment(
        orderId: order.id,
        cashPaid: amounts.c,
        walletPaid: amounts.w,
      );
      lastReceipt = SellerSaleReceipt(
        result: result,
        lines: order.items
            .map(
              (it) => SellerCartLine(
                key: it.name,
                kind: it.productType.isNotEmpty ? it.productType : 'item',
                inventoryId: it.name,
                name: it.name,
                emoji: it.emoji,
                unitPrice: it.unitPrice,
                unit: it.unit,
                qty: (it.qty ?? it.count).toDouble(),
              ),
            )
            .toList(),
        customerPhone: order.userPhone,
        payMode: payMode,
        pickup: true,
      );
      sessionTotal += result.total;
      await _persistDailyTotal();
      cancelPayingOrder();
      unawaited(refreshShiftSummary());
      return result;
    } catch (e) {
      lastError = '$e';
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _foodSub?.cancel();
    _foodInvSub?.cancel();
    _breadSub?.cancel();
    _ordersSub?.cancel();
    super.dispose();
  }
}
