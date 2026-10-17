import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:ava_gurlan/features/wholesale/utils/wholesale_similar.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_tier_picker.dart';
import 'package:ava_gurlan/models/price_tier.dart';
import 'package:flutter_test/flutter_test.dart';

WholesaleProduct _p(
  String id, {
  String title = 'Помидор',
  String seller = 's1',
  String status = WholesaleProduct.statusActive,
  String market = WholesaleProduct.marketWholesale,
  List<PriceTier>? tiers,
  DateTime? createdAt,
}) =>
    WholesaleProduct(
      id: id,
      sellerId: seller,
      sellerCompanyName: 'Фирма $seller',
      title: title,
      titleLower: title.toLowerCase(),
      description: '',
      priceTiers: tiers ??
          const [
            PriceTier(minQty: 1, price: 14000),
            PriceTier(minQty: 10, price: 12000),
            PriceTier(minQty: 50, price: 10500),
          ],
      status: status,
      market: market,
      createdAt: createdAt,
    );

void main() {
  group('поғона қоидаси (activeTierIndex / tierPriceForQty)', () {
    const tiers = [
      PriceTier(minQty: 1, price: 14000),
      PriceTier(minQty: 10, price: 12000),
      PriceTier(minQty: 50, price: 10500),
    ];

    test('чегара: 9→1-поғона, 10→2-, 49→2-, 50→3-', () {
      expect(activeTierIndex(tiers, 9), 0);
      expect(activeTierIndex(tiers, 10), 1);
      expect(activeTierIndex(tiers, 49), 1);
      expect(activeTierIndex(tiers, 50), 2);
    });

    test('биринчи поғонадан кам миқдор — энг паст поғона', () {
      const t = [PriceTier(minQty: 5, price: 100), PriceTier(minQty: 20, price: 80)];
      expect(activeTierIndex(t, 1), 0);
      expect(tierPriceForQty(t, 1), 100);
    });

    test('поғона йўқ: индекс -1, нарх null', () {
      expect(activeTierIndex(const [], 5), -1);
      expect(tierPriceForQty(const [], 5), isNull);
    });

    test('nextTierAfter: охирги поғонада null', () {
      expect(nextTierAfter(tiers, 12)!.minQty, 50);
      expect(nextTierAfter(tiers, 50), isNull);
    });

    test('WholesaleProduct.priceForQty сумма: 9×14000 ва 10×12000', () {
      final p = _p('a');
      expect(p.priceForQty(9) * 9, 126000);
      expect(p.priceForQty(10) * 10, 120000);
    });
  });

  group('clampWholesaleQty', () {
    test('минимал буюртмадан кам — минимумга', () => expect(clampWholesaleQty(2, 5), 5));
    test('нол ва манфий — минимумга', () {
      expect(clampWholesaleQty(0, 1), 1);
      expect(clampWholesaleQty(-7, 3), 3);
    });
    test('юқори чегара', () => expect(clampWholesaleQty(99999999, 1), kWholesaleMaxQty));
    test('ичида — ўзгармайди', () => expect(clampWholesaleQty(37, 5), 37));
  });

  group('similarWholesale', () {
    test('фақат БОШҚА сотувчилар, ўзи ва фаол бўлмаганлар кирмайди', () {
      final cur = _p('cur');
      final pool = [
        cur,
        _p('same-seller', seller: 's1'),
        _p('other', seller: 's2'),
        _p('pending', seller: 's3', status: WholesaleProduct.statusPending),
      ];
      expect(similarWholesale(cur, pool).map((e) => e.id), ['other']);
    });

    test('алоқасиз ном ўхшаш эмас', () {
      final cur = _p('cur');
      final pool = [_p('x', title: 'Кабель', seller: 's2')];
      expect(similarWholesale(cur, pool), isEmpty);
    });

    test('кирилл/лотин ёзув бир хил ҳисобланади', () {
      final cur = _p('cur', title: 'Помидор');
      final pool = [_p('lat', title: 'Pomidor qizil', seller: 's2')];
      expect(similarWholesale(cur, pool).map((e) => e.id), ['lat']);
    });

    test('Хитой ва Улгуржи аралашмайди', () {
      final cur = _p('cur');
      final pool = [_p('cn', seller: 's2', market: WholesaleProduct.marketChina)];
      expect(similarWholesale(cur, pool), isEmpty);
    });

    test('тартиб: кўпроқ умумий сўз, кейин арзонроқ бошланғич нарх', () {
      final cur = _p('cur', title: 'Қизил помидор');
      final pool = [
        _p('one-word', title: 'Помидор', seller: 's2'),
        _p('two-words', title: 'Қизил помидор', seller: 's3'),
        _p(
          'cheap-one-word',
          title: 'Помидор',
          seller: 's4',
          tiers: const [PriceTier(minQty: 1, price: 9000)],
        ),
      ];
      expect(similarWholesale(cur, pool).map((e) => e.id),
          ['two-words', 'cheap-one-word', 'one-word']);
    });

    test('limit', () {
      final cur = _p('cur');
      final pool = [for (var i = 0; i < 20; i++) _p('p$i', seller: 's${i + 2}')];
      expect(similarWholesale(cur, pool, limit: 5), hasLength(5));
    });
  });

  group('wholesaleSwipeList', () {
    test('лента тартиби сақланади, фаол бўлмаган ва бошқа бозор тушмайди', () {
      final cur = _p('b');
      final pool = [
        _p('a', seller: 's2'),
        cur,
        _p('off', status: WholesaleProduct.statusInactive),
        _p('cn', market: WholesaleProduct.marketChina),
        _p('c', seller: 's3'),
      ];
      expect(wholesaleSwipeList(cur, pool).map((e) => e.id), ['a', 'b', 'c']);
    });

    test('жорий товар лентада йўқ — бошида туради', () {
      final cur = _p('x');
      expect(
        wholesaleSwipeList(cur, [_p('a'), _p('b')]).map((e) => e.id),
        ['x', 'a', 'b'],
      );
    });

    test('лента бўш — фақат жорий (свайп йўқ)', () {
      final cur = _p('x');
      expect(wholesaleSwipeList(cur, const []).map((e) => e.id), ['x']);
    });

    test('жорий товар фаол бўлмаса ҳам рўйхатда қолади', () {
      final cur = _p('x', status: WholesaleProduct.statusPending);
      expect(wholesaleSwipeList(cur, [cur, _p('a')]).map((e) => e.id), ['x', 'a']);
    });
  });

  group('sellerOthers', () {
    test('шу сотувчининг бошқа фаол товарлари, янгиси биринчи', () {
      final cur = _p('cur');
      final pool = [
        cur,
        _p('old', title: 'Бошқа', createdAt: DateTime(2026, 1, 1)),
        _p('new', title: 'Яна', createdAt: DateTime(2026, 9, 1)),
        _p('foreign', seller: 's2'),
        _p('off', status: WholesaleProduct.statusInactive),
      ];
      expect(sellerOthers(cur, pool).map((e) => e.id), ['new', 'old']);
    });

    test('сотувчи ID бўш — бўш рўйхат', () {
      expect(sellerOthers(_p('c', seller: ''), [_p('x', seller: '')]), isEmpty);
    });
  });
}
