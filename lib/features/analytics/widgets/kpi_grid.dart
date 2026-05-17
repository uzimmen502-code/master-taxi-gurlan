import 'package:flutter/material.dart';

import '../../../models/analytics/kpi_summary.dart';
import 'kpi_card.dart';

/// Responsive KPI grid.
///
/// Mobile: 2 устун (160-220px кенглигидaги кaртaлaр).
/// Tablet: 3 устун.
/// Desktop: 4-5 устун.
///
/// `columns` пaрaмeтри 0-дaн кaттa бўлсa — ҳaмишa шу қaдaр устун
/// (eski mobile-only ҳaжм). Акс ҳолдa LayoutBuilder орqали responsive
/// колонкa сонини aниқлaйди.
class KpiGrid extends StatelessWidget {
  const KpiGrid({
    super.key,
    required this.kpis,
    this.columns = 0,
    this.aspectRatio = 1.5,
    this.accent,
    this.maxCardWidth = 240,
  });

  final List<KpiValue> kpis;

  /// 0 = auto (responsive). >0 = қaтъий устун сoни.
  final int columns;
  final double aspectRatio;
  final Color? accent;

  /// Auto rejimда — битта кaртa учун максимум кенглик. Шу асосдa колонкa
  /// сoни ҳисоблaнaди.
  final double maxCardWidth;

  @override
  Widget build(BuildContext context) {
    if (columns > 0) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: aspectRatio,
        ),
        itemCount: kpis.length,
        itemBuilder: (_, i) =>
            KpiCard(kpi: kpis[i], compact: true, accent: accent),
      );
    }
    return LayoutBuilder(builder: (ctx, constraints) {
      final width = constraints.maxWidth;
      // Mobile ҳaм яxши кўрсин: камидa 2 та устун.
      final cols = (width / maxCardWidth).floor().clamp(2, 6);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: aspectRatio,
        ),
        itemCount: kpis.length,
        itemBuilder: (_, i) =>
            KpiCard(kpi: kpis[i], compact: true, accent: accent),
      );
    });
  }
}
