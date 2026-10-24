// Меню категорияларига ўтиш (2026-10-24, UI/UX): оз категорияда — юқоридаги чиплар, кўпида — чап рейл.
//
// Нега: 2 категорияли менюда 96 dp рейл экран кенглигининг ¼ қисмини ер эди, таом номига ≈118 dp қоларди
// ва «Ширинликлар» сўзи ўртасидан бўлинарди. Чиплар тўлиқ кенгликни қайтаради; 4+ категорияда рейл (左右联动,
// §12.4) ўзгармайди — фақат сўз сиғмаса шрифт кичраяди.

import 'package:flutter/material.dart';

import '../../../core/theme/ava_tokens.dart';

/// Категорияларга ўтиш шакли.
enum MenuNavMode {
  /// Битта категория — ўтишга жой йўқ (сарлавҳанинг ўзи кифоя).
  none,

  /// 2…[kMenuChipsMaxSections] категория — юқорида чиплар.
  chips,

  /// Кўпроқ — чап рейл.
  rail,
}

/// Чиплар кўрсатиладиган энг кўп категория сони.
const int kMenuChipsMaxSections = 3;

/// Чап рейл кенглиги (96 → 104, эга тасдиғи 2026-10-24).
const double kMenuRailWidth = 104;

MenuNavMode menuNavModeFor(int sectionCount) {
  if (sectionCount <= 1) return MenuNavMode.none;
  return sectionCount <= kMenuChipsMaxSections ? MenuNavMode.chips : MenuNavMode.rail;
}

/// [name] даги ЭНГ УЗУН СЎЗ [maxWidth] га сиғадиган шрифт ўлчами ([base]дан [min]гача, 0.5 қадам билан).
///
/// Нега: `Text` битта узун сўзни сиғмаса ҳарф ўртасидан бўлади («Ширинликл / ар»). Сўзлар орасидан
/// ўралиш яхши, шунинг учун фақат энг узун сўз ўлчанади. [min] да ҳам сиғмаса — [min] қайтади
/// (қолганини `ellipsis` ушлайди).
double fitCategoryFontSize({
  required String name,
  required double maxWidth,
  required TextScaler scaler,
  TextDirection direction = TextDirection.ltr,
  double base = 12.5,
  double min = 10.5,
  FontWeight weight = FontWeight.w700,

  /// Амалда чизиладиган шрифт оиласи/ҳарф ораси (Theme.textTheme): ўлчаш ва чизиш БИР хил бўлсин —
  /// акс ҳолда тор шрифтда ўлчаб, кенг шрифтда («Inter») чизилади ва сўз барибир бўлинади.
  TextStyle? baseStyle,
}) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty || !maxWidth.isFinite || maxWidth <= 0) return base;
  final longest = words.reduce((a, b) => a.length >= b.length ? a : b);
  var size = base;
  while (size > min) {
    final p = TextPainter(
      text: TextSpan(text: longest, style: (baseStyle ?? const TextStyle()).copyWith(fontSize: size, fontWeight: weight)),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final fits = p.width <= maxWidth;
    p.dispose();
    if (fits) return size;
    size -= 0.5;
  }
  return min;
}

/// Чап рейлдаги битта категория.
class MenuCategoryTile extends StatelessWidget {
  const MenuCategoryTile({
    super.key,
    required this.name,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final String name;
  final bool selected;

  /// Шу категориядан саватдаги таомлар сони (0 — белги йўқ).
  final int badge;
  final VoidCallback onTap;

  static const double _padH = 8;
  static const double _border = 3;
  static const double _badgeW = 22;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final weight = selected ? FontWeight.w700 : FontWeight.w500;
    return Semantics(
      button: true,
      selected: selected,
      label: badge > 0 ? '$name, $badge' : name,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: selected ? c.surface : Colors.transparent,
              border: Border(left: BorderSide(color: selected ? c.brand : Colors.transparent, width: _border)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: _padH, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: fitCategoryFontSize(
                          name: name,
                          maxWidth: box.maxWidth,
                          scaler: MediaQuery.textScalerOf(context),
                          direction: Directionality.of(context),
                          weight: weight,
                          baseStyle: Theme.of(context).textTheme.bodyMedium,
                        ),
                        fontWeight: weight,
                        color: selected ? c.ink : c.ink2,
                      ),
                    ),
                  ),
                ),
                if (badge > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: _badgeW - 6),
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: c.brand, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      '$badge',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.brandInk),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Юқоридаги категория чиплари (2…3 категория). Фаол чип кўринмай қолса (катта шрифт) ўзи суриб келтирилади.
class MenuCategoryChips extends StatefulWidget {
  const MenuCategoryChips({
    super.key,
    required this.names,
    required this.badges,
    required this.active,
    required this.onTap,
  });

  final List<String> names;

  /// Ҳар категория учун саватдаги таомлар сони ([names] билан бир хил узунликда).
  final List<int> badges;
  final int active;
  final void Function(int index) onTap;

  /// Чипнинг кўриниши 36, босиш майдони 44 (AvaTap.minSize).
  static const double barHeight = 52;

  @override
  State<MenuCategoryChips> createState() => _MenuCategoryChipsState();
}

class _MenuCategoryChipsState extends State<MenuCategoryChips> {
  late List<GlobalKey> _keys = [for (final _ in widget.names) GlobalKey()];

  @override
  void didUpdateWidget(MenuCategoryChips old) {
    super.didUpdateWidget(old);
    if (_keys.length != widget.names.length) {
      _keys = [for (final _ in widget.names) GlobalKey()];
    }
    if (old.active != widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.active >= _keys.length) return;
        final ctx = _keys[widget.active].currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 180), alignment: 0.5);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      height: MenuCategoryChips.barHeight,
      decoration: BoxDecoration(color: c.surface, border: Border(bottom: BorderSide(color: c.line))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            for (var i = 0; i < widget.names.length; i++)
              _Chip(
                key: _keys[i],
                chipKey: ValueKey('menu-chip-$i'),
                name: widget.names[i],
                badge: i < widget.badges.length ? widget.badges[i] : 0,
                selected: i == widget.active,
                onTap: () => widget.onTap(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.chipKey,
    required this.name,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  final Key chipKey;
  final String name;
  final int badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Semantics(
      button: true,
      selected: selected,
      label: badge > 0 ? '$name, $badge' : name,
      child: ExcludeSemantics(
        child: InkWell(
          key: chipKey,
          onTap: onTap,
          borderRadius: BorderRadius.circular(AvaRadius.chip),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AvaTap.minSize),
            child: Center(
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: selected ? c.brand : c.surface,
                  borderRadius: BorderRadius.circular(AvaRadius.chip),
                  border: Border.all(color: selected ? c.brand : c.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? c.brandInk : c.ink,
                      ),
                    ),
                    if (badge > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(9)),
                        child: Text(
                          '$badge',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c.surface),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
