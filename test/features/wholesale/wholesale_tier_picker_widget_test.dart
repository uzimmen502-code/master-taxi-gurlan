import 'package:ava_gurlan/core/theme/product_detail_dark.dart';
import 'package:ava_gurlan/core/utils/formatters.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:ava_gurlan/features/wholesale/widgets/wholesale_tier_picker.dart';
import 'package:ava_gurlan/models/price_tier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WholesaleProduct _product({List<PriceTier>? tiers, String unit = 'кг'}) =>
    WholesaleProduct(
      id: 'p',
      sellerId: 's',
      sellerCompanyName: 'Фирма',
      title: 'Помидор',
      titleLower: 'помидор',
      description: '',
      unit: unit,
      priceTiers: tiers ??
          const [
            PriceTier(minQty: 1, price: 14000),
            PriceTier(minQty: 10, price: 12000),
            PriceTier(minQty: 50, price: 10500),
          ],
    );

/// Локализация делегати АТАЙЛАБ уланмаган: `tr` калитнинг ўзини қайтаради
/// (қаранг: app_version_gate_view_test) — тест тилдан мустақил.
Future<ValueNotifier<int>> _pump(
  WidgetTester tester,
  WholesaleProduct p,
) async {
  final qty = ValueNotifier<int>(p.moq);
  await tester.pumpWidget(
    MaterialApp(
      home: ProductDetailDark(
        child: Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder<int>(
              valueListenable: qty,
              builder: (_, q, __) => WholesaleTierPicker(
                product: p,
                qty: q,
                onQtyChanged: (v) => qty.value = v,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return qty;
}

String _money(int v) => '${formatPrice(v)} сўм';

void main() {
  testWidgets('бошланиш: миқдор = минимал буюртма, сумма = 1 × биринчи поғона',
      (tester) async {
    await _pump(tester, _product());
    expect(find.text('1 кг × ${_money(14000)}'), findsOneWidget);
    expect(find.text(_money(14000)), findsOneWidget);
  });

  testWidgets('поғонани босиш — миқдор поғона бошига ўтади, сумма жонли',
      (tester) async {
    final qty = await _pump(tester, _product());
    await tester.tap(find.text('10–49 кг'));
    await tester.pump();
    expect(qty.value, 10);
    expect(find.text('10 кг × ${_money(12000)}'), findsOneWidget);
    expect(find.text(_money(120000)), findsOneWidget);

    await tester.tap(find.text('50+ кг'));
    await tester.pump();
    expect(qty.value, 50);
    expect(find.text(_money(525000)), findsOneWidget);
  });

  testWidgets('юқори поғонадан паст поғонага қайтиш ишлайди', (tester) async {
    final qty = await _pump(tester, _product());
    await tester.tap(find.text('50+ кг'));
    await tester.pump();
    await tester.tap(find.text('1–9 кг'));
    await tester.pump();
    expect(qty.value, 1);
  });

  testWidgets('+ миқдорни ошириб, сумма ортади (чегарада нарх тушади)',
      (tester) async {
    final qty = await _pump(tester, _product());
    await tester.tap(find.text('1–9 кг'));
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
    }
    expect(qty.value, 9);
    expect(find.text(_money(126000)), findsOneWidget); // 9 × 14 000
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    expect(qty.value, 10);
    expect(find.text(_money(120000)), findsOneWidget); // 10 × 12 000 — арзон
  });

  testWidgets('минимал буюртмада «−» ишламайди', (tester) async {
    final qty = await _pump(tester, _product());
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pump();
    expect(qty.value, 1);
  });

  testWidgets('қўлда киритилган кам миқдор минимумга кўтарилади',
      (tester) async {
    final p = _product(
      tiers: const [PriceTier(minQty: 5, price: 1000)],
    );
    final qty = await _pump(tester, p);
    await tester.enterText(find.byType(TextField), '2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(qty.value, 5);
  });

  testWidgets('қўлда киритилган миқдор — поғона ва сумма мос', (tester) async {
    final qty = await _pump(tester, _product());
    await tester.enterText(find.byType(TextField), '49');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(qty.value, 49);
    expect(find.text(_money(588000)), findsOneWidget); // 49 × 12 000
  });

  testWidgets('кейинги поғона маслаҳати: «қилиш» босилса шу поғонага ўтади',
      (tester) async {
    final qty = await _pump(tester, _product());
    await tester.tap(find.text('10–49 кг'));
    await tester.pump();
    expect(find.text('wholesale_next_tier_hint'), findsOneWidget);
    await tester.tap(find.text('wholesale_set_qty'));
    await tester.pump();
    expect(qty.value, 50);
  });

  testWidgets('энг арзон поғонада маслаҳат йўқ', (tester) async {
    await _pump(tester, _product());
    await tester.tap(find.text('50+ кг'));
    await tester.pump();
    expect(find.text('wholesale_next_tier_hint'), findsNothing);
  });

  testWidgets('битта поғона: танлов тугмалари йўқ, ҳисоб бор', (tester) async {
    await _pump(
      tester,
      _product(tiers: const [PriceTier(minQty: 1, price: 5000)]),
    );
    expect(find.text('wholesale_pick_tier'), findsNothing);
    expect(find.text('1 кг × ${_money(5000)}'), findsOneWidget);
  });

  testWidgets('тежамкорлик фақат арзонроқ поғонада кўринади', (tester) async {
    await _pump(tester, _product());
    expect(find.text('wholesale_savings'), findsNothing);
    await tester.tap(find.text('10–49 кг'));
    await tester.pump();
    expect(find.text('wholesale_savings'), findsOneWidget);
    expect(find.text(_money(20000)), findsOneWidget); // 10×14000 − 10×12000
  });
}
