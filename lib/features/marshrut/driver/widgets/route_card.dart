import 'package:flutter/material.dart';

import '../../../../utils/app_theme.dart';

/// Bugungi marshrut karta'i — qaerdan-qayerga, to'xtash chiplari, o'rinlar
/// ko'rsatkichi ва йўналишни ўзгартириш тугмаси.
class RouteCard extends StatelessWidget {
  const RouteCard({
    super.key,
    required this.stops,
    required this.direction,
    required this.seatsLeft,
    required this.onSwitchDirection,
    this.color = const Color(0xFF00695C),
    this.errorColor = const Color(0xFFB71C1C),
  });

  final List<String> stops;
  final String direction;
  final int seatsLeft;
  final VoidCallback onSwitchDirection;
  final Color color;
  final Color errorColor;

  @override
  Widget build(BuildContext context) {
    final from = stops.isNotEmpty ? stops.first : '';
    final to = stops.isNotEmpty ? stops.last : '';
    final routeText = direction == 'forward' ? '$from → $to' : '$to → $from';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(routeText,
            style: const TextStyle(
                fontSize: AppText.bodyMedium, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: stops
              .map((s) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(s,
                        style: TextStyle(
                            fontSize: AppText.labelTiny, color: color)),
                  ))
              .toList(),
        ),
        const SizedBox(height: 10),
        Text(
          seatsLeft == 0 ? '🚫 Бўш жой йўқ' : '💺 $seatsLeft та бўш жой',
          style: TextStyle(
              fontSize: AppText.bodyMedium,
              fontWeight: FontWeight.bold,
              color: seatsLeft == 0 ? errorColor : color),
        ),
        const SizedBox(height: 10),
        Center(
          child: GestureDetector(
            onTap: onSwitchDirection,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(10)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_horiz, size: 16, color: Colors.black),
                  SizedBox(width: 6),
                  Text('ЙЎНАЛИШНИ ЎЗГАРТИРИШ',
                      style: TextStyle(
                          fontSize: AppText.labelSmall,
                          color: Colors.black,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
