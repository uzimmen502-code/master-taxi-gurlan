import 'package:ava_gurlan/features/platform_store/controllers/platform_store_controller.dart';
import 'package:ava_gurlan/features/platform_store/services/platform_cart_store.dart';
import 'package:ava_gurlan/models/platform_product.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Нуқсон (2026-10-17): AVA товари тафсилотида саватга қўйилган товарлар
/// «орқага» босилганда йўқолар эди — сават фақат хотирада, контроллер эса
/// маршрут билан яратилиб, у ёпилганда ўлар эди (`openPlatformProductDetail`).
void main() {
  const product = PlatformProduct(id: 'p1', name: 'Помидор', price: 12000);

  setUp(() => SharedPreferences.setMockInitialValues({'user_phone': '998901112233'}));

  PlatformStoreController newController() =>
      PlatformStoreController(cartStore: PlatformCartStore());

  test('регрессия: «орқага» (контроллер ўлиши) дан кейин сават қайта тикланади',
      () async {
    final first = newController();
    first.addToCart(product);
    await first.cartSaved; // сақлаш тугашини кутамиз
    first.dispose();

    final second = newController(); // тафсилот қайта очилди
    await second.restoreCart();
    expect(second.qtyOf('p1'), 1);
    expect(second.cartItemCount, 1);
  });

  test('сават тозаланса — тикланмайди (бўш ҳолат ҳам сақланади)', () async {
    final first = newController();
    first.addToCart(product);
    first.clearCart();
    await first.cartSaved;

    final second = newController();
    await second.restoreCart();
    expect(second.cart, isEmpty);
  });

  test('бошқа фойдаланувчининг саватини кўрмайди (бир қурилма)', () async {
    // Қурилмада A нинг сават калити бор, лекин ҳозир B кирган.
    final store = PlatformCartStore();
    SharedPreferences.setMockInitialValues({
      'user_phone': '998907778899', // B
      store.keyFor('998901112233'): '{"p1":1}', // A нинг саватни
    });
    expect(await store.load(), isEmpty);
  });

  group('PlatformCartStore (чегара ҳолатлар)', () {
    test('бузилган JSON — бўш сават, хато чиқмайди', () async {
      final store = PlatformCartStore();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(store.keyFor('998901112233'), '{not json');
      expect(await store.load(), isEmpty);
    });

    test('нол ва манфий миқдорлар ташлаб юборилади', () async {
      final store = PlatformCartStore();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        store.keyFor('998901112233'),
        '{"a":3,"b":0,"c":-2,"d":"x"}',
      );
      expect(await store.load(), {'a': 3});
    });

    test('сақла → юкла бир хил натижа беради', () async {
      final store = PlatformCartStore();
      await store.save({'a': 5, 'b': 12});
      expect(await store.load(), {'a': 5, 'b': 12});
    });
  });
}
