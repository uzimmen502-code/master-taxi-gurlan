import 'dart:async';

import 'package:ava_gurlan/features/ev_charging/controllers/ev_car_tracker.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_trip_planner.dart';
import 'package:ava_gurlan/features/ev_charging/models/ev_trip_plan.dart';
import 'package:ava_gurlan/features/ev_charging/screens/ev_trip_map_screen.dart';
import 'package:ava_gurlan/features/ev_charging/widgets/ev_map_top_overlay.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ev_test_support.dart';

// "Yo'l rejimi" (ekran darajasida): tezlikdan yoqiladi, og'ir reja varaqasi
// yashirinadi, kartochkada ikkita katta tugma, "Band" xabari (soxta
// repozitoriy), "Almashtirish", "Yetib keldingiz", GPS yo'q. Matnlar haqiqiy,
// shrift Inter, katta shrift 1.3, GPS - soxta oqim, soat - soxta.

const double _kmPerDegLat = 111.1949;
double _lat(double km) => 41.0 + km / _kmPerDegLat;

const _car = EvCarSpec(
  usableBatteryKwh: 60,
  consumptionKwhPer100Km: 20,
  connectors: ['CCS2'],
);

EvCorridorStation _cs(String id, double along, {String? occupancy}) =>
    EvCorridorStation(
      station: EvChargingStation(
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
        occupancy: occupancy,
        occupancyAt: occupancy == null ? null : DateTime.now(),
      ),
      alongKm: along,
      offRouteKm: 0.5,
    );

List<EvCorridorStation> _corridor({String? bOccupancy}) => [
      _cs('a', 100),
      _cs('a2', 230),
      _cs('d', 250),
      _cs('b', 265, occupancy: bOccupancy),
      _cs('e', 300),
      _cs('c', 430),
    ];

EvTripPlan _plan(List<EvCorridorStation> corridor) => EvTripPlanner.plan(
      corridorStations: corridor,
      totalKm: 600,
      car: _car,
      startSocPercent: 100,
    );

List<EvRoutePoint> _route() =>
    [for (var i = 0; i <= 100; i += 10) EvRoutePoint(_lat(i * 6.0), 60.0)];

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

class _H {
  EvTripMapRenderData? last;
  final source = _Source();
  DateTime now = DateTime(2026, 10, 16, 12);
  final busyCalls = <String>[];
  Completer<void>? busyHold;
  bool busyThrows = false;
}

const _card = ValueKey('ev_drive_card');
const _title = ValueKey('ev_drive_title');
const _busy = ValueKey('ev_drive_busy_button');
const _alt = ValueKey('ev_drive_alt_button');
const _started = ValueKey('ev_drive_charging_started');
const _header = ValueKey('ev_trip_sheet_header');
const _chip = ValueKey('ev_trip_drive_chip');
const _navBtn = ValueKey('ev_trip_navigate_button');

