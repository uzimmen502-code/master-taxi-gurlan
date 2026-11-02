// Улгуржи тафсилоти «Б вариант» (эга, 2026-11-02): қолдиқ нарх қаторида,
// поғоналар сарлавҳасиз, тор «− N +», пастда [− N +] [📞] [Буюртма ёзиш · ≈ сумма].
import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/features/wholesale/widgets/wholesale_compact_detail_parts.dart';
import 'package:ava_gurlan/models/price_tier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../restaurants/restaurants_l10n_harness.dart';

Widget _host(Widget child, {JsonL10nDelegate? d}) => l10nApp(
      delegate: d,
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );

void main() {
  final d = JsonL10nDelegate();
  const tiers = [
    PriceTier(minQty: 1, price: 12000),
    PriceTier(minQty: 10, price: 11000),
    PriceTier(minQty: 50, price: 10000),
  ];

  group('clampCompactQty', () {
    test('MOQ дан кам — MOQ, қолдиқдан кўп — қолдиқ', () {
      expect(clampCompactQty(0, moq: 5, max: 100), 5);
      expect(clampCompactQty(150, moq: 5, max: 100), 100);
      expect(clampCompactQty(42, moq: 5, max: 100), 42);
    });
    test('қолдиқ MOQ дан кам бўлса ҳам MOQ қолади (чегара тескари эмас)', () {
      expect(clampCompactQty(1, moq: 10, max: 3), 10);
      expect(clampCompactQty(99, moq: 10, max: 3), 10);
    });
  });

  testWidgets('қолдиқ нарх билан бир қаторда; киритилмаган — йўқ; 0 — «Тугаган»', (tester) async {
    await tester.pumpWidget(_host(
      const WholesalePriceStockRow(priceText: '11 000 сўм', unitLabel: 'дона', stockQty: 120),
      d: d,
    ));
    await tester.pumpAndSettle();
    final stockText = d.tr('wholesale_stock_left_short').replaceAll('{qty}', '120').replaceAll('{unit}', 'дона');
    // Харнес лотинда; калит 3 тилда (эга кўрган матн: «Қолди: 120 дона»).
    expect(stockText, 'Qoldi: 120 дона');
    for (final (lang, word) in [('uz_Cyrl', 'Қолди:'), ('uz_Latn', 'Qoldi:'), ('ru', 'Осталось:')]) {
      final j = jsonDecode(File('assets/lang/$lang.json').readAsStringSync()) as Map<String, dynamic>;
      expect(j['wholesale_stock_left_short'], '$word {qty} {unit}', reason: lang);
    }
    expect(find.text(stockText), findsOneWidget);
    final price = tester.getCenter(find.byKey(const ValueKey('wholesale-compact-price')));
    final stock = tester.getCenter(find.byKey(const ValueKey('wholesale-stock-line')));
    expect((price.dy - stock.dy).abs(), lessThan(4));
    expect(stock.dx, greaterThan(price.dx));

    await tester.pumpWidget(_host(
      const WholesalePriceStockRow(priceText: '11 000 сўм', unitLabel: 'дона', stockQty: null),
      d: d,
    ));
    expect(find.byKey(const ValueKey('wholesale-stock-line')), findsNothing);

    await tester.pumpWidget(_host(
      const WholesalePriceStockRow(priceText: '11 000 сўм', unitLabel: 'дона', stockQty: 0),
      d: d,
    ));
    expect(find.text(d.tr('wholesale_stock_out')), findsOneWidget);
  });

  testWidgets('поғоналар: сарлавҳасиз, фаол поғона миқдорга мос, босилса бошланишига ўтади', (tester) async {
    int? picked;
    await tester.pumpWidget(_host(
      WholesaleTierRow(tiers: tiers, qty: 12, unitLabel: 'дона', onPick: (q) => picked = q),
      d: d,
    ));
    await tester.pumpAndSettle();
    expect(find.text(d.tr('wholesale_pick_tier')), findsNothing);
    expect(find.text('10–49 дона'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wholesale-tier-2')));
    expect(picked, 50);

    await tester.pumpWidget(_host(
      WholesaleTierRow(tiers: const [PriceTier(minQty: 1, price: 5000)], qty: 1, unitLabel: 'дона', onPick: (_) {}),
      d: d,
    ));
    expect(find.byKey(const ValueKey('wholesale-tier-0')), findsNothing);
  });

  testWidgets('тор «− N +»: эни ≤ 56 px, чегарада тугма ўчиқ', (tester) async {
    var qty = 10;
    await tester.pumpWidget(_host(
      StatefulBuilder(
        builder: (context, set) => Align(
          alignment: Alignment.topLeft,
          child: WholesaleQtyStepper(qty: qty, min: 10, max: 12, onChanged: (v) => set(() => qty = v)),
        ),
      ),
      d: d,
    ));
    // 15 + 15 тугма + рамка + рақам; тест шрифти (Ahem) ҳарфни 12 px энли
    // чизади («10» = 24 px), ҳақиқий шрифтда ≈ 52 px.
    expect(tester.getSize(find.byType(WholesaleQtyStepper)).width, lessThanOrEqualTo(57));
    await tester.tap(find.byKey(const ValueKey('wholesale-qty-minus')));
    expect(qty, 10, reason: 'MOQ дан пастга тушмайди');
    await tester.tap(find.byKey(const ValueKey('wholesale-qty-plus')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('wholesale-qty-plus')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('wholesale-qty-plus')));
    await tester.pump();
    expect(qty, 12, reason: 'қолдиқдан ошмайди');
  });

  testWidgets('пастки панел: [− N +] [📞] [Буюртма ёзиш · ≈ сумма] бир қаторда, босилади', (tester) async {
    var calls = 0, writes = 0;
    await tester.pumpWidget(_host(
      WholesaleCompactBottomBar(
        qty: 10,
        minQty: 1,
        maxQty: 100,
        onQtyChanged: (_) {},
        totalText: '≈ 110 000 сўм',
        onCall: () => calls++,
        onWriteOrder: () => writes++,
      ),
      d: d,
    ));
    await tester.pumpAndSettle();
    expect(find.text(d.tr('deal_chat_write_order')), findsOneWidget);
    expect(find.text('≈ 110 000 сўм'), findsOneWidget);
    final step = tester.getCenter(find.byType(WholesaleQtyStepper));
    final call = tester.getCenter(find.byKey(const ValueKey('wholesale-call')));
    final write = tester.getCenter(find.byKey(const ValueKey('wholesale-write-order')));
    expect([(step.dy - call.dy).abs() < 1, (call.dy - write.dy).abs() < 1], [true, true]);
    expect(step.dx < call.dx && call.dx < write.dx, isTrue);
    await tester.tap(find.byKey(const ValueKey('wholesale-call')));
    await tester.tap(find.byKey(const ValueKey('wholesale-write-order')));
    expect([calls, writes], [1, 1]);
  });

  testWidgets('ўз маҳсулоти: миқдор ва «Буюртма ёзиш» йўқ, фақат қўнғироқ', (tester) async {
    await tester.pumpWidget(_host(
      WholesaleCompactBottomBar(
        qty: 1,
        minQty: 1,
        maxQty: 10,
        onQtyChanged: (_) {},
        totalText: '≈ 1 сўм',
        onCall: () {},
        onWriteOrder: () {},
        showWriteOrder: false,
      ),
      d: d,
    ));
    expect(find.byType(WholesaleQtyStepper), findsNothing);
    expect(find.byKey(const ValueKey('wholesale-write-order')), findsNothing);
    expect(find.text(d.tr('wholesale_call')), findsOneWidget);
  });

  testWidgets('тор экран (320 dp): тошиб кетмайди', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(
      WholesaleCompactBottomBar(
        qty: 99999,
        minQty: 1,
        maxQty: 100000,
        onQtyChanged: (_) {},
        totalText: '≈ 1 099 989 000 сўм',
        onCall: () {},
        onWriteOrder: () {},
      ),
      d: d,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
