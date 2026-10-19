// Стол бронь, клиент томони (S5, D-REST-23/38, эга 2026-10-19). Қоида, сиғим ва пул — серверда
// (`functions/test/restaurant_bookings_cf.test.js`); бу ерда: созлама ва модел, мижоз варағи, «Менинг бронларим»,
// ресторан панели («Бронлар»), профил формаси, 3 тил, тор экран.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/bookings.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_sections.dart';
import 'package:ava_gurlan/features/restaurants/merchant/merchant_bookings_tab.dart';
import 'package:ava_gurlan/features/restaurants/merchant/restaurant_register_form.dart';
import 'package:ava_gurlan/features/restaurants/screens/my_bookings_screen.dart';
import 'package:ava_gurlan/features/restaurants/screens/restaurant_screen.dart';
import 'package:ava_gurlan/features/restaurants/screens/restaurants_list_screen.dart';
import 'package:ava_gurlan/features/restaurants/widgets/booking_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'restaurants_l10n_harness.dart';

const _uid = '998912000001';

Restaurant _rest({
  bool bookings = true,
  int seats = 20,
  String note = '',
  bool disabled = false,
  OpeningHours? hours,
  DateTime? paused,
}) =>
    Restaurant(
      id: 'r1',
      name: 'Gurlan osh',
      status: 'approved',
      acceptsBookings: bookings,
      bookingSeats: seats,
      bookingNote: note,
      bookingsDisabled: disabled,
      openingHours: hours,
      pausedUntil: paused,
    );

RestaurantBooking _bk(
  String id, {
  String status = BookingStatus.requested,
  DateTime? at,
  int guests = 4,
  int fee = 50000,
  bool charged = false,
  DateTime? deadline,
}) =>
    RestaurantBooking(
      id: id,
      restaurantId: 'r1',
      restaurantName: 'Gurlan osh',
      restaurantAddress: 'Gurlan, markaz',
      userName: 'Ali',
      userPhone: _uid,
      guests: guests,
      startAt: at ?? DateTime.now().add(const Duration(days: 1)),
      status: status,
      feeAmount: fee,
      feeCharged: charged,
      acceptDeadlineAt: deadline ?? DateTime.now().add(const Duration(hours: 1)),
      note: 'deraza yonida',
    );

const _public = BookingConfig(stage: 'public');

