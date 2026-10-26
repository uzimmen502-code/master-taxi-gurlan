import 'dart:async';

import 'package:ava_gurlan/core/utils/lazy_broadcast.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Хабарлар» чексиз «загрузка» (аудит X-01, 2026-10-26) регрессия тести: манба обунадан ОЛДИН дарров жавоб
/// берса ҳам (Firestore кеши), биринчи қиймат обуначига етиб боради.
void main() {
  test('эски усул (eager broadcast) — обунадан олдинги қиймат йўқолади: тест X-01 ни ҳақиқатан ушлайди', () async {
    final source = StreamController<int>.broadcast(sync: true);
    final eager = StreamController<int>.broadcast();
    source.stream.listen(eager.add); // оқим яратилган заҳоти очилган тингловчи (аввалги код)
    source.add(1); // кешдан тезкор жавоб — ҳали обуначи йўқ
    await Future<void>.delayed(Duration.zero);
    final got = <int>[];
    eager.stream.listen(got.add); // StreamBuilder кейинги кадрда обуна бўлади
    await Future<void>.delayed(Duration.zero);
    expect(got, isEmpty, reason: 'шу сабабли экран абадий загрузкада қоларди');
  });

  test('lazyBroadcastStream — манба фақат обунада очилади, биринчи қиймат етиб боради', () async {
    var started = 0;
    final s = lazyBroadcastStream<int>((c) {
      started++;
      c.add(42); // манба дарров жавоб берди (кеш)
      return const [];
    });
    await Future<void>.delayed(const Duration(milliseconds: 20)); // экран оқимни яратди, обуна кечикди
    expect(started, 0, reason: 'обуначи йўқ — Firestore тингловчиси очилмайди');
    final got = <int>[];
    final sub = s.listen(got.add);
    await Future<void>.delayed(Duration.zero);
    expect(started, 1);
    expect(got, [42]);
    await sub.cancel();
  });

  test('обуна бекор бўлса манбалар ёпилади; қайта обунада яна очилади («ўлик» оқим йўқ)', () async {
    final sources = <StreamController<int>>[];
    final s = lazyBroadcastStream<int>((c) {
      final src = StreamController<int>();
      sources.add(src);
      return [src.stream.listen(c.add)];
    });
    final got = <int>[];
    final a = s.listen(got.add);
    sources.last.add(1);
    await Future<void>.delayed(Duration.zero);
    await a.cancel();
    expect(sources.single.hasListener, isFalse, reason: 'бекор қилишда манба тингловчиси ёпилди');

    final b = s.listen(got.add);
    expect(sources, hasLength(2), reason: 'қайта обунада манба янгидан очилди');
    sources.last.add(2);
    await Future<void>.delayed(Duration.zero);
    expect(got, [1, 2]);
    await b.cancel();
  });

  test('манба хатоси обуначига етиб боради (spinner ўрнига хато ҳолати)', () async {
    final s = lazyBroadcastStream<int>((c) {
      c.addError(StateError('permission-denied'));
      return const [];
    });
    final errors = <Object>[];
    final sub = s.listen((_) {}, onError: errors.add);
    await Future<void>.delayed(Duration.zero);
    expect(errors, hasLength(1));
    await sub.cancel();
  });
}
