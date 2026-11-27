// Эга қарорлари 2026-11-27: бонус ҳамма супермаркет буюртмасида, совға матни + маълумот ўчирилиши, ўз туғилган
// куни эслатмалари (D-7..D-3, мақсадлар), Қурбон ҳайит → Мол бозори (баннер, чип, белги).
import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/geo/ring_query.dart';
import 'package:ava_gurlan/core/service_config_holder.dart';
import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/admin_web/screens/holiday_admin_screen.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_holiday_service.dart';
import 'package:ava_gurlan/features/markets/data/market_listings_source.dart';
import 'package:ava_gurlan/features/markets/data/market_search.dart';
import 'package:ava_gurlan/features/markets/domain/market_taxonomy.dart';
import 'package:ava_gurlan/features/markets/screens/market_screen.dart';
import 'package:ava_gurlan/features/markets/widgets/market_form_fields.dart';
import 'package:ava_gurlan/features/supermarket/data/supermarket_repository.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_access.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_holiday.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_inbox.dart';
import 'package:ava_gurlan/features/supermarket/screens/sm_checkout_screen.dart';
import 'package:ava_gurlan/features/supermarket/supermarket_controller.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/models/news_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sm_fixture.dart';

Finder _k(String k) => find.byKey(ValueKey(k));

Widget _app(Widget home, {double textScale = 1}) => MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    );

Map<String, String> _n(String s) => {'uz_Cyrl': s, 'uz_Latn': '$s-lat', 'ru': '$s-ru'};

SupermarketController _controller({FakeSupermarketApi? api}) {
  final c = SupermarketController(api: api ?? FakeSupermarketApi());
  c.setCatalogForTest(smTaxonomyFixture, smOffersFixture(), access: smAccessFixture);
  c.deliveryArea = const GeoArea(regionId: 'xorazm', districtId: 'gurlan', districtLabel: 'Гурлан');
  return c;
}

class _FakeAdminApi implements AdminHolidayApi {
  _FakeAdminApi(this.occasions);
  final List<HolidayOccasion> occasions;
  final saved = <HolidayOccasion>[];
  @override
  Future<List<HolidayOccasion>> loadOccasions() async => occasions;
  @override
  Future<List<HolidayBasket>> loadBaskets() async => const [];
  @override
  Future<Map<String, FamilyBonusProgram?>> loadFamilyPrograms() async => const {};
  @override
  Future<void> saveOccasion(HolidayOccasion o, {String reason = ''}) async => saved.add(o);
  @override
  Future<void> saveBasket(HolidayBasket b, {String reason = ''}) async {}
  @override
  Future<void> saveFamilyProgram(String programId, FamilyBonusProgram p, {String reason = ''}) async {}
}

const _qurbonRaw = {
  'id': 'qurbon_hayit',
  'names': {'uz_Cyrl': 'Қурбон ҳайит', 'uz_Latn': 'Qurbon hayit', 'ru': 'Курбан-хайит'},
  'kind': 'holiday',
  'dateRule': {'type': 'list', 'dates': ['2027-05-16']},
  'target': {'type': 'market', 'market': 'livestock', 'categories': ['sheep_goat', 'cattle']},
};

