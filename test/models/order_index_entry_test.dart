import 'dart:io';

import 'package:ava_gurlan/models/order_index_entry.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Барча буюртмалар» модели (D-ALL-1…11).
void main() {
  final t0 = DateTime.utc(2026, 10, 12, 5);

  OrderIndexEntry entry({DateTime? stuckAt, bool fin = false, DateTime? since}) =>
      OrderIndexEntry.fromMap('bread_o1', {
        'module': 'bread',
        'sourceCollection': 'orders',
        'sourceId': 'o1',
        'normStatus': fin ? 'DELIVERED' : 'NEW',
        'stage': fin ? 'done' : 'new',
        'rawStatus': fin ? 'delivered' : 'new',
        'final': fin,
        'amount': 8000,
        'customerTail': '4567',
        if (stuckAt != null) 'stuckAt': Timestamp.fromDate(stuckAt),
        if (since != null) 'stageSince': Timestamp.fromDate(since),
      });

  group('isStuck — чегаралар', () {
    test('айнан stuckAt пайтида — тиқилиб қолган (чегара киради)', () {
      expect(entry(stuckAt: t0).isStuck(t0), isTrue);
    });
    test('бир сония олдин — ҳали эмас', () {
      expect(entry(stuckAt: t0).isStuck(t0.subtract(const Duration(seconds: 1))), isFalse);
    });
    test('якунланган буюртма ҳеч қачон тиқилиб қолмайди', () {
      expect(entry(stuckAt: t0, fin: true).isStuck(t0.add(const Duration(days: 9))), isFalse);
    });
    test('чегараси йўқ (stuckAt null) — тиқилиб қолмайди', () {
      expect(entry().isStuck(t0), isFalse);
      expect(entry().overdueBy(t0), isNull);
    });
    test('кечикиш ва ҳолатда турган вақт', () {
      final e = entry(stuckAt: t0, since: t0.subtract(const Duration(minutes: 15)));
      final now = t0.add(const Duration(minutes: 42));
      expect(e.overdueBy(now), const Duration(minutes: 42));
      expect(e.inStageFor(now), const Duration(minutes: 57));
    });
  });

  test('fromMap: майдонлар ва ёрлиқлар', () {
    final e = entry();
    expect(e.moduleLabel, 'Нон');
    expect(e.statusLabel, 'Янги');
    expect(e.amount, 8000);
    expect(e.customerTail, '4567');
    expect(e.managedInSection, 'Буюртмалар → Доска');
  });

  test('formatAge', () {
    expect(formatAge(const Duration(minutes: 42)), '42 дақ');
    expect(formatAge(const Duration(hours: 3, minutes: 5)), '3 соат 5 дақ');
    expect(formatAge(const Duration(hours: 2)), '2 соат');
    expect(formatAge(const Duration(days: 2, hours: 4)), '2 кун 4 соат');
    expect(formatAge(const Duration(minutes: -3)), '0 дақ');
  });

  test('ҳар бир ягона ҳолатнинг ёрлиғи бор', () {
    for (final s in OrderIndexEntry.statusOrder) {
      expect(OrderIndexEntry.statusLabels.containsKey(s), isTrue, reason: s);
    }
  });

  test('паритет: сервердаги ҳар бир босқич ва модулнинг ёрлиғи бор', () {
    // Ягона манба — functions/order_index.js. Серверга янги босқич қўшилса,
    // бу ерда ёрлиғи ёзилмаса экранда хом калит чиқарди.
    final src = File('functions/order_index.js').readAsStringSync();
    final stages = RegExp(r"\[NORM\.[A-Z_]+,\s*'([a-z_]+)'\]")
        .allMatches(src)
        .map((m) => m.group(1)!)
        .toSet();
    expect(stages, isNotEmpty);
    final missing = stages.where((s) => !OrderIndexEntry.stageLabels.containsKey(s)).toList();
    expect(missing, isEmpty, reason: 'stageLabels да йўқ: $missing');

    final modules = RegExp(r"module: '([a-z]+)'")
        .allMatches(src)
        .map((m) => m.group(1)!)
        .toSet()
      ..addAll(['wholesale', 'bread']); // тернар ифода ичида
    final missingMod = modules.where((m) => !OrderIndexEntry.moduleLabels.containsKey(m)).toList();
    expect(missingMod, isEmpty, reason: 'moduleLabels да йўқ: $missingMod');
  });
}
