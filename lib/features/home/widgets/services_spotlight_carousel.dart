import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/app_theme.dart';
import '../home_module_gate.dart';

class ServiceSpotlightItem {
  const ServiceSpotlightItem({
    required this.moduleId,
    required this.label,
    required this.onTap,
    this.imagePath,
    this.emoji,
    this.iconScale = 1.0,
  });

  final String moduleId;
  final String label;
  final VoidCallback onTap;
  final String? imagePath;
  final String? emoji;
  final double iconScale;
}

/// Хизматлар карусели — грид ўрнига.
///
/// Бир қаторда 4 та квадрат; ҳар 2 с **1 катак** чапдан ўнгга snap.
/// Infinite loop; биринчи touch → авто тўхтайди; виджет recreate → яна бошланади.
class ServicesSpotlightCarousel extends StatefulWidget {
  const ServicesSpotlightCarousel({
    super.key,
    required this.items,
  });

  final List<ServiceSpotlightItem> items;

  @override
  State<ServicesSpotlightCarousel> createState() =>
      _ServicesSpotlightCarouselState();
}

class _ServicesSpotlightCarouselState extends State<ServicesSpotlightCarousel> {
  static const _autoPlayInterval = Duration(seconds: 2);
  static const _visibleCount = 4;
  static const _virtualPageCount = 100000;
  static const _initialVirtualPage = 50000;
  static const _aspectRatio = 0.88;
  static const _colGap = 10.0;
  static const _viewportFraction = 1.0 / _visibleCount;

  late final PageController _controller;
  Timer? _timer;
  bool _userStoppedAuto = false;
  List<ServiceSpotlightItem> _visible = const [];
  VoidCallback? _configListener;

  @override
  void initState() {
    super.initState();
    _controller = PageController(
      initialPage: _initialVirtualPage,
      viewportFraction: _viewportFraction,
    );
    _configListener = () {
      if (!mounted) return;
      setState(_refreshVisible);
    };
    ServiceConfigHolder.revision.addListener(_configListener!);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshVisible();
    if (!_userStoppedAuto && !_reduceMotion) {
      _startAutoPlay();
    }
  }

  @override
  void didUpdateWidget(covariant ServicesSpotlightCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshVisible();
  }

  bool get _reduceMotion {
    final mq = MediaQuery.maybeOf(context);
    return mq?.disableAnimations == true;
  }

  void _refreshVisible() {
    _visible = widget.items
        .where((e) => HomeModuleGate.showInGrid(e.moduleId))
        .toList(growable: false);
  }

  void _startAutoPlay() {
    _timer?.cancel();
    if (_userStoppedAuto || _reduceMotion || _visible.length < 2) return;
    _timer = Timer.periodic(_autoPlayInterval, (_) {
      if (!mounted || _userStoppedAuto || !_controller.hasClients) return;
      if (_visible.length < 2) return;
      final page = _controller.page;
      if (page == null) return;
      // -1 page = 1 катак ўнгга (янги иконка чапдан).
      _controller.animateToPage(
        page.round() - 1,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    });
  }

  void _stopAutoForever() {
    if (_userStoppedAuto) return;
    _userStoppedAuto = true;
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    if (_configListener != null) {
      ServiceConfigHolder.revision.removeListener(_configListener!);
    }
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_visible.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('home_services_spotlight_title'),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Color(0xFF102418),
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) {
            final cellW = c.maxWidth * _viewportFraction;
            final rowH = (cellW - _colGap) / _aspectRatio;
            return SizedBox(
              height: rowH,
              child: Listener(
                onPointerDown: (_) => _stopAutoForever(),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n is ScrollStartNotification &&
                        n.dragDetails != null) {
                      _stopAutoForever();
                    }
                    return false;
                  },
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _virtualPageCount,
                    padEnds: false,
                    itemBuilder: (context, index) {
                      final item = _visible[index % _visible.length];
                      return Padding(
                        padding: const EdgeInsets.only(right: _colGap),
                        child: _SpotlightTile(item: item),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SpotlightTile extends StatefulWidget {
  const _SpotlightTile({required this.item});

  final ServiceSpotlightItem item;

  @override
  State<_SpotlightTile> createState() => _SpotlightTileState();
}

class _SpotlightTileState extends State<_SpotlightTile> {
  static const _brandGreen = Color(0xFF36A63A);
  bool _pressed = false;

  Future<void> _handleTap() async {
    if (_pressed) return;
    setState(() => _pressed = true);
    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (!mounted) return;
    HomeModuleGate.gatedTap(context, widget.item.moduleId, widget.item.onTap)();
    if (mounted) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final scale = (w / 390).clamp(0.9, 1.15);
    final iconSize = (52 * scale).clamp(44.0, 56.0);
    final labelSize = (10.5 * scale).clamp(9.5, 10.5);
    final glyphSize = iconSize * 0.74 * widget.item.iconScale;
    final item = widget.item;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _handleTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: _brandGreen.withValues(alpha: 0.15),
        highlightColor: _brandGreen.withValues(alpha: 0.08),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFE53935),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: iconSize,
                height: iconSize,
                child: item.emoji != null
                    ? Center(
                        child: Text(
                          item.emoji!,
                          style: TextStyle(fontSize: glyphSize),
                        ),
                      )
                    : item.imagePath != null
                        ? Image.asset(
                            item.imagePath!,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.apps_rounded,
                              color: AppColors.primaryDark,
                              size: glyphSize,
                            ),
                          )
                        : Icon(
                            Icons.apps_rounded,
                            color: AppColors.primaryDark,
                            size: glyphSize,
                          ),
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: labelSize,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF102418),
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
