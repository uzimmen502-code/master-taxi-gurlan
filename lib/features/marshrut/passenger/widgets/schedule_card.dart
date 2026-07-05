import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';

import '../../../../models/schedule_search_result.dart';
import '../../../../core/theme/app_theme.dart';

/// Qidiruv natijasidagi haydovchi kartochkasi (Phase A — ixcham).
class ScheduleCard extends StatelessWidget {
  const ScheduleCard({
    super.key,
    required this.result,
    required this.onCall,
  });

  final ScheduleSearchResult result;
  final VoidCallback onCall;

  static const Color _blue = AppColors.primary;
  static const Color _green = Color(0xFF039BE5);

  @override
  Widget build(BuildContext context) {
    final s = result.schedule;
    final eta = result.etaMin;
    final etaColor = eta == null
        ? Colors.grey
        : eta <= 3
            ? _green
            : eta <= 7
                ? Colors.orange
                : Colors.grey;
    final firstChar =
        s.driverName.isNotEmpty ? s.driverName.substring(0, 1) : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eta != null)
                Container(
                  width: 52,
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  decoration: BoxDecoration(
                    color: etaColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: etaColor.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$eta',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: etaColor,
                          height: 1,
                        ),
                      ),
                      Text(
                        context.tr('marshrut_eta_min_unit'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: etaColor,
                        ),
                      ),
                    ],
                  ),
                )
              else
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _blue.withValues(alpha: 0.1),
                  child: Text(firstChar,
                      style: TextStyle(
                          fontSize: AppText.titleMedium,
                          fontWeight: FontWeight.bold,
                          color: _blue)),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.driverName,
                        style: const TextStyle(
                            fontSize: AppText.bodyLarge,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text('🚗 ${s.car} · ${s.plate}',
                        style: TextStyle(
                            fontSize: AppText.bodySmall,
                            color: Colors.grey.shade600)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: s.seatsLeft > 0
                                  ? _green.withValues(alpha: 0.1)
                                  : Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(
                            context
                                .tr('marshrut_seats_available')
                                .replaceAll('{n}', '${s.seatsLeft}'),
                            style: TextStyle(
                                fontSize: AppText.labelSmall,
                                fontWeight: FontWeight.w600,
                                color:
                                    s.seatsLeft > 0 ? _green : Colors.red),
                          ),
                        ),
                        if (s.price > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            context
                                .tr('price_sum_short')
                                .replaceAll('{price}', '${s.price}'),
                            style: const TextStyle(
                              fontSize: AppText.labelSmall,
                              fontWeight: FontWeight.w700,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onCall,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.button,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.notifications_active,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    context.tr('marshrut_call_system'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('marshrut_call_hint'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
