import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/sm_lists_repository.dart';
import 'domain/sm_basket.dart';
import 'domain/sm_list.dart';
import 'domain/sm_offer.dart';
import 'supermarket_controller.dart';

/// Шу қурилмада танланган саватча id (кўп рўйхатли эски мижоз — саватча «сакраб» кетмасин). Йўқолса — [smPickBasket]
/// қоидаси (энг охирги рўйхат). Сервер ҳужжатига ёзилмайди (rules ўзгармайди).
class SmBasketPointer {
  static const _key = 'sm_basket_list_id_v1';

  Future<String> load() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_key) ?? '';
    } catch (e) {
      debugPrint('[SmBasketPointer] load: $e');
      return '';
    }
  }

  Future<void> save(String id) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, id);
    } catch (e) {
      debugPrint('[SmBasketPointer] save: $e');
    }
  }
}

/// «Менинг ҳафталик харид саватчам» ҳолати: тўр, гуруҳ экрани ва пастки панел БИТТА манбадан ўқийди (ҳар қўшишда
/// панел дарҳол янгиланади). Сақлаш — кечиктирилган (ҳар босишда Firestore'га ёзилмайди, 37-банд), кетма-кет.
class SmBasketController extends ChangeNotifier {
  SmBasketController({
    required this.supermarket,
    required this.store,
    SmListPriceMemo? memo,
    SmBasketPointer? pointer,
    this.saveDelay = const Duration(milliseconds: 700),
    this.defaultName = '',
  })  : memo = memo ?? SmListPriceMemo(),
        pointer = pointer ?? SmBasketPointer();

  final SupermarketController supermarket;
  final SmListsStore store;
  final SmListPriceMemo memo;
  final SmBasketPointer pointer;
  final Duration saveDelay;

  /// Янги саватча номи (ҳужжат `name` 1..40 шарт) — экран 3 тилдан беради.
  final String defaultName;

  SmList basket = const SmList(id: '', name: '');
  List<SmList> others = const [];
  bool loaded = false;
  bool loadError = false;

  /// Охирги сақлаш хатоси (кўрсатиш учун; кейинги ўзгаришда қайта уринилади).
  bool saveError = false;

  Timer? _timer;
  Future<void> _chain = Future.value();
  bool _dirty = false;
  bool _disposed = false;

  Future<void> load() async {
    loadError = false;
    _notify();
    try {
      final lists = await store.load();
      final remembered = await pointer.load();
      final p = smPickBasket(lists, remembered: remembered);
      basket = p.basket ?? SmList(id: '', name: defaultName);
      others = p.others;
      if (basket.id.isNotEmpty && basket.id != remembered) await pointer.save(basket.id);
      loaded = true;
    } catch (e) {
      debugPrint('[Supermarket] SM_BASKET_LOAD_FAILED: $e');
      loadError = true;
    }
    _notify();
  }

  SmBasketTotals get totals => smBasketTotals(basket, supermarket.offers, supermarket.offersByGroup);

  int qtyOf(String offerId) => smBasketQtyOf(basket, offerId);

  void setOffer(SmOffer o, int qtyMilli) => _edit(smBasketSetOffer(basket, o, qtyMilli));
  void setQtyAt(int index, int qtyMilli) => _edit(basket.setQtyAt(index, qtyMilli));
  void removeAt(int index) => _edit(basket.removeAt(index));
  void setRemind(SmRemind r) => _edit(basket.copyWith(remind: r));

  void _edit(SmList next) {
    if (identical(next, basket)) return;
    basket = next;
    _dirty = true;
    _notify();
    _timer?.cancel();
    _timer = Timer(saveDelay, flush);
  }

  /// Кутаётган ўзгаришни дарҳол сақлаш (экрандан чиқишда, расмийлаштиришдан олдин).
  Future<void> flush() {
    _timer?.cancel();
    if (!_dirty) return _chain;
    _dirty = false;
    final snapshot = basket;
    _chain = _chain.then((_) => _save(snapshot));
    return _chain;
  }

  Future<void> _save(SmList snapshot) async {
    try {
      final name = snapshot.name.trim().isEmpty ? defaultName : snapshot.name;
      var id = basket.id;
      if (id.isEmpty) {
        // Биринчи сақлаш — `weekly_basket` ҳужжати (create). Шу орада бошқа ўзгариш бўлса — кейинги навбатда update.
        id = await store.create(SmList(id: kSmBasketListId, name: name, items: snapshot.items, remind: snapshot.remind));
        basket = SmList(id: id, name: name, items: basket.items, remind: basket.remind);
        await pointer.save(id);
      } else {
        await store.update(SmList(
          id: id,
          name: name,
          items: snapshot.items,
          remind: snapshot.remind,
          occasionId: snapshot.occasionId,
        ));
      }
      await memo.save(id, smPricesOf(snapshot.items, supermarket.offers));
      saveError = false;
    } catch (e) {
      debugPrint('[Supermarket] SM_BASKET_SAVE_FAILED: $e');
      saveError = true;
      _dirty = true;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (_dirty) unawaited(flush());
    super.dispose();
  }
}
