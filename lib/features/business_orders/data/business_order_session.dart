// Сессия ҳолати: сотувчи бўйича сават ва дарвоза жавоби кеши (сервер ҳолати эмас).
//
// Сават — «Бозорлар» STAGE 11 (эга 2026-11-16): ЯГОНА «Сават» экрани, сотувчи бўйича гуруҳ (объект —
// `businessId`, ўз дўкони — `shop:<телефон>`, [businessCartKey]). Қурилмада фойдаланувчи телефони бўйича сақланади
// ([BusinessCartPersistence], мавжуд `PlatformCartStore` усули — SharedPreferences): бир қурилмада бошқа аккаунт
// кирса, эскисининг саватини кўрмайди. Нарх — фақат кўрсатиш учун; якуний нарх сервер квотасидан (18-қоида).
//
// Дарвоза (`getBusinessOrdersAccess`) — калит бўйича 5 дақиқа кешланади: ҳар маҳсулот варағи очилганда янги
// чақирув бўлмасин (37-қоида). Ёпиқ жавоб ҳам кешланади; хато — кешланмайди (кейинги очилишда қайта сўралади).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../tv_market/models/tv_shop.dart';
import '../domain/business_order.dart';

/// Сават ёзувини қурилмада сақлаш (`biz_cart_v1_<телефон рақамлари>`).
class BusinessCartPersistence {
  const BusinessCartPersistence();

  static const _prefix = 'biz_cart_v1_';
  static const _guest = 'guest';

  String keyFor(String phone) {
    final digits = phoneDigits(phone);
    return '$_prefix${digits.isEmpty ? _guest : digits}';
  }

  Future<String> currentKey() async {
    final prefs = await SharedPreferences.getInstance();
    return keyFor(prefs.getString('user_phone') ?? '');
  }

  /// Бузилган ёзув — бўш рўйхат (экран ишлайверади).
  Future<List<BusinessCart>> load(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      final list = decoded is Map ? decoded['carts'] : null;
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (BusinessCart.fromJson(e) case final BusinessCart c when c.isNotEmpty) c,
      ];
    } catch (e) {
      debugPrint('[BusinessCartPersistence] load: $e');
      return const [];
    }
  }

  Future<void> save(String key, Iterable<BusinessCart> carts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nonEmpty = [for (final c in carts) if (c.isNotEmpty) c.toJson()];
      if (nonEmpty.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, jsonEncode({'v': 1, 'carts': nonEmpty}));
      }
    } catch (e) {
      debugPrint('[BusinessCartPersistence] save: $e');
    }
  }
}

class BusinessCartStore extends ChangeNotifier {
  /// [persistence] — `null` бўлса фақат хотирада (тестлар, эски чақирувчилар).
  BusinessCartStore({this.persistence});

  /// Иловадаги ягона сават омбори (қурилмада сақланади).
  static final BusinessCartStore instance = BusinessCartStore(persistence: const BusinessCartPersistence());

  final BusinessCartPersistence? persistence;
  final Map<String, BusinessCart> _carts = {};

  /// Юкланган ёзув калити (фойдаланувчи алмашса — қайта юкланади).
  String? _loadedKey;
  Future<void>? _loading;
  Future<void> _saving = Future.value();

  /// Сақлаш тугашини кутиш (тест учун).
  @visibleForTesting
  Future<void> get saved => _saving;

  /// Қурилмадаги саватни юклайди (бир марта; фойдаланувчи алмашса — янгиси). Хотирадаги ўзгаришлар устидан
  /// ёзилмайди: юкланган сават фақат хотирада йўқ сотувчилар учун қўшилади.
  Future<void> ensureLoaded() {
    final p = persistence;
    if (p == null) return Future.value();
    return _loading ??= () async {
      try {
        final key = await p.currentKey();
        if (key == _loadedKey) return;
        if (_loadedKey != null) _carts.clear();
        _loadedKey = key;
        final loaded = await p.load(key);
        for (final c in loaded) {
          _carts.putIfAbsent(c.key, () => c);
        }
        notifyListeners();
      } catch (e) {
        debugPrint('[BusinessCartStore] load: $e');
      } finally {
        _loading = null;
      }
    }();
  }

  /// Объект савати (йўқ бўлса бўш сават яратилади).
  BusinessCart cartFor(String businessId, {String businessName = ''}) {
    final c = _carts.putIfAbsent(businessId, () => BusinessCart(businessId: businessId));
    if (businessName.isNotEmpty) c.businessName = businessName;
    return c;
  }

  /// Таклиф сотувчисининг савати (объект ёки ўз дўкони).
  BusinessCart cartForItem(TvShopItem item, {String sellerName = ''}) {
    final key = businessCartKey(businessId: item.businessId, ownerPhone: item.ownerPhone);
    final c = _carts.putIfAbsent(
      key,
      () => BusinessCart(businessId: item.businessId, ownerPhone: item.ownerPhone),
    );
    if (sellerName.isNotEmpty) c.businessName = sellerName;
    return c;
  }

  BusinessCart? existing(String key) => _carts[key];

  /// Бўш бўлмаган саватлар (сотувчи гуруҳлари, қўшилиш тартибида).
  List<BusinessCart> get carts => [for (final c in _carts.values) if (c.isNotEmpty) c];

  /// Нишон сони — барча саватлардаги қаторлар.
  int get linesCount => _carts.values.fold<int>(0, (s, c) => s + c.lines.length);

  /// Сават ўзгарганини билдириш (қатор қўшилди/ўчирилди) — қурилмага ҳам ёзилади.
  void changed() {
    notifyListeners();
    _persist();
  }

  void clear(String key) {
    _carts.remove(key);
    notifyListeners();
    _persist();
  }

  void _persist() {
    final p = persistence;
    if (p == null) return;
    final snapshot = [for (final c in _carts.values) if (c.isNotEmpty) c];
    _saving = _saving.then((_) async {
      try {
        final key = _loadedKey ?? await p.currentKey();
        await p.save(key, snapshot);
      } catch (e) {
        debugPrint('[BusinessCartStore] save: $e');
      }
    });
  }
}

class BusinessOrdersAccessCache {
  BusinessOrdersAccessCache({DateTime Function()? now, this.ttl = const Duration(minutes: 5)})
      : _now = now ?? DateTime.now;

  static final BusinessOrdersAccessCache instance = BusinessOrdersAccessCache();

  final DateTime Function() _now;
  final Duration ttl;
  final Map<String, (BusinessOrdersAccess, DateTime)> _byKey = {};

  /// [key] — `businessId` ёки `item:<itemId>` (ўз дўкони маҳсулоти). [load] фақат кеш йўқ ёки эскирганда.
  Future<BusinessOrdersAccess> get(String key, Future<BusinessOrdersAccess> Function() load) async {
    final hit = _byKey[key];
    if (hit != null && _now().difference(hit.$2) < ttl) return hit.$1;
    final a = await load();
    // Хато ([BusinessOrdersAccess.closed] — сабабсиз) кешланмайди.
    if (a.allowed || a.reason.isNotEmpty) _byKey[key] = (a, _now());
    return a;
  }

  @visibleForTesting
  void clear() => _byKey.clear();
}
