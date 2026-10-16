import 'dart:async';

import 'package:ava_gurlan/features/ev_charging/controllers/ev_car_tracker.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_planner.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_selection.dart';
import 'package:ava_gurlan/features/ev_charging/models/ev_trip_plan.dart';
import 'package:ava_gurlan/features/ev_charging/screens/ev_trip_map_screen.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ev_test_support.dart';

// "Navigatsiya" Google Maps chegarasidan ko'p to'xtashni bloklamaydi:
// birinchi `limit` ta yuboriladi, qolgani "Keyingi to'xtashlar" bo'lib turadi;
// mashina oxirgi yuborilgandan o'tgach (yoki haydovchi bossa) "Davom etish".
// Matnlar haqiqiy (uz_Latn), shrift Inter, GPS - soxta oqim, Google Maps -
// soxta launcher.

const double _kmPerDegLat = 111.1949;
double _lat(double km) => 41.0 + km / _kmPerDegLat;

EvChargingStation _station(String id, double along) => EvChargingStation(
      id: id,
      latitude: _lat(along),
      longitude: 60.0,
      geohash: '',
      chargingTypes: const ['DC'],
      connectors: const ['CCS2'],
      powerKw: 120,
      status: 'working',
      verificationStatus: 'verified',
      confirmationCount: 2,
      reportCount: 0,
      createdBy: 'u1',
      isActive: true,
      name: 'ST-$id',
    );

EvTripPlan _plan(List<double> alongs) => EvTripPlan(
      status: EvTripPlanStatus.ok,
      stops: [
        for (final a in alongs)
          EvTripStop(
            station: _station('s${a.round()}', a),
            alongKm: a,
            offRouteKm: 0,
            legKm: a,
            arriveSocPercent: 18,
            departSocPercent: 80,
            backups: const [],
          ),
      ],
      totalKm: 640,
      arrivalSocPercent: 25,
    );

List<EvRoutePoint> _route() =>
    [for (var i = 0; i <= 100; i += 10) EvRoutePoint(_lat(i * 6.4), 60.0)];

/// Soxta GPS manbai: oxirgi nuqtani saqlaydi - qayta ochilganda (ilova
/// fondan qaytganda) birinchi bo'lib shuni beradi (haqiqiy manba kabi,
/// "oxirgi ma'lum joy").
class _Source implements EvCarLocationSource {
  final ctrl = StreamController<EvCarFix>.broadcast();
  EvCarFix? last;
  bool unavailable = false;

  @override
  Future<Stream<EvCarFix>?> open() async {
    if (unavailable) return null;
    return Stream<EvCarFix>.multi((c) {
      final l = last;
      if (l != null) c.add(l);
      final sub = ctrl.stream.listen(c.add);
      c.onCancel = sub.cancel;
    });
  }
}

class _Call {
  _Call(this.originLat, this.originLng, this.destLat, this.destLng, this.stops);
  final double originLat, originLng, destLat, destLng;
  final List<EvWaypoint> stops;
  List<double> get lats => [for (final s in stops) s.lat];
}

class _H {
  final calls = <_Call>[];
  bool result = true;
  final source = _Source();
  EvTripMapRenderData? last;
}

const _btn = ValueKey('ev_trip_navigate_button');
const _chip = ValueKey('ev_trip_next_chip');
const _card = ValueKey('ev_trip_next_card');
const _continue = ValueKey('ev_trip_continue_button');
const _close = ValueKey('ev_trip_next_close');
const _notice = ValueKey('ev_trip_nav_notice');
const _toggle = ValueKey('ev_station_sheet_toggle');

