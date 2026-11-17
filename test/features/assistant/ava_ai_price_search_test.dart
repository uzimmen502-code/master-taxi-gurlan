// AVA AI (эга 2026-11-17): Plus = 25 000 сўм / 24 соат ва «Нарх қидириш» 1-босқич (клиент — фақат кўрсатиш),
// маҳсулот формасидаги ихтиёрий «тахминий вазн» (unitWeightG).

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/core/utils/formatters.dart';
import 'package:ava_gurlan/features/assistant/models/assistant_status.dart';
import 'package:ava_gurlan/features/assistant/models/price_offer.dart';
import 'package:ava_gurlan/features/assistant/screens/price_search_screen.dart';
import 'package:ava_gurlan/features/assistant/services/assistant_service.dart';
import 'package:ava_gurlan/features/assistant/widgets/assistant_pro_sheet.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/screens/business_product_form_screen.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/features/tv_market/repositories/tv_shop_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeService implements AssistantService {
  _FakeService({this.result, this.error});
  PriceSearchResult? result;
  AssistantException? error;
  Map<String, Object?>? lastArgs;

  @override
  Future<PriceSearchResult> priceSearch({required String query, required String districtId, double? lat, double? lng}) async {
    lastArgs = {'query': query, 'districtId': districtId, 'lat': lat, 'lng': lng};
    if (error != null) throw error!;
    return result!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class _FakeShop implements TvShopRepository {
  TvShopItem? created;
  Map<String, dynamic>? patch;
  @override
  Future<void> ensureShop({required String ownerPhone, required String name}) async {}
  @override
  Future<String> createItem(TvShopItem item) async {
    created = item;
    return 'item1';
  }

  @override
  Future<void> updateItem(String itemId, Map<String, dynamic> p) async => patch = p;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

Map<String, dynamic> _offer(String id, {String kind = 'retail', int? fee, bool fromPrice = false, int? total, String? reason, bool sponsored = false, int? moq}) => {
      'id': id,
      'source': kind == 'wholesale' ? 'wholesale_products' : 'tv_shop_items',
      'kind': kind,
      'title': 'Олма $id',
      'photoUrl': '',
      'sellerName': 'Сотувчи',
      'ownerPhone': '998901111111',
      'sellerDistrictId': 'gurlan',
      'sellerRegionId': 'xorazm',
      'price': 10000,
      'priceUnit': '',
      'unit': kind == 'wholesale' ? 'кг' : null,
      'qty': moq ?? 1,
      'moq': moq,
      'goodsTotal': 10000 * (moq ?? 1),
      'delivery': {'fee': fee, 'fromPrice': fromPrice, 'reason': reason, 'tariffVersion': 1, 'estimate': true},
      'total': total,
      'totalFrom': fromPrice && total != null,
      'listedAt': DateTime(2026, 11, 16, 10).millisecondsSinceEpoch,
      'sponsored': sponsored,
    };

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(420 * 2, 1600 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: home));
  await tester.pumpAndSettle();
}

String _k(String k) => k;
String _km(String k, Map<String, String> p) => '$k:${p.values.join(',')}';

