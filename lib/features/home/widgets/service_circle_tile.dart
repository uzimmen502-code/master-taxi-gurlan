import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/theme/ava_tokens.dart';
import '../home_module_gate.dart';
import 'services_spotlight_carousel.dart' show ServiceSpotlightItem;

/// OLX бош экранидаги «Разделы на сервисе OLX» катаги услуби.
///
/// olx.uz дан 2026-09-26 да ЖОНЛИ ўлчанган (DOM, мобил 375px):
///   • расм доираси — **88×88** (бизда 20% кичик, қаранг [circleSize]);
///   • катак баландлиги — **156** (бизда 136, доирага мос);
///   • ёрлиқ — **16px / w600 / rgb(2,40,44)**, қатор баландлиги 20, марказда;
///   • рамка ЙЎҚ, соя ЙЎҚ, градиент ЙЎҚ, бурчак радиуси ЙЎҚ.
///
/// OLX'да доиранинг ранги расмнинг ичига сингдирилган (битта PNG). Бизда
/// хизмат расмлари шаффоф фонли, шунинг учун ранг [olxTintFor] дан олинади
/// ва доира кодда чизилади — натижа бир хил кўринади.
///
/// Эски [ServiceSpotlightTile] (3D «аркада тугмаси»: қизил-яшил рамка,
/// градиент, тушувчи соя) ЎЧИРИЛМАДИ — бош саҳифадаги карусель ҳамон уни
/// ишлатади. Бу катак фақат «Барча хизматлар» экрани учун.
class ServiceCircleTile extends StatefulWidget {
  const ServiceCircleTile({super.key, required this.item});

  final ServiceSpotlightItem item;

  /// OLX'даги ҳақиқий доира ўлчами — манба сифатида сақланади
  /// (ўзгартирманг: бу ўлчанган қиймат, созлама эмас).
  static const double olxReferenceCircle = 88;

  /// Бизнинг доира. Икки босқичда кичрайтирилган (эга қарори, иккиси
  /// ҳам 2026-09-27):
  ///
  ///   88 (OLX) → −20% → 70 → −15% → 59.5 ≈ **60**
  ///
  /// Сабаби: бош саҳифада хизматлар блоки 2 қатор бўлгани учун 88px
  /// доира билан ~320px жой эгаллар эди, бу эса қолган бўлимлари зич
  /// (14px қатор, 1px оралиқ) бўлган лентага мос тушмасди.
  ///
  /// 60 — яхлит қиймат (аниқ 15% 59.5 бўлар эди, фарқи 0.5px).
  static const double circleSize = 60;

  /// Доира билан ёзув ораси.
  static const double labelGap = 12;

  /// Ёзув энг кўпи шунча қаторга ўралади.
  ///
  /// 3 → **2** (2026-09-27): шрифт 2 баробар кичрайгач қурилмада
  /// ТЕКШИРИЛДИ — мавжуд 13 та ёрлиқнинг ҲАММАСИ бир қаторга сиғади
  /// («Шаҳарлараро такси», «Менинг яқинларим», «ChatGPT + AVA AI»).
  /// 3-қаторга сақланган жой ҳеч қачон ишлатилмас, лекин катак остида
  /// ўлик бўшлиқ бўлиб қолар ва қаторларни бир-биридан узоқлаштирар
  /// эди. 2 қатор — келажакда узунроқ ёрлиқ қўшилса деб қолдирилган
  /// заҳира (бу ўлчамда бир қаторга ~30 белги сиғади).
  static const int labelMaxLines = 2;

  /// Ёзув қаторининг зичлиги (`TextStyle.height`).
  static const double labelLineHeight = 1.25;

