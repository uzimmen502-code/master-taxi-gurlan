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
    this.icon,
    this.iconColor,
    this.iconScale = 1.0,
  });

  final String moduleId;
  final String label;
  final VoidCallback onTap;
  final String? imagePath;
  final String? emoji;
  final IconData? icon;
  final Color? iconColor;
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
  static const _aspectRatio = 0.92;
  static const _colGap = 10.0;
  /// 3D «оёқ» сояси учун қўшимча баландлик (катак ичидан емайди).
  static const _shadowFoot = 5.0;
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
        Row(
          children: [
            Text(
              context.tr('home_services_spotlight_title'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF102418),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 22,
              color: Color(0xFF102418),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) {
            final cellW = c.maxWidth * _viewportFraction;
            final rowH = (cellW - _colGap) / _aspectRatio + _shadowFoot;
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
  static const _radius = 14.0;
  static const _facePressed = Color(0xFFEEF6D8);

  bool _pressed = false;
  bool _busy = false;

  void _setPressed(bool v) {
    if (_pressed == v || !mounted) return;
    setState(() => _pressed = v);
  }

  Future<void> _handleTap() async {
    if (_busy) return;
    _busy = true;
    _setPressed(true);
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (!mounted) return;
    HomeModuleGate.gatedTap(context, widget.item.moduleId, widget.item.onTap)();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (mounted) _setPressed(false);
    _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final scale = (w / 390).clamp(0.9, 1.15);
    // 3D рамка/padding жой олиши учун иконка бироз кичикроқ —
    // матн аввалгидек катакка тўлиқ сиғсин.
    final iconSize = (38 * scale).clamp(34.0, 42.0);
    final labelSize = (10.0 * scale).clamp(9.0, 10.5);
    // PNG'ларда шаффоф чекка бор — scale билан оптик марказга тўлдирамиз.
    final glyphSize = iconSize * 0.9 * widget.item.iconScale;
    final imageZoom = (1.28 * widget.item.iconScale).clamp(1.0, 1.55);
    final item = widget.item;
    final pressed = _pressed;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _handleTap(),
      onTapCancel: () => _setPressed(false),
      child: Padding(
        // 3D «оёқ» сояси учун жой — қатор баландлигига қўшилган.
        padding: EdgeInsets.only(bottom: pressed ? 1 : _ServicesSpotlightCarouselState._shadowFoot),
        child: SizedBox.expand(
          child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, pressed ? 4.0 : 0.0, 0),
          transformAlignment: Alignment.center,
          child: AnimatedScale(
            scale: pressed ? 0.94 : 1.0,
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOut,
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_radius),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: pressed
                      ? const [
                          Color(0xFFDCE8B0),
                          _facePressed,
                          Color(0xFFC8D890),
                        ]
                      : const [
                          Color(0xFFFFFFFF),
                          Color(0xFFFAFCF0),
                          Color(0xFFE8F2C0),
                        ],
                ),
                border: Border(
                  top: BorderSide(
                    color: pressed
                        ? const Color(0xFFB71C1C)
                        : const Color(0xFFFF8A80),
                    width: 1.0,
                  ),
                  left: BorderSide(
                    color: pressed
                        ? const Color(0xFFB71C1C)
                        : const Color(0xFFFF6F60),
                    width: 1.0,
                  ),
                  right: BorderSide(
                    color: pressed
                        ? const Color(0xFF8B0000)
                        : const Color(0xFFC62828),
                    width: pressed ? 1.5 : 1.2,
                  ),
                  bottom: BorderSide(
                    color: pressed
                        ? const Color(0xFF6A0000)
                        : const Color(0xFFB71C1C),
                    width: pressed ? 1.5 : 2.0,
                  ),
                ),
                boxShadow: pressed
                    ? [
                        BoxShadow(
                          color:
                              const Color(0xFF4E9F00).withValues(alpha: 0.35),
                          blurRadius: 0,
                          offset: const Offset(0, 1),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.20),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: const Color(0xFF3D7A00),
                          blurRadius: 0,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 8,
                          offset: const Offset(0, 6),
                        ),
                      ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 2,
                    right: 2,
                    top: 1,
                    height: 8,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(10),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white
                                  .withValues(alpha: pressed ? 0.25 : 0.65),
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: iconSize,
                            height: iconSize,
                            child: ClipRect(
                              child: Center(
                                child: item.icon != null
                                    ? Icon(
                                        item.icon,
                                        color: item.iconColor ??
                                            const Color(0xFFE53935),
                                        size: glyphSize,
                                      )
                                    : item.emoji != null
                                        ? Text(
                                            item.emoji!,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: glyphSize,
                                              height: 1.0,
                                              leadingDistribution:
                                                  TextLeadingDistribution.even,
                                            ),
                                          )
                                        : item.imagePath != null
                                            ? Transform.scale(
                                                scale: imageZoom,
                                                child: Image.asset(
                                                  item.imagePath!,
                                                  width: iconSize,
                                                  height: iconSize,
                                                  fit: BoxFit.contain,
                                                  alignment: Alignment.center,
                                                  filterQuality:
                                                      FilterQuality.high,
                                                  errorBuilder: (_, __, ___) =>
                                                      Icon(
                                                    Icons.apps_rounded,
                                                    color:
                                                        AppColors.primaryDark,
                                                    size: glyphSize,
                                                  ),
                                                ),
                                              )
                                            : Icon(
                                                Icons.apps_rounded,
                                                color: AppColors.primaryDark,
                                                size: glyphSize,
                                              ),
                              ),
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
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF102418),
                              height: 1.05,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}
