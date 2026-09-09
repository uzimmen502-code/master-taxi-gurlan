import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/analytics/kpi_summary.dart';
import '../../../models/analytics/tv_playback_analytics.dart';
import '../controllers/analytics_controller.dart';
import '../widgets/donut_chart.dart';
import '../widgets/kpi_grid.dart';
import '../widgets/metric_row.dart';
import '../widgets/section_card.dart';
import '../widgets/top_list.dart';

/// 6-таб: TV Market playback сифати (video_engine лойиҳаси, 5-босқич).
///
/// Rollup ҳужжат йўқ — `tv_clips.playbackStats` denormalized
/// hisoblagichlaridan yig'ilgan "hozirgi holat" ko'rsatkichlari
/// (kunlik trend/heatmap yo'q, chunki ma'lumot vaqt-buketlarga
/// bo'linmagan).
class TvMarketTab extends StatefulWidget {
  const TvMarketTab({super.key});

  @override
  State<TvMarketTab> createState() => _TvMarketTabState();
}

class _TvMarketTabState extends State<TvMarketTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AnalyticsController>().loadTv();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.watch<AnalyticsController>();
    if (c.tvLoading && c.tvAnalytics == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final t = c.tvAnalytics;
    if (t == null) {
      return Center(
        child: Text(c.tvError ?? 'Маълумот юклаб бўлмади',
            style: const TextStyle(color: Colors.red)),
      );
    }

    final wide = MediaQuery.of(context).size.width > 800;
    final pad = wide ? 24.0 : 12.0;
    return RefreshIndicator(
      onRefresh: () => c.loadTv(force: true),
      child: ListView(
        padding: EdgeInsets.fromLTRB(pad, pad, pad, 80),
        children: [
          if (t.clipsWithData == 0)
            SectionCard(
              title: 'TV Market playback',
              icon: '🎬',
              child: Text(
                'Ҳали playback маълумоти йўқ — фойдаланувчилар клип '
                'кўра бошлагач бу ерда рефбуфер/tugatish ko\'rsatkichlari '
                'chiqadi.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            )
          else ...[
            _tvKpis(t),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SectionCard(
                    title: 'Кўриш натижаси',
                    icon: '📊',
                    child: DonutChart(breakdown: t.outcomeBreakdown, size: 130),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SectionCard(
                    title: 'Сифат метрикалари',
                    icon: '⚙️',
                    child: Column(children: [
                      MetricRow(
                        icon: '⏱',
                        label: 'Биринчи кадр (ўртача)',
                        value: '${t.avgFirstFrameMs.round()} ms',
                        valueColor: t.avgFirstFrameMs > 2000
                            ? const Color(0xFFB71C1C)
                            : null,
                      ),
                      MetricRow(
                        icon: '🧊',
                        label: 'Rebuffer ratio',
                        value: '${t.rebufferRatio.toStringAsFixed(1)}%',
                        valueColor: t.rebufferRatio > 5
                            ? const Color(0xFFB71C1C)
                            : null,
                      ),
                      MetricRow(
                        icon: '❌',
                        label: 'Хато даражаси',
                        value: '${t.errorRate.toStringAsFixed(1)}%',
                      ),
                      MetricRow(
                        icon: '📦',
                        label: 'Скан қилинган клип',
                        value: '${t.clipsWithData}',
                      ),
                    ]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'Топ кўрилган клиплар',
              icon: '🏆',
              child: TopList(
                items: t.topViewed,
                color: AppColors.primary,
                maxItems: 10,
                formatValue: (v) => '${v.toInt()}',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tvKpis(TvPlaybackAnalytics t) {
    return SectionCard(
      title: 'TV Market KPI',
      icon: '🎬',
      child: KpiGrid(
        aspectRatio: 1.45,
        accent: AppColors.primary,
        kpis: [
          KpiValue(label: 'Жами кўриш', value: t.totalViews, unit: 'та', icon: '👁'),
          KpiValue(
            label: 'Тугатиш даражаси',
            value: t.completionRate,
            unit: '%',
            icon: '✅',
          ),
          KpiValue(
            label: "Ўтказиб юбориш",
            value: t.skipRate,
            unit: '%',
            icon: '⏭',
          ),
          KpiValue(
            label: 'Rebuffer',
            value: t.rebufferRatio,
            unit: '%',
            icon: '🧊',
          ),
        ],
      ),
    );
  }
}
