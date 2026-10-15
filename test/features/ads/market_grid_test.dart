import 'package:ava_gurlan/features/ads/widgets/market_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({required double width, required double scale, required Widget child}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 800),
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(
        body: SizedBox(width: width, height: 800, child: child),
      ),
    ),
  );
}

Widget _cell({required bool twoLineTitle}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AspectRatio(
        aspectRatio: MarketGridMetrics.imageAspect,
        child: const ColoredBox(color: Colors.grey),
      ),
      MarketCardText(
        title: twoLineTitle
            ? 'Узун сарлавҳа биринчи қатор ва иккинчи қаторга ўтадиган матн'
            : 'Сарлавҳа',
        titleLines: twoLineTitle ? 2 : 1,
        price: '10 000 сўм',
        caption: twoLineTitle ? null : 'МОҚ 10 дона · Сотувчи',
      ),
    ],
  );
}

void main() {
  for (final width in const [320.0, 360.0, 411.0, 600.0]) {
    for (final scale in const [1.0, 1.3]) {
      for (final two in const [false, true]) {
        testWidgets(
            'катак: ${width.toInt()} dp, шрифт ×$scale, '
            '${two ? "2 қаторли сарлавҳа" : "3 қаторли блок"} — тошмайди, бўш жой кам',
            (tester) async {
          await tester.pumpWidget(_host(
            width: width,
            scale: scale,
            child: MarketProductGrid(
              itemCount: 4,
              itemBuilder: (_, __) => _cell(twoLineTitle: two),
            ),
          ));
          await tester.pump();
          // Тошиш (overflow) хатоси йўқ.
          expect(tester.takeException(), isNull);

          // Катак баландлиги = расм + матн блоки (кенгликка пропорционал
          // бўш жой йўқ).
          final cell = tester.getSize(find.byType(AspectRatio).first.evaluate().isEmpty
              ? find.byType(MarketCardText).first
              : find.byType(Column).first);
          final cellW = (width - 24 - 10) / 2;
          final block = tester.getSize(find.byType(MarketCardText).first).height;
          expect(cell.height, closeTo(cellW / MarketGridMetrics.imageAspect + block, 1.5));

          // Матн блоки ичидаги ҳақиқий мазмун билан блок орасидаги фарқ
          // кичик (≤ 18 dp: энг кўпи — нарх қатори бўлмаган ҳолат).
          final content = tester
              .getSize(find.descendant(
                of: find.byType(MarketCardText).first,
                matching: find.byType(Column),
              ).first)
              .height;
          expect(block - content - 2 * MarketGridMetrics.textPad, lessThan(18));
        });
      }
    }
  }
}