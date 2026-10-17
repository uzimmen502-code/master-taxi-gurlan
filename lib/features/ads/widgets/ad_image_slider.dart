import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'ad_image_gallery.dart';
import '../../../core/theme/ava_tokens.dart';

/// Full-width image pager with dot indicators.
class AdImageSlider extends StatefulWidget {
  const AdImageSlider({
    super.key,
    required this.imageUrls,
    this.height = 300,
  });

  final List<String> imageUrls;
  final double height;

  @override
  State<AdImageSlider> createState() => _AdImageSliderState();
}

class _AdImageSliderState extends State<AdImageSlider> {
  final _pageController = PageController();
  int _index = 0;

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
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => openAdImageGallery(
                context,
                urls: urls,
                initialIndex: i,
              ),
              child: CachedNetworkImage(
                imageUrl: urls[i],
                fit: BoxFit.cover,
                width: double.infinity,
                placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
              ),
            ),
          ),
          // «2/5» — нуқталар кичик расмларда адаштиради; максимал 7 та расмда
          // нечанчисида эканини рақам аниқ айтади. Пастда-ўнгда: тепада
          // (SliverAppBar'нинг шикоят тугмаси остида) тугмалар билан тўқнашади.
          if (urls.length > 1)
            Positioned(
              right: 10,
              bottom: 8,
              child: IgnorePointer(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_index + 1}/${urls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          if (urls.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(urls.length, (i) {
                  final active = i == _index;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 8 : 6,
                    height: active ? 8 : 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.5),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}