  /// Ёрлиқ шрифти устун энига боғланган: OLX кенглигида керакли ўлчам
  /// чиқади, торроқ экранда эса ўзи кичраяди.
  ///
  /// Коэффициент 0.125 → **0.0625**: эга қарори, 2026-09-27 —
  /// «шрифт ўлчамини 2 баробарга кичрайтир». Чегаралар ҳам худди
  /// шундай иккига бўлинди (11.5–16 → 5.75–8).
  ///
  /// Ёндош фойда: 104px устунда ўлчам 13 → 6.5 бўлгани учун
  /// «Шаҳарлараро» каби узун ЯГОНА сўз энди бир қаторга сиғади ва
  /// олдин қурилмада кўринган сўз ўртасидан бўлиниш («Шаҳарларар /
  /// о такси») ўз-ўзидан йўқолади.
  static const double labelSizeFactor = 0.0625;
  static const double labelSizeMin = 5.75;
  static const double labelSizeMax = 8;

  /// Берилган устун эни учун ёрлиқ шрифти.
  static double labelFontSize(double columnWidth) =>
      (columnWidth * labelSizeFactor)
          .clamp(labelSizeMin, labelSizeMax)
          .toDouble();

  /// Катак баландлиги: доира + оралиқ + [labelMaxLines] қатор ёзув.
  ///
  /// Шрифт 2 баробар кичрайгач бу ҳам қисқарди (136 → 102), доира 15%
  /// кичрайгач яна (102 → **92**). Акс ҳолда ёзув остида ўлик бўш жой
  /// қолар, у эса аслида ИККИ ҚАТОР ОРАСИДАГИ масофага айланиб,
  /// «қаторлар орасини максимал қисқартир» талабини бекор қилар эди.
  ///
  /// Ҳисоб: 60 доира + 12 оралиқ + 2 қатор × 6.5px × 1.25 × 1.15
  /// (шрифт масштаби чегараси) ≈ 90.7 → 92.
  static const double tileHeight = 92;

  @override
  State<ServiceCircleTile> createState() => _ServiceCircleTileState();
}

