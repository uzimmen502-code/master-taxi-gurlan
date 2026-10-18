import 'dart:async';

import 'package:ava_gurlan/features/home/controllers/home_unread_badge.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Хабарлар» таби белгиси: оқим уланиши, аудитория, қайта улаш.
class _Fake {
  final calls = <({String uid, List<String> audiences})>[];
  final controllers = <StreamController<int>>[];
  String role = 'user';

  Stream<int> watch({required String userId, required List<String> audiences}) {
    calls.add((uid: userId, audiences: audiences));
    final c = StreamController<int>();
    controllers.add(c);
    return c.stream;
  }

  Future<String> audience() async => role;

  HomeUnreadBadge make() => HomeUnreadBadge(watch: watch, audience: audience);
}

void main() {
  test('телефон бор — оқим уланади, аудитория [all, роль], сон янгиланади', () async {
    final f = _Fake()..role = 'driver';
    final b = f.make();
    var notified = 0;
    b.addListener(() => notified++);

    await b.sync('+998 90 123 45 67');
    expect(f.calls, hasLength(1));
    expect(f.calls.single.uid, '998901234567');
    expect(f.calls.single.audiences, ['all', 'driver']);

    f.controllers.single.add(3);
    await Future<void>.delayed(Duration.zero);
    expect(b.total, 3);
    expect(notified, 1);

    b.dispose();
  });

  test('бир хил телефон+роль — қайта чақирилса янги тингловчи очилмайди', () async {
    final f = _Fake();
    final b = f.make();
    await b.sync('998901234567');
    await b.sync('998901234567');
    await b.sync('+998901234567');
    expect(f.calls, hasLength(1));
    b.dispose();
  });

  test('роль ўзгарса (ҳайдовчи ҳуқуқи келди) — оқим қайта уланади, эскиси ёпилади', () async {
    final f = _Fake();
    final b = f.make();
    await b.sync('998901234567');
    f.role = 'driver';
    await b.sync('998901234567');

    expect(f.calls, hasLength(2));
    expect(f.calls.last.audiences, ['all', 'driver']);
    expect(f.controllers.first.hasListener, isFalse, reason: 'эски тингловчи ёпилиши шарт');
    expect(f.controllers.last.hasListener, isTrue);
    b.dispose();
  });

  test('телефон йўқ/қисқа — оқим очилмайди, сон 0 га тушади', () async {
    final f = _Fake();
    final b = f.make();
    await b.sync('998901234567');
    f.controllers.single.add(5);
    await Future<void>.delayed(Duration.zero);
    expect(b.total, 5);

    await b.sync('');
    expect(b.total, 0);
    expect(f.controllers.single.hasListener, isFalse);

    final g = _Fake();
    final c = g.make();
    await c.sync('12345');
    expect(g.calls, isEmpty);
    b.dispose();
    c.dispose();
  });

  test('оқим хатоси — охирги сон қолади, илова йиқилмайди', () async {
    final f = _Fake();
    final b = f.make();
    await b.sync('998901234567');
    f.controllers.single.add(2);
    await Future<void>.delayed(Duration.zero);
    f.controllers.single.addError(StateError('permission-denied'));
    await Future<void>.delayed(Duration.zero);
    expect(b.total, 2);
    b.dispose();
  });

  test('бир хил сон — қайта хабар берилмайди (ортиқча rebuild йўқ)', () async {
    final f = _Fake();
    final b = f.make();
    var notified = 0;
    b.addListener(() => notified++);
    await b.sync('998901234567');
    f.controllers.single
      ..add(4)
      ..add(4)
      ..add(4);
    await Future<void>.delayed(Duration.zero);
    expect(notified, 1);
    b.dispose();
  });

  test('иккита sync пойгаси: кейингиси ғолиб, эскиси оқим очмайди', () async {
    final f = _Fake();
    final slow = Completer<String>();
    var n = 0;
    final b = HomeUnreadBadge(
      watch: f.watch,
      audience: () => (n++ == 0) ? slow.future : Future.value('driver'),
    );
    final first = b.sync('998901234567'); // секин аудитория ('user' келади)
    await b.sync('998901234567'); // тез ('driver')
    slow.complete('user');
    await first;

    expect(f.calls, hasLength(1));
    expect(f.calls.single.audiences, ['all', 'driver']);
    b.dispose();
  });

  test('dispose дан кейин келган натижа ҳеч нарса қилмайди', () async {
    final f = _Fake();
    final slow = Completer<String>();
    final b = HomeUnreadBadge(watch: f.watch, audience: () => slow.future);
    final pending = b.sync('998901234567');
    b.dispose();
    slow.complete('user');
    await pending;
    expect(f.calls, isEmpty);
  });
}
