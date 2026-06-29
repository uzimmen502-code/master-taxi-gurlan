import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/analytics/kpi_summary.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/analytics_controller.dart';
import '../widgets/kpi_grid.dart';
import '../widgets/section_card.dart';

/// 1-С‚Р°Р±: Р‘СѓС‚СѓРЅ ТіРѕР»Р°С‚РЅРёРЅРі Р±РёСЂР»Р°С€РіР°РЅ KPI РєРµСЃРёРјРё.
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
    if (kpi == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(c.kpiError ?? 'РњР°СЉР»СѓРјРѕС‚ СЋРєР»Р°Р± Р±СћР»РјР°РґРё',
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
          _liveBanner(kpi),
          const SizedBox(height: 12),
          SectionCard(
            title: 'РђСЃРѕСЃРёР№ KPI',
            icon: 'рџ“Љ',
            subtitle:
                'Р‘СѓРіСѓРЅ ${DateFormat('dd.MM.yyyy').format(DateTime.now())}',
            child: KpiGrid(
              aspectRatio: 1.55,
              kpis: [
                kpi.todayOrdersKpi,
                kpi.todayTripsKpi,
                kpi.todayRevenueKpi,
                kpi.newUsersTodayKpi,
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Р¤РѕР№РґР°Р»Р°РЅСѓРІС‡РёР»Р°СЂ',
            icon: 'рџ‘Ґ',
            child: KpiGrid(
              aspectRatio: 1.55,
              accent: AppColors.primary,
              kpis: [
                kpi.usersKpi,
                kpi.activeUsersKpi,
                KpiValue(
                    label: 'Р‘Р»РѕРє',
                    value: kpi.blockedUsers,
                    unit: 'С‚Р°',
                    icon: 'рџљ«'),
                KpiValue(
                    label: 'РљСѓС‚Р°С‘С‚РіР°РЅ payout',
                    value: kpi.pendingPayouts,
                    unit: 'С‚Р°',
                    icon: 'рџ’ё'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'ТІР°Р№РґРѕРІС‡РёР»Р°СЂ',
            icon: 'рџљ–',
            child: KpiGrid(
              aspectRatio: 1.55,
              accent: AppColors.primaryDark,
              kpis: [
                kpi.driversKpi,
                kpi.onlineDriversKpi,
              ],
            ),
          ),
          const SizedBox(height: 12),
          _quickPulse(kpi),
        ],
      ),
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
            _live('РћРЅР»Р°Р№РЅ ТіР°Р№РґРѕРІС‡Рё', kpi.onlineDrivers, 'рџџў'),
            _live('Р¤Р°РѕР» СЃР°С„Р°СЂР»Р°СЂ (hozir)', kpi.activeTrips, 'рџљ—'),
            _live('РљСѓС‚Р°С‘С‚РіР°РЅ Р±СѓСЋСЂС‚РјР°', kpi.pendingOrders, 'рџ“¦'),
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

  Widget _quickPulse(KpiSummary kpi) {
    final fmt = NumberFormat.decimalPattern('en');
    final revToday = fmt.format(kpi.todayRevenue);
    return SectionCard(
      title: 'РљСѓРЅРґР°Р»РёРє РїСѓР»СЃ',
      icon: 'рџ’“',
      subtitle: 'РЎСћРЅРіРіРё 24 СЃРѕР°С‚',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _pulseLine(
            'рџ“¦ Р‘СѓРіСѓРЅРіРё С‚СѓС€СѓРј', '$revToday СЃСћРј', AppColors.primary),
        _pulseLine(
            'рџ›’ Р‘СѓРіСѓРЅРіРё Р±СѓСЋСЂС‚РјР°Р»Р°СЂ',
            '${kpi.todayOrders} С‚Р°',
            AppColors.primary),
        _pulseLine('рџ›Ј Р‘СѓРіСѓРЅРіРё СЃР°С„Р°СЂР»Р°СЂ', '${kpi.todayTrips} С‚Р°',
            AppColors.primary),
        _pulseLine(
            'рџ†• РЇРЅРіРё С„РѕР№РґР°Р»Р°РЅСѓРІС‡Рё', '${kpi.newUsersToday} С‚Р°',
            AppColors.primary),
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
