import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../core/utils/formatters.dart';
import '../data/oil_catalog.dart';

const oilHubBg = Color(0xFFF5F8F3);
const oilHubInk = Color(0xFF1A2E1C);
const oilHubMuted = Color(0xFF6B7C6E);
const oilHubViolet = Color(0xFF6A3DE8);

enum OilBarVariant { mineral, semi, full }

OilBarVariant oilBarVariantFor(String key) => switch (key) {
      'semi' => OilBarVariant.semi,
      'full' => OilBarVariant.full,
      _ => OilBarVariant.mineral,
    };

/// Бир полоса: [phase] 0 = бўш, 0..1 = фаол тўлдириш, 1 = тўлдирилган.
/// Тўлдириш учида оқ–қизил байроқча (тескарига хилпирайди).
class OilTypeBar extends StatelessWidget {
  const OilTypeBar({
    super.key,
    required this.widthFraction,
    required this.phase,
    this.variant = OilBarVariant.mineral,
  });

  final double widthFraction;
  final double phase;
  final OilBarVariant variant;

  static const _barH = 12.0;
  static const _flagW = 20.0;
  static const _flagH = 16.0;

  List<Color> get _colors => switch (variant) {
        OilBarVariant.mineral => const [
            Color(0xFF7BC67E),
            Color(0xFF36A63A),
            Color(0xFF7BC67E),
          ],
        OilBarVariant.semi => const [
            Color(0xFF69C06D),
            Color(0xFF2F9E45),
            Color(0xFF69C06D),
          ],
        OilBarVariant.full => const [
            Color(0xFF4CAF50),
            Color(0xFF1B7A28),
            Color(0xFF4CAF50),
          ],
      };

  @override
  Widget build(BuildContext context) {
    final target = widthFraction.clamp(0.12, 1.0);
    double w;
    var shine = 0.0;
    if (phase <= 0) {
      w = 0.12;
    } else if (phase >= 1) {
      w = target;
    } else {
      // 0–0.7 fill, 0.7–0.85 hold, 0.85–1 soft settle
      if (phase < 0.7) {
        w = 0.12 + (target - 0.12) * (phase / 0.7);
      } else if (phase < 0.85) {
        w = target;
      } else {
        w = target;
      }
      shine = (phase * 2) % 1.0;
    }

    final moving = phase > 0 && phase < 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final barW = constraints.maxWidth;
        final tipX = barW * w;
        // Байроқча тики ўңда — мато чапга (тескари) хилпирайди.
        final flagLeft =
            (tipX - _flagW + 2).clamp(0.0, math.max(0.0, barW - _flagW)).toDouble();

        return SizedBox(
          height: _barH + 12,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _barH,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6EEE5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: w,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(
                            colors: _colors,
                            stops: moving
                                ? [
                                    (shine - 0.35).clamp(0.0, 1.0),
                                    shine.clamp(0.0, 1.0),
                                    (shine + 0.35).clamp(0.0, 1.0),
                                  ]
                                : const [0.0, 0.5, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: flagLeft,
                bottom: _barH - 3,
                width: _flagW,
                height: _flagH + 8,
                child: const _OilRacingFlag(),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Оқ–қизил байроқча: тик ўңда, мато чапга хилпирайди.
class _OilRacingFlag extends StatefulWidget {
  const _OilRacingFlag();

  @override
  State<_OilRacingFlag> createState() => _OilRacingFlagState();
}

class _OilRacingFlagState extends State<_OilRacingFlag>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _wave,
      builder: (context, _) {
        // Тескари: чапга эгилиш (тўлдириш йўналишига қарши).
        final t = Curves.easeInOut.transform(_wave.value);
        final tilt = -0.08 - t * 0.28; // ~-5° … -20°
        final bob = (0.5 - t) * 1.2;
        return Transform.translate(
          offset: Offset(0, bob),
          child: Transform.rotate(
            angle: tilt,
            alignment: Alignment.bottomRight,
            child: CustomPaint(
              painter: _OilStartStopFlagPainter(wave: t),
              size: Size.infinite,
            ),
          ),
        );
      },
    );
  }
}

/// Оқ–қизил шахмат; мато тикдан чапга (тескари).
class _OilStartStopFlagPainter extends CustomPainter {
  const _OilStartStopFlagPainter({this.wave = 0});

  final double wave;

  @override
  void paint(Canvas canvas, Size size) {
    final poleX = size.width - 2.5;
    final pole = Paint()
      ..color = const Color(0xFF37474F)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(poleX, size.height),
      Offset(poleX, 1),
      pole,
    );

    const cols = 4;
    const rows = 3;
    final flagW = size.width - 5;
    final flagH = size.height * 0.55;
    final flagTop = 1.0;
    final flagRight = poleX - 0.5;
    final flagLeft = flagRight - flagW;
    final cellW = flagW / cols;
    final cellH = flagH / rows;

    // Енгил «шамол» — юқори қаторни чапга силкитиш.
    final sway = wave * 1.8;

    for (var r = 0; r < rows; r++) {
      final rowSway = sway * (1 - r / rows);
      for (var c = 0; c < cols; c++) {
        final red = (r + c).isEven;
        final paint = Paint()
          ..color = red ? const Color(0xFFE53935) : Colors.white;
        // Чапга: c=0 энг чап (байроқ учи).
        final x = flagLeft + c * cellW - rowSway * (cols - c) / cols;
        canvas.drawRect(
          Rect.fromLTWH(
            x,
            flagTop + r * cellH,
            cellW + 0.35,
            cellH + 0.35,
          ),
          paint,
        );
      }
    }
    final border = Paint()
      ..color = const Color(0xFFB71C1C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    canvas.drawRect(
      Rect.fromLTWH(flagLeft - sway, flagTop, flagW, flagH),
      border,
    );
  }

  @override
  bool shouldRepaint(covariant _OilStartStopFlagPainter oldDelegate) =>
      oldDelegate.wave != wave;
}

/// 20 с цикл: минерал → ярим → тўлиқ, кетма-кет.
class OilSequentialBarsTicker extends StatefulWidget {
  const OilSequentialBarsTicker({super.key, required this.builder});

  final Widget Function(
    BuildContext context,
    double Function(int index) phaseOf,
  ) builder;

  @override
  State<OilSequentialBarsTicker> createState() =>
      _OilSequentialBarsTickerState();
}

class _OilSequentialBarsTickerState extends State<OilSequentialBarsTicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _phaseOf(int index) {
    const n = 3;
    final segment = 1.0 / n;
    final start = index * segment;
    final end = start + segment;
    final t = _c.value;
    if (t < start) return 0;
    if (t >= end) return 1;
    return (t - start) / segment;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => widget.builder(context, _phaseOf),
    );
  }
}

