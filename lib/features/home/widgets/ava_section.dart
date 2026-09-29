import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import 'service_circle_tile.dart';

/// Бўлимнинг ҳолати.
/// Бозор маҳсулотлари — ЁНГА сурилувчи ИККИ қатор (эга қарори,
/// 2026-09-27: «махсулотлар қатори 2 га оширилсин»).
///
/// Тўлдириш УСТУН бўйича: 1-маҳсулот тепада, 2-си остида, 3-си кейинги
/// устун тепасида. Шунда энг янги моллар доим чап томонда тўпланади —
/// ёнга сурилувчи витриналарда одатий тартиб (горизонтал `GridView`
/// айнан шундай тўлдиради).
///
/// Маҳсулот [minForTwoRows] дан кам бўлса БИТТА қаторга тушади: акс
/// ҳолда 2 та мол учун 500px бўш жой эгалланиб, иккинчи қатор ярим-ёрти
/// осилиб қоларди (улгуржи ва Хитой бозорида ҳозир 0 та мол бор).
class AvaProductShelf extends StatelessWidget {
  const AvaProductShelf({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.rowHeight,
    this.controller,
    this.itemWidth = 148,
    this.gap = 8,
  });

  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  /// Чексиз скролл учун — бўлим охирига етганда яна маҳсулот юклайди
  /// (`_onScroll`). Узатилмаса ўша хусусият ишламай қолади.
  final ScrollController? controller;

  /// БИТТА қаторнинг баландлиги (`avaTileListHeight`).
  final double rowHeight;

  final double itemWidth;
  final double gap;

  /// Шунчадан кам бўлса иккинчи қатор очилмайди.
  static const int minForTwoRows = 5;

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) return const SizedBox.shrink();
    final twoRows = itemCount >= minForTwoRows;
    final rows = twoRows ? 2 : 1;
    return SizedBox(
      height: rowHeight * rows + (twoRows ? gap : 0),
      child: GridView.builder(
        controller: controller,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        // Горизонтал гридда `crossAxisCount` — ҚАТОРЛАР сони,
        // `mainAxisExtent` эса карточка ЭНИ.
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: rows,
          mainAxisExtent: itemWidth,
          mainAxisSpacing: gap,
          crossAxisSpacing: gap,
        ),
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      ),
    );
  }
}

/// Эълон қаторлари турадиган БОТИҚ майдон (эга қарори, 2026-09-27).
///
/// Ботиқлик ҳар бир қаторга эмас, уларнинг УМУМИЙ майдонига берилади —
/// шунинг учун қатор баландлиги (14px), шрифт (12px) ва оралиқ (1px)
/// ўзгармайди.
///
/// ─── УЧ ҚАВАТ (эга қарори, 2026-09-29 — «D» сояси + «1c» рамка) ───
///
/// • Саҳифа фони — `#F3F5F8` ([AvaColors.bg]).
/// • ОҚ РАМКА — устки қават, виджетнинг ўзи чизади ([AvaColors.surface]).
/// • Ички майдон — БИРИНЧИ қават. Фони [AvaColors.surface2], рамкадан
///   бир поғона тўқроқ: қават фарқи рангдан ҳам сезилади.
///
/// Рамка НИМА УЧУН кўшилди: `AvaSection` — шунчаки `Column`, унинг фони
/// йўқ, яъни бўлимлар тўғридан-тўғри саҳифа фонида турарди. Майдон
/// (`#EEF1F6`) билан саҳифа (`#F3F5F8`) фарқи каналларига 5/4/2 — деярли
/// кўринмас эди, ва чуқурликни ёлғиз соя кўтариб турарди. Оқ билан
/// фарқ 17/14/9, яъни уч баробар кучли.
///
/// «1c» — рамкада ҳошия ҳам, соя ҳам ЙЎҚ: фақат ранг поғонаси. Энг арзон
/// чизиш ва энг тинч кўриниш (эга танлови).
///
/// Соя майдоннинг ЎЗ ЧЕГАРАСИДА кесилади ва матнга ёйилмайди. Аввалги
/// ечим тепадан пастга 20px градиент чизар эди — у чуқурлик эмас,
/// биринчи икки қатор устидаги хиралик бўлиб кўринарди (эга, 2026-09-29).
///
/// Flutter'да CSS'даги `box-shadow: inset` нинг муқобили ЙЎҚ: `BoxShadow`
/// фақат ташқарига тушади. Шунинг учун соя [_InsetShadowPainter] да
/// қўлда чизилади — майдон шакли қирқим қилиб қўйилади ва соя ўша
/// қирқим ичида қолади.
///
/// Аввал ҳар бўлим шу кўринишни ўз ичида, қўлда ясар эди (бешта бир хил
/// `Container`) — энди битта жойда. Уни олтита бўлим ишлатади.
class AvaInsetPanel extends StatelessWidget {
  const AvaInsetPanel({super.key, required this.child});

