import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../domain/business_category.dart';

/// Харита тепасидаги тур чиплари: «Ҳаммаси» + БАРЧА 14 та фаолият тури (мавжуд-мавжуд эмаслигидан қатъи назар),
/// ҳар бири ўз рангида (эга, 2026-10-23). Танланган чип — шу ранг билан тўлдирилади; харитадаги маркер ҳам шу ранг.
class BusinessCategoryChips extends StatelessWidget {
  const BusinessCategoryChips({super.key, required this.selected, required this.onChanged});

  final BusinessCategory? selected;
  final ValueChanged<BusinessCategory?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _Chip(
            key: const ValueKey('biz_chip_all'),
            label: context.tr('bizmap_all'),
            icon: Icons.apps_rounded,
            color: const Color(0xFF334155),
            selected: selected == null,
            onTap: () => onChanged(null),
          ),
          for (final c in BusinessCategory.values)
            _Chip(
              key: ValueKey('biz_chip_${c.wire}'),
              label: context.tr(c.labelKey),
              icon: c.icon,
              color: c.color,
              selected: selected == c,
              onTap: () => onChanged(c),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : color;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected ? color : Colors.white,
        elevation: 2,
        shape: StadiumBorder(side: BorderSide(color: color, width: 1.4)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? Colors.white : Colors.black87),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
