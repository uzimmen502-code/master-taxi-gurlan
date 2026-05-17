import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../../../models/analytics/kpi_summary.dart';
import '../controllers/analytics_controller.dart';
import '../widgets/donut_chart.dart';
import '../widgets/hourly_bar_chart.dart';
import '../widgets/kpi_grid.dart';
import '../widgets/metric_row.dart';
import '../widgets/section_card.dart';
import '../widgets/top_list.dart';
import '../widgets/trend_chart.dart';

/// 4-таб: Молия чуқур таҳлили.
class FinanceTab extends StatefulWidget {
  const FinanceTab({super.key});

  @override
  State<FinanceTab> createState() => _FinanceTabState();
}

class _FinanceTabState extends State<FinanceTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _money(num v) => _MoneyFmt.fmt(v);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AnalyticsController>().loadFinance();
        context.read<AnalyticsController>().loadOperations();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.watch<AnalyticsController>();
    if (c.financeLoading && c.financeAnalytics == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final f = c.financeAnalytics;
    if (f == null) {
      return Center(
          child: Text(c.financeError ?? 'Маълумот юклаб бўлмади',
              style: const TextStyle(color: Colors.red)));
    }
    final o = c.operationsAnalytics;

    final wide = MediaQuery.of(context).size.width > 800;
    final pad = wide ? 24.0 : 12.0;
    return RefreshIndicator(
      onRefresh: () async {
        await c.loadFinance(force: true);
        await c.loadOperations(force: true);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(pad, pad, pad, 80),
        children: [
          SectionCard(
            title: 'Тушум KPIлари',
            icon: '💰',
            child: KpiGrid(
              aspectRatio: 1.45,
              accent: const Color(0xFF2E7D32),
              kpis: [
                KpiValue(
                    label: 'Бугунги тушум',
                    value: f.todayRevenue,
                    unit: 'сўм',
                    icon: '💵'),
                KpiValue(
                    label: 'Ҳафталик тушум',
                    value: f.weekRevenue,
                    unit: 'сўм',
                    icon: '📊'),
                KpiValue(
                    label: 'Ойлик тушум',
                    value: f.monthRevenue,
                    unit: 'сўм',
                    icon: '📅'),
                KpiValue(
                    label: 'Кошелёк баланси',
                    value: f.totalWalletBalance,
                    unit: 'сўм',
                    icon: '💳'),
                KpiValue(
                    label: 'Кутаётган payout',
                    value: f.pendingPayouts,
                    unit: 'та',
                    icon: '⏳'),
                KpiValue(
                    label: 'Payout суммаси',
                    value: f.pendingPayoutsAmount,
                    unit: 'сўм',
                    icon: '💸'),
                KpiValue(
                    label: 'Ўртача буюртма',
                    value: double.parse(f.avgOrderValue.toStringAsFixed(0)),
                    unit: 'сўм',
                    icon: '🛒'),
                KpiValue(
                    label: 'Ўртача сафар',
                    value: double.parse(f.avgTripValue.toStringAsFixed(0)),
                    unit: 'сўм',
                    icon: '🛣'),
                KpiValue(
                    label: 'Қайтарилган қолдиқ',
                    value: f.cashChangeIssued,
                    unit: 'сўм',
                    icon: '🔄'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Кунлик тушум — 30 кун',
            icon: '📈',
            subtitle: 'Жами: ${_money(f.revenueDailyTrend.total)} сўм',
            child: TrendChart(
              series: f.revenueDailyTrend,
              color: const Color(0xFF2E7D32),
              formatValue: (v) => _money(v),
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Соатлик тушум — бугун',
            icon: '🕐',
            child: HourlyBarChart(
              series: f.revenueHourly,
              color: const Color(0xFF1565C0),
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Тушум модул бўйича',
            icon: '🧩',
            child: DonutChart(breakdown: f.revenueByModule, size: 170),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Тўлов методи',
            icon: '💳',
            child: DonutChart(breakdown: f.paymentMethods, size: 150),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Топ маҳсулотлар — тушум',
            icon: '🥇',
            child: TopList(
              items: f.topProducts,
              color: const Color(0xFFE65100),
              formatValue: (v) => '${_money(v)} сўм',
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Топ маршрутлар — тушум',
            icon: '🛣',
            child: TopList(
              items: f.topRoutes,
              color: const Color(0xFF00695C),
              formatValue: (v) => '${_money(v)} сўм',
            ),
          ),
          if (o != null) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'Эффективлик',
              icon: '⚙️',
              child: Column(children: [
                MetricRow(
                  icon: '⏱',
                  label: 'Буюртма қабул вақти',
                  value:
                      '${o.avgOrderFulfillmentMinutes.toStringAsFixed(1)} дақ',
                ),
                MetricRow(
                  icon: '🛣',
                  label: 'Сафар якунлаш',
                  value:
                      '${o.avgTripCompletionMinutes.toStringAsFixed(1)} дақ',
                ),
                MetricRow(
                  icon: '❌',
                  label: 'Бекор қилиш даражаси',
                  value: '${o.cancellationRate.toStringAsFixed(1)}%',
                  valueColor: o.cancellationRate > 15
                      ? const Color(0xFFB71C1C)
                      : null,
                ),
                MetricRow(
                  icon: '🕐',
                  label: 'Eng band соат',
                  value:
                      '${o.peakHour.toString().padLeft(2, '0')}:00',
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _MoneyFmt {
  static final _fmt = intl.NumberFormat.decimalPattern('en');
  static String fmt(num v) {
    if (v.abs() >= 1000000) {
      return '${(v / 1000000).toStringAsFixed(1)}M';
    }
    if (v.abs() >= 1000) {
      return '${(v / 1000).toStringAsFixed(1)}K';
    }
    return _fmt.format(v.toInt());
  }
}
