import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../ava_store_colors.dart';

/// «AVA бонуси −X сўм» қатори (рағбат, эга 2026-11-02): саватча ва тасдиқлаш ойнасида.
/// Бонус бўлмаса (ёки шу саватга тўғри келмаса) — ҳеч нарса чизилмайди.
class IncentiveBonusRow extends StatelessWidget {
  const IncentiveBonusRow({
    super.key,
    required this.available,
    required this.applied,
    required this.enabled,
    required this.onChanged,
  });

  /// Сервер ҳисоблаган шу саватга қўлланадиган бонус.
  final int available;

  /// Ҳозир қўлланаётгани (ўчирилган бўлса 0).
  final int applied;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    if (available <= 0) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('incentive_bonus_row'),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.card_giftcard, size: 18, color: AppColors.primaryText),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('incentive_bonus_label'),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AvaStoreColors.ink),
                ),
                Text(
                  context.tr('incentive_bonus_hint'),
                  style: const TextStyle(fontSize: 11, color: AvaStoreColors.muted),
                ),
              ],
            ),
          ),
          Text(
            '−${formatPrice(enabled ? applied : available)} ${context.tr('sum')}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: enabled ? AppColors.primaryText : AvaStoreColors.muted,
              decoration: enabled ? null : TextDecoration.lineThrough,
            ),
          ),
          Switch(
            key: const ValueKey('incentive_bonus_switch'),
            value: enabled,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
