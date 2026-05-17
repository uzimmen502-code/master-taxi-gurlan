import 'package:flutter/material.dart';

import '../../../../utils/app_theme.dart';

/// Marshrut driver panelidagi katta online toggle — switch + navbat o'rni.
class OnlineToggleTile extends StatelessWidget {
  const OnlineToggleTile({
    super.key,
    required this.isOnline,
    required this.queuePosition,
    required this.onTap,
    this.color = const Color(0xFF00695C),
  });

  final bool isOnline;
  final int queuePosition;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isOnline ? const Color(0xFFE8F5E9) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color:
                  isOnline ? color.withOpacity(0.4) : Colors.grey.shade300,
              width: 1.5),
        ),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: (isOnline ? color : Colors.grey).withOpacity(0.15),
                shape: BoxShape.circle),
            child: Icon(
                isOnline ? Icons.wifi : Icons.wifi_off,
                color: isOnline ? color : Colors.grey,
                size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isOnline ? '🟢 Онлайн' : '⚫ Оффлайн',
                style: TextStyle(
                    fontSize: AppText.bodyLarge,
                    fontWeight: FontWeight.bold,
                    color: isOnline ? color : Colors.grey.shade600)),
            Text(
              isOnline
                  ? 'Навбат: $queuePosition-ўрин'
                  : 'Буюртмалар тўхтатилган',
              style: TextStyle(
                  fontSize: AppText.labelSmall, color: Colors.grey.shade500),
            ),
          ])),
          Container(
            width: 52,
            height: 28,
            decoration: BoxDecoration(
                color: isOnline ? color : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(14)),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              alignment:
                  isOnline ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.all(4),
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