void showOilProductSheet(BuildContext context, OilProduct p) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      final specs = p.localizedSpecs(ctx);
      return Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          16,
          18,
          18 + MediaQuery.paddingOf(ctx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p.displayName(ctx),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: oilHubInk,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF6EB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${ctx.tr('oil_why_picked')}\n',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    TextSpan(text: p.displayReason(ctx)),
                  ],
                ),
                style: const TextStyle(height: 1.35, color: oilHubInk),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: specs.entries
                  .map(
                    (e) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F5F2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${e.key}: ',
                              style: const TextStyle(color: oilHubMuted),
                            ),
                            TextSpan(
                              text: e.value,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 14),
            Text(
              ctx.tr('oil_price_from').replaceAll(
                    '{price}',
                    formatPrice(p.price),
                  ),
              style: const TextStyle(
                color: oilHubViolet,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                shadows: [Shadow(color: Colors.white, blurRadius: 6)],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              ctx.tr('oil_price_admin_note'),
              style: const TextStyle(fontSize: 12, color: oilHubMuted),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(ctx.tr('close')),
            ),
          ],
        ),
      );
    },
  );
}

void showOilTypeDetail(BuildContext context, OilTypeInfo t) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          16,
          18,
          18 + MediaQuery.paddingOf(ctx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.detailTitle(ctx),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: oilHubInk,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              t.detail(ctx),
              style: const TextStyle(height: 1.4, color: oilHubInk),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(ctx.tr('close')),
            ),
          ],
        ),
      );
    },
  );
}

class OilProductCard extends StatelessWidget {
  const OilProductCard({super.key, required this.product, this.onTap});

  final OilProduct product;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap ?? () => showOilProductSheet(context, product),
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 132,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: product.isOil
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFEEF2F7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFD5E5D6)),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (product.imageUrl.trim().isNotEmpty &&
                        isHttpImageUrl(product.imageUrl))
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: CachedNetworkImage(
                          imageUrl: product.imageUrl.trim(),
                          fit: BoxFit.cover,
                          fadeInDuration: const Duration(milliseconds: 200),
                          placeholder: (_, __) => Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Center(
                            child: Icon(
                              product.isOil
                                  ? Icons.opacity
                                  : Icons.filter_alt_outlined,
                              size: 40,
                              color: AppColors.primary.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      )
                    else
                      Center(
                        child: Icon(
                          product.isOil
                              ? Icons.opacity
                              : Icons.filter_alt_outlined,
                          size: 40,
                          color: AppColors.primary.withValues(alpha: 0.7),
                        ),
                      ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Text(
                        context
                            .tr('oil_price_from_multiline')
                            .replaceAll('{price}', formatPrice(product.price)),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: oilHubViolet,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          height: 1.15,
                          shadows: [
                            Shadow(color: Colors.white, blurRadius: 8),
                            Shadow(color: Colors.white, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              product.displayName(context),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: oilHubInk,
              ),
            ),
            Text(
              product.displayMeta(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: oilHubMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class OilRankCard extends StatelessWidget {
  const OilRankCard({
    super.key,
    required this.product,
    required this.rank,
  });

  final OilProduct product;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final labels = [
      (context.tr('oil_rank_1'), const Color(0xFF1B7A28), true),
      (context.tr('oil_rank_2'), const Color(0xFF2F9E45), false),
      (context.tr('oil_rank_3'), const Color(0xFF69C06D), false),
    ];
    final L = labels[rank.clamp(1, 3) - 1];
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => showOilProductSheet(context, product),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: L.$3 ? AppColors.primary : const Color(0xFFD5E5D6),
              width: L.$3 ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: L.$2.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  L.$1,
                  style: TextStyle(
                    color: L.$2,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                product.displayName(context),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: oilHubInk,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                product.displayMeta(context),
                style: const TextStyle(color: oilHubMuted, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                context.tr('oil_price_from').replaceAll(
                      '{price}',
                      formatPrice(product.price),
                    ),
                style: const TextStyle(
                  color: oilHubViolet,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('oil_rank_tap_hint'),
                style: const TextStyle(fontSize: 11.5, color: oilHubMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
