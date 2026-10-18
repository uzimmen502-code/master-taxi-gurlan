import 'package:ava_gurlan/features/admin_web/utils/realty_counts_validation.dart';
import 'package:ava_gurlan/features/admin_web/widgets/realty_counts_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String? _v({
  String free = '3',
  List<(String, String)>? pk,
  List<(String, String, String, String)>? pl,
}) =>
    validateRealtyCounts(
      freeLimit: free,
      packages: pk ?? const [('5', '30000'), ('10', '50000')],
      plans: pl ?? const [('pro_25', '25', '30', '250000')],
    );

void main() {
  group('validateRealtyCounts', () {
    test('тўғри форма', () => expect(_v(), isNull));

    test('бўш бепул лимит рухсат (бошланғичга қайтариш)', () => expect(_v(free: ''), isNull));

    test('бепул лимит чегарадан ташқарида — рад', () {
      for (final f in ['0', '51', '-1', '2.5', 'abc']) {
        expect(_v(free: f), isNotNull, reason: f);
      }
    });

    test('пакет: бўш рўйхат ва 7 қатор — рад', () {
      expect(_v(pk: const []), isNotNull);
      expect(_v(pk: [for (var i = 1; i <= 7; i++) ('$i', '1000')]), isNotNull);
    });

    test('пакет: яроқсиз ўлчам/нарх ва такрор — рад', () {
      expect(_v(pk: const [('0', '1')]), isNotNull);
      expect(_v(pk: const [('101', '1')]), isNotNull);
      expect(_v(pk: const [('5', '-1')]), isNotNull);
      expect(_v(pk: const [('5', '')]), isNotNull);
      expect(_v(pk: const [('5', '1'), ('5', '2')]), contains('бир хил ўлчам'));
    });

    test('пакет: катта пакет битта объектда қиммат — рад; тенг нарх — рухсат; тартиб муҳим эмас', () {
      expect(_v(pk: const [('5', '30000'), ('10', '70000')]), isNotNull);
      expect(_v(pk: const [('5', '25000'), ('10', '50000')]), isNull);
      expect(_v(pk: const [('10', '50000'), ('5', '30000')]), isNull);
    });

    test('режа: id, объект (≤200), кун (≤365), нарх, такрор', () {
      expect(_v(pl: const [('A', '5', '5', '1')]), isNotNull);
      expect(_v(pl: const [('ok_id', '0', '5', '1')]), isNotNull);
      expect(_v(pl: const [('ok_id', '201', '5', '1')]), isNotNull);
      expect(_v(pl: const [('ok_id', '5', '366', '1')]), isNotNull);
      expect(_v(pl: const [('ok_id', '5', '5', '-1')]), isNotNull);
      expect(_v(pl: const [('a1', '5', '5', '1'), ('a1', '6', '5', '1')]), isNotNull);
      expect(_v(pl: const [('ok_id', '200', '365', '0')]), isNull);
      expect(_v(pl: const []), isNotNull);
    });
  });

  test('realtyCountsServerError: сабаб тушунарли матнга, нотаниш — умумий', () {
    expect(realtyCountsServerError('package_per_object'), contains('қиммат'));
    expect(realtyCountsServerError('Admin only'), contains('админ'));
    expect(realtyCountsServerError('weird'), contains('weird'));
  });

  group('RealtyCountsEditor', () {
    Future<List<Map<String, Object?>>> pump(
      WidgetTester t, {
      int? free = 2,
      Future<void> Function()? failWith,
    }) async {
      final saved = <Map<String, Object?>>[];
      await t.binding.setSurfaceSize(const Size(1000, 1800));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RealtyCountsEditor(
              initialFreeLimit: free,
              initialPackages: const [(5, 30000), (10, 50000)],
              initialPlans: const [('pro_25', 25, 30, 250000)],
              onSave: ({required freeLimit, required packages, required proPlans}) async {
                if (failWith != null) await failWith();
                saved.add({'free': freeLimit, 'packages': packages, 'plans': proPlans});
              },
            ),
          ),
        ),
      ));
      return saved;
    }

    testWidgets('амалдаги қийматлар майдонларда кўринади', (t) async {
      await pump(t);
      expect(t.widget<TextField>(find.byKey(const ValueKey('counts-free-limit'))).controller!.text, '2');
      expect(t.widget<TextField>(find.byKey(const ValueKey('counts-pkg-size-1'))).controller!.text, '10');
      expect(t.widget<TextField>(find.byKey(const ValueKey('counts-plan-id-0'))).controller!.text, 'pro_25');
    });

    testWidgets('ўзгартириб сақлаш — серверга тозаланган қийматлар кетади', (t) async {
      final saved = await pump(t);
      await t.enterText(find.byKey(const ValueKey('counts-free-limit')), '5');
      await t.enterText(find.byKey(const ValueKey('counts-pkg-size-0')), '3');
      await t.enterText(find.byKey(const ValueKey('counts-pkg-price-0')), '20000');
      await t.enterText(find.byKey(const ValueKey('counts-plan-objects-0')), '40');
      await t.tap(find.byKey(const ValueKey('counts-save')));
      await t.pumpAndSettle();
      expect(saved.length, 1);
      expect(saved.single['free'], 5);
      expect(saved.single['packages'], [
        {'size': 3, 'price': 20000},
        {'size': 10, 'price': 50000},
      ]);
      expect((saved.single['plans'] as List).single, {'id': 'pro_25', 'objects': 40, 'days': 30, 'price': 250000});
      expect(find.byKey(const ValueKey('counts-ok')), findsOneWidget);
    });

    testWidgets('бўш бепул лимит — null (бошланғичга қайтариш)', (t) async {
      final saved = await pump(t);
      await t.enterText(find.byKey(const ValueKey('counts-free-limit')), '');
      await t.tap(find.byKey(const ValueKey('counts-save')));
      await t.pumpAndSettle();
      expect(saved.single['free'], isNull);
    });

    testWidgets('яроқсиз қиймат — серверга ЮБОРИЛМАЙДИ, хато кўрсатилади', (t) async {
      final saved = await pump(t);
      await t.enterText(find.byKey(const ValueKey('counts-pkg-price-1')), '90000');
      await t.tap(find.byKey(const ValueKey('counts-save')));
      await t.pumpAndSettle();
      expect(saved, isEmpty);
      expect(find.byKey(const ValueKey('counts-error')), findsOneWidget);
    });

    testWidgets('қатор қўшиш ва олиб ташлаш; охирги қаторни олиб бўлмайди', (t) async {
      final saved = await pump(t);
      await t.tap(find.byKey(const ValueKey('counts-pkg-add')));
      await t.pump();
      await t.enterText(find.byKey(const ValueKey('counts-pkg-size-2')), '20');
      await t.enterText(find.byKey(const ValueKey('counts-pkg-price-2')), '80000');
      await t.tap(find.byKey(const ValueKey('counts-plan-add')));
      await t.pump();
      await t.enterText(find.byKey(const ValueKey('counts-plan-id-1')), 'pro_60');
      await t.enterText(find.byKey(const ValueKey('counts-plan-objects-1')), '60');
      await t.enterText(find.byKey(const ValueKey('counts-plan-days-1')), '30');
      await t.enterText(find.byKey(const ValueKey('counts-plan-price-1')), '500000');
      await t.tap(find.byKey(const ValueKey('counts-pkg-del-0')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('counts-save')));
      await t.pumpAndSettle();
      expect((saved.single['packages'] as List).length, 2);
      expect((saved.single['plans'] as List).length, 2);

      // Битта қатор қолганда ўчириш тугмаси ўчиқ.
      await t.tap(find.byKey(const ValueKey('counts-pkg-del-0')));
      await t.pump();
      final del = t.widget<IconButton>(find.byKey(const ValueKey('counts-pkg-del-0')));
      expect(del.onPressed, isNull);
    });

    testWidgets('сервер хатоси (StateError) админга кўрсатилади, «сақланди» ёзилмайди', (t) async {
      await pump(t, failWith: () async => throw StateError('Катта пакет қиммат'));
      await t.tap(find.byKey(const ValueKey('counts-save')));
      await t.pumpAndSettle();
      expect(find.text('Катта пакет қиммат'), findsOneWidget);
      expect(find.byKey(const ValueKey('counts-ok')), findsNothing);
    });

    testWidgets('сақлаш давомида тугма ўчиқ (икки марта босишдан ҳимоя)', (t) async {
      var calls = 0;
      await t.binding.setSurfaceSize(const Size(1000, 1800));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RealtyCountsEditor(
              initialFreeLimit: 2,
              initialPackages: const [(5, 30000)],
              initialPlans: const [('pro_25', 25, 30, 250000)],
              onSave: ({required freeLimit, required packages, required proPlans}) async {
                calls++;
                await Future<void>.delayed(const Duration(milliseconds: 50));
              },
            ),
          ),
        ),
      ));
      await t.tap(find.byKey(const ValueKey('counts-save')));
      await t.pump();
      expect(t.widget<ElevatedButton>(find.byKey(const ValueKey('counts-save'))).onPressed, isNull);
      await t.pumpAndSettle();
      expect(calls, 1);
    });
  });
}
