import 'package:ava_gurlan/features/admin_web/widgets/order_history_from_bar.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

OrderModel _order(String status, {DateTime? createdAt}) => OrderModel(
      id: 'o1',
      type: 'bread',
      total: 35000,
      status: status,
      items: const [],
      createdAt: createdAt,
    );

void main() {
  final from = DateTime(2026, 10, 1);
  final before = DateTime(2026, 9, 30, 23, 59);
  final after = DateTime(2026, 10, 1, 0, 1);

  group('OrderModel.hasFinalStatus', () {
    test('delivered / rejected / cancelled — якуний', () {
      for (final s in ['delivered', 'rejected', 'cancelled']) {
        expect(_order(s).hasFinalStatus, isTrue, reason: s);
      }
    });

    test('фаол ҳолатлар — якуний эмас', () {
      for (final s in ['new', 'accepted', 'ready', 'in_delivery', 'courier']) {
        expect(_order(s).hasFinalStatus, isFalse, reason: s);
      }
    });
  });

  group('isHiddenByOrderHistoryFrom', () {
    test('чегара йўқ — ҳеч нарса яширилмайди', () {
      expect(
        isHiddenByOrderHistoryFrom(_order('delivered', createdAt: before), null),
        isFalse,
      );
    });

    test('санадан олдинги якунланган буюртма яширилади', () {
      for (final s in ['delivered', 'rejected', 'cancelled']) {
        expect(
          isHiddenByOrderHistoryFrom(_order(s, createdAt: before), from),
          isTrue,
          reason: s,
        );
      }
    });

    test('санадан олдинги ФАОЛ буюртма кўринади', () {
      for (final s in ['new', 'accepted', 'ready', 'in_delivery', 'courier']) {
        expect(
          isHiddenByOrderHistoryFrom(_order(s, createdAt: before), from),
          isFalse,
          reason: s,
        );
      }
    });

    test('чегара: айнан шу сана ва ундан кейинги кўринади', () {
      expect(
        isHiddenByOrderHistoryFrom(_order('delivered', createdAt: from), from),
        isFalse,
      );
      expect(
        isHiddenByOrderHistoryFrom(_order('delivered', createdAt: after), from),
        isFalse,
      );
    });

    test('createdAt йўқ (serverTimestamp ҳали келмаган) — кўринади', () {
      expect(isHiddenByOrderHistoryFrom(_order('delivered'), from), isFalse);
    });
  });

  group('OrderHistoryFromBar', () {
    Future<void> pump(WidgetTester tester, DateTime? from) {
      return tester.pumpWidget(
        MaterialApp(home: Scaffold(body: OrderHistoryFromBar(from: from))),
      );
    }

    testWidgets('чегара йўқ — фақат «Санани танлаш»', (tester) async {
      await pump(tester, null);
      expect(find.textContaining('барча якунланган'), findsOneWidget);
      expect(find.text('Санани танлаш'), findsOneWidget);
      expect(find.text('Ҳаммасини кўрсатиш'), findsNothing);
    });

    testWidgets('чегара бор — сана ва «Ҳаммасини кўрсатиш»', (tester) async {
      await pump(tester, from);
      expect(find.textContaining('01.10.2026'), findsOneWidget);
      expect(find.text('Ўзгартириш'), findsOneWidget);
      expect(find.text('Ҳаммасини кўрсатиш'), findsOneWidget);
    });
  });
}
