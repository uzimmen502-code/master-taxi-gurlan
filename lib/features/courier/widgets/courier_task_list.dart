import 'package:flutter/material.dart';

import '../../../core/utils/user_error.dart';

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
  });

  final Future<List<T>> Function() load;
  final String emptyText;

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
                userErrorMessage(context, snap.error!,
                    fallbackKey: 'courier_error_generic'),
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
