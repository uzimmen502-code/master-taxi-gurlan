import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../core/utils/formatters.dart';
import '../data/oil_catalog.dart';
import '../data/oil_l10n.dart';
import '../data/oil_type_article.dart';

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

/// Мой тури «трассаси» метрикаси (HTML oilTypeBars билан бир хил).
class _BarSpec {
  const _BarSpec({
    required this.safeFrac,
    required this.greenStart,
    required this.yellowStart,
    required this.orangeStart,
    required this.marks,
    required this.carBody,
    required this.carWindow,
    required this.carBase,
    required this.legend,
  });

  final double safeFrac;
  final double greenStart;
  final double yellowStart;
  final double orangeStart;
  final List<(double, String)> marks;
  final Color carBody;
  final Color carWindow;
  final Color carBase;
  final List<(Color, L3)> legend;
}

// Йўл зона ранглари (CSS .bar-track.range gradient).
const _zoneGray = Color(0xFF6B736B);
const _zoneGreen = Color(0xFF3F8F44);
const _zoneYellow = Color(0xFFC9A412);
const _zoneOrange = Color(0xFFC45A12);
// Легенда ранглари.
const _legGreen = Color(0xFF66BB6A);
const _legYellow = Color(0xFFFDD835);
const _legOrange = Color(0xFFEF6C00);

const _barSpecs = <OilBarVariant, _BarSpec>{
  OilBarVariant.full: _BarSpec(
    safeFrac: 0.80,
    greenStart: 0.80,
    yellowStart: 0.88,
    orangeStart: 0.92,
    marks: [(0.80, '10k'), (0.88, '12k'), (0.92, '13k'), (1.0, '15k')],
    carBody: Color(0xFF1B7A28),
    carWindow: Color(0xFFC8E6C9),
    carBase: Color(0xFF0D5C18),
    legend: [
      (
        _legGreen,
        L3(
          'Ўзбекистон шароитида МЕТАН/ПРОПАНда · ~10 000 км · хавфсиз',
          'O‘zbekiston sharoitida METAN/PROPANda · ~10 000 km · xavfsiz',
          'В условиях Узбекистана на МЕТАНЕ/ПРОПАНЕ · ~10 000 км · безопасно',
        )
      ),
      (_legGreen, L3('10–12k яшил', '10–12k yashil', '10–12k зелёный')),
      (_legYellow, L3('12–13k сариқ', '12–13k sariq', '12–13k жёлтый')),
      (_legOrange, L3('13–15k огоҳлик', '13–15k ogohlik', '13–15k предупреждение')),
    ],
  ),
  OilBarVariant.semi: _BarSpec(
    safeFrac: 0.70,
    greenStart: 0.70,
    yellowStart: 0.80,
    orangeStart: 0.90,
    marks: [(0.70, '7k'), (0.80, '8k'), (0.90, '9k'), (1.0, '10k')],
    carBody: Color(0xFFEF6C00),
    carWindow: Color(0xFFFFE0B2),
    carBase: Color(0xFFE65100),
    legend: [
      (
        _legGreen,
        L3(
          'Ўзбекистон шароитида МЕТАН/ПРОПАНда · ~7 000 км · хавфсиз',
          'O‘zbekiston sharoitida METAN/PROPANda · ~7 000 km · xavfsiz',
          'В условиях Узбекистана на МЕТАНЕ/ПРОПАНЕ · ~7 000 км · безопасно',
        )
      ),
      (_legYellow, L3('8–9k сариқ', '8–9k sariq', '8–9k жёлтый')),
      (_legOrange, L3('9–10k огоҳлик', '9–10k ogohlik', '9–10k предупреждение')),
    ],
  ),
  OilBarVariant.mineral: _BarSpec(
    safeFrac: 0.60,
    greenStart: 0.45,
    yellowStart: 0.60,
    orangeStart: 0.80,
    marks: [(0.45, '4k'), (0.60, '5k'), (0.80, '6k'), (1.0, '7k')],
    carBody: Color(0xFF2E7D32),
    carWindow: Color(0xFFA5D6A7),
    carBase: Color(0xFF1B5E20),
    legend: [
      (
        _legGreen,
        L3(
          'Ўзбекистон шароитида МЕТАН/ПРОПАНда · ~5 000 км · хавфсиз',
          'O‘zbekiston sharoitida METAN/PROPANda · ~5 000 km · xavfsiz',
          'В условиях Узбекистана на МЕТАНЕ/ПРОПАНЕ · ~5 000 км · безопасно',
        )
      ),
      (_legYellow, L3('5–6k сариқ', '5–6k sariq', '5–6k жёлтый')),
      (_legOrange, L3('6–7k огоҳлик', '6–7k ogohlik', '6–7k предупреждение')),
    ],
  ),
};

