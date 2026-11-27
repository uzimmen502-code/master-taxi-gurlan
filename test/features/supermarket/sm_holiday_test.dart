import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/utils/idempotency_keys.dart';
import 'package:ava_gurlan/features/home/controllers/home_holiday_cards.dart';
import 'package:ava_gurlan/features/home/widgets/home_lite_cards.dart';
import 'package:ava_gurlan/features/home/widgets/home_markets_block.dart';
import 'package:ava_gurlan/features/supermarket/data/holiday_repository.dart';
import 'package:ava_gurlan/features/supermarket/data/supermarket_repository.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_access.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_cart.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_holiday.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_inbox.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_list.dart';
import 'package:ava_gurlan/features/supermarket/screens/sm_checkout_screen.dart';
import 'package:ava_gurlan/features/supermarket/supermarket_controller.dart';
import 'package:ava_gurlan/models/news_item.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sm_fixture.dart';

// ─── Сохта манбалар ──────────────────────────────────────────────────────────

class _FakeHolidayApi implements HolidayApi {
  _FakeHolidayApi(this.catalog);
  final HolidayCatalog catalog;
  int loads = 0;

  @override
  Future<HolidayCatalog> loadCatalog() async {
    loads++;
    return catalog;
  }

  @override
  Future<HolidayBuildResult> build({required String basketId, int? guests, int? budget}) => throw UnimplementedError();

  @override
  Future<Object?> claimRelativesBonus() async => null;
}

Map<String, String> _n(String s) => {'uz_Cyrl': s, 'uz_Latn': '$s-lat', 'ru': '$s-ru'};

final _catalog = HolidayCatalog.fromMap({
  'today': '2026-11-26',
  'occasions': [
    {'id': 'new_year', 'names': _n('Янги йил'), 'kind': 'holiday', 'bigHoliday': true, 'order': 4, 'remindDaysBefore': 10, 'nextDate': '2027-01-01'},
    {'id': 'birthday', 'names': _n('Туғилган кун'), 'kind': 'birthday', 'order': 1, 'remindDaysBefore': 5, 'nextDate': null},
  ],
  'baskets': [
    {'id': 'birthday_large', 'occasionId': 'birthday', 'tier': 'large', 'names': _n('Катта'), 'baseGuests': 10, 'items': 14},
    {'id': 'birthday_simple', 'occasionId': 'birthday', 'tier': 'simple', 'names': _n('Оддий'), 'baseGuests': 10, 'items': 6},
  ],
});

final _build = HolidayBuildResult.fromMap({
  'lines': [
    {'productId': 'o_red_cheap', 'groupId': 'onion', 'name': 'Пиёз', 'price': 5000, 'qty': 1.5, 'qtyStep': 0.5, 'unit': 'kg', 'total': 7500, 'weighed': true, 'priority': 2},
    {'productId': 'p1', 'groupId': 'potato', 'name': 'Картошка', 'price': 6000, 'qty': 2, 'qtyStep': 1, 'unit': 'kg', 'total': 12000, 'weighed': true, 'priority': 1},
  ],
  'goods': 19500,
  'fee': 2145,
  'total': 21645,
  'changes': [
    {'type': 'swap', 'reason': 'budget', 'groupId': 'onion', 'fromOfferId': 'o_red_exp', 'toOfferId': 'o_red_cheap', 'saving': 3000},
    {'type': 'drop', 'reason': 'budget', 'groupId': 'milk', 'offerId': 'm1', 'saving': 12000},
    {'type': 'unavailable', 'groupId': 'empty'},
  ],
  'guests': 12,
  'budget': 22000,
  'withinBudget': true,
  'feePercent': 11,
});

SupermarketController _controller({FakeSupermarketApi? api, SmAccess? access}) {
  final c = SupermarketController(api: api ?? FakeSupermarketApi());
  c.setCatalogForTest(smTaxonomyFixture, smOffersFixture(), access: access ?? smAccessFixture);
  c.deliveryArea = const GeoArea(regionId: 'xorazm', districtId: 'gurlan', districtLabel: 'Гурлан');
  return c;
}

Widget _app(Widget home, {double textScale = 1}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    );

Finder _k(String k) => find.byKey(ValueKey(k));

final _today = DateTime(2026, 11, 26);

