import 'package:flutter/material.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/theme/app_theme.dart';

import '../../../models/analytics/kpi_summary.dart';

/// Битта KPI кадрни кўрсатувчи карта — асосий рақам + delta тенглик.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.kpi,
    this.compact = false,
    this.accent,
  });

  final KpiValue kpi;
  final bool compact;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final clr = accent ?? AppColors.primary;
    final delta = kpi.deltaPercent;
    final isUp = kpi.isPositive;
    final hasDelta = delta != null && delta.isFinite;
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: clr.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            if (kpi.icon != null) ...[
              Text(kpi.icon!, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                kpi.label,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            formatPrice(kpi.value),
            style: TextStyle(
                fontSize: compact ? 18 : 22,
                fontWeight: FontWeight.bold,
                color: clr),
          ),
          if (kpi.unit.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(kpi.unit,
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500)),
            ),
          if (hasDelta) ...[
            const SizedBox(height: 6),
            Row(children: [
              Icon(
                  isUp
                      ? Icons.trending_up
                      : (delta == 0
                          ? Icons.trending_flat
                          : Icons.trending_down),
                  size: 14,
                  color: isUp
                      ? AppColors.primary
                      : (delta == 0
                          ? Colors.grey
                          : const Color(0xFFB71C1C))),
              const SizedBox(width: 4),
              Text(
                '${delta.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isUp
                      ? AppColors.primary
                      : (delta == 0
                          ? Colors.grey
                          : const Color(0xFFB71C1C)),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'аввалгидан',
                style: TextStyle(
                    fontSize: 10, color: Colors.grey.shade500),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}
