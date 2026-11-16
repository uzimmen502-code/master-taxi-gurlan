import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../markets/data/market_taxonomy_repository.dart';
import '../../markets/domain/market_taxonomy.dart';
import '../home_module_gate.dart';
import 'ava_section.dart';

/// Бош саҳифадаги «Бозорлар» блоки (STAGE 12, эга 2026-11-16).
///
/// Хизматлар қаторидан кейин — бозор карточкалари вертикал рўйхатда, эга
/// белгилаган ТАРТИБДА. Ҳар карточка ўз модул дарвозаси билан
/// ([HomeModuleGate.showInGrid]); биронтаси кўринмаса — блок умуман йўқ.
/// Босилганда очиш мантиғи чақирувчида (`home_screen.dart`, мавжуд
/// helper'лар: `openMarket`, `_openGated`, `_openWholesale`, `_openModule`).
class HomeMarketEntry {
  const HomeMarketEntry({
    required this.id,
    required this.moduleId,
    required this.titleKey,
    required this.imagePath,
    this.taxonomyMarketId,
    this.sloganKey,
  });

  /// Блок ичидаги ID (тест/калит учун): `livestock` … `aralash`.
  final String id;

  /// Админ дарвозаси (`kKnownModuleIds`).
  final String moduleId;
  final String titleKey;
  final String imagePath;

  /// Таксономиядаги бозор (`taxonomy/markets`) — шиор шу ердан.
  final String? taxonomyMarketId;

  /// Таксономияда бўлмаган бозорлар шиори — lang калити.
  final String? sloganKey;
}

/// Эга тартиби: Мол, Мошина, Гўшт, Деҳқон, Уй-жой, Улгуржи, Хитой, Аралаш.
const kHomeMarketEntries = <HomeMarketEntry>[
  HomeMarketEntry(
    id: 'livestock',
    moduleId: 'livestock_market',
    titleKey: 'home_module_livestock_market',
    imagePath: 'assets/images/markets/market_livestock_v2.webp',
    taxonomyMarketId: 'livestock',
    sloganKey: 'home_market_livestock_slogan',
  ),
  HomeMarketEntry(
    id: 'auto',
    moduleId: 'auto_market',
    titleKey: 'home_module_auto_market',
    imagePath: 'assets/images/markets/market_auto_v2.webp',
    taxonomyMarketId: 'auto',
    sloganKey: 'home_market_auto_slogan',
  ),
  HomeMarketEntry(
    id: 'meat',
    moduleId: 'meat_market',
    titleKey: 'home_module_meat_market',
    imagePath: 'assets/images/markets/market_meat_v2.webp',
    taxonomyMarketId: 'meat',
    sloganKey: 'home_market_meat_slogan',
  ),
  HomeMarketEntry(
    id: 'farm',
    moduleId: 'farm_market',
    titleKey: 'home_module_farm_market',
    imagePath: 'assets/images/markets/market_farm_v2.webp',
    taxonomyMarketId: 'farm',
    sloganKey: 'home_market_farm_slogan',
  ),
  HomeMarketEntry(
    id: 'realty',
    moduleId: 'realty',
    titleKey: 'home_module_realty',
    imagePath: 'assets/images/markets/market_realty_v2.webp',
    sloganKey: 'home_market_realty_slogan',
  ),
  HomeMarketEntry(
    id: 'wholesale',
    moduleId: 'wholesale_market',
    titleKey: 'home_module_wholesale',
    imagePath: 'assets/images/markets/market_wholesale_v2.webp',
    sloganKey: 'home_market_wholesale_slogan',
  ),
  HomeMarketEntry(
    id: 'china',
    moduleId: 'china_market',
    titleKey: 'home_module_china',
    imagePath: 'assets/images/markets/market_china_v2.webp',
    sloganKey: 'home_market_china_slogan',
  ),
  HomeMarketEntry(
    id: 'aralash',
    moduleId: 'cheap_products_home',
    titleKey: 'home_market_aralash_title',
    imagePath: 'assets/images/markets/market_aralash_v2.webp',
    sloganKey: 'home_market_aralash_slogan',
  ),
];

