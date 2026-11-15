/// «Ҳалқалар» лентасининг саҳифалаш ҳолати ([RingPager] устида) — Уй-жой / Улгуржи / Хитой экранлари учун
/// умумий (7-босқич, эга 2026-11-15). `MarketScreen` ичидаги оқим билан бир хил қоида:
///   * филтр ёки ҳудуд ўзгарса — [restart] (эски жавоблар `_gen` орқали ташланади);
///   * клиент филтри (қидирув/битим тури) кўринадиган элемент қўшмаган кетма-кет 3 саҳифадан кейин автоматик
///     юклаш тўхтайди — [needsManualMore], «Яна кўрсатиш» (чексиз ўқиш бўлмасин, 37-банд).
library;

import 'package:flutter/material.dart';

import '../l10n/l10n_extension.dart';
import '../../shared/widgets/load_error_view.dart';
import 'ring_query.dart';

class RingFeed<T> extends ChangeNotifier {
  RingFeed({this.pageSize = 20, this.tag = 'RingFeed'});

  final int pageSize;

  /// Лог учун (`[tag] RING_FEED_LOAD_FAILED …`).
  final String tag;

  RingPager<T>? _pager;
  final List<RingItem<T>> _items = [];
  bool _loading = false;
  Object? _error;
  int _emptyStreak = 0;
  int _gen = 0;
  bool _disposed = false;
  bool Function(T item) _visible = _all;

  static bool _all(Object? _) => true;

  List<RingItem<T>> get items => List.unmodifiable(_items);
  bool get loading => _loading;
  Object? get error => _error;
  bool get hasMore => _pager?.hasMore ?? false;
  bool get started => _pager != null;
  bool get needsManualMore => hasMore && _emptyStreak >= 3;

  /// Юкланган элементлар ичидан [test]га мослари (тартиб — ҳалқа, ичида сервер тартиби).
  List<T> visible() => [
        for (final r in _items)
          if (_visible(r.item)) r.item,
      ];

  /// Янги режа (ҳудуд/филтр ўзгарди). [visibleWhere] — клиент филтри (бўш саҳифа ҳисоби учун).
  void restart(RingPager<T> pager, {bool Function(T item)? visibleWhere}) {
    _gen++;
    _pager = pager;
    _items.clear();
    _error = null;
    _loading = false;
    _emptyStreak = 0;
    _visible = visibleWhere ?? _all;
    _notify();
    loadMore();
  }

  /// Клиент филтри ўзгарди (қидирув) — сервер сўрови қайта очилмайди.
  void setVisibleWhere(bool Function(T item)? test) {
    _visible = test ?? _all;
    _emptyStreak = 0;
    _notify();
  }

  void resetStreak() {
    _emptyStreak = 0;
    loadMore();
  }

  Future<void> loadMore() async {
    final pager = _pager;
    if (_loading || pager == null || !pager.hasMore || _disposed) return;
    final gen = _gen;
    _loading = true;
    _error = null;
    _notify();
    try {
      final page = await pager.next(pageSize);
      if (_disposed || gen != _gen) return;
      final added = page.where((r) => _visible(r.item)).length;
      _items.addAll(page);
      _loading = false;
      _emptyStreak = added == 0 ? _emptyStreak + 1 : 0;
      _notify();
    } catch (e) {
      debugPrint('[$tag] RING_FEED_LOAD_FAILED: $e');
      if (_disposed || gen != _gen) return;
      _loading = false;
      _error = e;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _gen++;
    super.dispose();
  }
}

/// Рўйхат охири: хато / юкланмоқда / «Яна кўрсатиш» / кейинги саҳифани автоматик сўраш.
class RingFeedFooter extends StatelessWidget {
  const RingFeedFooter({super.key, required this.feed, this.auto = true});

  final RingFeed<Object?> feed;

  /// `false` — кейинги саҳифа фақат тугма ёки ташқи айлантириш тинглагичи орқали (тўр кўринишида футер доим
  /// кўриниб туради — автоматик юклаш бутун Республикани ўқиб юборарди).
  final bool auto;

  @override
  Widget build(BuildContext context) {
    final err = feed.error;
    if (err != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: LoadErrorView(error: err, onRetry: feed.loadMore),
      );
    }
    if (feed.loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!feed.hasMore) return const SizedBox(height: 8);
    if (feed.needsManualMore || !auto) {
      return Center(
        child: TextButton(
          key: const ValueKey('ring_feed_load_more'),
          onPressed: feed.resetStreak,
          child: Text(context.tr('market_load_more')),
        ),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => feed.loadMore());
    return const SizedBox(height: 48);
  }
}
