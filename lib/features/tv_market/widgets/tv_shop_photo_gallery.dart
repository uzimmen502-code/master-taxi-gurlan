import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/data_url_image.dart';

/// Тўлиқ экран: pinch/double-tap зум, свайп, миниатюра танлаш.
Future<void> openTvShopPhotoGallery(
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
      pageBuilder: (_, __, ___) => TvShopPhotoGalleryPage(
        urls: cleaned,
        initialIndex: start,
      ),
      transitionsBuilder: (_, anim, __, child) {
        return FadeTransition(opacity: anim, child: child);
      },
    ),
  );
}

/// Дўкон товар расмлари — варақлаш, танлаш, зумга кириш.
class TvShopPhotoCarousel extends StatefulWidget {
  const TvShopPhotoCarousel({
    super.key,
    required this.urls,
    this.height = 280,
    this.onVideo,
    this.hasVideo = false,
  });

  final List<String> urls;
  final double height;
  final VoidCallback? onVideo;
  final bool hasVideo;

  @override
  State<TvShopPhotoCarousel> createState() => _TvShopPhotoCarouselState();
}

class _TvShopPhotoCarouselState extends State<TvShopPhotoCarousel> {
  final _page = PageController();
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _openGallery(int i) async {
    await openTvShopPhotoGallery(
      context,
      urls: widget.urls,
      initialIndex: i,
    );
  }

