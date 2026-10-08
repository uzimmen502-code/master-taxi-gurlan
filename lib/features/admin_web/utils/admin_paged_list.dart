import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Бир саҳифанинг чегаралари. Firestore'да — `startAfterDocument`,
/// `endAtDocument`, `limit` ([watchFirestoreWindow]).
@immutable
class AdminPageWindow<D> {
  const AdminPageWindow({this.startAfter, this.endAt, this.limit});

  final D? startAfter;
  final D? endAt;
  final int? limit;
}

typedef AdminDoc = QueryDocumentSnapshot<Map<String, dynamic>>;

/// Firestore'даги admin рўйхати.
typedef AdminFirestorePagedList<T> = AdminPagedList<AdminDoc, T>;

/// [base] сўровини [window] чегараси билан жонли тинглаш. [base] да
/// `orderBy` бўлиши шарт — курсор шу тартиб (ва ҳужжат ID) бўйича ишлайди.
Stream<List<AdminDoc>> watchFirestoreWindow(
  Query<Map<String, dynamic>> base,
  AdminPageWindow<AdminDoc> window,
) {
  var q = base;
  final after = window.startAfter;
  if (after != null) q = q.startAfterDocument(after);
  final end = window.endAt;
  if (end != null) q = q.endAtDocument(end);
  final limit = window.limit;
  if (limit != null) q = q.limit(limit);
  return q.snapshots().map((s) => s.docs);
}

/// Admin рўйхати: аввал [pageSize] та, «Яна юклаш» билан кейингилари
/// (эга, 2026-10-08 — лимитни катталаштириш ўрнига).
///
/// Ҳамма саҳифа ЖОНЛИ (тасдиқ/рад/ўчириш карточкада дарҳол кўринади) ва
/// ҳар саҳифа бир марта очилади. Лимитни ошириб қайта сўраш эса ҳар
/// босишда бутун рўйхатни бошидан қайта ўқирди.
///
/// ТИРҚИШ БЎЛМАСИН: биринчи саҳифа — «энг янги [pageSize] та», ойнаси
/// суриладиган. Янги эълон келса, ойнанинг охиргиси тушиб қолади, кейинги
/// саҳифа эса ўша охиргидан КЕЙИН бошланган — тушган эълон ҳеч қаерда
/// кўринмай қоларди. Шунинг учун биринчи «Яна юклаш»да биринчи саҳифа
/// `endAt(охиргиси)` билан қайта очилади: чегара қотади, янгилари юқоридан
/// қўшилаверади. Нархи — бир марта [pageSize] ўқиш. Кейинги саҳифаларга
/// янги эълон тушмайди (улар эскироқ); ҳужжат ўчирилса саҳифа кейингисидан
/// биттасини олади — такрори [idOf] бўйича олиб ташланади.
class AdminPagedList<D, T> extends ChangeNotifier {
  AdminPagedList({
    required Stream<List<D>> Function(AdminPageWindow<D> window) watch,
    required T? Function(D doc) map,
    required String Function(T item) idOf,
    this.pageSize = 500,
  })  : assert(pageSize > 0),
        _watch = watch,
        _map = map,
        _idOf = idOf {
    _openPage(_Page<D>(AdminPageWindow<D>(limit: pageSize)));
  }

  final int pageSize;
  final Stream<List<D>> Function(AdminPageWindow<D>) _watch;

  /// `null` қайтарса — ҳужжат рўйхатга кирмайди (масалан бошқа бозорники).
  /// Саҳифа тўлиқлиги эса барибир ҳужжатлар сони бўйича ҳисобланади.
  final T? Function(D) _map;
  final String Function(T) _idOf;

  final _pages = <_Page<D>>[];
  StreamSubscription<List<D>>? _pendingFirst;
  bool _loadingMore = false;
  bool _disposed = false;
  Object? _error;
  Object? _loadMoreError;
  List<T>? _items;

  /// Биринчи саҳифа ҳали келмаган.
  bool get isLoading => _error == null && !_pages.first.loaded;

  /// Биринчи саҳифа хатоси (масалан рухсат йўқ) — рўйхат кўрсатилмайди.
  Object? get error => _error;

