import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/ev_charging/widgets/ev_map_top_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// `AppLocalizations` делегати уланмаганда `context.tr(key)` калитнинг ўзини
// қайтаради — «Қаерга борамиз?» матни `ev_trip_entry` калити бўйича
// текширилади. `GoogleMap` платформа кўриниши керак эмас: композиция
// ([EvChargingMapLayout]) харитани ташқаридан олади, тестда оддий
// виджет берилади.

const _mapKey = ValueKey('fake_map');
const _barKey = ValueKey('ev_add_station_bar');

Widget _layout({
  bool loading = false,
  String? errorText,
  VoidCallback? onAdd,
  VoidCallback? onTrip,
}) {
  return EvChargingMapLayout(
    loading: loading,
    errorText: errorText,
    onAddStation: onAdd ?? () {},
    onTripPlanner: onTrip ?? () {},
    map: const SizedBox.expand(key: _mapKey),
  );
}

Future<void> _pumpLayout(WidgetTester tester, Widget layout) {
  return tester.pumpWidget(MaterialApp(home: layout));
}

void main() {
  testWidgets('AppBar ҳам, зарядлаш тури чиплари ҳам йўқ', (tester) async {
    await _pumpLayout(tester, _layout());

    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.text('⚡ Зарядлаш нуқталари'), findsNothing);
    expect(find.text('Ҳаммаси'), findsNothing);
    expect(find.text('AC+DC'), findsNothing);
    // Харита бутун экранни эгаллайди.
    expect(tester.getSize(find.byKey(_mapKey)),
        tester.view.physicalSize / tester.view.devicePixelRatio);
  });

  testWidgets('«Станция қўшиш» — тўлиқ шаффоф: фон, соя, контур йўқ',
      (tester) async {
    await _pumpLayout(tester, _layout());

    final bar = find.byKey(_barKey);
    expect(bar, findsOneWidget);

    final material = tester.widget<Material>(bar);
    expect(material.type, MaterialType.transparency);
    expect(material.elevation, 0);
    expect(material.color, isNull);
    expect(material.shape, isNull);
    expect(material.borderRadius, isNull);

    // Панель ичида фақат «пуллик» белгисининг фони бор (BoxDecoration);
    // панелнинг ўзида фон/контур/соя йўқ.
    final boxes = tester
        .widgetList<DecoratedBox>(
            find.descendant(of: bar, matching: find.byType(DecoratedBox)))
        .toList();
    expect(boxes, hasLength(1));
    final badge = boxes.single.decoration as BoxDecoration;
    expect(badge.border, isNull);
    expect(badge.boxShadow, isNull);
    expect(find.descendant(of: bar, matching: find.byType(PhysicalModel)),
        findsNothing);
    expect(find.descendant(of: bar, matching: find.byType(PhysicalShape)),
        findsNothing);

    // Матн, белги ва «пуллик» сақланган.
    expect(find.descendant(of: bar, matching: find.text('Станция қўшиш')),
        findsOneWidget);
    expect(find.descendant(of: bar, matching: find.text('пуллик')),
        findsOneWidget);
    expect(find.descendant(of: bar, matching: find.byIcon(Icons.add_rounded)),
        findsOneWidget);
  });

  testWidgets('матн тўқ ранг ва оқ ҳошия билан (ўқилувчанлик)', (tester) async {
    await _pumpLayout(tester, _layout());

    final text = tester.widget<Text>(find.text('Станция қўшиш'));
    expect(text.style!.color, AppColors.onPrimary);
    expect(text.style!.shadows, isNotEmpty);
    expect(text.style!.shadows!.every((s) => s.color == Colors.white), isTrue);

    final icon = tester.widget<Icon>(find.byIcon(Icons.add_rounded));
    expect(icon.color, AppColors.onPrimary);
    expect(icon.shadows, isNotEmpty);
  });

  testWidgets('«Станция қўшиш» орқага стрелка билан БИР қаторда, унинг ўнгида',
      (tester) async {
    await _pumpLayout(tester, _layout());

    final row = find.byKey(const ValueKey('ev_map_top_row'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.byType(EvMapBackButton)),
        findsOneWidget);
    expect(find.descendant(of: row, matching: find.byType(EvPaidAddStationBar)),
        findsOneWidget);

    final back = tester.getRect(find.byType(EvMapBackButton));
    final add = tester.getRect(find.byType(EvPaidAddStationBar));
    expect((back.center.dy - add.center.dy).abs(), lessThan(0.5));
    expect(add.left, greaterThanOrEqualTo(back.right));
    // Чап юқори бурчак.
    expect(back.left, lessThan(24));
  });

  testWidgets('«Қаерга борамиз?» қатор остида, босилади', (tester) async {
    var trips = 0;
    await _pumpLayout(tester, _layout(onTrip: () => trips++));

    final trip = find.text('ev_trip_entry');
    expect(trip, findsOneWidget);
    expect(find.byType(EvTripPlannerBar), findsOneWidget);

    final row = tester.getRect(find.byKey(const ValueKey('ev_map_top_row')));
    expect(tester.getRect(find.byType(EvTripPlannerBar)).top,
        greaterThanOrEqualTo(row.bottom));

    await tester.tap(trip);
    expect(trips, 1);
  });

  testWidgets('«Станция қўшиш» бутун панель бўйлаб босилади', (tester) async {
    var adds = 0;
    await _pumpLayout(tester, _layout(onAdd: () => adds++));

    final rect = tester.getRect(find.byType(EvPaidAddStationBar));
    // Матн/белгидан ташқари, панелнинг чап четига яқин нуқта.
    await tester.tapAt(Offset(rect.left + 4, rect.center.dy));
    expect(adds, 1);
    await tester.tap(find.text('Станция қўшиш'));
    expect(adds, 2);
  });

  testWidgets('орқага стрелка экрандан чиқади (pop)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => _layout()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(EvChargingMapLayout), findsOneWidget);

    await tester.tap(find.byType(EvMapBackButton));
    await tester.pumpAndSettle();
    expect(find.byType(EvChargingMapLayout), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets(
      'GPS йўқ — кичик огоҳлантириш «Қаерга борамиз?» тагида, харита ҳам бор',
      (tester) async {
    await _pumpLayout(tester, _layout(errorText: 'GPS ўчиқ'));

    expect(find.byType(MaterialBanner), findsNothing);
    expect(find.text('GPS ўчиқ'), findsOneWidget);
    expect(find.byKey(_mapKey), findsOneWidget);
    expect(
        tester.getRect(find.byType(EvMapGpsBanner)).top,
        greaterThanOrEqualTo(
            tester.getRect(find.byType(EvTripPlannerBar)).bottom));
  });

  testWidgets('юкланиш: спиннер, харита яширин, фақат орқага тугмаси',
      (tester) async {
    await _pumpLayout(tester, _layout(loading: true));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(_mapKey), findsNothing);
    expect(find.byType(EvMapBackButton), findsOneWidget);
    expect(find.byType(EvPaidAddStationBar), findsNothing);
    expect(find.byType(EvTripPlannerBar), findsNothing);
  });

  test('панель баландлиги: огоҳлантириш қўшилса каттароқ', () {
    expect(EvChargingMapLayout.overlayHeight(hasError: true),
        greaterThan(EvChargingMapLayout.overlayHeight(hasError: false)));
  });
}
