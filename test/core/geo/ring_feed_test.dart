import 'dart:async';

import 'package:ava_gurlan/core/geo/ring_feed.dart';
import 'package:ava_gurlan/core/geo/ring_query.dart';
import 'package:flutter_test/flutter_test.dart';

/// Эга 2026-11-19 (тезлик): RingFeed биринчи саҳифани ҳалқама-ҳалқа чизади (ҳар бўш бўлмаган ҳалқадан кейин
/// хабар), жами [RingFeed.pageSize] гача шу юклаш ичида; кейинги саҳифалар аввалгидек.
void main() {
  final data = {
    'gurlan': ['g1'],
    'urganch': ['u1', 'u2'],
    'nukus': ['n1', 'n2', 'n3'],
  };
  final regions = {
    'xorazm': ['gurlan', 'urganch'],
    'qoraqalpogiston': ['nukus'],
  };

  RingPager<String> pager({Completer<void>? holdRing1}) => RingPager<String>(
        plan: buildRingPlan(userDistrictId: 'gurlan', userRegionId: 'xorazm'),
        districtsOf: (r) async => regions[r] ?? const [],
        fetch: (ids, after, limit) async {
          if (ids.contains('urganch') && holdRing1 != null) await holdRing1.future;
          final all = [for (final d in ids) ...data[d] ?? const <String>[]];
          final start = after == null ? 0 : (after as int) + 1;
          final page = all.skip(start).take(limit).toList();
          return RingFetchResult(page, page.isEmpty ? after : start + page.length - 1);
        },
      );

  test('биринчи ҳалқа келиши билан кўринади; pageSize гача давом этади; тартиб ва такрорсизлик', () async {
    final hold = Completer<void>();
    final feed = RingFeed<String>(pageSize: 4);
    final snapshots = <List<String>>[];
    feed.addListener(() => snapshots.add([for (final r in feed.items) r.item]));
    feed.restart(pager(holdRing1: hold));
    await pumpEventQueue();
    // ring 1 ҳали кутмоқда — ring 0 аллақачон кўринади, юклаш давом этмоқда.
    expect(feed.items.map((r) => r.item), ['g1']);
    expect(feed.loading, isTrue);
    hold.complete();
    await pumpEventQueue();
    expect(feed.items.map((r) => r.item), ['g1', 'u1', 'u2', 'n1']);
    expect(feed.items.map((r) => r.ring), [0, 1, 1, 2]);
    expect(feed.loading, isFalse);
    expect(snapshots.any((s) => s.length == 1 && s.single == 'g1'), isTrue, reason: 'оралиқ чизиш бўлди');

    await feed.loadMore();
    expect(feed.items.map((r) => r.item), ['g1', 'u1', 'u2', 'n1', 'n2', 'n3']);
    expect(feed.hasMore, isFalse);
    feed.dispose();
  });

  test('restart оралиқ жавобни ташлайди (эски режа)', () async {
    final hold = Completer<void>();
    final feed = RingFeed<String>(pageSize: 4);
    feed.restart(pager(holdRing1: hold));
    await pumpEventQueue();
    feed.restart(pager());
    hold.complete();
    await pumpEventQueue();
    expect(feed.items.map((r) => r.item), ['g1', 'u1', 'u2', 'n1']);
    feed.dispose();
  });
}