Future<_H> _pump(
  WidgetTester tester, {
  Locale locale = evUzLatn,
  double scale = 1.3,
  bool gps = true,
  String? bOccupancy,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final corridor = _corridor(bOccupancy: bOccupancy);
  final h = _H();
  h.source.unavailable = !gps;
  await tester.pumpWidget(evL10nApp(
    locale: locale,
    textScale: scale,
    home: EvTripMapScreen(
      plan: _plan(corridor),
      route: _route(),
      corridorStations: corridor,
      originLat: _lat(0),
      originLng: 60.0,
      destinationLat: _lat(600),
      destinationLng: 60.0,
      onOpenNavigator: () {},
      locationSource: h.source,
      car: _car,
      driveClock: () => h.now,
      reportBusy: (id) async {
        h.busyCalls.add(id);
        if (h.busyThrows) throw StateError('offline');
        if (h.busyHold != null) await h.busyHold!.future;
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

/// Mashina yo'lning [km] joyida, [kmh] tezlikda.
Future<void> _fix(WidgetTester tester, _H h, double km, double kmh) async {
  final fix = EvCarFix(lat: _lat(km), lng: 60.0, speedMps: kmh / 3.6);
  h.source.last = fix;
  h.source.ctrl.add(fix);
  await tester.pump();
  await tester.pump();
}

/// Yo'l rejimini yoqadi: 3 ta ketma-ket tez nuqta.
Future<void> _startDriving(WidgetTester tester, _H h, {double km = 50}) async {
  for (var i = 0; i < 3; i++) {
    await _fix(tester, h, km + i, 60);
  }
  await tester.pumpAndSettle();
}

String _tr(String key, [Locale locale = evUzLatn]) => evTr(locale, key);

String _titleText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_title)).data!;

void main() {
  setUpAll(loadInterFont);

  group('yoqilishi va og\'ir varaqaning yashirinishi', () {
    testWidgets('to\'xtab turganda: reja varaqasi bor, yo\'l kartochkasi yo\'q',
        (tester) async {
      final h = await _pump(tester);
      await _fix(tester, h, 50, 0);
      expect(find.byKey(_card), findsNothing);
      expect(find.byKey(_header), findsOneWidget);
    });

    testWidgets('harakat: 3 ta tez nuqtadan keyin kartochka chiqadi, varaqa yashirin',
        (tester) async {
      final h = await _pump(tester);
      await _fix(tester, h, 50, 60);
      await _fix(tester, h, 51, 60);
      await tester.pumpAndSettle();
      expect(find.byKey(_card), findsNothing, reason: '2 ta nuqta yetmaydi');
      await _fix(tester, h, 52, 60);
      await tester.pumpAndSettle();

      expect(find.byKey(_card), findsOneWidget);
      expect(find.byKey(_header), findsNothing,
          reason: 'og\'ir reja varaqasi yo\'l rejimida yashirin');
      expect(tester.takeException(), isNull);
    });

    testWidgets('kartochka: masofa, kelishdagi zaryad (reja qiymati), nom, band belgisi',
        (tester) async {
      final h = await _pump(tester, bOccupancy: 'free');
      await _startDriving(tester, h);

      final plan = _plan(_corridor(bOccupancy: 'free'));
      final b = plan.stops.first;
      expect(b.station.id, 'b');
      final title = _titleText(tester);
      expect(title, startsWith("Keyingi zaryadlash: 21"));
      expect(title, endsWith('km'));
      expect(find.text('Kelishda ~${b.arriveSocPercent}%'), findsOneWidget);
      expect(find.byKey(const ValueKey('ev_drive_station_name')), findsOneWidget);
      expect(find.text('ST-b'), findsOneWidget);
      expect(find.byKey(const ValueKey('ev_occupancy_free')), findsOneWidget,
          reason: 'yangi "Bo\'sh" belgisi ko\'rinadi');
    });

    testWidgets('to\'xtagach (3 ta sekin nuqta) kartochka yo\'qoladi, varaqa qaytadi',
        (tester) async {
      final h = await _pump(tester);
      await _startDriving(tester, h);
      expect(find.byKey(_card), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await _fix(tester, h, 53, 0);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(_card), findsNothing);
      expect(find.byKey(_header), findsOneWidget);
    });

    testWidgets('yangi nuqta kelmasa 20 soniyadan keyin o\'chadi (davriy tekshiruv)',
        (tester) async {
      final h = await _pump(tester);
      await _startDriving(tester, h);
      expect(find.byKey(_card), findsOneWidget);

      h.now = h.now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byKey(_card), findsNothing);
      expect(find.byKey(_header), findsOneWidget);
    });

    testWidgets('yo\'l rejimi boshlanganda ochiq varaqa yig\'iladi, to\'xtagach '
        'yig\'iq holatda qaytadi', (tester) async {
      final h = await _pump(tester);
      await tester.tap(find.byKey(_header)); // varaqani ochamiz
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ev_stop_replace_1')), findsOneWidget);

      await _fix(tester, h, 50, 0); // GPS bor
      await _startDriving(tester, h);
      expect(find.byKey(_header), findsNothing);
      for (var i = 0; i < 3; i++) {
        await _fix(tester, h, 53, 0);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(_header), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const ValueKey('ev_stop_replace_1'))).dy,
          greaterThanOrEqualTo(800),
          reason: 'varaqa yig\'iq qaytdi (kartochkalar ekrandan pastda)');
    });

    testWidgets('GPS yo\'q: yo\'l rejimi ham, chip ham ko\'rsatilmaydi',
        (tester) async {
      await _pump(tester, gps: false);
      expect(find.byKey(_chip), findsNothing);
      expect(find.byKey(_card), findsNothing);
      expect(find.byKey(_header), findsOneWidget);
    });

    testWidgets('qo\'lda chip: yoqadi va o\'chiradi (tezlik bo\'lmasa ham)',
        (tester) async {
      final h = await _pump(tester);
      expect(find.byKey(_chip), findsNothing, reason: 'GPS nuqtasi hali yo\'q');
      await _fix(tester, h, 50, 0);
      expect(find.byKey(_chip), findsOneWidget);
      expect(find.byKey(_card), findsNothing);

      await tester.tap(find.byKey(_chip));
      await tester.pumpAndSettle();
      expect(find.byKey(_card), findsOneWidget);
      expect(find.byKey(_header), findsNothing);

      await tester.tap(find.byKey(_chip));
      await tester.pumpAndSettle();
      expect(find.byKey(_card), findsNothing);
      expect(find.byKey(_header), findsOneWidget);
    });
  });

  group('kartochka tugmalari', () {
    testWidgets('aynan ikkita katta tugma (>= 56 dp), matn kiritish yo\'q, '
        '1.3 shriftda sig\'adi', (tester) async {
      final h = await _pump(tester);
      await _startDriving(tester, h);

      final busy = find.byKey(_busy);
      final alt = find.byKey(_alt);
      expect(busy, findsOneWidget);
      expect(alt, findsOneWidget);
      expect(tester.getSize(busy).height, greaterThanOrEqualTo(56));
      expect(tester.getSize(alt).height, greaterThanOrEqualTo(56));

      // Kartochkadagi katta tugmalar: faqat shu ikkitasi (Elevated/Outlined).
      final bigButtons = find.descendant(
          of: find.byKey(_card),
          matching: find.byWidgetPredicate((w) =>
              w is ElevatedButton || w is OutlinedButton || w is FilledButton));
      expect(bigButtons, findsNWidgets(2));

      // Matn kiritish maydoni yo'q.
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(EditableText), findsNothing);

      // Ekran ichida.
      for (final f in [busy, alt, find.byKey(_card)]) {
        final r = tester.getRect(f);
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(400));
        expect(r.bottom, lessThanOrEqualTo(800));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('katta "Navigatsiya" tugmasi, orqaga tugmasi va qayta markazlash '
        'o\'z joyida (karta tugma ustida)', (tester) async {
      final h = await _pump(tester);
      await _startDriving(tester, h);
      final nav = tester.getRect(find.byKey(_navBtn));
      final card = tester.getRect(find.byKey(_card));
      expect(nav.height, greaterThanOrEqualTo(56));
      expect(card.bottom, lessThanOrEqualTo(nav.top + 0.5),
          reason: 'karta tugmani yopmaydi');
      expect(nav.bottom, lessThanOrEqualTo(800));
      expect(find.byType(EvMapBackButton), findsOneWidget);
    });

    testWidgets('"Band": repozitoriy bir marta chaqiriladi, minnatdorchilik xabari',
        (tester) async {
      final h = await _pump(tester);
      await _startDriving(tester, h);
      await tester.tap(find.byKey(_busy));
      await tester.pumpAndSettle();
      expect(h.busyCalls, ['b']);
      expect(find.text(_tr('ev_occupancy_saved')), findsOneWidget);
    });

    testWidgets('"Band" yuborilayotganda qayta bosilmaydi (bitta chaqiruv)',
        (tester) async {
      final h = await _pump(tester);
      h.busyHold = Completer<void>();
      await _startDriving(tester, h);

      await tester.tap(find.byKey(_busy));
      await tester.pump();
      await tester.tap(find.byKey(_busy), warnIfMissed: false);
      await tester.pump();
      expect(h.busyCalls, ['b'], reason: 'ikkinchi bosish e\'tiborga olinmaydi');

      h.busyHold!.complete();
      await tester.pumpAndSettle();
      expect(find.text(_tr('ev_occupancy_saved')), findsOneWidget);

      // Tugatgach yana bosish mumkin.
      h.busyHold = null;
      await tester.tap(find.byKey(_busy));
      await tester.pumpAndSettle();
      expect(h.busyCalls, ['b', 'b']);
    });

    testWidgets('tarmoq yo\'q: do\'stona xabar, ilova qotmaydi, qayta urinish mumkin',
        (tester) async {
      final h = await _pump(tester);
      h.busyThrows = true;
      await _startDriving(tester, h);
      await tester.tap(find.byKey(_busy));
      await tester.pumpAndSettle();
      expect(find.text(_tr('ev_drive_busy_failed')), findsOneWidget);
      expect(find.textContaining('StateError'), findsNothing,
          reason: 'texnik matn ko\'rsatilmaydi');
      expect(tester.takeException(), isNull);

      h.busyThrows = false;
      await tester.tap(find.byKey(_busy));
      await tester.pumpAndSettle();
      expect(h.busyCalls, hasLength(2));
    });

    testWidgets('internet yo\'q (javob kelmaydi): 8 soniyadan keyin do\'stona xabar, '
        'tugma yana ishlaydi', (tester) async {
      final h = await _pump(tester);
      h.busyHold = Completer<void>(); // hech qachon tugamaydi
      await _startDriving(tester, h);
      await tester.tap(find.byKey(_busy));
      await tester.pump();
      await tester.pump(const Duration(seconds: 7));
      expect(find.text(_tr('ev_drive_busy_failed')), findsNothing,
          reason: '8 soniya o\'tmadi');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text(_tr('ev_drive_busy_failed')), findsOneWidget);

      h.busyHold = null;
      await tester.tap(find.byKey(_busy));
      await tester.pumpAndSettle();
      expect(h.busyCalls, hasLength(2));
    });

    testWidgets('"Almashtirish": ro\'yxat ochiladi, tanlansa karta yangi stansiyani '
        'ko\'rsatadi', (tester) async {
      final h = await _pump(tester);
      await _startDriving(tester, h);
      await tester.tap(find.byKey(_alt));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ev_alt_title')), findsOneWidget);

      final choose = find.byKey(const ValueKey('ev_alt_choose_a2'));
      await tester.ensureVisible(choose);
      await tester.pumpAndSettle();
      expect(tester.getSize(choose).height, greaterThanOrEqualTo(56),
          reason: 'yo\'lda tanlash tugmasi katta');
      await tester.tap(choose);
      await tester.pumpAndSettle();

      expect(find.text('ST-a2'), findsOneWidget);
      expect(find.byKey(const ValueKey('ev_trip_undo_chip')), findsOneWidget);
      expect(h.last!.plan.stops.first.station.id, 'a2');
    });
  });

  group('Yetib keldingiz', () {
    testWidgets('150 m ichida: "Yetib keldingiz" va "Zaryadlash boshlandi"; '
        'tasdiqlansa shu to\'xtash uchun karta yo\'qoladi', (tester) async {
      final h = await _pump(tester);
      await _startDriving(tester, h);
      await _fix(tester, h, 264.9, 60);
      await tester.pumpAndSettle();

      expect(_titleText(tester), _tr('ev_drive_arrived'));
      expect(find.byKey(_started), findsOneWidget);
      expect(tester.getSize(find.byKey(_started)).height,
          greaterThanOrEqualTo(56));
      expect(find.text('ST-b'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(_started));
      await tester.pumpAndSettle();
      // Mashina hali harakatda - keyingi to'xtash (c) uchun karta.
      expect(find.byKey(_started), findsNothing);
      expect(find.text('ST-b'), findsNothing);
      expect(find.text('ST-c'), findsOneWidget);
      expect(_titleText(tester), startsWith('Keyingi zaryadlash'));
    });

    testWidgets('to\'xtab turgan bo\'lsa ham, yetib kelganda holat ko\'rinib turadi; '
        'tasdiqlangach varaqa qaytadi', (tester) async {
      final h = await _pump(tester);
      await _fix(tester, h, 264.9, 0);
      await tester.pumpAndSettle();
      expect(find.byKey(_card), findsOneWidget);
      expect(_titleText(tester), _tr('ev_drive_arrived'));

      await tester.tap(find.byKey(_started));
      await tester.pumpAndSettle();
      expect(find.byKey(_card), findsNothing);
      expect(find.byKey(_header), findsOneWidget);
    });
  });

  group('uch tilda va katta shrift', () {
    for (final entry in {
      'uz_Cyrl': evUzCyrl,
      'uz_Latn': evUzLatn,
      'ru': evRu,
    }.entries) {
      testWidgets('${entry.key}: kartochka xatosiz, tugma matnlari o\'z tilida',
          (tester) async {
        final h = await _pump(tester, locale: entry.value);
        await _startDriving(tester, h);
        expect(tester.takeException(), isNull);
        expect(find.text(_tr('ev_mark_busy', entry.value)), findsOneWidget);
        expect(find.text(_tr('ev_alt_swap', entry.value)), findsOneWidget);
        expect(find.byKey(_chip), findsOneWidget);
        expect(find.text(_tr('ev_drive_mode', entry.value)), findsOneWidget);
        final r = tester.getRect(find.byKey(_chip));
        expect(r.right, lessThanOrEqualTo(400));
      });
    }
  });
}
