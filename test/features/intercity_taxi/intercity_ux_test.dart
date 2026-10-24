import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/features/intercity_taxi/intercity_tap_target.dart';
import 'package:ava_gurlan/features/intercity_taxi/passenger/widgets/intercity_ride_card.dart';
import 'package:ava_gurlan/models/intercity_ride.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Шаҳарлараро такси занжирининг UI/UX аудити (2026-10-24) регрессия тестлари:
/// эмодзи иконка ўрнида ишлатилмасин, 3 тилли калитлар тўлиқ бўлсин,
/// тегиш майдони 48 dp, ўчиқ тугма сабабини айтсин.
IntercityRide _ride({
  int seats = 3,
  int female = 0,
  int male = 0,
  double rating = 4.5,
}) =>
    IntercityRide(
      id: 'r1',
      driverName: 'Анвар',
      rating: rating,
      carModel: 'Cobalt',
      carNumber: '01A123BC',
      phoneNumber: '998901234567',
      price: 120000,
      availableSeats: seats,
      fromCity: 'Гурлан',
      toCity: 'Тошкент',
      district: '',
      departureTime: DateTime(2026, 10, 25, 8, 30),
      femaleCount: female,
      maleCount: male,
    );

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: 380, child: child),
        ),
      ),
    );

/// Эмодзи ва пиктограммалар диапазони (Misc Symbols/Dingbats/Emoticons/…).
final _emoji = RegExp(
  r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]',
  unicode: true,
);

