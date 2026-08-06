import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../jobs_colors.dart';

/// "Шошилинч" чекбокс — «Эълон» учун.
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
          color: isUrgent ? JobsColors.urgentSoft : JobsColors.fieldFill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isUrgent ? JobsColors.urgent : JobsColors.border),
        ),
        child: Row(children: [
          Icon(
            isUrgent ? Icons.priority_high_rounded : Icons.schedule_rounded,
            size: 22,
            color: isUrgent ? JobsColors.urgent : JobsColors.muted,
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Шошилинч',
                style: TextStyle(
                    fontSize: AppText.bodyMedium,
                    fontWeight: FontWeight.w600,
                    color: isUrgent ? JobsColors.urgent : JobsColors.muted)),
            if (showHint)
              const Text('Алоҳида «Шошилинч» бўлимида кўринади',
                  style: TextStyle(
                      fontSize: AppText.labelTiny,
                      color: JobsColors.hint)),
          ]),
          const Spacer(),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: isUrgent ? JobsColors.urgent : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: isUrgent ? JobsColors.urgent : JobsColors.hint),
            ),
            child: isUrgent
                ? const Icon(Icons.check, color: JobsColors.onBar, size: 14)
                : null,
          ),
        ]),
      ),
    );
  }
}
