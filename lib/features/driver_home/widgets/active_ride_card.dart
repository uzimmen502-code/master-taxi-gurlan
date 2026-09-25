import 'package:flutter/material.dart';

import '../../../models/trip_request.dart';
import '../../../core/theme/app_theme.dart';

/// Қабул қилинган фаол сафар картаси — "Якунлаш" тугмаси билан.
class ActiveRideCard extends StatelessWidget {
  const ActiveRideCard({
    super.key,
    required this.ride,
    required this.onComplete,
    this.onArrived,
  });

  final TripRequest ride;
  final VoidCallback onComplete;

  /// «Етиб келдим» — йўловчининг бош саҳифасидаги карточка «Йўлда» дан
  /// «Етиб келди» га ўтади. `null` бўлса тугма кўрсатилмайди.
  final VoidCallback? onArrived;

  static const _green = AppColors.primaryDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AvaLight.okSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _green.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.directions_car, color: _green, size: 20),
          SizedBox(width: 8),
          Text('Фаол сафар',
              style: TextStyle(
                  fontSize: AppText.bodyLarge,
                  fontWeight: FontWeight.bold,
                  color: _green)),
        ]),
        const SizedBox(height: 10),
        Text('📞 ${ride.userPhone}',
            style: const TextStyle(
                fontSize: AppText.bodyMedium,
                fontWeight: FontWeight.w600)),
        Text('📍 ${ride.from} → ${ride.to}',
            style: TextStyle(
                fontSize: AppText.bodySmall, color: Colors.grey.shade700)),
        const SizedBox(height: 10),
        if (onArrived != null && !ride.hasArrived)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onArrived,
              icon: const Icon(Icons.where_to_vote_outlined, size: 18),
              label: const Text('ЕТИБ КЕЛДИМ'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _green,
                side: const BorderSide(color: _green),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          )
        else if (ride.hasArrived)
          Row(
            children: const [
              Icon(Icons.where_to_vote, color: _green, size: 16),
              SizedBox(width: 6),
              Text(
                'Йўловчи хабардор қилинди',
                style: TextStyle(
                  fontSize: AppText.bodySmall,
                  fontWeight: FontWeight.w600,
                  color: _green,
                ),
              ),
            ],
          ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onComplete,
            icon: const Icon(Icons.check_circle, size: 18),
            label: const Text('САФАРНИ ЯКУНЛАШ'),
            style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
          ),
        ),
      ]),
    );
  }
}
