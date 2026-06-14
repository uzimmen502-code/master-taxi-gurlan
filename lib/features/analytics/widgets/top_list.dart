import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'package:intl/intl.dart';

import '../../../models/analytics/top_entity.dart';

/// Top-N рўйхати — горизонтал proportion полосалар билан.
class TopList extends StatelessWidget {
  const TopList({
    super.key,
    required this.items,
    this.color = AppColors.primary,
    this.maxItems = 10,
    this.formatValue,
  });

  final List<TopEntity> items;
  final Color color;
  final int maxItems;
  final String Function(num)? formatValue;

  static final _fmt = NumberFormat.decimalPattern('en');

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text('Маълумот йўқ',
            style: TextStyle(color: Colors.grey.shade400)),
      );
    }
    final shown = items.take(maxItems).toList();
    final maxV = shown.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    return Column(
      children: List.generate(shown.length, (i) {
        final e = shown[i];
        final pct = maxV == 0 ? 0.0 : (e.value / maxV).toDouble();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: i == 0
                        ? const Color(0xFFFFC107)
                        : color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: i == 0 ? Colors.white : color),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (e.icon != null) ...[
                  Text(e.icon!, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    e.label,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  formatValue != null
                      ? formatValue!(e.value)
                      : _fmt.format(e.value),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: color),
                ),
              ]),
              if (e.subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(left: 30, top: 2),
                  child: Text(e.subtitle!,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500)),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 30, top: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 4,
                    backgroundColor: color.withOpacity(0.08),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
