import 'package:flutter/material.dart';

import '../../../../models/schedule_search_result.dart';
import '../../../../utils/app_theme.dart';

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

  static const Color _blue = Color(0xFF0288D1);
  static const Color _green = Color(0xFF039BE5);

  @override
  Widget build(BuildContext context) {
    final s = result.schedule;
    final eta = result.etaMin ?? 3;
    final etaColor =
        eta <= 3 ? _green : eta <= 7 ? Colors.orange : Colors.grey;
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
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: _blue.withOpacity(0.1),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: etaColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: etaColor.withOpacity(0.3)),
            ),
            child: Column(children: [
              Text('$eta дақ',
                  style: TextStyle(
                      fontSize: AppText.bodyLarge,
                      fontWeight: FontWeight.bold,
                      color: etaColor)),
              Text('ETA',
                  style: TextStyle(
                      fontSize: AppText.labelTiny, color: etaColor)),
            ]),
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
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
                color: s.seatsLeft > 0
                    ? _green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Text('💺 ${s.seatsLeft} ўрин',
                style: TextStyle(
                    fontSize: AppText.labelSmall,
                    fontWeight: FontWeight.w600,
                    color: s.seatsLeft > 0 ? _green : Colors.red)),
          ),
          const SizedBox(width: 8),
          if (s.price > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text('💰 ${s.price} сўм',
                  style: const TextStyle(
                      fontSize: AppText.labelSmall,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange)),
            ),
          const Spacer(),
          GestureDetector(
            onTap: onCall,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                  color: _green, borderRadius: BorderRadius.circular(10)),
              child: const Row(children: [
                Icon(Icons.notifications_active,
                    color: Colors.white, size: 16),
                SizedBox(width: 6),
                Text('ЧАҚИРИШ',
                    style: TextStyle(
                        fontSize: AppText.bodySmall,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }
}
