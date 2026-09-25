import 'package:ava_gurlan/core/service_config_holder.dart';
import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/home/widgets/ava_bottom_nav.dart';
import 'package:ava_gurlan/features/home/widgets/ava_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  tearDown(ServiceConfigHolder.resetForTest);

  group('ServiceConfigHolder.geoLabel', () {
    test('туман + вилоят', () {
      ServiceConfigHolder.setForTest(
        districtLabel: 'Гурлан',
        regionLabel: 'Хоразм',
      );
      expect(ServiceConfigHolder.geoLabel, 'Гурлан, Хоразм');
    });

    test('фақат туман', () {
      ServiceConfigHolder.setForTest(districtLabel: 'Гурлан');
      expect(ServiceConfigHolder.geoLabel, 'Гурлан');
    });

    test('фақат вилоят', () {
      ServiceConfigHolder.setForTest(regionLabel: 'Хоразм');
      expect(ServiceConfigHolder.geoLabel, 'Хоразм');
    });

    test('иккаласи ҳам бўш — бўш сатр', () {
      ServiceConfigHolder.setForTest();
      expect(ServiceConfigHolder.geoLabel, '');
    });
  });

  group('AvaTopBar', () {
    testWidgets('ҳудуд танланмаган — «Ҳудудни танланг»', (tester) async {
      ServiceConfigHolder.setForTest();
      await _pump(tester, AvaTopBar(onPickRegion: () {}));
      expect(find.text('AVA'), findsOneWidget);
      // Локализациясиз калитнинг ўзи чиқади — муҳими, ҳудуд номи эмас.
      expect(find.text('home_region_pick'), findsOneWidget);
    });

    testWidgets('ҳудуд танланган — номи кўрсатилади', (tester) async {
      ServiceConfigHolder.setForTest(
        districtLabel: 'Гурлан',
        regionLabel: 'Хоразм',
      );
      await _pump(tester, AvaTopBar(onPickRegion: () {}));
      expect(find.text('Гурлан, Хоразм'), findsOneWidget);
      expect(find.text('home_region_pick'), findsNothing);
    });

    testWidgets('босилганда чақирилади', (tester) async {
      ServiceConfigHolder.setForTest(districtLabel: 'Гурлан');
      var taps = 0;
      await _pump(tester, AvaTopBar(onPickRegion: () => taps++));
      await tester.tap(find.text('Гурлан'));
      expect(taps, 1);
    });

    testWidgets('узун ҳудуд номи, 320px + 130% — тошмайди', (tester) async {
      ServiceConfigHolder.setForTest(
        districtLabel: 'Шайхонтоҳур тумани',
        regionLabel: 'Тошкент шаҳри',
      );
      await _pump(
        tester,
        AvaTopBar(onPickRegion: () {}),
        width: 320,
        scale: 1.3,
      );
      expect(tester.takeException(), isNull);
      // Логотип сиқилиб йўқолмаган.
      expect(find.text('AVA'), findsOneWidget);
    });
  });

  group('AvaBottomNav', () {
    testWidgets('бешта таб: Бош · AVAGram · ＋ · Хабарлар · Кабинет',
        (tester) async {
      await _pump(
        tester,
        AvaBottomNav(current: AvaNavTab.home, onTap: (_) {}),
      );
      expect(find.text('home_nav_home'), findsOneWidget);
      expect(find.text('home_nav_avagram'), findsOneWidget);
      expect(find.text('home_nav_messages'), findsOneWidget);
      expect(find.text('home_nav_cabinet'), findsOneWidget);
      // «＋» — ёрлиқсиз, фақат иконка.
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('«Буюртмалар» ва «Ҳамён» таблари йўқ', (tester) async {
      await _pump(
        tester,
        AvaBottomNav(current: AvaNavTab.home, onTap: (_) {}),
      );
      // Тавсиф: Буюртмалар Кабинет ичига ўтади, Ҳамён интерфейсда яширилади.
      expect(find.text('bottom_orders'), findsNothing);
      expect(find.text('bottom_wallet'), findsNothing);
    });

    testWidgets('ҳар таб ўз қийматини қайтаради', (tester) async {
      final tapped = <AvaNavTab>[];
      await _pump(
        tester,
        AvaBottomNav(current: AvaNavTab.home, onTap: tapped.add),
      );
      await tester.tap(find.text('home_nav_avagram'));
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.tap(find.text('home_nav_cabinet'));
      expect(tapped, [
        AvaNavTab.avagram,
        AvaNavTab.create,
        AvaNavTab.cabinet,
      ]);
    });

    testWidgets('белги 0 бўлса кўринмайди, бўлса чиқади', (tester) async {
      await _pump(
        tester,
        AvaBottomNav(current: AvaNavTab.home, onTap: (_) {}),
      );
      expect(find.text('3'), findsNothing);

      await _pump(
        tester,
        AvaBottomNav(
          current: AvaNavTab.home,
          onTap: (_) {},
          messagesBadge: 3,
        ),
      );
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('99 дан ошса «99+»', (tester) async {
      await _pump(
        tester,
        AvaBottomNav(
          current: AvaNavTab.home,
          onTap: (_) {},
          messagesBadge: 250,
        ),
      );
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('320px + 130% шрифтда тошмайди', (tester) async {
      await _pump(
        tester,
        AvaBottomNav(
          current: AvaNavTab.home,
          onTap: (_) {},
          messagesBadge: 12,
        ),
        width: 320,
        scale: 1.3,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
