import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/home_module.dart';
import '../controllers/home_label_animator.dart';
import 'home_module_card_background_image.dart';
import 'home_module_card_leaves.dart';
import 'home_module_fitted_box.dart';
import 'wave_label_text.dart';

/// Taksi moduli — chapda rasm (fon), o‘ngda matn + uchburchak.
class HomeTaxiModuleCard extends StatelessWidget {
  const HomeTaxiModuleCard({
    super.key,
    required this.module,
    required this.onTap,
    this.subtitle,
  });

  final HomeModule module;
  final VoidCallback onTap;
  final String? subtitle;

  /// Matn zonasi — karta kengligining chap qismi (rasmdan keyin).
  static const double _textZoneLeftFraction = 0.30;

  static const _titleStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w900,
    color: AppColors.primary,
    height: 1.05,
  );

  static const _subtitleStyle = TextStyle(
    fontSize: 12,
    height: 1.15,
    fontWeight: FontWeight.w500,
    color: AppColors.primarySoft,
  );

  static String? defaultSubtitle(BuildContext context, String id) {
    return switch (id) {
      'cheap_products_home' => context.tr('module_ads_subtitle'),
      'marshrut' => context.tr('module_marshrut_subtitle'),
      'local_taxi' => context.tr('module_local_subtitle'),
      'intercity' => context.tr('module_intercity_subtitle'),
      _ => null,
    };
  }

  static const _onlineTitleStyleFactor = 0.6;

  static TextStyle _onlinePrefixStyle(TextStyle titleStyle) => TextStyle(
        fontSize: titleStyle.fontSize! * _onlineTitleStyleFactor,
        fontWeight: FontWeight.w900,
        color: AppColors.error,
        height: titleStyle.height,
      );

  static String imageFor(String id) {
    return switch (id) {
      'cheap_products_home' => 'assets/images/online_bozor.png',
      'marshrut' => 'assets/images/taxi_marshrut.png',
      'local_taxi' => 'assets/images/taxi_local.png',
      'intercity' => 'assets/images/luggage.png',
      _ => 'assets/images/taxi_marshrut.png',
    };
  }

  static IconData errorIconFor(String id) {
    return switch (id) {
      'cheap_products_home' => Icons.campaign_outlined,
      'intercity' => Icons.luggage_outlined,
      _ => Icons.local_taxi,
    };
  }

  /// Taksi kartasi balandligi (~73 px, featured qator bilan ~15% qisqaroq).
  static const double _taxiCardHeightScale = 0.62;

  /// Barcha taksi modullari rasmi (marshrut, mahalliy, shaharlararo).
  static const double _taxiImageScale = 0.72;

  static ({
    double cardH,
    double minH,
    double maxH,
    double widthFrac,
    double multiplier,
    double imageLeft,
    double maxHeightFrac,
  }) _layoutFor(bool hasSub) {
    final cardH = (hasSub ? 118.0 : 106.0) * _taxiCardHeightScale;
    const s = _taxiImageScale;
    return (
      cardH: cardH,
      minH: cardH * 0.86 * s,
      maxH: cardH * 1.0 * s,
      widthFrac: 0.82 * s,
      multiplier: 1.16 * s,
      imageLeft: 14.0,
      maxHeightFrac: 0.98,
    );
  }

  @override
  Widget build(BuildContext context) {
    final plain =
        HomeLabelAnimator.plainTextFor(context, module.id, featured: false);
    context
        .read<HomeLabelAnimator>()
        .syncPlainCharCount(module.id, plain);
    final sub = subtitle ?? defaultSubtitle(context, module.id);
    final hasSub = sub != null && sub.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _layoutFor(hasSub);
        final textLeft = constraints.maxWidth * _textZoneLeftFraction;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(30),
            child: Ink(
              decoration: AppTheme.homeModuleCardDecoration,
              child: SizedBox(
                height: layout.cardH,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: HomeModuleCardBackgroundImage(
                          asset: imageFor(module.id),
                          imageSide: HomeModuleCardImageSide.left,
                          anchorImageToBottom: false,
                          alignment: const Alignment(0.22, 0),
                          heightFactor: 1.0,
                          minImageHeight: layout.minH,
                          maxImageHeight: layout.maxH,
                          imageSizeMultiplier: layout.multiplier,
                          maxWidthFraction: layout.widthFrac,
                          maxHeightFraction: layout.maxHeightFrac,
                          left: layout.imageLeft,
                          bottom: 0,
                          errorIcon: errorIconFor(module.id),
                        ),
                      ),
                    ),
                    ...HomeModuleCardLeaves.positioned(),
                    Positioned(
                      left: textLeft,
                      right: 8,
                      top: 6,
                      bottom: 6,
                      child: LayoutBuilder(
                        builder: (context, textConstraints) {
                          return Center(
                            child: HomeModuleFittedBox(
                              maxWidth: textConstraints.maxWidth,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  _buildTitle(context, plain),
                                  if (hasSub) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      sub,
                                      maxLines: 2,
                                      textAlign: TextAlign.center,
                                      style: _subtitleStyle,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTitle(BuildContext context, String plain) {
    if (module.id == 'jobs') {
      return const HomeJobsThreeRowTitle(moduleId: 'jobs');
    }
    if (plain.isNotEmpty && HomeLabelAnimator.order.contains(module.id)) {
      if (module.id == 'cheap_products_home') {
        final onlineLen =
            context.tr('home_module_cheap_products_online').characters.length;
        return WaveLabelText(
          moduleId: module.id,
          plainText: plain,
          maxLines: 1,
          wrapAlignment: WrapAlignment.center,
          baseStyle: _onlinePrefixStyle(_titleStyle),
          highlightFromIndex: onlineLen,
          highlightStyle: _titleStyle,
        );
      }
      return WaveLabelText(
        moduleId: module.id,
        plainText: plain,
        maxLines: 1,
        wrapAlignment: WrapAlignment.center,
        baseStyle: _titleStyle,
      );
    }
    return Text(
      plain.isNotEmpty ? plain : module.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: _titleStyle,
    );
  }
}

/// Иш топ — 3 qator: ИШ БОР, ХИЗМАТ, ТАКЛИФИ (to‘lqin animatsiyasi saqlanadi).
class HomeJobsThreeRowTitle extends StatelessWidget {
  const HomeJobsThreeRowTitle({
    super.key,
    required this.moduleId,
    this.alignment = Alignment.centerRight,
    this.firstLineStyle = const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w900,
      color: AppColors.primary,
      height: 1.05,
      letterSpacing: 0.15,
    ),
  });

  final String moduleId;
  final Alignment alignment;
  final TextStyle firstLineStyle;

  static const TextStyle _urgentLineStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w900,
    color: Colors.red,
    height: 1.05,
    letterSpacing: 0.15,
  );

  static ({String line1, String line2, String line3, String combined})
      _linesFor(BuildContext context) {
    final line1 = context.tr('home_featured_ish_bor');
    final line2 = context.tr('home_featured_xizmat');
    final taklifiFull = context.tr('home_featured_xizmat_taklifi');
    final parts = taklifiFull.split(RegExp(r'\s+'));
    final line3 =
        parts.length >= 2 ? parts.sublist(1).join(' ') : taklifiFull;
    return (
      line1: line1,
      line2: line2,
      line3: line3,
      combined: '$line1\n$line2\n$line3',
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = _linesFor(context);
    context
        .read<HomeLabelAnimator>()
        .syncPlainCharCount(moduleId, lines.combined);

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final animator = context.watch<HomeLabelAnimator>();
    final rowTexts = [lines.line1, lines.line2, lines.line3];
    final highlightFrom = lines.line1.length;

    if (reduceMotion) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < rowTexts.length; i++)
            _fittedTextRow(
              rowTexts[i],
              style: i == 0 ? firstLineStyle : _urgentLineStyle,
            ),
        ],
      );
    }

    final active = animator.isActive(moduleId);
    final wave = animator.waveIndex;
    var charGlobal = 0;

    final rows = <Widget>[];
    for (final line in rowTexts) {
      rows.add(
        _fittedAnimatedRow(
          line: line,
          alignment: alignment,
          active: active,
          wave: wave,
          highlightFrom: highlightFrom,
          charGlobalStart: charGlobal,
          firstLineStyle: firstLineStyle,
        ),
      );
      charGlobal += line.characters.length;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: rows,
    );
  }

  Widget _fittedTextRow(String text, {required TextStyle style}) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: Text(
        text,
        maxLines: 1,
        textAlign: TextAlign.right,
        style: style,
      ),
    );
  }

  Widget _fittedAnimatedRow({
    required String line,
    required Alignment alignment,
    required bool active,
    required int wave,
    required int highlightFrom,
    required int charGlobalStart,
    required TextStyle firstLineStyle,
  }) {
    var index = charGlobalStart;
    final children = <Widget>[];
    for (final ch in line.characters) {
      final style = index >= highlightFrom ? _urgentLineStyle : firstLineStyle;
      var opacity = 1.0;
      var weight = style.fontWeight ?? FontWeight.w900;
      if (active && index > wave) {
        opacity = 0.32;
        weight = FontWeight.w600;
      }
      children.add(
        Text(
          ch,
          style: style.copyWith(
            color: style.color?.withValues(alpha: opacity),
            fontWeight: weight,
          ),
        ),
      );
      index++;
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: Wrap(
        alignment: WrapAlignment.end,
        children: children,
      ),
    );
  }
}
