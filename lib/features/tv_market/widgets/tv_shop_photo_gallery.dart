import 'package:flutter/material.dart';

/// Дўкон товар расмлари — варақлаш + тўлиқ экран.
class TvShopPhotoCarousel extends StatefulWidget {
  const TvShopPhotoCarousel({
    super.key,
    required this.urls,
    this.height = 220,
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

  void _openGallery(int i) {
    if (widget.urls.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvShopPhotoGalleryPage(
          urls: widget.urls,
          initialIndex: i,
        ),
      ),
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
    return SizedBox(
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
                child: Image.network(urls[i], fit: BoxFit.cover),
              );
            },
          ),
          if (widget.hasVideo && widget.onVideo != null)
            Align(
              alignment: Alignment.center,
              child: GestureDetector(
                onTap: widget.onVideo,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white70),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          if (urls.length > 1)
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
        ],
      ),
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

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1}/${widget.urls.length}'),
      ),
      body: PageView.builder(
        controller: _page,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          return InteractiveViewer(
            child: Center(
              child: Image.network(widget.urls[i], fit: BoxFit.contain),
            ),
          );
        },
      ),
    );
  }
}
