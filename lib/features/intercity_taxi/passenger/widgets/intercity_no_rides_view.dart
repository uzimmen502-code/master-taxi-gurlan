import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../intercity_colors.dart';

/// Natijalar sahifasidagi YAGONA bo'sh holat (avval bo'sh sahifa + takror
/// snackbar chiqardi). Sabab matni shu yerda; ikki foydali amal:
/// keyingi kunni qidirish ("Ertaga") va qayta qidirish.
class IntercityNoRidesView extends StatelessWidget {
  const IntercityNoRidesView({
    super.key,
    required this.reasonKey,
    required this.isToday,
    required this.canSearchNextDay,
    required this.onSearchNextDay,
    required this.onSearchAgain,
  });

  /// `no_driver_today` / `no_driver_tomorrow` / `no_driver_on_date` /
  /// `no_seats_for_passenger_count` yoki `null` (sabab noma'lum).
  final String? reasonKey;

  /// Qidirilayotgan kun bugunmi: shunda tugma "Ertaga qidirish", aks holda
  /// "Keyingi kunni qidirish".
  final bool isToday;

  /// Keyingi kun qidiruv chegarasidan (30 kun) oshmaydimi.
  final bool canSearchNextDay;

  final VoidCallback onSearchNextDay;
  final VoidCallback onSearchAgain;

  @override
  Widget build(BuildContext context) {
    final reason = reasonKey;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.directions_bus_outlined,
              size: 64,
              color: IntercityColors.textFaint,
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('intercity_no_rides'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: IntercityColors.text,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (reason != null) ...[
              const SizedBox(height: 8),
              Text(
                context.tr(reason),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: IntercityColors.textMuted,
                  fontSize: 14,
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (canSearchNextDay)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onSearchNextDay,
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(context.tr(isToday
                      ? 'intercity_search_tomorrow'
                      : 'intercity_search_next_day')),
                  style: FilledButton.styleFrom(
                    backgroundColor: IntercityColors.primary,
                    foregroundColor: IntercityColors.onPrimary,
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ),
            if (canSearchNextDay) const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onSearchAgain,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(context.tr('intercity_search_again')),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
