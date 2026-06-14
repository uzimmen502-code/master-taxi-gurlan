import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'package:provider/provider.dart';

import '../../../models/analytics/kpi_summary.dart';
import '../controllers/analytics_controller.dart';
import '../widgets/donut_chart.dart';
import '../widgets/kpi_grid.dart';
import '../widgets/metric_row.dart';
import '../widgets/section_card.dart';
import '../widgets/top_list.dart';

/// 3-таб: Ҳайдовчиларнинг чуқур таҳлили.
class DriversTab extends StatefulWidget {
  const DriversTab({super.key});

  @override
  State<DriversTab> createState() => _DriversTabState();
}

class _DriversTabState extends State<DriversTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AnalyticsController>().loadDrivers();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.watch<AnalyticsController>();
    if (c.driversLoading && c.driverAnalytics == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final d = c.driverAnalytics;
    if (d == null) {
      return Center(
          child: Text(c.driversError ?? 'Маълумот юклаб бўлмади',
              style: const TextStyle(color: Colors.red)));
    }

    final wide = MediaQuery.of(context).size.width > 800;
    final pad = wide ? 24.0 : 12.0;
    return RefreshIndicator(
      onRefresh: () => c.loadDrivers(force: true),
      child: ListView(
        padding: EdgeInsets.fromLTRB(pad, pad, pad, 80),
        children: [
          SectionCard(
            title: 'Ҳайдовчи KPIлари',
            icon: '🚖',
            child: KpiGrid(
              aspectRatio: 1.45,
              accent: AppColors.primaryDark,
              kpis: [
                KpiValue(
                    label: 'Жами',
                    value: d.totalDrivers,
                    unit: 'та',
                    icon: '🚖'),
                KpiValue(
                    label: 'Онлайн',
                    value: d.onlineDrivers,
                    unit: 'та',
                    icon: '🟢'),
                KpiValue(
                    label: 'Бандлик',
                    value: d.busyDrivers,
                    unit: 'та',
                    icon: '🔴'),
                KpiValue(
                    label: 'Аризалар',
                    value: d.pendingApplications,
                    unit: 'та',
                    icon: '📝'),
                KpiValue(
                    label: 'Бугунги фаол',
                    value: d.activeToday,
                    unit: 'та',
                    icon: '⚡'),
                KpiValue(
                    label: 'Ҳафта фаол',
                    value: d.activeWeek,
                    unit: 'та',
                    icon: '📈'),
                KpiValue(
                    label: 'Бугунги рейс',
                    value: d.scheduleRegistered,
                    unit: 'та',
                    icon: '🗓'),
                KpiValue(
                    label: 'Ўртача рейтинг',
                    value: double.parse(d.avgRating.toStringAsFixed(2)),
                    unit: '/ 5',
                    icon: '⭐'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SectionCard(
                  title: 'Такси тури',
                  icon: '🚕',
                  child: DonutChart(breakdown: d.byTaxiType, size: 130),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SectionCard(
                  title: 'Рейтинг тарқалиш',
                  icon: '⭐',
                  child: DonutChart(breakdown: d.byRating, size: 130),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Эффективлик кўрсаткичлари',
            icon: '⚙️',
            child: Column(children: [
              MetricRow(
                  icon: '🛣',
                  label: 'Ўртача сафар / ҳайдовчи (7 кун)',
                  value: d.avgTripsPerDriver.toStringAsFixed(1)),
              MetricRow(
                  icon: '💰',
                  label: 'Ўртача даромад / ҳайдовчи (7 кун)',
                  value: '${d.avgEarningsPerDriver} сўм',
                  valueColor: AppColors.primary),
              MetricRow(
                  icon: '📊',
                  label: 'Онлайн ulushi',
                  value: d.totalDrivers > 0
                      ? '${(100 * d.onlineDrivers / d.totalDrivers).toStringAsFixed(0)}%'
                      : '0%',
                  valueColor: AppColors.primaryDark),
            ]),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Топ — сафарлар бўйича (7 кун)',
            icon: '🏆',
            child: TopList(
                items: d.topByTrips, color: AppColors.primary),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Топ — даромад бўйича (7 кун)',
            icon: '💎',
            child: TopList(
                items: d.topByEarnings, color: AppColors.primary),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Топ — рейтинг бўйича',
            icon: '⭐',
            child: TopList(
                items: d.topByRating, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
