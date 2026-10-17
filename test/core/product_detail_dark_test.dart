import 'package:ava_gurlan/core/theme/product_detail_dark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Қора мавзу ФАҚАТ ўраладиган экранга таъсир қилади (эга қарори,
/// 2026-10-17) ва тизим шрифти катта бўлса ×1.15 дан ошмайди.
void main() {
  Future<({double scale, Brightness brightness, Color bg})> probe(
    WidgetTester tester, {
    required double outerScale,
  }) async {
    late double scale;
    late Brightness brightness;
    late Color bg;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(outerScale)),
          child: child!,
        ),
        home: ProductDetailDark(
          child: Builder(builder: (context) {
            scale = MediaQuery.textScalerOf(context).scale(10) / 10;
            brightness = Theme.of(context).brightness;
            bg = Theme.of(context).scaffoldBackgroundColor;
            return const SizedBox();
          }),
        ),
      ),
    );
    return (scale: scale, brightness: brightness, bg: bg);
  }

  testWidgets('шрифт ×1.3 → ×1.15 га чекланади', (tester) async {
    final r = await probe(tester, outerScale: 1.3);
    expect(r.scale, closeTo(1.15, 0.001));
  });

  testWidgets('шрифт ×1.5 → ×1.15', (tester) async {
    expect((await probe(tester, outerScale: 1.5)).scale, closeTo(1.15, 0.001));
  });

  testWidgets('шрифт ×1.0 ва ×1.1 ўзгармайди (кичик шрифт катталашмайди)',
      (tester) async {
    expect((await probe(tester, outerScale: 1.0)).scale, closeTo(1.0, 0.001));
    expect((await probe(tester, outerScale: 1.1)).scale, closeTo(1.1, 0.001));
  });

  testWidgets('мавзу қора, фон PdDark.bg', (tester) async {
    final r = await probe(tester, outerScale: 1.0);
    expect(r.brightness, Brightness.dark);
    expect(r.bg, PdDark.bg);
  });

  testWidgets('ташқарида қора мавзу ТАЪСИР қилмайди', (tester) async {
    late Brightness outside;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) {
          outside = Theme.of(context).brightness;
          return const ProductDetailDark(child: SizedBox());
        }),
      ),
    );
    expect(outside, Brightness.light);
  });
}
