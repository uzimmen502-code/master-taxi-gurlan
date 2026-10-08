import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/home/widgets/services_spotlight_carousel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Регрессия: хизмат плиткасининг 3D ҳошияси юмалоқ бурчакли `Border`да
/// тўрт хил рангли томон билан чизиларди. Flutter буни чизмайди:
/// debug'да `A borderRadius can only be given on borders with uniform
/// colors` assert ташлайди, release'да бурчаклар тўғри бурчак бўлиб
/// чиқади. Энди ҳамма томон битта рангда, қалинлиги турлича.
void main() {
  Future<void> pumpTile(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 90,
            height: 110,
            child: ServiceSpotlightTile(
              item: ServiceSpotlightItem(
                moduleId: 'umuman_yoq',
                label: 'Такси',
                onTap: () {},
                icon: Icons.local_taxi,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  BoxDecoration faceDecoration(WidgetTester tester) {
    final boxes = tester
        .widgetList<AnimatedContainer>(find.descendant(
          of: find.byType(ServiceSpotlightTile),
          matching: find.byType(AnimatedContainer),
        ))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.border != null);
    return boxes.single;
  }

  testWidgets('оддий ҳолат чизилади — paint хатоси йўқ', (tester) async {
    await pumpTile(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('босилган ҳолат чизилади — paint хатоси йўқ', (tester) async {
    await pumpTile(tester);
    final g = await tester
        .startGesture(tester.getCenter(find.byType(ServiceSpotlightTile)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await g.up();
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
  });

  testWidgets('ҳошия томонлари битта рангда, қалинлиги 3D учун турлича',
      (tester) async {
    await pumpTile(tester);
    final border = faceDecoration(tester).border! as Border;
    final colors = {
      border.top.color,
      border.left.color,
      border.right.color,
      border.bottom.color,
    };
    expect(colors, hasLength(1));
    expect(border.bottom.width, greaterThan(border.top.width));
  });

  testWidgets('эски лайм/яшил/қизил ранглар қайтмаган', (tester) async {
    await pumpTile(tester);
    final d = faceDecoration(tester);
    final border = d.border! as Border;
    final oldColors = <Color>{
      Color(0xFFE8F2C0), // лайм юз
      Color(0xFF3D7A00), // тўқ яшил лаб
      Color(0xFFB71C1C), // қизил ҳошия
    };
    final used = <Color>{
      ...?(d.gradient as LinearGradient?)?.colors,
      border.bottom.color,
      for (final s in d.boxShadow ?? const <BoxShadow>[]) s.color,
    };
    expect(used.intersection(oldColors), isEmpty);
    expect(border.bottom.color, AvaLight.brandPressed);
  });
}