void main() {
  group('IntercityRideCard', () {
    testWidgets('жинс ва ўрин — иконка, эмодзи эмас', (tester) async {
      await tester.pumpWidget(_host(IntercityRideCard(
        ride: _ride(female: 1, male: 2),
        onCall: () {},
        onBook: () {},
      )));

      final texts = tester.widgetList<Text>(find.byType(Text));
      for (final t in texts) {
        final s = t.data ?? t.textSpan?.toPlainText() ?? '';
        expect(_emoji.hasMatch(s), isFalse, reason: 'эмодзи топилди: "$s"');
      }
      expect(find.byIcon(Icons.female), findsOneWidget);
      expect(find.byIcon(Icons.male), findsOneWidget);
      expect(find.byIcon(Icons.airline_seat_recline_normal), findsOneWidget);
    });

    testWidgets('қўнғироқ ва «брон» тугмалари >= 48 dp', (tester) async {
      await tester.pumpWidget(_host(IntercityRideCard(
        ride: _ride(),
        onCall: () {},
        onBook: () {},
      )));

      final call = tester.getSize(find.byType(IntercityTapTarget));
      expect(call.width, greaterThanOrEqualTo(48));
      expect(call.height, greaterThanOrEqualTo(48));

      final book = tester.getSize(find.byType(ElevatedButton));
      expect(book.height, greaterThanOrEqualTo(48));
    });

    testWidgets('жой бор — «брон», босилади', (tester) async {
      var booked = 0;
      await tester.pumpWidget(_host(IntercityRideCard(
        ride: _ride(seats: 2),
        onCall: () {},
        onBook: () => booked++,
      )));

      expect(find.text('book_btn'), findsOneWidget);
      await tester.tap(find.byType(ElevatedButton));
      expect(booked, 1);
    });

    testWidgets('жой йўқ — тугма ўчиқ ва сабабини айтади', (tester) async {
      var booked = 0;
      await tester.pumpWidget(_host(IntercityRideCard(
        ride: _ride(seats: 0),
        onCall: () {},
        onBook: () => booked++,
      )));

      final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(btn.onPressed, isNull);
      expect(find.text('ic_ux_seats_full'), findsOneWidget);
      expect(find.text('book_btn'), findsNothing);
      await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
      expect(booked, 0);
    });

    testWidgets('қўнғироқ тугмаси screen reader учун номланган',
        (tester) async {
      final handle = tester.ensureSemantics();
      var called = 0;
      await tester.pumpWidget(_host(IntercityRideCard(
        ride: _ride(),
        onCall: () => called++,
        onBook: () {},
      )));

      final node = tester.getSemantics(find.byType(IntercityTapTarget));
      expect(node.label, 'call_lowercase');
      await tester.tap(find.byType(IntercityTapTarget));
      expect(called, 1);
      handle.dispose();
    });
  });

  group('IntercityTapTarget', () {
    testWidgets('кичик child ҳам 48x48 босиш майдони беради', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: IntercityTapTarget(
              label: 'x',
              onTap: () => taps++,
              child: const SizedBox(width: 20, height: 20),
            ),
          ),
        ),
      ));

      final size = tester.getSize(find.byType(IntercityTapTarget));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));

      // Кўринадиган 20x20 дан ташқарида, лекин 48x48 ичида босиш ишлайди.
      final center = tester.getCenter(find.byType(IntercityTapTarget));
      await tester.tapAt(center + const Offset(20, 20));
      expect(taps, 1);
    });

    testWidgets('onTap == null — ўчиқ, босилмайди', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: IntercityTapTarget(
              label: 'minus',
              onTap: null,
              child: Icon(Icons.remove),
            ),
          ),
        ),
      ));

      expect(
        tester.getSemantics(find.byType(IntercityTapTarget)),
        isSemantics(
          label: 'minus',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      handle.dispose();
    });
  });

  group('модул манбаси (регрессия қулфи)', () {
    final moduleFiles = Directory('lib/features/intercity_taxi')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    // Push/локал билдиришнома матни: иконка қўйиб бўлмайди, алоҳида қарор.
    const emojiAllowed = {
      'intercity_driver_alert_text.dart',
      'intercity_driver_panel_controller.dart',
    };

    String name(File f) => f.uri.pathSegments.last;
    String read(File f) => f.readAsStringSync();

    test('UI файлларида эмодзи йўқ', () {
      final offenders = <String>[];
      for (final f in moduleFiles) {
        if (emojiAllowed.contains(name(f))) continue;
        final lines = read(f).split('\n');
        for (var i = 0; i < lines.length; i++) {
          // Изоҳ ва ҳужжат қаторлари (// …) ҳисобга олинмайди.
          final code = lines[i].split('//').first;
          if (_emoji.hasMatch(code)) offenders.add('${name(f)}:${i + 1}');
        }
      }
      expect(offenders, isEmpty, reason: offenders.join(', '));
    });

    test('фойдаланувчига хом exception матни чиқмайди', () {
      final raw = RegExp(r"""Text\([^;]*\$e[\s'"\)\}]""");
      final assigned =
          RegExp(r'(_err|_previewError)\s*=\s*e\.toString\(\)');
      final offenders = <String>[];
      for (final f in moduleFiles) {
        final s = read(f);
        if (raw.hasMatch(s)) offenders.add(name(f));
        if (assigned.hasMatch(s)) offenders.add('${name(f)} (e.toString)');
        if (s.contains(r"'booking_error|$e'")) {
          offenders.add('${name(f)} (booking_error|\$e)');
        }
      }
      expect(offenders, isEmpty, reason: offenders.join(', '));
    });

    test('бронь репозиторийси фойдаланувчига хом/ҳардкод матн бермайди', () {
      final s =
          File('lib/repositories/intercity_bookings_repository.dart')
              .readAsStringSync();
      // Тури `unknown` бўлган истисноларнинг матни — 3 тилли калит.
      final msgs = RegExp(
        r"""IntercityBookingErrorKind\.unknown,\s*'([^']*)'""",
      ).allMatches(s).map((m) => m.group(1)!).toList();
      expect(msgs, isNotEmpty);
      for (final m in msgs) {
        expect(RegExp(r'^[a-z0-9_]+$').hasMatch(m), isTrue,
            reason: 'калит эмас: "$m"');
      }
    });

    test('Text ичида ҳардкод Кирилл/Latin сўз қолмаган', () {
      // `Text('Бекор')` / `Text(\n 'Давом etish')` кўринишлари.
      final hard = RegExp(
        r"""Text\(\s*'[^'$]*[Ѐ-ӿA-Za-z][^']*'""",
        unicode: true,
      );
      // Тил-мустақил белгилар: GPS, MFY — рухсат.
      const neutral = {'GPS'};
      final offenders = <String>[];
      for (final f in moduleFiles) {
        for (final m in hard.allMatches(read(f))) {
          final lit = RegExp(r"'([^']*)'").firstMatch(m.group(0)!)!.group(1)!;
          if (neutral.contains(lit.trim())) continue;
          offenders.add('${name(f)}: "$lit"');
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('; '));
    });

    test('модулда ишлатилган ҳар бир tr() калит 3 тилда бор', () {
      Map<String, dynamic> load(String lang) =>
          jsonDecode(File('assets/lang/$lang.json').readAsStringSync())
              as Map<String, dynamic>;
      final langs = {
        'uz_Cyrl': load('uz_Cyrl'),
        'uz_Latn': load('uz_Latn'),
        'ru': load('ru'),
      };
      final used = RegExp(r"""\btr\(\s*'([a-z0-9_]+)'\s*\)""");
      final missing = <String>{};
      for (final f in moduleFiles) {
        for (final m in used.allMatches(read(f))) {
          final key = m.group(1)!;
          for (final e in langs.entries) {
            if (!e.value.containsKey(key)) missing.add('${e.key}:$key');
          }
        }
      }
      expect(missing, isEmpty, reason: missing.join(', '));
    });

    test('ic_ux_* калитлари: 3 тилда бир хил {placeholder} тўплами', () {
      Map<String, dynamic> load(String lang) =>
          jsonDecode(File('assets/lang/$lang.json').readAsStringSync())
              as Map<String, dynamic>;
      final cyr = load('uz_Cyrl');
      final lat = load('uz_Latn');
      final ru = load('ru');
      final ph = RegExp(r'\{[a-z]+\}');
      final keys = cyr.keys.where((k) => k.startsWith('ic_ux_')).toList();
      expect(keys, isNotEmpty);
      for (final k in keys) {
        Set<String> p(Map<String, dynamic> m) =>
            ph.allMatches('${m[k]}').map((e) => e.group(0)!).toSet();
        expect(lat.containsKey(k) && ru.containsKey(k), isTrue, reason: k);
        expect(p(lat), p(cyr), reason: '$k (uz_Latn)');
        expect(p(ru), p(cyr), reason: '$k (ru)');
        expect('${cyr[k]}'.trim(), isNotEmpty, reason: k);
      }
    });
  });
}
