import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';

enum MarshrutResultsView { list, map }

/// Ro'yxat / xarita tablari (Phase C).
class MarshrutResultsViewToggle extends StatelessWidget {
  const MarshrutResultsViewToggle({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final MarshrutResultsView selected;
  final ValueChanged<MarshrutResultsView> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<MarshrutResultsView>(
      segments: [
        ButtonSegment(
          value: MarshrutResultsView.list,
          icon: const Icon(Icons.view_list, size: 18),
          label: Text(context.tr('marshrut_tab_list')),
        ),
        ButtonSegment(
          value: MarshrutResultsView.map,
          icon: const Icon(Icons.map_outlined, size: 18),
          label: Text(context.tr('marshrut_tab_map')),
        ),
      ],
      selected: {selected},
      onSelectionChanged: (s) => onChanged(s.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return Colors.grey.shade700;
        }),
      ),
    );
  }
}
