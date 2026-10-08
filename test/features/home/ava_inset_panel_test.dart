import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/home/widgets/ava_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Регрессия (2026-10-08, эга скриншоти): бош саҳифадаги ботиқ панел
/// веб'да бутунлай лой рангида чиқарди.
///
/// Symptom: панел ичи `#B2A287`, матн хира.
/// Root cause: ички соя `Path.combine(difference)` билан ясалган «ҳалқа»
/// эди; веб рендерери уни тешигисиз — бутун тўртбурчак қилиб чизди ва
/// 55% тиниқ соя майдон ҳамда матн устини тўлиқ қоплади. Мобил Skia'да
/// хато кўринмасди, шунинг учун тест муҳитида ҳам кўринмайди.
/// Fix: ҳалқа `canvas.drawDRRect` билан чизилади — у ташқи ва ички шакл
/// ОРАСИНИ чизади ва ҳамма рендерерда бир хил ишлайди.
///
/// Тест рендерерни эмас, ишлатилган чизиш буйруғини қулфлайди: соя
/// DRRect бўлиши, ҳеч қандай path бўлмаслиги шарт.
void main() {
  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(16),
          child: AvaInsetPanel(
            child: SizedBox(height: 80, child: Text('Қатор')),
          ),
        ),
      ),
    ));
  }

  RenderBox shadowBox(WidgetTester tester) => tester.renderObject<RenderBox>(
        find
            .descendant(
              of: find.byType(AvaInsetPanel),
              matching: find.byType(CustomPaint),
            )
            .last,
      );

  testWidgets('ички соя drawDRRect билан чизилади (веб-хавфсиз)',
      (tester) async {
    await pumpPanel(tester);
    expect(
      shadowBox(tester),
      paints..drrect(color: AvaColors.light.insetShadow),
    );
  });

  testWidgets('соя path билан чизилмайди (Path.combine веб\'да бузилади)',
      (tester) async {
    await pumpPanel(tester);
    expect(shadowBox(tester), isNot(paints..path()));
  });

  testWidgets('DRRect ички чети панелнинг ўзи — соя ичкарига тушади',
      (tester) async {
    await pumpPanel(tester);
    final size = shadowBox(tester).size;
    expect(
      shadowBox(tester),
      paints
        ..drrect(
          inner: RRect.fromRectAndRadius(
            (Offset.zero & size).shift(const Offset(0, AvaInsetPanel.band * 0.5)),
            const Radius.circular(10),
          ),
        ),
    );
  });
}
