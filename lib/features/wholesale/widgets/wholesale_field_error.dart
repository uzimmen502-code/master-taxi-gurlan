import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';

/// Майдон/бўлим остидаги хато матни: қизил + иконка (ранг ёлғиз белги эмас),
/// экран ўқувчи пайдо бўлганда ўқийди (`liveRegion`). [textKey] — матн калити.
class WholesaleFieldError extends StatelessWidget {
  const WholesaleFieldError({super.key, required this.textKey});

  final String textKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 16, color: AppColors.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                context.tr(textKey),
                style: TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
