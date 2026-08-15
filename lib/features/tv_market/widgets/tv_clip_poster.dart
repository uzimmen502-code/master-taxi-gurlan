import 'package:flutter/material.dart';

/// Постер дарҳол кўринади — видео келгунча бўш экран бўлмайди.
class TvClipPoster extends StatelessWidget {
  const TvClipPoster({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const ColoredBox(color: Colors.black);
    return Image.network(
      url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black),
    );
  }
}
