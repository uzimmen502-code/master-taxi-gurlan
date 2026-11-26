import 'package:ava_gurlan/features/admin_web/screens/holiday_admin_screen.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_holiday_service.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_incentives_service.dart';
import 'package:ava_gurlan/features/profile/widgets/holiday_reminders_toggle.dart';
import 'package:ava_gurlan/features/relatives/utils/relative_birthdays.dart';
import 'package:ava_gurlan/features/relatives/widgets/relative_upcoming_birthdays.dart';
import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/screens/restaurants_list_screen.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_holiday.dart';
import 'package:ava_gurlan/features/supermarket/domain/sm_taxonomy.dart';
import 'package:ava_gurlan/models/relative_person.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sm_fixture.dart';

Finder _k(String k) => find.byKey(ValueKey(k));

Widget _app(Widget home, {double textScale = 1}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    );

/// [daysAhead] кундан кейин туғилган кун (бугунга нисбатан).
RelativePerson _p(String id, int? daysAhead, {String phone = '', bool self = false}) {
  final now = DateTime.now();
  final d = daysAhead == null ? null : DateTime(now.year - 30, now.month, now.day + daysAhead);
  return RelativePerson(id: id, fullName: 'Қариндош $id', birthDate: d, phone: phone, isSelf: self);
}

class _FakeAdminApi implements AdminHolidayApi {
  final occasions = <HolidayOccasion>[
    const HolidayOccasion(id: 'navruz', names: {'uz_Cyrl': 'Наврўз', 'uz_Latn': 'Navröz', 'ru': 'Навруз'}, ruleType: 'fixed', md: '03-21', stage: 'off'),
  ];
  final savedOccasions = <HolidayOccasion>[];
  final savedBonus = <RelativesBonusProgram>[];

  @override
  Future<List<HolidayOccasion>> loadOccasions() async => occasions;
  @override
  Future<List<HolidayBasket>> loadBaskets() async => const [];
  @override
  Future<RelativesBonusProgram?> loadBonusProgram() async => null;
  @override
  Future<void> saveOccasion(HolidayOccasion o, {String reason = ''}) async => savedOccasions.add(o);
  @override
  Future<void> saveBasket(HolidayBasket b, {String reason = ''}) async {}
  @override
  Future<void> saveBonusProgram(RelativesBonusProgram p, {String reason = ''}) async => savedBonus.add(p);
}

class _FakeRestRepo implements RestaurantsRepository {
  _FakeRestRepo(this.list);
  final List<Restaurant> list;

  @override
  Stream<List<Restaurant>> watchApproved({int limit = 50}) => Stream.value(list);

