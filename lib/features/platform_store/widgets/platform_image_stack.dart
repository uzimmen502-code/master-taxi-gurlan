import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/data_url_image.dart';
import '../ava_store_colors.dart';

/// 1 та расм — тўлиқ (ҳозиргидек); 2–5 та — орқа чекка peek + ўнг/чап свайп.
class PlatformImageStack extends StatefulWidget {
  const PlatformImageStack({
    super.key,
    required this.urls,
    this.memCacheWidth = 600,
    this.showDots = true,
    this.padding = EdgeInsets.zero,
    this.borderRadius = 12,
    this.onDoubleTap,
  });

  final List<String> urls;
  final int memCacheWidth;
  final bool showDots;
  final EdgeInsets padding;
  final double borderRadius;

  /// Икки марта босилганда жорий расм индекси билан чақирилади.
  final ValueChanged<int>? onDoubleTap;

  @override
  State<PlatformImageStack> createState() => _PlatformImageStackState();
}

class _PlatformImageStackState extends State<PlatformImageStack> {
  PageController? _ctrl;
  int _index = 0;

  List<String> get _urls => widget.urls
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .take(5)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _ensureController();
  }

  @override
  void didUpdateWidget(covariant PlatformImageStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls.join('|') != widget.urls.join('|')) {
      _index = 0;
      _ctrl?.dispose();
      _ctrl = null;
      _ensureController();
    }
  }

  void _ensureController() {
    if (_urls.length <= 1) return;
    _ctrl ??= PageController();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = _urls;
    if (urls.isEmpty) {
      return Padding(
        padding: widget.padding,
        child: const _EmptyImage(),
      );
    }

    // Битта расм — ўзгармас.
    if (urls.length == 1) {
      return Padding(
        padding: widget.padding,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: widget.onDoubleTap == null
              ? null
              : () => widget.onDoubleTap!(0),
          child: _Frame(
            borderRadius: widget.borderRadius,
            child: _NetImage(
              url: urls.first,
              memCacheWidth: widget.memCacheWidth,
            ),
          ),
        ),
      );
    }

    final ctrl = _ctrl!;
    // Ўнг томонда орқа расм(лар) чеккаси учун жой.
    const peekReserve = 14.0;

    return Padding(
      padding: widget.padding,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Орқа дек: кейинги расм(лар)нинг чеккаси ўнгдан чиқиб туради.
          if (urls.length > 2)
            Positioned(
              top: 10,
              bottom: 8,
              left: peekReserve + 10,
              right: 0,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.45,
                  child: Transform.rotate(
                    angle: 0.045,
                    alignment: Alignment.bottomRight,
                    child: _Frame(
                      borderRadius: widget.borderRadius,
                      child: _NetImage(
                        url: urls[(_index + 2) % urls.length],
                        memCacheWidth: widget.memCacheWidth,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 5,
            bottom: 5,
            left: peekReserve + 4,
            right: 2,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.7,
                child: Transform.rotate(
                  angle: 0.025,
                  alignment: Alignment.bottomRight,
                  child: _Frame(
                    borderRadius: widget.borderRadius,
                    child: _NetImage(
                      url: urls[(_index + 1) % urls.length],
                      memCacheWidth: widget.memCacheWidth,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Олд расм — ўнгга/чапга свайп; икки марта босиш → тўлиқ экран.
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(right: peekReserve),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: widget.onDoubleTap == null
                    ? null
                    : () => widget.onDoubleTap!(_index),
                child: PageView.builder(
                  controller: ctrl,
                  itemCount: urls.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => _Frame(
                    borderRadius: widget.borderRadius,
                    elevated: true,
                    child: _NetImage(
                      url: urls[i],
                      memCacheWidth: widget.memCacheWidth,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.showDots)
            Positioned(
              left: 0,
              right: peekReserve,
              bottom: 5,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < urls.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: i == _index ? 12 : 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: i == _index
                            ? AvaStoreColors.deep
                            : Colors.white.withValues(alpha: 0.75),
                        border: Border.all(
                          color: AvaStoreColors.deep.withValues(alpha: 0.35),
                          width: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({
    required this.child,
    required this.borderRadius,
    this.elevated = false,
  });

  final Widget child;
  final double borderRadius;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AvaStoreColors.soft,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: elevated
              ? AvaStoreColors.brand.withValues(alpha: 0.7)
              : AvaStoreColors.border,
          width: elevated ? 1.2 : 0.9,
        ),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: AvaStoreColors.deep.withValues(alpha: 0.14),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : [
                BoxShadow(
                  color: AvaStoreColors.deep.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(1, 1),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius - 0.5),
        child: ColoredBox(
          color: AvaStoreColors.soft,
          child: child,
        ),
      ),
    );
  }
}

class _NetImage extends StatelessWidget {
  const _NetImage({required this.url, required this.memCacheWidth});

  final String url;
  final int memCacheWidth;

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
        width: double.infinity,
        height: double.infinity,
        memCacheWidth: memCacheWidth,
        placeholder: (_, __) => const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AvaStoreColors.deep,
            ),
          ),
        ),
        errorWidget: (_, __, ___) => const Icon(
          Icons.shopping_bag_outlined,
          size: 36,
          color: AvaStoreColors.muted,
        ),
      );
    }
    if (u.isNotEmpty && isDataImageUrl(u)) {
      final bytes = decodeDataUrlImageBytes(u);
      if (bytes != null) {
        return Image.memory(bytes, fit: BoxFit.contain);
      }
    }
    return const _EmptyImage();
  }
}

class _EmptyImage extends StatelessWidget {
  const _EmptyImage();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AvaStoreColors.soft,
      child: Center(
        child: Icon(
          Icons.shopping_bag_outlined,
          size: 36,
          color: AvaStoreColors.muted,
        ),
      ),
    );
  }
}
