import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/core/utils/wallet_ledger_labels.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:ava_gurlan/models/wallet_ledger_entry.dart';

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
      expect(offer('p', unit: 'pack', packQty: 1, packUnit: 'piece').unitPriceOfPack, 5000, reason: 'дона ҳам (эга 2026-11-20)');
    });
    test('smStatus йўқ — эски active белгиси бўйича (26-банд)', () {
      final a = SmOffer.fromMap('a', {'smGroupId': 'onion', 'price': 1, 'active': true, 'stock': 5});
      final b = SmOffer.fromMap('b', {'smGroupId': 'onion', 'price': 1, 'active': false});
      expect(a.status, SmStatus.active);
      expect(b.status, SmStatus.hidden);
      expect(SmOffer.fromMap('c', {'price': 1}).visible, isFalse, reason: 'smGroupId йўқ — супермаркетда эмас');
      // Сервер янги таклифни active:false ёзади — smStatus устун.
      final d = SmOffer.fromMap('d', {'smGroupId': 'onion', 'price': 1, 'active': false, 'smStatus': 'active', 'stock': 5});
      expect(d.available, isTrue);
    });
    test('қолдиқ (сервер кўзгуси): йўқ ёки бир қадамдан кам — сотувда эмас; чегара = бир қадам', () {
      expect(offer('s0', stock: null).available, isFalse);
      expect(offer('s1', stock: 0.4, step: 0.5).available, isFalse);
      expect(offer('s2', stock: 0.5, step: 0.5).available, isTrue);
      expect(offer('s3', stock: 3).maxQtyMilli, 3000);
      expect(offer('s0', stock: null).visible, isTrue, reason: 'кўринади, лекин «Ҳозир мавжуд эмас»');
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
    test('ушлаш ҲАР қаторда юқорига (сервер computeCharge): 1 001 + 1 001 → 101 + 101', () {
      final offers = {
        'a': offer('a', price: 1001, step: 1),
        'b': offer('b', price: 1001, step: 1),
      };
      final t = smCartTotals(SmCart.empty.add('a', 1000).add('b', 1000), offers, feePercent: 11, weighHoldPercent: 10);
      expect(t.weighedHold, 202, reason: 'жамидан ceil(2002×10%)=201 эмас');
      expect(t.feeEstimate, 220, reason: 'floor((2002×1100+5000)/10000)');
      expect(smCartTotals(SmCart.empty.add('a', 1000), offers, weighHoldPercent: 0).weighedHold, 0);
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
    test('getSupermarketAccess жавоби (сервер шакли: slots {today[], tomorrow[]})', () {
      final a = SmAccess.fromMap({
        'allowed': true,
        'reason': '',
        'districtId': 'gurlan',
        'feePercent': 11,
        'weighHoldPercent': 12,
        'tariffVersion': 'sm-v1',
        'slots': {
          'today': [
            {'id': 's1', 'names': n('Эрталаб'), 'startMin': 540, 'endMin': 660, 'date': '2026-11-20'},
            {'bad': 1},
          ],
          'tomorrow': [
            {'id': 's2', 'startMin': 900, 'endMin': 1020, 'date': '2026-11-21'},
          ],
        },
      });
      expect(a.allowed, isTrue);
      expect(a.feePercent, 11);
      expect(a.weighHoldPercent, 12);
      expect(a.districtId, 'gurlan');
      expect(a.slots.map((s) => '${s.id}:${s.day}'), ['s1:today', 's2:tomorrow']);
      expect(a.days, ['today', 'tomorrow']);
      expect(a.slots[1].label('ru'), '15:00–17:00');
      expect(a.slots[1].date, '2026-11-21');
      expect(SmAccess.fromMap(null).allowed, isFalse);
      final denied = SmAccess.fromMap({
        'allowed': false,
        'reason': 'DISTRICT_NOT_SERVED',
        'messages': {'uz_Cyrl': 'Бу ҳудудга…', 'uz_Latn': 'Bu hududga…', 'ru': 'В этот район…'},
        'feePercent': null,
        'slots': {'today': [], 'tomorrow': []},
      });
      expect(denied.allowed, isFalse);
      expect(smServerMessage(denied.messages, 'ru'), 'В этот район…');
      expect(denied.weighHoldPercent, 10, reason: 'сукут');
      expect(denied.feePercent, 0);
    });
    test('placeSupermarketOrder натижаси (сервер майдонлари)', () {
      final r = SmPlaceResult.fromMap({
        'ok': true, 'orderId': 'o1', 'itemsTotal': 22000, 'weighHold': 1000, 'deliveryFee': 2420, 'total': 25420, 'duplicate': true,
      });
      expect([r.orderId, r.goodsTotal, r.weighHold, r.fee, r.hold, r.duplicate], ['o1', 22000, 1000, 2420, 25420, true]);
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
      expect(smErrorKey(grpcCode: 'failed-precondition', details: {'code': 'INSUFFICIENT_BALANCE'}), 'sm_err_insufficient_funds');
      expect(smErrorKey(grpcCode: 'failed-precondition', details: {'code': 'NOT_TESTER'}), 'sm_err_not_allowed');
      expect(smErrorKey(grpcCode: 'failed-precondition', details: {'code': 'QTY_STEP_INVALID'}), 'sm_err_qty');
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
    test('5 босқич (сервер статуслари); рад/бекор/номаълум — null', () {
      expect(smOrderStep('new'), SmOrderStep.accepted);
      expect(smOrderStep('accepted'), SmOrderStep.preparing);
      expect(smOrderStep('ready'), SmOrderStep.ready);
      expect(smOrderStep('ready', fulfillmentStatus: 'courier_picked'), SmOrderStep.courier);
      expect(smOrderStep('in_delivery'), SmOrderStep.courier);
      expect(smOrderStep('courier'), SmOrderStep.courier);
      expect(smOrderStep('delivered'), SmOrderStep.delivered);
      expect(smOrderStep('in_delivery', fulfillmentStatus: 'completed'), SmOrderStep.delivered);
      expect(smOrderStep('rejected'), isNull);
      expect(smOrderStep('accepted', fulfillmentStatus: 'cancelled'), isNull);
      expect(smOrderStep('???'), isNull);
      expect(isSupermarketOrder('platform', 'supermarket'), isTrue);
      expect(isSupermarketOrder('platform', ''), isFalse);
      expect(isSupermarketOrder('supermarket', ''), isFalse);
    });
  });

  test('ҳамён тарихи: супермаркет тўлови ва қисман қайтим (3 тил калити)', () {
    String tr(String k, [Map<String, String>? p]) =>
        p == null ? '<$k>' : '<$k:${p.entries.map((e) => '${e.key}=${e.value}').join(',')}>';
    const debit = WalletLedgerEntry(
        id: '1', type: 'purchase_debit', amount: -25420, module: 'platform', meta: {'subtype': 'supermarket'});
    const refund = WalletLedgerEntry(
        id: '2', type: 'order_partial_refund', amount: 900, module: 'platform', meta: {'subtype': 'supermarket'});
    const plain = WalletLedgerEntry(id: '3', type: 'order_partial_refund', amount: 1);
    expect(walletLedgerTitle(debit, tr), '<wlt_l_purchase_mod:module=<wlt_m_supermarket>>');
    expect(walletLedgerTitle(refund, tr), '<wlt_l_partial_refund_mod:module=<wlt_m_supermarket>>');
    expect(walletLedgerTitle(plain, tr), '<wlt_l_partial_refund>');
    for (final l in ['uz_Cyrl', 'uz_Latn', 'ru']) {
      final m = jsonDecode(File('assets/lang/$l.json').readAsStringSync()) as Map<String, dynamic>;
      for (final k in ['wlt_m_supermarket', 'wlt_l_partial_refund', 'wlt_l_partial_refund_mod']) {
        expect((m[k] as String?)?.isNotEmpty, isTrue, reason: '$l $k');
      }
      expect(m['wlt_l_partial_refund_mod'], contains('{module}'));
    }
  });

  test('ҳамён изоҳи: сервер 3 тилли матни → noteKey → эски note', () {
    String tr(String k, [Map<String, String>? p]) => k == 'known_key' ? 'Таржима' : k;
    WalletLedgerEntry e(Map<String, dynamic> meta) => WalletLedgerEntry(id: 'x', type: 'order_partial_refund', amount: 1, meta: meta);
    final msgs = {'uz_Cyrl': 'Қайтим', 'uz_Latn': 'Qaytim', 'ru': 'Возврат'};
    expect(walletLedgerNote(e({'messages': msgs, 'noteKey': 'known_key', 'note': 'эски'}), tr, lang: 'ru'), 'Возврат');
    expect(walletLedgerNote(e({'noteMessages': msgs, 'note': 'эски'}), tr, lang: 'ru'), 'эски',
        reason: 'сервер 18b4ca04: фақат messages');
    for (final l in ['uz_Cyrl', 'uz_Latn', 'ru']) {
      final m = jsonDecode(File('assets/lang/$l.json').readAsStringSync()) as Map<String, dynamic>;
      for (final k in ['sm_refund_weigh', 'sm_refund_line_removed']) {
        expect((m[k] as String?)?.isNotEmpty, isTrue, reason: '$l $k');
      }
    }
    expect(walletLedgerNote(e({'messages': {'uz_Cyrl': 'Қайтим'}}), tr, lang: 'uz_Latn'), 'Қайтим', reason: 'тил йўқ — uz_Cyrl');
    expect(walletLedgerNote(e({'noteKey': 'known_key', 'note': 'эски'}), tr), 'Таржима');
    expect(walletLedgerNote(e({'noteKey': 'unknown_key', 'note': 'эски'}), tr), 'эски', reason: 'таржимаси йўқ калит');
    expect(walletLedgerNote(e({'note': 'эски'}), tr), 'эски');
    expect(walletLedgerSubtitle(e({'messages': msgs}), tr, lang: 'uz_Latn'), startsWith('Qaytim'));
  });

  test('мижоз бекори: супермаркетда фақат new', () {
    OrderModel o(String status) =>
        OrderModel(id: 'o', type: 'platform', subtype: 'supermarket', total: 1, status: status, items: const []);
    expect(o('new').canCustomerCancel, isTrue);
    for (final s in ['accepted', 'ready', 'in_delivery', 'delivered']) {
      expect(o(s).canCustomerCancel, isFalse, reason: s);
    }
    expect(o('new').isSupermarket, isTrue);
    expect(const OrderModel(id: 'o', type: 'platform', total: 1, status: 'new', items: []).isSupermarket, isFalse);
  });

  test('қадоқ бирлик нархи: дона ҳам (эга 2026-11-20)', () {
    expect(offer('p', unit: 'pack', price: 12000, packQty: 10, packUnit: 'piece').unitPriceOfPack, 1200);
    expect(offer('p', unit: 'pack', price: 12000, packQty: 0, packUnit: 'l').unitPriceOfPack, isNull);
    expect(offer('p', unit: 'pack', price: 12000, packQty: 1, packUnit: 'm').unitPriceOfPack, isNull);
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