/// Иловада бозор маҳсулотига буюртма бериш ёқилганми (Гўшт шиори танлови).
///
/// ALMASHTIRISH NUQTASI: ҳозир клиентда бизнес-буюртма учун дарвоза/флаг
/// ЙЎҚ — шунинг учун `false` ва Гўштда `sloganNoOrder` кўрсатилади. Буюртма
/// ёқилганда шу ерни сервер флагига улаш керак (таксономиядаги `slogan`
/// «етказиб беришдан фойдаланинг» матнига ўтади).
const bool kMarketInAppOrderingEnabled = false;

/// Таксономия шиори: буюртма ёқилмаган бўлса ва `sloganNoOrder` бор бўлса — у,
/// акс ҳолда `slogan`. Таксономия йўқ/бузилган бўлса — бўш сатр (карточка сарлавҳа билан қолади).
String taxonomyMarketSlogan(
  MarketDef? def,
  String lang, {
  bool inAppOrdering = kMarketInAppOrderingEnabled,
}) {
  if (def == null) return '';
  if (!inAppOrdering && def.sloganNoOrder.isNotEmpty) {
    return localizedName(def.sloganNoOrder, lang);
  }
  return localizedName(def.slogan, lang);
}

/// Дарвоза бўйича кўринадиган карточкалар — [kHomeMarketEntries] тартибида.
List<HomeMarketEntry> visibleHomeMarkets(bool Function(String moduleId) isVisible) => [
      for (final e in kHomeMarketEntries)
        if (isVisible(e.moduleId)) e,
    ];

class HomeMarketsBlock extends StatefulWidget {
  const HomeMarketsBlock({
    super.key,
    required this.onOpen,
    this.isVisible,
    this.loadTaxonomy,
  });

  final void Function(HomeMarketEntry entry) onOpen;

  /// Тест учун; сукут — [HomeModuleGate.showInGrid].
  final bool Function(String moduleId)? isVisible;

  /// Тест учун; сукут — [MarketTaxonomyRepository.load] (сеансда бир марта ўқилади).
  final Future<MarketTaxonomy> Function()? loadTaxonomy;

  @override
  State<HomeMarketsBlock> createState() => _HomeMarketsBlockState();
}

class _HomeMarketsBlockState extends State<HomeMarketsBlock> {
  MarketTaxonomy? _taxonomy;

  @override
  void initState() {
    super.initState();
    _taxonomy = widget.loadTaxonomy == null ? MarketTaxonomyRepository.cached : null;
    if (_taxonomy == null) _load();
  }

