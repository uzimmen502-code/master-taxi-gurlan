import 'dart:convert';

import 'package:ava_gurlan/features/supermarket/data/supermarket_repository.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_access.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_cart.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_offer.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_order_progress.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_qty.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_search.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sm_fixture.dart';

void main() {
  group('taxonomy', () {
    test('9/90 шакли: тартиб, бирлик, қадам; номаълум бирлик ташланади', () {
      final t = smTaxonomyFixture;
      expect(t.version, 3);
      expect(t.categories.map((c) => c.id), ['vegetables', 'dairy']);
      expect(t.category('dairy')!.groups.map((g) => g.id), ['milk'], reason: "unit 'ton' ташланди");
      final onion = t.group('onion')!;
      expect(onion.stepMilli, 500);
      expect(onion.weighed, isTrue);
      expect(onion.categoryId, 'vegetables');
      expect(onion.name('uz_Latn'), 'Пиёз-lat');
      expect(onion.synonyms, ['piyoz', 'лук']);
    });
  });

  group('qty (бутун сон)', () {
    test('қадам текшируви: мусбат, қадамга каррали', () {
      expect(smIsValidQty(1500, 500), isTrue);
      expect(smIsValidQty(1200, 500), isFalse);
      expect(smIsValidQty(0, 500), isFalse);
      expect(smIsValidQty(-500, 500), isFalse);
      expect(smIsValidQty(500, 500), isTrue, reason: 'чегара: бир қадам');
    });
    test('snap: бир қадамдан кам эмас, энг яқин қадам', () {
      expect(smSnapQty(100, 500), 500);
      expect(smSnapQty(1200, 500), 1000);
      expect(smSnapQty(1300, 500), 1500);
    });
    test('сатр суммаси: 5 000 × 1,5 = 7 500; ярми юқорига', () {
      expect(smLineTotal(5000, 1500), 7500);
      expect(smLineTotal(3333, 500), 1667);
      expect(smLineTotal(0, 1000), 0);
    });
    test('кўрсатиш ва серверга сон', () {
      expect(smFormatQty(1500), '1,5');
      expect(smFormatQty(2000), '2');
      expect(smFormatQty(250), '0,25');
      expect(smFromMilli(2000), 2);
      expect(smFromMilli(2000), isA<int>());
      expect(smFromMilli(1500), 1.5);
    });
    test('фоиз: 11% ярми юқорига; ушлаш — юқорига', () {
      expect(smPercentOf(100000, 11), 11000);
      expect(smPercentOf(1005, 11), 111);
      expect(smPercentCeil(1001, 10), 101);
      expect(smPercentOf(0, 11), 0);
    });
  });

  group('offers', () {
    final all = smOffersFixture().where((o) => o.groupId == 'onion' && o.varietyId == 'red');
    test('нарх ўсиши бўйича; тугаганлари охирида; яширин йўқ', () {
      expect(smSortOffersAsc(all).map((o) => o.id), ['o_red_cheap', 'o_red_exp', 'o_red_oos']);
    });
    test('«… дан» — фақат мавжуд энг арзони (тугаган 3 000 ҳисобланмайди)', () {
      expect(smCheapestActivePrice(all), 5000);
      expect(smCheapestActivePrice([offer('x', status: 'out_of_stock')]), isNull);
    });
    test('пакет бирлик нархи: 12 000 / 0,9 л = 13 333 сўм/л', () {
      final m = smOffersFixture().firstWhere((o) => o.id == 'm1');
      expect(m.unitPriceOfPack, 13333);
      expect(offer('k', unit: 'kg').unitPriceOfPack, isNull);
      expect(offer('p', unit: 'pack', packQty: 1, packUnit: 'piece').unitPriceOfPack, isNull);
    });
    test('smStatus йўқ — эски active белгиси бўйича (26-банд)', () {
      final a = SmOffer.fromMap('a', {'smGroupId': 'onion', 'price': 1, 'active': true});
      final b = SmOffer.fromMap('b', {'smGroupId': 'onion', 'price': 1, 'active': false});
      expect(a.status, SmStatus.active);
      expect(b.status, SmStatus.hidden);
      expect(SmOffer.fromMap('c', {'price': 1}).visible, isFalse, reason: 'smGroupId йўқ — супермаркетда эмас');
    });
    test('навлар — такрорсиз', () {
      expect(smVarieties(smOffersFixture().where((o) => o.groupId == 'onion')).map((v) => v.id), ['white', 'red']);
    });
  });

  group('cart', () {
    test('бир хил таклиф — миқдор ошади; бошқа таклиф — алоҳида қатор', () {
      var c = SmCart.empty.add('a', 1000).add('b', 500).add('a', 500);
      expect(c.lines.map((l) => '${l.productId}:${l.qtyMilli}'), ['a:1500', 'b:500']);
      c = c.setQty('b', 0);
      expect(c.count, 1);
      expect(c.add('a', 0).qtyOf('a'), 1500, reason: '0 қўшилмайди');
    });
    test('таклифни алмаштириш: ўрни сақланади, мавжуд билан бирлашади', () {
      final c = SmCart.empty.add('a', 1000).add('b', 500).add('c', 1000);
      expect(c.replaceOffer('a', 'x', 2000).lines.map((l) => '${l.productId}:${l.qtyMilli}'), ['x:2000', 'b:500', 'c:1000']);
      expect(c.replaceOffer('a', 'c', 1000).lines.map((l) => '${l.productId}:${l.qtyMilli}'), ['c:2000', 'b:500']);
    });
    test('JSON: бузилган/такрор/манфий ёзув ташланади', () {
      final c = SmCart.fromJson(jsonDecode('[{"p":"a","q":1500},{"p":"a","q":1},{"p":"b","q":-1},{"x":1},"z"]'));
      expect(c.lines.map((l) => l.productId), ['a']);
      expect(SmCart.fromJson('bad').isEmpty, isTrue);
    });
    test('йиғинди: тугаган қатор ҳисобга кирмайди; +10% фақат тортиладиганга; 11% тахмин', () {
      final offers = {for (final o in smOffersFixture()) o.id: o};
      final cart = SmCart.empty.add('o_red_cheap', 2000).add('m1', 1000).add('o_red_oos', 1000);
      final t = smCartTotals(cart, offers, feePercent: 11);
      expect(t.goodsTotal, 10000 + 12000);
      expect(t.weighedTotal, 10000);
      expect(t.weighedHold, 1000);
      expect(t.feeEstimate, 2420);
      expect(t.holdEstimate, 22000 + 1000 + 2420);
      expect(t.unavailableIds, ['o_red_oos']);
    });
  });

  group('persistence', () {
    test('сават илова қайта очилганда ҳам (телефон бўйича ажратилган)', () async {
      SharedPreferences.setMockInitialValues({'user_phone': '+998 90 123-45-67'});
      final store = SmCartStore();
      await store.save(SmCart.empty.add('a', 1500).add('b', 1000));
      final again = await SmCartStore().load();
      expect(again.lines.map((l) => '${l.productId}:${l.qtyMilli}'), ['a:1500', 'b:1000']);
      expect(store.keyFor('+998 90 123-45-67'), 'sm_cart_v1_998901234567');
      SharedPreferences.setMockInitialValues({'user_phone': '+998 91 000 00 00'});
      expect((await SmCartStore().load()).isEmpty, isTrue, reason: 'бошқа аккаунт — бошқа сават');
    });
    test('бўш сават — ёзув ўчирилади', () async {
      SharedPreferences.setMockInitialValues({});
      await SmCartStore().save(SmCart.empty.add('a', 1000));
      await SmCartStore().save(SmCart.empty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith('sm_cart_v1_')), isEmpty);
    });
  });

  group('access / payload / errors', () {
    test('getSupermarketAccess жавоби', () {
      final a = SmAccess.fromMap({
        'allowed': true,
        'reason': '',
        'feePercent': 11,
        'slots': [
          {'id': 's1', 'names': n('Эрталаб'), 'startMin': 540, 'endMin': 660, 'day': 'today'},
          {'id': 's2', 'startMin': 900, 'endMin': 1020, 'day': 'tomorrow'},
          {'bad': 1},
        ],
      });
      expect(a.allowed, isTrue);
      expect(a.feePercent, 11);
      expect(a.slots.map((s) => s.id), ['s1', 's2']);
      expect(a.days, ['today', 'tomorrow']);
      expect(a.slots[1].label('ru'), '15:00–17:00');
      expect(SmAccess.fromMap(null).allowed, isFalse);
    });
    test('placeSupermarketOrder payload — шартнома шакли', () {
      final p = smOrderPayload(
        clientRequestId: 'req-1',
        cart: SmCart.empty.add('a', 1500).add('b', 2000),
        address: {'districtId': 'gurlan', 'phone': '+998901234567'},
        slotId: 's1',
        day: 'today',
      );
      expect(p, {
        'clientRequestId': 'req-1',
        'items': [
          {'productId': 'a', 'qty': 1.5},
          {'productId': 'b', 'qty': 2},
        ],
        'address': {'districtId': 'gurlan', 'phone': '+998901234567'},
        'slotId': 's1',
        'day': 'today',
      });
    });
    test('хато коди → дўстона калит', () {
      expect(smErrorKey(grpcCode: 'failed-precondition', details: {'code': 'INSUFFICIENT_FUNDS'}), 'sm_err_insufficient_funds');
      expect(smErrorKey(grpcCode: 'failed-precondition', details: {'errorCode': 'OUT_OF_STOCK'}), 'sm_err_out_of_stock');
      expect(smErrorKey(grpcCode: 'unavailable'), 'sm_err_network');
      expect(smErrorKey(grpcCode: 'permission-denied'), 'sm_err_not_allowed');
      expect(smErrorKey(grpcCode: 'internal', details: {'code': 'WHAT'}), 'sm_err_generic');
    });
    test('SupermarketAccessCache: хато — кўрсатилмайди; кеш', () async {
      SupermarketAccessCache.resetForTest();
      final api = FakeSupermarketApi();
      expect((await SupermarketAccessCache.get(api)).allowed, isTrue);
      api.access = const SmAccess(allowed: false);
      expect((await SupermarketAccessCache.get(api)).allowed, isTrue, reason: 'кеш (5 дақ)');
      expect((await SupermarketAccessCache.get(api, force: true)).allowed, isFalse);
      SupermarketAccessCache.resetForTest();
    });
  });

  group('order progress', () {
    test('5 босқич; номаълум — null', () {
      expect(smOrderStep('accepted'), SmOrderStep.accepted);
      expect(smOrderStep('preparing'), SmOrderStep.preparing);
      expect(smOrderStep('ready'), SmOrderStep.ready);
      expect(smOrderStep('in_delivery'), SmOrderStep.courier);
      expect(smOrderStep('delivered'), SmOrderStep.delivered);
      expect(smOrderStep('rejected'), isNull);
      expect(isSupermarketOrderType('supermarket'), isTrue);
      expect(isSupermarketOrderType('platform'), isFalse);
    });
  });

  group('search', () {
    final by = <String, List<SmOffer>>{};
    for (final o in smOffersFixture()) {
      if (o.visible) (by[o.groupId] ??= []).add(o);
    }
    test('кирилл / лотин / синоним; маҳсулотсиз гуруҳ чиқмайди', () {
      expect(smSearchGroups(smTaxonomyFixture, by, 'пиёз').map((g) => g.id), ['onion']);
      expect(smSearchGroups(smTaxonomyFixture, by, 'piyoz').map((g) => g.id), ['onion']);
      expect(smSearchGroups(smTaxonomyFixture, by, 'лук').map((g) => g.id), ['onion']);
      expect(smSearchGroups(smTaxonomyFixture, by, 'kartoshka').map((g) => g.id), ['potato']);
      expect(smSearchGroups(smTaxonomyFixture, by, 'Бўш'), isEmpty);
      expect(smSearchGroups(smTaxonomyFixture, by, '  '), isEmpty);
    });
  });
}
