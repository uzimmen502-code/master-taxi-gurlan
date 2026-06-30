import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// "ИШНИ БОШЛАШ" ва "ИШНИ ТУГАТИШ" тугмалари.
class MainActionButtons extends StatelessWidget {
  const MainActionButtons({
    super.key,
    required this.hasScheduleToday,
    required this.onStart,
    required this.onEnd,
    this.isOnline = false,
  });

  final bool hasScheduleToday;
  final VoidCallback onStart;
  final VoidCallback onEnd;
  final bool isOnline;

  static const _green = AppColors.primaryDark;
  static const _red = Color(0xFFB71C1C);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: GestureDetector(
        onTap: onStart,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [AppColors.primaryDark, AppColors.primary]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: _green.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Column(children: [
            Icon(isOnline ? Icons.check_circle : Icons.play_circle_fill,
                color: Colors.white, size: 28),
            const SizedBox(height: 6),
            Text(isOnline ? 'ИШ БОШЛАНДИ' : 'ИШНИ БОШЛАШ',
                style: const TextStyle(
                    fontSize: AppText.bodyMedium,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ]),
        ),
      )),
      const SizedBox(width: 12),
      Expanded(child: GestureDetector(
        onTap: hasScheduleToday ? onEnd : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: hasScheduleToday
                ? const LinearGradient(
                    colors: [Color(0xFF7F0000), Color(0xFFB71C1C)])
                : LinearGradient(
                    colors: [Colors.grey.shade300, Colors.grey.shade400]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: hasScheduleToday
                ? [
                    BoxShadow(
                        color: _red.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4)),
                  ]
                : null,
          ),
          child: Column(children: [
            Icon(Icons.stop_circle,
                color: hasScheduleToday ? Colors.white : Colors.grey.shade600,
                size: 28),
            const SizedBox(height: 6),
            Text(isOnline ? 'ИШНИ ТУГАТИШ' : 'ИШ ТУГАДИ',
                style: TextStyle(
                    fontSize: AppText.bodyMedium,
                    fontWeight: FontWeight.bold,
                    color: hasScheduleToday
                        ? Colors.white
                        : Colors.grey.shade600)),
          ]),
        ),
      )),
    ]);
  }
}
