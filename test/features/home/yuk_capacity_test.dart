import 'package:ava_gurlan/features/home/widgets/home_yuk_local_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `formatYukCapacity` контекст талаб қилади (бирлик номи таржима
/// қилинади) — локализациясиз калитнинг ўзи қайтади, шу етарли.
Future<String> _fmt(WidgetTester tester, double kg) async {
  late String out;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          out = formatYukCapacity(context, kg);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return out;
}

void main() {
  group('formatYukCapacity', () {
    testWidgets('1000 дан кам — килограммда', (tester) async {
      expect(await _fmt(tester, 500), '500 yuk_unit_kg');
      expect(await _fmt(tester, 999), '999 yuk_unit_kg');
    });

    testWidgets('1000 ва ундан юқори — тоннада', (tester) async {
      expect(await _fmt(tester, 1000), '1 yuk_unit_ton');
      expect(await _fmt(tester, 3000), '3 yuk_unit_ton');
    });

    testWidgets('бутун бўлмаган тонна — вергул билан', (tester) async {
      expect(await _fmt(tester, 3500), '3,5 yuk_unit_ton');
      expect(await _fmt(tester, 1200), '1,2 yuk_unit_ton');
    });

    testWidgets('нол ва манфий — бўш сатр', (tester) async {
      expect(await _fmt(tester, 0), '');
      expect(await _fmt(tester, -5), '');
    });

    testWidgets('каср килограмм яхлитланади', (tester) async {
      expect(await _fmt(tester, 499.6), '500 yuk_unit_kg');
    });
  });
}
