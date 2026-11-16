// «Бозорлар» STAGE 11: сотувчи бўйича сават + қурилмада сақлаш, буюртма тугмаси қарори, йирик техника,
// хато кодлари, етказиш нархи сўрови (харидор/курьер).

import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_orders/data/business_order_session.dart';
import 'package:ava_gurlan/features/business_orders/data/business_orders_repository.dart';
import 'package:ava_gurlan/features/business_orders/domain/business_order.dart';
import 'package:ava_gurlan/features/business_orders/domain/business_order_errors.dart';
import 'package:ava_gurlan/features/business_orders/domain/delivery_quote.dart';
import 'package:ava_gurlan/features/business_orders/screens/business_cart_screen.dart';
import 'package:ava_gurlan/features/business_orders/screens/delivery_quote_screens.dart';
import 'package:ava_gurlan/features/business_orders/widgets/business_order_entry.dart';
import 'package:ava_gurlan/features/business_orders/widgets/delivery_quote_requests_section.dart';
import 'package:ava_gurlan/features/markets/domain/market_taxonomy.dart';
import 'package:ava_gurlan/features/my_shop/screens/main_shop_screen.dart';
import 'package:ava_gurlan/models/map_picker_result.dart';
import 'package:ava_gurlan/features/tv_market/domain/price_unit.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_business_orders_repository.dart';

const _seller = '998901111111';
const _seller2 = '998903333333';
const _me = '998902222222';

TvShopItem _it(
  String id, {
  String businessId = '',
  String owner = _seller,
  String market = '',
  String category = '',
  PriceUnit unit = PriceUnit.piece,
  int price = 5000,
}) =>
    TvShopItem(
      id: id,
      ownerPhone: owner,
      ownerName: 'Сотувчи',
      title: 'Маҳсулот $id',
      price: price,
      photoUrl: '',
      kind: 'product',
      districtId: 'd1',
      districtLabel: '',
      businessId: businessId,
      priceUnit: unit,
      status: 'active',
      market: market,
      category: category,
    );

final _tax = MarketTaxonomy.fromMap({
  'version': 3,
  'markets': {
    'appliances': {
      'moduleId': 'appliances',
      'categories': [
        {'id': 'fridges', 'orderable': true},
        {'id': 'kettles', 'orderable': true},
        {'id': 'misc'},
      ],
    },
  },
});

TvShop _shop({bool pickup = true, String status = 'active'}) => TvShop(
      ownerPhone: _seller,
      name: 'Дўконим',
      status: status,
      pickupLat: pickup ? 41.5 : null,
      pickupLng: pickup ? 60.3 : null,
      pickupAddress: pickup ? 'Бозор 1' : '',
    );