Future<_H> _pump(
  WidgetTester tester, {
  List<double> alongs = const [100, 200, 300, 400, 500],
  int? maxWaypoints = 3,
  Locale locale = evUzLatn,
  double scale = 1.0,
  Size size = const Size(400, 800),
  bool gps = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final h = _H();
  h.source.unavailable = !gps;
  await tester.pumpWidget(evL10nApp(
    locale: locale,
    textScale: scale,
    home: EvTripMapScreen(
      plan: _plan(alongs),
      route: _route(),
      corridorStations: const [],
      originLat: _lat(0),
      originLng: 60.0,
      destinationLat: _lat(640),
      destinationLng: 60.0,
      onOpenNavigator: () {},
      locationSource: h.source,
      maxWaypoints: maxWaypoints,
      routeLauncher: ({
        required double originLat,
        required double originLng,
        required double destinationLat,
        required double destinationLng,
        List<EvWaypoint> stops = const [],
      }) async {
        h.calls.add(
            _Call(originLat, originLng, destinationLat, destinationLng, stops));
        return h.result;
      },
      mapBuilder: (context, data) {
        h.last = data;
        return const ColoredBox(
          color: Color(0xFFCCDDEE),
          child: SizedBox.expand(),
        );
      },
    ),
  ));
  await tester.pumpAndSettle();
  return h;
}

/// Mashina yo'l boshidan [km] da.
Future<void> _drive(WidgetTester tester, _H h, double km) async {
  final fix = EvCarFix(lat: _lat(km), lng: 60.0);
  h.source.last = fix;
  h.source.ctrl.add(fix);
  await tester.pump();
  await tester.pump();
}

Future<void> _tapNavigate(WidgetTester tester) async {
  await tester.tap(find.byKey(_btn));
  await tester.pumpAndSettle();
}

String _tr(String key, [Map<String, String> params = const {}]) {
  var s = evTr(evUzLatn, key);
  params.forEach((k, v) => s = s.replaceAll('{$k}', v));
  return s;
}

String _chipText(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: find.byKey(_chip), matching: find.byType(Text)))
    .data!;

