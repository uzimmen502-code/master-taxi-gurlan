import 'dart:async';

import 'package:ava_gurlan/features/admin_web/screens/admin_all_orders_screen.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_all_orders_service.dart';
import 'package:ava_gurlan/models/order_index_entry.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 12, 12, 0);

OrderIndexEntry _e(String id, String module, String status, {DateTime? stuckAt, DateTime? since}) =>
    OrderIndexEntry.fromMap('${module}_$id', {
      'module': module,
      'sourceCollection': 'orders',
      'sourceId': id,
      'normStatus': status,
      'stage': 'new',
      'rawStatus': 'new',
      'amount': 12000,
      'customerTail': '4567',
      if (stuckAt != null) 'stuckAt': Timestamp.fromDate(stuckAt),
      if (since != null) 'stageSince': Timestamp.fromDate(since),
    });

class _FakeSource implements AllOrdersSource {
  final watchCalls = <(AllOrdersFilter, int)>[];
  final searchCalls = <String>[];
  Object? error;
  List<OrderIndexEntry> items = [
    _e('ord1', 'bread', 'NEW',
        stuckAt: _now.subtract(const Duration(minutes: 18)),
        since: _now.subtract(const Duration(minutes: 33))),
    _e('ord2', 'carpet', 'ACCEPTED'),
  ];

  @override
  Stream<List<OrderIndexEntry>> watch(AllOrdersFilter filter, int limit) {
    watchCalls.add((filter, limit));
    if (error != null) return Stream.error(error!);
    final list = filter.stuckOnly ? items.where((e) => e.isStuck(_now)).toList() : items;
    return Stream.value(list);
  }

  @override
  Future<AllOrdersCounts> counts(AllOrdersFilter filter, DateTime now) async =>
      const AllOrdersCounts(byStatus: {'NEW': 3, 'ACCEPTED': 1}, stuck: 1);

  @override
  Future<List<OrderIndexEntry>> search(String query) async {
    searchCalls.add(query);
    return [items.first];
  }
}

Future<_FakeSource> _pump(WidgetTester tester, [_FakeSource? src]) async {
  final s = src ?? _FakeSource();
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: AdminAllOrdersScreen(source: s, clock: () => _now)),
  ));
  await tester.pumpAndSettle();
  return s;
}

void main() {
  testWidgets('рўйхат ва ҳисоблагичлар; тиқилиб қолган қатор белгиланади', (tester) async {
    await _pump(tester);
    expect(find.text('Янги: 3'), findsOneWidget);
    expect(find.text('Тиқилиб қолган: 1'), findsOneWidget);
    expect(find.textContaining('Нон · #ord1'), findsOneWidget);
    expect(find.textContaining('Гилам ювиш · #ord2'), findsOneWidget);
    expect(find.text('⚠ 18 дақ кечикди'), findsOneWidget);
    expect(find.text('33 дақ'), findsOneWidget);
  });

  testWidgets('«Тиқилиб қолган» чипи — stuckOnly фильтр, ҳолат фильтри тушади', (tester) async {
    final s = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('count_NEW')));
    await tester.pumpAndSettle();
    expect(s.watchCalls.last.$1.status, 'NEW');
    await tester.tap(find.byKey(const ValueKey('count_stuck')));
    await tester.pumpAndSettle();
    expect(s.watchCalls.last.$1.stuckOnly, isTrue);
    expect(s.watchCalls.last.$1.status, isNull);
    expect(find.textContaining('#ord2'), findsNothing);
  });

  testWidgets('rebuild янги listener очмайди (оқим кешланган)', (tester) async {
    final s = await _pump(tester);
    final before = s.watchCalls.length;
    // Фильтр ўзгармаган ҳолда бир неча rebuild.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(s.watchCalls.length, before);
  });

  testWidgets('қидирув: охирги 4 рақам — search() чақирилади', (tester) async {
    final s = await _pump(tester);
    await tester.enterText(find.byKey(const ValueKey('search_field')), '4567');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(s.searchCalls, ['4567']);
    expect(find.textContaining('#ord1'), findsOneWidget);
  });

  testWidgets('тафсилот — фақат кўриш (ҳаракат тугмаси йўқ)', (tester) async {
    await _pump(tester);
    await tester.tap(find.textContaining('Нон · #ord1'));
    await tester.pumpAndSettle();
    expect(find.text('Нон буюртмаси'), findsOneWidget);
    expect(find.textContaining('Бу ерда фақат кўриш'), findsOneWidget);
    expect(find.text('…4567'), findsOneWidget);
    expect(find.text('Тиқилиб қолди'), findsOneWidget);
    // Диалогда фақат «Ёпиш».
    final dialogButtons = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextButton));
    expect(dialogButtons, findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('рухсат йўқ (permission-denied) — тушунарли хабар', (tester) async {
    final s = _FakeSource()..error = Exception('[cloud_firestore/permission-denied] Missing or insufficient permissions.');
    await _pump(tester, s);
    expect(find.textContaining('Бу бўлимга рухсатингиз йўқ'), findsOneWidget);
  });
}
