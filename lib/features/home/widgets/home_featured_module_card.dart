import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/home_module.dart';
import '../../../core/l10n/l10n_extension.dart';
import 'package:provider/provider.dart';
import '../controllers/home_label_animator.dart';
import 'festive_price_text.dart';
import 'home_module_card_background_image.dart';
import 'home_module_card_leaves.dart';
import 'home_module_fitted_box.dart';
import 'home_taxi_module_card.dart';
import 'wave_label_text.dart';

/// Yuqori 2 karta (Non, Ish top).
class HomeFeaturedModuleCard extends StatelessWidget {
  const HomeFeaturedModuleCard({
    super.key,
    required this.module,
    required this.height,
    required this.onTap,
  });

  final HomeModule module;
  final double height;
  final VoidCallback onTap;

  static const _labelStyle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w900,
    color: AppColors.primary,
    height: 1.05,
    letterSpacing: 0.15,
  );

  double get _breadPriceFontSize {
    final base = height > 160 ? 22.0 : 18.0;
    return base * 0.7 * 1.2;
  }

  /// Non rasmi ustidagi sarlavha zonasi (karta kengligi).
  static const double _breadTitleZoneWidthFraction = 0.52;

  static const double _breadImageScale = 0.85;

  @override
  Widget build(BuildContext context) {
    final isBread = module.id == 'bread';
    final plain =
        HomeLabelAnimator.plainTextFor(context, module.id, featured: true);
    context
        .read<HomeLabelAnimator>()
        .syncPlainCharCount(module.id, plain);
    final imageMaxH = (height * 0.78 * _breadImageScale).clamp(64.0, 93.0);
    final imageMinH = (height * 0.52 * _breadImageScale).clamp(52.0, 78.0);

    return SizedBox(
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Ink(
            decoration: AppTheme.homeModuleCardDecoration,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: isBread
                        ? HomeModuleCardBackgroundImage(
                            asset: module.image,
                            imageSide: HomeModuleCardImageSide.left,
                            anchorImageToBottom: false,
                            alignment: Alignment.centerLeft,
                            heightFactor: 0.88 * _breadImageScale,
                            minImageHeight: imageMinH,
                            maxImageHeight: imageMaxH,
                            imageSizeMultiplier: _breadImageScale,
                            left: -6,
                            errorIcon: Icons.bakery_dining,
                          )
                        : HomeModuleCardBackgroundImage(
                            asset: module.image,
                            imageSide: HomeModuleCardImageSide.left,
                            anchorImageToBottom: false,
                            wrapAlignment: Alignment.center,
                            contentWidthFraction: 0.50,
                            alignment: Alignment.center,
                            heightFactor: 0.78,
                            minImageHeight: (height * 0.48).clamp(52.0, 78.0),
                            maxImageHeight: (height * 0.72).clamp(68.0, 92.0),
                            imageSizeMultiplier: 0.76,
                            left: 0,
                            maxWidthFraction: 0.90,
                            maxHeightFraction: 0.88,
                            errorIcon: Icons.work_outline,
                          ),
                  ),
                ),
                ...HomeModuleCardLeaves.positioned(),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 4, 4),
                    child: isBread
                        ? _breadForeground(context, plain)
                        : _jobsForeground(context, plain),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _breadForeground(BuildContext context, String plain) {
    const serviceStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.primarySoft,
      height: 1.0,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final titleZoneW =
            constraints.maxWidth * _breadTitleZoneWidthFraction;

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: titleZoneW * 0.34,
              right: 8,
              top: 12,
              child: LayoutBuilder(
                builder: (context, textConstraints) {
                  return Align(
                    alignment: Alignment.topRight,
                    child: HomeModuleFittedBox(
                      maxWidth: textConstraints.maxWidth,
                      alignment: Alignment.topRight,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          WaveLabelText(
                            moduleId: 'bread',
                            plainText: plain,
                            maxLines: 2,
                            wrapAlignment: WrapAlignment.end,
                            baseStyle: _labelStyle,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context.tr('bread_service'),
                            textAlign: TextAlign.right,
                            style: serviceStyle,
                          ),
                          const SizedBox(height: 4),
                          FestivePriceText(
                            amountFontSize: _breadPriceFontSize,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _jobsForeground(BuildContext context, String plain) {
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned(
          top: 4,
          left: 0,
          right: 8,
          bottom: 4,
          child: LayoutBuilder(
            builder: (context, textConstraints) {
              return Align(
                alignment: Alignment.centerRight,
                child: HomeJobsThreeRowTitle(
                  moduleId: 'jobs',
                  alignment: Alignment.centerRight,
                  firstLineStyle: _labelStyle.copyWith(fontSize: 15),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
