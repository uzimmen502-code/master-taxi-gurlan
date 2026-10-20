// «Хабарлар» → «Талаб» ички таби (радар): қисқа хулоса + тўлиқ экранга ўтиш.
//
// Локализация делегати атайин йўқ (қаранг service_ui_adapter_test.dart):
// `context.tr('key')` калитнинг ўзини қайтаради, шунинг учун тест матнга эмас,
// КАЛИТ ва САНОҚ (маълумот)га қарайди.
import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/demand_offer/presentation/radar/demand_radar_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app({
  String userId = '998901234567',
  int active = 0,
  int incoming = 0,
  VoidCallback? onOpen,
}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SizedBox(
        width: 360,
        height: 640,
        child: DemandRadarTab(
          userId: userId,
          activeDemands: active,
          newMatches: incoming,
          onOpen: onOpen ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  group('radarCountText', () {
    test('99 гача — сон, ундан кўп — 99+', () {
      expect(radarCountText(0), '0');
      expect(radarCountText(7), '7');
      expect(radarCountText(99), '99');
      expect(radarCountText(100), '99+');
      expect(radarCountText(5000), '99+');
    });

    test('манфий қиймат 0 бўлади (белги «-3» кўрсатмайди)', () {
      expect(radarCountText(-3), '0');
    });
  });

  group('DemandRadarTab', () {
    testWidgets('иккиси 0 — бўш ҳолат ва «Очиш» тугмаси', (tester) async {
      await tester.pumpWidget(_app());
      expect(find.text('radar_empty'), findsOneWidget);
      expect(find.text('radar_open'), findsOneWidget);
    });

    testWidgets('фаол сўровлар сони кўрсатилади', (tester) async {
      await tester.pumpWidget(_app(active: 2));
      expect(find.text('radar_my_active'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('radar_empty'), findsNothing);
      expect(find.text('radar_new_incoming'), findsNothing);
    });

    testWidgets('янги келган сўровлар сони кўрсатилади', (tester) async {
      await tester.pumpWidget(_app(incoming: 3));
      expect(find.text('radar_new_incoming'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('radar_empty'), findsNothing);
      expect(find.text('radar_my_active'), findsNothing);
    });

    testWidgets('иккиси ҳам бор — иккита карточка', (tester) async {
      await tester.pumpWidget(_app(active: 4, incoming: 1));
      expect(find.text('radar_new_incoming'), findsOneWidget);
      expect(find.text('radar_my_active'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('100 дан кўп — 99+', (tester) async {
      await tester.pumpWidget(_app(incoming: 150));
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('«Очиш» босилса onOpen чақирилади', (tester) async {
      var opened = 0;
      await tester.pumpWidget(_app(onOpen: () => opened++));
      await tester.tap(find.text('radar_open'));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('фойдаланувчи ID йўқ (кирилмаган) — бўш ҳолат, тугма йўқ', (tester) async {
      await tester.pumpWidget(_app(userId: '', active: 5, incoming: 5));
      expect(find.text('radar_empty'), findsOneWidget);
      expect(find.text('radar_open'), findsNothing);
      expect(find.text('5'), findsNothing);
    });

    testWidgets('сон ўзгарса таб янгиланади (ота-ҳаб қайта қурганда)', (tester) async {
      await tester.pumpWidget(_app(incoming: 1));
      expect(find.text('1'), findsOneWidget);
      await tester.pumpWidget(_app(incoming: 4));
      expect(find.text('4'), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('рус тилидаги узун матн ҳам сиғади (overflow йўқ)', (tester) async {
      // Тест калитни қайтаради; узун калит матнни ўзига ўхшатади.
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 640,
            child: DemandRadarTab(
              userId: '998901234567',
              activeDemands: 120,
              newMatches: 7,
              onOpen: () {},
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
