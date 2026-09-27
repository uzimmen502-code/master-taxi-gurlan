import 'package:ava_gurlan/features/home/widgets/ava_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        // Бош саҳифанинг вертикал скроллини тақлид қиламиз — тўқнашув
        // айнан шу ҳолатда чиқарди.
        body: SingleChildScrollView(
          child: Column(children: [child, const SizedBox(height: 2000)]),
        ),
      ),
    );

List<Widget> _rows(int n) => [
      for (var i = 0; i < n; i++) Text('qator $i'),
    ];

void main() {
  group('AvaRowPager', () {
    testWidgets('5 тадан кам қатор — саҳифалаш ҳам, нуқта ҳам йўқ',
        (tester) async {
      await tester.pumpWidget(_host(
        AvaRowPager(rowHeight: AvaRowPager.textRow, rows: _rows(3)),
      ));
      expect(find.byType(PageView), findsNothing);
      expect(find.text('qator 0'), findsOneWidget);
      expect(find.text('qator 2'), findsOneWidget);
    });

    testWidgets('10 қатор — 2 саҳифа, биринчисида дастлабки 5 таси',
        (tester) async {
      await tester.pumpWidget(_host(
        AvaRowPager(rowHeight: AvaRowPager.textRow, rows: _rows(10)),
      ));
      expect(find.byType(PageView), findsOneWidget);
      expect(find.text('qator 0'), findsOneWidget);
      expect(find.text('qator 4'), findsOneWidget);
      // 6-қатор иккинчи саҳифада — ҳозир чизилмайди.
      expect(find.text('qator 5'), findsNothing);
    });

    testWidgets('ёнга сурилса иккинчи саҳифа кўринади', (tester) async {
      await tester.pumpWidget(_host(
        AvaRowPager(rowHeight: AvaRowPager.textRow, rows: _rows(10)),
      ));
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('qator 5'), findsOneWidget);
      expect(find.text('qator 0'), findsNothing);
    });

    testWidgets('охирги саҳифадан яна сурилса — модул очилади',
        (tester) async {
      var opened = 0;
      await tester.pumpWidget(_host(
        AvaRowPager(
          rowHeight: AvaRowPager.textRow,
          rows: _rows(10),
          onOpenModule: () => opened++,
        ),
      ));
      // Иккинчи (охирги) саҳифага ўтамиз.
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(opened, 0);
      // Охиридан яна ўнгдан чапга — overscroll.
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(opened, 1, reason: 'охиридан сурилганда модул очилиши керак');
    });

    testWidgets('модул бир мартадан кўп очилмайди', (tester) async {
      var opened = 0;
      await tester.pumpWidget(_host(
        AvaRowPager(
          rowHeight: AvaRowPager.textRow,
          rows: _rows(10),
          onOpenModule: () => opened++,
        ),
      ));
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      // Битта узлуксиз ҳаракат ичида бир неча overscroll хабари келади.
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });

    testWidgets('вертикал ҳаракат САҲИФАга тегишли — тўқнашув йўқ',
        (tester) async {
      await tester.pumpWidget(_host(
        AvaRowPager(rowHeight: AvaRowPager.textRow, rows: _rows(10)),
      ));
      final outer = find.byType(SingleChildScrollView);
      final before = tester.widget<SingleChildScrollView>(outer);
      expect(before.controller?.hasClients ?? true, isTrue);

      // Бармоқ АЙНАН қаторлар устида — аввал шу ҳолат саҳифани қотирарди.
      await tester.drag(find.byType(PageView), const Offset(0, -300));
      await tester.pumpAndSettle();

      final position = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      ).position;
      expect(
        position.pixels,
        greaterThan(0),
        reason: 'қаторлар устидан пастга сурилганда саҳифа сурилиши керак',
      );
    });
  });
}
