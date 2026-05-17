import 'package:flutter/material.dart';

import '../../../../models/active_trip.dart';
import '../../../../utils/app_theme.dart';

/// Driver panelidagi pending buyurtma karta'i — qisqacha ma'lumot va "КЎРИШ" tugmasi.
class RideRequestCard extends StatelessWidget {
  const RideRequestCard({
    super.key,
    required this.ride,
    required this.onView,
    this.color = const Color(0xFF00695C),
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
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)
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
