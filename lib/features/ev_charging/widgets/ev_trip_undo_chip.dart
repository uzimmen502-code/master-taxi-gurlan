import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';

/// Reja o'zgargandan keyin (stansiya almashtirildi / zaryad yangilandi)
/// xarita tepasida chiqadigan ixcham chip: "Режа янгиланди · Қайтариш".
/// Haydovchi o'zgarishni bir bosishda qaytara oladi yoki chipni yopadi.
/// Matn kesilmaydi - katta shriftda (1.3) ikkinchi qatorga o'tadi.
class EvTripUndoChip extends StatelessWidget {
  const EvTripUndoChip({
    super.key,
    required this.onUndo,
    required this.onClose,
  });

  final VoidCallback onUndo;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('ev_trip_undo_chip'),
      color: Colors.white,
      elevation: 4,
      shape: const StadiumBorder(
        side: BorderSide(color: AppColors.primaryDark, width: 1.4),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 14, end: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  context.tr('ev_replan_done'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onPrimary,
                  ),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('ev_trip_undo_button'),
                onPressed: onUndo,
                icon: const Icon(Icons.undo_rounded, size: 20),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryText,
                  minimumSize: const Size(0, 44),
                  textStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800),
                ),
                label: Text(context.tr('ev_undo')),
              ),
              IconButton(
                key: const ValueKey('ev_trip_undo_close'),
                tooltip: context.tr('close'),
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded,
                    size: 20, color: AppColors.primaryText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
