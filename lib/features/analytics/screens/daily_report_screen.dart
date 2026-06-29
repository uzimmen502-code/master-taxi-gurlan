import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/analytics/daily_report.dart';
import '../controllers/analytics_controller.dart';
import '../widgets/metric_row.dart';
import '../widgets/section_card.dart';

/// РљСѓРЅРґР°Р»РёРє ТіРёСЃРѕР±РѕС‚ СЌРєСЂР°РЅРё вЂ” Р±СѓРіСѓРЅРіРё ТіРёСЃРѕР±РѕС‚ + 30 РєСѓРЅР»РёРє Р°СЂС…РёРІ.
class DailyReportScreen extends StatefulWidget {
  const DailyReportScreen({super.key});

  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends State<DailyReportScreen> {
  static final _money = NumberFormat.decimalPattern('en');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AnalyticsController>().loadReports();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AnalyticsController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('рџ“Љ РљСѓРЅРґР°Р»РёРє ТіРёСЃРѕР±РѕС‚'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'ТљР°Р№С‚Р°-СЏСЃР°С€',
            onPressed: c.reportsLoading
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await c.regenerateTodayReport();
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(
                          content: Text('вњ… ТІРёСЃРѕР±РѕС‚ Т›Р°Р№С‚Р° СЏСЂР°С‚РёР»РґРё')),
                    );
                  },
          ),
        ],
      ),
      body: c.reportsLoading && c.todayReport == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => c.loadReports(force: true),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  if (c.todayReport != null)
                    _todayCard(c.todayReport!)
                  else
                    _emptyToday(c.reportsLoading),
                  const SizedBox(height: 12),
                  if (c.historicalReports.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 8, 4, 8),
                      child: Text('рџ—‚ РўР°СЂРёС…РёР№ ТіРёСЃРѕР±РѕС‚Р»Р°СЂ',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                    ...c.historicalReports
                        .where((r) =>
                            r.dateKey != (c.todayReport?.dateKey ?? ''))
                        .map(_historyCard),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _todayCard(DailyReport r) {
    final formatted = DateFormat('dd MMMM yyyy', 'uz').format(
            DateTime.tryParse(r.dateKey) ?? DateTime.now())
        // Р‘РѕС€РёРґР° intl uz Р»РѕРєaР»Рё Р№СћТ› Р±СћР»СЃР° fallback
        .replaceAll('January', 'РЇРЅРІР°СЂ')
        .replaceAll('February', 'Р¤РµРІСЂР°Р»')
        .replaceAll('March', 'РњР°СЂС‚')
        .replaceAll('April', 'РђРїСЂРµР»')
        .replaceAll('May', 'РњР°Р№')
        .replaceAll('June', 'РСЋРЅ')
        .replaceAll('July', 'РСЋР»')
        .replaceAll('August', 'РђРІРіСѓСЃС‚')
        .replaceAll('September', 'РЎРµРЅС‚СЏР±СЂ')
        .replaceAll('October', 'РћРєС‚СЏР±СЂ')
        .replaceAll('November', 'РќРѕСЏР±СЂ')
        .replaceAll('December', 'Р”РµРєР°Р±СЂ');
    return SectionCard(
      title: 'рџ“… Р‘СѓРіСѓРЅРіРё ТіРёСЃРѕР±РѕС‚',
      icon: 'рџ“Љ',
      subtitle: '$formatted В· ${DateFormat('HH:mm').format(r.generatedAt)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r.notes.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: r.notes
                      .map((n) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(n,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600)),
                          ))
                      .toList()),
            ),
            const SizedBox(height: 12),
          ],
          _section('рџ‘Ґ Р¤РѕР№РґР°Р»Р°РЅСѓРІС‡РёР»Р°СЂ', [
            MetricRow(label: 'Р–Р°РјРё', value: '${r.totalUsers} С‚Р°'),
            MetricRow(label: 'Р‘СѓРіСѓРЅРіРё СЏРЅРіРё', value: '${r.newUsersToday} С‚Р°'),
            MetricRow(label: 'Р‘СѓРіСѓРЅ С„Р°РѕР»', value: '${r.activeUsersToday} С‚Р°'),
            MetricRow(
                label: 'Р‘Р»РѕРє',
                value: '${r.blockedUsers} С‚Р°',
                valueColor: r.blockedUsers > 0
                    ? const Color(0xFFB71C1C)
                    : null),
          ]),
          _section('рџљ– ТІР°Р№РґРѕРІС‡РёР»Р°СЂ', [
            MetricRow(label: 'Р–Р°РјРё', value: '${r.totalDrivers} С‚Р°'),
            MetricRow(label: 'ТІРѕР·РёСЂ РѕРЅР»Р°Р№РЅ', value: '${r.onlineDriversNow} С‚Р°'),
            MetricRow(
                label: 'Р‘СѓРіСѓРЅРіРё С„Р°РѕР»',
                value: '${r.activeDriversToday} С‚Р°'),
          ]),
          _section('рџ“¦ Р‘СѓСЋСЂС‚РјР°Р»Р°СЂ', [
            MetricRow(label: 'Р–Р°РјРё', value: '${r.todayOrdersTotal} С‚Р°'),
            ...r.todayOrdersByStatus.entries.map(
                (e) => MetricRow(label: e.key, value: '${e.value} С‚Р°')),
            ...r.todayOrdersByType.entries.map(
                (e) => MetricRow(label: e.key, value: '${e.value} С‚Р°')),
            if (r.todayRejectReasons.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.only(top: 6, bottom: 2),
                child: Text('Р Р°Рґ СЃР°Р±Р°Р±Р»Р°СЂРё:',
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFB71C1C),
                        fontWeight: FontWeight.w600)),
              ),
              ...r.todayRejectReasons.entries.map(
                  (e) => MetricRow(label: e.key, value: '${e.value} С‚Р°')),
            ],
          ]),
          _section('рџ›Ј РЎР°С„Р°СЂР»Р°СЂ', [
            MetricRow(label: 'Р–Р°РјРё', value: '${r.todayTripsTotal} С‚Р°'),
            ...r.todayTripsByStatus.entries.map(
                (e) => MetricRow(label: e.key, value: '${e.value} С‚Р°')),
            ...r.todayTripsByTaxiType.entries.map(
                (e) => MetricRow(label: e.key, value: '${e.value} С‚Р°')),
          ]),
          _section('рџ’° РњРѕР»РёСЏ', [
            MetricRow(
                icon: 'рџ’µ',
                label: 'Р‘СѓРіСѓРЅРіРё С‚СѓС€СѓРј',
                value: '${_money.format(r.todayRevenue)} СЃСћРј',
                valueColor: AppColors.primary),
            MetricRow(
                label: 'ТІР°С„С‚Р°Р»РёРє С‚СѓС€СѓРј',
                value: '${_money.format(r.weekRevenue)} СЃСћРј'),
            MetricRow(
                label: 'РћР№Р»РёРє С‚СѓС€СѓРј',
                value: '${_money.format(r.monthRevenue)} СЃСћРј'),
            MetricRow(
                label: 'РЋСЂС‚Р°С‡Р° Р±СѓСЋСЂС‚РјР° Т›РёР№РјР°С‚Рё',
                value: '${_money.format(r.avgOrderValue.toInt())} СЃСћРј'),
            MetricRow(
                label: 'РЋСЂС‚Р°С‡Р° СЃР°С„Р°СЂ Т›РёР№РјР°С‚Рё',
                value: '${_money.format(r.avgTripValue.toInt())} СЃСћРј'),
            MetricRow(
                label: 'ТљР°Р№С‚Р°СЂРёР»РіР°РЅ Т›РѕР»РґРёТ›',
                value: '${_money.format(r.todayCashChange)} СЃСћРј'),
            MetricRow(
                label: 'РљРѕС€РµР»С‘РєРґР°РіРё РїСѓР»',
                value: '${_money.format(r.totalWalletBalance)} СЃСћРј'),
            MetricRow(
                label: 'РљСѓС‚Р°С‘С‚РіР°РЅ payout',
                value:
                    '${r.pendingPayouts} С‚Р° В· ${_money.format(r.pendingPayoutsAmount)} СЃСћРј',
                valueColor: r.pendingPayouts > 0
                    ? AppColors.primary
                    : null),
          ]),
          _section('вљ™пёЏ Р­С„С„РµРєС‚РёРІР»РёРє', [
            MetricRow(
                label: 'Eng band СЃРѕР°С‚',
                value: '${r.peakHour.toString().padLeft(2, '0')}:00'),
            MetricRow(
                label: 'Р‘РµРєРѕСЂ Т›РёР»РёС€',
                value: '${r.cancellationRate.toStringAsFixed(1)}%',
                valueColor: r.cancellationRate > 15
                    ? const Color(0xFFB71C1C)
                    : null),
          ]),
          if (r.topProducts.isNotEmpty)
            _section('рџЏ† РўРѕРї РјР°ТіСЃСѓР»РѕС‚Р»Р°СЂ', [
              for (final p in r.topProducts)
                MetricRow(
                    label: p['label']?.toString() ?? '',
                    value: '${p['value']} С‚Р°'),
            ]),
          if (r.topRoutes.isNotEmpty)
            _section('рџ›Ј РўРѕРї РјР°СЂС€СЂСѓС‚Р»Р°СЂ', [
              for (final p in r.topRoutes)
                MetricRow(
                    label: p['label']?.toString() ?? '',
                    value: '${p['value']} С‚Р°'),
            ]),
          if (r.topDrivers.isNotEmpty)
            _section('рџҐ‡ РўРѕРї ТіР°Р№РґРѕРІС‡РёР»Р°СЂ (СЃР°С„Р°СЂ)', [
              for (final p in r.topDrivers)
                MetricRow(
                    label: p['label']?.toString() ?? '',
                    value: '${p['value']} С‚Р°'),
            ]),
        ],
      ),
    );
  }

  Widget _emptyToday(bool loading) {
    return SectionCard(
      title: 'рџ“… Р‘СѓРіСѓРЅРіРё ТіРёСЃРѕР±РѕС‚',
      icon: 'рџ“Љ',
      child: Column(children: [
        Icon(Icons.assessment_outlined,
            size: 48, color: Colors.grey.shade300),
        const SizedBox(height: 8),
        Text(
          loading
              ? 'Р®РєР»Р°РЅРјРѕТ›РґР°...'
              : 'Р‘СѓРіСѓРЅРіРё ТіРёСЃРѕР±РѕС‚ ТіР°Р»Рё С‚Р°Р№С‘СЂ СЌРјР°СЃ.\nРЎРѕР°С‚ 20:00 РґР°РЅ РєРµР№РёРЅ С‘РєРё "ТљР°Р№С‚Р°-СЏСЃР°С€" С‚СѓРіРјР°СЃРё РѕСЂТ›Р°Р»Рё.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
      ]),
    );
  }

  Widget _historyCard(DailyReport r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10)),
          child: const Center(
              child: Icon(Icons.calendar_today,
                  color: AppColors.primary, size: 18)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.dateKey,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(
                '${r.todayOrdersTotal} Р±СѓСЋСЂС‚РјР° В· ${r.todayTripsTotal} СЃР°С„Р°СЂ В· ${_money.format(r.todayRevenue)} СЃСћРј',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        if (r.notes.isNotEmpty)
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.primary, size: 18),
      ]),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            ...children,
          ]),
    );
  }
}