void main() {
  setUpAll(loadInterFont);

  group('chegaradan ko\'p to\'xtash bloklanmaydi', () {
    testWidgets('5 ta tanlangan, limit 3: birinchi 3 ta yuboriladi, manzil '
        'oxirgi manzil, xabar chiqadi, chip "2 ta"', (tester) async {
      final h = await _pump(tester);
      await _tapNavigate(tester);

      expect(h.calls, hasLength(1));
      final c = h.calls.single;
      expect(c.originLat, closeTo(_lat(0), 1e-12));
      expect(c.destLat, closeTo(_lat(640), 1e-12),
          reason: 'har doim OXIRGI manzil');
      expect(c.lats, [_lat(100), _lat(200), _lat(300)]);

      // Bloklovchi xabar yo'q; do'stona xabar bor.
      expect(find.byKey(const ValueKey('ev_trip_over_limit_message')),
          findsNothing);
      expect(find.byKey(_notice), findsOneWidget);
      expect(
          find.text(_tr('ev_trip_nav_sent_first', {'n': '3'})), findsOneWidget);
      expect(find.text(
              "Google Maps'ga dastlabki 3 ta to'xtash yuborildi. "
              'Qolganlari keyin taklif qilinadi'),
          findsOneWidget);

      // Chip: qolgan 2 ta; katta karta hali yo'q.
      expect(find.byKey(_chip), findsOneWidget);
      expect(_chipText(tester), "Keyingi to'xtashlar: 2 ta");
      expect(find.byKey(_card), findsNothing);
    });

    testWidgets('chegaradan oshmasa: bitta chaqiruv, xabar ham, chip ham yo\'q',
        (tester) async {
      final h = await _pump(tester, alongs: const [100, 200, 300]);
      await _tapNavigate(tester);
      expect(h.calls, hasLength(1));
      expect(h.calls.single.lats, [_lat(100), _lat(200), _lat(300)]);
      expect(find.byKey(_notice), findsNothing);
      expect(find.byKey(_chip), findsNothing);
      expect(find.byKey(_card), findsNothing);
    });

    testWidgets('hech narsa tanlanmagan: faqat manzilga, chip yo\'q',
        (tester) async {
      final h = await _pump(tester, alongs: const []);
      await _tapNavigate(tester);
      expect(h.calls.single.stops, isEmpty);
      expect(find.byKey(_chip), findsNothing);
    });

    testWidgets('birinchi chaqiruv ochilmasa: do\'stona xabar, qolgan to\'xtash '
        'chipi paydo bo\'lmaydi', (tester) async {
      final h = await _pump(tester);
      h.result = false;
      await _tapNavigate(tester);
      expect(h.calls, hasLength(1));
      expect(find.text(_tr('maps_open_failed')), findsOneWidget);
      expect(find.byKey(_chip), findsNothing);
      expect(find.byKey(_notice), findsNothing);
    });

    testWidgets('qayta "Navigatsiya": bo\'laklash boshidan (hozirgi joydan '
        'oldindagilar bilan)', (tester) async {
      final h = await _pump(tester);
      await _tapNavigate(tester);
      expect(h.calls, hasLength(1));
      await _tapNavigate(tester);
      expect(h.calls, hasLength(2));
      expect(h.calls[1].lats, [_lat(100), _lat(200), _lat(300)]);
      expect(_chipText(tester), "Keyingi to'xtashlar: 2 ta");
    });

    testWidgets('mashina yo\'lda (250 km): boshlanish nuqtasi = GPS, ortda '
        'qolgan stansiyalar qo\'shilmaydi', (tester) async {
      final h = await _pump(tester);
      await _drive(tester, h, 250);
      await _tapNavigate(tester);
      final c = h.calls.single;
      expect(c.originLat, closeTo(_lat(250), 1e-9));
      expect(c.lats, [_lat(300), _lat(400), _lat(500)]);
      expect(c.destLat, closeTo(_lat(640), 1e-12));
      // 3 ta <= limit: davomi yo'q.
      expect(find.byKey(_chip), findsNothing);
    });
  });

  group('"Kelgusi to\'xtashlar" kartasi: oxirgi yuborilgandan o\'tgach', () {
    testWidgets('o\'tmaguncha faqat chip; +1.5 km dan keyin katta karta '
        '(chipning o\'rniga)', (tester) async {
      final h = await _pump(tester);
      await _tapNavigate(tester);

      await _drive(tester, h, 150);
      expect(find.byKey(_card), findsNothing);
      expect(find.byKey(_chip), findsOneWidget);

      await _drive(tester, h, 300); // oxirgi yuborilgan to'xtashning o'zi
      expect(find.byKey(_card), findsNothing);
      await _drive(tester, h, 301.4);
      expect(find.byKey(_card), findsNothing, reason: '1.5 km dan kam');
      await _drive(tester, h, 301.6);
      expect(find.byKey(_card), findsOneWidget);
      expect(find.byKey(_chip), findsNothing);
      expect(tester.widget<Text>(find.byKey(const ValueKey('ev_trip_next_card_title'))).data,
          "Keyingi to'xtashlar: 2 ta");
      expect(find.byKey(_continue), findsOneWidget);
      expect(find.text('Davom etish'), findsOneWidget);
    });

    testWidgets('"Davom etish": hozirgi GPS dan, oxirgi manzilgacha, keyingi '
        'to\'xtashlar bilan; tugagach hammasi yo\'qoladi', (tester) async {
      final h = await _pump(tester);
      await _tapNavigate(tester);
      await _drive(tester, h, 301.6);
      await tester.tap(find.byKey(_continue));
      await tester.pumpAndSettle();

      expect(h.calls, hasLength(2));
      final c = h.calls[1];
      expect(c.originLat, closeTo(_lat(301.6), 1e-9), reason: 'hozirgi GPS');
      expect(c.destLat, closeTo(_lat(640), 1e-12));
      expect(c.lats, [_lat(400), _lat(500)]);
      expect(find.text(_tr('ev_trip_nav_sent_last', {'n': '2'})),
          findsOneWidget);
      expect(find.byKey(_card), findsNothing);
      expect(find.byKey(_chip), findsNothing);
    });

    testWidgets('limit 3, 7 ta: 3 + 3 + 1, har safar oxirgi o\'tgach',
        (tester) async {
      final h = await _pump(tester,
          alongs: const [60, 120, 180, 240, 300, 360, 420]);
      await _tapNavigate(tester);
      expect(h.calls.single.lats, [_lat(60), _lat(120), _lat(180)]);

      await _drive(tester, h, 182);
      await tester.tap(find.byKey(_continue));
      await tester.pumpAndSettle();
      expect(h.calls, hasLength(2));
      expect(h.calls[1].lats, [_lat(240), _lat(300), _lat(360)]);
      expect(find.text(_tr('ev_trip_nav_sent_next', {'n': '3'})),
          findsOneWidget);
      // Yangi bo'lakdan keyin karta yana chipga qaytadi, yangi chegara kutiladi.
      expect(find.byKey(_card), findsNothing);
      expect(_chipText(tester), "Keyingi to'xtashlar: 1 ta");

      await _drive(tester, h, 361);
      expect(find.byKey(_card), findsNothing);
      await _drive(tester, h, 362);
      expect(find.byKey(_card), findsOneWidget);
      await tester.tap(find.byKey(_continue));
      await tester.pumpAndSettle();
      expect(h.calls, hasLength(3));
      expect(h.calls[2].lats, [_lat(420)]);
      expect(h.calls[2].originLat, closeTo(_lat(362), 1e-9));
      expect(find.byKey(_chip), findsNothing);
      expect(find.byKey(_card), findsNothing);
    });

    testWidgets('limit 9, 11 ta: 9 + 2', (tester) async {
      final alongs = [for (var i = 1; i <= 11; i++) 50.0 * i];
      final h = await _pump(tester, alongs: alongs, maxWaypoints: 9);
      await _tapNavigate(tester);
      expect(h.calls.single.stops, hasLength(9));
      expect(h.calls.single.lats.last, _lat(450));
      expect(_chipText(tester), "Keyingi to'xtashlar: 2 ta");

      await _drive(tester, h, 452);
      await tester.tap(find.byKey(_continue));
      await tester.pumpAndSettle();
      expect(h.calls[1].lats, [_lat(500), _lat(550)]);
      expect(find.byKey(_chip), findsNothing);
    });

    testWidgets('GPS yo\'q: faqat chip (karta o\'zi chiqmaydi); chip bosilsa '
        'karta, "Davom etish" dastlabki nuqtadan', (tester) async {
      final h = await _pump(tester, gps: false);
      await _tapNavigate(tester);
      expect(find.byKey(_chip), findsOneWidget);
      expect(find.byKey(_card), findsNothing);

      await tester.tap(find.byKey(_chip));
      await tester.pumpAndSettle();
      expect(find.byKey(_card), findsOneWidget);
      expect(find.byKey(_chip), findsNothing);

      await tester.tap(find.byKey(_continue));
      await tester.pumpAndSettle();
      expect(h.calls, hasLength(2));
      expect(h.calls[1].originLat, closeTo(_lat(0), 1e-12),
          reason: 'GPS yo\'q: asl boshlanish nuqtasi');
      expect(h.calls[1].lats, [_lat(400), _lat(500)]);
    });

    testWidgets('chip qo\'lda bosilsa mashina o\'tmagan bo\'lsa ham karta '
        'ochiladi; yopilsa chipga qaytadi va o\'zi qayta chiqmaydi',
        (tester) async {
      final h = await _pump(tester);
      await _tapNavigate(tester);
      await _drive(tester, h, 100);
      await tester.tap(find.byKey(_chip));
      await tester.pumpAndSettle();
      expect(find.byKey(_card), findsOneWidget);

      await tester.tap(find.byKey(_close));
      await tester.pumpAndSettle();
      expect(find.byKey(_card), findsNothing);
      expect(find.byKey(_chip), findsOneWidget);

      // Haydovchi yopgan: mashina o'tsa ham o'zi chiqmaydi, chip qoladi.
      await _drive(tester, h, 305);
      expect(find.byKey(_card), findsNothing);
      expect(find.byKey(_chip), findsOneWidget);
      // Lekin yana bossa - ochiladi.
      await tester.tap(find.byKey(_chip));
      await tester.pumpAndSettle();
      expect(find.byKey(_card), findsOneWidget);
    });

    testWidgets('ilova fonda bo\'lganda yurildi: qaytganda karta shu yerda',
        (tester) async {
      final h = await _pump(tester);
      await _tapNavigate(tester);
      await _drive(tester, h, 150);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      // Fonda GPS oqimi yopiq: bu nuqta ekranga yetib bormaydi...
      final far = EvCarFix(lat: _lat(320), lng: 60.0);
      h.source.last = far;
      h.source.ctrl.add(far);
      await tester.pump();
      expect(find.byKey(_card), findsNothing);

      // ...ilova qaytganda oqim qayta ochiladi va oxirgi joy kelib tushadi.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_card), findsOneWidget);
    });

    testWidgets('haydovchi kutilayotgan stansiyani rejadan olib tashlasa '
        'soni kamayadi; hammasi tugasa chip ham yo\'qoladi', (tester) async {
      final h = await _pump(tester);
      await _tapNavigate(tester);
      expect(_chipText(tester), "Keyingi to'xtashlar: 2 ta");

      h.last!.onStationTap('s500');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(_chipText(tester), "Keyingi to'xtashlar: 1 ta");

      h.last!.onStationTap('s400');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_toggle));
      await tester.pumpAndSettle();
      expect(find.byKey(_chip), findsNothing);
    });

    testWidgets('"Davom etish" ochilmasa: xabar, holat saqlanadi (qayta '
        'urinish mumkin)', (tester) async {
      final h = await _pump(tester);
      await _tapNavigate(tester);
      await _drive(tester, h, 302);
      h.result = false;
      await tester.tap(find.byKey(_continue));
      await tester.pumpAndSettle();
      expect(find.text(_tr('maps_open_failed')), findsOneWidget);
      expect(find.byKey(_card), findsOneWidget);

      h.result = true;
      await tester.tap(find.byKey(_continue));
      await tester.pumpAndSettle();
      expect(h.calls, hasLength(3));
      expect(h.calls[2].lats, [_lat(400), _lat(500)]);
      expect(find.byKey(_card), findsNothing);
    });
  });

  group('katta shrift (1.3), haqiqiy matn va Inter shrifti', () {
    const locales = {'uz_Cyrl': evUzCyrl, 'uz_Latn': evUzLatn, 'ru': evRu};

    for (final entry in locales.entries) {
      testWidgets('${entry.key}: xabar, chip va karta sig\'adi, kesilmaydi, '
          'overflow yo\'q', (tester) async {
        final h = await _pump(tester,
            locale: entry.value, scale: 1.3, size: const Size(360, 640));
        await _tapNavigate(tester);

        // Xabar (SnackBar) haqiqiy matn bilan.
        final noticeText = evTr(entry.value, 'ev_trip_nav_sent_first')
            .replaceAll('{n}', '3');
        expect(find.text(noticeText), findsOneWidget, reason: entry.key);

        // Chip kesilmaydi.
        final title = evTr(entry.value, 'ev_trip_next_stops')
            .replaceAll('{n}', '2');
        expect(
            find.descendant(of: find.byKey(_chip), matching: find.text(title)),
            findsOneWidget,
            reason: entry.key);

        // Karta (o'tgandan keyin).
        await _drive(tester, h, 302);
        expect(find.byKey(_card), findsOneWidget);
        expect(
            find.descendant(of: find.byKey(_card), matching: find.text(title)),
            findsOneWidget);
        expect(
            find.descendant(
                of: find.byKey(_continue),
                matching: find.text(evTr(entry.value, 'ev_trip_continue'))),
            findsOneWidget);

        for (final el in find
            .descendant(of: find.byKey(_card), matching: find.byType(RichText))
            .evaluate()) {
          final ro = el.renderObject;
          if (ro is RenderParagraph) {
            expect(ro.didExceedMaxLines, isFalse,
                reason: '${entry.key}: ${ro.text.toPlainText()}');
          }
        }
        // Karta ekran ichida va "Navigatsiya" tugmasi bilan to'qnashmaydi.
        final card = tester.getRect(find.byKey(_card));
        final nav = tester.getRect(find.byKey(_btn));
        expect(card.left, greaterThanOrEqualTo(0));
        expect(card.right, lessThanOrEqualTo(360));
        expect(card.overlaps(nav), isFalse, reason: '$card vs $nav');
        expect(tester.takeException(), isNull, reason: entry.key);
      });
    }
  });
}
