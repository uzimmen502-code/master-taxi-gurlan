import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/user_error.dart';
import '../../../models/platform_product.dart';
import '../../../models/price_tier.dart';
import '../../../repositories/platform_products_repository.dart';
import '../../../services/order_payment_service.dart';
import '../services/platform_cart_store.dart';

/// Платформа дўкони: каталог + сават + буюртма/тўлов.
class PlatformStoreController extends ChangeNotifier {
  PlatformStoreController({
    PlatformProductsRepository? repo,
    PlatformCartStore? cartStore,
    Future<int> Function(List<Map<String, dynamic>> items)? incentivePreviewer,
  })  : _repoOverride = repo,
        _cartStore = cartStore ?? PlatformCartStore(),
        _incentivePreviewer = incentivePreviewer;

  /// Рағбат (AVA бонуси) олдиндан ҳисоби — тест учун алмаштирилади; бўлмаса
  /// `previewIncentiveForOrder` callable (сервер буюртмадаги билан БИР қоида).
  final Future<int> Function(List<Map<String, dynamic>> items)? _incentivePreviewer;

  final PlatformProductsRepository? _repoOverride;

  /// Кечикиб яратилади — сават тестлари Firebase'сиз ишлайди.
  late final PlatformProductsRepository _repo =
      _repoOverride ?? PlatformProductsRepository();
  final PlatformCartStore _cartStore;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _settingsSub;

  List<PlatformProduct> _products = const [];
  final Map<String, int> _cart = {};

  /// Сават қурилмага ёзилиши навбати — ёзувлар кетма-кет, тартибда бажарилади.
  Future<void> _saving = Future<void>.value();
  bool _cartRestored = false;

  /// Охирги сават ўзгариши қурилмага ёзилгунча (тест ва «орқага» учун).
  Future<void> get cartSaved => _saving;

  void _persistCart() {
    final snapshot = Map<String, int>.of(_cart);
    _saving = _saving.then((_) => _cartStore.save(snapshot));
  }

  /// Қурилмада сақланган саватни тиклайди. Контроллер маршрут билан
  /// яратилади ва «орқага»да ўлади — сават шунга қарамай сақланиб қолади.
  /// Фақат биринчи марта ишлайди (ундан кейин хотира — ҳақиқат манбаи).
  Future<void> restoreCart() async {
    if (_cartRestored) return;
    _cartRestored = true;
    final saved = await _cartStore.load();
    // Тикланиш давомида фойдаланувчи аллақачон нимадир қўшган бўлса,
    // унинг танловини босиб юбормаймиз.
    for (final e in saved.entries) {
      _cart.putIfAbsent(e.key, () => e.value);
    }
    notifyListeners();
    _schedulePreview();
  }
  bool loading = true;
  String? errorMessage;
  int walletBalance = 0;
  /// Мижоз ҳамёндан тўлашни танладими (default off — opt-in).
  bool useWallet = false;

  /// AVA бонуси (рағбат, эга 2026-11-02): `users.incentiveBalance` — фақат AVA дўконида.
  int incentiveBalance = 0;

  /// Бонусни ишлатиш (сукут бўйича ЁҚИҚ — бонус бор бўлса ўзи қўлланади, мижоз ўчириши мумкин).
  bool useIncentive = true;

  /// Сервер ҳисоблаган шу саватга қўлланадиган бонус (туркум ва улуш чегараси бўйича).
  int incentivePreview = 0;
  Timer? _previewTimer;
  int _previewSeq = 0;

  void setUseIncentive(bool value) {
    if (useIncentive == value) return;
    useIncentive = value;
    notifyListeners();
  }

  /// Саватча ўзгарганда бонус ҳисобини янгилаш (350 мс кечиктириб — ҳар босишда сўров эмас).
  void _schedulePreview() {
    _previewTimer?.cancel();
    if (incentiveBalance <= 0 || _cart.isEmpty) {
      if (incentivePreview != 0) {
        incentivePreview = 0;
        notifyListeners();
      }
      return;
    }
    _previewTimer = Timer(const Duration(milliseconds: 350), () => unawaited(_runPreview()));
  }

