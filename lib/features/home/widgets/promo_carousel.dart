import 'dart:async';

import 'package:flutter/material.dart';

/// Non / Taom / Bozor promo bannerlari — avtomatik aylantirish, nuqtasiz.
class PromoCarousel extends StatefulWidget {
  const PromoCarousel({
    super.key,
    required this.onNonTap,
    required this.onTaomTap,
    required this.onBozorTap,
  });

  final VoidCallback onNonTap;
  final VoidCallback onTaomTap;
  final VoidCallback onBozorTap;

  @override
  State<PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoBannerData {
  const _PromoBannerData({
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onTap;
}

class _PromoCarouselState extends State<PromoCarousel> {
  static const _autoPlayInterval = Duration(seconds: 4);
  static const _resumeDelay = Duration(seconds: 8);

  final PageController _controller = PageController();
  Timer? _timer;
  bool _autoPaused = false;
  int _current = 0;

  late final List<_PromoBannerData> _banners;

  @override
  void initState() {
    super.initState();
    _banners = [
      _PromoBannerData(
        title: 'Non buyurtma',
        subtitle: 'Yangi non — eshigingizga',
        colors: const [Color(0xFF5D4037), Color(0xFF8D6E63)],
        onTap: widget.onNonTap,
      ),
      _PromoBannerData(
        title: 'Taom buyurtma',
        subtitle: 'Issiq taomlar — tez yetkazib berish',
        colors: const [Color(0xFFE65100), Color(0xFFFF9800)],
        onTap: widget.onTaomTap,
      ),
      _PromoBannerData(
        title: 'Online bozor',
        subtitle: 'Arzon mahsulotlar — uyingizga',
        colors: const [Color(0xFF1565C0), Color(0xFF42A5F5)],
        onTap: widget.onBozorTap,
      ),
    ];
    _startAutoPlay();
  }

  void _startAutoPlay() {
    _timer?.cancel();
    _timer = Timer.periodic(_autoPlayInterval, (_) {
      if (!mounted || _autoPaused) return;
      final next = (_current + 1) % _banners.length;
      _controller.animateToPage(
        next,
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
          itemCount: _banners.length,
          onPageChanged: (index) => setState(() => _current = index),
          itemBuilder: (context, index) {
            final banner = _banners[index];
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
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: data.colors,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      data.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _CtaButton(onTap: data.onTap),
            ],
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
