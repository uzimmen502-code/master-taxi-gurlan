import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:flutter_test/flutter_test.dart';

Restaurant _r(String id) => Restaurant(id: id, name: 'R$id', status: 'approved');
MenuItem _m(String id, int price, {String cat = 'c1', int pack = 0}) =>
    MenuItem(id: id, name: id, price: price, categoryId: cat, packagingFee: pack);

void main() {
  group('RestaurantCart', () {
    test('qo\'shish, sanash, yig\'indi — butun so\'m', () {
      final cart = RestaurantCart();
      expect(cart.add(_m('osh', 40000), restaurant: _r('a')), isTrue);
      expect(cart.add(_m('somsa', 10000, pack: 500), restaurant: _r('a')), isTrue);
      expect(cart.add(_m('somsa', 10000, pack: 500), restaurant: _r('a')), isTrue);
      expect(cart.count, 3);
      expect(cart.itemsTotal, 60000);
      expect(cart.packagingTotal, 1000);
      expect(cart.qtyOf('somsa'), 2);
      expect(cart.restaurantId, 'a');
      expect(cart.restaurantName, 'Ra');
      expect(cart.toOrderItems(), [
        {'itemId': 'osh', 'qty': 1},
        {'itemId': 'somsa', 'qty': 2},
      ]);
    });

    test('bitta restoran — bitta savat: boshqasidan qo\'shish rad, replaceWith tozalab boshlaydi', () {
      final cart = RestaurantCart();
      cart.add(_m('osh', 40000), restaurant: _r('a'));
      expect(cart.add(_m('lagmon', 35000), restaurant: _r('b')), isFalse);
      expect(cart.count, 1, reason: 'rad etilganda savat o\'zgarmaydi');
      cart.replaceWith(_m('lagmon', 35000), restaurant: _r('b'));
      expect(cart.restaurantId, 'b');
      expect(cart.lines.single.item.id, 'lagmon');
    });

    test('kamaytirish → o\'chirish → bo\'sh savat restoranni bo\'shatadi', () {
      final cart = RestaurantCart();
      cart.add(_m('osh', 40000), restaurant: _r('a'));
      cart.add(_m('osh', 40000), restaurant: _r('a'));
      cart.decrement('osh');
      expect(cart.qtyOf('osh'), 1);
      cart.decrement('osh');
      expect(cart.isEmpty, isTrue);
      expect(cart.restaurantId, isNull, reason: 'endi boshqa restorandan qo\'shish mumkin');
      expect(cart.add(_m('x', 1000), restaurant: _r('b')), isTrue);
    });

    test('kategoriya bo\'yicha sanash (chap ustun badge) va maxQty chegarasi', () {
      final cart = RestaurantCart();
      for (var i = 0; i < RestaurantCart.maxQty + 5; i++) {
        cart.add(_m('osh', 1000, cat: 'c1'), restaurant: _r('a'));
      }
      cart.add(_m('cola', 500, cat: 'c2'), restaurant: _r('a'));
      expect(cart.qtyOf('osh'), RestaurantCart.maxQty);
      expect(cart.countInCategory('c1'), RestaurantCart.maxQty);
      expect(cart.countInCategory('c2'), 1);
      expect(cart.countInCategory('c9'), 0);
    });

    test('notifyListeners — har o\'zgarishda', () {
      final cart = RestaurantCart();
      var n = 0;
      cart.addListener(() => n++);
      cart.add(_m('osh', 1000), restaurant: _r('a'));
      cart.decrement('osh');
      cart.clear();
      expect(n, 2, reason: 'bo\'sh savatni tozalash xabar bermaydi');
    });
  });
}
