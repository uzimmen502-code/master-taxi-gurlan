import 'package:fl_chart/fl_chart.dart';
import '../../../core/utils/formatters.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'package:intl/intl.dart';

import '../../../models/analytics/time_series.dart';

/// 24 соатлик "heatmap" — устунли диаграмма. `peakHour` ажратилади.
class HourlyBarChart extends StatelessWidget {
  const HourlyBarChart({
    super.key,
    required this.series,
    this.height = 160,
    this.color = AppColors.primary,
    this.peakColor = AppColors.primary,
  });

  final TimeSeries series;
  final double height;
  final Color color;
  final Color peakColor;

  @override
  Widget build(BuildContext context) {
    if (series.points.isEmpty) {
      return SizedBox(height: height);
    }
    final maxV = series.max.toDouble();
    int peakIdx = 0;
    for (int i = 0; i < series.points.length; i++) {
      if (series.points[i].value == maxV) {
        peakIdx = i;
        break;
      }
    }
    final yInterval =
        (maxV > 0 ? (maxV / 4).ceilToDouble() : 1.0).clamp(1.0, double.infinity);

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceBetween,
          maxY: maxV == 0 ? 1 : maxV * 1.15,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: yInterval,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Colors.grey.shade200, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                interval: yInterval,
                getTitlesWidget: (v, _) => Text(
                  NumberFormat.compact().format(v),
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFF9E9E9E)),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: 3,
                getTitlesWidget: (v, _) {
                  final h = v.toInt();
                  if (h % 3 != 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(h.toString().padLeft(2, '0'),
                        style: const TextStyle(
                            fontSize: 9, color: Color(0xFF9E9E9E))),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(series.points.length, (i) {
            final v = series.points[i].value.toDouble();
            final isPeak = i == peakIdx && v > 0;
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: v,
                  color: isPeak ? peakColor : color,
                  width: 7,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4)),
                ),
              ],
            );
          }),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Colors.black87,
              getTooltipItem: (g, _, __, ___) {
                final p = series.points[g.x.toInt()];
                return BarTooltipItem(
                  '${p.hourLabel}\n${formatPrice(p.value.toInt())} ${series.unit}',
                  const TextStyle(color: Colors.white, fontSize: 11),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
