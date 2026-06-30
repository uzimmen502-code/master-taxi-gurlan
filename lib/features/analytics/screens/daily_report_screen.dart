import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/analytics/daily_report.dart';
import '../controllers/analytics_controller.dart';
import '../widgets/metric_row.dart';
import '../widgets/section_card.dart';

/// Кундалик ҳисобот экрани — бугунги ҳисобот + 30 кунлик архив.
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
        title: const Text('📊 Кундалик ҳисобот'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Қайта-ясаш',
            onPressed: c.reportsLoading
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await c.regenerateTodayReport();
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(
                          content: Text('✅ Ҳисобот қайта яратилди')),
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
                      child: Text('🗂 Тарихий ҳисоботлар',
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
        // Бошида intl uz локaли йўқ бўлса fallback
        .replaceAll('January', 'Январ')
        .replaceAll('February', 'Феврал')
        .replaceAll('March', 'Март')
        .replaceAll('April', 'Апрел')
        .replaceAll('May', 'Май')
        .replaceAll('June', 'РСЋРЅ')
        .replaceAll('July', 'РСЋР»')
        .replaceAll('August', 'Август')
        .replaceAll('September', 'Сентябр')
        .replaceAll('October', 'Октябр')
        .replaceAll('November', 'Ноябр')
        .replaceAll('December', 'Декабр');
    return SectionCard(
      title: '📅 Бугунги ҳисобот',
      icon: '📊',
      subtitle: '$formatted · ${DateFormat('HH:mm').format(r.generatedAt)}',
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
          _section('👥 Фойдаланувчилар', [
            MetricRow(label: 'Жами', value: '${r.totalUsers} та'),
            MetricRow(label: 'Бугунги янги', value: '${r.newUsersToday} та'),
            MetricRow(label: 'Бугун фаол', value: '${r.activeUsersToday} та'),
            MetricRow(
                label: 'Блок',
                value: '${r.blockedUsers} та',
                valueColor: r.blockedUsers > 0
                    ? const Color(0xFFB71C1C)
                    : null),
          ]),
          _section('🚖 Ҳайдовчилар', [
            MetricRow(label: 'Жами', value: '${r.totalDrivers} та'),
            MetricRow(label: 'Ҳозир онлайн', value: '${r.onlineDriversNow} та'),
            MetricRow(
                label: 'Бугунги фаол',
                value: '${r.activeDriversToday} та'),
          ]),
          _section('📦 Буюртмалар', [
            MetricRow(label: 'Жами', value: '${r.todayOrdersTotal} та'),
            ...r.todayOrdersByStatus.entries.map(
                (e) => MetricRow(label: e.key, value: '${e.value} та')),
            ...r.todayOrdersByType.entries.map(
                (e) => MetricRow(label: e.key, value: '${e.value} та')),
            if (r.todayRejectReasons.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.only(top: 6, bottom: 2),
                child: Text('Рад сабаблари:',
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFB71C1C),
                        fontWeight: FontWeight.w600)),
              ),
              ...r.todayRejectReasons.entries.map(
                  (e) => MetricRow(label: e.key, value: '${e.value} та')),
            ],
          ]),
          _section('🛣 Сафарлар', [
            MetricRow(label: 'Жами', value: '${r.todayTripsTotal} та'),
            ...r.todayTripsByStatus.entries.map(
                (e) => MetricRow(label: e.key, value: '${e.value} та')),
            ...r.todayTripsByTaxiType.entries.map(
                (e) => MetricRow(label: e.key, value: '${e.value} та')),
          ]),
          _section('💰 Молия', [
            MetricRow(
                icon: '💵',
                label: 'Бугунги тушум',
                value: '${_money.format(r.todayRevenue)} сўм',
                valueColor: AppColors.primary),
            MetricRow(
                label: 'Ҳафталик тушум',
                value: '${_money.format(r.weekRevenue)} сўм'),
            MetricRow(
                label: 'Ойлик тушум',
                value: '${_money.format(r.monthRevenue)} сўм'),
            MetricRow(
                label: 'Ўртача буюртма қиймати',
                value: '${_money.format(r.avgOrderValue.toInt())} сўм'),
            MetricRow(
                label: 'Ўртача сафар қиймати',
                value: '${_money.format(r.avgTripValue.toInt())} сўм'),
            MetricRow(
                label: 'Қайтарилган қолдиқ',
                value: '${_money.format(r.todayCashChange)} сўм'),
            MetricRow(
                label: 'Кошелёкдаги пул',
                value: '${_money.format(r.totalWalletBalance)} сўм'),
            MetricRow(
                label: 'Кутаётган payout',
                value:
                    '${r.pendingPayouts} та · ${_money.format(r.pendingPayoutsAmount)} сўм',
                valueColor: r.pendingPayouts > 0
                    ? AppColors.primary
                    : null),
          ]),
          _section('⚙️ Эффективлик', [
            MetricRow(
                label: 'Eng band соат',
                value: '${r.peakHour.toString().padLeft(2, '0')}:00'),
            MetricRow(
                label: 'Бекор қилиш',
                value: '${r.cancellationRate.toStringAsFixed(1)}%',
                valueColor: r.cancellationRate > 15
                    ? const Color(0xFFB71C1C)
                    : null),
          ]),
          if (r.topProducts.isNotEmpty)
            _section('🏆 Топ маҳсулотлар', [
              for (final p in r.topProducts)
                MetricRow(
                    label: p['label']?.toString() ?? '',
                    value: '${p['value']} та'),
            ]),
          if (r.topRoutes.isNotEmpty)
            _section('🛣 Топ маршрутлар', [
              for (final p in r.topRoutes)
                MetricRow(
                    label: p['label']?.toString() ?? '',
                    value: '${p['value']} та'),
            ]),
          if (r.topDrivers.isNotEmpty)
            _section('🥇 Топ ҳайдовчилар (сафар)', [
              for (final p in r.topDrivers)
                MetricRow(
                    label: p['label']?.toString() ?? '',
                    value: '${p['value']} та'),
            ]),
        ],
      ),
    );
  }

  Widget _emptyToday(bool loading) {
    return SectionCard(
      title: '📅 Бугунги ҳисобот',
      icon: '📊',
      child: Column(children: [
        Icon(Icons.assessment_outlined,
            size: 48, color: Colors.grey.shade300),
        const SizedBox(height: 8),
        Text(
          loading
              ? 'Юкланмоқда...'
              : 'Бугунги ҳисобот ҳали тайёр эмас.\nСоат 20:00 дан кейин ёки "Қайта-ясаш" тугмаси орқали.',
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
                '${r.todayOrdersTotal} буюртма · ${r.todayTripsTotal} сафар · ${_money.format(r.todayRevenue)} сўм',
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