/// Мой тури «трассаси»: зона ранглари + пунктир йўл + хавфсиз белги +
/// қотиб турган байроқ + ҳаракатланувчи машина + км-белгилар (+ легенда).
/// [phase] 0..1 — машина 8%→хавфсиз нуқтага боради, кейин туради.
class OilTypeBar extends StatelessWidget {
  const OilTypeBar({
    super.key,
    required this.phase,
    this.variant = OilBarVariant.mineral,
    this.showLegend = false,
  });

  final double phase;
  final OilBarVariant variant;
  final bool showLegend;

  static const _trackAreaH = 26.0;
  static const _flagW = 12.0;

  @override
  Widget build(BuildContext context) {
    final s = _barSpecs[variant]!;
    final lang = oilLangOf(context);
    final fp = oilBarFillProgress(phase);
    final w = math.max(0.08, s.safeFrac * fp);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final barW = c.maxWidth;
            return SizedBox(
              height: _trackAreaH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _OilRaceTrackPainter(spec: s, w: w),
                    ),
                  ),
                  Positioned(
                    left: (s.safeFrac * barW - _flagW)
                        .clamp(0.0, math.max(0.0, barW - _flagW)),
                    top: -2,
                    width: _flagW,
                    height: 16,
                    child: const _OilRacingFlag(),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 1),
        LayoutBuilder(
          builder: (context, c) {
            final barW = c.maxWidth;
            return SizedBox(
              height: 13,
              child: Stack(
                children: [
                  for (final m in s.marks)
                    Positioned(
                      left: (m.$1 * barW - 12).clamp(0.0, math.max(0.0, barW - 24)),
                      child: SizedBox(
                        width: 24,
                        child: Text(
                          m.$2,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: oilHubMuted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        if (showLegend) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 5,
            children: [for (final l in s.legend) _oilLegendItem(l.$1, l.$2.t(lang))],
          ),
        ],
      ],
    );
  }
}

Widget _oilLegendItem(Color c, String text) {
  return ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 280),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(right: 4, top: 1),
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: oilHubMuted,
              height: 1.2,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Трассани чизади: зона ранглари, пунктир, қоронғи «босиб ўтилган» қисм,
/// хавфсиз белги ва машина.
class _OilRaceTrackPainter extends CustomPainter {
  const _OilRaceTrackPainter({required this.spec, required this.w});

  final _BarSpec spec;
  final double w;

  static const _trackTop = 13.0;
  static const _trackH = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    final bw = size.width;
    final rr = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, _trackTop, bw, _trackH),
      const Radius.circular(2),
    );

    canvas.save();
    canvas.clipRRect(rr);

    void band(double a, double b, Color col) {
      canvas.drawRect(
        Rect.fromLTWH(bw * a, _trackTop, bw * (b - a), _trackH),
        Paint()..color = col,
      );
    }

    band(0, spec.greenStart, _zoneGray);
    band(spec.greenStart, spec.yellowStart, _zoneGreen);
    band(spec.yellowStart, spec.orangeStart, _zoneYellow);
    band(spec.orangeStart, 1, _zoneOrange);

    // Пунктир йўл чизиғи (ўртада).
    final cy = _trackTop + _trackH / 2;
    final dash = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 1;
    var x = 4.0;
    while (x < bw - 4) {
      canvas.drawLine(Offset(x, cy), Offset(math.min(x + 6, bw - 4), cy), dash);
      x += 12;
    }

    // Босиб ўтилган масофа (қоронғи қатлам).
    canvas.drawRect(
      Rect.fromLTWH(0, _trackTop, bw * w, _trackH),
      Paint()..color = const Color(0xFF141414).withValues(alpha: 0.46),
    );

    canvas.restore();

    // Хавфсиз белги (клипдан ташқарида — чегарадан чиқади).
    final sx = bw * spec.safeFrac;
    canvas.drawRect(
      Rect.fromLTWH(sx - 2, _trackTop - 3, 4, _trackH + 6),
      Paint()..color = const Color(0xFF1B7A28).withValues(alpha: 0.85),
    );
    canvas.drawRect(
      Rect.fromLTWH(sx - 1, _trackTop - 3, 2, _trackH + 6),
      Paint()..color = Colors.white,
    );

    _paintCar(canvas, bw * w, _trackTop + _trackH, spec);
  }

