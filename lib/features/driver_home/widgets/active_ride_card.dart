import 'package:flutter/material.dart';

import '../../../models/trip_request.dart';
import '../../../core/theme/app_theme.dart';

/// ТљР°Р±СѓР» Т›РёР»РёРЅРіР°РЅ С„Р°РѕР» СЃР°С„Р°СЂ РєР°СЂС‚Р°СЃРё вЂ” "РЇРєСѓРЅР»Р°С€" С‚СѓРіРјР°СЃРё Р±РёР»Р°РЅ.
class ActiveRideCard extends StatelessWidget {
  const ActiveRideCard({
    super.key,
    required this.ride,
    required this.onComplete,
  });

  final TripRequest ride;
  final VoidCallback onComplete;

  static const _green = AppColors.primaryDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _green.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.directions_car, color: _green, size: 20),
          SizedBox(width: 8),
          Text('Р¤Р°РѕР» СЃР°С„Р°СЂ',
              style: TextStyle(
                  fontSize: AppText.bodyLarge,
                  fontWeight: FontWeight.bold,
                  color: _green)),
        ]),
        const SizedBox(height: 10),
        Text('рџ“ћ ${ride.userPhone}',
            style: const TextStyle(
                fontSize: AppText.bodyMedium,
                fontWeight: FontWeight.w600)),
        Text('рџ“Ќ ${ride.from} в†’ ${ride.to}',
            style: TextStyle(
                fontSize: AppText.bodySmall, color: Colors.grey.shade700)),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onComplete,
            icon: const Icon(Icons.check_circle, size: 18),
            label: const Text('РЎРђР¤РђР РќР РЇРљРЈРќР›РђРЁ'),
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
