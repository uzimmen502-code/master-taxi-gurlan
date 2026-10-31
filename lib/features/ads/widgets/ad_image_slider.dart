import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'ad_image_gallery.dart';
import '../../../core/theme/ava_tokens.dart';

/// Full-width image pager (ҳисоблагич ва нуқтасиз, эга 2026-11-01).
class AdImageSlider extends StatefulWidget {
  const AdImageSlider({
    super.key,
    required this.imageUrls,
    this.height = 300,
    this.backgroundColor = AvaLight.surface2,
  });

  final List<String> imageUrls;
  final double height;

  /// containда расм атрофида қоладиган фон (қоронғи саҳифада — қоронғи ранг).
  final Color backgroundColor;

  @override
  State<AdImageSlider> createState() => _AdImageSliderState();
}

class _AdImageSliderState extends State<AdImageSlider> {
  final _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.imageUrls;
    if (urls.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const ColoredBox(
          color: AvaLight.surface2,
          child: Center(child: Icon(Icons.image_not_supported, size: 48)),
        ),
      );
    }

    return SizedBox(
      height: widget.height,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: urls.length,
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => openAdImageGallery(
                context,
                urls: urls,
                initialIndex: i,
              ),
              // contain: катта расм четлари қирқилмай сиғиб кичраяди
              // (ега 2026-10-19); бўш жойни ёруғ фон тўлдиради.
              child: ColoredBox(
                color: widget.backgroundColor,
                child: CachedNetworkImage(
                  imageUrl: urls[i],
                  fit: BoxFit.contain,
                  width: double.infinity,
                  placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
                ),
              ),
            ),
          ),
          // Расм ҳисоблагичи («1/9») ва нуқталар олиб ташланди (эга, 2026-11-01).
        ],
      ),
    );
  }
}
