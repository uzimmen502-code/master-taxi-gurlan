import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_pack_chips.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_pack_editor.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_tier_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Қадоқлар UI (эга, 2026-10-31): тафсилотда танлов, қолдиқ қатори,
/// поғона виджети танланган қадоқ нархини олади; формадаги қадоқ
/// карточкаси текшируви. Тестда `tr` калитнинг ўзини қайтаради.
WholesaleProduct _product() => WholesaleProduct.fromMap('x', {
      'sellerId': '998901111111',
      'title': 'Гуруч',
      'description': 'Лазер',
      'priceTiers': [
        {'minQty': 1, 'price': 15000},
      ],
      'unit': 'қоп',
      'packs': [
        {
          'id': 'p1',
          'label': '1 кг',
          'priceTiers': [
            {'minQty': 1, 'price': 15000},
          ],
        },
        {
          'id': 'p2',
          'label': '25 кг',
          'priceTiers': [
            {'minQty': 1, 'price': 320000},
            {'minQty': 10, 'price': 300000},
          ],
        },
      ],
    });

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('қадоқ чиплари: ҳаммаси кўринади, босилганда ID қайтади', (tester) async {
    String? picked;
    await tester.pumpWidget(_host(WholesalePackChips(
      product: _product(),
      selectedId: 'p1',
      onSelected: (id) => picked = id,
    )));
    expect(find.text('1 кг'), findsOneWidget);
    expect(find.text('25 кг'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wholesale-pack-chip-p2')));
    expect(picked, 'p2');
    // Тугма 48 dp дан кичик эмас (бармоқ билан босиш).
    expect(tester.getSize(find.byKey(const ValueKey('wholesale-pack-chip-p2'))).height,
        greaterThanOrEqualTo(48));
  });

  testWidgets('қолдиқ: сон / Тугаган / киритилмаган — ҳеч нарса', (tester) async {
    await tester.pumpWidget(_host(const WholesaleStockLine(qty: 120, unitLabel: 'қоп')));
    expect(find.text('wholesale_stock_left'), findsOneWidget);
    await tester.pumpWidget(_host(const WholesaleStockLine(qty: 0, unitLabel: 'қоп')));
    expect(find.text('wholesale_stock_out'), findsOneWidget);
    await tester.pumpWidget(_host(const WholesaleStockLine(qty: null, unitLabel: 'қоп')));
    expect(find.byKey(const ValueKey('wholesale-stock-line')), findsNothing);
  });

  testWidgets('поғона виджети танланган қадоқ поғоналарини кўрсатади', (tester) async {
    final p = _product();
    await tester.pumpWidget(_host(WholesaleTierPicker(
      product: p,
      pack: p.packById('p2'),
      qty: 1,
      onQtyChanged: (_) {},
    )));
    expect(find.text('320 000'), findsOneWidget);
    expect(find.text('300 000'), findsOneWidget);
    expect(find.text('15 000'), findsNothing, reason: '1 кг қадоқ нархи кўринмасин');
  });

  group('WholesalePackDraft', () {
    test('нарх, вазн, қолдиқ текшируви (мусбат + манфий + чегара)', () {
      final d = WholesalePackDraft(id: 'p1');
      expect(d.collectTiers(), isEmpty);
      d.prices[0].text = '15000';
      d.prices[2].text = '13000';
      expect(d.collectTiers().map((t) => t.minQty), [1, 50]);

      d.weight.text = '1,5';
      expect(d.collectShipping().weightG, 1500);
      d.dimL.text = '10';
      expect(d.collectShipping().error, 'wholesale_err_dims_invalid', reason: 'ўлчам — учаласи бирга');

      expect(d.collectStock().qty, isNull);
      d.stock.text = '0';
      expect(d.collectStock().qty, 0);
      d.stock.text = '1000000';
      expect(d.collectStock().qty, 1000000);
      d.stock.text = '1000001';
      expect(d.collectStock().error, 'wholesale_err_stock_invalid');
      d.dispose();
    });

    test('мавжуд қадоқдан: default ID → p1, поғоналар тўғри майдонга', () {
      final legacy = WholesaleProduct.fromMap('y', {
        'sellerId': '998901111111',
        'title': 'Ун',
        'priceTiers': [
          {'minQty': 1, 'price': 9000},
          {'minQty': 10, 'price': 8500},
        ],
      }).effectivePacks.single;
      final d = WholesalePackDraft.fromPack(legacy, stock: 40);
      expect(d.id, 'p1');
      expect(d.prices[0].text, '9000');
      expect(d.prices[1].text, '8500');
      expect(d.label.text, isEmpty);
      expect(d.stock.text, '40');
      d.dispose();
    });
  });
}
