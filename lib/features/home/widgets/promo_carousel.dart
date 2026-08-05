import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../home_module_gate.dart';

/// Non / Taom / Bozor / taksi promo bannerlari — avtomatik aylantirish, nuqtasiz.
class PromoCarousel extends StatefulWidget {
  const PromoCarousel({
    super.key,
    required this.onNonTap,
    required this.onCarpetWashTap,
    required this.onMilkTap,
    required this.onTaomTap,
    required this.onBozorTap,
    required this.onLocalTaxiTap,
    required this.onIntercityTap,
    required this.onMarshrutTap,
  });

  final VoidCallback onNonTap;
  final VoidCallback onCarpetWashTap;
  final VoidCallback onMilkTap;
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
    required this.moduleId,
    required this.title,
    required this.imagePath,
    required this.onTap,
    this.darkText = false,
  });

  /// Baseline/admin holatiga qarab banner ko'rsatilishi uchun (Ёпиқ → yashirin).
  final String moduleId;
  final String title;
  final String imagePath;
  final VoidCallback onTap;

  /// Yorug' (oq fonli) rasmlar uchun matn qora bo'lsin.
  final bool darkText;
}

class _PromoCarouselState extends State<PromoCarousel> {
  static const _bannerHeight = 94.5; // 90 + 5%
  static const _autoPlayInterval = Duration(seconds: 4);
  static const _resumeDelay = Duration(seconds: 8);
  static const _virtualPageCount = 100000;
  static const _initialVirtualPage = 50000;

  final PageController _controller =
      PageController(initialPage: _initialVirtualPage);
  Timer? _timer;
  bool _autoPaused = false;

  @override
  void initState() {
    super.initState();
    _startAutoPlay();
  }

  List<_PromoBannerData> _banners(BuildContext context) => [
      _PromoBannerData(
        moduleId: 'bread',
        title: context.tr('home_module_bread'),
        imagePath: 'assets/images/banners/banner_bread.jpg',
        onTap: widget.onNonTap,
      ),
      _PromoBannerData(
        moduleId: 'carpet_wash',
        title: context.tr('home_module_carpet'),
        imagePath: 'assets/images/banners/banner_carpet_wash.jpg',
        onTap: widget.onCarpetWashTap,
      ),
      _PromoBannerData(
        moduleId: 'milk',
        title: context.tr('milk_short_label'),
        imagePath: 'assets/images/banners/banner_milk.jpg',
        onTap: widget.onMilkTap,
      ),
      _PromoBannerData(
        moduleId: 'food',
        title: context.tr('home_module_food'),
        imagePath: 'assets/images/banners/banner_food.jpg',
        onTap: widget.onTaomTap,
      ),
      _PromoBannerData(
        moduleId: 'cheap_products_home',
        title: context.tr('home_module_cheap_products'),
        imagePath: 'assets/images/banners/banner_market.jpg',
        onTap: widget.onBozorTap,
      ),
      _PromoBannerData(
        moduleId: 'local_taxi',
        title: context.tr('home_module_local'),
        imagePath: 'assets/images/banners/banner_local_taxi.jpg',
        onTap: widget.onLocalTaxiTap,
      ),
      _PromoBannerData(
        moduleId: 'marshrut',
        title: context.tr('home_module_marshrut'),
        imagePath: 'assets/images/banners/banner_marshrut.jpg',
        onTap: widget.onMarshrutTap,
        darkText: true,
      ),
      _PromoBannerData(
        moduleId: 'intercity',
        title: context.tr('home_module_intercity'),
        imagePath: 'assets/images/banners/banner_intercity.jpg',
        onTap: widget.onIntercityTap,
      ),
    ];

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
    // Baseline Ёпиқ qilgan modul banneri iloviada ko'rinmasin (faqat tap
    // bloklashning o'zi yetarli emas — banner "buyurtma bering" deb chaqiradi).
    final banners = _banners(context)
        .where((b) => HomeModuleGate.showInGrid(b.moduleId))
        .toList(growable: false);
    if (banners.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: _bannerHeight,
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
            final banner = banners[index % banners.length];
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

/// Banner rasmlariga kontrast + to'yinganlik (saturation) + ozgina yorug'lik
/// qo'shadi — rasmlar yorqinroq va "pop" bo'lib ko'rinadi.
final ColorFilter _vividFilter = _buildVividFilter();

const _tightStrut = StrutStyle(height: 1, forceStrutHeight: true);

ColorFilter _buildVividFilter() {
  const s = 1.22; // to'yinganlik (saturation)
  const c = 1.16; // kontrast
  const br = 18.0; // yorug'lik (0–255 shkalada)
  const lumR = 0.2126, lumG = 0.7152, lumB = 0.0722;
  const sr = (1 - s) * lumR;
  const sg = (1 - s) * lumG;
  const sb = (1 - s) * lumB;
  const k = 128 * (1 - c) + br;
  return const ColorFilter.matrix(<double>[
    c * (sr + s), c * sg, c * sb, 0, k, //
    c * sr, c * (sg + s), c * sb, 0, k, //
    c * sr, c * sg, c * (sb + s), 0, k, //
    0, 0, 0, 1, 0, //
  ]);
}

class _PromoBannerCard extends StatelessWidget {
  const _PromoBannerCard({required this.data});

  final _PromoBannerData data;

  /// Binaфша scrim — oq matn bilan yuqori kontrast (har xil fon rasmlarida).
  static const _purpleDeep = Color(0xFF4A148C);
  static const _purpleOnLight = Color(0xFF311B92);

  @override
  Widget build(BuildContext context) {
    final onDarkScrim = data.darkText;
    final titleColor = onDarkScrim ? _purpleOnLight : Colors.white;
    final titleScrim = onDarkScrim
        ? Colors.white.withValues(alpha: 0.92)
        : _purpleDeep.withValues(alpha: 0.88);
    final ctaColor = titleColor;
    final ctaScrim = onDarkScrim
        ? Colors.white.withValues(alpha: 0.88)
        : _purpleDeep.withValues(alpha: 0.92);

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
              alignment: Alignment.center,
              colorFilter: _vividFilter,
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 6,
                left: 8,
                right: 80,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _ScrimText(
                    text: data.title,
                    color: titleColor,
                    scrim: titleScrim,
                    fontSize: 14,
                  ),
                ),
              ),
              Positioned(
                bottom: 6,
                right: 8,
                child: _CtaButton(
                  onTap: data.onTap,
                  textColor: ctaColor,
                  backgroundColor: ctaScrim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scrim fon balandligi matn qator balandligi bilan teng (vertikal padding yo'q).
class _ScrimText extends StatelessWidget {
  const _ScrimText({
    required this.text,
    required this.color,
    required this.scrim,
    required this.fontSize,
  });

  final String text;
  final Color color;
  final Color scrim;
  final double fontSize;

  static const _strut = _tightStrut;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scrim,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          strutStyle: _strut,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            height: 1,
            color: color,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({
    required this.onTap,
    required this.textColor,
    required this.backgroundColor,
  });

  final VoidCallback onTap;
  final Color textColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              context.tr('home_promo_order_cta'),
              strutStyle: _tightStrut,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1,
                color: textColor,
                letterSpacing: 0.15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
