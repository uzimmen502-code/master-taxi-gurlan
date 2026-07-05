import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';
import '../models/marshrut_route_pair.dart';

/// Oxirgi + mashhur yo'nalishlar — bitta gorizontal qator (Phase R).
class MarshrutDirectionChips extends StatelessWidget {
  const MarshrutDirectionChips({
    super.key,
    required this.recentRoutes,
    required this.popularRoutes,
    required this.onRouteSelected,
    this.activeFrom,
    this.activeTo,
    this.maxRecent = 3,
  });

  final List<MarshrutRoutePair> recentRoutes;
  final List<MarshrutRoutePair> popularRoutes;
  final ValueChanged<MarshrutRoutePair> onRouteSelected;
  final String? activeFrom;
  final String? activeTo;
  final int maxRecent;

  List<MarshrutRoutePair> _mergedRoutes() {
    final seen = <String>{};
    final merged = <MarshrutRoutePair>[];
    for (final route in recentRoutes.take(maxRecent)) {
      if (seen.add(route.key)) merged.add(route);
    }
    for (final route in popularRoutes) {
      if (seen.add(route.key)) merged.add(route);
    }
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    final routes = _mergedRoutes();
    if (routes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('marshrut_quick_directions'),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.85),
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final route in routes) ...[
                _DirectionChip(
                  label: _shortLabel(route),
                  selected: route.from == activeFrom && route.to == activeTo,
                  onTap: () => onRouteSelected(route),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _shortLabel(MarshrutRoutePair route) {
    String short(String s) {
      final cleaned = s.replaceAll(' МФЙ', '').trim();
      return cleaned.length > 14 ? '${cleaned.substring(0, 13)}…' : cleaned;
    }

    return '${short(route.from)} → ${short(route.to)}';
  }
}

class _DirectionChip extends StatelessWidget {
  const _DirectionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.primary : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
