import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/data_url_image.dart';
import '../ava_store_colors.dart';

/// Тўлиқ экран галерея: ўнг/чап свайп, бир марта босилса ёпилади.
Future<void> openPlatformImageGallery(
  BuildContext context, {
  required List<String> urls,
  int initialIndex = 0,
}) async {
  final cleaned = urls
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .take(5)
      .toList(growable: false);
  if (cleaned.isEmpty) return;

  final start = initialIndex.clamp(0, cleaned.length - 1);
  HapticFeedback.lightImpact();
  await Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => _PlatformImageGalleryPage(
        urls: cleaned,
        initialIndex: start,
      ),
      transitionsBuilder: (_, anim, __, child) {
        return FadeTransition(opacity: anim, child: child);
      },
    ),
  );
}

class _PlatformImageGalleryPage extends StatefulWidget {
  const _PlatformImageGalleryPage({
    required this.urls,
    required this.initialIndex,
  });

  final List<String> urls;
  final int initialIndex;

  @override
  State<_PlatformImageGalleryPage> createState() =>
      _PlatformImageGalleryPageState();
}

class _PlatformImageGalleryPageState extends State<_PlatformImageGalleryPage> {
  late final PageController _ctrl;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _ctrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _close() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.urls.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _close,
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Бир марта босиш → ёпиш (свайп ўнг/чап — кейинги расм).
              PageView.builder(
                controller: _ctrl,
                itemCount: widget.urls.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) {
                  return Center(
                    child: _GalleryImage(url: widget.urls[i]),
                  );
                },
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  onPressed: _close,
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                ),
              ),
              if (multi)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 16,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < widget.urls.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: i == _index ? 14 : 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color: i == _index
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.45),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GalleryImage extends StatelessWidget {
  const _GalleryImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final u = url.trim();
    if (u.startsWith('assets/')) {
      return Image.asset(u, fit: BoxFit.contain);
    }
    if (u.isNotEmpty && isHttpImageUrl(u)) {
      return CachedNetworkImage(
        imageUrl: u,
        fit: BoxFit.contain,
        memCacheWidth: 1600,
        placeholder: (_, __) => const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white70,
            ),
          ),
        ),
        errorWidget: (_, __, ___) => const Icon(
          Icons.broken_image_outlined,
          size: 48,
          color: Colors.white54,
        ),
      );
    }
    if (u.isNotEmpty && isDataImageUrl(u)) {
      final bytes = decodeDataUrlImageBytes(u);
      if (bytes != null) {
        return Image.memory(bytes, fit: BoxFit.contain);
      }
    }
    return const Icon(
      Icons.shopping_bag_outlined,
      size: 48,
      color: AvaStoreColors.muted,
    );
  }
}
