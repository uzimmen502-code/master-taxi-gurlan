import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../models/tv_clip.dart';

/// Пуллик реклама клипи (`category == 'ad'`) томошабинга ҳар жойда очиқ
/// «Реклама» деб белгиланади (8-босқич, 2026-10-25): тўлиқ экран, бош саҳифа,
/// қидирув, канал. Реклама бўлмаган клипда ҳеч нарса чизмайди.
class TvAdLabel extends StatelessWidget {
  const TvAdLabel({super.key, required this.clip, this.compact = false});

  final TvClip clip;

  /// Кичик карточкалар учун (постер устида).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!clip.isAd) return const SizedBox.shrink();
    final text = context.tr('tv_ad_label');
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: DecoratedBox(
        key: const ValueKey('tv_ad_label'),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white70, width: 0.8),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 7, vertical: compact ? 1 : 2),
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: compact ? 1.2 : 1.3,
            ),
          ),
        ),
      ),
    );
  }
}