  @override
  Stream<List<Restaurant>> watchNearby({
    required double lat,
    required double lng,
    double radiusKm = RestaurantsRepository.nearbyRadiusKm,
    int perCellLimit = 50,
  }) =>
      Stream.value(list);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'user_phone': '+998901234567'}));

  group('қариндошлар: яқин туғилган кунлар', () {
    test('30 кун ичида, «Мен»сиз, энг яқини олдин, кўпи билан 3 та', () {
      final list = upcomingBirthdaysWithin([
        _p('a', 20),
        _p('b', 0),
        _p('c', 31),
        _p('d', null),
        _p('me', 1, self: true),
        _p('e', 5),
        _p('f', 30),
      ]);
      expect(list.map((p) => p.id), ['b', 'e', 'a']);
      expect(upcomingBirthdaysWithin([_p('f', 30)]).single.id, 'f', reason: 'чегара 30');
    });

    test('«Саватча тайёрлаш»: телефон тўғри — совға олдиндан; йўқ — совғасиз', () {
      final g = relativeGiftCheckout(_p('a', 3, phone: '+998 90 111 22 33'));
      expect([g.asGift, g.recipientName, g.recipientPhone], [true, 'Қариндош a', '998901112233']);
      final none = relativeGiftCheckout(_p('b', 3, phone: '123'));
      expect([none.asGift, none.recipientPhone], [false, '']);
    });

    testWidgets('рўйхат бошидаги блок: тугма босилади; 320 px / 1.5 — overflow йўқ', (t) async {
      final tapped = <String>[];
      await t.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(_app(
        Scaffold(
          body: ListView(children: [
            RelativeUpcomingBirthdays(
              people: [_p('a', 0), _p('b', 12)],
              onPrepare: (p) => tapped.add(p.id),
              avatar: (p) => const CircleAvatar(child: Text('A')),
            ),
          ]),
        ),
        textScale: 1.5,
      ));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('rel_today'), findsOneWidget);
      await t.tap(_k('rel_prepare_basket_b'));
      expect(tapped, ['b']);
    });
  });

  group('профил: «Байрам эслатмалари»', () {
    test('майдон йўқ — ёқиқ; false — ўчиқ', () {
      expect(holidayRemindersOn(null), isTrue);
      expect(holidayRemindersOn({}), isTrue);
      expect(holidayRemindersOn({'holidayRemindersOptIn': false}), isFalse);
      expect(holidayRemindersOn({'holidayRemindersOptIn': true}), isTrue);
    });

    testWidgets('ўчириш → сақланади; хато бўлса қайтади', (t) async {
      final saved = <bool>[];
      var fail = false;
      await t.pumpWidget(_app(Scaffold(
        body: HolidayRemindersToggle(
          load: () async => true,
          save: (v) async {
            if (fail) throw Exception('offline');
            saved.add(v);
          },
        ),
      )));
      await t.pumpAndSettle();
      expect(t.widget<SwitchListTile>(_k('holiday_reminders_toggle')).value, isTrue);
      await t.tap(_k('holiday_reminders_toggle'));
      await t.pumpAndSettle();
      expect(saved, [false]);
      expect(t.widget<SwitchListTile>(_k('holiday_reminders_toggle')).value, isFalse);
      fail = true;
      await t.tap(_k('holiday_reminders_toggle'));
      await t.pumpAndSettle();
      expect(t.widget<SwitchListTile>(_k('holiday_reminders_toggle')).value, isFalse, reason: 'қайтди');
      expect(find.text('hb_reminders_save_failed'), findsOneWidget);
    });
  });

  group('админ', () {
    const names = {'uz_Cyrl': 'Наврўз', 'uz_Latn': 'Navröz', 'ru': 'Навруз'};

    test('байрам: тўғри (fixed / list / туғилган кун) ва хатолар (ID, 02-29, такрор сана, эслатма 0)', () {
      expect(holidayOccasionProblems(const HolidayOccasion(id: 'navruz', names: names, ruleType: 'fixed', md: '03-21', stage: 'off')), isEmpty);
      expect(holidayOccasionProblems(const HolidayOccasion(id: 'birthday', names: names, kind: 'birthday', stage: 'internal')), isEmpty);
      expect(
          holidayOccasionProblems(const HolidayOccasion(id: 'hayit', names: names, ruleType: 'list', dates: ['2027-03-10'], stage: 'public')),
          isEmpty);
      expect(holidayOccasionProblems(const HolidayOccasion(id: 'Navruz', names: names, ruleType: 'fixed', md: '03-21', stage: 'off')),
          hasLength(1));
      expect(holidayOccasionProblems(const HolidayOccasion(id: 'navruz', names: names, ruleType: 'fixed', md: '02-29', stage: 'off')),
          hasLength(1));
      expect(
          holidayOccasionProblems(
              const HolidayOccasion(id: 'hayit', names: names, ruleType: 'list', dates: ['2027-03-10', '2027-03-10'], stage: 'off')),
          hasLength(1));
      expect(
          holidayOccasionProblems(
              const HolidayOccasion(id: 'navruz', names: names, ruleType: 'fixed', md: '03-21', stage: 'off', remindDaysBefore: 0)),
          hasLength(1));
    });

    test('байрам toAdminMap: туғилган кун — dateRule null; fixed — {type, md}; list — {type, dates}', () {
      expect(const HolidayOccasion(id: 'b', names: names, kind: 'birthday').toAdminMap()['dateRule'], isNull);
      expect(const HolidayOccasion(id: 'n', names: names, ruleType: 'fixed', md: '03-21').toAdminMap()['dateRule'],
          {'type': 'fixed', 'md': '03-21'});
      final m = const HolidayOccasion(id: 'h', names: names, ruleType: 'list', dates: ['2027-03-10']).toAdminMap();
      expect(m['dateRule'], {'type': 'list', 'dates': ['2027-03-10']});
      expect(m['stage'], 'off', reason: 'бўш босқич — off');
      // Эга 2026-11-27: байрамда `target` (null — саватча), туғилган кунда `selfReminders`.
      expect(m.keys.toSet(), {'id', 'names', 'kind', 'bigHoliday', 'dateRule', 'remindDaysBefore', 'stage', 'order', 'image', 'target'});
      expect(m['target'], isNull);
      // Эслатмалар майдони йўқ — сервер сукути (D-7..D-3); бўш рўйхат — ўчиқ.
      expect(const HolidayOccasion(id: 'b', names: names, kind: 'birthday').toAdminMap().containsKey('selfReminders'), isFalse);
      expect(const HolidayOccasion(id: 'b', names: names, kind: 'birthday', selfReminders: []).toAdminMap()['selfReminders'],
          isEmpty);
    });

    test('саватча: такрор гуруҳ, меҳмон 0, бўш — хато; тўғриси — бўш; шакл', () {
      const ok = HolidayBasket(
        id: 'navruz_simple',
        occasionId: 'navruz',
        tier: 'simple',
        names: names,
        baseGuests: 10,
        items: [HolidayBasketItem(groupId: 'onion', qtyMilli: 1500, priority: 2)],
      );
      expect(holidayBasketProblems(ok), isEmpty);
      expect(ok.toAdminMap()['items'], [{'groupId': 'onion', 'qty': 1.5, 'priority': 2}]);
      expect(
          holidayBasketProblems(const HolidayBasket(
              id: 'navruz_simple',
              occasionId: 'navruz',
              tier: 'simple',
              names: names,
              baseGuests: 0,
              items: [HolidayBasketItem(groupId: 'onion', qtyMilli: 1000), HolidayBasketItem(groupId: 'onion', qtyMilli: 1000)])),
          hasLength(2));
      expect(holidayBasketProblems(const HolidayBasket(id: 'x', occasionId: '', tier: 'simple')), isNotEmpty);
    });

    test('бонус дастури: тўғри; миқдор 0 / қариндош 21 / бюджет < бонус — хато; умумий экранда қулф', () {
      const ok = RelativesBonusProgram(
        title: {'uz_Cyrl': 'Б', 'uz_Latn': 'B', 'ru': 'Б'},
        amount: 20000,
        minRelatives: 3,
        budgetTotal: 1000000,
        internalPhones: ['998901234567'],
      );
      expect(relativesBonusProblems(ok), isEmpty);
      expect(ok.toMap().keys.toSet(), {
        'title', 'stage', 'internalPhones', 'pilotDistrictIds', 'amount', 'minRelatives', 'minOrderAmount', 'maxOrderSharePct',
        'validityDays', 'budgetTotal',
      });
      const bad = RelativesBonusProgram(title: {'uz_Cyrl': 'Б', 'uz_Latn': 'B', 'ru': 'Б'}, amount: 0, minRelatives: 21, budgetTotal: 0);
      expect(relativesBonusProblems(bad), hasLength(3));
      expect(incentiveProgramLocked('relatives_birthdays', const {}), isTrue);
      expect(incentiveProgramLocked('x', const {'kind': 'relatives_birthdays'}), isTrue);
      expect(incentiveProgramLocked('women', const {}), isFalse);
    });

    testWidgets('байрамлар бўлими: янги байрам формаси — хато кўрсатилади, тўғриси callable га', (t) async {
      final api = _FakeAdminApi();
      await t.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(_app(Scaffold(
        body: HolidayAdminScreen(
          api: api,
          loadTaxonomy: () async => smTaxonomyFixture,
          loadOffers: (SmTaxonomy tx) async => smOffersFixture(),
        ),
      )));
      await t.pumpAndSettle();
      expect(_k('hb_admin_occasion_navruz'), findsOneWidget);
      await t.tap(_k('hb_admin_add_occasion'));
      await t.pumpAndSettle();
      await t.tap(_k('hb_admin_save'));
      await t.pumpAndSettle();
      expect(api.savedOccasions, isEmpty);
      expect(find.textContaining('ID:'), findsOneWidget);
      await t.enterText(_k('hb_admin_id'), 'new_year');
      await t.enterText(_k('hb_admin_name_cyrl'), 'Янги йил');
      await t.enterText(_k('hb_admin_name_latn'), 'Yangi yil');
      await t.enterText(_k('hb_admin_name_ru'), 'Новый год');
      await t.enterText(_k('hb_admin_md'), '01-01');
      await t.tap(_k('hb_admin_save'));
      await t.pumpAndSettle();
      expect(api.savedOccasions.single.toAdminMap()['dateRule'], {'type': 'fixed', 'md': '01-01'});
      expect(api.savedOccasions.single.id, 'new_year');
    });
  });

  testWidgets('ресторанлар: «Олдиндан буюртма» филтри (туғилган кун ҳаволасидан) — фақат acceptsPreorder; чип ўчирилади',
      (t) async {
    RestaurantsListScreen.resetLastKnownConfig();
    SharedPreferences.setMockInitialValues({});
    await t.binding.setSurfaceSize(const Size(2400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    Restaurant r(String id, bool pre) => Restaurant(
          id: id,
          name: id,
          status: 'approved',
          lat: 41.84,
          lng: 60.39,
          acceptsPreorder: pre,
          delivery: const RestaurantDelivery(mode: 'ava_courier', pickup: true),
        );
    await t.pumpWidget(MaterialApp(
      home: RestaurantsListScreen(
        repository: _FakeRestRepo([r('Tortchi', true), r('Oshxona', false)]),
        userLat: 41.84,
        userLng: 60.39,
        locate: () async => null,
        preorderOnly: true,
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Tortchi'), findsWidgets);
    expect(find.text('Oshxona'), findsNothing);
    await t.ensureVisible(_k('restaurants_filter_preorder'));
    await t.tap(_k('restaurants_filter_preorder'));
    await t.pumpAndSettle();
    expect(find.text('Oshxona'), findsWidgets);
  });
}
