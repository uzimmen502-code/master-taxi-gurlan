import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/analytics/kpi_summary.dart';
import '../../../models/analytics/time_series.dart';
import '../controllers/analytics_controller.dart';
import '../widgets/donut_chart.dart';
import '../widgets/hourly_bar_chart.dart';
import '../widgets/kpi_grid.dart';
import '../widgets/metric_row.dart';
import '../widgets/section_card.dart';
import '../widgets/top_list.dart';
import '../widgets/trend_chart.dart';

/// 2-таб: Фойдаланувчиларнинг чуқур таҳлили.
///
/// Вертикал кесим: KPI → ўсиш тренди → сегментлар → топ.
/// Горизонтал: жинс/роль/маҳалла бўйича паралел қарашлар.
class UsersTab extends StatefulWidget {
  const UsersTab({super.key});

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AnalyticsController>().loadUsers();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.watch<AnalyticsController>();
    if (c.usersLoading && c.userAnalytics == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final u = c.userAnalytics;
    if (u == null) {
      return Center(
          child: Text(c.usersError ?? 'Маълумот юклаб бўлмади',
              style: const TextStyle(color: Colors.red)));
    }

    final wide = MediaQuery.of(context).size.width > 800;
    final pad = wide ? 24.0 : 12.0;
    return RefreshIndicator(
      onRefresh: () => c.loadUsers(force: true),
      child: ListView(
        padding: EdgeInsets.fromLTRB(pad, pad, pad, 80),
        children: [
          SectionCard(
            title: 'Фойдаланувчи KPIлари',
            icon: '👥',
            child: KpiGrid(
              aspectRatio: 1.45,
              accent: const Color(0xFF1565C0),
              kpis: [
                KpiValue(
                    label: 'Жами',
                    value: u.totalUsers,
                    unit: 'та',
                    icon: '👤'),
                KpiValue(
                    label: 'Бугунги янги',
                    value: u.newUsersToday,
                    unit: 'та',
                    icon: '🆕'),
                KpiValue(
                    label: 'Ҳафталик янги',
                    value: u.newUsersWeek,
                    unit: 'та',
                    icon: '📅'),
                KpiValue(
                    label: 'Ойлик янги',
                    value: u.newUsersMonth,
                    unit: 'та',
                    icon: '📆'),
                KpiValue(
                    label: 'Кунлик фаол',
                    value: u.activeUsersDaily,
                    unit: 'та',
                    icon: '⚡'),
                KpiValue(
                    label: 'Ҳафталик фаол',
                    value: u.activeUsersWeekly,
                    unit: 'та',
                    icon: '📈'),
                KpiValue(
                    label: 'Ойлик фаол',
                    value: u.activeUsersMonthly,
                    unit: 'та',
                    icon: '🌐'),
                KpiValue(
                    label: 'Блок',
                    value: u.blockedUsers,
                    unit: 'та',
                    icon: '🚫'),
                KpiValue(
                    label: 'Йўқолганлар (30+к)',
                    value: u.churnedUsers,
                    unit: 'та',
                    icon: '🌪'),
                KpiValue(
                    label: 'Кошелёкли',
                    value: u.usersWithWallet,
                    unit: 'та',
                    icon: '💳'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Янги рўйхатдан ўтиш — 30 кун',
            icon: '📈',
            subtitle:
                'Жами ${u.newUserRegistrationTrend.total} · ўртача ${u.newUserRegistrationTrend.average.toStringAsFixed(1)}/кун',
            child: TrendChart(
              series: u.newUserRegistrationTrend,
              color: const Color(0xFF1565C0),
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Соатлик фаоллик — бугун',
            icon: '🕐',
            subtitle: 'lastActiveAt бўйича',
            child: HourlyBarChart(
              series: u.activityHeatmap,
              color: const Color(0xFF6A1B9A),
            ),
          ),
          const SizedBox(height: 12),
          // Горизонтал — жинс + роль ёнма-ён
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SectionCard(
                  title: 'Жинс',
                  icon: '⚥',
                  child: DonutChart(breakdown: u.byGender, size: 130),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SectionCard(
                  title: 'Роль',
                  icon: '🎭',
                  child: DonutChart(breakdown: u.byRole, size: 130),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Маҳалла бўйича',
            icon: '🏘',
            subtitle: 'Топ ${u.byCity.segments.length} маҳалла',
            child: DonutChart(breakdown: u.byCity, size: 170),
          ),
          const SizedBox(height: 12),
          if (u.cohortRetention.isNotEmpty)
            SectionCard(
              title: 'Когорт ретеншн (ҳафталик)',
              icon: '🔁',
              subtitle: 'Ҳар ҳафтада уникал буюртмачи сони',
              child: TrendChart(
                series: TimeSeries(
                  label: 'Когорт',
                  unit: 'фойдаланувчи',
                  points: u.cohortRetention,
                ),
                color: const Color(0xFFE65100),
              ),
            ),
          if (u.cohortRetention.isNotEmpty) const SizedBox(height: 12),
          SectionCard(
            title: 'Хулқ-атвор',
            icon: '🧠',
            child: Column(children: [
              MetricRow(
                  icon: '🔁',
                  label: 'Такрорий буюртма даражаси',
                  value: '${u.repeatRate.toStringAsFixed(1)}%',
                  valueColor: const Color(0xFF2E7D32)),
              MetricRow(
                  icon: '📊',
                  label: 'Ўртача буюртма / фойдаланувчи',
                  value: u.avgOrdersPerUser.toStringAsFixed(2)),
            ]),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SectionCard(
                  title: 'Топ буюртма (миқдор)',
                  icon: '🏆',
                  child: TopList(
                    items: u.topUsersByOrders,
                    color: const Color(0xFF1565C0),
                    maxItems: 5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SectionCard(
                  title: 'Топ тушум',
                  icon: '💎',
                  child: TopList(
                    items: u.topUsersByRevenue,
                    color: const Color(0xFF2E7D32),
                    maxItems: 5,
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
