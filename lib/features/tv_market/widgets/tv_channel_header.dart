import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../models/tv_clip.dart';

/// Оммaviy канал боши — ism, tuman, qisqa stat.
class TvChannelHeader extends StatelessWidget {
  const TvChannelHeader({
    super.key,
    required this.displayName,
    this.districtLabel = '',
    this.clipCount,
  });

  final String displayName;
  final String districtLabel;
  final int? clipCount;

  @override
  Widget build(BuildContext context) {
    final name = tvOwnerDisplayName(displayName);
    if (name.isEmpty) return const SizedBox.shrink();
    final initial = name.trim().isNotEmpty
        ? name.trim().substring(0, 1).toUpperCase()
        : '?';
    final district = districtLabel.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFF00E676).withValues(alpha: 0.18),
            child: Text(
              initial,
              style: const TextStyle(
                color: Color(0xFF007A3D),
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    height: 1.2,
                  ),
                ),
                if (district.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    district,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
                if (clipCount != null && clipCount! > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    context.tr('tv_channel_clip_count').replaceAll('{n}', '$clipCount'),
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
