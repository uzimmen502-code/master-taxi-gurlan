import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'package:provider/provider.dart';

import '../../../models/analytics/kpi_summary.dart';
import '../../../models/analytics/operations_analytics.dart';
import '../controllers/analytics_controller.dart';
import '../widgets/donut_chart.dart';
import '../widgets/hourly_bar_chart.dart';
import '../widgets/kpi_grid.dart';
import '../widgets/metric_row.dart';
import '../widgets/section_card.dart';
import '../widgets/top_list.dart';
import '../widgets/trend_chart.dart';

/// 5-таб: Операциялар таҳлили + жонли админ панели.
///
/// Чуқур таҳлилни кўрсатади ва эски админ амалларига (driver_requests,
/// prices, products) йўналтирувчи карталар тақдим этади.
class OperationsTab extends StatefulWidget {
  const OperationsTab({super.key});

  @override
  State<OperationsTab> createState() => _OperationsTabState();
}

class _OperationsTabState extends State<OperationsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AnalyticsController>().loadOperations();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.watch<AnalyticsController>();
    if (c.operationsLoading && c.operationsAnalytics == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final o = c.operationsAnalytics;
    if (o == null) {
      return Center(
          child: Text(c.operationsError ?? 'Маълумот юклаб бўлмади',
              style: const TextStyle(color: Colors.red)));
    }

    final wide = MediaQuery.of(context).size.width > 800;
    final pad = wide ? 24.0 : 12.0;
    return RefreshIndicator(
      onRefresh: () => c.loadOperations(force: true),
      child: ListView(
        padding: EdgeInsets.fromLTRB(pad, pad, pad, 80),
        children: [
          _operationsKpis(o),
          const SizedBox(height: 12),
          _liveCount(),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Соатлик буюртма heatmap',
            icon: '🕐',
            subtitle:
                'Eng band: ${o.peakHour.toString().padLeft(2, '0')}:00',
            child: HourlyBarChart(
                series: o.ordersHourlyHeatmap,
                color: AppColors.primary),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Соатлик сафар heatmap',
            icon: '🕐',
            child: HourlyBarChart(
                series: o.tripsHourlyHeatmap,
                color: AppColors.primary),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '30 кунлик буюртма + сафар тренди',
            icon: '📈',
            child: Column(children: [
              TrendChart(
                  series: o.ordersDailyTrend,
                  color: AppColors.primary,
                  height: 140),
              const SizedBox(height: 8),
              TrendChart(
                  series: o.tripsDailyTrend,
                  color: AppColors.primary,
                  height: 140),
            ]),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SectionCard(
                  title: 'Буюртма статуси',
                  icon: '📦',
                  child:
                      DonutChart(breakdown: o.ordersByStatus, size: 130),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SectionCard(
                  title: 'Сафар статуси',
                  icon: '🚗',
                  child: DonutChart(breakdown: o.tripsByStatus, size: 130),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SectionCard(
                  title: 'Буюртма тури',
                  icon: '🧩',
                  child: DonutChart(breakdown: o.ordersByType, size: 130),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SectionCard(
                  title: 'Такси тури',
                  icon: '🚕',
                  child:
                      DonutChart(breakdown: o.tripsByTaxiType, size: 130),
                ),
              ),
            ],
          ),
          if (o.rejectReasons.segments.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'Рад этиш сабаблари',
              icon: '🚫',
              child: DonutChart(breakdown: o.rejectReasons, size: 170),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SectionCard(
                  title: 'Топ маҳсулот',
                  icon: '🏆',
                  child: TopList(
                    items: o.topOrderProducts,
                    color: AppColors.primary,
                    maxItems: 5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SectionCard(
                  title: 'Топ маршрут',
                  icon: '🛣',
                  child: TopList(
                    items: o.topTripRoutes,
                    color: AppColors.primary,
                    maxItems: 5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Эффективлик',
            icon: '⚙️',
            child: Column(children: [
              MetricRow(
                  icon: '⏱',
                  label: 'Буюртма қабул вақти',
                  value:
                      '${o.avgOrderFulfillmentMinutes.toStringAsFixed(1)} дақ'),
              MetricRow(
                  icon: '🚗',
                  label: 'Сафар якунлаш вақти',
                  value:
                      '${o.avgTripCompletionMinutes.toStringAsFixed(1)} дақ'),
              MetricRow(
                  icon: '❌',
                  label: 'Бекор қилиш даражаси',
                  value: '${o.cancellationRate.toStringAsFixed(1)}%',
                  valueColor: o.cancellationRate > 15
                      ? const Color(0xFFB71C1C)
                      : null),
              MetricRow(
                  icon: '🕐',
                  label: 'Eng band соат',
                  value: '${o.peakHour.toString().padLeft(2, '0')}:00'),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _operationsKpis(OperationsAnalytics o) {
    return SectionCard(
      title: 'Операция KPIлари',
      icon: '⚙️',
      child: KpiGrid(
        aspectRatio: 1.45,
        accent: AppColors.primary,
        kpis: [
          KpiValue(
              label: 'Бугунги буюртмалар',
              value: o.todayOrders,
              unit: 'та',
              icon: '📦'),
          KpiValue(
              label: 'Бугунги сафарлар',
              value: o.todayTrips,
              unit: 'та',
              icon: '🛣'),
          KpiValue(
              label: 'Фаол буюртма',
              value: o.activeOrders,
              unit: 'та',
              icon: '⏳'),
          KpiValue(
              label: 'Фаол сафар',
              value: o.activeTrips,
              unit: 'та',
              icon: '🚗'),
        ],
      ),
    );
  }

  Widget _liveCount() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('driver_requests')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (ctx, snap) {
        final n = snap.data?.docs.length ?? 0;
        if (n == 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.notifications_active,
                color: AppColors.primary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text('$n та ҳайдовчи аризаси кутмоқда',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
            ),
            // Аризаларни кўриш — pending_drivers экранига
            // (улар Cloud Functions/Repository орқали ҳал қилинади).
            const Icon(Icons.chevron_right, color: AppColors.primary),
          ]),
        );
      },
    );
  }
}
