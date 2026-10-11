import 'package:flutter/material.dart';

import '../../../core/geo/geo_names.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/ava_tokens.dart';

/// Бош саҳифанинг юқори қатори: AVA логотипи + ҳудуд тугмаси.
///
/// Ҳудуд номи [ServiceConfigHolder] кешидан келади ва
/// [ServiceConfigHolder.revision] га обуна бўлади — ҳудуд ўзгарса тугма
/// ўзи янгиланади, бутун саҳифани қайта қуриш керак эмас.
class AvaTopBar extends StatelessWidget {
  const AvaTopBar({super.key, required this.onPickRegion});

  /// Ҳудуд тугмаси босилганда — вилоят/туман танлаш.
  final VoidCallback onPickRegion;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const AvaLogoBadge(),
          const SizedBox(width: 12),
          // Ҳудуд номи узун бўлса («Шайхонтоҳур, Тошкент шаҳри») логотипни
          // сиқиб қўймасин — тугма қолган жойни олади ва ичида қирқилади.
          Expanded(child: _RegionButton(onTap: onPickRegion)),
        ],
      ),
    );
  }
}

/// Юқори чап бурчакдаги логотип: эски AVA логотипи қора думалоқ ичида
/// (эга қарори, 2026-10-08 — «думалоқ шаклда қора фонда, ўлчови катта
/// бўлмасин»). Аввал бу ерда бренд рангидаги «AVA» матни эди.
///
/// Ўлчам — [diameter]: босиш майдони минимумига ([AvaTap.minSize]) яқин,
/// юқори қатор баландлигини деярли ўзгартирмайди. Логотип узунчоқ
/// (≈1.85:1), шунинг учун доира ичида кенглиги [logoWidthFactor] билан
/// чекланади — четларга тегмайди.
class AvaLogoBadge extends StatelessWidget {
  const AvaLogoBadge({super.key});

  static const double diameter = 42;
  static const double logoWidthFactor = 0.8;
  static const String asset = 'assets/images/ava_logo_mark.png';

  /// Логотип фони — бренд токени ЭМАС: бу эски логотипнинг ўз фони.
  static const Color background = Color(0xFF000000);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'AVA',
      image: true,
      child: Container(
        width: diameter,
        height: diameter,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: background,
          shape: BoxShape.circle,
        ),
        child: Image.asset(
          asset,
          width: diameter * logoWidthFactor,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

class _RegionButton extends StatelessWidget {
  const _RegionButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return ListenableBuilder(
      listenable: Listenable.merge([ServiceConfigHolder.revision, GeoNames.revision]),
      builder: (context, _) {
        // `ServiceConfigHolder.geoLabel`нинг тилли шакли (сақланган ёрлиқ — fallback).
        final lang = context.contentLang;
        final d = GeoNames.district(ServiceConfigHolder.districtId, lang,
                fallback: ServiceConfigHolder.districtLabel)
            .trim();
        final r = GeoNames.region(ServiceConfigHolder.regionId, lang,
                fallback: ServiceConfigHolder.regionLabel)
            .trim();
        final geo = d.isEmpty ? r : (r.isEmpty ? d : '$d, $r');
        final chosen = geo.isNotEmpty;
        // Геолокация ёқилмаган / ҳудуд танланмаган — тавсиф талаби
        // бўйича «Ҳудудни танланг».
        final label = chosen ? geo : context.tr('home_region_pick');

        return Align(
          alignment: Alignment.centerRight,
          child: Semantics(
            button: true,
            label: label,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AvaRadius.chip),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AvaTap.minSize),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 18,
                        // brand (#FFA500) крем фонда кам кўринарди —
                        // иконка учун матн-хавфсиз brandText.
                        color: chosen ? c.brandText : c.warn,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: _ShrinkToFitText(
                          text: label,
                          style: AvaText.caption.copyWith(
                            color: chosen ? c.ink : c.warn,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: chosen ? c.ink2 : c.warn,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Матнни берилган кенгликка сиғгунча кичрайтиради — қирқилмайди.
///
/// `FittedBox` матннинг ҳақиқий ўлчамини ўзи ўлчайди, шунинг учун
/// шрифт метрикасини қўлда тахмин қилишдан аниқроқ. Кенглик чекланмаган
/// ёки 0 бўлган layout pass'да эса у Transform matrix'ни NaN қилиб
/// қўйиши мумкин, шунинг учун бундай ҳолатда оддий `Text` чизилади.
class _ShrinkToFitText extends StatelessWidget {
  const _ShrinkToFitText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final label = Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: style,
        );

        final maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite || maxWidth <= 1 || text.isEmpty) return label;

        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: label,
        );
      },
    );
  }
}
