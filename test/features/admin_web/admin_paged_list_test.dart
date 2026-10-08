import 'dart:async';

import 'package:ava_gurlan/features/admin_web/utils/admin_paged_list.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Яна юклаш» (эга, 2026-10-08) — admin рўйхати саҳифалари.
///
/// Firestore ўрнига хотирадаги «жонли» база: ҳар `watch` ойнаси
/// (startAfter / endAt / limit) база ўзгарганда қайта чиқарилади — Firestore
/// `snapshots()` каби. Тартиб: createdAt DESC, ID DESC.
class _Doc {
  _Doc(this.id, this.t);
  final String id;
  final int t;
  String status = 'pending';
}

/// a тартибда b дан олдин бўлса — манфий.
int _cmp(_Doc a, _Doc b) {
  if (a.t != b.t) return b.t.compareTo(a.t);
  return b.id.compareTo(a.id);
}

class _FakeDb {
  final docs = <_Doc>[];
  final opened = <AdminPageWindow<_Doc>>[];
  final _live = <(StreamController<List<_Doc>>, AdminPageWindow<_Doc>)>[];

  /// Шу ойна очилганда хато берилсин (бир марта).
  bool Function(AdminPageWindow<_Doc> w)? failOnce;

  int get activeListeners => _live.length;

  void add(_Doc d) {
    docs.add(d);
    _emitAll();
  }

  void remove(String id) {
    docs.removeWhere((d) => d.id == id);
    _emitAll();
  }

  void setStatus(String id, String status) {
    docs.firstWhere((d) => d.id == id).status = status;
    _emitAll();
  }

  List<_Doc> _window(AdminPageWindow<_Doc> w) {
    var list = docs.toList()..sort(_cmp);
    final after = w.startAfter;
    if (after != null) list = list.where((d) => _cmp(d, after) > 0).toList();
    final end = w.endAt;
    if (end != null) list = list.where((d) => _cmp(d, end) <= 0).toList();
    final limit = w.limit;
    if (limit != null && list.length > limit) list = list.sublist(0, limit);
    return list;
  }

  Stream<List<_Doc>> watch(AdminPageWindow<_Doc> w) {
    opened.add(w);
    late final StreamController<List<_Doc>> c;
    c = StreamController<List<_Doc>>(
      onListen: () {
        final fail = failOnce;
        if (fail != null && fail(w)) {
          failOnce = null;
          c.addError(StateError('permission-denied'));
          return;
        }
        _live.add((c, w));
        c.add(_window(w));
      },
      onCancel: () => _live.removeWhere((e) => identical(e.$1, c)),
    );
    return c.stream;
  }

