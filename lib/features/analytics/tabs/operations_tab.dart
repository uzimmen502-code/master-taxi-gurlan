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

/// 5-С‚Р°Р±: РћРїРµСЂР°С†РёСЏР»Р°СЂ С‚Р°ТіР»РёР»Рё + Р¶РѕРЅР»Рё Р°РґРјРёРЅ РїР°РЅРµР»Рё.
///
/// Р§СѓТ›СѓСЂ С‚Р°ТіР»РёР»РЅРё РєСћСЂСЃР°С‚Р°РґРё РІР° СЌСЃРєРё Р°РґРјРёРЅ Р°РјР°Р»Р»Р°СЂРёРіР° (driver_requests,
/// prices, products) Р№СћРЅР°Р»С‚РёСЂСѓРІС‡Рё РєР°СЂС‚Р°Р»Р°СЂ С‚Р°Т›РґРёРј СЌС‚Р°РґРё.
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
          child: Text(c.operationsError ?? 'РњР°СЉР»СѓРјРѕС‚ СЋРєР»Р°Р± Р±СћР»РјР°РґРё',
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
            title: 'РЎРѕР°С‚Р»РёРє Р±СѓСЋСЂС‚РјР° heatmap',
            icon: 'рџ•ђ',
            subtitle:
                'Eng band: ${o.peakHour.toString().padLeft(2, '0')}:00',
            child: HourlyBarChart(
                series: o.ordersHourlyHeatmap,
                color: AppColors.primary),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'РЎРѕР°С‚Р»РёРє СЃР°С„Р°СЂ heatmap',
            icon: 'рџ•ђ',
            child: HourlyBarChart(
                series: o.tripsHourlyHeatmap,
                color: AppColors.primary),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: '30 РєСѓРЅР»РёРє Р±СѓСЋСЂС‚РјР° + СЃР°С„Р°СЂ С‚СЂРµРЅРґРё',
            icon: 'рџ“€',
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
                  title: 'Р‘СѓСЋСЂС‚РјР° СЃС‚Р°С‚СѓСЃРё',
                  icon: 'рџ“¦',
                  child:
                      DonutChart(breakdown: o.ordersByStatus, size: 130),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SectionCard(
                  title: 'РЎР°С„Р°СЂ СЃС‚Р°С‚СѓСЃРё',
                  icon: 'рџљ—',
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
                  title: 'Р‘СѓСЋСЂС‚РјР° С‚СѓСЂРё',
                  icon: 'рџ§©',
                  child: DonutChart(breakdown: o.ordersByType, size: 130),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SectionCard(
                  title: 'РўР°РєСЃРё С‚СѓСЂРё',
                  icon: 'рџљ•',
                  child:
                      DonutChart(breakdown: o.tripsByTaxiType, size: 130),
                ),
              ),
            ],
          ),
          if (o.rejectReasons.segments.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'Р Р°Рґ СЌС‚РёС€ СЃР°Р±Р°Р±Р»Р°СЂРё',
              icon: 'рџљ«',
              child: DonutChart(breakdown: o.rejectReasons, size: 170),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SectionCard(
                  title: 'РўРѕРї РјР°ТіСЃСѓР»РѕС‚',
                  icon: 'рџЏ†',
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
                  title: 'РўРѕРї РјР°СЂС€СЂСѓС‚',
                  icon: 'рџ›Ј',
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
            title: 'Р­С„С„РµРєС‚РёРІР»РёРє',
            icon: 'вљ™пёЏ',
            child: Column(children: [
              MetricRow(
                  icon: 'вЏ±',
                  label: 'Р‘СѓСЋСЂС‚РјР° Т›Р°Р±СѓР» РІР°Т›С‚Рё',
                  value:
                      '${o.avgOrderFulfillmentMinutes.toStringAsFixed(1)} РґР°Т›'),
              MetricRow(
                  icon: 'рџљ—',
                  label: 'РЎР°С„Р°СЂ СЏРєСѓРЅР»Р°С€ РІР°Т›С‚Рё',
                  value:
                      '${o.avgTripCompletionMinutes.toStringAsFixed(1)} РґР°Т›'),
              MetricRow(
                  icon: 'вќЊ',
                  label: 'Р‘РµРєРѕСЂ Т›РёР»РёС€ РґР°СЂР°Р¶Р°СЃРё',
                  value: '${o.cancellationRate.toStringAsFixed(1)}%',
                  valueColor: o.cancellationRate > 15
                      ? const Color(0xFFB71C1C)
                      : null),
              MetricRow(
                  icon: 'рџ•ђ',
                  label: 'Eng band СЃРѕР°С‚',
                  value: '${o.peakHour.toString().padLeft(2, '0')}:00'),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _operationsKpis(OperationsAnalytics o) {
    return SectionCard(
      title: 'РћРїРµСЂР°С†РёСЏ KPIР»Р°СЂРё',
      icon: 'вљ™пёЏ',
      child: KpiGrid(
        aspectRatio: 1.45,
        accent: AppColors.primary,
        kpis: [
          KpiValue(
              label: 'Р‘СѓРіСѓРЅРіРё Р±СѓСЋСЂС‚РјР°Р»Р°СЂ',
              value: o.todayOrders,
              unit: 'С‚Р°',
              icon: 'рџ“¦'),
          KpiValue(
              label: 'Р‘СѓРіСѓРЅРіРё СЃР°С„Р°СЂР»Р°СЂ',
              value: o.todayTrips,
              unit: 'С‚Р°',
              icon: 'рџ›Ј'),
          KpiValue(
              label: 'Р¤Р°РѕР» Р±СѓСЋСЂС‚РјР°',
              value: o.activeOrders,
              unit: 'С‚Р°',
              icon: 'вЏі'),
          KpiValue(
              label: 'Р¤Р°РѕР» СЃР°С„Р°СЂ',
              value: o.activeTrips,
              unit: 'С‚Р°',
              icon: 'рџљ—'),
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
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.notifications_active,
                color: AppColors.primary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text('$n С‚Р° ТіР°Р№РґРѕРІС‡Рё Р°СЂРёР·Р°СЃРё РєСѓС‚РјРѕТ›РґР°',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
            ),
            // РђСЂРёР·Р°Р»Р°СЂРЅРё РєСћСЂРёС€ вЂ” pending_drivers СЌРєСЂР°РЅРёРіР°
            // (СѓР»Р°СЂ Cloud Functions/Repository РѕСЂТ›Р°Р»Рё ТіР°Р» Т›РёР»РёРЅР°РґРё).
            const Icon(Icons.chevron_right, color: AppColors.primary),
          ]),
        );
      },
    );
  }
}
