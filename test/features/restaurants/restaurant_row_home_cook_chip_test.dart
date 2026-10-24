import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/widgets/restaurant_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// UI/UX аудит (2026-10-24): қатордаги чиплар `take(3)` билан кесилади, «Уй
/// ошпази» чипи рўйхат охирида эди — етказиш + олиб кетиш + мин. сумма бор
/// бўлса кўринмай қоларди.
Future<void> _pump(WidgetTester t, Restaurant r) => t.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: RestaurantRow(restaurant: r)),
    ));

const _busy = RestaurantDelivery(mode: 'ava_courier', pickup: true);

void main() {
  testWidgets('уй ошпази: етказиш + олиб кетиш + мин. сумма бўлса ҳам чип кўринади', (t) async {
    await _pump(
      t,
      const Restaurant(id: 'h', name: 'Oshxona', legalType: 'individual', delivery: _busy, minOrderAmount: 20000),
    );
    expect(find.text('restaurants_chip_home_cook'), findsOneWidget);
    // Кесиш чегараси ўзгармади (3 та чип): кесилгани — энг кам муҳими, мин. сумма.
    expect(find.text('restaurants_chip_delivery'), findsOneWidget);
    expect(find.text('restaurants_chip_pickup'), findsOneWidget);
    expect(find.text('restaurants_chip_min'), findsNothing);
  });

  testWidgets('кафеда «Уй ошпази» чипи йўқ ва аввалги чиплар жойида', (t) async {
    await _pump(
      t,
      const Restaurant(id: 'c', name: 'Kafe', legalType: 'yatt', delivery: _busy, minOrderAmount: 20000),
    );
    expect(find.text('restaurants_chip_home_cook'), findsNothing);
    expect(find.text('restaurants_chip_delivery'), findsOneWidget);
    expect(find.text('restaurants_chip_pickup'), findsOneWidget);
    expect(find.text('restaurants_chip_min'), findsOneWidget);
  });
}
