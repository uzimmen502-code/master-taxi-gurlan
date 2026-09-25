import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/home/controllers/active_orders_controller.dart';
import 'package:ava_gurlan/features/home/widgets/active_order_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

HomeActiveOrder _order({
  ActiveOrderStage stage = ActiveOrderStage.onWay,
  ActiveOrderKind kind = ActiveOrderKind.localTaxi,
  String title = 'Гурлан → Урганч',
  DateTime? at,
}) =>
    HomeActiveOrder(
      id: 'o1',
      kind: kind,
      stage: stage,
      title: title,
      sortAt: at ?? DateTime(2026, 1, 1, 12),
    );

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 360,
  double scale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Center(child: SizedBox(width: width, child: child)),
        ),
      ),
    ),
  );
}

void main() {
  group('ActiveOrderCard — кўриниш', () {
    testWidgets('буюртма йўқ — карточка бутунлай йўқолади', (tester) async {
      await _pump(
        tester,
        ActiveOrderCard(order: null, extraCount: 0, onTap: () {}),
      );
      // Тавсиф талаби: жой ҳам эгалланмайди. Кенглигини ота-виджет
      // мажбурлайди, шунинг учун муҳими — БАЛАНДЛИК нол.
      expect(tester.getSize(find.byType(ActiveOrderCard)).height, 0);
    });

    testWidgets('учта ҳолат — ўз матни билан', (tester) async {
      for (final (stage, key) in <(ActiveOrderStage, String)>[
        (ActiveOrderStage.searching, 'home_active_order_searching'),
        (ActiveOrderStage.onWay, 'home_active_order_on_way'),
        (ActiveOrderStage.arrived, 'home_active_order_arrived'),
      ]) {
        await _pump(
          tester,
          ActiveOrderCard(
            order: _order(stage: stage),
            extraCount: 0,
            onTap: () {},
          ),
        );
        expect(find.text(key), findsOneWidget, reason: '$stage');
      }
    });

    testWidgets('йўналиш кўрсатилади', (tester) async {
      await _pump(
        tester,
        ActiveOrderCard(order: _order(), extraCount: 0, onTap: () {}),
      );
      expect(find.text('Гурлан → Урганч'), findsOneWidget);
    });

    testWidgets('«+1» фақат бошқа буюртма бўлганда', (tester) async {
      await _pump(
        tester,
        ActiveOrderCard(order: _order(), extraCount: 0, onTap: () {}),
      );
      expect(find.text('+1'), findsNothing);

      await _pump(
        tester,
        ActiveOrderCard(order: _order(), extraCount: 1, onTap: () {}),
      );
      expect(find.text('+1'), findsOneWidget);

      await _pump(
        tester,
        ActiveOrderCard(order: _order(), extraCount: 3, onTap: () {}),
      );
      expect(find.text('+3'), findsOneWidget);
    });

    testWidgets('босилганда кузатишга ўтади', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        ActiveOrderCard(
          order: _order(),
          extraCount: 0,
          onTap: () => taps++,
        ),
      );
      await tester.tap(find.byType(ActiveOrderCard));
      expect(taps, 1);
    });

    testWidgets('узун йўналиш, 320px + 130% — тошмайди', (tester) async {
      await _pump(
        tester,
        ActiveOrderCard(
          order: _order(
            title: 'Шайхонтоҳур тумани → Урганч шаҳри автовокзали',
          ),
          extraCount: 2,
          onTap: () {},
        ),
        width: 320,
        scale: 1.3,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('HomeActiveOrder — саралаш устунлиги', () {
    test('кетаётган сафар режалаштирилган брондан устун', () {
      final trip = _order(kind: ActiveOrderKind.localTaxi);
      final booking = _order(kind: ActiveOrderKind.intercity);
      expect(trip.priority, lessThan(booking.priority));
    });

    test('маршрут ҳам «ҳозир» тоифасида', () {
      expect(_order(kind: ActiveOrderKind.marshrut).priority, 0);
    });
  });
}
