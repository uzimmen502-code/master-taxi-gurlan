import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/data_url_image.dart';
import '../ava_store_colors.dart';

/// Тўлиқ экран галерея: ўнг/чап свайп, pinch/pan зум, ✕ ёки пастга свайп билан ёпиш.
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

  /// Зумланган бўлса PageView свайпи ўчирилади.
  bool _zoomed = false;

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
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _ctrl,
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
                  key: ValueKey('gal_${widget.urls[i]}_$i'),
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
                child: IgnorePointer(
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
          child: Center(child: _GalleryImage(url: widget.url)),
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
