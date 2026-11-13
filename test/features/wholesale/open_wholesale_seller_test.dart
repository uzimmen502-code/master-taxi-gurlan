// «＋» → «Улгуржи/Ишлаб чиқарувчи маҳсулотлари» (эга, 2026-11-13): тасдиқланган
// сотувчига форма дарҳол (орқага — ўз маҳсулотлари, яна орқага — чақирган экран);
// бошқа ҳолатда — сотувчи экрани (рўйхатдан ўтиш / ҳолат).
import 'package:ava_gurlan/features/wholesale/models/wholesale_seller.dart';
import 'package:ava_gurlan/features/wholesale/open_wholesale_seller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WholesaleSeller _seller({required String status, bool shipFrom = true}) => WholesaleSeller(
      phone: '998901234567',
      companyName: 'Zavod',
      ownerName: 'Ali',
      sellerType: 'manufacturer',
      approvalStatus: status,
      regionId: shipFrom ? 'xorazm' : '',
      districtId: shipFrom ? 'gurlan' : '',
    );

void main() {
  Future<void> run(WidgetTester t, Future<WholesaleSeller?> Function(String) load) async {
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => openWholesaleSeller(
                context,
                phone: '998901234567',
                loadSeller: load,
                screenBuilder: () => const WholesaleSellerScreen(
                  phone: '998901234567',
                  body: Text('SELLER_AREA'),
                ),
                formBuilder: (s) => Scaffold(body: Text('FORM ${s.companyName}')),
              ),
              child: const Text('HOME'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('HOME'));
    await t.pumpAndSettle();
  }

  NavigatorState nav(WidgetTester t) => t.state<NavigatorState>(find.byType(Navigator).first);

  testWidgets('тасдиқланган + манзил бор — форма дарҳол; орқага — сотувчи экрани; яна орқага — асосий', (t) async {
    await run(t, (_) async => _seller(status: WholesaleSeller.statusApproved));
    expect(find.text('FORM Zavod'), findsOneWidget);
    nav(t).pop();
    await t.pumpAndSettle();
    expect(find.text('SELLER_AREA'), findsOneWidget);
    expect(find.text('home_create_wholesale'), findsOneWidget, reason: 'сарлавҳа');
    nav(t).pop();
    await t.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
  });

  for (final c in [
    ('рўйхатдан ўтмаган', null),
    ('текширувда', _seller(status: WholesaleSeller.statusPending)),
    ('рад этилган', _seller(status: WholesaleSeller.statusRejected)),
    ('тасдиқланган, манзилсиз', _seller(status: WholesaleSeller.statusApproved, shipFrom: false)),
  ]) {
    testWidgets('${c.$1} — форма эмас, сотувчи экрани', (t) async {
      await run(t, (_) async => c.$2);
      expect(find.textContaining('FORM'), findsNothing);
      expect(find.text('SELLER_AREA'), findsOneWidget);
    });
  }

  testWidgets('сотувчини ўқиб бўлмади — форма эмас, сотувчи экрани (ўзи қайта уланади)', (t) async {
    await run(t, (_) async => throw StateError('offline'));
    expect(find.textContaining('FORM'), findsNothing);
    expect(find.text('SELLER_AREA'), findsOneWidget);
  });
}