  Future<void> _load() async {
    try {
      final t = await (widget.loadTaxonomy ?? MarketTaxonomyRepository.load)();
      if (mounted) setState(() => _taxonomy = t);
    } catch (e) {
      // Шиорсиз ҳам карточка ишлайди (сарлавҳа + расм); хато фақат логда (25-банд).
      debugPrint('[HomeMarketsBlock] MARKET_TAXONOMY_LOAD_FAILED: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = visibleHomeMarkets(widget.isVisible ?? HomeModuleGate.showInGrid);
    if (items.isEmpty) return const SizedBox.shrink();
    final lang = context.contentLang;
    return Padding(
      padding: const EdgeInsets.only(top: AvaSpace.sectionMin),
      child: AvaSection(
        key: const ValueKey('home_markets_block'),
        title: context.tr('home_markets_block_title'),
        status: AvaSectionStatus.ready,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: AvaSpace.gap),
              _MarketCard(
                entry: items[i],
                // Эга 2026-11-16: 8 та картанинг ҳаммасида қисқа шиор тил калитидан (таксономия шиори — фақат калит йўқ бўлса).
                slogan: items[i].sloganKey != null
                    ? context.tr(items[i].sloganKey!)
                    : taxonomyMarketSlogan(_taxonomy?.market(items[i].taxonomyMarketId!), lang),
                onTap: () => widget.onOpen(items[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Карта ўлчамлари (эга, 2026-11-16).
const double kHomeMarketCardHeight = 64;
const double kHomeMarketSloganMinFont = 9;
const double kHomeMarketSloganMaxFont = 22;
const double kHomeMarketSloganLineHeight = 1.1;

/// Сарлавҳа: 15 px w700, ҳарф оралиғи 0.2, устун ўртасида (эга, 2026-11-16).
const double kHomeMarketTitleFont = 15;
const double kHomeMarketTitleLetterSpacing = 0.2;

/// Шиор ↔ карта пастки чети (эга, 2026-11-16: 2 px).
const double kHomeMarketSloganBottomGap = 2;

/// Стрелка: катта қалин шеврон (CustomPaint), ўнг четдан 2 px; матн устуни стрелкагача 1 px.
const double kHomeMarketArrowWidth = 16;
const double kHomeMarketArrowHeight = 30;
const double kHomeMarketArrowStroke = 3.5;
const double kHomeMarketArrowRightGap = 2;

/// Шиорни авто-мослаш натижаси.
class MarketSloganFit {
  const MarketSloganFit(this.fontSize, {required this.fits, required this.maxLines});

  final double fontSize;

  /// `true` — бутун шиор шу ўлчамда қутига сиғади (кесилмайди).
  final bool fits;

  /// [fits] бўлса — `null` (чеклов йўқ); акс ҳолда 9 px да қутига сиғадиган қаторлар сони (ellipsis).
  final int? maxLines;
}

/// Эга 2026-11-16: шиор учун ЭНГ КАТТА шрифт ([kHomeMarketSloganMinFont]..[kHomeMarketSloganMaxFont],
/// 0.5 px қадам, line height 1.1) — бутун шиор `maxWidth × maxHeight` қутига кесилмасдан сиғадиган.
/// Сўз ўртасидан бўлинмаслиги ҳам шарт (энг узун сўз ≤ кенглик). 9 px да ҳам сиғмаса — 9 px + ellipsis.
/// [baseStyle] — Text виджети ишлатадиган тўлиқ услуб (DefaultTextStyle билан бирлаштирилган).
MarketSloganFit fitMarketSloganFont({
  required String text,
  required double maxWidth,
  required double maxHeight,
  required TextScaler textScaler,
  TextStyle baseStyle = const TextStyle(),
  TextDirection textDirection = TextDirection.ltr,
}) {
  TextPainter paint(double fs) => TextPainter(
        text: TextSpan(
          text: text,
          style: baseStyle.copyWith(fontSize: fs, height: kHomeMarketSloganLineHeight),
        ),
        textDirection: textDirection,
        textScaler: textScaler,
      )..layout(maxWidth: maxWidth);

  if (maxWidth > 0 && maxHeight > 0) {
    for (var fs = kHomeMarketSloganMaxFont; fs >= kHomeMarketSloganMinFont; fs -= 0.5) {
      final tp = paint(fs);
      final ok = tp.height <= maxHeight + 0.01 && tp.minIntrinsicWidth <= maxWidth + 0.01;
      tp.dispose();
      if (ok) return MarketSloganFit(fs, fits: true, maxLines: null);
    }
  }
  final tp = paint(kHomeMarketSloganMinFont);
  final lines = tp.computeLineMetrics();
  final lineH = lines.isEmpty ? 1.0 : lines.first.height;
  tp.dispose();
  final n = lineH <= 0 ? 1 : (maxHeight / lineH).floor();
  return MarketSloganFit(kHomeMarketSloganMinFont, fits: false, maxLines: n < 1 ? 1 : n);
}

class _MarketCard extends StatelessWidget {
  const _MarketCard({required this.entry, required this.slogan, required this.onTap});

  final HomeMarketEntry entry;
  final String slogan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final radius = BorderRadius.circular(AvaRadius.card);
    return Material(
      key: ValueKey('home_market_card_${entry.id}'),
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      // Эга 2026-11-16: чегара расм ОСТИДА чизилади — расм устида кулранг чизиқ кўринмайди, матн томонида қолади.
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: c.line)),
        child: InkWell(
          onTap: onTap,
          // Эга 2026-11-16: карта баландлиги = расм баландлиги (64), ички чет йўқ — расм карта четига тегади;
          // сарлавҳа ↔ чегара 1 px, сарлавҳа ↔ шиор 1 px, шиор ↔ пастки чегара 2 px; матн устуни
          // стрелкагача 1 px; шиор шрифти ҳар карта учун авто-мосланади ([fitMarketSloganFont]).
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.0,
            child: SizedBox(
              height: kHomeMarketCardHeight,
              child: Row(
                children: [
                  Image.asset(
                    entry.imagePath,
                    width: 100,
                    height: kHomeMarketCardHeight,
                    fit: BoxFit.cover,
                    cacheWidth: 300,
                    errorBuilder: (_, __, ___) =>
                        Container(width: 100, height: kHomeMarketCardHeight, color: c.surface2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      key: ValueKey('home_market_text_${entry.id}'),
                      padding: const EdgeInsets.only(top: 1, right: 1, bottom: kHomeMarketSloganBottomGap),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Text(
                            context.tr(entry.titleKey),
                            key: ValueKey('home_market_title_${entry.id}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            // Эга 2026-11-16: сарлавҳа устун ўртасида, каттароқ ва кенгроқ — ҳамма картада бир хил.
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: kHomeMarketTitleFont,
                              fontWeight: FontWeight.w700,
                              letterSpacing: kHomeMarketTitleLetterSpacing,
                              color: c.ink,
                            ),
                          ),
                          if (slogan.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, box) {
                                  final style = DefaultTextStyle.of(context)
                                      .style
                                      .merge(TextStyle(color: c.ink2));
                                  final fit = fitMarketSloganFont(
                                    text: slogan,
                                    maxWidth: box.maxWidth,
                                    maxHeight: box.maxHeight,
                                    textScaler: MediaQuery.textScalerOf(context),
                                    baseStyle: style,
                                    textDirection: Directionality.of(context),
                                  );
                                  return Text(
                                    slogan,
                                    key: ValueKey('home_market_slogan_${entry.id}'),
                                    maxLines: fit.maxLines,
                                    overflow: fit.fits ? TextOverflow.clip : TextOverflow.ellipsis,
                                    style: style.copyWith(
                                      fontSize: fit.fontSize,
                                      height: kHomeMarketSloganLineHeight,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Эга 2026-11-16 (охирги): стрелка КАТТА ва ЖУДА ҚАЛИН (CustomPaint, 3.5 px, юмалоқ учлар, c.ink),
                  // вертикал марказда, карта ўнг четидан 2 px; матн устуни стрелкагача 1 px — шиор кенглиги шундан.
                  SizedBox(
                    key: ValueKey('home_market_arrow_${entry.id}'),
                    width: kHomeMarketArrowWidth,
                    height: kHomeMarketArrowHeight,
                    child: CustomPaint(painter: HomeMarketChevronPainter(color: c.ink)),
                  ),
                  const SizedBox(width: kHomeMarketArrowRightGap),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Карта стрелкаси — қалин шеврон «›» ([kHomeMarketArrowStroke] px, юмалоқ учлар).
class HomeMarketChevronPainter extends CustomPainter {
  const HomeMarketChevronPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const s = kHomeMarketArrowStroke;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final h = size.height * 0.62; // шеврон баландлиги
    final top = (size.height - h) / 2;
    final path = Path()
      ..moveTo(s / 2 + 1, top)
      ..lineTo(size.width - s / 2 - 1, size.height / 2)
      ..lineTo(s / 2 + 1, top + h);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(HomeMarketChevronPainter old) => old.color != color;
}
