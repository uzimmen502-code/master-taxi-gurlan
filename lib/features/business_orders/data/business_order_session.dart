// Сессия ҳолати: объект бўйича сават ва дарвоза жавоби кеши (фақат хотирада — сервер ҳолати эмас).
//
// Сават — илова очиқ турганда сақланади (ресторан саватидаги каби; қурилмага ёзилмайди). Дарвоза
// (`getBusinessOrdersAccess`) — объект бўйича 5 дақиқа кешланади: ҳар маҳсулот варағи очилганда янги чақирув
// бўлмасин (37-қоида). Ёпиқ жавоб ҳам кешланади; хато — кешланмайди (кейинги очилишда қайта сўралади).

import 'package:flutter/foundation.dart';

import '../domain/business_order.dart';

class BusinessCartStore extends ChangeNotifier {
  BusinessCartStore();

  /// Иловадаги ягона сават омбори.
  static final BusinessCartStore instance = BusinessCartStore();

  final Map<String, BusinessCart> _carts = {};

  /// Объект савати (йўқ бўлса бўш сават яратилади).
  BusinessCart cartFor(String businessId, {String businessName = ''}) {
    final c = _carts.putIfAbsent(businessId, () => BusinessCart(businessId: businessId));
    if (businessName.isNotEmpty) c.businessName = businessName;
    return c;
  }

  BusinessCart? existing(String businessId) => _carts[businessId];

  /// Сават ўзгарганини билдириш (қатор қўшилди/ўчирилди).
  void changed() => notifyListeners();

  void clear(String businessId) {
    _carts.remove(businessId);
    notifyListeners();
  }
}

class BusinessOrdersAccessCache {
  BusinessOrdersAccessCache({DateTime Function()? now, this.ttl = const Duration(minutes: 5)})
      : _now = now ?? DateTime.now;

  static final BusinessOrdersAccessCache instance = BusinessOrdersAccessCache();

  final DateTime Function() _now;
  final Duration ttl;
  final Map<String, (BusinessOrdersAccess, DateTime)> _byKey = {};

  /// [load] фақат кеш йўқ ёки эскирганда чақирилади.
  Future<BusinessOrdersAccess> get(String businessId, Future<BusinessOrdersAccess> Function() load) async {
    final hit = _byKey[businessId];
    if (hit != null && _now().difference(hit.$2) < ttl) return hit.$1;
    final a = await load();
    // Хато ([BusinessOrdersAccess.closed] — сабабсиз) кешланмайди.
    if (a.allowed || a.reason.isNotEmpty) _byKey[businessId] = (a, _now());
    return a;
  }

  @visibleForTesting
  void clear() => _byKey.clear();
}