  Future<void> _runPreview() async {
    final seq = ++_previewSeq;
    final items = [
      for (final e in _cart.entries) {'productId': e.key, 'qty': e.value},
    ];
    try {
      final previewer = _incentivePreviewer ?? _callPreview;
      final v = await previewer(items);
      if (seq != _previewSeq) return;
      incentivePreview = v < 0 ? 0 : v;
    } catch (e) {
      // Ҳисоб олинмаса — бонус кўрсатилмайди; буюртмада сервер барибир ўзи ҳисоблайди.
      debugPrint('[PlatformStore] incentive preview: $e');
      if (seq != _previewSeq) return;
      incentivePreview = 0;
    }
    notifyListeners();
  }

  Future<int> _callPreview(List<Map<String, dynamic>> items) async {
    final res = await FirebaseFunctions.instance.httpsCallable('previewIncentiveForOrder').call<Object?>({
      'items': items,
      'pricingVersion': kPlatformPricingVersion,
    });
    final d = res.data;
    return d is Map && d['incentiveTotal'] is num ? (d['incentiveTotal'] as num).toInt() : 0;
  }

  bool isSubmitting = false;
  /// `delivery` | `pickup`
  String fulfillmentMode = 'delivery';
  /// `settings/app.platformDeliveryFeePercent` (default 5).
  double deliveryFeePercent = 5;

  void setUseWallet(bool value) {
    if (useWallet == value) return;
    useWallet = value;
    notifyListeners();
  }

  List<PlatformProduct> get products => List.unmodifiable(_products);

  /// Тест: каталогни Firebase'сиз бериш.
  @visibleForTesting
  set debugProducts(List<PlatformProduct> value) => _products = value;
  Map<String, int> get cart => Map.unmodifiable(_cart);

  int get cartItemCount => _cart.values.fold(0, (a, b) => a + b);

  /// Фақат маҳсулотлар жами.
  ///
  /// Улгуржи поғонаси бор товарда МИҚДОРГА мос нарх олинади
  /// (`priceForQty`) — 2026-09-29. Поғонасиз товарда у одатдаги
  /// `price` ни қайтаради, шунинг учун эски хулқ ўзгармайди.
  int get cartTotal {
    var sum = 0;
    for (final e in _cart.entries) {
      final p = _byId(e.key);
      if (p != null) sum += p.priceForQty(e.value) * e.value;
    }
    return sum;
  }

  /// Етказиб бериш ҳақи = маҳсулот жами × %.
  int get deliveryFee {
    if (cartTotal <= 0 || deliveryFeePercent <= 0) return 0;
    return (cartTotal * deliveryFeePercent / 100).round();
  }

  /// Маҳсулот + етказиб бериш.
  int get grandTotal => cartTotal + deliveryFee;

  /// Қўлланадиган AVA бонуси — фақат маҳсулот суммасидан (етказиш ҳақи бонусдан эмас).
  int get incentiveApplyAmount {
    if (!useIncentive || incentivePreview <= 0) return 0;
    return incentivePreview < cartTotal ? incentivePreview : cartTotal;
  }

  /// Мижоз тўлайдиган сумма (бонусдан кейин) — ҳамён ва нақд шунга қўлланади.
  int get netTotal => grandTotal - incentiveApplyAmount;

  int get walletApplyAmount {
    if (!useWallet || walletBalance <= 0 || netTotal <= 0) return 0;
    return walletBalance < netTotal ? walletBalance : netTotal;
  }

  int get cashDuePreview => netTotal - walletApplyAmount;

  bool isInCart(String id) => (_cart[id] ?? 0) > 0;

  int qtyOf(String id) => _cart[id] ?? 0;

  /// Саватдаги белгиланган турлар: food / non_food.
  Set<String> get cartGoodsKinds {
    final out = <String>{};
    for (final id in _cart.keys) {
      final p = _byId(id);
      if (p != null && p.isKindSet) out.add(p.goodsKind);
    }
    return out;
  }

