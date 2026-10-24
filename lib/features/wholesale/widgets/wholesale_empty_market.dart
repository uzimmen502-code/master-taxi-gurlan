import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';

/// Бўш лента: «ҳеч нарса йўқ» эмас, нима қилиш мумкинлигини айтади —
/// қидирув бўлса «тозалаш» тугмаси, ҳудуд торайтирилган бўлса ҳудудни
/// ўзгартириш таклифи.
class WholesaleEmptyMarket extends StatelessWidget {
  const WholesaleEmptyMarket({
    super.key,
    required this.hasQuery,
    required this.narrowedArea,
    required this.onClearSearch,
  });

  final bool hasQuery;
  final bool narrowedArea;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 48, color: AppColors.sectionMuted),
            const SizedBox(height: 12),
            Text(
              context.tr('wholesale_empty_products'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (narrowedArea) ...[
              const SizedBox(height: 6),
              Text(
                context.tr('wholesale_empty_try_area'),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.sectionMuted),
              ),
            ],
            if (hasQuery) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: onClearSearch,
                icon: const Icon(Icons.close, size: 20),
                label: Text(context.tr('wholesale_empty_clear_search')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
