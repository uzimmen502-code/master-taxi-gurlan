// Етказилган буюртмадаги таомларни баҳолаш карточкаси (D-REST-18).
//
// Мижоз ҳар таомга 1–5 юлдуз қўяди ва БИРГА юборади. Баҳолаш муддати — етказилгандан кейин
// 30 дақиқа (эга: «қўйилса қўйилди, бўлмаса йўқ»): муддат ўтса ҳали баҳоланмаган таомлар
// яширилади, баҳоланганлари қулфланган ҳолда кўрсатилади. Сервер баҳони ўзгартирмайди: бир марта
// юборилган таом қулфланади (`order.dishRatings`). Қоида ва текширув — серверда
// (`submitDishRatings`); бу ерда фақат UI (44-қоида).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/order_model.dart';
import '../domain/dish_stats.dart';

class DishRatingCard extends StatefulWidget {
  const DishRatingCard({super.key, required this.order, required this.onSubmit, this.busy = false, this.clock});

  final OrderModel order;

  /// Танланган баҳолар (`itemId → 1..5`) — фақат ҳали баҳоланмаган таомлар.
  /// `true` — сақланди; `false` — хато (танлов сақланиб қолади, қайта юбориш мумкин).
  final Future<bool> Function(Map<String, int> stars) onSubmit;
  final bool busy;

  /// Тест учун соат; бўш бўлса ҳақиқий вақт.
  final DateTime Function()? clock;

  @override
  State<DishRatingCard> createState() => _DishRatingCardState();
}

class _DishRatingCardState extends State<DishRatingCard> {
  final Map<String, int> _picked = {};
  Timer? _tick;

  DateTime get _now => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    // Муддат тугашини кутиб ўтирган экранда карточка ўзи ўзгарсин (ҳар 20 сония).
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Баҳоланадиган таомлар: идентификатори бор, такрорсиз, буюртма тартибида.
  List<OrderItem> get _items {
    final seen = <String>{};
    return [
      for (final it in widget.order.items)
        if (it.itemId.isNotEmpty && seen.add(it.itemId)) it,
    ];
  }

  Map<String, int> get _pending {
    final saved = widget.order.dishRatings;
    return {
      for (final e in _picked.entries)
        if (!saved.containsKey(e.key)) e.key: e.value,
    };
  }

  Future<void> _submit() async {
    final stars = _pending;
    if (stars.isEmpty) return;
    final ok = await widget.onSubmit(stars);
    if (ok && mounted) setState(_picked.clear);
  }

  @override
  Widget build(BuildContext context) {
    final saved = widget.order.dishRatings;
    final left = dishRatingTimeLeft(widget.order.deliveredAt, _now);
    final open = left > Duration.zero;
    // Муддат ўтган: фақат баҳоланганлари (қулфланган) қолади.
    final items = [for (final it in _items) if (open || saved.containsKey(it.itemId)) it];
    if (items.isEmpty) return const SizedBox.shrink();
    final c = context.ava;
    final allRated = items.every((it) => saved.containsKey(it.itemId));
    final canSubmit = open && !allRated;
    final pending = _pending;
    final minutes = (left.inSeconds / 60).ceil();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Column(
        key: const Key('dish-rating-card'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr(canSubmit ? 'restaurants_rate_title' : 'restaurants_rate_saved'),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink),
          ),
          if (canSubmit) ...[
            const SizedBox(height: 2),
            Text(context.tr('restaurants_rate_hint'), style: TextStyle(fontSize: 12, color: c.ink2)),
            const SizedBox(height: 2),
            Text(
              context.tr('restaurants_rate_left').replaceAll('{min}', '$minutes'),
              key: const Key('dish-rating-left'),
              style: TextStyle(fontSize: 12, color: minutes <= 5 ? c.warn : c.ink2),
            ),
          ],
          const SizedBox(height: 8),
          for (final it in items)
            _DishRow(
              item: it,
              stars: saved[it.itemId] ?? _picked[it.itemId] ?? 0,
              locked: saved.containsKey(it.itemId),
              enabled: !widget.busy,
              onPick: (n) => setState(() => _picked[it.itemId] = n),
            ),
          if (canSubmit) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('dish-rating-submit'),
                onPressed: widget.busy || pending.isEmpty ? null : _submit,
                child: Text(context.tr('restaurants_rate_submit')),
              ),
            ),
            if (pending.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(context.tr('restaurants_rate_pick'), style: TextStyle(fontSize: 12, color: c.ink2)),
              ),
          ],
        ],
      ),
    );
  }
}

class _DishRow extends StatelessWidget {
  const _DishRow({required this.item, required this.stars, required this.locked, required this.enabled, required this.onPick});

  final OrderItem item;
  final int stars;
  final bool locked;
  final bool enabled;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.name, style: TextStyle(fontSize: 13, color: c.ink)),
          Row(
            children: [
              for (var n = 1; n <= 5; n++)
                Semantics(
                  button: !locked,
                  selected: n == stars,
                  label: context.tr('restaurants_rate_star').replaceAll('{n}', '$n'),
                  child: InkResponse(
                    key: Key('dish-star-${item.itemId}-$n'),
                    onTap: locked || !enabled ? null : () => onPick(n),
                    radius: 22,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(
                        n <= stars ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 30,
                        color: n <= stars ? (locked ? c.ink3 : c.brand) : c.ink3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