const _datedAccess = SmAccess(
  allowed: true,
  feePercent: 11,
  slots: [SmSlot(id: 's1', names: {}, startMin: 600, endMin: 720, day: 'today')],
  maxAheadDays: 14,
  dateSlots: {
    '2026-11-26': [SmSlot(id: 's1', names: {}, startMin: 600, endMin: 720, day: '2026-11-26')],
    '2026-12-05': [SmSlot(id: 's9', names: {}, startMin: 900, endMin: 1020, day: '2026-12-05')],
    '2026-12-20': [SmSlot(id: 's9', names: {}, startMin: 900, endMin: 1020, day: '2026-12-20')],
  },
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'user_phone': '+998901234567'});
    SupermarketAccessCache.resetForTest();
    HolidayCatalogCache.resetForTest();
  });

  group('домен: каталог, сана, меҳмон/бюджет', () {
    test('каталог: тартиб (order), саватлар даража бўйича, items сони', () {
      expect(_catalog.occasions.map((o) => o.id), ['birthday', 'new_year']);
      expect(_catalog.occasions.first.isBirthday, isTrue);
      final b = holidayBasketsFor(_catalog.baskets, 'birthday');
      expect(b.map((x) => x.tier), ['simple', 'large']);
      expect(b.first.itemsCount, 6);
      expect(holidayBasketsFor(_catalog.baskets, 'new_year'), isEmpty);
    });

    test('энг яқин сана: сервер nextDate; ҳар йили (ўтган бўлса — кейинги йил); рўйхат; туғилган кун — йўқ', () {
      final ny = _catalog.occasions.last;
      expect(nextOccasionDate(ny, _today), DateTime(2027, 1, 1));
      const navruz = HolidayOccasion(id: 'navruz', names: {}, ruleType: 'fixed', md: '03-21');
      expect(nextOccasionDate(navruz, _today), DateTime(2027, 3, 21));
      expect(nextOccasionDate(navruz, DateTime(2027, 3, 21)), DateTime(2027, 3, 21), reason: 'бугун ҳам ҳисоб');
      const hayit = HolidayOccasion(id: 'hayit', names: {}, ruleType: 'list', dates: ['2026-03-20', '2027-03-10', 'bad']);
      expect(nextOccasionDate(hayit, _today), DateTime(2027, 3, 10));
      expect(nextOccasionDate(_catalog.occasions.first, _today), isNull);
      expect(holidayMdValid('02-29'), isFalse);
      expect(holidayMdValid('13-01'), isFalse);
      expect(holidayFullDateValid('2027-02-30'), isFalse);
    });

    test('меҳмонлар: бўш — ихтиёрий; 1 ва 500 — чегара; 0 / 501 / ҳарф — хато', () {
      expect(holidayParseGuests('').value, isNull);
      expect(holidayParseGuests('').error, isNull);
      expect(holidayParseGuests('1').value, 1);
      expect(holidayParseGuests('500').value, 500);
      expect(holidayParseGuests('0').error, 'hb_err_guests');
      expect(holidayParseGuests('501').error, 'hb_err_guests');
      expect(holidayParseGuests('abc').error, 'hb_err_guests');
    });

    test('бюджет: бўшлиқлар олиб ташланади; 0 ва 100 000 001 — хато', () {
      expect(holidayParseBudget('').value, isNull);
      expect(holidayParseBudget('250 000').value, 250000);
      expect(holidayParseBudget('0').error, 'hb_err_budget');
      expect(holidayParseBudget('100000001').error, 'hb_err_budget');
      expect(holidayParseBudget('100000000').value, 100000000);
    });

    test('buildHolidayBasket жавоби: қаторлар, жами, ўзгаришлар; розилик шарти', () {
      expect(_build.lines.map((l) => l.productId), ['o_red_cheap', 'p1']);
      expect(_build.lines.first.qtyMilli, 1500);
      expect(_build.total, 21645);
      expect(_build.needsApproval, isTrue);
      expect(_build.changes.map(holidayChangeKey), ['hb_change_swap', 'hb_change_drop', 'hb_change_unavailable']);
      expect(holidayChangeKey(const HolidayChange(type: 'swap', groupId: 'g', toOfferId: 'x')), 'hb_change_swap_unavailable');
      expect(HolidayChange.fromMap({'type': 'scale', 'groupId': 'g'}), isNull, reason: 'номаълум тур ташланади');
      expect(const HolidayBuildResult().needsApproval, isFalse);
    });

    test('етказиш санаси: 0..14 кун; dateSlots дан фақат оралиғи борлари, тартибли', () {
      expect(smDeliveryDateOk(_today, _today), isTrue);
      expect(smDeliveryDateOk(DateTime(2026, 12, 10), _today), isTrue, reason: '14-кун');
      expect(smDeliveryDateOk(DateTime(2026, 12, 11), _today), isFalse, reason: '15-кун');
      expect(smDeliveryDateOk(DateTime(2026, 11, 25), _today), isFalse);
      final dates = smSelectableDates(_datedAccess.dateSlots, _today, maxDays: 14);
      expect(dates.map(smIsoDate), ['2026-11-26', '2026-12-05'], reason: '2026-12-20 — 14 кундан кейин');
    });

    test('getSupermarketAccess withDates: maxAheadDays + dateSlots ўқилади; бўш оралиқли сана — йўқ', () {
      final a = SmAccess.fromMap({
        'allowed': true,
        'slots': {'today': [], 'tomorrow': []},
        'maxAheadDays': 14,
        'dateSlots': [
          {'date': '2026-12-01', 'slots': [{'id': 's1', 'names': {}, 'startMin': 600, 'endMin': 720, 'date': '2026-12-01'}]},
          {'date': '2026-12-02', 'slots': []},
          {'date': 'bad', 'slots': []},
        ],
      });
      expect(a.maxAheadDays, 14);
      expect(a.dateSlots.keys, ['2026-12-01']);
      expect(a.dateSlots['2026-12-01']!.single.day, '2026-12-01');
      expect(SmAccess.fromMap({'allowed': true}).dateSlots, isEmpty, reason: 'эски жавоб');
    });
  });

  group('совға формаси', () {
    test('исм, телефон (9 ёки 998+9), табрик ≤ 200', () {
      expect(smGiftProblems(const SmGift(recipientName: 'Ali', recipientPhone: '901234567')), isEmpty);
      expect(smGiftProblems(const SmGift(recipientName: 'Ali', recipientPhone: '+998 90 123 45 67')), isEmpty);
      expect(smGiftProblems(const SmGift(recipientName: ' ', recipientPhone: '901234567')), ['sm_gift_err_name']);
      expect(smGiftProblems(const SmGift(recipientName: 'Ali', recipientPhone: '90123456')), ['sm_gift_err_phone']);
      expect(smGiftProblems(const SmGift(recipientName: 'Ali', recipientPhone: '79012345678')), ['sm_gift_err_phone']);
      expect(smGiftProblems(SmGift(recipientName: 'Ali', recipientPhone: '901234567', message: 'a' * 200)), isEmpty);
      expect(smGiftProblems(SmGift(recipientName: 'Ali', recipientPhone: '901234567', message: 'a' * 201)), ['sm_gift_err_message']);
      expect(smGiftProblems(SmGift(recipientName: 'a' * 61, recipientPhone: '901234567')), ['sm_gift_err_name']);
      expect(const SmGift(recipientName: ' Ali ', recipientPhone: '901234567', message: ' Табрик ').toMap(),
          {'recipientName': 'Ali', 'recipientPhone': '998901234567', 'message': 'Табрик', 'hidePrice': true});
    });

    test('байрам буюртмаси payload: deliveryDate, origin holiday, useIncentive, gift, occasion/basket; day ЙЎҚ', () {
      final p = smHolidayOrderPayload(
        clientRequestId: 'k1',
        cart: SmCart.empty.add('p1', 2000),
        address: const {'districtId': 'gurlan', 'phone': '998901234567'},
        slotId: 's9',
        deliveryDate: '2026-12-05',
        gift: const SmGift(recipientName: 'Ali', recipientPhone: '901234567'),
        occasionId: 'birthday',
        basketId: 'birthday_simple',
      );
      expect(p['deliveryDate'], '2026-12-05');
      expect(p['origin'], 'holiday');
      expect(p['useIncentive'], isTrue);
      expect(p['occasionId'], 'birthday');
      expect(p['basketId'], 'birthday_simple');
      expect((p['gift'] as Map)['hidePrice'], isTrue);
      expect(p.containsKey('day'), isFalse);
      expect(p['items'], [{'productId': 'p1', 'qty': 2}]);
      // Оддий буюртмада совға/сана йўқ; бонус эга 2026-11-27 дан ҳамма буюртмада (useIncentive: true).
      final old = smOrderPayload(clientRequestId: 'k', cart: SmCart.empty.add('p1', 1000), address: const {}, slotId: 's1', day: 'today');
      expect(old.containsKey('gift') || old.containsKey('deliveryDate'), isFalse);
      expect(old['useIncentive'], isTrue);
    });
  });

  group('бош саҳифа карточкалари', () {
    test('мавзу (эга 2026-11-28): эслатма даври ичидаги энг яқин байрам; мавзусиз/ўчиқ/узоқ — йўқ; админга сақланади', () {
      HolidayOccasion o(String id, String next, {String stage = '', bool theme = true, int remind = 5}) => HolidayOccasion.fromMap({
            'id': id, 'names': _n(id), 'kind': 'holiday', 'nextDate': next, 'stage': stage, 'remindDaysBefore': remind,
            if (theme) 'theme': {'uz_Cyrl': 'гуллар', 'uz_Latn': 'gullar', 'ru': 'цветы'},
          })!;
      final today = DateTime(2027, 2, 10);
      expect(holidayThemeNow([o('sevishganlar', '2027-02-14'), o('xotin_qizlar', '2027-03-08', remind: 10)], today)?.id, 'sevishganlar');
      expect(holidayThemeNow([o('sevishganlar', '2027-02-14')], today)!.themeText('uz_Latn'), 'gullar');
      expect(holidayThemeNow([o('a', '2027-02-20')], today), isNull, reason: '10 кун > 5');
      expect(holidayThemeNow([o('a', '2027-02-12', theme: false)], today), isNull);
      expect(holidayThemeNow([o('a', '2027-02-12', stage: 'off')], today), isNull);
      expect(o('a', '2027-02-12').toAdminMap()['theme'], {'uz_Cyrl': 'гуллар', 'uz_Latn': 'gullar', 'ru': 'цветы'});
      expect(o('a', '2027-02-12', theme: false).toAdminMap().containsKey('theme'), isFalse);
    });

    // Эга 2026-11-28: ҳафталик саватча — байрамга боғлиқ эмас, фақат супермаркет рухсати.
    test('ҳафталик саватча картаси: супермаркет очиқ + рухсат (байрам шарт ЭМАС)', () {
      expect(holidayCardVisible(smOpenable: true, smAllowed: true), isTrue);
      expect(holidayCardVisible(smOpenable: false, smAllowed: true), isFalse);
      expect(holidayCardVisible(smOpenable: true, smAllowed: false), isFalse);
    });

    test('holidayAvailable: каталогда ёқилган байрам ЙЎҚ бўлса ҳам — рухсат бўлса true; рухсат йўқ — false', () async {
      HolidayCatalogCache.resetForTest();
      SupermarketAccessCache.resetForTest(smAccessFixture);
      addTearDown(HolidayCatalogCache.resetForTest);
      addTearDown(() => SupermarketAccessCache.resetForTest());
      final empty = _FakeHolidayApi(HolidayCatalog.empty);
      expect(await holidayAvailable(smOpenable: true, api: empty, smApi: FakeSupermarketApi()), isTrue);
      expect(empty.loads, 1, reason: 'каталог кешга олдиндан юкланади');
      expect(await holidayAvailable(smOpenable: false, api: empty), isFalse);
    });

    // Эга 2026-11-28: карточка 5 тагача (аввал 3); бонус мақсади 3 ўзгармади.
    test('қариндошлар картаси: 4 — кўринади, 5 — яширин, байрам ёпиқ — яширин; прогресс фақат бонус фаолда', () {
      expect(kRelativesPromptHideAt, 5);
      expect(kRelativesBirthdayGoal, 3);
      expect(relativesPromptVisible(holidayAvailable: true, birthdaysCount: 2), isTrue);
      expect(relativesPromptVisible(holidayAvailable: true, birthdaysCount: 3), isTrue);
      expect(relativesPromptVisible(holidayAvailable: true, birthdaysCount: 4), isTrue);
      expect(relativesPromptVisible(holidayAvailable: true, birthdaysCount: 5), isFalse);
      expect(relativesPromptVisible(holidayAvailable: true, birthdaysCount: 6), isFalse);
      expect(relativesPromptVisible(holidayAvailable: false, birthdaysCount: 0), isFalse);
      expect(relativesBonusProgress(bonusActive: false, birthdaysCount: 2), isNull);
      final p = relativesBonusProgress(bonusActive: true, birthdaysCount: 2)!;
      expect([p.n, p.goal, p.left], [2, 3, 1]);
      expect(relativesBonusProgress(bonusActive: true, birthdaysCount: 9)!.left, 0);
    });

    test('claimRelativesBonus жавоби: NOT_ENOUGH_RELATIVES — фаол; PROGRAM_OFF / granted — йўқ', () {
      expect(relativesBonusFromClaim({'result': 'skip', 'code': 'NOT_ENOUGH_RELATIVES', 'count': 1}).active, isTrue);
      expect(relativesBonusFromClaim({'result': 'skip', 'code': 'NOT_ENOUGH_RELATIVES', 'count': 1}).count, 1);
      expect(relativesBonusFromClaim({'result': 'skip', 'code': 'PROGRAM_OFF'}).active, isFalse);
      expect(relativesBonusFromClaim({'result': 'granted'}).active, isFalse);
      expect(relativesBonusFromClaim(null).active, isFalse);
    });

    test('«Эълон ва хизматлар» тартиби (эга 2026-11-28): саватча йўқ («Бозорлар»да), қариндошлар — охирида, фақат байрам бўлса', () {
      List<String> ids({bool h = false, bool r = false}) => homeAdsServicesCardIds(
            isVisible: (id) => id == 'jobs',
            viewerBirthDate: '',
            restaurantsAllowed: false,
            holidayVisible: h,
            relativesPromptVisible: r,
          );
      expect(ids(), ['ads', 'vacancies']);
      expect(ids(h: true, r: true), ['ads', 'vacancies', 'relatives_bday']);
      expect(ids(h: true), ['ads', 'vacancies']);
      expect(ids(r: true), ['ads', 'vacancies']);
    });

    test('HomeHolidayCards: 3..4 — карточка бор, бонус сўралмайди; 5 — карточка йўқ', () async {
      var claims = 0;
      Future<Object?> claim() async {
        claims++;
        return {'result': 'skip', 'code': 'NOT_ENOUGH_RELATIVES', 'count': 2};
      }

      for (final n in [3, 4]) {
        final s = await HomeHolidayCards(holidayCheck: () async => true, countBirthdays: (_) async => n, claimBonus: claim)
            .resolve(smOpenable: true, phone: '998901234567');
        expect([s.showRelativesPrompt, s.bonusActive], [true, false], reason: '$n');
      }
      final s5 = await HomeHolidayCards(holidayCheck: () async => true, countBirthdays: (_) async => 5, claimBonus: claim)
          .resolve(smOpenable: true, phone: '998901234567');
      expect(s5.showRelativesPrompt, isFalse);
      expect(claims, 0);
      expect(HomeHolidayState.none.showRelativesPrompt, isFalse);
      expect(const HomeHolidayState(holiday: true).showRelativesPrompt, isFalse, reason: 'номаълум сон — карточка йўқ');
    });

    test('HomeHolidayCards: байрам ёпиқ — ҳеч нарса; ≥5 — карточка йўқ; <3 — бонус бир марта сўралади', () async {
      var claims = 0;
      Future<Object?> claim() async {
        claims++;
        return {'result': 'skip', 'code': 'NOT_ENOUGH_RELATIVES', 'count': 2};
      }

      final closed = HomeHolidayCards(holidayCheck: () async => false, countBirthdays: (_) async => 0, claimBonus: claim);
      expect(await closed.resolve(smOpenable: true, phone: '998901234567'), HomeHolidayState.none);
      final full = HomeHolidayCards(holidayCheck: () async => true, countBirthdays: (_) async => 5, claimBonus: claim);
      final s3 = await full.resolve(smOpenable: true, phone: '998901234567');
      expect([s3.holiday, s3.showRelativesPrompt, claims], [true, false, 0]);
      final two = HomeHolidayCards(holidayCheck: () async => true, countBirthdays: (_) async => 2, claimBonus: claim);
      final s2 = await two.resolve(smOpenable: true, phone: '+998 90 123 45 67');
      await two.resolve(smOpenable: true, phone: '998901234567');
      expect([s2.showRelativesPrompt, s2.bonusActive, claims], [true, true, 1]);
      two.invalidate();
      await two.resolve(smOpenable: true, phone: '998901234567');
      expect(claims, 2);
      final err = HomeHolidayCards(holidayCheck: () async => throw Exception('x'));
      expect(await err.resolve(smOpenable: true, phone: '998901234567'), HomeHolidayState.none);
    });

    // Эга 2026-11-28: бозор мақсадли байрам (Қурбон ҳайит → Мол бозори) супермаркет рухсатига боғлиқ эмас.
    group('бозор мақсадли байрам — супермаркетсиз', () {
      HolidayOccasion occ(String id, {String next = '2027-05-20', Map<String, Object?>? target, String stage = ''}) =>
          HolidayOccasion.fromMap({
            'id': id, 'names': _n(id), 'kind': 'holiday', 'order': 1, 'remindDaysBefore': 5, 'nextDate': next,
            'stage': stage, 'target': target,
          })!;
      const market = {'type': 'market', 'market': 'livestock', 'categories': ['cattle']};
      final today = DateTime(2027, 5, 10);

      test('holidayMarketOccasion: давр 0..15 кун; ўтган/узоқ/ўчиқ/саватча мақсади — йўқ', () {
        expect(holidayMarketOccasion([occ('qurbon_hayit', target: market)], today)?.id, 'qurbon_hayit');
        expect(holidayMarketOccasion([occ('qurbon_hayit', next: '2027-05-10', target: market)], today)?.id, 'qurbon_hayit');
        expect(holidayMarketOccasion([occ('qurbon_hayit', next: '2027-05-25', target: market)], today)?.id, 'qurbon_hayit');
        expect(holidayMarketOccasion([occ('qurbon_hayit', next: '2027-05-26', target: market)], today), isNull, reason: '16 кун');
        expect(holidayMarketOccasion([occ('qurbon_hayit', next: '2027-05-09', target: market)], today), isNull, reason: 'ўтган');
        expect(holidayMarketOccasion([occ('qurbon_hayit', target: market, stage: 'off')], today), isNull);
        expect(holidayMarketOccasion([occ('navruz', target: const {'type': 'holiday_basket', 'occasionId': 'navruz'})], today), isNull);
        expect(holidayMarketOccasion([occ('navruz')], today), isNull);
        expect(holidayMarketOccasion(const [], today), isNull);
      });

      test('repo: супермаркет ёпиқ — саватча йўқ, бозор байрами БОР (сервер каталоги уни беради)', () async {
        HolidayCatalogCache.resetForTest();
        addTearDown(HolidayCatalogCache.resetForTest);
        final api = _FakeHolidayApi(HolidayCatalog(occasions: [occ('qurbon_hayit', target: market)]));
        expect(await holidayAvailable(smOpenable: false, api: api), isFalse);
        final m = await holidayMarketAvailable(api: api, today: today);
        expect([m?.id, m?.target?.market], ['qurbon_hayit', 'livestock']);
        expect(api.loads, 1);
      });

      test('HomeHolidayCards: саватча ёпиқ + бозор байрами — фақат бозор карточкаси; қариндошлар йўқ; хато ажралган', () async {
        final q = occ('qurbon_hayit', target: market);
        final s = await HomeHolidayCards(holidayCheck: () async => false, marketCheck: () async => q)
            .resolve(smOpenable: false, phone: '998901234567');
        expect([s.holiday, s.showRelativesPrompt, s.market?.id], [false, false, 'qurbon_hayit']);
        expect(s == HomeHolidayState.none, isFalse);
        final both = await HomeHolidayCards(
          holidayCheck: () async => true,
          countBirthdays: (_) async => 5,
          marketCheck: () async => q,
        ).resolve(smOpenable: true, phone: '998901234567');
        expect([both.holiday, both.market?.id], [true, 'qurbon_hayit']);
        final basketErr = await HomeHolidayCards(holidayCheck: () async => throw Exception('x'), marketCheck: () async => q)
            .resolve(smOpenable: true, phone: '998901234567');
        expect([basketErr.holiday, basketErr.market?.id], [false, 'qurbon_hayit']);
        final marketErr = await HomeHolidayCards(holidayCheck: () async => false, marketCheck: () async => throw Exception('y'))
            .resolve(smOpenable: true, phone: '998901234567');
        expect(marketErr, HomeHolidayState.none);
      });

      test('holidayMarketCardFor: байрам номи, Мол бозори расми, дарвоза — бозор модули; босилса мақсад', () {
        HolidayTarget? opened;
        final q = occ('qurbon_hayit', target: market);
        final c = holidayMarketCardFor(q, lang: 'uz_Latn', caption: 'cap', isVisible: (_) => true, onOpen: (t) => opened = t)!;
        expect([c.id, c.title, c.caption, c.imagePath], ['holiday_market', 'qurbon_hayit-lat', 'cap', 'assets/images/markets/market_livestock_v3.webp']);
        c.onTap();
        expect([opened?.market, opened?.initialCategory], ['livestock', 'cattle']);
        expect(holidayMarketCardFor(q, lang: 'uz_Cyrl', caption: '', isVisible: (id) => id != 'livestock_market', onOpen: (_) {}), isNull);
        expect(holidayMarketCardFor(null, lang: 'uz_Cyrl', caption: '', isVisible: (_) => true, onOpen: (_) {}), isNull);
        expect(holidayMarketCardFor(occ('navruz'), lang: 'uz_Cyrl', caption: '', isVisible: (_) => true, onOpen: (_) {}), isNull);
      });
    });
  });

  group('push / «Хабарлар» йўналиши', () {
    test('holiday_reminder → байрам; holiday_birthday_reminder → туғилган кун + қариндош; бонус; бошқа — йўқ', () {
      final a = holidayPushTarget({'type': 'holiday_reminder', 'occasionId': 'navruz'})!;
      expect([a.kind, a.occasionId, a.personId], [HolidayPushKind.occasion, 'navruz', '']);
      final b = holidayPushTarget({'type': 'holiday_birthday_reminder', 'occasionId': 'birthday', 'personId': 'p_1'})!;
      expect([b.kind, b.occasionId, b.personId], [HolidayPushKind.birthday, 'birthday', 'p_1']);
      expect(holidayPushTarget({'type': 'holiday_relatives_bonus'})!.kind, HolidayPushKind.bonus);
      final bad = holidayPushTarget({'type': 'holiday_birthday_reminder', 'personId': '../x', 'occasionId': 'a b'})!;
      expect([bad.occasionId, bad.personId], ['', ''], reason: 'нотўғри ID бўш');
      expect(holidayPushTarget({'type': 'sm_weekly_reminder'}), isNull);
      expect(holidayPushTarget(const {}), isNull);
    });

    test('инбокс: source + occasionId/personId — push билан бир хил', () {
      final n = NewsItem(
        id: 'n1',
        title: 't',
        body: 'b',
        createdAt: DateTime(2026, 11, 26),
        source: 'holiday_birthday_reminder',
        occasionId: 'birthday',
        personId: 'p9',
      );
      final t = holidayInboxTarget(n)!;
      expect([t.kind, t.personId], [HolidayPushKind.birthday, 'p9']);
      expect(holidayInboxTarget(NewsItem(id: 'x', title: '', body: '', createdAt: DateTime(2026), source: 'order_status')), isNull);
    });
  });

  test('курьер: совға — қабул қилувчига қўнғироқ; оддий — буюртмачи', () {
    const gift = OrderModel(
      id: 'o1',
      type: 'platform',
      total: 0,
      status: 'new',
      items: [],
      userPhone: '998900000001',
      giftRecipientName: 'Ali',
      giftRecipientPhone: '998900000002',
      giftHidePrice: true,
    );
    expect(gift.isGift, isTrue);
    expect(gift.courierCallPhone, '998900000002');
    const plain = OrderModel(id: 'o2', type: 'platform', total: 0, status: 'new', items: [], userPhone: '998900000001');
    expect(plain.isGift, isFalse);
    expect(plain.courierCallPhone, '998900000001');
  });

  test('ўз саватчаси: occasionId ёзилади ва ўқилади; бўш — ёзилмайди (эски ҳужжатлар)', () {
    const l = SmList(id: 'a', name: 'Наврўз', occasionId: 'navruz');
    expect(l.toMap()['occasionId'], 'navruz');
    expect(l.copyWith(name: 'x').occasionId, 'navruz');
    expect(const SmList(id: 'b', name: 'n').toMap().containsKey('occasionId'), isFalse);
    expect(SmList.fromMap('c', {'name': 'n', 'items': [], 'occasionId': 'birthday'}).occasionId, 'birthday');
  });

  group('экранлар', () {
    testWidgets('расмийлаштириш (байрам): withDates, сана чиплари, совға текшируви, payload', (t) async {
      final api = FakeSupermarketApi(access: _datedAccess);
      final c = _controller(api: api, access: _datedAccess);
      c.addToCart('p1', 1000);
      await t.binding.setSurfaceSize(const Size(420, 2600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      var n = 0;
      await t.pumpWidget(_app(SmCheckoutScreen(
        controller: c,
        balance: Stream.value(10000000),
        keys: IdempotencyKeys(generator: () => 'key-${++n}'),
        pickArea: (_) async => null,
        today: _today,
        holiday: const SmHolidayCheckout(occasionId: 'birthday', basketId: 'birthday_simple', asGift: true, recipientName: 'Ali'),
      )));
      await t.pumpAndSettle();
      expect(api.accessWithDates.last, isTrue);
      expect(_k('sm_date_2026-11-26'), findsOneWidget);
      expect(_k('sm_date_2026-12-05'), findsOneWidget);
      expect(_k('sm_date_2026-12-20'), findsNothing, reason: '14 кундан кейин');
      expect(_k('sm_gift_info'), findsOneWidget);

      await t.tap(_k('sm_date_2026-12-05'));
      await t.pump();
      await t.tap(_k('sm_slot_s9'));
      await t.enterText(_k('sm_addr_phone'), '+998 90 123 45 67');
      await t.pump();
      // Совға телефони йўқ — босилганда хато кўрсатилади, сервер чақирилмайди.
      await t.ensureVisible(_k('sm_confirm'));
      await t.tap(_k('sm_confirm'));
      await t.pump();
      expect(find.text('sm_gift_err_phone'), findsOneWidget);
      expect(api.payloads, isEmpty);

      await t.enterText(_k('sm_gift_phone'), '90 765 43 21');
      await t.enterText(_k('sm_gift_message'), 'Туғилган кунингиз муборак!');
      await t.pump();
      await t.ensureVisible(_k('sm_confirm'));
      await t.tap(_k('sm_confirm'));
      await t.pumpAndSettle();
      final p = api.payloads.single;
      expect(p['deliveryDate'], '2026-12-05');
      expect(p['slotId'], 's9');
      expect(p['origin'], 'holiday');
      expect(p['useIncentive'], isTrue);
      expect(p['occasionId'], 'birthday');
      expect(p['basketId'], 'birthday_simple');
      expect(p['gift'], {'recipientName': 'Ali', 'recipientPhone': '998907654321', 'message': 'Туғилган кунингиз муборак!', 'hidePrice': true});
      expect(p.containsKey('day'), isFalse);
    });

    testWidgets('табрик 200 белгидан ошмайди (майдон чеклайди)', (t) async {
      final c = _controller(api: FakeSupermarketApi(access: _datedAccess), access: _datedAccess);
      c.addToCart('p1', 1000);
      await t.binding.setSurfaceSize(const Size(420, 2600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(_app(SmCheckoutScreen(
        controller: c,
        balance: Stream.value(10000000),
        today: _today,
        holiday: const SmHolidayCheckout(asGift: true),
      )));
      await t.pumpAndSettle();
      await t.enterText(_k('sm_gift_message'), 'x' * 250);
      await t.pump();
      expect(t.widget<TextField>(_k('sm_gift_message')).controller!.text.length, 200);
    });

    testWidgets('оддий расмийлаштириш ўзгармаган: совға/сана блоки йўқ, withDates сўралмайди', (t) async {
      final api = FakeSupermarketApi();
      final c = _controller(api: api);
      c.addToCart('p1', 1000);
      await t.pumpWidget(_app(SmCheckoutScreen(controller: c, balance: Stream.value(1000000), pickArea: (_) async => null)));
      await t.pumpAndSettle();
      expect(_k('sm_gift_section'), findsNothing);
      expect(_k('sm_delivery_dates'), findsNothing);
      expect(api.accessWithDates.last, isFalse);
    });
  });

  group('катта шрифт 1.5 / 320 px — overflow йўқ (байрам)', () {
    final screens = <String, Widget Function()>{
      'checkout': () {
        final c = _controller(api: FakeSupermarketApi(access: _datedAccess), access: _datedAccess);
        c.addToCart('p1', 1000);
        return SmCheckoutScreen(
          controller: c,
          balance: Stream.value(10000000),
          today: _today,
          holiday: const SmHolidayCheckout(asGift: true, recipientName: 'Алишер Навоий номидаги қабул қилувчи'),
        );
      },
      'home_cards': () => Scaffold(
            body: ListView(children: [
              HomeLiteSection(title: 'home_lite_section_ads_services', cards: [
                HomeLiteCardData(id: 'holiday', title: 'Байрам саватчаси', caption: 'Туғилган кун, Наврўз, Ҳайит, Янги йил — тайёр саватчалар', icon: Icons.celebration_rounded, fit: HomeLiteImageFit.contain, onTap: () {}),
                HomeLiteCardData(id: 'relatives_bday', title: 'Яқинларингиз туғилган кунини қўшинг', caption: '2/3 — бонус учун яна 1 та', icon: Icons.cake_rounded, fit: HomeLiteImageFit.contain, onTap: () {}),
              ]),
            ]),
          ),
    };
    for (final e in screens.entries) {
      testWidgets(e.key, (t) async {
        await t.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(_app(e.value(), textScale: 1.5));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        // Пастгача айлантириб ҳам.
        final list = find.byType(Scrollable).first;
        await t.drag(list, const Offset(0, -2000));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });
}