  /// Фақат озиқ ёки фақат но-озиқ бўлса — қарама-қарши тур; акс ҳолда null.
  String? get suggestOppositeKind {
    final kinds = cartGoodsKinds;
    if (kinds.length != 1) return null;
    final only = kinds.first;
    if (only == PlatformProduct.kindFood) return PlatformProduct.kindNonFood;
    if (only == PlatformProduct.kindNonFood) return PlatformProduct.kindFood;
    return null;
  }

  /// Қарши категориядан ақлли таклифлар (нарх яқинлиги + витрина).
  List<PlatformProduct> suggestOppositeProducts({int take = 6}) {
    final target = suggestOppositeKind;
    if (target == null || _cart.isEmpty) return const [];
    final avg = cartTotal / cartItemCount.clamp(1, 999999);
    final pool = _products
        .where(
          (p) =>
              p.goodsKind == target &&
              p.price > 0 &&
              !isInCart(p.id),
        )
        .toList();
    int score(PlatformProduct p) {
      var s = 0;
      if (p.featuredOnHome) s += 30;
      final diff = (p.price - avg).abs();
      if (avg > 0) {
        final ratio = diff / avg;
        if (ratio <= 0.35) {
          s += 40;
        } else if (ratio <= 0.8) {
          s += 22;
        } else if (ratio <= 1.5) {
          s += 10;
        }
      }
      s -= p.sortOrder.clamp(0, 40);
      return s;
    }

    pool.sort((a, b) => score(b).compareTo(score(a)));
    return pool.take(take).toList(growable: false);
  }

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

