import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';

/// Эгаси: таҳрир + ўчириш.
///
/// Баландлик 44 → 26 px (эга, 2026-11-03: «40% га кичрайтир»). Шу баландликка
/// сиғиши учун ички вертикал бўшлиқ 0, Material'нинг 48 px минимал босиш майдони
/// олиб ташланган, матн 15 → 13, иконка 18 → 15.
class TvOwnerActionBar extends StatelessWidget {
  const TvOwnerActionBar({
    super.key,
    required this.onEdit,
    required this.onDelete,
    this.height = defaultHeight,
  });

  static const double defaultHeight = 26;

  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final double height;

  static const _label = TextStyle(fontWeight: FontWeight.w700, fontSize: 13, height: 1);
  static const _padding = EdgeInsets.symmetric(horizontal: 10);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('tv-owner-edit'),
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 15),
              label: Text(context.tr('tv_market_edit'), style: _label),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70, width: 1.2),
                padding: _padding,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              key: const ValueKey('tv-owner-delete'),
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 15),
              label: Text(context.tr('tv_market_delete'), style: _label),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF1744),
                foregroundColor: Colors.white,
                padding: _padding,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                elevation: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
