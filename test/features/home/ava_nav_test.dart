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
      expect(find.byType(AvaLogoBadge), findsOneWidget);
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
      // Логотип сиқилиб йўқолмаган — тўлиқ ўлчамда қолган.
      expect(tester.getSize(find.byType(AvaLogoBadge)),
          const Size.square(AvaLogoBadge.diameter));
    });

    // Эга қарори 2026-10-08: эски логотип, қора думалоқ ичида, кичик.
    testWidgets('логотип — қора доира ичида эски AVA расми', (tester) async {
      ServiceConfigHolder.setForTest(districtLabel: 'Гурлан');
      await _pump(tester, AvaTopBar(onPickRegion: () {}));
      final box = tester.widget<Container>(find.descendant(
        of: find.byType(AvaLogoBadge),
        matching: find.byType(Container),
      ));
      final deco = box.decoration! as BoxDecoration;
      expect(deco.shape, BoxShape.circle);
      expect(deco.color, const Color(0xFF000000));
      final img = tester.widget<Image>(find.descendant(
        of: find.byType(AvaLogoBadge),
        matching: find.byType(Image),
      ));
      expect((img.image as AssetImage).assetName, AvaLogoBadge.asset);
      // Расм доирадан чиқмайди.
      expect(img.width, lessThan(AvaLogoBadge.diameter));
    });

    // Чегара: «ўлчови катта бўлиб кетмасин» — босиш майдони минимумидан
    // сал кичик ёки тенг; қатор баландлигини оширмайди.
    test('логотип ўлчами кичик: диаметр ≤ AvaTap.minSize', () {
      expect(AvaLogoBadge.diameter, lessThanOrEqualTo(AvaTap.minSize));
    });

    testWidgets('скрин-ридер учун «AVA» ёрлиғи бор', (tester) async {
      ServiceConfigHolder.setForTest();
      await _pump(tester, AvaTopBar(onPickRegion: () {}));
      expect(find.bySemanticsLabel('AVA'), findsOneWidget);
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

    // Аудит 2026-10-19: фаол бўлмаган ёрлиқ `ink3` (≈2.7:1) эди; белги
    // матни қизил устида тўқ (≈3.2:1) эди — иккови ҳам 4.5:1 дан паст.
    testWidgets('контраст: фаол бўлмаган ёрлиқ ink2, белги матни оқ (surface)',
        (tester) async {
      await _pump(
        tester,
        AvaBottomNav(
          current: AvaNavTab.home,
          onTap: (_) {},
          messagesBadge: 3,
        ),
      );
      final inactive = tester.widget<Text>(find.text('home_nav_cabinet'));
      expect(inactive.style!.color, AvaLight.ink2);
      final active = tester.widget<Text>(find.text('home_nav_home'));
      expect(active.style!.color, AvaLight.brand);
      final badge = tester.widget<Text>(find.text('3'));
      expect(badge.style!.color, AvaLight.surface);
    });

    testWidgets('семантика: белги сони ёрлиқ билан бирга, иккинчи марта эмас',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        AvaBottomNav(
          current: AvaNavTab.home,
          onTap: (_) {},
          messagesBadge: 3,
        ),
      );
      // Тестда локализация йўқ — калит ўзи чиқади; муҳими: ёрлиқ + сон-матн.
      expect(find.bySemanticsLabel('home_nav_messages, home_nav_unread'),
          findsOneWidget);
      // Яланғоч «3» ва такрорий ёрлиқ ўқилмайди.
      expect(find.bySemanticsLabel('3'), findsNothing);
      expect(find.bySemanticsLabel('home_nav_messages'), findsNothing);
      // Белгисиз таб — оддий ёрлиқ.
      expect(find.bySemanticsLabel('home_nav_cabinet'), findsOneWidget);
      handle.dispose();
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

    testWidgets('Scaffold ичида пастда қолади — бутун экранни эгалламайди',
        (tester) async {
      // 2026-09-25 қурилмада: «＋» тугмасидаги `Center` бўш чегараларда
      // максимал баландликни олиб, мену бутун саҳифани ёпиб қўйган эди.
      // Шунинг учун меню АЙНАН иловадагидек — `bottomNavigationBar`
      // сифатида — жойлаштирилиб, баландлиги ўлчанади.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: const Center(child: Text('CONTENT')),
            bottomNavigationBar:
                AvaBottomNav(current: AvaNavTab.home, onTap: (_) {}),
          ),
        ),
      );

      final navHeight = tester.getSize(find.byType(AvaBottomNav)).height;
      final screenHeight = tester.getSize(find.byType(Scaffold)).height;
      expect(navHeight, lessThan(120));
      expect(navHeight, lessThan(screenHeight / 3));
      // Мену контентни ёпиб қўймаган.
      expect(find.text('CONTENT'), findsOneWidget);
      expect(
        tester.getCenter(find.text('CONTENT')).dy,
        lessThan(tester.getTopLeft(find.byType(AvaBottomNav)).dy),
      );
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
