import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

import '../../../models/analytics/segment.dart';

/// Donut/Pie диаграмма — улушлар + жами марказда.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.breakdown,
    this.size = 180,
    this.centerLabel,
  });

  final SegmentBreakdown breakdown;
  final double size;
  final String? centerLabel;

  @override
  Widget build(BuildContext context) {
    final total = breakdown.total;
    if (total == 0) {
      return SizedBox(
        height: size,
        child: Center(
          child: Text('Маълумот йўқ',
              style: TextStyle(color: Colors.grey.shade400)),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(alignment: Alignment.center, children: [
            PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: size * 0.3,
                startDegreeOffset: -90,
                sections: breakdown.segments
                    .where((s) => s.value > 0)
                    .map((s) => PieChartSectionData(
                          value: s.value.toDouble(),
                          color: s.color ?? AppColors.primary,
                          radius: size * 0.28,
                          title: '',
                          showTitle: false,
                        ))
                    .toList(),
              ),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                total.toString(),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                centerLabel ?? 'Жами',
                style:
                    TextStyle(fontSize: 10, color: Colors.grey.shade500),
              ),
            ]),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: breakdown.segments
                .where((s) => s.value > 0)
                .map((s) {
              final pct = breakdown.percentOf(s);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        color: s.color ?? AppColors.primary,
                        borderRadius: BorderRadius.circular(3)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      (s.icon != null ? '${s.icon} ' : '') + s.label,
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${s.value} (${pct.toStringAsFixed(0)}%)',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ]),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
