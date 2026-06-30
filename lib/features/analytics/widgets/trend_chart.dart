import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'package:intl/intl.dart';

import '../../../models/analytics/time_series.dart';

/// Кенг тренд графиги — кунлик/соатлик чизиқли қатор.
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.series,
    this.color = AppColors.primary,
    this.height = 180,
    this.useWeekday = false,
    this.formatValue,
  });

  final TimeSeries series;
  final Color color;
  final double height;

  /// `true` бўлса X ёрлиқлар "Душ, Сеш, ..." — акс ҳолда "DD.MM" ёки `HH:00`.
  final bool useWeekday;

  /// Y кўрсаткичини форматлаш (мас. сум).
  final String Function(double)? formatValue;

  @override
  Widget build(BuildContext context) {
    if (series.points.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('Маълумот йўқ',
              style: TextStyle(color: Colors.grey.shade400)),
        ),
      );
    }
    final spots = <FlSpot>[];
    for (int i = 0; i < series.points.length; i++) {
      spots.add(FlSpot(i.toDouble(), series.points[i].value.toDouble()));
    }
    final maxY = series.max.toDouble();
    final yInterval =
        (maxY > 0 ? (maxY / 4).ceilToDouble() : 1.0).clamp(1.0, double.infinity);
    final showHourly =
        series.points.length >= 2 && series.points.first.timestamp.day == series.points.last.timestamp.day;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (series.points.length - 1).toDouble(),
          minY: 0,
          maxY: maxY == 0 ? 1 : (maxY * 1.15),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: yInterval,
            getDrawingHorizontalLine: (_) => FlLine(
                color: Colors.grey.shade200, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                interval: yInterval,
                getTitlesWidget: (v, _) => Text(
                  formatValue != null
                      ? formatValue!(v)
                      : NumberFormat.compact().format(v),
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFF9E9E9E)),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: _bottomInterval(series.points.length),
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= series.points.length) {
                    return const SizedBox.shrink();
                  }
                  final p = series.points[i];
                  final lbl = showHourly
                      ? p.hourLabel
                      : (useWeekday ? p.weekdayLabel : p.dayLabel);
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(lbl,
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
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.25,
              color: color,
              barWidth: 2.5,
              dotData: FlDotData(
                show: series.points.length <= 14,
                getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                    radius: 3, color: color, strokeWidth: 0),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.02)],
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => Colors.black87,
              getTooltipItems: (spots) => spots.map((s) {
                final i = s.x.toInt();
                final p = series.points[i];
                final lbl = showHourly
                    ? p.hourLabel
                    : (useWeekday ? p.weekdayLabel : p.dayLabel);
                final v = formatValue != null
                    ? formatValue!(s.y)
                    : NumberFormat.decimalPattern('en').format(s.y.toInt());
                return LineTooltipItem('$lbl\n$v ${series.unit}',
                    const TextStyle(color: Colors.white, fontSize: 11));
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  double _bottomInterval(int n) {
    if (n <= 7) return 1;
    if (n <= 14) return 2;
    if (n <= 30) return 5;
    return 7;
  }
}