void main() {
  // «Охирги маълум созлама» (экран очилишини тезлатади) тестлар орасида эскирмасин.
  setUp(RestaurantsListScreen.resetLastKnownConfig);
  final l10n = JsonL10nDelegate();
  String tr(String key) => l10n.tr(key);

  group('BookingConfig', () {
    test('hujjat yo\'q / buzilgan — OFF: hech kimga ko\'rinmaydi', () {
      expect(BookingConfig.fromMap(null).visibleFor(_uid), isFalse);
      expect(BookingConfig.fromMap(const {'stage': 'pilot'}).stage, 'off');
      expect(BookingConfig.off.visibleFor(_uid), isFalse);
    });

    test('public — hammaga; internal — faqat tester; off — hech kimga', () {
      expect(BookingConfig.fromMap(const {'stage': 'public'}).visibleFor(null), isTrue);
      final internal = BookingConfig.fromMap(const {'stage': 'internal', 'testerIds': ['998912000001']});
      expect(internal.visibleFor(_uid), isTrue);
      expect(internal.visibleFor('998912000002'), isFalse);
      expect(internal.visibleFor(null), isFalse);
      expect(BookingConfig.fromMap(const {'stage': 'off', 'testerIds': ['998912000001']}).visibleFor(_uid), isFalse);
    });

    test('ega tarifi: 1–5 → 50 000, 6–10 → 150 000, 11+ → 400 000; chegaralar 5/6, 10/11; 101 — yo\'q', () {
      int? fee(int g) => _public.tierFor(g)?.fee;
      expect([1, 5, 6, 10, 11, 100].map(fee), [50000, 50000, 150000, 150000, 400000, 400000]);
      expect(fee(0), isNull);
      expect(fee(101), isNull);
      expect(_public.maxGuests, 100);
    });

    test('buzilgan pog\'onalar → default; to\'g\'rilari o\'qiladi', () {
      final custom = BookingConfig.fromMap(const {
        'stage': 'public',
        'tiers': [
          {'upTo': 3, 'fee': 1000},
          {'upTo': 8, 'fee': 2000},
        ]
      });
      expect(custom.tierFor(3)!.fee, 1000);
      expect(custom.tierFor(4)!.fee, 2000);
      expect(custom.tierFor(9), isNull);
      for (final bad in [
        [<String, dynamic>{'upTo': 5, 'fee': 1.5}],
        [<String, dynamic>{'upTo': 5, 'fee': 1}, <String, dynamic>{'upTo': 5, 'fee': 2}],
        [<String, dynamic>{'upTo': 5, 'fee': -1}],
        <Map<String, dynamic>>[],
      ]) {
        expect(BookingConfig.fromMap({'stage': 'public', 'tiers': bad}).tiers.map((t) => t.upTo), [5, 10, 100], reason: '$bad');
      }
    });

    test('SERVER BILAN MOSLIK: default pog\'onalar va qoidalar functions/restaurant_bookings.js DEFAULTS bilan bir xil', () {
      final src = File('functions/restaurant_bookings.js').readAsStringSync();
      final tiers = RegExp(r'Object\.freeze\(\{ upTo: (\d+), fee: (\d+) \}\)').allMatches(src).map((m) => (int.parse(m[1]!), int.parse(m[2]!))).toList();
      expect(tiers, BookingConfig.defaultTiers.map((t) => (t.upTo, t.fee)).toList());
      int num(String k) => int.parse(RegExp('$k: (\\d+)').firstMatch(src.substring(src.indexOf('const DEFAULTS')))![1]!);
      expect(num('slotMin'), const BookingConfig().slotMin);
      expect(num('minLeadMin'), const BookingConfig().minLeadMin);
      expect(num('maxDays'), const BookingConfig().maxDays);
      expect(num('maxActivePerGuest'), const BookingConfig().maxActivePerGuest);
    });
  });

  group('RestaurantBooking', () {
    final now = DateTime(2026, 10, 19, 12);
    test('fromMap: tur va buzilgan qiymatlar xavfsiz; noma\'lum holat — requested', () {
      final b = RestaurantBooking.fromMap('b1', {
        'restaurantId': 'r1',
        'restaurantName': 'X',
        'guests': 4.0,
        'status': 'nope',
        'fee': {'amount': 150000, 'charged': true},
        'note': 5,
      });
      expect([b.guests, b.status, b.feeAmount, b.feeCharged, b.note], [4, BookingStatus.requested, 150000, true, '']);
      expect(RestaurantBooking.fromMap('b2', const {}).guests, 0);
    });

    test('ruxsatlar: mijoz bekor — faol va kelajak; restoran javobi — requested, muddat va vaqt o\'tmagan; bekor — faqat tasdiqlangan', () {
      final future = now.add(const Duration(days: 1));
      final req = _bk('a', at: future, deadline: now.add(const Duration(hours: 1)));
      expect([req.canGuestCancel(now), req.canRestaurantAnswer(now), req.canRestaurantCancel(now)], [true, true, false]);
      final conf = _bk('b', status: BookingStatus.confirmed, at: future);
      expect([conf.canGuestCancel(now), conf.canRestaurantAnswer(now), conf.canRestaurantCancel(now)], [true, false, true]);
      final late = _bk('c', at: future, deadline: now.subtract(const Duration(minutes: 1)));
      expect(late.canRestaurantAnswer(now), isFalse, reason: 'muddat o\'tgan');
      final past = _bk('d', status: BookingStatus.confirmed, at: now.subtract(const Duration(hours: 1)));
      expect([past.canGuestCancel(now), past.canRestaurantCancel(now)], [false, false]);
      for (final s in [BookingStatus.rejected, BookingStatus.expired, BookingStatus.cancelledByGuest, BookingStatus.cancelledByRestaurant]) {
        final x = _bk('e', status: s, at: future);
        expect([x.canGuestCancel(now), x.canRestaurantAnswer(now), x.canRestaurantCancel(now)], [false, false, false], reason: s);
      }
    });
  });

  group('Booking.check (server qoidasining nusxasi)', () {
    final now = DateTime(2026, 10, 19, 12);
    String? check(DateTime start, {int guests = 4, Restaurant? r}) => Booking.check(now: now, start: start, guests: guests, restaurant: r ?? _rest(), config: _public);

    test('chegaralar: 60 daqiqa aniq — ok, 59 — soon; 30 kun — ok, 30 kun + 1 daq — far', () {
      expect(check(now.add(const Duration(minutes: 59))), Booking.errSoon);
      expect(check(now.add(const Duration(minutes: 60))), isNull);
      expect(check(now.add(const Duration(days: 30))), isNull);
      expect(check(now.add(const Duration(days: 30, minutes: 1))), Booking.errFar);
    });

    test('mehmonlar: 0 va ko\'p — guests; joylardan ko\'p — seats; ish vaqti va pauza', () {
      final t = now.add(const Duration(hours: 5));
      expect(check(t, guests: 0), Booking.errGuests);
      expect(check(t, guests: 101), Booking.errGuests);
      expect(check(t, guests: 21), Booking.errSeats);
      expect(check(t, r: _rest(seats: 0)), Booking.errSeats);
      expect(check(DateTime(2026, 10, 19, 23), r: _rest(hours: const OpeningHours(open: '09:00', close: '22:00'))), Booking.errClosed);
      expect(check(DateTime(2026, 10, 19, 18), r: _rest(hours: const OpeningHours(open: '09:00', close: '22:00'))), isNull);
      expect(check(t, r: _rest(paused: t.add(const Duration(hours: 1)))), Booking.errPaused);
    });

    test('suggest: kamida minLead + 60 daqiqa keyin, 15 ga yaxlitlangan; days: bugundan boshlab 14 kun', () {
      final s = Booking.suggest(DateTime(2026, 10, 19, 12, 7), _public);
      expect(s.isAfter(DateTime(2026, 10, 19, 12, 7).add(const Duration(minutes: 120))) || s == DateTime(2026, 10, 19, 14, 15), isTrue);
      expect(s.minute % 15, 0);
      final days = Booking.days(now, _public);
      expect(days.first, DateTime(2026, 10, 19));
      expect(days.length, 15);
    });
  });

  group('Restaurant va profil formasi', () {
    test('Restaurant.fromMap: bron maydonlari; buzilgani — o\'chiq', () {
      final r = Restaurant.fromMap('a', {'name': 'A', 'acceptsBookings': true, 'bookingSeats': 12, 'bookingNote': 'Zakalat', 'bookingsDisabledReason': 'cancel_limit'});
      expect([r.acceptsBookings, r.bookingSeats, r.bookingNote, r.bookingsDisabled], [true, 12, 'Zakalat', true]);
      for (final v in ['12', 0, -1, 501, 2.5, null]) {
        expect(Restaurant.fromMap('a', {'name': 'A', 'bookingSeats': v}).bookingSeats, 0, reason: '$v');
      }
      for (final v in ['true', 1, null]) {
        expect(Restaurant.fromMap('a', {'name': 'A', 'acceptsBookings': v}).acceptsBookings, isFalse, reason: '$v');
      }
      expect(Restaurant.fromMap('a', const {'name': 'A'}).bookingsDisabled, isFalse);
    });

    test('forma: yoqilganda joylar 1..500 shart; patch faqat to\'g\'ri joy sonini yuboradi; ro\'yxatdan o\'tish payload\'ida yo\'q', () {
      final f = RestaurantFormData(name: 'Gurlan osh', lat: 41.8, lng: 60.3, address: 'x', acceptsBookings: true);
      expect(f.validate(), contains('booking_seats'));
      f.bookingSeats = 501;
      expect(f.validate(), contains('booking_seats'));
      f.bookingSeats = 20;
      expect(f.validate(), isNot(contains('booking_seats')));
      final patch = f.toProfilePatch();
      expect([patch['acceptsBookings'], patch['bookingSeats']], [true, 20]);
      final off = RestaurantFormData(name: 'A', lat: 1, lng: 1, address: 'x');
      expect(off.validate(), isNot(contains('booking_seats')));
      expect(off.toProfilePatch().containsKey('bookingSeats'), isFalse, reason: 'joy soni yo\'q — yuborilmaydi (rules int 1..500)');
      expect(off.toProfilePatch()['acceptsBookings'], isFalse);
      expect(off.toRegisterPayload().containsKey('acceptsBookings'), isFalse);
    });
  });

  group('BookingSheet', () {
    final fixedNow = DateTime(2026, 10, 19, 12);

    Future<_Repo> pump(WidgetTester t, {Restaurant? r, Object? failWith, double width = 390, double scale = 1.0}) async {
      t.view.physicalSize = Size(width * 3, 1800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final repo = _Repo(failWith: failWith);
      await t.pumpWidget(l10nApp(
        textScale: scale,
        home: Scaffold(
          body: BookingSheet(restaurant: r ?? _rest(note: 'Zakalat 100 000'), config: _public, repository: repo, clock: () => fixedNow),
        ),
      ));
      await t.pumpAndSettle();
      return repo;
    }

    testWidgets('boshlang\'ich holat: tavsiya vaqti, 2 mehmon, restoran eslatmasi, tushuntirish; tugma faol; narx KO\'RSATILMAYDI', (t) async {
      await pump(t);
      expect(find.byKey(const ValueKey('booking-cafe-note')), findsOneWidget);
      expect(find.text('Zakalat 100 000'), findsOneWidget);
      expect(find.byKey(const ValueKey('booking-how')), findsOneWidget);
      expect((t.widget(find.byKey(const ValueKey('booking-guests'))) as Text).data, '2');
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('booking-submit'))).onPressed, isNotNull);
      expect(find.textContaining('50 000'), findsNothing, reason: 'haqni restoran to\'laydi — mijozga ko\'rinmaydi');
    });

    testWidgets('mehmonlar: − 1 da to\'xtaydi, + restoran joyi (5) da to\'xtaydi', (t) async {
      await pump(t, r: _rest(seats: 5));
      for (var i = 0; i < 3; i++) {
        await t.tap(find.byKey(const ValueKey('booking-guests-minus')));
        await t.pump();
      }
      expect((t.widget(find.byKey(const ValueKey('booking-guests'))) as Text).data, '1');
      for (var i = 0; i < 9; i++) {
        await t.tap(find.byKey(const ValueKey('booking-guests-plus')));
        await t.pump();
      }
      expect((t.widget(find.byKey(const ValueKey('booking-guests'))) as Text).data, '5');
      expect(t.widget<IconButton>(find.byKey(const ValueKey('booking-guests-plus'))).onPressed, isNull);
    });

    testWidgets('yuborish: kalit, kechqurun 14:15 → so\'rov; callable argumentlari to\'g\'ri; varaq yopiladi', (t) async {
      final repo = _Repo();
      bool? result;
      t.view.physicalSize = const Size(390 * 3, 1800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(l10nApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              key: const ValueKey('open'),
              onPressed: () async => result = await showBookingSheet(ctx, restaurant: _rest(), config: _public, repository: repo, clock: () => fixedNow),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.byKey(const ValueKey('open')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('booking-guests-plus')));
      await t.enterText(find.byKey(const ValueKey('booking-note')), 'deraza yonida');
      await t.pump();
      await t.tap(find.byKey(const ValueKey('booking-submit')));
      await t.pumpAndSettle();
      expect(result, isTrue);
      expect(repo.placed, hasLength(1));
      final p = repo.placed.single;
      expect([p.restaurantId, p.guests, p.note], ['r1', 3, 'deraza yonida']);
      expect(p.idempotencyKey.length, greaterThanOrEqualTo(8));
      expect(p.startAt.isAfter(fixedNow.add(const Duration(minutes: 60))), isTrue);
      expect(find.byKey(const ValueKey('booking-submit')), findsNothing, reason: 'varaq yopildi');
    });

    testWidgets('server xatosi (NO_CAPACITY): matn chiqadi, varaq ochiq qoladi, QAYTA yuborish bir xil kalit bilan', (t) async {
      final repo = await pump(t, failWith: const RestaurantsException('failed-precondition', 'NO_CAPACITY', 'x'));
      await t.tap(find.byKey(const ValueKey('booking-submit')));
      await t.pumpAndSettle();
      expect(find.text(tr('restaurants_err_NO_CAPACITY')), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('booking-submit'))).onPressed, isNotNull);
      await t.tap(find.byKey(const ValueKey('booking-submit')));
      await t.pumpAndSettle();
      expect(repo.placed, hasLength(2));
      expect(repo.placed[0].idempotencyKey, repo.placed[1].idempotencyKey, reason: 'kalit varaq ochilganda BIR marta');
    });

    testWidgets('restoran ish vaqtidan tashqari vaqt: tugma o\'chiq, aniq sabab yoziladi', (t) async {
      await pump(t, r: _rest(hours: const OpeningHours(open: '09:00', close: '10:00')));
      expect(find.text(tr('restaurants_booking_err_closed_at_time')), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('booking-submit'))).onPressed, isNull);
    });

    testWidgets('tor ekran 320 + shrift ×2: overflow yo\'q', (t) async {
      await pump(t, r: _rest(note: 'Zakalat 100 000 so\'m, kartaga o\'tkaziladi, iltimos oldindan xabar bering'), width: 320, scale: 2.0);
      expect(t.takeException(), isNull);
    });
  });

  group('MyBookingsScreen', () {
    Future<_Repo> pump(WidgetTester t, List<RestaurantBooking> list, {Object? cancelFails}) async {
      t.view.physicalSize = const Size(390 * 3, 1800 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final repo = _Repo(mine: list, cancelFails: cancelFails);
      await t.pumpWidget(l10nApp(home: MyBookingsScreen(uid: _uid, repository: repo)));
      await t.pumpAndSettle();
      return repo;
    }

    testWidgets('bo\'sh ro\'yxat', (t) async {
      await pump(t, const []);
      expect(find.byKey(const ValueKey('bookings-empty')), findsOneWidget);
    });

    testWidgets('yaqinlashayotgan va o\'tgan alohida; holat matnlari; faqat faol bronda «Bekor qilish»', (t) async {
      await pump(t, [
        _bk('up1', at: DateTime.now().add(const Duration(days: 2))),
        _bk('up2', status: BookingStatus.confirmed, at: DateTime.now().add(const Duration(days: 1))),
        _bk('rej', status: BookingStatus.rejected),
        _bk('old', status: BookingStatus.confirmed, at: DateTime.now().subtract(const Duration(days: 3))),
      ]);
      expect(find.text(tr('restaurants_booking_upcoming')), findsOneWidget);
      expect(find.text(tr('restaurants_booking_past')), findsOneWidget);
      expect((t.widget(find.byKey(const ValueKey('booking-status-up2'))) as Text).data, tr('restaurants_booking_status_confirmed'));
      expect((t.widget(find.byKey(const ValueKey('booking-status-rej'))) as Text).data, tr('restaurants_booking_status_rejected'));
      expect(find.byKey(const ValueKey('booking-cancel-up1')), findsOneWidget);
      expect(find.byKey(const ValueKey('booking-cancel-up2')), findsOneWidget);
      expect(find.byKey(const ValueKey('booking-cancel-rej')), findsNothing);
      expect(find.byKey(const ValueKey('booking-cancel-old')), findsNothing, reason: 'o\'tgan bronni bekor qilib bo\'lmaydi');
    });

    testWidgets('bekor qilish: tasdiq dialogi → callable; «Yo\'q» — hech narsa chaqirilmaydi', (t) async {
      final repo = await pump(t, [_bk('up1')]);
      await t.tap(find.byKey(const ValueKey('booking-cancel-up1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('cancel-no')));
      await t.pumpAndSettle();
      expect(repo.guestCancelled, isEmpty);
      await t.tap(find.byKey(const ValueKey('booking-cancel-up1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('cancel-yes')));
      await t.pumpAndSettle();
      expect(repo.guestCancelled, ['up1']);
      expect(find.text(tr('restaurants_booking_cancelled_ok')), findsOneWidget);
    });

    testWidgets('bekor qilishda server xatosi — matn chiqadi', (t) async {
      await pump(t, [_bk('up1')], cancelFails: const RestaurantsException('failed-precondition', 'BOOKING_INVALID_TRANSITION', 'x'));
      await t.tap(find.byKey(const ValueKey('booking-cancel-up1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('cancel-yes')));
      await t.pumpAndSettle();
      expect(find.text(tr('restaurants_err_BOOKING_INVALID_TRANSITION')), findsOneWidget);
    });
  });

  group('MerchantBookingsTab', () {
    Future<_Repo> pump(WidgetTester t, List<RestaurantBooking> list, {Restaurant? r, Object? acceptFails, double width = 390, double scale = 1.0}) async {
      t.view.physicalSize = Size(width * 3, 2000 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final repo = _Repo(mine: list, acceptFails: acceptFails);
      await t.pumpWidget(l10nApp(textScale: scale, home: Scaffold(body: MerchantBookingsTab(restaurant: r ?? _rest(), repository: repo))));
      await t.pumpAndSettle();
      return repo;
    }

    testWidgets('bo\'limlar: javob kutayotgan, tasdiqlangan, o\'tgan; haq summasi ko\'rinadi (qabulgacha — «yechiladi», keyin — «yechilgan»)', (t) async {
      await pump(t, [
        _bk('n1', guests: 8, fee: 150000),
        _bk('c1', status: BookingStatus.confirmed, charged: true, fee: 50000, at: DateTime.now().add(const Duration(days: 2))),
        _bk('x1', status: BookingStatus.cancelledByGuest, charged: true, fee: 50000),
      ]);
      expect(find.text(tr('restaurants_m_bk_new')), findsOneWidget);
      expect(find.text(tr('restaurants_m_bk_confirmed')), findsOneWidget);
      expect(find.text(tr('restaurants_m_bk_past')), findsOneWidget);
      expect((t.widget(find.byKey(const ValueKey('bk-fee-n1'))) as Text).data, contains('150 000'));
      expect((t.widget(find.byKey(const ValueKey('bk-fee-n1'))) as Text).data, tr('restaurants_m_bk_fee').replaceAll('{amount}', '150 000'));
      expect((t.widget(find.byKey(const ValueKey('bk-fee-c1'))) as Text).data, tr('restaurants_m_bk_fee_charged').replaceAll('{amount}', '50 000'));
      expect(find.byKey(const ValueKey('bk-accept-n1')), findsOneWidget);
      expect(find.byKey(const ValueKey('bk-accept-c1')), findsNothing);
      expect(find.byKey(const ValueKey('bk-cancel-c1')), findsOneWidget);
      expect(find.byKey(const ValueKey('bk-cancel-x1')), findsNothing);
      expect(find.byKey(const ValueKey('bk-call-x1')), findsNothing, reason: 'bekor qilingan bronga qo\'ng\'iroq yo\'q');
    });

    testWidgets('qabul: callable chaqiriladi; hamyonda yetmasa aniq xato matni', (t) async {
      final repo = await pump(t, [_bk('n1')]);
      await t.tap(find.byKey(const ValueKey('bk-accept-n1')));
      await t.pumpAndSettle();
      expect(repo.accepted, ['n1']);
      expect(find.text(tr('restaurants_m_bk_accepted_ok')), findsOneWidget);
    });

    testWidgets('qabul — RESTAURANT_WALLET_INSUFFICIENT: xato ko\'rsatiladi', (t) async {
      await pump(t, [_bk('n1')], acceptFails: const RestaurantsException('failed-precondition', 'RESTAURANT_WALLET_INSUFFICIENT', 'x'));
      await t.tap(find.byKey(const ValueKey('bk-accept-n1')));
      await t.pumpAndSettle();
      expect(find.text(tr('restaurants_err_RESTAURANT_WALLET_INSUFFICIENT')), findsOneWidget);
    });

    testWidgets('rad etish; tasdiqlangan bronni bekor qilish — ogohlantirish dialogi (haq qaytmaydi), tasdiqdan keyin callable', (t) async {
      final repo = await pump(t, [_bk('n1'), _bk('c1', status: BookingStatus.confirmed, charged: true, at: DateTime.now().add(const Duration(days: 2)))]);
      await t.tap(find.byKey(const ValueKey('bk-reject-n1')));
      await t.pumpAndSettle();
      expect(repo.rejected, ['n1']);
      await t.tap(find.byKey(const ValueKey('bk-cancel-c1')));
      await t.pumpAndSettle();
      expect(find.text(tr('restaurants_m_bk_cancel_warn')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('bk-cancel-no')));
      await t.pumpAndSettle();
      expect(repo.restaurantCancelled, isEmpty);
      await t.tap(find.byKey(const ValueKey('bk-cancel-c1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('bk-cancel-yes')));
      await t.pumpAndSettle();
      expect(repo.restaurantCancelled, ['c1']);
    });

    testWidgets('lim itdan avtomat o\'chirilgan restoran: ogohlantirish; yoqilmagan — yo\'riqnoma', (t) async {
      await pump(t, const [], r: _rest(bookings: false, disabled: true));
      expect(find.text(tr('restaurants_m_booking_disabled')), findsOneWidget);
    });

    testWidgets('yoqilmagan restoran: yo\'riqnoma; yoqilgan — ogohlantirish yo\'q', (t) async {
      await pump(t, const [], r: _rest(bookings: false));
      expect(find.text(tr('restaurants_m_bk_not_enabled')), findsOneWidget);
      await pump(t, const []);
      expect(find.byKey(const ValueKey('bk-off-note')), findsNothing);
    });

    testWidgets('tor ekran 320 + shrift ×2: overflow yo\'q', (t) async {
      await pump(t, [_bk('n1', guests: 12, fee: 400000), _bk('c1', status: BookingStatus.confirmed, charged: true, at: DateTime.now().add(const Duration(days: 2)))], width: 320, scale: 2.0);
      expect(t.takeException(), isNull);
    });
  });

  group('Ekranlarga ulanish', () {
    setUp(() => SharedPreferences.setMockInitialValues({'user_phone': '+998 91 200 00 01'}));

    Future<void> pumpRestaurant(WidgetTester t, _Repo repo) async {
      t.view.physicalSize = const Size(390 * 3, 1600 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(l10nApp(
        home: RestaurantScreen(
          key: UniqueKey(),
          restaurant: _rest(),
          repository: repo,
          cart: RestaurantCart(),
          itemClipsLoader: (_) async => const {},
          restaurantVideoLoader: () async => null,
          dishStatsLoader: (_) async => const {},
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('RestaurantScreen: bron yoqilgan va restoran qabul qiladi — AppBar\'da tugma; bosilsa varaq ochiladi', (t) async {
      await pumpRestaurant(t, _Repo(config: _public, restaurant: _rest()));
      expect(find.byKey(const ValueKey('book-table')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('book-table')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('booking-submit')), findsOneWidget);
    });

    testWidgets('RestaurantScreen: sozlama OFF yoki restoran qabul qilmaydi yoki limitdan o\'chirilgan — tugma YO\'Q', (t) async {
      await pumpRestaurant(t, _Repo(config: BookingConfig.off, restaurant: _rest()));
      expect(find.byKey(const ValueKey('book-table')), findsNothing);
      await pumpRestaurant(t, _Repo(config: _public, restaurant: _rest(bookings: false)));
      expect(find.byKey(const ValueKey('book-table')), findsNothing);
      await pumpRestaurant(t, _Repo(config: _public, restaurant: _rest(disabled: true)));
      expect(find.byKey(const ValueKey('book-table')), findsNothing);
      await pumpRestaurant(t, _Repo(config: _public, restaurant: _rest(seats: 0)));
      expect(find.byKey(const ValueKey('book-table')), findsNothing);
    });

    testWidgets('RestaurantScreen: sozlamani o\'qib bo\'lmasa (xato) — ekran ishlayveradi, tugma yo\'q', (t) async {
      await pumpRestaurant(t, _Repo(configFails: true, restaurant: _rest()));
      expect(find.byKey(const ValueKey('book-table')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('RestaurantsListScreen: «Mening bronlarim» tugmasi faqat bron yoqilgan bo\'lsa', (t) async {
      Future<void> pumpList(_Repo repo) async {
        await t.pumpWidget(l10nApp(
          home: RestaurantsListScreen(key: UniqueKey(), repository: repo, currentUid: _uid, userLat: 41.84, userLng: 60.39, locate: () async => null),
        ));
        await t.pumpAndSettle();
      }

      await pumpList(_Repo(config: _public));
      expect(find.byKey(const ValueKey('my-bookings')), findsOneWidget);
      await pumpList(_Repo(config: BookingConfig.off));
      expect(find.byKey(const ValueKey('my-bookings')), findsNothing);
    });
  });

  group('3 tilda matnlar', () {
    Map<String, dynamic> load(String n) => jsonDecode(File('assets/lang/$n.json').readAsStringSync()) as Map<String, dynamic>;
    final cyrl = load('uz_Cyrl');
    final latn = load('uz_Latn');
    final ru = load('ru');

    final keys = <String>[
      'restaurants_booking_action', 'restaurants_booking_title', 'restaurants_booking_day', 'restaurants_booking_time',
      'restaurants_booking_guests', 'restaurants_booking_guests_n', 'restaurants_booking_note', 'restaurants_booking_how',
      'restaurants_booking_submit', 'restaurants_booking_sent', 'restaurants_booking_my', 'restaurants_booking_empty',
      'restaurants_booking_cancel', 'restaurants_booking_login_needed', 'restaurants_m_tab_bookings',
      'restaurants_m_booking_enable', 'restaurants_m_booking_hint', 'restaurants_m_booking_disabled',
      'restaurants_m_err_booking_seats', 'restaurants_m_bk_fee', 'restaurants_m_bk_cancel_warn',
      for (final s in BookingStatus.all) 'restaurants_booking_status_$s',
      for (final e in [Booking.errSoon, Booking.errFar, Booking.errPaused, Booking.errClosed, Booking.errGuests, Booking.errSeats]) 'restaurants_booking_err_$e',
      for (final e in [
        'BOOKINGS_OFF', 'BOOKINGS_INTERNAL_ONLY', 'GUESTS_INVALID', 'BOOKING_TIME_INVALID', 'BOOKING_TOO_SOON', 'BOOKING_TOO_FAR',
        'BOOKINGS_NOT_ACCEPTED', 'SEATS_NOT_CONFIGURED', 'BOOKING_CLOSED_AT_TIME', 'TOO_MANY_ACTIVE_BOOKINGS', 'DUPLICATE_BOOKING',
        'NO_CAPACITY', 'BOOKING_NOT_FOUND', 'NOT_BOOKING_OWNER', 'BOOKING_INVALID_TRANSITION', 'BOOKING_EXPIRED',
        'RESTAURANT_WALLET_INSUFFICIENT', 'IDEMPOTENCY_KEY_INVALID',
      ])
        'restaurants_err_$e',
    ];

    test('har kalit uchala tilda bor va bo\'sh emas; parametrlar bir xil', () {
      final ph = RegExp(r'\{(\w+)\}');
      for (final k in keys) {
        for (final m in [cyrl, latn, ru]) {
          expect((m[k] as String?)?.trim().isNotEmpty, isTrue, reason: k);
        }
        Set<String> p(Map<String, dynamic> m) => ph.allMatches(m[k] as String).map((x) => x[1]!).toSet();
        expect(p(latn), p(cyrl), reason: '$k latn/cyrl');
        expect(p(ru), p(cyrl), reason: '$k ru/cyrl');
      }
    });

    test('lotin matnda kirill harf, kirill/rus matnda lotin so\'z aralashmagan (AVA brendi istisno)', () {
      final cyr = RegExp(r'[Ѐ-ӿ]');
      final lat = RegExp(r'[A-Za-z]{2,}');
      for (final k in keys) {
        expect(cyr.hasMatch(latn[k] as String), isFalse, reason: 'latn $k');
        for (final m in [cyrl, ru]) {
          final s = (m[k] as String).replaceAll('AVA', '').replaceAll(RegExp(r'\{\w+\}'), '');
          expect(lat.hasMatch(s), isFalse, reason: '$k: $s');
        }
      }
    });

    test('rus matnda o\'zbekcha maxsus harflar (ў қ ғ ҳ) yo\'q', () {
      final uz = RegExp('[ўқғҳЎҚҒҲ]');
      for (final k in keys) {
        expect(uz.hasMatch(ru[k] as String), isFalse, reason: k);
      }
    });
  });
}

class _Placed {
  _Placed(this.idempotencyKey, this.restaurantId, this.guests, this.startAt, this.note);

  final String idempotencyKey;
  final String restaurantId;
  final int guests;
  final DateTime startAt;
  final String note;
}

class _Repo implements RestaurantsRepository {
  _Repo({
    this.failWith,
    this.mine = const [],
    this.cancelFails,
    this.acceptFails,
    this.config = BookingConfig.off,
    this.configFails = false,
    Restaurant? restaurant,
  }) : _restaurant = restaurant;

  final Object? failWith;
  final List<RestaurantBooking> mine;
  final Object? cancelFails;
  final Object? acceptFails;
  final BookingConfig config;
  final bool configFails;
  final Restaurant? _restaurant;

  final placed = <_Placed>[];
  final guestCancelled = <String>[];
  final accepted = <String>[];
  final rejected = <String>[];
  final restaurantCancelled = <String>[];

  @override
  Future<({String bookingId, int feeAmount, bool duplicate})> placeBooking({
    required String idempotencyKey,
    required String restaurantId,
    required int guests,
    required DateTime startAt,
    String note = '',
  }) async {
    placed.add(_Placed(idempotencyKey, restaurantId, guests, startAt, note));
    final err = failWith;
    if (err != null) throw err;
    return (bookingId: 'bk_1', feeAmount: 50000, duplicate: false);
  }

  @override
  Stream<List<RestaurantBooking>> watchMyBookings(String uid, {int limit = 50}) => Stream.value(mine);

  @override
  Stream<List<RestaurantBooking>> watchRestaurantBookings(String restaurantId, {int limit = 100}) => Stream.value(mine);

  @override
  Future<void> guestCancelBooking(String bookingId) async {
    guestCancelled.add(bookingId);
    final err = cancelFails;
    if (err != null) throw err;
  }

  @override
  Future<void> acceptBooking(String bookingId) async {
    accepted.add(bookingId);
    final err = acceptFails;
    if (err != null) throw err;
  }

  @override
  Future<void> rejectBooking(String bookingId, {String reason = ''}) async => rejected.add(bookingId);

  @override
  Future<bool> restaurantCancelBooking(String bookingId, {String reason = ''}) async {
    restaurantCancelled.add(bookingId);
    return false;
  }

  @override
  Future<BookingConfig> getBookingsConfig({bool force = false}) async {
    if (configFails) throw StateError('offline');
    return config;
  }

  // RestaurantScreen / RestaurantsListScreen
  @override
  Stream<Restaurant?> watchRestaurant(String id) => Stream.value(_restaurant);

  @override
  Stream<List<MenuCategory>> watchCategories(String restaurantId) => Stream.value(const []);

  @override
  Stream<List<MenuItem>> watchMenu(String restaurantId) => Stream.value(const []);

  @override
  Stream<List<Restaurant>> watchNearby({required double lat, required double lng, double radiusKm = RestaurantsRepository.nearbyRadiusKm, int perCellLimit = 50}) =>
      Stream.value(const []);

  @override
  Stream<List<Restaurant>> watchApproved({int limit = 50}) => Stream.value(const []);

  @override
  Future<RestaurantSectionsConfig> getSectionsConfig({bool force = false}) async => RestaurantSectionsConfig.off;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}
