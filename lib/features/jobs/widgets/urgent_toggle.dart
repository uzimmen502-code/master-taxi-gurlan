import 'package:flutter/material.dart';

import '../../../utils/app_theme.dart';

/// "Шошилинч" чекбокс — иш эълонлари учун.
class UrgentToggle extends StatelessWidget {
  const UrgentToggle({
    super.key,
    required this.isUrgent,
    required this.onTap,
    this.showHint = true,
  });

  final bool isUrgent;
  final VoidCallback onTap;
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isUrgent ? Colors.red.shade50 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isUrgent ? Colors.red.shade300 : Colors.grey.shade300),
        ),
        child: Row(children: [
          Text(isUrgent ? '🚨' : '⏰',
              style: const TextStyle(fontSize: AppText.titleLarge)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Шошилинч',
                style: TextStyle(
                    fontSize: AppText.bodyMedium,
                    fontWeight: FontWeight.w600,
                    color: isUrgent ? Colors.red : Colors.grey.shade600)),
            if (showHint)
              Text('Рўйхат бошига чиқади',
                  style: TextStyle(
                      fontSize: AppText.labelTiny,
                      color: Colors.grey.shade500)),
          ]),
          const Spacer(),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: isUrgent ? Colors.red : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: isUrgent ? Colors.red : Colors.grey.shade400),
            ),
            child: isUrgent
                ? const Icon(Icons.check, color: Colors.white, size: 14)
                : null,
          ),
        ]),
      ),
    );
  }
}
