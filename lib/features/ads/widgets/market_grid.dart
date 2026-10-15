import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Бозор катакчаларининг ЯГОНА ўлчам қоидаси (Аҳоли бозори, Улгуржи бозор,
/// Хитой бозори).
///
/// Аввал катак баландлиги кенгликка пропорционал (`childAspectRatio`), матн
/// блоки эса dp да доимий эди — экран кенгайган сайин катак остида бўш жой
/// ўсарди (393 dp да 12–32 dp). Энди баландлик = расм (кенглик / 1.2) + матн
/// блокининг ҳақиқий баландлиги, шунинг учун бўш жой экран кенглигига
/// боғлиқ эмас.
class MarketGridMetrics {
  MarketGridMetrics._();

  /// Расм нисбати (кенглик / баландлик).
  static const double imageAspect = 1.2;

  /// Матн блокининг ички чети.
  static const double textPad = 8;

  /// Шрифт масштаби чегараси: катта тизим шрифтида ёзув кесилмасин, лекин
  /// катак ҳам чексиз ўсмасин.
  static const double textScaleCap = 1.15;

  static const double titleSize = 13;
  static const double priceSize = 13;
  static const double captionSize = 11;
  static const double lineHeight = 1.2;
  static const double lineGap = 2;

  /// Матн блокининг баландлиги: икки схеманинг каттаси —
  ///   • сарлавҳа (1 қатор) + нарх + изоҳ;
  ///   • сарлавҳа (2 қатор) + нарх.
  static double textBlockHeight(BuildContext context) {
    final s = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: textScaleCap);
    final title = s.scale(titleSize * lineHeight);
    final price = s.scale(priceSize * lineHeight);
    final caption = s.scale(captionSize * lineHeight);
    final threeLines = title + lineGap + price + lineGap + caption;
    final twoLineTitle = 2 * title + lineGap + price;
    final content = threeLines > twoLineTitle ? threeLines : twoLineTitle;
    // +2: шрифт қатор баландликларининг яхлитланиш захираси.
    return (content + 2 * textPad + 2).ceilToDouble();
  }

  /// Катакнинг тўлиқ баландлиги.
  static double cellExtent(BuildContext context, double cellWidth) =>
      (cellWidth / imageAspect + textBlockHeight(context)).ceilToDouble();
}

/// Катак ичидаги матн блоки: сарлавҳа, нарх, изоҳ. Баландлиги
/// [MarketGridMetrics.textBlockHeight] га тенг — `Spacer` йўқ.
class MarketCardText extends StatelessWidget {
  const MarketCardText({
    super.key,
    required this.title,
    this.titleLines = 1,
    this.price,
    this.caption,
    this.priceColor = AppColors.primaryText,
  });

  final String title;
  final int titleLines;
  final String? price;
  final String? caption;
  final Color priceColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MarketGridMetrics.textBlockHeight(context),
      child: Padding(
        padding: const EdgeInsets.all(MarketGridMetrics.textPad),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: MarketGridMetrics.textScaleCap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: titleLines,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: MarketGridMetrics.titleSize,
                  height: MarketGridMetrics.lineHeight,
                ),
              ),
              if (price != null && price!.isNotEmpty) ...[
                const SizedBox(height: MarketGridMetrics.lineGap),
                Text(
                  price!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: priceColor,
                    fontWeight: FontWeight.w700,
                    fontSize: MarketGridMetrics.priceSize,
                    height: MarketGridMetrics.lineHeight,
                  ),
                ),
              ],
              if (caption != null && caption!.isNotEmpty) ...[
                const SizedBox(height: MarketGridMetrics.lineGap),
                Text(
                  caption!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: MarketGridMetrics.captionSize,
                    height: MarketGridMetrics.lineHeight,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Икки устунли бозор тўри: катак баландлиги [MarketGridMetrics] дан.
class MarketProductGrid extends StatelessWidget {
  const MarketProductGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.padding = const EdgeInsets.all(12),
    this.spacing = 10,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsets padding;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final cellWidth = (box.maxWidth - padding.horizontal - spacing) / 2;
        return GridView.builder(
          padding: padding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            mainAxisExtent: MarketGridMetrics.cellExtent(context, cellWidth),
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}
