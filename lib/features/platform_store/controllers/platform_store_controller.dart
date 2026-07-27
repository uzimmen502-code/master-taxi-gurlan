import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/platform_product.dart';
import '../../../repositories/platform_products_repository.dart';
import '../../../services/order_payment_service.dart';

/// Платформа дўкони: каталог + сават + буюртма/тўлов.
class PlatformStoreController extends ChangeNotifier {
  PlatformStoreController({PlatformProductsRepository? repo})
      : _repo = repo ?? PlatformProductsRepository();

  final PlatformProductsRepository _repo;

  List<PlatformProduct> _products = const [];
  final Map<String, int> _cart = {};
  bool loading = true;
  String? errorMessage;
  int walletBalance = 0;
  bool isSubmitting = false;
  /// `delivery` | `pickup`
  String fulfillmentMode = 'delivery';

  List<PlatformProduct> get products => List.unmodifiable(_products);
  Map<String, int> get cart => Map.unmodifiable(_cart);

  int get cartItemCount => _cart.values.fold(0, (a, b) => a + b);

  int get cartTotal {
    var sum = 0;
    for (final e in _cart.entries) {
      final p = _byId(e.key);
      if (p != null) sum += p.price * e.value;
    }
    return sum;
  }

  int get walletApplyAmount {
    if (walletBalance <= 0 || cartTotal <= 0) return 0;
    return walletBalance < cartTotal ? walletBalance : cartTotal;
  }

  int get cashDuePreview => cartTotal - walletApplyAmount;

  bool isInCart(String id) => (_cart[id] ?? 0) > 0;

  int qtyOf(String id) => _cart[id] ?? 0;

  PlatformProduct? _byId(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  PlatformProduct? productOf(String id) => _byId(id);

  bool isOutOfStock(PlatformProduct p) => !p.inStock;

  bool _wouldExceed(PlatformProduct p, int nextQty) {
    if (p.isUnlimitedStock) return false;
    return nextQty > p.remaining;
  }

  Future<void> init() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      _products = await _repo.fetchActive();
      _pruneMissing();
      await _loadWallet();
    } catch (e) {
      errorMessage = e.toString();
      _products = const [];
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => init();

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

  void _pruneMissing() {
    final ids = _products.map((e) => e.id).toSet();
    _cart.removeWhere((id, _) => !ids.contains(id));
    for (final id in _cart.keys.toList()) {
      final p = _byId(id);
      if (p == null) continue;
      if (!p.inStock) {
        _cart.remove(id);
        continue;
      }
      if (!p.isUnlimitedStock && _cart[id]! > p.remaining) {
        _cart[id] = p.remaining;
      }
    }
  }

  void addToCart(PlatformProduct p) {
    if (!p.inStock || p.price <= 0) return;
    final next = (qtyOf(p.id) + p.step).clamp(p.minQty, 999999);
    if (_wouldExceed(p, next)) return;
    _cart[p.id] = next;
    notifyListeners();
  }

  void increase(String id) {
    final p = _byId(id);
    if (p == null) return;
    final next = qtyOf(id) + p.step;
    if (_wouldExceed(p, next)) return;
    _cart[id] = next;
    notifyListeners();
  }

  void decrease(String id) {
    final p = _byId(id);
    if (p == null) return;
    final next = qtyOf(id) - p.step;
    if (next < p.minQty) {
      _cart.remove(id);
    } else {
      _cart[id] = next;
    }
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    notifyListeners();
  }

  void setFulfillmentMode(String mode) {
    fulfillmentMode = mode == 'pickup' ? 'pickup' : 'delivery';
    notifyListeners();
  }

  Future<({bool success, String? error})> submitOrder({
    required String address,
    required String phone,
  }) async {
    if (_cart.isEmpty) {
      errorMessage = 'Сават бўш';
      notifyListeners();
      return (success: false, error: errorMessage);
    }
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final userName = prefs.getString('user_name') ?? '';
      final userPhoneRaw = prefs.getString('user_phone') ?? '';
      final userPhone = canonicalPhoneId(userPhoneRaw);
      if (phoneDigits(userPhone).length < 9) {
        isSubmitting = false;
        errorMessage = 'Телефон рақамингизни профилда тўлдиринг.';
        notifyListeners();
        return (success: false, error: errorMessage);
      }

      final items = <Map<String, dynamic>>[];
      final decrements = <Map<String, dynamic>>[];
      for (final entry in _cart.entries) {
        final p = _byId(entry.key);
        if (p == null) continue;
        final qty = entry.value;
        items.add({
          'name': p.name,
          'price': p.price,
          'qty': qty,
          'unit': p.unit,
          'total': p.price * qty,
          'productId': p.id,
          'inventoryId': p.id,
        });
        decrements.add({
          'kind': 'platform',
          'id': p.id,
          'qty': qty,
          'label': p.name,
        });
      }
      if (items.isEmpty) {
        isSubmitting = false;
        errorMessage = 'Сават бўш';
        notifyListeners();
        return (success: false, error: errorMessage);
      }

      final apply = walletApplyAmount;
      final orderData = <String, dynamic>{
        'type': 'platform',
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

      final idempotencyKey = _buildIdempotencyKey(userPhone, items);
      await OrderPaymentService.placeOrderPostPaid(
        userPhone: userPhone,
        idempotencyKey: idempotencyKey,
        orderBase: orderData,
        decrements: decrements,
      );
      clearCart();
      await Future.wait([refresh(), _loadWallet()]);
      isSubmitting = false;
      notifyListeners();
      return (success: true, error: null);
    } on FirebaseFunctionsException catch (e) {
      isSubmitting = false;
      final m = e.message ?? e.code;
      errorMessage = e.code == 'failed-precondition' ? '⚠️ $m' : 'Хатолик: $m';
      notifyListeners();
      return (success: false, error: errorMessage);
    } catch (e) {
      isSubmitting = false;
      errorMessage = 'Хатолик: $e';
      notifyListeners();
      return (success: false, error: errorMessage);
    }
  }

  String _buildIdempotencyKey(
    String phone,
    List<Map<String, dynamic>> items,
  ) {
    final parts = <String>[];
    for (final it in items) {
      parts.add('${it['productId']}_${it['qty']}');
    }
    parts.sort();
    final cartSignature = parts.join('|');
    final dateStr = DateTime.now().toIso8601String().substring(0, 10);
    final raw = '$phone|$dateStr|$cartSignature';
    return 'platform_${dateStr}_${_stableHash(raw)}';
  }

  static String _stableHash(String input) {
    var hash = BigInt.parse('14695981039346656037');
    final prime = BigInt.parse('1099511628211');
    final mask = (BigInt.one << 64) - BigInt.one;
    final bytes = utf8.encode(input);
    for (final b in bytes) {
      hash = (hash ^ BigInt.from(b)) & mask;
      hash = (hash * prime) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