  final Widget child;

  /// Соя тасмасининг кенглиги. Силжиш ва хиралик шундан ҳисобланади,
  /// яъни чуқурликни БИТТА сон бошқаради.
  static const double band = 4;

  /// Соянинг пастга силжиши — ёруғлик тепадан тушгандек кўринсин.
  static const double _dy = band * 0.5;

  /// Хиралик радиуси — CSS'даги `blur-radius` билан бир хил маънода.
  static const double _blur = band * 1.6;

  /// Оқ рамканинг ички бўшлиғи. Бўлим шунинг ИККИ баробарига узаяди
  /// (10px да +20px, олтита бўлимда ~120px) — камайтирмоқчи бўлсангиз
  /// фақат шу сонга тегинг.
  static const double framePad = 10;

  /// Ички майдон радиуси — рамканикидан кичикроқ, шунда ичкарига
  /// жойлашган бўлиб кўринади.
  static const double _innerRadius = 10;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final innerRadius = BorderRadius.circular(_innerRadius);
    // УСТКИ ҚАВАТ — оқ рамка. Ҳошия ҳам, соя ҳам йўқ («1c»): қават
    // фарқини рангнинг ўзи кўтаради.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AvaRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(framePad),
        // Қирқим аввалги ечимда ҳам бор эди
        // (`clipBehavior: Clip.antiAlias`) — бола виджет юмалоқ
        // бурчакдан чиқиб кетмасин.
        child: ClipRRect(
          borderRadius: innerRadius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: innerRadius,
            ),
            child: CustomPaint(
              // `foregroundPainter` — соя матн УСТИДАН чизилади, лекин у
              // чеккадаги тасмада қолгани учун матнга тегмайди.
              foregroundPainter: _InsetShadowPainter(
                color: c.insetShadow,
                radius: _innerRadius,
                dy: _dy,
                blur: _blur,
              ),
              child: Padding(
                // Вертикал 4 → 6: матн соя тасмасига кирмасин. Қатор
                // баландлиги ва шрифт ўзгармайди.
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ички соя — [AvaInsetPanel] учун.
///
/// Ишлаш тартиби: майдон шакли қирқим қилиб қўйилади, сўнг унинг ичига
/// «тешикли» шакл хираланган ҳолда чизилади. Тешикнинг чети хираланганда
/// соя майдон ичига қараб тушади, қирқим эса уни чегарада тўхтатади:
/// на ташқарига чиқади, на матнга ёйилади.
class _InsetShadowPainter extends CustomPainter {
  const _InsetShadowPainter({
    required this.color,
    required this.radius,
    required this.dy,
    required this.blur,
  });

  final Color color;
  final double radius;

  /// Соянинг пастга силжиши.
  final double dy;

  /// Хиралик радиуси.
  final double blur;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.save();
    // Қирқим — соя шу чегарадан ташқарига чиқа олмайди.
    canvas.clipRRect(rrect);
    // Ташқи тўртбурчакдан майдон шаклини айириб «ҳалқа» оламиз. Ҳалқа
    // хираланганда унинг ички чети майдонга соя бўлиб тушади.
    final ring = Path.combine(
      ui.PathOperation.difference,
      Path()..addRect(rrect.outerRect.inflate(blur * 2 + dy + 1)),
      Path()..addRRect(rrect.shift(Offset(0, dy))),
    );
    canvas.drawPath(
      ring,
      Paint()
        ..color = color
        // `MaskFilter.blur` сигма билан ишлайди, CSS эса радиус билан:
        // сигма ≈ радиус / 2.
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, blur / 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InsetShadowPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.dy != dy ||
      old.blur != blur;
}

/// Бўлим ичидаги қаторлар — [visibleRows] таси кўринади, қолгани ЁНГА
/// суриб кўрилади (эга қарори, 2026-09-27).
///
/// НЕГА ЁНГА, ПАСТГА ЭМАС. Аввал бу ерда вертикал `SingleChildScrollView`
/// бор эди. Бош саҳифанинг ўзи ҳам вертикал скролл — Flutter'да бир хил
/// йўналишдаги иккита скролл ичма-ич турса, бармоқ ичкаридаги рўйхат
/// устида бўлганда ҳаракатни ЎША ушлаб қолади ва рўйхат охирига етганда
/// ҳам қолган ҳаракат отасига ЎТМАЙДИ. Натижада фойдаланувчи саҳифани
/// пастга сура олмай қолар эди (эга қурилмада сезди).
///
/// Горизонтал саҳифалашда бундай тўқнашув умуман йўқ: вертикал ҳаракат
/// доим саҳифага, горизонтал ҳаракат доим шу виджетга тегишли.
///
/// Охирги саҳифада ЯНА ёнга сурилса — [onOpenModule] чақирилади, яъни
/// бўлимнинг тўлиқ экрани очилади («Барчаси →» билан бир хил жой).
class AvaRowPager extends StatefulWidget {
  const AvaRowPager({
    super.key,
    required this.rows,
    required this.rowHeight,
    this.visibleRows = 5,
    this.rowGap = 1,
    this.onOpenModule,
  });

  /// Тайёр қаторлар. Оралиқни виджетнинг ўзи қўяди — чақирувчида
  /// `SizedBox(height: 1)` керак эмас.
  final List<Widget> rows;

  /// Битта қаторнинг баландлиги ([textRow] ёки [avatarRow]).
  final double rowHeight;

  /// Битта саҳифада нечта қатор.
  final int visibleRows;

  /// Қаторлар ораси.
  final double rowGap;

  /// Охирги саҳифадан яна ёнга сурилганда — модул экрани.
  final VoidCallback? onOpenModule;

  /// Нуқта + бир сатр матн: [AvaText.feedRow] нинг қатор баландлиги
  /// тизим шрифти 100% бўлгандаги ҳолати.
  ///
  /// ТЎҒРИДАН-ТЎҒРИ ИШЛАТМАНГ — [textRowHeight] ни чақиринг.
  static const double textRow = 14;

  /// Матнли қатор баландлиги — тизим шрифти билан БИРГА ўсади.
  ///
  /// НЕГА: `AvaText.feedRow` (12px, height 14/12) 100% шрифтда айнан
  /// 14px жой эгаллайди — яъни [textRow] га тиқ-тиқ сиғади, захира йўқ.
  /// Фойдаланувчи тизим шрифтини 130% қилса қатор 18.2px бўлади ва
  /// қатъий 14px қутига сиғмай, ҳарфларнинг пастки думлари («р», «у»)
  /// КЕСИЛАДИ.
  ///
  /// Қурилмада топилди (2026-09-27, TECNO LH7n, `font_scale=1.3`).
  /// Эски виджет тестлари буни тутмаган эди: улар фақат
  /// `takeException()` ни, яъни «тошиб кетиш хатоси» ни текширарди —
  /// кесилиш эса хато чиқармайди, чунки `SizedBox` жимгина қирқади.
  /// Танишув бўлимида ҳам АЙНАН шу баландлик ишлатилади (эга қарори,
  /// 2026-09-27: «қаторлар орасидаги масофа бошқа бўлимдагидек бўлсин»).
  /// Олдин у алоҳида `avatarRow = 28` эди — бош ҳарф доираси қаторни
  /// керагидан икки баробар баланд қилиб юборарди.
  static double textRowHeight(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(textRow);

  /// Модулга ўтиш учун охирги саҳифадан кейин сурилиши керак бўлган масофа.
  static const double _openThreshold = 56;

  @override
  State<AvaRowPager> createState() => _AvaRowPagerState();
}

class _AvaRowPagerState extends State<AvaRowPager> {
  final _controller = PageController();
  int _page = 0;
  double _overscroll = 0;
  bool _opened = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<List<Widget>> get _pages {
    final out = <List<Widget>>[];
    for (var i = 0; i < widget.rows.length; i += widget.visibleRows) {
      out.add(widget.rows.sublist(
        i,
        (i + widget.visibleRows).clamp(0, widget.rows.length),
      ));
    }
    return out;
  }

  double get _height =>
      widget.visibleRows * widget.rowHeight +
      (widget.visibleRows - 1) * widget.rowGap;

  bool _onScroll(ScrollNotification n) {
    final pages = _pages.length;
    if (n is OverscrollNotification) {
      // Фақат ОХИРГИ саҳифадан ўнгга сурилганда (мусбат overscroll).
      if (_page >= pages - 1 && n.overscroll > 0) {
        _overscroll += n.overscroll;
        if (!_opened &&
            _overscroll > AvaRowPager._openThreshold &&
            widget.onOpenModule != null) {
          _opened = true;
          widget.onOpenModule!.call();
        }
      }
    } else if (n is ScrollEndNotification) {
      _overscroll = 0;
      _opened = false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final pages = _pages;
    if (pages.isEmpty) return const SizedBox.shrink();

    // Битта саҳифагина бўлса — саҳифалаш ҳам, нуқталар ҳам ортиқча.
    if (pages.length == 1) {
      return _Page(rows: pages.first, rowHeight: widget.rowHeight, gap: widget.rowGap);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _height,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: PageView.builder(
              controller: _controller,
              // `PageScrollPhysics` — саҳифага ёпишиш (усиз рўйхат эркин
              // сурилиб, қаторлар ярим-ёрти кўриниб қоларди).
              // `ClampingScrollPhysics` ота сифатида — сакраш (bounce)
              // бўлмайди, лекин четга урилганда `OverscrollNotification`
              // келаверади; модулга ўтиш айнан шунга таянади.
              physics: const PageScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              itemCount: pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => _Page(
                rows: pages[i],
                rowHeight: widget.rowHeight,
                gap: widget.rowGap,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < pages.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: i == _page ? 14 : 5,
                height: 5,
                decoration: BoxDecoration(
                  color: i == _page ? c.brand : c.line,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Битта саҳифа — тепадан бошлаб терилган қаторлар.
class _Page extends StatelessWidget {
  const _Page({required this.rows, required this.rowHeight, required this.gap});

  final List<Widget> rows;
  final double rowHeight;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          SizedBox(height: rowHeight, child: rows[i]),
        ],
      ],
    );
  }
}

enum AvaSectionStatus {
  /// Маълумот юкланмоқда.
  loading,

  /// Маълумот бор — [AvaSection.child] кўрсатилади.
  ready,

  /// Маълумот йўқ — бўлим ўз ўрнида қолади, битта ихчам қаторга айланади.
  empty,

  /// Юклашда хатолик — ихчам қатор + «Қайта уриниш».
  error,
}

/// Бош саҳифанинг бўлим каркаси: сарлавҳа + «Барчаси →» + 4 та ҳолат.
///
/// Тавсиф талаби: «Бўш бўлим ўз ўрнида қолади ва битта ихчам қаторга
/// айланади». Шунинг учун [AvaSectionStatus.empty] да ҳам сарлавҳа
/// кўринади — бўлим саҳифадан йўқолиб кетмайди ва рўйхат «сакрамайди».
class AvaSection extends StatelessWidget {
  const AvaSection({
    super.key,
    required this.title,
    required this.status,
    this.child,
    this.onSeeAll,
    this.onRetry,
    this.emptyLabel,
    this.skeletonRows = 3,
    this.moduleId,
  });

  final String title;
  final AvaSectionStatus status;

  /// Сарлавҳа олдидаги ихчам ранг доира учун модул (`'intercity'`,
  /// `'jobs'` …). `null` бўлса доира чизилмайди — эски чақирувлар
  /// ўзгаришсиз ишлайверади.
  ///
  /// Доира хизматлар рўйхатидагиси билан АЙНАН бир хил ранг ва расмда
  /// бўлади ([ServiceCircleBadge]), фақат кичик — шунда бўлим ва
  /// хизматлар блоки бир-бирига боғланиб туради.
  final String? moduleId;

  /// `status == ready` бўлганда кўрсатиладиган мазмун.
  final Widget? child;

  /// «Барчаси →» — бўлимнинг тўлиқ саҳифасини очади. `null` бўлса тугма йўқ.
  final VoidCallback? onSeeAll;

  /// Хатолик ҳолатида қайта уриниш.
  final VoidCallback? onRetry;

  /// Бўш ҳолат матни; берилмаса `home_section_empty`.
  final String? emptyLabel;

  /// Юкланиш ҳолатидаги «скелет» қаторлар сони.
  final int skeletonRows;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(title: title, onSeeAll: onSeeAll, moduleId: moduleId),
        const SizedBox(height: AvaSpace.sectionHeaderGap),
        switch (status) {
          AvaSectionStatus.ready =>
            child ?? const SizedBox.shrink(),
          AvaSectionStatus.loading => _Skeleton(rows: skeletonRows),
          AvaSectionStatus.empty => AvaNoticeRow(
              text: emptyLabel ?? context.tr('home_section_empty'),
              icon: Icons.inbox_outlined,
              color: c.ink3,
            ),
          AvaSectionStatus.error => AvaNoticeRow(
              text: context.tr('home_section_error'),
              icon: Icons.cloud_off_rounded,
              color: c.warn,
              actionLabel:
                  onRetry == null ? null : context.tr('home_section_retry'),
              onAction: onRetry,
            ),
        },
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.onSeeAll, this.moduleId});

  final String title;
  final VoidCallback? onSeeAll;
  final String? moduleId;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    // `Row` flex бўлмаган болани аввал ЧЕКСИЗ кенгликда ўлчайди, шунинг
    // учун узун ёрлиқ («Барчаси» нинг бошқа тилдаги варианти ёки 130%
    // шрифт) тугмани бутун қаторни тошириб юборадиган даражада кенг
    // қилиши мумкин эди. Тугмага қатъий юқори чегара қўямиз — ундан
    // ошса ичидаги матн ellipsis'га тушади, сарлавҳа эса қолган жойни
    // олади.
    // Тизим шрифти катталашганда «Барчаси» ёрлиғи сарлавҳани сиқиб қўяди:
    // қурилмада 130% да «Яқинингиздаги эъ…» бўлиб қирқилган эди. Шундай
    // ҳолатда тугма фақат стрелкага айланади — босиш майдони ва
    // Semantics ёрлиғи ўша-ўша қолади.
    // Ёрлиқ 12 → 11px га кичрайгандан кейин тугма ҳам торайди, яъни
    // сарлавҳани сиқиб қўйиш хавфи кечроқ бошланади — шунинг учун
    // чегара ҳам кўтарилди (аввал `scale(12) > 14`).
    final compact = MediaQuery.textScalerOf(context).scale(11) > 15;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxSeeAll = constraints.maxWidth.isFinite
            ? constraints.maxWidth * (compact ? 0.22 : 0.45)
            : double.infinity;
        final id = moduleId;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (id != null && hasServiceGlyph(id)) ...[
              ServiceCircleBadge(moduleId: id),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AvaText.sectionTitle.copyWith(color: c.ink),
              ),
            ),
            if (onSeeAll != null) ...[
              const SizedBox(width: AvaSpace.gap),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxSeeAll),
                child: _SeeAllButton(onTap: onSeeAll!, iconOnly: compact),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// «Барчаси →» — босиш майдони камида 44.
///
/// Эга қарори (2026-09-27): стрелка ҚАЛИНРОҚ, «Барчаси» эса ИХЧАМРОҚ —
/// сарлавҳага кўпроқ жой қолсин, ўтиш белгиси эса кўзга яққол ташлансин.
class _SeeAllButton extends StatelessWidget {
  const _SeeAllButton({required this.onTap, this.iconOnly = false});

  final VoidCallback onTap;

  /// Жуда катта тизим шрифтида — фақат стрелка (сарлавҳа қирқилмасин).
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final label = context.tr('home_section_see_all');
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AvaRadius.chip),
        child: ConstrainedBox(
          // Матн 130% гача катталашса ҳам босиш майдони кичраймайди ва
          // ёрлиқ қирқилмайди — шунинг учун қатъий баландлик эмас, минимум.
          //
          // 44 → 32 (эга қарори, 2026-09-27: «сарлавҳа билан майдон
          // орасидаги масофа қисқартирилсин»). Айнан шу 44 сарлавҳа
          // ҚАТОРИНИНГ баландлигини белгилар эди: сарлавҳа матни 20px,
          // қолган 24px эса тепа-пастга бўш жой бўлиб тарқаларди. Энди
          // қатор 32px — сарлавҳа тагидаги бўшлиқ 12px дан 6px га тушди.
          //
          // Босиш майдони ЁНИГА кенг қолади (матн + стрелка + чекинма),
          // шунинг учун тегиш қийинлашмайди — фақат бўйи пасайди.
          constraints: const BoxConstraints(minHeight: _seeAllMinHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!iconOnly) ...[
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // Ихчам: 11px. Аввал `AvaText.caption` эди — бу ерда
                      // ёрлиқ иккинчи даражали, асосийси сарлавҳа.
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        color: c.brand,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                ],
                _ThickArrow(color: c.brand),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Барчаси» тугмасининг баландлиги — қаранг: [_SeeAllButton] изоҳи.
const double _seeAllMinHeight = 32;

/// «Барчаси» стрелкасининг тест калити.
///
/// Аввал тестлар `Icons.arrow_forward_rounded` ни излаган эди; стрелка
/// энди чизилгани учун иконка йўқ. Калит — барқарор нишон: ичидаги
/// чизиш усули ўзгарса ҳам тест синмайди.
const Key kSeeAllArrowKey = ValueKey('ava_see_all_arrow');

/// Қалин ўнг стрелка.
///
/// `Icon(Icons.arrow_forward_rounded)` ишлатилмайди: `MaterialIcons` —
/// СТАТИК шрифт, шунинг учун `Icon(weight: …)` унга таъсир қилмайди ва
/// стрелка ингичка бўлиб қолаверарди. Бу ерда у чизилади — қалинлик
/// [stroke] билан аниқ бошқарилади.
class _ThickArrow extends StatelessWidget {
  const _ThickArrow({required this.color});

  final Color color;

  /// Чизиқ қалинлиги — стандарт иконка ~1.5 эди.
  static const double stroke = 2.4;
  static const Size _size = Size(15, 13);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: kSeeAllArrowKey,
      size: _size,
      painter: _ThickArrowPainter(color: color),
    );
  }
}

class _ThickArrowPainter extends CustomPainter {
  const _ThickArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ThickArrow.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final cy = size.height / 2;
    // Учи ўткир кўринмаслиги учун чизиқ четдан ярим қалинлик чекинади.
    final pad = _ThickArrow.stroke / 2;
    final tipX = size.width - pad;
    final headBack = tipX - size.height * 0.42;

    // Танаси.
    canvas.drawLine(Offset(pad, cy), Offset(tipX, cy), p);
    // Учи (˅ шакли ёнбошига).
    canvas.drawPath(
      Path()
        ..moveTo(headBack, pad)
        ..lineTo(tipX, cy)
        ..lineTo(headBack, size.height - pad),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _ThickArrowPainter old) => old.color != color;
}

/// Бўш / хатолик ҳолатининг ихчам қатори.
class AvaNoticeRow extends StatelessWidget {
  const AvaNoticeRow({
    super.key,
    required this.text,
    required this.icon,
    required this.color,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final IconData icon;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      constraints: const BoxConstraints(minHeight: AvaTap.minSize),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AvaSpace.gap),
          Expanded(
            child: Text(
              text,
              style: AvaText.caption.copyWith(color: c.ink2),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: AvaSpace.gap),
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(AvaRadius.chip),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text(
                  actionLabel!,
                  style: AvaText.caption.copyWith(color: c.brand),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Юкланиш «скелети» — мазмун келгунча жой эгаллаб туради, шунда рўйхат
/// маълумот келганда сакрамайди.
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.rows});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Column(
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == rows - 1 ? 0 : 8),
            child: Container(
              height: 58,
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(AvaRadius.card),
              ),
            ),
          ),
      ],
    );
  }
}