  void _bindSettings() {
    _settingsSub ??= FirebaseFirestore.instance
        .collection('settings')
        .doc('app')
        .snapshots()
        .listen((snap) {
      final raw = (snap.data()?['platformDeliveryFeePercent'] as num?)
          ?.toDouble();
      final next = (raw != null && raw >= 0 && raw <= 100) ? raw : 5.0;
      if (next == deliveryFeePercent) return;
      deliveryFeePercent = next;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _settingsSub?.cancel();
    _settingsSub = null;
    super.dispose();
  }

  Future<void> init() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    _bindSettings();
    try {
      await restoreCart();
      _products = await _repo.fetchCatalog();
      _pruneMissing();
      await _loadWallet();
    } catch (e) {
      errorMessage = userErrorKey(e, fallbackKey: 'err_load_failed');
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
      // Рағбат — каноник (998…) ҳужжатда (сервер `claimIncentive` шу ерга ёзади).
      final canon = (u != null && u.id == uid12)
          ? u
          : (uid12.length >= 12 ? await FirebaseFirestore.instance.collection('users').doc(uid12).get() : null);
      incentiveBalance = (canon?.data()?['incentiveBalance'] as num?)?.toInt() ?? 0;
      notifyListeners();
      _schedulePreview();
    } catch (_) {}
  }

  void _pruneMissing() {
    // Каталог бўш келса (узилиш/хато) — сақланган саватни ўчирмаймиз:
    // у энди қурилмада сақланади ва бўш жавоб уни йўқотиб юбормасин.
    if (_products.isEmpty) return;
    final before = Map<String, int>.of(_cart);
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
    if (!mapEquals(before, _cart)) _persistCart();
  }

  void addToCart(PlatformProduct p) {
    // Поғонали товарда `price` бўш бўлиши мумкин — нарх поғонадан
    // олинади, шунинг учун таъсирчан нарх текширилади.
    if (!p.inStock || p.priceForQty(p.minQty) <= 0) return;
    final next = (qtyOf(p.id) + p.step).clamp(p.minQty, 999999);
    if (_wouldExceed(p, next)) return;
    _cart[p.id] = next;
    _persistCart();
    notifyListeners();
    _schedulePreview();
  }

  /// Поғонани танлашда саватга қўйиладиган миқдор: поғона бошланиши, `step`
  /// га мослаб юқорига юмалатилган. Қолдиқ етмаса `null` (поғонага
  /// чиқиб бўлмайди). Фақат ҳисоб — UI шуни кўрсатади, нархни сервер ҳисоблайди.
  static int? qtyForTier(PlatformProduct p, int tierMinQty) {
    if (!p.inStock) return null;
    final step = p.step < 1 ? 1 : p.step;
    final base = tierMinQty < p.minQty ? p.minQty : tierMinQty;
    final aligned = base + ((step - (base - p.minQty) % step) % step);
    if (!p.isUnlimitedStock && aligned > p.remaining) return null;
    return aligned;
  }

  /// Харидор поғонани танлади — миқдор шу поғона бошланишига ўтади
  /// (саватда бўлмаса, қўшилади). Миқдорни кўпайтирилса ҳам, камайтирилса ҳам.
  bool selectTier(PlatformProduct p, int tierMinQty) {
    final q = qtyForTier(p, tierMinQty);
    if (q == null || p.priceForQty(q) <= 0) return false;
    _cart[p.id] = q;
    _persistCart();
    notifyListeners();
    _schedulePreview();
    return true;
  }

  void increase(String id) {
    final p = _byId(id);
    if (p == null) return;
    final next = qtyOf(id) + p.step;
    if (_wouldExceed(p, next)) return;
    _cart[id] = next;
    _persistCart();
    notifyListeners();
    _schedulePreview();
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
    _persistCart();
    notifyListeners();
    _schedulePreview();
  }

  void clearCart() {
    _cart.clear();
    useWallet = false;
    _persistCart();
    notifyListeners();
    _schedulePreview();
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
      errorMessage = 'cart_empty';
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
        errorMessage = 'misc_profile_phone_required';
        notifyListeners();
        return (success: false, error: errorMessage);
      }

      final items = <Map<String, dynamic>>[];
      final decrements = <Map<String, dynamic>>[];
      for (final entry in _cart.entries) {
        final p = _byId(entry.key);
        if (p == null) continue;
        final qty = entry.value;
        final unitPrice = p.priceForQty(qty);
        items.add({
          'name': p.name,
          'price': unitPrice,
          'qty': qty,
          'unit': p.unit,
          'total': unitPrice * qty,
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
        errorMessage = 'cart_empty';
        notifyListeners();
        return (success: false, error: errorMessage);
      }

      final apply = walletApplyAmount;
      final incentive = incentiveApplyAmount;
      final orderData = <String, dynamic>{
        'type': 'platform',
        // Сервер шу версия бўйича нархни ҳисоблайди (улгуржи поғоналари,
        // 2026-10-06). Версиясиз буюртма — эски ягона нарх (эски илова).
        'pricingVersion': kPlatformPricingVersion,
        'userName': userName,
        'userPhone': userPhone,
        'address': address,
        'phone': phone.isNotEmpty ? phone : userPhone,
        'items': items,
        // Сервер суммаларни ўзи қайта ҳисоблайди (бонус ҳам); бу ерда — фақат кўриниш/эски ҳисоб.
        'total': netTotal,
        'itemsTotal': cartTotal,
        'deliveryFee': deliveryFee,
        'deliveryFeePercent': deliveryFeePercent,
        'balanceApplied': apply,
        'useWallet': useWallet,
        // AVA бонуси (эга 2026-11-02) — фақат мижоз рози бўлса ва ҳисобда бонус бор бўлса.
        'useIncentive': useIncentive && incentive > 0,
        'cashDue': netTotal - apply,
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
      // `placeOrderPostPaid` xabarlari — developer/aralash tilli matn: l10n
      // kaliti qaytariladi (UI `context.trMsg(error)` bilan chiqaradi).
      errorMessage = userErrorKey(
        e,
        fallbackKey: e.code == 'failed-precondition'
            ? 'misc_stock_insufficient'
            : 'err_unexpected',
        byServerMessage: const {
          'insufficient_balance': 'misc_wallet_insufficient',
        },
      );
      notifyListeners();
      return (success: false, error: errorMessage);
    } catch (e) {
      isSubmitting = false;
      errorMessage = userErrorKey(e);
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
