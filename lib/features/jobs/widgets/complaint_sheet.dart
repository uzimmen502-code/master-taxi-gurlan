import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Эълонга шикоят сабабини танлаш bottom sheet'и.
Future<String?> showComplaintSheet(BuildContext context) {
  const reasons = <String>[
    '🚫 Алдамчи эълон',
    '📞 Телефон нотўғри',
    '🗑️ Спам / Такрорий',
    '⚠️ Ҳақоратли матн',
  ];
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Шикоят',
            style: TextStyle(
                fontSize: AppText.titleMedium, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...reasons.map((r) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r,
                    style: const TextStyle(fontSize: AppText.bodyLarge)),
                onTap: () => Navigator.of(context).pop(r),
              )),
        ],
      ),
    ),
  );
}