class _ServiceCircleTileState extends State<ServiceCircleTile> {
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
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    HomeModuleGate.gatedTap(context, widget.item.moduleId, widget.item.onTap)();
    await Future<void>.delayed(const Duration(milliseconds: 70));
    if (mounted) _setPressed(false);
    _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final item = widget.item;
    final tint = olxTintFor(item.moduleId);

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final labelSize = ServiceCircleTile.labelFontSize(w);
        final circle =
            ServiceCircleTile.circleSize.clamp(56.0, w - 8).toDouble();

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _handleTap(),
          onTapCancel: () => _setPressed(false),
          child: Semantics(
            button: true,
            label: item.label,
            child: AnimatedScale(
              scale: _pressed ? 0.93 : 1.0,
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOut,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: circle,
                    height: circle,
                    decoration: BoxDecoration(
                      color: tint,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    // Расм доирадан ошиб кетмасин — OLX'да ҳам расм
                    // доиранинг ичида, четида ҳаво қолади.
                    child: Padding(
                      padding: EdgeInsets.all(circle * 0.14),
                      child: _Glyph(item: item, size: circle * 0.72),
                    ),
                  ),
                  const SizedBox(height: ServiceCircleTile.labelGap),
                  Flexible(
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.15,
                      child: Text(
                        item.label,
                        textAlign: TextAlign.center,
                        maxLines: ServiceCircleTile.labelMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: labelSize,
                          fontWeight: FontWeight.w600,
                          height: ServiceCircleTile.labelLineHeight,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Доира ичидаги расм/иконка — манба тури бўйича.
class _Glyph extends StatelessWidget {
  const _Glyph({required this.item, required this.size});

  final ServiceSpotlightItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (item.svgPath != null) {
      return SvgPicture.asset(
        item.svgPath!,
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    }
    if (item.imagePath != null) {
      return Image.asset(
        item.imagePath!,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => _fallbackIcon(size),
      );
    }
    if (item.icon != null) {
      // Ранг берилмаган иконкалар доира устида оқ — доира ранги тўйинган.
      return Icon(item.icon, size: size * 0.86, color: Colors.white);
    }
    if (item.emoji != null) {
      return Text(
        item.emoji!,
        style: TextStyle(fontSize: size * 0.72, height: 1.0),
      );
    }
    return _fallbackIcon(size);
  }

  Widget _fallbackIcon(double s) =>
      Icon(Icons.apps_rounded, size: s * 0.8, color: Colors.white);
}

/// Бўлим САРЛАВҲАСИ олдидаги ихчам доира — каталог катагининг кичик
/// нусхаси (эга қарори, 2026-09-27).
///
/// Мақсад: бош саҳифадаги ҳар бўлим ўз хизматининг ранги ва расми билан
/// бошлансин — шунда фойдаланувчи сарлавҳани ўқимасдан ҳам қайси бўлим
/// экани кўзга ташланади.
class ServiceCircleBadge extends StatelessWidget {
  const ServiceCircleBadge({
    super.key,
    required this.moduleId,
    this.size = 24,
  });

  final String moduleId;

  /// Диаметр. Сарлавҳа 16px/20px қатор — 24 унга ихчам мос тушади.
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = serviceImageFor(moduleId);
    final svg = serviceSvgFor(moduleId);
    final icon = serviceIconFor(moduleId);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: olxTintFor(moduleId),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: EdgeInsets.all(size * 0.14),
        child: svg != null
            ? SvgPicture.asset(svg, fit: BoxFit.contain)
            : image != null
                ? Image.asset(
                    image,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.apps_rounded,
                      size: size * 0.58,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    icon ?? Icons.apps_rounded,
                    size: size * 0.62,
                    color: Colors.white,
                  ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// moduleId → расм/иконка.
//
// ЭСЛАТМА: бу жадвал `home_services_catalog.dart` даги қийматларни
// такрорлайди. Каталог банди `label` ва `onTap` ни ҳам ташийди, шунинг
// учун у ердан тўғридан-тўғри ўқиб бўлмайди (BuildContext ва
// action'лар керак). Янги модул қўшилганда ИККАЛА жойни янгиланг —
// `service_circle_tint_test.dart` даги тест буни эслатиб туради.
// ─────────────────────────────────────────────────────────────────────

const _kServiceImages = <String, String>{
  'local_taxi': 'assets/images/services/service_taxi_local.png',
  'intercity': 'assets/images/services/service_taxi_intercity.png',
  'marshrut': 'assets/images/services/service_marshrut.png',
  'yuk_local': 'assets/images/services/service_yuk_local.png',
  'yuk_intercity': 'assets/images/services/service_yuk_birja.png',
  'food': 'assets/images/services/service_food.png',
  'jobs': 'assets/images/services/service_jobs.png',
  'cheap_products_home': 'assets/images/services/service_market.png',
  'bread': 'assets/images/services/service_bread.png',
  'oil_change': 'assets/images/services/service_oil_change.png',
  'circles': 'assets/images/services/service_relatives.png',
  'courier': 'assets/images/services/service_courier.png',
  'milk': 'assets/images/services/service_milk.png',
  'tire': 'assets/images/services/service_tire.png',
  'car_wash': 'assets/images/services/service_car_wash.png',
  'carpet_wash': 'assets/images/services/service_carpet_wash.png',
  'ev_charging': 'assets/images/services/service_ev_charging.png',
  'pay_paynet': 'assets/images/services/service_pay_paynet.png',
};

const _kServiceSvgs = <String, String>{
  'pay_click': 'assets/images/services/service_pay_click.svg',
  'pay_payme': 'assets/images/services/service_pay_payme.svg',
};

const _kServiceIcons = <String, IconData>{
  'platform_store': Icons.storefront_rounded,
  'tv_market': Icons.play_circle_filled_rounded,
  'dating': Icons.favorite_rounded,
  'chatgpt': Icons.auto_awesome_rounded,
  'wholesale_market': Icons.warehouse_outlined,
};

/// PNG расм йўли — бўлмаса `null`.
String? serviceImageFor(String moduleId) => _kServiceImages[moduleId];

/// SVG (бренд логотипи) йўли — бўлмаса `null`.
String? serviceSvgFor(String moduleId) => _kServiceSvgs[moduleId];

/// Расми йўқ модуллар учун иконка — бўлмаса `null`.
IconData? serviceIconFor(String moduleId) => _kServiceIcons[moduleId];

/// Модулнинг расми ҳам, иконкаси ҳам борми.
bool hasServiceGlyph(String moduleId) =>
    _kServiceImages.containsKey(moduleId) ||
    _kServiceSvgs.containsKey(moduleId) ||
    _kServiceIcons.containsKey(moduleId);

/// Ҳар хизматнинг доира ранги.
///
/// OLX ҳар бўлимга ўз тўйинган рангини беради (боланинг дунёси — сариқ,
/// кўчмас мулк — кўк, транспорт — феруза…). Бу ерда ҳам ранг хизматнинг
/// МАЪНОСИГА боғланган, тасодифий эмас: такси — сариқ, юк — тўқ сариқ,
/// овқат — қизил, иш — яшил ва ҳк.
///
/// Рангни ўзгартириш керак бўлса — ФАҚАТ шу жадвал таҳрирланади.
Color olxTintFor(String moduleId) {
  switch (moduleId) {
    // ── Транспорт ────────────────────────────────────────────────
    case 'local_taxi':
      return const Color(0xFFFFC93D); // такси сариғи
    case 'intercity':
      return const Color(0xFF1BD9CE); // феруза — OLX «Транспорт»и каби
    case 'marshrut':
      return const Color(0xFF5B7CF5);
    // ── Юк ───────────────────────────────────────────────────────
    case 'yuk_local':
      return const Color(0xFFFF8A3D);
    case 'yuk_intercity':
      return const Color(0xFFF4693B);
    case 'courier':
      return const Color(0xFFFFB020);
    // ── Овқат ва маҳсулот ───────────────────────────────────────
    case 'food':
      return const Color(0xFFFF6B5A);
    case 'bread':
      return const Color(0xFFF2C14E);
    case 'milk':
      return const Color(0xFFBFD8F0);
    // ── Бозор ва эълон ──────────────────────────────────────────
    case 'jobs':
      return const Color(0xFF6FBF3B);
    case 'cheap_products_home':
      return const Color(0xFF8E7BF0);
    case 'wholesale_market':
      return const Color(0xFF12A594);
    case 'platform_store':
      return const Color(0xFF3F6FE4);
    case 'sell':
      return const Color(0xFF7E8CF2);
    // ── Медиа ва ижтимоий ───────────────────────────────────────
    case 'tv_market':
      return const Color(0xFFE9497F);
    case 'circles':
      return const Color(0xFFA8B8F0);
    case 'dating':
      return const Color(0xFFF2789F);
    case 'chatgpt':
      return const Color(0xFF6E5BE0);
    // ── Автохизмат ──────────────────────────────────────────────
    case 'oil_change':
      return const Color(0xFF6E7B8B);
    case 'tire':
      return const Color(0xFF55606E);
    case 'car_wash':
      return const Color(0xFF46B7F0);
    case 'carpet_wash':
      return const Color(0xFF9B6BD6);
    case 'ev_charging':
      return const Color(0xFF2FBF71);
    // ── Тўлов провайдерлари ─────────────────────────────────────
    // Бренд логотиплари ўз рангига эга — доира ОЧ нейтрал бўлади,
    // акс ҳолда логотип билан ранг тўқнашади.
    case 'pay_click':
    case 'pay_payme':
    case 'pay_paynet':
      return const Color(0xFFEEF1F6);
    default:
      return const Color(0xFFD9E2EC);
  }
}
