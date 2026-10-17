import 'package:ava_gurlan/features/platform_store/controllers/platform_store_controller.dart';
import 'package:ava_gurlan/features/platform_store/services/platform_cart_store.dart';
import 'package:ava_gurlan/models/platform_product.dart';
import 'package:ava_gurlan/models/price_tier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Харидор нарх поғонасини босиб танлайди (2026-10-17): миқдор поғона
/// бошланишига ўтади, нарх эса ўша `priceForQty`дан — серверга мос.
void main() {
  PlatformProduct product({
    int step = 1,
    int minQty = 1,
    int totalStock = 0,
    int soldToday = 0,
  }) =>
      PlatformProduct(
        id: 'p1',
        name: 'Помидор',
        price: 12000,
        step: step,
        minQty: minQty,
        totalStock: totalStock,
        soldToday: soldToday,
        priceTiers: const [
          PriceTier(minQty: 1, price: 14000),
          PriceTier(minQty: 10, price: 12000),
          PriceTier(minQty: 50, price: 10500),
        ],
        createdAt: DateTime.utc(2026, 10, 10),
      );

  setUp(() => SharedPreferences.setMockInitialValues({'user_phone': '998901112233'}));

  PlatformStoreController ctrl() =>
      PlatformStoreController(cartStore: PlatformCartStore());

  group('qtyForTier', () {
    test('лимитсиз товар: поғона бошланиши аниқ шу', () {
      expect(PlatformStoreController.qtyForTier(product(), 1), 1);
      expect(PlatformStoreController.qtyForTier(product(), 10), 10);
      expect(PlatformStoreController.qtyForTier(product(), 50), 50);
    });

    test('step=5, minQty=5: 10 га тўғри келади, 12 эмас; 50 → 50', () {
      final p = product(step: 5, minQty: 5);
      expect(PlatformStoreController.qtyForTier(p, 10), 10);
      expect(PlatformStoreController.qtyForTier(p, 1), 5); // minQty дан кам эмас
    });

    test('step=4, minQty=1: поғона 10 → 13 (1,5,9,13…), юқорига юмалатилади', () {
      final p = product(step: 4, minQty: 1);
      expect(PlatformStoreController.qtyForTier(p, 10), 13);
      expect(p.priceForQty(13), 12000); // 10–49 поғонасида қолади
    });

    test('чегара: қолдиқ 49 бўлса 50+ поғонага чиқиб бўлмайди, 10 га бўлади', () {
      final p = product(totalStock: 49);
      expect(PlatformStoreController.qtyForTier(p, 50), isNull);
      expect(PlatformStoreController.qtyForTier(p, 10), 10);
    });

    test('чегара: қолдиқ аниқ 50 бўлса 50 га бўлади', () {
      expect(PlatformStoreController.qtyForTier(product(totalStock: 50), 50), 50);
    });

    test('қолдиқ тугаган товар — поғона танланмайди', () {
      final p = product(totalStock: 10, soldToday: 10);
      expect(PlatformStoreController.qtyForTier(p, 1), isNull);
    });
  });

  group('selectTier', () {
    test('саватда йўқ товар — танланганда поғона миқдори билан қўшилади', () {
      final c = ctrl();
      expect(c.selectTier(product(), 10), isTrue);
      expect(c.qtyOf('p1'), 10);
    });

    test('юқори поғонадан паст поғонага қайтиш ҳам ишлайди', () {
      final c = ctrl();
      c.selectTier(product(), 50);
      c.selectTier(product(), 1);
      expect(c.qtyOf('p1'), 1);
    });

    test('етмайдиган поғона — сават ўзгармайди, false', () {
      final c = ctrl();
      final p = product(totalStock: 20);
      c.selectTier(p, 10);
      expect(c.selectTier(p, 50), isFalse);
      expect(c.qtyOf('p1'), 10);
    });

    test('танлов қурилмага сақланади («орқага»дан кейин тикланади)', () async {
      final first = ctrl();
      first.selectTier(product(), 50);
      await first.cartSaved;

      final second = ctrl();
      await second.restoreCart();
      expect(second.qtyOf('p1'), 50);
    });
  });

  test('сумма = поғона нархи × миқдор, чегарада нарх сакрайди', () {
    final p = product();
    expect(p.priceForQty(9) * 9, 126000);
    expect(p.priceForQty(10) * 10, 120000); // 10 кг 9 кгдан арзон
    expect(p.priceForQty(49) * 49, 588000);
    expect(p.priceForQty(50) * 50, 525000);
  });
}
