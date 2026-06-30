import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../models/active_trip.dart';
import '../../../../core/theme/app_theme.dart';

/// Driver panelidagi pending buyurtma karta'i — qisqacha ma'lumot va "КЎРИШ" tugmasi.
class RideRequestCard extends StatelessWidget {
  const RideRequestCard({
    super.key,
    required this.ride,
    required this.onView,
    this.color = AppColors.primaryDark,
  });

  final ActiveTrip ride;
  final VoidCallback onView;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)
        ],
      ),
      child: Row(children: [
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('📍 ${ride.pickupMfy}',
              style: const TextStyle(
                  fontSize: AppText.bodyMedium, fontWeight: FontWeight.bold)),
          if (ride.fromAddr.isNotEmpty)
            Text('🏠 ${ride.fromAddr}',
                style: TextStyle(
                    fontSize: AppText.labelSmall,
                    color: Colors.grey.shade500)),
          Text('🏁 ${ride.dropoffMfy}',
              style: TextStyle(
                  fontSize: AppText.labelSmall, color: Colors.grey.shade500)),
          Text('📞 ${ride.userPhone}',
              style: TextStyle(
                  fontSize: AppText.labelSmall, color: Colors.grey.shade400)),
        ])),
        GestureDetector(
          onTap: onView,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(10)),
            child: Text(context.tr('marshrut_view_request'),
                style: const TextStyle(
                    fontSize: AppText.labelSmall,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }
}
