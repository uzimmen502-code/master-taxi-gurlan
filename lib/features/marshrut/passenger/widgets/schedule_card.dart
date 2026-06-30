import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';

import '../../../../models/schedule_search_result.dart';
import '../../../../core/theme/app_theme.dart';

/// Qidiruv natijasidagi bitta marshrut haydovchisi kartochkasi.
///
/// "ЧАҚИРИШ" tugmasi bosilganda [onCall] chaqiriladi.
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: _blue.withValues(alpha: 0.1),
            child: Text(firstChar,
                style: TextStyle(
                    fontSize: AppText.titleMedium,
                    fontWeight: FontWeight.bold,
                    color: _blue)),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.driverName,
                style: const TextStyle(
                    fontSize: AppText.bodyLarge,
                    fontWeight: FontWeight.bold)),
            Text('🚗 ${s.car} · ${s.plate}',
                style: TextStyle(
                    fontSize: AppText.bodySmall,
                    color: Colors.grey.shade500)),
          ])),
          if (eta != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: etaColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: etaColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                context.tr('marshrut_eta_arrival').replaceAll('{n}', '$eta'),
                style: TextStyle(
                  fontSize: AppText.bodySmall,
                  fontWeight: FontWeight.bold,
                  color: etaColor,
                ),
                maxLines: 2,
                textAlign: TextAlign.center,
              ),
            ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.route, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          Expanded(
              child: Text(
            '${s.from} → ${s.to}',
            style: TextStyle(
                fontSize: AppText.bodySmall, color: Colors.grey.shade600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )),
        ]),
        const SizedBox(height: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                      color: s.seatsLeft > 0 ? _green : Colors.red),
                ),
              ),
              const SizedBox(width: 8),
              if (s.price > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                      '💰 ${context.tr('price_sum_short').replaceAll('{price}', '${s.price}')}',
                      style: const TextStyle(
                          fontSize: AppText.labelSmall,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange)),
                ),
              const Spacer(),
            ]),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onCall,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
          ],
        ),
      ]),
    );
  }
}
