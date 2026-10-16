import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';

/// Курьер вазифалари рўйхати — callable'дан, pull-to-refresh билан
/// (гилам ва сут курьер экранлари).
///
/// Firestore оқими эмас: `carpet_wash_orders` / `agro_pickup_orders`
/// қоидаси capability курьерга рўйхат бермайди (`courier` `isStaff()`да йўқ —
/// D-SERVICE-4 / D-CLEAN-1) ва майдонларни кеса олмайди. Шунинг учун сервер
/// олишдан олдин фақат иш ҳажмини, олингандан кейин тўлиқ маълумотни
/// беради. Хато «вазифа йўқ» деб яширилмайди — аввалги StreamBuilder рад
/// жавобини бўш рўйхат қилиб кўрсатарди.
class CourierTaskList<T> extends StatefulWidget {
  const CourierTaskList({
    super.key,
    required this.load,
    required this.emptyText,
    required this.itemBuilder,
    this.autoRefresh = false,
    this.autoRefreshInterval = const Duration(seconds: 8),
  });

  final Future<List<T>> Function() load;
  final String emptyText;

  /// `true` — [autoRefreshInterval] да рўйхат ўзи янгиланади. Фақат мижоз
  /// тасдиғи кутилаётганда ёқилади (D2/D7): тасдиқ келгач вазифа ўзи ўтсин.
  final bool autoRefresh;
  final Duration autoRefreshInterval;

  /// [reload] — амалдан кейин (муваффақият ёки рад) рўйхатни янгилаш:
  /// вазифани бошқа курьер олиб улгурган ёки админ бекор қилган бўлиши мумкин.
  final Widget Function(
    BuildContext context,
    T item,
    Future<void> Function() reload,
  ) itemBuilder;

  @override
  State<CourierTaskList<T>> createState() => _CourierTaskListState<T>();
}

class _CourierTaskListState<T> extends State<CourierTaskList<T>> {
  late Future<List<T>> _items = widget.load();
  Timer? _timer;
  bool _reloading = false;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant CourierTaskList<T> old) {
    super.didUpdateWidget(old);
    _syncTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _syncTimer() {
    if (!widget.autoRefresh) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(widget.autoRefreshInterval, (_) async {
      if (!mounted || _reloading) return;
      _reloading = true;
      try {
        await _reload();
      } finally {
        _reloading = false;
      }
    });
  }

  Future<void> _reload() async {
    final next = widget.load();
    if (!mounted) return;
    setState(() {
      _items = next;
    });
    try {
      await next;
    } catch (_) {
      // Хато FutureBuilder'да кўрсатилади.
    }
  }

  /// Бўш ёки хато ҳолатда ҳам pull-to-refresh ишласин.
  Widget _refreshable(Widget child) {
    return RefreshIndicator(
      onRefresh: _reload,
      child: LayoutBuilder(
        builder: (context, constraints) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: constraints.maxHeight,
              child: Center(child: child),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<T>>(
      future: _items,
      builder: (context, snap) {
        // Қайта олишда эски рўйхат/хато кўриниб туради — спиннер фақат
        // биринчи юкланишда.
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData &&
            !snap.hasError) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _refreshable(
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                context
                    .tr('courier_error_generic')
                    .replaceAll('{error}', '${snap.error}'),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ),
          );
        }
        final items = snap.data ?? const [];
        if (items.isEmpty) {
          return _refreshable(
            Text(widget.emptyText, style: TextStyle(color: Colors.grey.shade600)),
          );
        }
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) =>
                widget.itemBuilder(context, items[i], _reload),
          ),
        );
      },
    );
  }
}
