import 'package:flutter/foundation.dart';

import '../../core/geo/geo_context.dart';

import 'data/supermarket_repository.dart';
import 'domain/sm_access.dart';
import 'domain/sm_cart.dart';
import 'domain/sm_offer.dart';
import 'domain/sm_taxonomy.dart';

/// Супермаркет экранлари учун ягона ҳолат: таксономия, таклифлар, сават, рухсат.
/// Экранлар уни конструктор орқали олади (Provider шарт эмас — модул ичида).
class SupermarketController extends ChangeNotifier {
  SupermarketController({SupermarketApi? api, SmCartStore? cartStore})
      : api = api ?? FirebaseSupermarketApi(),
        _store = cartStore ?? SmCartStore();

  final SupermarketApi api;
  final SmCartStore _store;

  SmTaxonomy taxonomy = SmTaxonomy.empty;
  Map<String, SmOffer> offers = const {};
  Map<String, List<SmOffer>> offersByGroup = const {};
  SmCart cart = SmCart.empty;
  SmAccess access = SmAccess.denied;

  /// Етказиш ҳудуди: сукут — профиль тумани; фойдаланувчи ўзгартира олади (профилга ёзилмайди).
  GeoArea? _deliveryArea;
  GeoArea get deliveryArea => _deliveryArea ?? GeoContext.home;
  set deliveryArea(GeoArea a) {
    _deliveryArea = a;
    notifyListeners();
  }

  bool loading = false;
  String? loadErrorKey;

  Future<void> load() async {
    loading = true;
    loadErrorKey = null;
    notifyListeners();
    try {
      cart = await _store.load();
      final tx = await api.loadTaxonomy();
      final list = await api.loadOffers(tx);
      access = await SupermarketAccessCache.get(api);
      _setCatalog(tx, list);
    } catch (e) {
      debugPrint('[Supermarket] SUPERMARKET_LOAD_FAILED: $e');
      loadErrorKey = e is SmCallError ? e.key : 'sm_err_load';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  @visibleForTesting
  void setCatalogForTest(SmTaxonomy tx, List<SmOffer> list, {SmAccess? access, SmCart? cart}) {
    if (access != null) this.access = access;
    if (cart != null) this.cart = cart;
    _setCatalog(tx, list);
    notifyListeners();
  }

  void _setCatalog(SmTaxonomy tx, List<SmOffer> list) {
    taxonomy = tx;
    offers = {for (final o in list) o.id: o};
    final by = <String, List<SmOffer>>{};
    for (final o in list) {
      if (o.visible) (by[o.groupId] ??= []).add(o);
    }
    offersByGroup = by;
  }

  /// Гуруҳда кўринадиган таклифлари борлар (категория экрани учун).
  List<SmGroup> visibleGroups(SmCategory c) =>
      [for (final g in c.groups) if ((offersByGroup[g.id] ?? const []).isNotEmpty) g];

  SmCartTotals get totals =>
      smCartTotals(cart, offers, feePercent: access.feePercent, weighHoldPercent: access.weighHoldPercent);

  void _setCart(SmCart next) {
    cart = next;
    notifyListeners();
    _store.save(next);
  }

  void addToCart(String productId, int qtyMilli) => _setCart(cart.add(productId, qtyMilli));
  void setQty(String productId, int qtyMilli) => _setCart(cart.setQty(productId, qtyMilli));
  void removeLine(String productId) => _setCart(cart.remove(productId));
  void replaceOffer(String oldId, String newId, int qtyMilli) => _setCart(cart.replaceOffer(oldId, newId, qtyMilli));
  void clearCart() => _setCart(SmCart.empty);

  /// Танланган туман учун рухсат ва вақтлар (расмийлаштириш). Хато — рад (хавфсиз томон).
  Future<SmAccess> refreshAccessFor(String districtId) async {
    try {
      access = await api.getAccess(districtId: districtId);
    } on SmCallError catch (e) {
      access = SmAccess(allowed: false, reason: e.code, messages: e.messages);
    } catch (e) {
      debugPrint('[Supermarket] SUPERMARKET_ACCESS_FAILED: $e');
      access = SmAccess.denied;
    }
    notifyListeners();
    return access;
  }
}
