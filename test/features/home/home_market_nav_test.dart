import 'package:ava_gurlan/features/home/home_market_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Асосий экрандаги бозор бўлимидан маҳсулот очилганда орқага стрелка
/// БОЗОРга қайтаради (Аҳоли / Улгуржи / Хитой), асосий экранга эмас.
void main() {
  Future<void> pumpHome(WidgetTester t, {required void Function() onDetailOpened}) async {
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => pushDetailOverMarket(
                context,
                market: const Scaffold(body: Center(child: Text('MARKET'))),
                openDetail: () async {
                  onDetailOpened();
                  await Navigator.of(context).push<void>(MaterialPageRoute(
                    builder: (ctx) => Scaffold(
                      appBar: AppBar(
                        leading: BackButton(onPressed: () => Navigator.of(ctx).pop()),
                      ),
                      body: const Center(child: Text('DETAIL')),
                    ),
                  ));
                },
              ),
              child: const Text('HOME'),
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('тафсилотдан орқага — бозор, яна орқага — асосий экран', (t) async {
    var opened = 0;
    await pumpHome(t, onDetailOpened: () => opened++);

    await t.tap(find.text('HOME'));
    await t.pumpAndSettle();
    expect(opened, 1);
    expect(find.text('DETAIL'), findsOneWidget);

    // Орқага (тафсилот ёпилади) → БОЗОР экрани, асосий экран эмас.
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.text('MARKET'), findsOneWidget);
    expect(find.text('DETAIL'), findsNothing);
    expect(find.text('HOME'), findsNothing);

    // Бозордан орқага → асосий экран.
    final nav = t.state<NavigatorState>(find.byType(Navigator));
    nav.pop();
    await t.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('MARKET'), findsNothing);
  });

  testWidgets('Future тафсилот ҳам, бозор ҳам ёпилгандан кейин тугайди', (t) async {
    var done = false;
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: Text('HOME'));
      }),
    ));
    final f = pushDetailOverMarket(
      ctx,
      market: const Scaffold(body: Text('MARKET')),
      openDetail: () => Navigator.of(ctx).push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('DETAIL'))),
      ),
    ).then((_) => done = true);
    await t.pumpAndSettle();
    expect(find.text('DETAIL'), findsOneWidget);

    final nav = t.state<NavigatorState>(find.byType(Navigator));
    nav.pop(); // тафсилот
    await t.pumpAndSettle();
    expect(done, isFalse, reason: 'бозор ҳали очиқ');
    nav.pop(); // бозор
    await t.pumpAndSettle();
    await f;
    expect(done, isTrue);
    expect(find.text('HOME'), findsOneWidget);
  });
}
