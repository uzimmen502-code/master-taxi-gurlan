import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

enum HomeModuleCardImageSide { left, right }

/// Modul kartasi — katta rasm fon qatlamida (matn ustida).
class HomeModuleCardBackgroundImage extends StatelessWidget {
  const HomeModuleCardBackgroundImage({
    super.key,
    required this.asset,
    required this.heightFactor,
    this.imageSide = HomeModuleCardImageSide.right,
    this.alignment = Alignment.bottomRight,
    this.errorIcon = Icons.image_outlined,
    this.minImageHeight = 72,
    this.maxImageHeight = 200,
    this.left,
    this.right = -4,
    this.bottom = -6,
    this.imageSizeMultiplier = 1.0,
    this.maxWidthFraction,
    this.maxHeightFraction = 0.90,
    this.anchorImageToBottom = true,
    this.wrapAlignment,
    this.contentWidthFraction,
  });

  final String asset;
  final double heightFactor;
  final HomeModuleCardImageSide imageSide;
  final Alignment alignment;
  final IconData errorIcon;
  final double minImageHeight;
  final double maxImageHeight;
  final double? left;
  final double? right;
  final double bottom;
  final double imageSizeMultiplier;
  /// Karta kengligining qismi (masalan 0.72). `null` — standart.
  final double? maxWidthFraction;
  /// Karta balandligining maksimal ulushi (masalan 0.98).
  final double maxHeightFraction;
  final bool anchorImageToBottom;
  /// `anchorImageToBottom: false` bo'lganda rasm qadoqlash alignment'i.
  final Alignment? wrapAlignment;
  /// Rasm zonasi kengligi (karta ulushi). `null` — to'liq balandlik zonasi.
  final double? contentWidthFraction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final maxH = c.maxHeight.isFinite && c.maxHeight > 0
            ? c.maxHeight
            : 120.0;
        var imageH = (maxH * heightFactor)
                .clamp(minImageHeight, maxImageHeight) *
            imageSizeMultiplier;
        imageH = imageH.clamp(0.0, maxH * maxHeightFraction);
        final imageOnLeft = imageSide == HomeModuleCardImageSide.left;
        final widthFrac = maxWidthFraction ?? (imageOnLeft ? 0.58 : 0.52);
        final maxImageW = c.maxWidth * widthFrac;

        final image = IgnorePointer(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: imageH,
              maxWidth: maxImageW,
            ),
            child: Image.asset(
              asset,
              fit: BoxFit.contain,
              alignment: alignment,
              errorBuilder: (_, __, ___) => Icon(
                errorIcon,
                size: imageH * 0.45,
                color: AppColors.primary.withValues(alpha: 0.22),
              ),
            ),
          ),
        );

        final imageWidget = anchorImageToBottom
            ? Positioned(
                left: imageOnLeft ? (left ?? -8) : null,
                right: imageOnLeft ? null : (right ?? -4),
                bottom: bottom,
                child: image,
              )
            : Positioned(
                left: imageOnLeft ? (left ?? -10) : null,
                right: imageOnLeft ? null : (right ?? -4),
                top: 0,
                bottom: 0,
                width: contentWidthFraction != null
                    ? c.maxWidth * contentWidthFraction!
                    : null,
                child: Align(
                  alignment: wrapAlignment ??
                      (imageOnLeft
                          ? Alignment.centerLeft
                          : Alignment.centerRight),
                  child: image,
                ),
              );

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: imageOnLeft ? null : 0,
              right: imageOnLeft ? 0 : null,
              top: 0,
              bottom: 0,
              width: c.maxWidth * 0.62,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: imageOnLeft
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    end: imageOnLeft
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    colors: [
                      AppColors.cardGradientStart.withValues(alpha: 0.97),
                      AppColors.cardGradientStart.withValues(alpha: 0.55),
                      AppColors.cardGradientStart.withValues(alpha: 0),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
            imageWidget,
          ],
        );
      },
    );
  }
}
