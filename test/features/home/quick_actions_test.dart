import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/home/widgets/ava_quick_actions.dart';
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
  group('AvaQuickActions', () {
    testWidgets('бўш рўйхат — жой эгалламайди', (tester) async {
      await _pump(tester, const AvaQuickActions(actions: []));
      expect(tester.getSize(find.byType(AvaQuickActions)).height, 0);
    });

    testWidgets('ҳар катак босилади', (tester) async {
      final tapped = <String>[];
      await _pump(
        tester,
        AvaQuickActions(
          actions: [
            AvaQuickAction(
              icon: Icons.apps_rounded,
              label: 'Барчаси',
              onTap: () => tapped.add('all'),
              highlighted: true,
            ),
            AvaQuickAction(
              icon: Icons.local_taxi_rounded,
              label: 'Такси',
              onTap: () => tapped.add('taxi'),
            ),
          ],
        ),
      );
      await tester.tap(find.text('Такси'));
      await tester.tap(find.text('Барчаси'));
      expect(tapped, ['taxi', 'all']);
    });

    testWidgets('ажратилган катак бренд фонида', (tester) async {
      await _pump(
        tester,
        AvaQuickActions(
          actions: [
            AvaQuickAction(
              icon: Icons.apps_rounded,
              label: 'Барчаси',
              onTap: () {},
              highlighted: true,
            ),
            AvaQuickAction(
              icon: Icons.local_taxi_rounded,
              label: 'Такси',
              onTap: () {},
            ),
          ],
        ),
      );
      final boxes = tester
          .widgetList<Container>(find.descendant(
            of: find.byType(AvaQuickActions),
            matching: find.byType(Container),
          ))
          .map((w) => w.decoration! as BoxDecoration)
          .toList();
      expect(boxes.first.color, AvaColors.light.brand);
      expect(boxes[1].color, AvaColors.light.surface);
    });

    testWidgets('олтита катак, 320px + 130% — тошмайди', (tester) async {
      // `defaultQuickActions` контекст талаб қилади — шунинг учун у
      // pump вақтида, Builder ичида қурилади.
      await _pump(
        tester,
        Builder(
          builder: (context) => AvaQuickActions(
            actions: defaultQuickActions(
              context,
              onOpenAll: () {},
              onTaxi: () {},
              onIntercity: () {},
              onMarket: () {},
              onAssistant: () {},
              onAvagram: () {},
            ),
          ),
        ),
        width: 320,
        scale: 1.3,
      );
      expect(tester.takeException(), isNull);
      // Олтита катак ҳам қурилди.
      expect(find.byType(InkWell), findsNWidgets(6));
    });

    testWidgets('узун ёрлиқ икки қаторга тушади, кесилмайди', (tester) async {
      await _pump(
        tester,
        AvaQuickActions(
          actions: [
            AvaQuickAction(
              icon: Icons.apps_rounded,
              label: 'Жуда узун хизмат номи',
              onTap: () {},
            ),
          ],
        ),
        width: 320,
        scale: 1.3,
      );
      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.text('Жуда узун хизмат номи'));
      expect(text.maxLines, 2);
    });
  });
}