  void _paintCar(Canvas canvas, double cx, double baseY, _BarSpec s) {
    const cw = 30.0;
    const ch = 13.0;
    final left = cx - cw / 2;
    final top = baseY - ch;

    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, baseY + 0.5), width: cw * 0.82, height: 3),
      Paint()..color = Colors.black.withValues(alpha: 0.12),
    );

    final body = Paint()..color = s.carBody;
    // Кабина/том (трапеция).
    final roof = Path()
      ..moveTo(left + cw * 0.26, top + 4)
      ..lineTo(left + cw * 0.34, top)
      ..lineTo(left + cw * 0.64, top)
      ..lineTo(left + cw * 0.72, top + 4)
      ..close();
    canvas.drawPath(roof, body);
    // Ойна.
    final win = Path()
      ..moveTo(left + cw * 0.30, top + 3.5)
      ..lineTo(left + cw * 0.36, top + 1)
      ..lineTo(left + cw * 0.62, top + 1)
      ..lineTo(left + cw * 0.67, top + 3.5)
      ..close();
    canvas.drawPath(win, Paint()..color = s.carWindow);
    // Асосий кузов.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top + 4, cw, ch - 6),
        const Radius.circular(3),
      ),
      body,
    );
    // Пастки чизиқ.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top + ch - 4, cw, 3),
        const Radius.circular(2),
      ),
      Paint()..color = s.carBase,
    );
    // Фара.
    canvas.drawRect(
      Rect.fromLTWH(left + cw - 3, top + 5.5, 2.5, 2),
      Paint()..color = const Color(0xFFFFEB3B),
    );
    // Ғилдираклар.
    final wheel = Paint()..color = const Color(0xFF212121);
    final hub = Paint()..color = const Color(0xFF9E9E9E);
    final wy = baseY - 1;
    for (final dx in const [0.28, 0.72]) {
      canvas.drawCircle(Offset(left + cw * dx, wy), 3.1, wheel);
      canvas.drawCircle(Offset(left + cw * dx, wy), 1.3, hub);
    }
  }

  @override
  bool shouldRepaint(covariant _OilRaceTrackPainter old) =>
      old.w != w || old.spec != spec;
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

/// 20 с цикл: учта полоса параллел (бир вақтда), phase 0→1.
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

  /// Барча индекслар учун бир хил phase — синхрон старт.
  double _phaseOf(int index) => _c.value;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => widget.builder(context, _phaseOf),
    );
  }
}

/// Байроқ тўлдириш прогресси (OilTypeBar билан мос).
double oilBarFillProgress(double phase) {
  if (phase <= 0) return 0;
  if (phase >= 1) return 1;
  if (phase < 0.7) return phase / 0.7;
  return 1;
}

String oilAnimatedKmLabel(
  BuildContext context,
  OilTypeInfo t,
  double phase,
) {
  final fp = oilBarFillProgress(phase);
  final safeKm = t.targetKm;
  final km = fp >= 1 ? safeKm : (safeKm * fp).round();
  final prefix = fp >= 1 ? '~' : '';
  return '$prefix${formatPrice(km)} ${context.tr('oil_km_suffix')}';
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
  final article = oilTypeArticle(t.key);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scroll) => Column(
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD5E5D6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: EdgeInsets.fromLTRB(
                18,
                12,
                18,
                18 + MediaQuery.paddingOf(ctx).bottom,
              ),
              children: [
                if (article != null)
                  OilTypeArticleView(article: article)
                else ...[
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
                ],
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
          ),
        ],
      ),
    ),
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
