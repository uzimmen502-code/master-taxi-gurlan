import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';

/// Постер дарҳол кўринади — видео келгунча бўш экран бўлмайди.
class TvClipPoster extends StatelessWidget {
  const TvClipPoster({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const ColoredBox(color: Colors.black);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final w = (MediaQuery.sizeOf(context).width * dpr).round().clamp(360, 720);
    return Image.network(
      url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      cacheWidth: w,
      errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black),
    );
  }
}

/// `clip.canStartPlayback == false` бўлганда постер устига қўйиладиган
/// белги — видео ҳали серверда transcode қилинмоқда, ХОМ файл ҳеч қачон
/// ўйнатилмайди (гуард [TvPlayerPool.prepare]да).
class TvClipProcessingBadge extends StatelessWidget {
  const TvClipProcessingBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.35),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
          ),
          const SizedBox(height: 10),
          Text(
            context.tr('tv_clip_processing'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
