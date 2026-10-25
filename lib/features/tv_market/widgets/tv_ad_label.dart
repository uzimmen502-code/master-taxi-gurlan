import 'package:flutter/material.dart';

import '../../../core/widgets/ava_ad_badge.dart';
import '../models/tv_clip.dart';

/// Пуллик реклама клипи (`category == 'ad'`) томошабинга ҳар жойда очиқ
/// «Реклама» деб белгиланади (8-босқич, 2026-10-25): тўлиқ экран, бош саҳифа,
/// қидирув, канал. Реклама бўлмаган клипда ҳеч нарса чизмайди.
///
/// Кўриниш умумий [AvaAdBadge]да (кўчмас мулк ҳам ишлатади); бу ерда фақат
/// шарт ва AVAGram'нинг эски калити (`tv_ad_label`).
class TvAdLabel extends StatelessWidget {
  const TvAdLabel({super.key, required this.clip, this.compact = false});

  final TvClip clip;

  /// Кичик карточкалар учун (постер устида).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!clip.isAd) return const SizedBox.shrink();
    return AvaAdBadge(compact: compact, boxKey: const ValueKey('tv_ad_label'));
  }
}
