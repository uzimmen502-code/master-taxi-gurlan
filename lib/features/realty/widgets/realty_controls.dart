import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/realty_listing.dart';
import '../realty_tabs.dart';

/// «Кўчмас мулк» бўлимининг УМУМИЙ бошқарув элементлари.
///
/// Нега алоҳида файл: буларнинг ҳар бири камида иккита экранда
/// ишлатилади. Аввал улар `screens/realty_map_screen.dart` ичида
/// турар эди ва лента экрани виджет олиш учун ЭКРАН файлини import
/// қилар эди — боғламалар чалкашиб, «харита экранини ўзгартирсам
/// лента нега бузилди?» деган савол туғилар эди.

/// Танлов тугмаси — ОДДИЙ/РЕКЛАМА/СРОЧНО, Сотиш/Ижара, муддат ва ҳ.к.
///
/// Эълон қўшиш экранида ва тариф варағида бир хил кўринади: аввал
/// иккита файлда иккита нусха бор эди (бир хил радиус, ҳошия, ранг ва
/// матн стили), шунинг учун биттасини ўзгартирганда иккинчиси орқада
/// қолар эди.
///
/// [onTap] `null` бўлса тугма ўчиқ — ярим шаффоф бўлиб, босилмайди.
/// [sub] — иккинчи қатор (масалан нарх).
class RealtyChoice extends StatelessWidget {
  const RealtyChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.sub,
    this.color,
  });

  final String label;
  final String? sub;
  final bool selected;
  final VoidCallback? onTap;

  /// Танланганда тўлдириш ранги; берилмаса бренд ранги.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final active = color ?? c.brand;
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? active : c.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? active : c.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppText.bodySmall,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : c.ink2,
                ),
              ),
              if (sub != null)
                Text(
                  sub!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppText.labelTiny,
                    color: selected ? Colors.white70 : c.ink3,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Эълоннинг даражасини кўрсатадиган ёрлиқ (ўқиш учун).
class RealtyTierBadge extends StatelessWidget {
  const RealtyTierBadge({super.key, required this.tier});

  final RealtyTier tier;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: RealtyTabs.colorFor(tier),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        context.tr(RealtyTabs.labelKey(tier)),
        style: const TextStyle(
          fontSize: AppText.labelTiny,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// «Эълон қўшиш» — матнсиз, доира ичида, сарлавҳа қаторининг ўнг
/// бурчагида (эга қарори, 2026-09-28). Аввал сузувчи кенг тугма эди ва
/// пастдаги харитани доим ёпиб турарди.
class RealtyAddButton extends StatelessWidget {
  const RealtyAddButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.only(right: 8, left: 4),
      child: Tooltip(
        message: context.tr('realty_add_cta'),
        child: Material(
          color: c.brandInk,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(Icons.add_home_outlined, size: 20, color: c.brand),
            ),
          ),
        ),
      ),
    );
  }
}

/// Сотиш / Ижара филтри — лента ва харита экранларида бир хил.
class RealtyDealFilter extends StatelessWidget {
  const RealtyDealFilter({
    super.key,
    required this.deal,
    required this.onChanged,
  });

  final RealtyDeal? deal;
  final ValueChanged<RealtyDeal?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    Widget chip(String labelKey, RealtyDeal? value) {
      final selected = deal == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(context.tr(labelKey)),
          selected: selected,
          onSelected: (_) => onChanged(value),
          labelStyle: TextStyle(
            fontSize: AppText.bodySmall,
            fontWeight: FontWeight.w600,
            color: selected ? c.brandInk : c.ink2,
          ),
          selectedColor: c.brand,
          backgroundColor: c.chip,
          side: BorderSide(color: c.line),
          showCheckmark: false,
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      color: c.bg,
      child: Row(
        children: [
          chip('realty_deal_all', null),
          chip('realty_deal_sale', RealtyDeal.sale),
          chip('realty_deal_rent', RealtyDeal.rent),
        ],
      ),
    );
  }
}

/// Харита легендаси — ранг маъноси ва «нуқталар тахминий» огоҳлантириши.
class RealtyMapLegend extends StatelessWidget {
  const RealtyMapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      // `Wrap` — аввал бу `Row` эди ва ичида `Spacer` билан бирга
      // `Expanded` турар эди: тор экранда доимий оверфлоу хавфи бор
      // қурилиш. Энди элементлар керак бўлса кейинги қаторга ўтади.
      child: Wrap(
        alignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final tier in RealtyTabs.order)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: RealtyTabs.colorFor(tier),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  context.tr(RealtyTabs.labelKey(tier)),
                  style: TextStyle(
                    fontSize: AppText.labelTiny,
                    color: c.ink2,
                  ),
                ),
              ],
            ),
          Text(
            context.tr('realty_map_approx_hint'),
            style: TextStyle(fontSize: AppText.labelTiny, color: c.ink3),
          ),
        ],
      ),
    );
  }
}
