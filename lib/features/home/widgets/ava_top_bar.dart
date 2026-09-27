import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/ava_tokens.dart';

/// Бош саҳифанинг юқори қатори: «AVA» + ҳудуд тугмаси.
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
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(
            'AVA',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: c.brand,
            ),
          ),
          const SizedBox(width: 12),
          // Ҳудуд номи узун бўлса («Шайхонтоҳур, Тошкент шаҳри») логотипни
          // сиқиб қўймасин — тугма қолган жойни олади ва ичида қирқилади.
          Expanded(child: _RegionButton(onTap: onPickRegion)),
        ],
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
    return ValueListenableBuilder<int>(
      valueListenable: ServiceConfigHolder.revision,
      builder: (context, _, __) {
        final geo = ServiceConfigHolder.geoLabel.trim();
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
                        color: chosen ? c.brand : c.warn,
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
