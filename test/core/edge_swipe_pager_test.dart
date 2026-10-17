import 'package:ava_gurlan/core/widgets/edge_swipe_pager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Свайп ФАҚАТ контент чегарасида ишлайди (эга қарори, 2026-10-17):
/// охирида юқорига — кейинги, тепада пастга — олдинги.
Widget _app({
  required int count,
  int initial = 0,
  double contentHeight = 200,
  ValueChanged<int>? onChanged,
}) =>
    MaterialApp(
      home: Scaffold(
        body: EdgeSwipePager(
          itemCount: count,
          initialIndex: initial,
          onPageChanged: onChanged,
          itemBuilder: (_, i) => ListView(
            physics: kEdgeSwipePhysics,
            children: [
              SizedBox(height: contentHeight, child: Text('page $i')),
            ],
          ),
        ),
      ),
    );

/// Бармоқ билан секин судраш (fling ЭМАС): oxirida to'xtab, qo'yib yuboriladi.
Future<void> _dragSlow(WidgetTester t, Offset by) async {
  final g = await t.startGesture(t.getCenter(find.byType(Scaffold)));
  const steps = 10;
  for (var i = 0; i < steps; i++) {
    await g.moveBy(by / steps.toDouble());
    await t.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await t.pumpAndSettle();
}

void main() {
  testWidgets('қисқа контент: юқорига суриш → кейинги саҳифа', (t) async {
    final seen = <int>[];
    await t.pumpWidget(_app(count: 3, onChanged: seen.add));
    expect(find.text('page 0'), findsOneWidget);
    await _dragSlow(t, const Offset(0, -160));
    expect(find.text('page 1'), findsOneWidget);
    expect(seen, [1]);
  });

  testWidgets('қисқа контент: пастга суриш → олдинги саҳифа', (t) async {
    await t.pumpWidget(_app(count: 3, initial: 1));
    await _dragSlow(t, const Offset(0, 160));
    expect(find.text('page 0'), findsOneWidget);
  });

  testWidgets('чегара: биринчи саҳифада пастга суриш — ҳеч нарса', (t) async {
    await t.pumpWidget(_app(count: 3));
    await _dragSlow(t, const Offset(0, 200));
    expect(find.text('page 0'), findsOneWidget);
  });

  testWidgets('чегара: охирги саҳифада юқорига суриш — ҳеч нарса', (t) async {
    await t.pumpWidget(_app(count: 3, initial: 2));
    await _dragSlow(t, const Offset(0, -200));
    expect(find.text('page 2'), findsOneWidget);
  });

  testWidgets('кичик суриш (чегара остида) ўтказмайди', (t) async {
    await t.pumpWidget(_app(count: 3));
    await _dragSlow(t, const Offset(0, -50)); // slop + 56 дан кам
    expect(find.text('page 0'), findsOneWidget);
  });

  testWidgets('узун контент: охирига етмай суриш — ўтмайди, скролл қилади',
      (t) async {
    await t.pumpWidget(_app(count: 3, contentHeight: 2000));
    await _dragSlow(t, const Offset(0, -300));
    expect(find.text('page 0'), findsOneWidget); // ҳали шу саҳифа
    expect(find.text('page 1'), findsNothing);
  });

  testWidgets(
      'узун контент: охиригача судраб ДАВОМ эттириш (ишора чегарада бошланмаган) — ўтмайди',
      (t) async {
    await t.pumpWidget(_app(count: 3, contentHeight: 2000));
    // Бир ишорада охиригача ва ундан ҳам узоқроқ судраш.
    await _dragSlow(t, const Offset(0, -2600));
    expect(find.text('page 1'), findsNothing);
  });

  testWidgets('узун контент: охирига етиб, ЯНГИ ишора билан юқорига — кейинги',
      (t) async {
    await t.pumpWidget(_app(count: 3, contentHeight: 1000));
    await _dragSlow(t, const Offset(0, -1200)); // охирига (ўтмайди)
    expect(find.text('page 1'), findsNothing);
    await _dragSlow(t, const Offset(0, -160)); // янги ишора чегарада
    expect(find.text('page 1'), findsOneWidget);
  });

  testWidgets('тез отиш (fling) охирга урилса — ўтмайди', (t) async {
    await t.pumpWidget(_app(count: 3, contentHeight: 900));
    await t.fling(find.byType(Scaffold), const Offset(0, -600), 4000);
    await t.pumpAndSettle();
    expect(find.text('page 1'), findsNothing);
  });

  testWidgets('горизонтал ишора вертикал ўтишни ишга туширмайди', (t) async {
    await t.pumpWidget(_app(count: 3));
    await t.drag(find.byType(Scaffold), const Offset(-300, 0));
    await t.pumpAndSettle();
    expect(find.text('page 0'), findsOneWidget);
  });
}
