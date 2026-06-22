import 'dart:async';

import 'package:flutter/material.dart';

/// Non / Taom / Bozor / taksi promo bannerlari — avtomatik aylantirish, nuqtasiz.
class PromoCarousel extends StatefulWidget {
  const PromoCarousel({
    super.key,
    required this.onNonTap,
    required this.onTaomTap,
    required this.onBozorTap,
    required this.onLocalTaxiTap,
    required this.onIntercityTap,
    required this.onMarshrutTap,
  });

  final VoidCallback onNonTap;
  final VoidCallback onTaomTap;
  final VoidCallback onBozorTap;
  final VoidCallback onLocalTaxiTap;
  final VoidCallback onIntercityTap;
  final VoidCallback onMarshrutTap;

  @override
  State<PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoBannerData {
  const _PromoBannerData({
    required this.title,
    required this.imagePath,
    required this.onTap,
  });

  final String title;
  final String imagePath;
  final VoidCallback onTap;
}

class _PromoCarouselState extends State<PromoCarousel> {
  static const _autoPlayInterval = Duration(seconds: 4);
  static const _resumeDelay = Duration(seconds: 8);
  static const _virtualPageCount = 100000;
  static const _initialVirtualPage = 50000;

  final PageController _controller =
      PageController(initialPage: _initialVirtualPage);
  Timer? _timer;
  bool _autoPaused = false;

  late final List<_PromoBannerData> _banners;

  @override
  void initState() {
    super.initState();
    _banners = [
      _PromoBannerData(
        title: 'Non buyurtma',
        imagePath: 'assets/images/banners/banner_bread.jpg',
        onTap: widget.onNonTap,
      ),
      _PromoBannerData(
        title: 'Taom buyurtma',
        imagePath: 'assets/images/banners/banner_food.jpg',
        onTap: widget.onTaomTap,
      ),
      _PromoBannerData(
        title: 'Online bozor',
        imagePath: 'assets/images/banners/banner_market.jpg',
        onTap: widget.onBozorTap,
      ),
      _PromoBannerData(
        title: 'Mahalliy taksi',
        imagePath: 'assets/images/banners/banner_local_taxi.jpg',
        onTap: widget.onLocalTaxiTap,
      ),
      _PromoBannerData(
        title: 'Marshrut taksi',
        imagePath: 'assets/images/banners/banner_marshrut.jpg',
        onTap: widget.onMarshrutTap,
      ),
      _PromoBannerData(
        title: 'Shaharlararo',
        imagePath: 'assets/images/banners/banner_intercity.jpg',
        onTap: widget.onIntercityTap,
      ),
    ];
    _startAutoPlay();
  }

  void _startAutoPlay() {
    _timer?.cancel();
    _timer = Timer.periodic(_autoPlayInterval, (_) {
      if (!mounted || _autoPaused || !_controller.hasClients) return;
      final page = _controller.page;
      if (page == null) return;
      _controller.animateToPage(
        page.round() + 1,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    });
  }

  void _pauseAutoPlay() {
    if (_autoPaused) return;
    _autoPaused = true;
    Future.delayed(_resumeDelay, () {
      if (mounted) _autoPaused = false;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            _pauseAutoPlay();
          }
          return false;
        },
        child: PageView.builder(
          controller: _controller,
          itemCount: _virtualPageCount,
          itemBuilder: (context, index) {
            final banner = _banners[index % _banners.length];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: _PromoBannerCard(data: banner),
            );
          },
        ),
      ),
    );
  }
}

class _PromoBannerCard extends StatelessWidget {
  const _PromoBannerCard({required this.data});

  final _PromoBannerData data;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            image: DecorationImage(
              image: AssetImage(data.imagePath),
              fit: BoxFit.cover,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black.withValues(alpha: 0.55),
                  Colors.black.withValues(alpha: 0.15),
                ],
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Stack(
            children: [
              Positioned(
                top: 2,
                left: 2,
                right: 14,
                child: Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: _CtaButton(onTap: data.onTap),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.22),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            'Buyurtma berish →',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