  void _emitAll() {
    for (final (c, w) in _live.toList()) {
      c.add(_window(w));
    }
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

_FakeDb _seed(int n) {
  final db = _FakeDb();
  // t: 100, 99, ... — энг янгиси d00.
  for (var i = 0; i < n; i++) {
    db.docs.add(_Doc('d${i.toString().padLeft(2, '0')}', 100 - i));
  }
  return db;
}

AdminPagedList<_Doc, _Doc> _list(
  _FakeDb db, {
  int pageSize = 3,
  _Doc? Function(_Doc d)? map,
}) =>
    AdminPagedList<_Doc, _Doc>(
      watch: db.watch,
      map: map ?? (d) => d,
      idOf: (d) => d.id,
      pageSize: pageSize,
    );

List<String> _ids(AdminPagedList<_Doc, _Doc> l) =>
    l.items.map((d) => d.id).toList();

void main() {
  test('биринчи саҳифа: энг янги pageSize та, давоми бор', () async {
    final db = _seed(7);
    final list = _list(db);
    expect(list.isLoading, isTrue);
    await _settle();
    expect(list.isLoading, isFalse);
    expect(_ids(list), ['d00', 'd01', 'd02']);
    expect(list.hasMore, isTrue);
    list.dispose();
  });

  test('ҳужжатлар pageSize дан кам — тугма йўқ', () async {
    final db = _seed(2);
    final list = _list(db);
    await _settle();
    expect(_ids(list), ['d00', 'd01']);
    expect(list.hasMore, isFalse);
    list.dispose();
  });

  test('«Яна юклаш»: кейинги саҳифалар, тартиб сақланади, охирида тугма '
      'йўқолади', () async {
    final db = _seed(7);
    final list = _list(db);
    await _settle();

    list.loadMore();
    expect(list.loadingMore, isTrue);
    expect(list.hasMore, isTrue, reason: 'юкланаётганда тугма (спиннер) қолади');
    await _settle();
    expect(list.loadingMore, isFalse);
    expect(_ids(list), ['d00', 'd01', 'd02', 'd03', 'd04', 'd05']);
    expect(list.hasMore, isTrue);

    list.loadMore();
    await _settle();
    expect(_ids(list), ['d00', 'd01', 'd02', 'd03', 'd04', 'd05', 'd06']);
    expect(list.hasMore, isFalse);

    // Ҳар ойна бир марта очилган: биринчи саҳифа, унинг қотирилгани,
    // 2- ва 3-саҳифа. Лимитни ошириб ҳаммасини қайта ўқиш йўқ.
    expect(db.opened.length, 4);
    expect(db.opened[0].limit, 3);
    expect(db.opened[1].endAt?.id, 'd02');
    expect(db.opened[1].limit, isNull);
    expect(db.opened[2].startAfter?.id, 'd02');
    expect(db.opened[3].startAfter?.id, 'd05');
    // Эски (суриладиган) биринчи саҳифа ёпилган.
    expect(db.activeListeners, 3);
    list.dispose();
  });

  test('аниқ pageSize та бўлса: охирги «Яна юклаш» бўш — тугма йўқолади',
      () async {
    final db = _seed(3);
    final list = _list(db);
    await _settle();
    expect(list.hasMore, isTrue);
    list.loadMore();
    await _settle();
    expect(_ids(list), ['d00', 'd01', 'd02']);
    expect(list.hasMore, isFalse);
    list.dispose();
  });

  test('ТИРҚИШ ЙЎҚ: «Яна юклаш»дан кейин янги эълонлар келса, эскилари '
      'рўйхатдан тушиб қолмайди', () async {
    final db = _seed(7);
    final list = _list(db);
    await _settle();
    list.loadMore();
    await _settle();
    final before = _ids(list);

    db.add(_Doc('n1', 200));
    db.add(_Doc('n2', 201));
    await _settle();

    expect(_ids(list).take(2), ['n2', 'n1']);
    for (final id in before) {
      expect(_ids(list), contains(id), reason: '$id тушиб қолмасин');
    }
    expect(_ids(list).toSet().length, _ids(list).length);
    list.dispose();
  });

  test('бир хил вақтли ҳужжатлар саҳифа чегарасида тушмайди ва '
      'такрорланмайди', () async {
    final db = _FakeDb();
    for (final id in ['a', 'b', 'c', 'd', 'e']) {
      db.docs.add(_Doc(id, 50));
    }
    final list = _list(db, pageSize: 2);
    await _settle();
    while (list.hasMore) {
      list.loadMore();
      await _settle();
    }
    expect(_ids(list), ['e', 'd', 'c', 'b', 'a']);
    list.dispose();
  });

  test('ўчирилган ҳужжат йўқолади, саҳифа силжиса такрор чиқмайди',
      () async {
    final db = _seed(7);
    final list = _list(db);
    await _settle();
    list.loadMore();
    await _settle();
    list.loadMore();
    await _settle();

    db.remove('d04'); // 2-саҳифадан — у 3-саҳифанинг d06 сини олади
    await _settle();
    expect(_ids(list), ['d00', 'd01', 'd02', 'd03', 'd05', 'd06']);
    list.dispose();
  });

  test('эски саҳифадаги ҳолат ўзгариши ҳам жонли кўринади', () async {
    final db = _seed(7);
    final list = _list(db);
    await _settle();
    list.loadMore();
    await _settle();

    db.setStatus('d04', 'active');
    await _settle();
    expect(list.items.firstWhere((d) => d.id == 'd04').status, 'active');
    list.dispose();
  });

  test('map null қайтарса — рўйхатда йўқ, лекин саҳифа тўлиқлиги ҳужжатлар '
      'бўйича (бошқа бозорники)', () async {
    final db = _seed(7);
    final list = _list(db, map: (d) => d.t.isEven ? d : null);
    await _settle();
    expect(_ids(list), ['d00', 'd02']);
    expect(list.hasMore, isTrue);
    list.loadMore();
    await _settle();
    expect(_ids(list), ['d00', 'd02', 'd04']);
    list.dispose();
  });

  test('кейинги саҳифа хатоси: хабар, тугма қолади, қайта босилса юклайди',
      () async {
    final db = _seed(7)..failOnce = (w) => w.startAfter != null;
    final list = _list(db);
    await _settle();
    list.loadMore();
    await _settle();
    expect(list.loadMoreError, isNotNull);
    expect(list.loadingMore, isFalse);
    expect(list.hasMore, isTrue);
    expect(_ids(list), ['d00', 'd01', 'd02']);

    list.loadMore();
    await _settle();
    expect(list.loadMoreError, isNull);
    expect(_ids(list), ['d00', 'd01', 'd02', 'd03', 'd04', 'd05']);
    // Биринчи саҳифа бир марта қотирилган.
    expect(db.opened.where((w) => w.endAt != null).length, 1);
    list.dispose();
  });

  test('биринчи саҳифа хатоси — error', () async {
    final db = _seed(7)..failOnce = (w) => true;
    final list = _list(db);
    await _settle();
    expect(list.error, isNotNull);
    expect(list.isLoading, isFalse);
    list.dispose();
  });

  test('dispose — ҳамма тинглов ёпилади', () async {
    final db = _seed(7);
    final list = _list(db);
    await _settle();
    list.loadMore();
    await _settle();
    expect(db.activeListeners, greaterThan(0));
    list.dispose();
    await _settle();
    expect(db.activeListeners, 0);
  });

  test('юкланаётганда қайта босиш иккинчи саҳифа очмайди', () async {
    final db = _seed(7);
    final list = _list(db);
    await _settle();
    list
      ..loadMore()
      ..loadMore();
    await _settle();
    expect(db.opened.where((w) => w.startAfter != null).length, 1);
    list.dispose();
  });
}
