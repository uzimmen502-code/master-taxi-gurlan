import 'package:flutter/material.dart';

import '../../../models/trip_request.dart';
import '../../../core/theme/app_theme.dart';

/// "Янги буюртмалар" рўйхатидаги битта карта — таймер билан.
class TripRequestCard extends StatelessWidget {
  const TripRequestCard({
    super.key,
    required this.ride,
    required this.onTap,
  });

  final TripRequest ride;
  final VoidCallback onTap;

  static const _blue = AppColors.primary;
  static const _green = AppColors.primaryDark;
  static const _orange = AppColors.primary;
  static const _red = Color(0xFFB71C1C);

  @override
  Widget build(BuildContext context) {
    final secs = ride.secsLeft;
    final m = secs ~/ 60;
    final s = secs % 60;
    final color = secs > 60 ? _green : secs > 30 ? _orange : _red;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: secs <= 30
            ? Border.all(color: _red.withOpacity(0.4), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
        ],
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ride.from,
                  style: const TextStyle(
                      fontSize: AppText.bodyMedium,
                      fontWeight: FontWeight.bold)),
              if (ride.to.isNotEmpty)
                Text('→ ${ride.to}',
                    style: TextStyle(
                        fontSize: AppText.labelSmall,
                        color: Colors.grey.shade500)),
              Text(ride.userPhone,
                  style: TextStyle(
                      fontSize: AppText.labelSmall,
                      color: Colors.grey.shade400)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.3))),
          child: Column(children: [
            Text('$m:${s.toString().padLeft(2, '0')}',
                style: TextStyle(
                    fontSize: AppText.bodyLarge,
                    fontWeight: FontWeight.bold,
                    color: color)),
            const Text('⏱', style: TextStyle(fontSize: AppText.labelTiny)),
          ]),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: _blue, borderRadius: BorderRadius.circular(10)),
            child: const Text('КЎРИШ',
                style: TextStyle(
                    fontSize: AppText.labelSmall,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }
}