void main() {
  group('сават: сотувчи бўйича гуруҳ', () {
    test('объект, ўз дўкони ва бошқа сотувчи — алоҳида гуруҳ; калитлар', () {
      final store = BusinessCartStore();
      store.cartForItem(_it('a', businessId: 'b1')).add(_it('a', businessId: 'b1'), 2);
      store.cartForItem(_it('b')).add(_it('b'), 1);
      store.cartForItem(_it('c')).add(_it('c'), 3);
      store.cartForItem(_it('d', owner: _seller2)).add(_it('d', owner: _seller2), 1);
      expect(store.carts.map((c) => c.key), ['b1', 'shop:$_seller', 'shop:$_seller2']);
      expect(store.linesCount, 4);
      expect(store.existing('shop:$_seller')!.qtyOf('c'), 3);
      expect(store.existing('shop:$_seller')!.sellerKind, 'shop');
    });

    test('бегона сотувчи, объект маҳсулоти, йирик техника — ўз дўкони саватига тушмайди', () {
      final cart = BusinessCart(businessId: '', ownerPhone: _seller);
      expect(cart.add(_it('x', owner: _seller2), 1), isFalse);
      expect(cart.add(_it('x', businessId: 'b1'), 1), isFalse);
      expect(cart.add(_it('x', market: 'appliances', category: 'fridges'), 1), isFalse);
      expect(cart.add(_it('x', unit: PriceUnit.ton), 1), isFalse);
      expect(cart.add(_it('x', market: 'appliances', category: 'kettles'), 1), isTrue);
    });

    test('қурилмада сақланади ва фойдаланувчи бўйича ажратилади', () async {
      SharedPreferences.setMockInitialValues({'user_phone': _me});
      final a = BusinessCartStore(persistence: const BusinessCartPersistence());
      await a.ensureLoaded();
      a.cartForItem(_it('a', businessId: 'b1'), sellerName: 'Объект').add(_it('a', businessId: 'b1'), 2);
      a.cartForItem(_it('b')).add(_it('b'), 1);
      a.changed();
      await a.saved;

      final b = BusinessCartStore(persistence: const BusinessCartPersistence());
      await b.ensureLoaded();
      expect(b.carts.map((c) => c.key), ['b1', 'shop:$_seller']);
      expect(b.existing('b1')!.qtyOf('a'), 2);
      expect(b.existing('b1')!.businessName, 'Объект');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_phone', _seller2);
      final other = BusinessCartStore(persistence: const BusinessCartPersistence());
      await other.ensureLoaded();
      expect(other.carts, isEmpty, reason: 'бошқа аккаунт эскисининг саватини кўрмайди');
    });

    test('бузилган ёзув — бўш сават (хато йўқ)', () async {
      SharedPreferences.setMockInitialValues({'user_phone': _me, 'biz_cart_v1_$_me': '{not json'});
      final s = BusinessCartStore(persistence: const BusinessCartPersistence());
      await s.ensureLoaded();
      expect(s.carts, isEmpty);
    });

    test('бўшатилганда ёзув ўчирилади', () async {
      SharedPreferences.setMockInitialValues({'user_phone': _me});
      final s = BusinessCartStore(persistence: const BusinessCartPersistence());
      await s.ensureLoaded();
      s.cartForItem(_it('b')).add(_it('b'), 1);
      s.changed();
      await s.saved;
      s.clear('shop:$_seller');
      await s.saved;
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('biz_cart_v1_$_me'), isNull);
    });
  });

  group('буюртма тугмаси қарори (offerOrderPrecheck)', () {
    test('Аралаш ўз дўкони (бозорсиз) — сават', () {
      expect(offerOrderPrecheck(_it('a'), myUid: _me), OfferOrderMode.cart);
    });
    test('тонна / келишилади — йўқ; ўз маҳсулоти — йўқ', () {
      expect(offerOrderPrecheck(_it('a', unit: PriceUnit.ton), myUid: _me), OfferOrderMode.none);
      expect(offerOrderPrecheck(_it('a', unit: PriceUnit.negotiable), myUid: _me), OfferOrderMode.none);
      expect(offerOrderPrecheck(_it('a'), myUid: _seller), OfferOrderMode.none);
    });
    test('кг ва м² — сават', () {
      expect(offerOrderPrecheck(_it('a', unit: PriceUnit.kg), myUid: _me), OfferOrderMode.cart);
      expect(offerOrderPrecheck(_it('a', unit: PriceUnit.m2), myUid: _me), OfferOrderMode.cart);
    });
    test('бозор бўлими: orderable — сават, йўқ/номаълум/таксономиясиз — йўқ', () {
      expect(offerOrderPrecheck(_it('a', market: 'appliances', category: 'kettles'), myUid: _me, taxonomy: _tax),
          OfferOrderMode.cart);
      expect(offerOrderPrecheck(_it('a', market: 'appliances', category: 'misc'), myUid: _me, taxonomy: _tax),
          OfferOrderMode.none);
      expect(offerOrderPrecheck(_it('a', market: 'appliances', category: 'zzz'), myUid: _me, taxonomy: _tax),
          OfferOrderMode.none);
      expect(offerOrderPrecheck(_it('a', market: 'appliances', category: 'kettles'), myUid: _me),
          OfferOrderMode.none);
    });
    test('йирик техника — етказиш нархи сўрови', () {
      expect(offerOrderPrecheck(_it('a', market: 'appliances', category: 'fridges'), myUid: _me, taxonomy: _tax),
          OfferOrderMode.deliveryQuote);
    });
  });

  group('йирик техника тўплами (сервер кўзгуси)', () {
    for (final c in ['fridges', 'washers', 'stoves', 'air_conditioners']) {
      test('appliances/$c — йирик', () => expect(isLargeDeliveryItem(_it('a', market: 'appliances', category: c)), isTrue));
    }
    test('бошқа бўлим ва бошқа бозор — йирик эмас', () {
      expect(isLargeDeliveryItem(_it('a', market: 'appliances', category: 'kettles')), isFalse);
      expect(isLargeDeliveryItem(_it('a', market: 'electronics', category: 'fridges')), isFalse);
      expect(isLargeDeliveryItem(_it('a')), isFalse);
    });
  });

  group('хато кодлари → 3 тилли матн', () {
    const codes = [
      'SHOP_BLOCKED', 'ITEM_NOT_IN_SHOP', 'SHOP_NO_OWNER', 'SELLER_PICKUP_LOCATION_MISSING', 'ITEM_NOT_ORDERABLE',
      'QUOTE_ALREADY_ANSWERED', 'DELIVERY_QUOTE_REQUIRED', 'DELIVERY_QUOTE_NOT_NEEDED', 'QUOTE_NOT_FOUND',
      'QUOTE_EXPIRED', 'QUOTE_NOT_ANSWERED', 'QUOTE_ALREADY_USED', 'PRICE_INVALID', 'NOT_QUOTE_OWNER',
      'QUOTE_RESPONDER_NOT_ALLOWED', 'QUOTE_SELF_RESPOND', 'FLOOR_INVALID',
    ];
    final langs = {
      for (final l in ['uz_Cyrl', 'uz_Latn', 'ru'])
        l: jsonDecode(File('assets/lang/$l.json').readAsStringSync()) as Map<String, dynamic>,
    };
    for (final code in codes) {
      test(code, () {
        final key = bizOrderErrorKeyOrNull(code);
        expect(key, isNotNull);
        for (final e in langs.entries) {
          expect((e.value[key] as String?)?.trim(), isNotEmpty, reason: '${e.key}: $key');
        }
      });
    }
    test('FLOOR_INVALID — {max} параметри', () {
      expect(bizOrderErrorParams('FLOOR_INVALID', {'max': 60}), {'max': '60'});
    });
  });

  group('нарх ва қават киритиш', () {
    test('parseQuotePrice', () {
      expect(parseQuotePrice('45 000'), 45000);
      expect(parseQuotePrice('0'), isNull);
      expect(parseQuotePrice('abc'), isNull);
      expect(parseQuotePrice(''), isNull);
    });
    test('parseQuoteFloor', () {
      expect(parseQuoteFloor(''), isNull);
      expect(parseQuoteFloor('0'), 0);
      expect(parseQuoteFloor('60'), 60);
      expect(parseQuoteFloor('61'), -1);
    });
    test('effectiveStatus: муддати ўтган open/answered — expired', () {
      final now = DateTime(2026, 11, 16, 12);
      DeliveryQuote q(String s, DateTime exp) => DeliveryQuote(id: 'q', status: s, expiresAt: exp);
      expect(q('open', now.subtract(const Duration(minutes: 1))).effectiveStatus(now), 'expired');
      expect(q('answered', now.add(const Duration(minutes: 1))).effectiveStatus(now), 'answered');
      expect(q('used', now.subtract(const Duration(days: 1))).effectiveStatus(now), 'used');
    });
  });

  group('виджетлар', () {
    Future<void> pump(WidgetTester tester, Widget child, {bool settle = true}) async {
      tester.view.physicalSize = const Size(420 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(key: UniqueKey(), theme: AppTheme.light, home: Scaffold(body: child)));
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
      }
    }

    Widget entry(FakeBusinessOrdersRepository repo, TvShopItem it, {TvShop? shop, List<String>? quotes}) => ListView(
          children: [
            BusinessOrderEntry(
              item: it,
              myUid: _me,
              repository: repo,
              store: BusinessCartStore(),
              accessCache: BusinessOrdersAccessCache(),
              loadShop: (_) async => shop,
              loadTaxonomy: () async => _tax,
              openQuote: (ctx, item) async => quotes?.add(item.id),
            ),
          ],
        );

    testWidgets('ўз дўкони + топшириш жойи → «Саватга қўшиш», дарвоза маҳсулот бўйича', (tester) async {
      final repo = FakeBusinessOrdersRepository();
      await pump(tester, entry(repo, _it('a'), shop: _shop()));
      expect(find.byKey(const ValueKey('biz_order_cta')), findsOneWidget);
      expect(repo.calls, contains('access:item:a'));
    });

    testWidgets('топшириш жойи йўқ / дўкон блокланган / дарвоза ёпиқ → тугма йўқ', (tester) async {
      await pump(tester, entry(FakeBusinessOrdersRepository(), _it('a'), shop: _shop(pickup: false)));
      expect(find.byKey(const ValueKey('biz_order_cta')), findsNothing);
      await pump(tester, entry(FakeBusinessOrdersRepository(), _it('a'), shop: _shop(status: 'blocked')));
      expect(find.byKey(const ValueKey('biz_order_cta')), findsNothing);
      final closed = FakeBusinessOrdersRepository()
        ..accessResult = const BusinessOrdersAccess(allowed: false, stage: 'off', reason: 'MODULE_OFF');
      await pump(tester, entry(closed, _it('a'), shop: _shop()));
      expect(find.byKey(const ValueKey('biz_order_cta')), findsNothing);
    });

    testWidgets('йирик техника → «Етказиш нархини сўраш»', (tester) async {
      final quotes = <String>[];
      await pump(tester, entry(FakeBusinessOrdersRepository(), _it('f', market: 'appliances', category: 'fridges'),
          shop: _shop(), quotes: quotes));
      expect(find.byKey(const ValueKey('biz_order_cta')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('dq_cta')));
      await tester.pumpAndSettle();
      expect(quotes, ['f']);
    });

    testWidgets('«Сават» экрани: гуруҳлар ва гуруҳ бўйича расмийлаштириш', (tester) async {
      final store = BusinessCartStore();
      store.cartForItem(_it('a', businessId: 'b1'), sellerName: 'Объект').add(_it('a', businessId: 'b1'), 1);
      store.cartForItem(_it('b'), sellerName: 'Дўконим').add(_it('b'), 2);
      final opened = <String>[];
      await pump(tester, BusinessCartScreen(store: store, openCheckout: (ctx, c) async => opened.add(c.key)));
      expect(find.byKey(const ValueKey('biz_cart_group_b1')), findsOneWidget);
      expect(find.byKey(const ValueKey('biz_cart_group_shop:$_seller')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('biz_cart_checkout_shop:$_seller')));
      await tester.pumpAndSettle();
      expect(opened, ['shop:$_seller']);
    });

    testWidgets('сўров варағи: қават хатоси → юборилмайди; тўғри → requestDeliveryQuote', (tester) async {
      final repo = FakeBusinessOrdersRepository();
      await pump(
        tester,
        DeliveryQuoteRequestSheet(
          item: _it('f', market: 'appliances', category: 'fridges'),
          repository: repo,
          loadPlace: () async => (lat: 41.5, lng: 60.3, label: 'Уй'),
        ),
      );
      await tester.enterText(find.byKey(const ValueKey('dq_floor')), '75');
      await tester.tap(find.byKey(const ValueKey('dq_send')));
      await tester.pumpAndSettle();
      expect(repo.requestQuoteArgs, isEmpty);
      await tester.enterText(find.byKey(const ValueKey('dq_floor')), '4');
      await tester.tap(find.byKey(const ValueKey('dq_qty_plus')));
      await tester.tap(find.byKey(const ValueKey('dq_send')));
      await tester.pumpAndSettle();
      expect(repo.requestQuoteArgs.single, {'itemId': 'f', 'qty': 2, 'lat': 41.5, 'address': 'Уй', 'floor': 4, 'note': ''});
    });

    testWidgets('ҳолат: рухсат хатоси → «кутилмоқда» + янгилаш; нарх → «Тасдиқлаш» → буюртма', (tester) async {
      final repo = FakeBusinessOrdersRepository();
      final opened = <String>[];
      await pump(
        tester,
        DeliveryQuoteStatusScreen(
          quoteId: 'q1',
          repository: repo,
          now: () => DateTime(2026, 11, 16, 12),
          openOrder: (ctx, id) => opened.add(id),
        ),
        settle: false,
      );
      repo.quoteCtrl('q1').addError(Exception('permission-denied'));
      await tester.pump();
      expect(find.byKey(const ValueKey('dq_waiting')), findsOneWidget);
      expect(find.text('dq_status_refresh_hint'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('dq_refresh')));
      await tester.pump();
      repo.quoteCtrl('q1').add(DeliveryQuote(
        id: 'q1',
        status: 'answered',
        priceUzs: 60000,
        itemTitle: 'Музлатгич',
        expiresAt: DateTime(2026, 11, 16, 13),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dq_price')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dq_pay_wallet')));
      await tester.tap(find.byKey(const ValueKey('dq_accept')));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('acceptQuote:q1:wallet'));
      expect(opened, ['o1']);
    });

    testWidgets('курьер: сўровга нарх юбориш; нотўғри нарх — юборилмайди', (tester) async {
      final repo = FakeBusinessOrdersRepository()
        ..openQuotes = const OpenDeliveryQuotes(
          [OpenDeliveryQuote(id: 'q9', itemTitle: 'Кир ювиш машинаси', qty: 1, floor: 3, distanceMeters: 2500)],
          viewer: 'courier',
        );
      await pump(tester, ListView(children: [DeliveryQuoteRequestsSection(repository: repo)]));
      expect(find.byKey(const ValueKey('dq_card_q9')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dq_send_q9')));
      await tester.pumpAndSettle();
      expect(repo.respondArgs, isEmpty);
      await tester.enterText(find.byKey(const ValueKey('dq_price_q9')), '45000');
      await tester.tap(find.byKey(const ValueKey('dq_send_q9')));
      await tester.pumpAndSettle();
      expect(repo.respondArgs, [('q9', 45000)]);
    });

    testWidgets('«Менинг дўконим»: топшириш жойи йўқ → огоҳлантириш → харита → манзил → сақланади', (tester) async {
      final saved = <(double, double, String)>[];
      tester.view.physicalSize = const Size(420 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: MainShopScreen(
          phone: _seller,
          loadName: () async => 'Дўконим',
          retailView: (_) => const SizedBox(),
          chinaView: (_) => const SizedBox(),
          loadShop: () async => _shop(pickup: false),
          pickPickup: (_) async => const MapPickerResult(lat: 41.5, lng: 60.3, label: 'Бозор 1'),
          savePickup: (lat, lng, a) async => saved.add((lat, lng, a)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('shop_pickup_missing'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('shop_pickup_banner')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('shop_pickup_save')));
      await tester.pumpAndSettle();
      expect(saved, [(41.5, 60.3, 'Бозор 1')]);
      expect(find.text('shop_pickup_missing'), findsNothing);
    });

    testWidgets('курьер: рухсат йўқ (хато) — бўлим кўринмайди', (tester) async {
      final repo = FakeBusinessOrdersRepository()
        ..openQuotesError = const BusinessOrderException('permission-denied', 'COURIER_NOT_APPROVED');
      await pump(tester, ListView(children: [DeliveryQuoteRequestsSection(repository: repo)]));
      expect(find.byKey(const ValueKey('dq_requests_section')), findsNothing);
    });
  });
}
