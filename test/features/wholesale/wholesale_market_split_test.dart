import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:ava_gurlan/features/wholesale/repositories/wholesale_products_repository.dart';
import 'package:flutter_test/flutter_test.dart';

WholesaleProduct _p(String id, {String market = WholesaleProduct.marketWholesale}) =>
    WholesaleProduct(
      id: id,
      sellerId: '998901234567',
      sellerCompanyName: 'Sunlight',
      title: 'трактор',
      titleLower: 'трактор',
      description: 'd',
      priceTiers: const [WholesalePriceTier(minQty: 1, price: 3800)],
      market: market,
    );

List<String> _ids(List<WholesaleProduct> l) => l.map((e) => e.id).toList();

void main() {
  group('belongsToMarket — Улгуржи ва Хитой бозори ажралиши (2026-10-07)', () {
    test('Хитой маҳсулоти фақат Хитой бозорида', () {
      final p = _p('c', market: WholesaleProduct.marketChina);
      expect(p.belongsToMarket(WholesaleProduct.marketChina), isTrue);
      expect(p.belongsToMarket(WholesaleProduct.marketWholesale), isFalse);
    });

    test('Улгуржи маҳсулоти фақат Улгуржида', () {
      final p = _p('w');
      expect(p.belongsToMarket(WholesaleProduct.marketWholesale), isTrue);
      expect(p.belongsToMarket(WholesaleProduct.marketChina), isFalse);
    });

    test('market майдони бўш эски ёзув — Улгуржи (Хитойга кирмайди)', () {
      final legacy = _p('old', market: '');
      expect(legacy.belongsToMarket(WholesaleProduct.marketWholesale), isTrue);
      expect(legacy.belongsToMarket(WholesaleProduct.marketChina), isFalse);
    });
  });

  group('filterByMarket — админ бўлимлари ва лента', () {
    // Продакшн 2026-10-07: 9 маҳсулот — 7 таси `china`, 2 таси `market`
    // майдонисиз (2026-09-21, Хитой бозори очилишидан олдин).
    final prod = [
      for (var i = 0; i < 7; i++)
        _p('china$i', market: WholesaleProduct.marketChina),
      _p('legacy1', market: ''),
      _p('legacy2', market: ''),
    ];

    test('Хитой бўлимида фақат Хитой маҳсулотлари', () {
      final china = WholesaleProductsRepository.filterByMarket(
          prod, WholesaleProduct.marketChina);
      expect(china.length, 7);
      expect(china.every((p) => p.isChina), isTrue);
    });

    test('Улгуржи бўлимида Хитой маҳсулоти йўқ (аввал аралаш эди)', () {
      final wholesale = WholesaleProductsRepository.filterByMarket(
          prod, WholesaleProduct.marketWholesale);
      expect(_ids(wholesale), ['legacy1', 'legacy2']);
      expect(wholesale.any((p) => p.isChina), isFalse);
    });

    test('иккала бўлим биргаликда ҳаммасини қамрайди, кесишмайди', () {
      final a = WholesaleProductsRepository.filterByMarket(
          prod, WholesaleProduct.marketWholesale);
      final b = WholesaleProductsRepository.filterByMarket(
          prod, WholesaleProduct.marketChina);
      expect(a.length + b.length, prod.length);
      expect(_ids(a).toSet().intersection(_ids(b).toSet()), isEmpty);
    });

    test('тартиб сақланади', () {
      final l = [_p('z'), _p('a'), _p('m')];
      expect(
        _ids(WholesaleProductsRepository.filterByMarket(
            l, WholesaleProduct.marketWholesale)),
        ['z', 'a', 'm'],
      );
    });

    test('бўш рўйхат — бўш', () {
      expect(
        WholesaleProductsRepository.filterByMarket(
            const [], WholesaleProduct.marketChina),
        isEmpty,
      );
    });
  });

  group('moduleIdFor — ҳар бозорнинг ўз дарвозаси', () {
    test('Хитой — china_market', () {
      expect(WholesaleProduct.moduleIdFor(WholesaleProduct.marketChina),
          'china_market');
    });

    test('Улгуржи — wholesale_market', () {
      expect(WholesaleProduct.moduleIdFor(WholesaleProduct.marketWholesale),
          'wholesale_market');
    });

    test('бўш/эски қиймат — wholesale_market', () {
      expect(WholesaleProduct.moduleIdFor(''), 'wholesale_market');
    });
  });
}
