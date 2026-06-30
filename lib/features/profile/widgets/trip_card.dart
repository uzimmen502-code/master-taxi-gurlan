import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/trip_model.dart';

class TripCard extends StatelessWidget {
  const TripCard({
    super.key,
    required this.trip,
    required this.isDriver,
  });

  final TripModel trip;
  final bool isDriver;

  static const _green = AppColors.primaryDark;
  static const _blue = AppColors.primary;

  String _emojiFor(String taxiType) {
    switch (taxiType) {
      case 'marshrut':
        return '🚐';
      case 'intercity':
        return '🚌';
      default:
        return '🚕';
    }
  }

  String get _dateStr {
    final d = trip.completedAt;
    if (d == null) return '';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$dd.$mm $hh:$min';
  }

  @override
  Widget build(BuildContext context) {
    final personName =
        isDriver ? trip.userPhone : trip.driverName;
    final carInfo = isDriver ? '' : trip.driverCar;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(children: [
        Text(_emojiFor(trip.taxiType), style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                trip.from.isEmpty ? 'Йўналиш' : '${trip.from} → ${trip.to}',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (personName.isNotEmpty)
                Text(
                  isDriver
                      ? '📞 $personName'
                      : '🚗 $personName${carInfo.isNotEmpty ? " · $carInfo" : ""}',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500),
                ),
            ],
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            '${formatPrice(trip.fare)} сўм',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDriver ? _green : _blue),
          ),
          if (_dateStr.isNotEmpty)
            Text(_dateStr,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
        ]),
      ]),
    );
  }
}