  /// Охирги «Яна юклаш» муваффақиятсиз — тугма қайта босилса яна уринади.
  Object? get loadMoreError => _loadMoreError;

  bool get loadingMore => _loadingMore;

  /// «Яна юклаш» тугмаси кўрсатилсинми.
  bool get hasMore {
    if (_loadingMore) return true;
    final last = _pages.last;
    return last.loaded && last.mayHaveMore && last.docs.isNotEmpty;
  }

  /// Ҳамма юкланган саҳифалар, янгиси биринчи, такрорсиз.
  List<T> get items => _items ??= _collect();

  List<T> _collect() {
    final seen = <String>{};
    final out = <T>[];
    for (final page in _pages) {
      for (final doc in page.docs) {
        final item = _map(doc);
        if (item != null && seen.add(_idOf(item))) out.add(item);
      }
    }
    return List.unmodifiable(out);
  }

  void loadMore() {
    if (_disposed || _loadingMore || !hasMore) return;
    final cursor = _pages.last.docs.last;
    _loadingMore = true;
    _loadMoreError = null;
    if (_pages.length == 1 &&
        _pages.first.window.endAt == null &&
        _pendingFirst == null) {
      _boundFirstPage(cursor);
    }
    _openPage(
      _Page<D>(AdminPageWindow<D>(startAfter: cursor, limit: pageSize)),
    );
    _changed();
  }

  void _openPage(_Page<D> page) {
    _pages.add(page);
    page.sub = _watch(page.window).listen(
      (docs) => _onData(page, docs),
      onError: (Object e, StackTrace _) => _onError(page, e),
    );
  }

  /// Биринчи саҳифани `endAt(cursor)` билан қайта очиш. Эски обуна янгиси
  /// биринчи маълумотни бергунча ишлайверади — рўйхат бўшаб қолмайди.
  void _boundFirstPage(D cursor) {
    final first = _pages.first;
    final window = AdminPageWindow<D>(endAt: cursor);
    late final StreamSubscription<List<D>> sub;
    sub = _watch(window).listen(
      (docs) {
        if (identical(_pendingFirst, sub)) {
          _pendingFirst = null;
          first.sub?.cancel();
          first
            ..sub = sub
            ..window = window;
        }
        _onData(first, docs);
      },
      onError: (Object e, StackTrace _) {
        if (identical(_pendingFirst, sub)) {
          // Эски (суриладиган) обуна ишлайверади.
          _pendingFirst = null;
          _loadMoreError = e;
          _changed();
          return;
        }
        _onError(first, e);
      },
    );
    _pendingFirst = sub;
  }

  void _onData(_Page<D> page, List<D> docs) {
    if (!_pages.contains(page)) return;
    page
      ..docs = docs
      ..loaded = true;
    if (_loadingMore && identical(page, _pages.last)) _loadingMore = false;
    _changed();
  }

  void _onError(_Page<D> page, Object e) {
    if (!_pages.contains(page)) return;
    if (identical(page, _pages.first)) {
      _error = e;
    } else {
      // Саҳифа олиб ташланади — тугма қайта босилса шу ердан яна уринади.
      page.sub?.cancel();
      _pages.remove(page);
      _loadMoreError = e;
      _loadingMore = false;
    }
    debugPrint('[AdminPagedList] ADMIN_LIST_PAGE_FAILED $e');
    _changed();
  }

  void _changed() {
    _items = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pendingFirst?.cancel();
    for (final page in _pages) {
      page.sub?.cancel();
    }
    super.dispose();
  }
}

class _Page<D> {
  _Page(this.window);

  AdminPageWindow<D> window;
  List<D> docs = const [];
  bool loaded = false;
  StreamSubscription<List<D>>? sub;

  /// `limit` ли саҳифа тўлса — давоми бўлиши мумкин. `endAt` билан
  /// қотирилган биринчи саҳифанинг давоми бор (шунинг учун қотирилган).
  bool get mayHaveMore {
    final limit = window.limit;
    return limit == null || docs.length >= limit;
  }
}
