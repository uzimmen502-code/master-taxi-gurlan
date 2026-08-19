import 'package:flutter/material.dart';
import '../../../core/utils/formatters.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/analytics/dashboard_period.dart';
import '../../../models/analytics/kpi_summary.dart';
import '../../../models/analytics/period_kpis.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/analytics_controller.dart';
import '../widgets/kpi_grid.dart';
import '../widgets/section_card.dart';
import '../widgets/trend_chart.dart';

/// 1-таб: LIVE ҳолат + давр бўйича тарихий KPI (analytics_daily).
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AnalyticsController>().loadKpis();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.watch<AnalyticsController>();
    if (c.kpiLoading && c.kpiSummary == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final kpi = c.kpiSummary;
    final period = c.periodKpis;
    if (kpi == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(c.kpiError ?? 'Маълумот юклаб бўлмади',
              style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    final wide = MediaQuery.of(context).size.width > 800;
    final pad = wide ? 24.0 : 12.0;
    return RefreshIndicator(
      onRefresh: () => c.loadKpis(force: true),
      child: ListView(
        padding: EdgeInsets.fromLTRB(pad, pad, pad, 80),
        children: [
          _periodChips(c),
          const SizedBox(height: 12),
          _liveBanner(kpi),
          if (c.backfillRunning) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 6),
            const Text('Тарихий агрегат ҳисобланмоқда…',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
          if (c.backfillError != null) ...[
            const SizedBox(height: 8),
            Text(c.backfillError!,
                style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
          if (period != null && (period.needsBackfill || !period.fromDaily)) ...[
            const SizedBox(height: 12),
            _backfillBanner(c, period),
          ],
          const SizedBox(height: 12),
          SectionCard(
            title: 'Асосий KPI',
            icon: '📊',
            subtitle: period == null
                ? DateFormat('dd.MM.yyyy').format(DateTime.now())
                : '${c.dashboardPeriod.titleLabel} · '
                    '${DateFormat('dd.MM').format(period.from)}'
                    ' – ${DateFormat('dd.MM.yyyy').format(period.to)}',
            child: KpiGrid(
              aspectRatio: 1.55,
              kpis: [
                period?.ordersKpi ?? kpi.todayOrdersKpi,
                period?.tripsKpi ?? kpi.todayTripsKpi,
                period?.revenueKpi ?? kpi.todayRevenueKpi,
                period?.newUsersKpi ?? kpi.newUsersTodayKpi,
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Контент',
            icon: '🎬',
            subtitle: 'Ролик, дўкон, платформа, эълон',
            child: KpiGrid(
              aspectRatio: 1.55,
              accent: AppColors.primaryDark,
              kpis: [
                period?.newClipsKpi ??
                    const KpiValue(label: 'Янги роликлар', value: 0, unit: 'та'),
                period?.totalClipsKpi ??
                    const KpiValue(label: 'Жами роликлар', value: 0, unit: 'та'),
                period?.newShopItemsKpi ??
                    const KpiValue(label: 'Янги товарлар', value: 0, unit: 'та'),
                period?.totalShopItemsKpi ??
                    const KpiValue(label: 'Жами товарлар', value: 0, unit: 'та'),
                period?.newPlatformProductsKpi ??
                    const KpiValue(
                        label: 'Янги платформа', value: 0, unit: 'та'),
                period?.totalPlatformProductsKpi ??
                    const KpiValue(
                        label: 'Платформа каталог', value: 0, unit: 'та'),
                period?.newAdsKpi ??
                    const KpiValue(label: 'Янги эълонлар', value: 0, unit: 'та'),
                period?.totalAdsKpi ??
                    const KpiValue(label: 'Жами эълонлар', value: 0, unit: 'та'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Фойдаланувчилар',
            icon: '👥',
            child: KpiGrid(
              aspectRatio: 1.55,
              accent: AppColors.primary,
              kpis: [
                period?.totalUsersKpi ?? kpi.usersKpi,
                period?.uniqueActiveKpi ?? kpi.activeUsersKpi,
                KpiValue(
                    label: 'Блок',
                    value: kpi.blockedUsers,
                    unit: 'та',
                    icon: '🚫'),
                KpiValue(
                    label: 'Кутаётган payout',
                    value: kpi.pendingPayouts,
                    unit: 'та',
                    icon: '💸'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Ҳайдовчилар',
            icon: '🚖',
            child: KpiGrid(
              aspectRatio: 1.55,
              accent: AppColors.primaryDark,
              kpis: [
                kpi.driversKpi,
                kpi.onlineDriversKpi,
              ],
            ),
          ),
          if (period != null && period.fromDaily) ...[
            const SizedBox(height: 12),
            _growthCharts(period),
          ],
          const SizedBox(height: 12),
          _quickPulse(kpi, period),
        ],
      ),
    );
  }

  Widget _periodChips(AnalyticsController c) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in DashboardPeriod.values)
          ChoiceChip(
            label: Text(p.chipLabel),
            selected: c.dashboardPeriod == p,
            onSelected: (_) => c.setDashboardPeriod(p),
            selectedColor: AppColors.primary.withValues(alpha: 0.18),
            labelStyle: TextStyle(
              fontWeight: FontWeight.w600,
              color: c.dashboardPeriod == p
                  ? AppColors.primaryDark
                  : Colors.grey.shade700,
            ),
          ),
      ],
    );
  }

  Widget _backfillBanner(AnalyticsController c, PeriodKpis period) {
    final allTimeGap = period.needsBackfill &&
        c.dashboardPeriod == DashboardPeriod.allTime;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            allTimeGap
                ? '«Бугунгача» тушуми учун тарихий агрегат керак. '
                    'Жами фойдаланувчи/контент тирик ҳисоб, пул эса backfill дан.'
                : 'Кунлик агрегат ҳали йўқ — график ва давр тенглиги '
                    'analytics_daily дан тўлади. LIVE рақамлар ишлайди.',
            style: const TextStyle(fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: c.backfillRunning
                  ? null
                  : () => c.runHistoricalBackfill(force: false),
              icon: const Icon(Icons.history, size: 18),
              label: const Text('Тарихий агрегатни ҳисоблаш'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _growthCharts(PeriodKpis period) {
    final show = period.newUsersTrend.points.length >= 2;
    if (!show) return const SizedBox.shrink();
    return Column(
      children: [
        SectionCard(
          title: 'Ўсиш',
          icon: '📈',
          subtitle: 'Кунлик янги (SUM эмас — ҳар кун ўз нуқтаси)',
          child: Column(
            children: [
              TrendChart(series: period.newUsersTrend),
              const SizedBox(height: 16),
              TrendChart(
                series: period.clipsTrend,
                color: AppColors.primaryDark,
              ),
              const SizedBox(height: 16),
              TrendChart(series: period.ordersTrend),
              const SizedBox(height: 16),
              TrendChart(
                series: period.revenueTrend,
                formatValue: (v) => NumberFormat.compact().format(v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _liveBanner(KpiSummary kpi) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [AppColors.primaryDark, AppColors.primary]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        const Icon(Icons.radio_button_checked,
            color: Colors.white, size: 16),
        const SizedBox(width: 8),
        const Text('LIVE',
            style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2)),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(spacing: 16, runSpacing: 4, children: [
            _live('Онлайн ҳайдовчи', kpi.onlineDrivers, '🟢'),
            _live('Фаол сафарлар (hozir)', kpi.activeTrips, '🚗'),
            _live('Кутаётган буюртма', kpi.pendingOrders, '📦'),
          ]),
        ),
      ]),
    );
  }

  Widget _live(String label, int value, String icon) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(icon, style: const TextStyle(fontSize: 14)),
      const SizedBox(width: 4),
      Text(
        '$value',
        style: const TextStyle(
            color: Colors.white,
            fontSize: AppText.bodyLarge,
            fontWeight: FontWeight.bold),
      ),
      const SizedBox(width: 4),
      Text(label,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85), fontSize: 11)),
    ]);
  }

  Widget _quickPulse(KpiSummary kpi, PeriodKpis? period) {
    final rev = formatMoney(period?.revenue ?? kpi.todayRevenue);
    final orders = period?.ordersCreated ?? kpi.todayOrders;
    final trips = period?.tripsCompleted ?? kpi.todayTrips;
    final users = period?.newUsers ?? kpi.newUsersToday;
    return SectionCard(
      title: 'Давр пулси',
      icon: '💓',
      subtitle: period?.fromDaily == true
          ? 'analytics_daily · аниқ сумма'
          : 'Тирик сўров · сўнгги юклаш',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _pulseLine('📦 Тушум', rev, AppColors.primary),
        _pulseLine('🛒 Буюртмалар', '$orders та', AppColors.primary),
        _pulseLine('🛣 Якунланган сафарлар', '$trips та', AppColors.primary),
        _pulseLine('🆕 Янги фойдаланувчи', '$users та', AppColors.primary),
      ]),
    );
  }

  Widget _pulseLine(String label, String value, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        Text(value,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }
}
