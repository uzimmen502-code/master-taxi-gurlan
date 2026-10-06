import 'package:ava_gurlan/models/platform_product.dart';
import 'package:ava_gurlan/models/price_tier.dart';
import 'package:ava_gurlan/repositories/platform_products_repository.dart';
import 'package:flutter_test/flutter_test.dart';

PlatformProduct _p(
  String id, {
  int price = 10000,
  bool active = true,
  List<PriceTier> tiers = const [],
}) =>
    PlatformProduct(
      id: id,
      name: 'товар $id',
      price: price,
      active: active,
      priceTiers: tiers,
    );

List<String> _ids(List<PlatformProduct> l) => l.map((e) => e.id).toList();

void main() {
  group('wholesaleEligible — AVA дўкони Улгуржи лентасида (2026-10-06)', () {
    test('ПОҒОНАСИЗ фаол товар ҳам чиқади (аввал чиқмасди — лента бўш эди)',
        () {
      // Продакшн 2026-10-06: 59 фаол товар, поғонали 0 — эски қоида
      // билан Улгуржида AVA товари умуман йўқ эди.
      expect(_ids(PlatformProductsRepository.wholesaleEligible([_p('a')])),
          ['a']);
    });

    test('поғонали товар ҳам чиқади', () {
      final t = [const PriceTier(minQty: 10, price: 9000)];
      expect(
        _ids(PlatformProductsRepository.wholesaleEligible(
            [_p('t', price: 0, tiers: t)])),
        ['t'],
      );
    });

    test('нофаол товар чиқмайди', () {
      expect(
        PlatformProductsRepository.wholesaleEligible([_p('x', active: false)]),
        isEmpty,
      );
    });

    test('нархсиз ва поғонасиз товар чиқмайди («0 сўм» карточка йўқ)', () {
      expect(
        PlatformProductsRepository.wholesaleEligible([_p('z', price: 0)]),
        isEmpty,
      );
    });

    test('40 тадан кўп бўлса ҳам ҲАММАСИ (аввал 40 билан кесиларди)', () {
      final many = [for (var i = 0; i < 59; i++) _p('p$i')];
      expect(PlatformProductsRepository.wholesaleEligible(many).length, 59);
    });

    test('тартиб сақланади', () {
      expect(
        _ids(PlatformProductsRepository.wholesaleEligible(
            [_p('c'), _p('a'), _p('b')])),
        ['c', 'a', 'b'],
      );
    });
  });
}
