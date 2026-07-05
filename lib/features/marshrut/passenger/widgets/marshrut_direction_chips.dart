import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';
import '../models/marshrut_route_pair.dart';

/// Oxirgi / mashhur yo'nalish chip-lari (Phase B).
class MarshrutDirectionChips extends StatelessWidget {
  const MarshrutDirectionChips({
    super.key,
    required this.recentRoutes,
    required this.popularRoutes,
    required this.onRouteSelected,
    this.activeFrom,
    this.activeTo,
  });

  final List<MarshrutRoutePair> recentRoutes;
  final List<MarshrutRoutePair> popularRoutes;
  final ValueChanged<MarshrutRoutePair> onRouteSelected;
  final String? activeFrom;
  final String? activeTo;

  List<MarshrutRoutePair> _dedupePopular() {
    final seen = recentRoutes.map((r) => r.key).toSet();
    return popularRoutes.where((r) => !seen.contains(r.key)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final popular = _dedupePopular();
    if (recentRoutes.isEmpty && popular.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (recentRoutes.isNotEmpty) ...[
          _SectionLabel(text: context.tr('marshrut_recent_directions')),
          const SizedBox(height: 6),
          _ChipRow(
            routes: recentRoutes,
            activeFrom: activeFrom,
            activeTo: activeTo,
            onRouteSelected: onRouteSelected,
          ),
        ],
        if (popular.isNotEmpty) ...[
          if (recentRoutes.isNotEmpty) const SizedBox(height: 10),
          _SectionLabel(text: context.tr('marshrut_popular_directions')),
          const SizedBox(height: 6),
          _ChipRow(
            routes: popular,
            activeFrom: activeFrom,
            activeTo: activeTo,
            onRouteSelected: onRouteSelected,
          ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Colors.white.withValues(alpha: 0.85),
        letterSpacing: 0.2,
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.routes,
    required this.onRouteSelected,
    this.activeFrom,
    this.activeTo,
  });

  final List<MarshrutRoutePair> routes;
  final ValueChanged<MarshrutRoutePair> onRouteSelected;
  final String? activeFrom;
  final String? activeTo;

  String _shortLabel(MarshrutRoutePair route) {
    String short(String s) {
      final cleaned = s.replaceAll(' МФЙ', '').trim();
      return cleaned.length > 14 ? '${cleaned.substring(0, 13)}…' : cleaned;
    }

    return '${short(route.from)} → ${short(route.to)}';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
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
    );
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