  void _select(int i) {
    if (i == _index) {
      _openGallery(i);
      return;
    }
    _page.animateToPage(
      i,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    if (urls.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: ColoredBox(
          color: Colors.grey.shade200,
          child: const Center(child: Icon(Icons.image_outlined, size: 40)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: widget.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _page,
                itemCount: urls.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  return GestureDetector(
                    onTap: () => _openGallery(i),
                    child: TvShopNetworkImage(
                      url: urls[i],
                      fit: BoxFit.cover,
                    ),
                  );
                },
              ),
              Positioned(
                left: 10,
                bottom: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.zoom_in_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        context.tr('tv_shop_zoom_hint'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (urls.length > 1)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_index + 1}/${urls.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              if (widget.hasVideo && widget.onVideo != null)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Material(
                    color: const Color(0xFF00E676),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      onTap: widget.onVideo,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.play_arrow_rounded,
                              size: 18,
                              color: Colors.black,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              context.tr('tv_shop_watch_clip'),
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (urls.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: SizedBox(
              height: 58,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: urls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final selected = i == _index;
                  return GestureDetector(
                    onTap: () => _select(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF00E676)
                              : Colors.grey.shade300,
                          width: selected ? 2.2 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: TvShopNetworkImage(
                        url: urls[i],
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class TvShopPhotoGalleryPage extends StatefulWidget {
  const TvShopPhotoGalleryPage({
    super.key,
    required this.urls,
    this.initialIndex = 0,
  });

  final List<String> urls;
  final int initialIndex;

  @override
  State<TvShopPhotoGalleryPage> createState() => _TvShopPhotoGalleryPageState();
}

class _TvShopPhotoGalleryPageState extends State<TvShopPhotoGalleryPage> {
  late final PageController _page;
  late int _index;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _index = widget.urls.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.urls.length - 1);
    _page = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _close() {
    if (mounted) Navigator.of(context).pop();
  }

  void _jumpTo(int i) {
    if (i == _index) return;
    _page.animateToPage(
      i,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }
    final multi = widget.urls.length > 1;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _page,
              physics: _zoomed
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() {
                _index = i;
                _zoomed = false;
              }),
              itemBuilder: (_, i) {
                return _GalleryZoomPane(
                  key: ValueKey('tv_gal_${widget.urls[i]}_$i'),
                  url: widget.urls[i],
                  onZoomedChanged: (z) {
                    if (_zoomed == z) return;
                    setState(() => _zoomed = z);
                  },
                  onDismiss: _zoomed ? null : _close,
                );
              },
            ),
            Positioned(
              top: 4,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  IconButton(
                    onPressed: _close,
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                  ),
                  const Spacer(),
                  Text(
                    '${_index + 1}/${widget.urls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (multi)
                    SizedBox(
                      height: 56,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: widget.urls.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final selected = i == _index;
                          return GestureDetector(
                            onTap: () => _jumpTo(i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selected
                                      ? const Color(0xFF00E676)
                                      : Colors.white24,
                                  width: selected ? 2.2 : 1,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: TvShopNetworkImage(
                                url: widget.urls[i],
                                fit: BoxFit.cover,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  if (multi) const SizedBox(height: 10),
                  Text(
                    context.tr('tv_shop_zoom_guide'),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryZoomPane extends StatefulWidget {
  const _GalleryZoomPane({
    super.key,
    required this.url,
    required this.onZoomedChanged,
    this.onDismiss,
  });

  final String url;
  final ValueChanged<bool> onZoomedChanged;
  final VoidCallback? onDismiss;

  @override
  State<_GalleryZoomPane> createState() => _GalleryZoomPaneState();
}

class _GalleryZoomPaneState extends State<_GalleryZoomPane>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _animCtrl;
  Animation<Matrix4>? _anim;
  TapDownDetails? _doubleTapDetails;

  static const _min = 1.0;
  static const _max = 4.0;
  static const _doubleTapScale = 2.5;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        final a = _anim;
        if (a != null) _transform.value = a.value;
      });
    _transform.addListener(_onTransform);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  void _onTransform() {
    final s = _transform.value.getMaxScaleOnAxis();
    widget.onZoomedChanged(s > 1.02);
  }

  void _animateTo(Matrix4 end) {
    _anim = Matrix4Tween(begin: _transform.value, end: end).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic),
    );
    _animCtrl.forward(from: 0);
  }

  void _onDoubleTap() {
    final s = _transform.value.getMaxScaleOnAxis();
    if (s > 1.05) {
      _animateTo(Matrix4.identity());
      return;
    }
    final details = _doubleTapDetails;
    final m = Matrix4.identity();
    if (details == null) {
      m.scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1);
      _animateTo(m);
      return;
    }
    final pos = details.localPosition;
    final x = -pos.dx * (_doubleTapScale - 1);
    final y = -pos.dy * (_doubleTapScale - 1);
    m
      ..translateByDouble(x, y, 0, 1)
      ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1);
    _animateTo(m);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onDismiss,
      onDoubleTapDown: (d) => _doubleTapDetails = d,
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: _min,
        maxScale: _max,
        clipBehavior: Clip.none,
        panEnabled: true,
        scaleEnabled: true,
        child: SizedBox.expand(
          child: Center(
            child: TvShopNetworkImage(
              url: widget.url,
              fit: BoxFit.contain,
              memCacheWidth: 1600,
              expand: false,
            ),
          ),
        ),
      ),
    );
  }
}

class TvShopNetworkImage extends StatelessWidget {
  const TvShopNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.memCacheWidth = 900,
    this.expand = true,
  });

  final String url;
  final BoxFit fit;
  final int memCacheWidth;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final u = url.trim();
    if (u.startsWith('assets/')) {
      return Image.asset(u, fit: fit);
    }
    if (u.isNotEmpty && isHttpImageUrl(u)) {
      return CachedNetworkImage(
        imageUrl: u,
        fit: fit,
        width: expand ? double.infinity : null,
        height: expand ? double.infinity : null,
        memCacheWidth: memCacheWidth,
        placeholder: (_, __) => ColoredBox(
          color: Colors.grey.shade200,
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          ),
        ),
        errorWidget: (_, __, ___) => ColoredBox(
          color: Colors.grey.shade200,
          child: const Icon(Icons.broken_image_outlined, size: 40),
        ),
      );
    }
    if (u.isNotEmpty && isDataImageUrl(u)) {
      final bytes = decodeDataUrlImageBytes(u);
      if (bytes != null) {
        return Image.memory(bytes, fit: fit);
      }
    }
    return ColoredBox(
      color: Colors.grey.shade200,
      child: const Icon(Icons.image_outlined, size: 40),
    );
  }
}