final _today = DateTime(2027, 5, 5);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ─── 1) Бонус ──────────────────────────────────────────────────────────────
  group('бонус ҳамма супермаркет буюртмасида', () {
    test('оддий payload ҳам useIncentive: true (сервер ҳал қилади)', () {
      final c = _controller()..addToCart('p1', 1000);
      final p = smOrderPayload(clientRequestId: 'k', cart: c.cart, address: const {}, slotId: 's1', day: 'today');
      expect(p['useIncentive'], isTrue);
      expect(p['origin'], 'catalog');
    });

    test('бонус баҳоси: қолдиқ, товардан ошмайди; манфий/бўш — 0', () {
      expect(smBonusEstimate(incentive: 5000, goodsTotal: 6000), 5000);
      expect(smBonusEstimate(incentive: 9000, goodsTotal: 6000), 6000);
      expect(smBonusEstimate(incentive: 0, goodsTotal: 6000), 0);
      expect(smBonusEstimate(incentive: -5, goodsTotal: 6000), 0);
      expect(smBonusEstimate(incentive: 5000, goodsTotal: 0), 0);
    });

    test('сервер етишмовчилиги: required − balance; бўлмаса 0', () {
      expect(smServerShortfall({'required': 9000, 'balance': 4000}), 5000);
      expect(smServerShortfall({'required': 4000, 'balance': 9000}), 0);
      expect(smServerShortfall(const {}), 0);
      expect(smServerShortfall({'required': '9000', 'balance': 1}), 0);
    });

    testWidgets('ҳамён + бонус етади — тугма ёқиқ, бонус қатори; бонус йўқ — тугма ўчиқ, тўлдириш', (t) async {
      final api = FakeSupermarketApi();
      final c = _controller(api: api)..addToCart('p1', 1000);
      await t.binding.setSurfaceSize(const Size(420, 2000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(_app(SmCheckoutScreen(
        controller: c,
        balance: Stream.value(5000),
        incentive: Stream.value(10000),
        pickArea: (_) async => null,
      )));
      await t.pumpAndSettle();
      await t.enterText(_k('sm_addr_phone'), '+998 90 123 45 67');
      await t.pump();
      expect(_k('sm_incentive_estimate'), findsOneWidget);
      expect(_k('sm_after_bonus'), findsOneWidget);
      expect(_k('sm_wallet_short'), findsNothing);
      await t.ensureVisible(_k('sm_confirm'));
      expect(t.widget<FilledButton>(_k('sm_confirm')).onPressed, isNotNull);
      await t.tap(_k('sm_confirm'));
      await t.pumpAndSettle();
      expect(api.payloads.single['useIncentive'], isTrue);
      expect(api.payloads.single.containsKey('day'), isFalse);

      await t.pumpWidget(const SizedBox());
      final c2 = _controller()..addToCart('p1', 1000);
      await t.pumpWidget(_app(SmCheckoutScreen(
        controller: c2,
        balance: Stream.value(1000),
        incentive: Stream.value(0),
        pickArea: (_) async => null,
      )));
      await t.pumpAndSettle();
      expect(_k('sm_incentive_estimate'), findsNothing);
      expect(_k('sm_wallet_short'), findsOneWidget);
      expect(_k('sm_topup'), findsOneWidget);
    });

    testWidgets('сервер «маблағ етмайди» (бонус кам қўлланди) — етишмаган сумма ва тўлдириш тугмаси', (t) async {
      final api = FakeSupermarketApi();
      api.placeResults.add(const SmCallError('sm_err_insufficient_funds', 'INSUFFICIENT_FUNDS',
          details: {'required': 7000, 'balance': 1000}));
      final c = _controller(api: api)..addToCart('p1', 1000);
      await t.binding.setSurfaceSize(const Size(420, 2000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(_app(SmCheckoutScreen(
        controller: c,
        balance: Stream.value(5000),
        incentive: Stream.value(10000),
        pickArea: (_) async => null,
      )));
      await t.pumpAndSettle();
      await t.enterText(_k('sm_addr_phone'), '+998 90 123 45 67');
      await t.pump();
      await t.ensureVisible(_k('sm_confirm'));
      await t.tap(_k('sm_confirm'));
      await t.pumpAndSettle();
      expect(find.text('sm_err_insufficient_funds'), findsOneWidget);
      expect(_k('sm_topup'), findsOneWidget);
    });
  });

  // ─── 2) Совға матни ────────────────────────────────────────────────────────
  testWidgets('совға: маълумот ўчирилиши изоҳи кўринади', (t) async {
    final dated = SmAccess(
      allowed: true,
      feePercent: 11,
      slots: smAccessFixture.slots,
      dateSlots: const {'2027-05-06': [SmSlot(id: 's9', names: {}, startMin: 600, endMin: 720, day: '')]},
    );
    final c = SupermarketController(api: FakeSupermarketApi(access: dated));
    c.setCatalogForTest(smTaxonomyFixture, smOffersFixture(), access: dated);
    c.deliveryArea = const GeoArea(regionId: 'xorazm', districtId: 'gurlan', districtLabel: 'Гурлан');
    c.addToCart('p1', 1000);
    await t.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(_app(
      SmCheckoutScreen(
        controller: c,
        balance: Stream.value(10000000),
        incentive: Stream.value(0),
        today: _today,
        holiday: const SmHolidayCheckout(asGift: true),
      ),
      textScale: 1.5,
    ));
    await t.pumpAndSettle();
    expect(_k('sm_gift_privacy'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  // ─── 4) Ўз туғилган куни эслатмалари ───────────────────────────────────────
  group('ўз туғилган куни эслатмалари', () {
    Map<String, Object> tx(String s) => {
          for (final l in const ['uz_Cyrl', 'uz_Latn', 'ru']) l: {'title': '$s $l', 'body': '$s матн $l'},
        };
    Map<String, ({String title, String body})> rtx(String s) => {
          for (final l in const ['uz_Cyrl', 'uz_Latn', 'ru']) l: (title: '$s $l', body: '$s матн $l'),
        };

    test('модел: сервер шакли (texts{title,body}, target объект) ↔ админ танлови; бузилгани ташланади', () {
      final o = HolidayOccasion.fromMap({
        'id': 'birthday',
        'names': _n('Туғилган кун'),
        'kind': 'birthday',
        'selfReminders': [
          {'daysBefore': 7, 'texts': tx('Ресторан'), 'target': {'type': 'restaurants_preorder'}},
          {'daysBefore': 3, 'texts': tx('Меҳмон'), 'target': {'type': 'holiday_basket', 'occasionId': 'birthday', 'mode': 'guests'}},
          {'daysBefore': 5, 'texts': tx('Саватча'), 'target': {'type': 'holiday_basket', 'occasionId': 'birthday'}},
          {'daysBefore': 'x', 'target': {'type': 'supermarket'}},
          'junk',
        ],
      })!;
      expect(o.selfReminders!.map((r) => '${r.daysBefore}:${r.target}'),
          ['7:restaurants_preorder', '3:birthday_basket_guests', '5:birthday_basket']);
      expect(o.selfReminders!.first.texts['ru']?.title, 'Ресторан ru');
      final m = o.toAdminMap();
      expect((m['selfReminders'] as List)[1], {
        'daysBefore': 3,
        'texts': tx('Меҳмон'),
        'target': {'type': 'holiday_basket', 'occasionId': 'birthday', 'mode': 'guests'},
      });
      expect((m['selfReminders'] as List).first['target'], {'type': 'restaurants_preorder'});
      expect(m.containsKey('target'), isFalse, reason: 'туғилган кунда мақсад йўқ');
      // Майдон йўқ — сервер сукути (юборилмайди); бўш рўйхат — ўчиқ (юборилади).
      expect(HolidayOccasion.fromMap({'id': 'birthday', 'names': {}, 'kind': 'birthday'})!.selfReminders, isNull);
      expect(const HolidayOccasion(id: 'birthday', names: {}, kind: 'birthday').toAdminMap().containsKey('selfReminders'), isFalse);
      expect(const HolidayOccasion(id: 'birthday', names: {}, kind: 'birthday', selfReminders: []).toAdminMap()['selfReminders'],
          isEmpty);
    });

    test('текширув: 1..14 кун, такрорсиз, ≤10, мақсад рўйхатдан, 3 тилда сарлавҳа ≤80 + матн ≤300', () {
      List<HolidaySelfReminder> list(List<(int, String)> v) =>
          [for (final e in v) HolidaySelfReminder(daysBefore: e.$1, texts: rtx('Матн'), target: e.$2)];
      expect(
          holidaySelfReminderProblems(list([
            (7, kSelfTargetPreorder),
            (6, kSelfTargetBasket),
            (5, kSelfTargetBasket),
            (4, kSelfTargetGuests),
            (3, kSelfTargetGuests),
          ])),
          isEmpty);
      expect(holidaySelfReminderProblems(list([(1, kSelfTargetBasket), (14, kSelfTargetBasket)])), isEmpty, reason: 'чегаралар');
      expect(holidaySelfReminderProblems(list([(0, kSelfTargetBasket)])), hasLength(1));
      expect(holidaySelfReminderProblems(list([(15, kSelfTargetBasket)])), hasLength(1));
      expect(holidaySelfReminderProblems(list([(5, kSelfTargetBasket), (5, kSelfTargetGuests)])), hasLength(1));
      expect(holidaySelfReminderProblems(list([(5, '')])), hasLength(1));
      expect(holidaySelfReminderProblems(list([for (var d = 1; d <= 11; d++) (d, kSelfTargetBasket)])), hasLength(1),
          reason: '10 тадан кўп');
      final long = HolidaySelfReminder(
        daysBefore: 5,
        target: kSelfTargetBasket,
        texts: {...rtx('a'), 'ru': (title: 'x' * 81, body: 'y' * 301)},
      );
      expect(holidaySelfReminderProblems([long]), hasLength(2));
      expect(
          holidaySelfReminderProblems(
              [const HolidaySelfReminder(daysBefore: 5, texts: {'uz_Cyrl': (title: 'a', body: 'b')}, target: kSelfTargetBasket)]),
          hasLength(4),
          reason: 'лотин ва рус йўқ');
    });

    test('push: holiday_self_birthday / holiday_reminder + targetType сатрлари → йўл', () {
      HolidayRoute r(Map<String, String> d) => holidayRouteOf(holidayPushTarget(d)!);
      const self = 'holiday_self_birthday';
      expect(r({'type': self, 'targetType': 'holiday_basket', 'occasionId': 'birthday', 'daysBefore': '6'}), HolidayRoute.basket);
      expect(r({'type': self, 'targetType': 'holiday_basket', 'occasionId': 'birthday', 'mode': 'guests'}), HolidayRoute.basketGuests);
      expect(r({'type': self, 'targetType': 'restaurants_preorder', 'daysBefore': '7'}), HolidayRoute.restaurantsPreorder);
      expect(r({'type': self}), HolidayRoute.basket, reason: 'мақсадсиз ўз туғилган куни — саватча');
      expect(r({'type': 'holiday_reminder', 'occasionId': 'navruz', 'targetType': 'supermarket'}), HolidayRoute.supermarket);
      expect(r({'type': 'holiday_reminder', 'occasionId': 'navruz', 'targetType': 'holiday_basket', 'mode': 'gift'}),
          HolidayRoute.basketGift);
      expect(r({'type': 'holiday_reminder', 'occasionId': 'navruz', 'targetType': 'evil'}), HolidayRoute.occasionList);
      expect(r({'type': 'holiday_reminder', 'occasionId': 'navruz'}), HolidayRoute.occasionList);
      expect(r({'type': 'holiday_birthday_reminder', 'personId': 'p1', 'targetType': 'supermarket'}), HolidayRoute.relativeBirthday);
      expect(r({'type': 'holiday_relatives_bonus'}), HolidayRoute.bonus);
      expect(holidayPushTarget({'type': 'other', 'targetType': 'supermarket'}), isNull);

      final q = holidayPushTarget({
        'type': 'holiday_reminder',
        'occasionId': 'qurbon_hayit',
        'targetType': 'market',
        'market': 'livestock',
        'categories': 'sheep_goat,cattle',
      })!;
      expect(holidayRouteOf(q), HolidayRoute.market);
      expect([q.target!.market, ...q.target!.categories], ['livestock', 'sheep_goat', 'cattle']);
      expect(holidayRouteOf(holidayPushTarget({'type': 'holiday_reminder', 'targetType': 'market'})!), HolidayRoute.occasionList,
          reason: 'бозор id йўқ — нотўғри мақсад');
      // Ўз туғилган кунида байрам id йўқ бўлса — birthday.
      expect(holidayRouteOccasion(holidayPushTarget({'type': self, 'targetType': 'holiday_basket'})!), 'birthday');
      expect(holidayRouteOccasion(holidayPushTarget({'type': 'holiday_reminder', 'occasionId': 'navruz'})!), 'navruz');
    });

    test('«Хабарлар» ёзуви (extraNews.target объекти) push билан бир хил йўл', () {
      final n = NewsItem(
        id: 'n1',
        title: 't',
        body: 'b',
        createdAt: DateTime(2027),
        source: 'holiday_self_birthday',
        occasionId: 'birthday',
        target: const {'type': 'restaurants_preorder'},
      );
      expect(holidayRouteOf(holidayInboxTarget(n)!), HolidayRoute.restaurantsPreorder);
      final g = NewsItem(
        id: 'n2',
        title: 't',
        body: 'b',
        createdAt: DateTime(2027),
        source: 'holiday_self_birthday',
        target: const {'type': 'holiday_basket', 'occasionId': 'birthday', 'mode': 'guests'},
      );
      expect(holidayRouteOf(holidayInboxTarget(g)!), HolidayRoute.basketGuests);
    });

    testWidgets('админ: туғилган кунда эслатмалар муҳаррири, D-7…D-3 тавсия → сақланади', (t) async {
      final api = _FakeAdminApi([
        HolidayOccasion(
          id: 'birthday',
          names: _n('Туғилган кун'),
          kind: 'birthday',
          stage: 'internal',
          selfReminders: [
            for (final d in [7, 6, 5, 4, 3])
              HolidaySelfReminder(
                daysBefore: d,
                texts: {for (final l in const ['uz_Cyrl', 'uz_Latn', 'ru']) l: (title: 'Сарлавҳа $d', body: 'Матн $d')},
                target: d == 7 ? kSelfTargetPreorder : (d >= 5 ? kSelfTargetBasket : kSelfTargetGuests),
              ),
          ],
        ),
      ]);
      await t.binding.setSurfaceSize(const Size(1000, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(_app(Scaffold(
        body: HolidayAdminScreen(api: api, loadTaxonomy: () async => smTaxonomyFixture, loadOffers: (_) async => const []),
      )));
      await t.pumpAndSettle();
      await t.tap(_k('hb_admin_occasion_birthday'));
      await t.pumpAndSettle();
      expect(_k('hb_admin_self'), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        expect(_k('hb_admin_self_days_$i'), findsOneWidget);
      }
      expect(_k('hb_admin_target_type'), findsNothing, reason: 'туғилган кунда бозор мақсади йўқ');
      // Биттасини ўчириб, 14 дан катта кун киритилса — хато.
      await t.enterText(_k('hb_admin_self_days_4'), '15');
      await t.ensureVisible(_k('hb_admin_save'));
      await t.tap(_k('hb_admin_save'));
      await t.pumpAndSettle();
      expect(api.saved, isEmpty);
      await t.enterText(_k('hb_admin_self_days_4'), '3');
      await t.tap(_k('hb_admin_self_del_0'));
      await t.pumpAndSettle();
      await t.ensureVisible(_k('hb_admin_save'));
      await t.tap(_k('hb_admin_save'));
      await t.pumpAndSettle();
      expect(api.saved.single.selfReminders!.map((r) => r.daysBefore), [6, 5, 4, 3]);
      expect(api.saved.single.toAdminMap()['selfReminders'], hasLength(4));
    });

    testWidgets('админ: бўш рўйхатга D-7…D-3 тавсия 5 қатор қўшади (матн тўлдирилмаса сақланмайди)', (t) async {
      final api = _FakeAdminApi([HolidayOccasion(id: 'birthday', names: _n('Туғилган кун'), kind: 'birthday', stage: 'off')]);
      await t.binding.setSurfaceSize(const Size(1000, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(_app(Scaffold(
        body: HolidayAdminScreen(api: api, loadTaxonomy: () async => smTaxonomyFixture, loadOffers: (_) async => const []),
      )));
      await t.pumpAndSettle();
      await t.tap(_k('hb_admin_occasion_birthday'));
      await t.pumpAndSettle();
      await t.tap(_k('hb_admin_self_defaults'));
      await t.pumpAndSettle();
      final days = [for (var i = 0; i < 5; i++) t.widget<TextField>(_k('hb_admin_self_days_$i')).controller!.text];
      expect(days, ['7', '6', '5', '4', '3']);
      await t.ensureVisible(_k('hb_admin_save'));
      await t.tap(_k('hb_admin_save'));
      await t.pumpAndSettle();
      expect(api.saved, isEmpty, reason: 'матнлар бўш');
    });

    testWidgets('админ: эслатмаларга тегилмаса — сукут (майдон юборилмайди)', (t) async {
      final api = _FakeAdminApi([HolidayOccasion(id: 'birthday', names: _n('Туғилган кун'), kind: 'birthday', stage: 'off')]);
      await t.binding.setSurfaceSize(const Size(1000, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(_app(Scaffold(
        body: HolidayAdminScreen(api: api, loadTaxonomy: () async => smTaxonomyFixture, loadOffers: (_) async => const []),
      )));
      await t.pumpAndSettle();
      await t.tap(_k('hb_admin_occasion_birthday'));
      await t.pumpAndSettle();
      expect(_k('hb_admin_self_default_note'), findsOneWidget);
      await t.ensureVisible(_k('hb_admin_save'));
      await t.tap(_k('hb_admin_save'));
      await t.pumpAndSettle();
      expect(api.saved.single.selfReminders, isNull);
      expect(api.saved.single.toAdminMap().containsKey('selfReminders'), isFalse);
    });

    testWidgets('админ: байрамда мақсад — «Ресторанда олдиндан буюртма» → target объекти', (t) async {
      final api = _FakeAdminApi([
        const HolidayOccasion(id: 'navruz', names: {'uz_Cyrl': 'Наврўз', 'uz_Latn': 'Navröz', 'ru': 'Навруз'}, ruleType: 'fixed', md: '03-21', stage: 'off'),
      ]);
      await t.binding.setSurfaceSize(const Size(1000, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(_app(Scaffold(
        body: HolidayAdminScreen(api: api, loadTaxonomy: () async => smTaxonomyFixture, loadOffers: (_) async => const []),
      )));
      await t.pumpAndSettle();
      await t.tap(_k('hb_admin_occasion_navruz'));
      await t.pumpAndSettle();
      expect(_k('hb_admin_self'), findsNothing);
      await t.tap(_k('hb_admin_target_type'));
      await t.pumpAndSettle();
      await t.tap(find.text('Ресторанда олдиндан буюртма').last);
      await t.pumpAndSettle();
      await t.ensureVisible(_k('hb_admin_save'));
      await t.tap(_k('hb_admin_save'));
      await t.pumpAndSettle();
      expect(api.saved.single.toAdminMap()['target'], {'type': 'restaurants_preorder'});
    });
  });

  // ─── 5) Қурбон ҳайит ───────────────────────────────────────────────────────
  group('Қурбон ҳайит → Мол бозори', () {
    final qurbon = HolidayOccasion.fromMap(_qurbonRaw)!;

    test('мақсад: бозор + бўлимлар; бузилгани — саватча; admin харитада target', () {
      expect(qurbon.target!.isMarket, isTrue);
      expect(qurbon.target!.market, 'livestock');
      expect(qurbon.target!.initialCategory, 'sheep_goat');
      expect(qurbon.toAdminMap()['target'], {'type': 'market', 'market': 'livestock', 'categories': ['sheep_goat', 'cattle']});
      expect(HolidayTarget.fromMap({'type': 'market', 'market': 'Bad Id'}), isNull);
      expect(HolidayTarget.fromMap({'type': 'basket'}), isNull);
      expect(HolidayTarget.fromMap(null), isNull);
      expect(HolidayTarget.fromMap({'type': 'supermarket'})!.toMap(), {'type': 'supermarket'});
      expect(HolidayOccasion.fromMap({'id': 'navruz', 'names': {}, 'target': null})!.target, isNull, reason: 'каталогда null');
      expect(const HolidayOccasion(id: 'navruz', names: {}, ruleType: 'fixed', md: '03-21').toAdminMap()['target'], isNull,
          reason: 'саватча — null (тозалаш учун ҳам)');
    });

    test('давр: байрамгача 0..15 кун; 16 — йўқ; ўтган — йўқ; бошқа бозор — йўқ', () {
      expect(qurbonMarketActive([qurbon], 'livestock', DateTime(2027, 5, 1)), isTrue, reason: '15 кун');
      expect(qurbonMarketActive([qurbon], 'livestock', DateTime(2027, 4, 30)), isFalse, reason: '16 кун');
      expect(qurbonMarketActive([qurbon], 'livestock', DateTime(2027, 5, 16)), isTrue, reason: 'байрам куни');
      expect(qurbonMarketActive([qurbon], 'livestock', DateTime(2027, 5, 17)), isFalse);
      expect(qurbonMarketActive([qurbon], 'meat', DateTime(2027, 5, 10)), isFalse);
      expect(qurbonMarketActive(const [], 'livestock', DateTime(2027, 5, 10)), isFalse);
    });

    final livestock = MarketTaxonomy.fromMap({
      'version': 9,
      'markets': {
        'livestock': {
          'moduleId': 'livestock_market',
          'order': 1,
          'names': {'uz_Cyrl': 'Мол бозори'},
          'categories': [
            {'id': 'sheep_goat', 'names': {'uz_Cyrl': 'Қўй-эчки'}},
            {'id': 'cattle', 'names': {'uz_Cyrl': 'Қорамол'}},
          ],
          'fields': [
            {'key': 'breed', 'type': 'text', 'names': {'uz_Cyrl': 'Зоти'}},
            {'key': 'qurbon_ready', 'type': 'bool', 'names': {'uz_Cyrl': 'Қурбонликка мос'}},
          ],
        },
        'meat': {
          'moduleId': 'meat_market',
          'order': 2,
          'names': {'uz_Cyrl': 'Гўшт'},
          'categories': [{'id': 'beef', 'names': {'uz_Cyrl': 'Мол гўшти'}}],
        },
      },
    });

    TvShopItem item(String id, {bool qurbon = false, String category = 'sheep_goat'}) => TvShopItem(
          id: id,
          ownerPhone: '998901111111',
          ownerName: 'Сотувчи',
          title: 'Қўчқор $id',
          price: 3000000,
          photoUrl: '',
          kind: 'product',
          districtId: 'gurlan',
          districtLabel: 'Гурлан',
          market: 'livestock',
          category: category,
          attrs: qurbon ? const {'qurbon_ready': true} : const {},
        );

    Future<void> pumpMarket(WidgetTester t, {required bool period, double width = 420, double scale = 1}) async {
      GeoContext.resetForTest();
      ServiceConfigHolder.resetForTest();
      await t.binding.setSurfaceSize(Size(width, 1200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(_app(
        MarketScreen(
          marketId: 'livestock',
          source: _FakeSource([item('a', qurbon: true), item('b')]),
          loadTaxonomy: () async => livestock,
          initialCategory: 'sheep_goat',
          qurbonCheck: (_) async => period,
          cachedItems: () => const [],
        ),
        textScale: scale,
      ));
      await t.pumpAndSettle();
    }

    testWidgets('давр: баннер + чип; чип — фақат белгиланганлар; карточкада «Қурбонликка»', (t) async {
      await pumpMarket(t, period: true);
      expect(_k('market_qurbon_banner'), findsOneWidget);
      expect(_k('market_qurbon_chip'), findsOneWidget);
      expect(_k('market_card_qurbon_a'), findsOneWidget);
      expect(_k('market_card_qurbon_b'), findsNothing);
      expect(_k('market_card_b'), findsOneWidget);
      await t.ensureVisible(_k('market_qurbon_chip'));
      await t.pumpAndSettle();
      await t.tap(_k('market_qurbon_chip'));
      await t.pumpAndSettle();
      expect(_k('market_card_a'), findsOneWidget);
      expect(_k('market_card_b'), findsNothing);
    });

    testWidgets('даврдан ташқари: баннер ва чип йўқ, белги қолади', (t) async {
      await pumpMarket(t, period: false);
      expect(_k('market_qurbon_banner'), findsNothing);
      expect(_k('market_qurbon_chip'), findsNothing);
      expect(_k('market_card_qurbon_a'), findsOneWidget);
    });

    testWidgets('320 px / 1.5 — overflow йўқ', (t) async {
      await pumpMarket(t, period: true, width: 320, scale: 1.5);
      expect(t.takeException(), isNull);
    });

    testWidgets('форма: таксономияда `qurbon_ready` бўлса — ихтиёрий белги (bool майдон)', (t) async {
      final values = <String, Object?>{};
      await t.pumpWidget(_app(Scaffold(
        body: StatefulBuilder(
          builder: (ctx, set) => MarketFieldsEditor(
            fields: livestock.market('livestock')!.fieldsFor('sheep_goat'),
            values: values,
            errors: const {},
            onChanged: (k, v) => set(() => values[k] = v),
          ),
        ),
      )));
      await t.pumpAndSettle();
      expect(_k('market_field_qurbon_ready'), findsOneWidget);
      expect(find.text('Қурбонликка мос'), findsOneWidget);
      await t.tap(_k('market_field_qurbon_ready'));
      await t.pump();
      expect(serializeAttrs(livestock.market('livestock')!, 'sheep_goat', values), {'qurbon_ready': true});
      expect(livestock.market('meat')!.fieldsFor('beef').any((f) => f.key == kQurbonReadyAttr), isFalse,
          reason: 'бошқа бозорда майдон йўқ — белги ҳам йўқ');
    });
  });

  // ─── l10n ──────────────────────────────────────────────────────────────────
  test('янги калитлар 3 тилда бор ва бўш эмас; uz_Latn янги алифбода (o‘/g‘/sh/ch йўқ)', () {
    const keys = [
      'sm_gift_info', 'sm_gift_privacy', 'sm_incentive_estimate', 'sm_after_bonus', 'hb_guests_hint',
      'restaurants_m_dish_preorder', 'restaurants_m_dish_preorder_hint', 'restaurants_m_dish_lead_days',
      'restaurants_preorder_lead_note', 'restaurants_preorder_err_lead',
      'market_qurbon_badge', 'market_qurbon_banner', 'market_qurbon_chip',
    ];
    for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
      final m = jsonDecode(File('assets/lang/$lang.json').readAsStringSync()) as Map<String, dynamic>;
      for (final k in keys) {
        expect((m[k] as String?)?.trim() ?? '', isNotEmpty, reason: '$lang $k');
        if (lang == 'uz_Latn') {
          expect(RegExp(r"o'|g'|sh|ch|o‘|g‘", caseSensitive: false).hasMatch(m[k] as String), isFalse, reason: k);
        }
      }
    }
  });
}

class _FakeSource implements MarketListingSource {
  _FakeSource(this.items);
  final List<TvShopItem> items;

  @override
  RingFetcher<TvShopItem> fetcher(MarketFilter filter) => (districtIds, startAfter, limit) async {
        final all = [
          for (final i in items)
            if (districtIds.contains(i.districtId) && i.market == filter.market && (filter.category.isEmpty || i.category == filter.category)) i,
        ];
        final start = startAfter is int ? startAfter : 0;
        final page = all.skip(start).take(limit).toList();
        return RingFetchResult(page, start + page.length);
      };

  @override
  Future<List<String>> districtsOf(String regionId) async => regionId == 'xorazm' ? ['gurlan'] : const [];

  @override
  Future<MarketSearchPage> search(MarketSearchRequest request, {Object? startAfter}) async => MarketSearchPage.empty;
}