void main() {
  group('AssistantStatus — 24 соатлик пасс ва нарх қидириш ҳолати', () {
    test('d10 пакети (10 кун): passPackage, isPass; priceSearch майдонлари', () {
      final s = AssistantStatus.fromMap({
        'pro': true,
        'paidUntil': DateTime(2026, 11, 18, 9, 30).millisecondsSinceEpoch,
        'packages': [
          {'id': 'd10', 'days': 10, 'price': 25000, 'promo': false, 'oneTime': false},
        ],
        'priceSearch': {'enabled': true, 'dailyLimit': 30, 'usedToday': 2},
      });
      expect(s.passPackage!.id, 'd10');
      expect(s.passPackage!.days, 10);
      expect(s.passPackage!.isPass, isTrue);
      expect(s.lifetime, isFalse, reason: '10 кун — «чекловсиз» эмас');
      expect(s.priceSearchEnabled, isTrue);
      expect(s.priceSearchDailyLimit, 30);
      expect(s.priceSearchUsedToday, 2);
    });

    test('эски сервер жавоби (priceSearch йўқ) — ёпиқ; эски once пакети isPass эмас', () {
      final s = AssistantStatus.fromMap({
        'packages': [
          {'id': 'once', 'days': 3650, 'price': 25000, 'oneTime': true},
        ],
      });
      expect(s.priceSearchEnabled, isFalse);
      expect(s.passPackage!.isPass, isFalse);
    });

    test('buyPackage pricingAck сервер PRICING_ACK билан бир хил', () {
      expect(AssistantService.pricingAck, 'pass_v3');
    });
  });

  group('PriceOffer — жавобни ўқиш ва матн', () {
    test('fromMap: улгуржи MOQ, етказиш null + сабаб, реклама', () {
      final r = PriceSearchResult.fromMap({
        'partial': true,
        'offers': [
          _offer('a', kind: 'wholesale', fee: 59400, total: 159400, moq: 10),
          _offer('b', reason: 'tariff_not_active', sponsored: true),
        ],
      });
      expect(r.partial, isTrue);
      expect(r.offers[0].wholesale, isTrue);
      expect(r.offers[0].moq, 10);
      expect(r.offers[0].goodsTotal, 100000);
      expect(r.offers[1].delivery.fee, isNull);
      expect(r.offers[1].delivery.reason, PriceDeliveryReason.tariffNotActive);
      expect(r.offers[1].total, isNull);
      expect(r.offers[1].sponsored, isTrue);
    });

    test('етказиш матни: нарх йўқ → «ҳали йўқ»; вазнсиз → «≈ … дан»; аниқ → сўм', () {
      final none = PriceOffer.fromMap(_offer('x', reason: 'zone_not_found'));
      final from = PriceOffer.fromMap(_offer('y', fee: 34000, fromPrice: true, total: 44000));
      final exact = PriceOffer.fromMap(_offer('z', fee: 7500, total: 17500));
      expect(priceOfferDeliveryText(_k, _km, none), 'ps_delivery_none');
      expect(priceOfferDeliveryText(_k, _km, from), 'ps_amount_from:${formatPrice(34000)}');
      expect(priceOfferDeliveryText(_k, _km, exact), formatMoney(7500));
    });

    test('сервер хато кодлари → фойдаланувчи калитлари (ички код кўрсатилмайди)', () {
      expect(priceSearchErrorKey('price_search_limit'), 'ps_err_limit');
      expect(priceSearchErrorKey('location_required'), 'ps_err_location');
      expect(priceSearchErrorKey('price_search_off'), 'ps_err_off');
      expect(priceSearchErrorKey('PRICE_SEARCH_FAILED'), 'ps_err_generic');
    });
  });

  group('PriceSearchScreen', () {
    Widget screen(_FakeService s, {Future<void> Function()? onPlus}) => PriceSearchScreen(
          phone: '998902222222',
          service: s,
          onPlusRequired: onPlus,
          coords: () async => (lat: 41.86, lng: 60.40),
          area: () => (districtId: 'gurlan', regionId: 'xorazm'),
        );

    testWidgets('натижа: чакана/улгуржи белгиси, етказиш, жами, реклама белгиси; сервердаги тартиб сақланади', (tester) async {
      final s = _FakeService(result: PriceSearchResult.fromMap({
        'offers': [
          _offer('a', fee: 7500, total: 17500, sponsored: true),
          _offer('w', kind: 'wholesale', fee: 59400, total: 159400, moq: 10),
          _offer('n', reason: 'tariff_not_active'),
        ],
      }));
      await _pump(tester, screen(s));
      await tester.enterText(find.byKey(const ValueKey('ps_query')), 'олма');
      await tester.tap(find.byKey(const ValueKey('ps_go')));
      await tester.pumpAndSettle();
      expect(s.lastArgs, {'query': 'олма', 'districtId': 'gurlan', 'lat': 41.86, 'lng': 60.40});
      expect(find.text('ps_badge_retail'), findsNWidgets(2));
      expect(find.text('ps_badge_wholesale'), findsOneWidget);
      expect(find.text('ps_sponsored'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('ps_total_a'))).data, formatMoney(17500));
      expect(tester.widget<Text>(find.byKey(const ValueKey('ps_delivery_n'))).data, 'ps_delivery_none');
      expect(tester.widget<Text>(find.byKey(const ValueKey('ps_total_n'))).data, '—');
      final ys = ['a', 'w', 'n'].map((id) => tester.getTopLeft(find.byKey(ValueKey('ps_offer_$id'))).dy).toList();
      expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue, reason: 'клиент қайта тартибламайди');
      expect(find.byKey(const ValueKey('ps_write_a')), findsOneWidget, reason: 'бегона сотувчи — «Ёзиш»');
    });

    testWidgets('Plus йўқ → onPlusRequired; лимит → матн; бўш натижа', (tester) async {
      var plusAsked = 0;
      final s = _FakeService(error: const AssistantException('plus_required'));
      await _pump(tester, screen(s, onPlus: () async => plusAsked++));
      await tester.enterText(find.byKey(const ValueKey('ps_query')), 'нон');
      await tester.tap(find.byKey(const ValueKey('ps_go')));
      await tester.pumpAndSettle();
      expect(plusAsked, 1);
      s.error = const AssistantException('price_search_limit');
      await tester.tap(find.byKey(const ValueKey('ps_go')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('ps_error'))).data, 'ps_err_limit');
      s.error = null;
      s.result = const PriceSearchResult(offers: [], partial: false);
      await tester.tap(find.byKey(const ValueKey('ps_go')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ps_empty')), findsOneWidget);
    });

    testWidgets('1 ҳарф — серверга юборилмайди', (tester) async {
      final s = _FakeService(result: const PriceSearchResult(offers: [], partial: false));
      await _pump(tester, screen(s));
      await tester.enterText(find.byKey(const ValueKey('ps_query')), 'о');
      await tester.tap(find.byKey(const ValueKey('ps_go')));
      await tester.pumpAndSettle();
      expect(s.lastArgs, isNull);
      expect(tester.widget<Text>(find.byKey(const ValueKey('ps_error'))).data, 'ps_err_query');
    });
  });

  group('AssistantProSheet — 10 кунлик пасс', () {
    testWidgets('пакет «Plus — {days} кун», нарх; нарх қидириш изоҳи', (tester) async {
      final status = AssistantStatus.fromMap({
        'packages': [
          {'id': 'd10', 'days': 10, 'price': 25000},
        ],
        'balance': 1000,
      });
      await _pump(tester, Scaffold(
        body: AssistantProSheet(status: status, service: _FakeService(), onTopUp: () {}, priceSearchRequired: true),
      ));
      expect(find.text('assistant_pass_label'), findsOneWidget);
      expect(find.text('assistant_pass_sub'), findsOneWidget);
      expect(find.text(formatMoney(25000)), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('assistant_pro_note_title'))).data, 'ps_plus_title');
      expect(find.text('assistant_onetime_label'), findsNothing, reason: 'доимий пакет матни йўқ');
    });
  });

  group('Тахминий вазн (unitWeightG)', () {
    test('модел: round-trip; йўқ/нотўғри → null, toMap ёзмайди (эски шакл)', () {
      TvShopItem base({int? w}) => TvShopItem(
          id: 'a', ownerPhone: '1', ownerName: 'x', title: 't', price: 1, photoUrl: '', kind: 'product',
          districtId: 'gurlan', districtLabel: '', unitWeightG: w);
      expect(base().toMap().containsKey('unitWeightG'), isFalse);
      expect(base(w: 1500).toMap()['unitWeightG'], 1500);
      expect(TvShopItem.fromMap('a', {'unitWeightG': 1500}).unitWeightG, 1500);
      expect(TvShopItem.fromMap('a', {'unitWeightG': 0}).unitWeightG, isNull);
      expect(TvShopItem.fromMap('a', {'unitWeightG': '500'}).unitWeightG, isNull);
      expect(TvShopItem.fromMap('a', {'unitWeightG': 10000001}).unitWeightG, isNull);
      expect(TvShopItem.fromMap('a', {}).unitWeightG, isNull);
    });

    Business biz() => Business(
          id: 'b1', ownerId: '998901111111', name: 'Дўкон', category: BusinessCategory.retail,
          phone: '998901234567', lat: 41.3, lng: 69.2, districtId: 'gurlan');

    testWidgets('форма: «1,5» кг → 1500 г сақланади; бўш — майдон йўқ', (tester) async {
      final shop = _FakeShop();
      await _pump(tester, BusinessProductFormScreen(
        business: biz(),
        repository: shop,
        ownerPhone: '998901111111',
        showMarketChoice: false,
        pickPhotos: (room) async => ['a.jpg'],
        uploadPhotos: (phone, paths) async => ['https://cdn/a.jpg'],
      ));
      await tester.enterText(find.byKey(const ValueKey('bizprod_name')), 'Олма');
      await tester.enterText(find.byKey(const ValueKey('bizprod_price')), '12000');
      await tester.enterText(find.byKey(const ValueKey('bizprod_weight')), '1,5');
      await tester.tap(find.byKey(const ValueKey('bizprod_add_photos')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('bizprod_save')));
      await tester.tap(find.byKey(const ValueKey('bizprod_save')));
      await tester.pumpAndSettle();
      expect(shop.created!.unitWeightG, 1500);
      expect(shop.created!.toMap()['unitWeightG'], 1500);
    });

    testWidgets('форма: нотўғри вазн — хато, сақланмайди', (tester) async {
      final shop = _FakeShop();
      await _pump(tester, BusinessProductFormScreen(
        business: biz(),
        repository: shop,
        ownerPhone: '998901111111',
        showMarketChoice: false,
        pickPhotos: (room) async => ['a.jpg'],
        uploadPhotos: (phone, paths) async => ['https://cdn/a.jpg'],
      ));
      await tester.enterText(find.byKey(const ValueKey('bizprod_name')), 'Олма');
      await tester.enterText(find.byKey(const ValueKey('bizprod_price')), '12000');
      await tester.enterText(find.byKey(const ValueKey('bizprod_weight')), '0');
      await tester.tap(find.byKey(const ValueKey('bizprod_add_photos')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('bizprod_save')));
      await tester.tap(find.byKey(const ValueKey('bizprod_save')));
      await tester.pumpAndSettle();
      expect(shop.created, isNull);
      expect(find.text('bizprod_err_weight'), findsOneWidget);
    });

    testWidgets('таҳрир: вазн ўчирилса — FieldValue.delete()', (tester) async {
      final shop = _FakeShop();
      final existing = TvShopItem(
          id: 'i1', ownerPhone: '998901111111', ownerName: 'x', title: 'Олма', price: 12000, photoUrl: 'https://x/a.jpg',
          photoUrls: const ['https://x/a.jpg'], kind: 'product', districtId: 'gurlan', districtLabel: '', businessId: 'b1',
          unitWeightG: 2000);
      await _pump(tester, BusinessProductFormScreen(business: biz(), repository: shop, ownerPhone: '998901111111', existing: existing));
      expect(find.text('2'), findsOneWidget, reason: 'мавжуд вазн кг да кўрсатилади');
      await tester.enterText(find.byKey(const ValueKey('bizprod_weight')), '');
      await tester.ensureVisible(find.byKey(const ValueKey('bizprod_save')));
      await tester.tap(find.byKey(const ValueKey('bizprod_save')));
      await tester.pumpAndSettle();
      expect(shop.patch!['unitWeightG'], isA<FieldValue>());
    });
  });
}
