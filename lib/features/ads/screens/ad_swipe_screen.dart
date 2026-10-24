import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/edge_swipe_pager.dart';
import '../models/ad_model.dart';
import 'ad_details_screen.dart';

/// Аҳоли бозори эълонлари — СУРИБ кўриш (эга қарори, 2026-09-29:
/// «экранларни свайп қилиш»).
///
/// Йўналиш Улгуржи бозор билан БИР ХИЛ (эга қарори, 2026-10-17):
/// маълумот ТУГАГАНДАН кейин юқорига суринг = кейинги эълон, тепада пастга
/// суринг = олдинги. Тафсилот экрани ёруғ қолади.
///
/// `AdDetailsScreen` деярли ЎЗГАРТИРИЛМАДИ: у мураккаб экран (кўришлар ҳисоби,
/// «ўхшаш эълонлар», метрика) ва ҳар саҳифа ўз ҳолича, ўз `Scaffold`и
/// билан қурилади. Шунинг учун бу экран — устидаги юпқа қобиқ.
class AdSwipeScreen extends StatefulWidget {
  const AdSwipeScreen({
    super.key,
    required this.ads,
    required this.initialIndex,
  });

  /// Лентадаги эълонлар — сурилиш шулар орасида боради.
  final List<AdModel> ads;

  /// Босилган эълоннинг рўйхатдаги ўрни.
  final int initialIndex;

  @override
  State<AdSwipeScreen> createState() => _AdSwipeScreenState();
}

class _AdSwipeScreenState extends State<AdSwipeScreen> {
  late int _index;
  late final PageController _pager;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.ads.length - 1);
    _pager = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  /// Свайпга муқобил тугма (WCAG 2.5.7): олдинги/кейинги эълонга ўтиш.
  void _step(int delta) {
    final target = _index + delta;
    if (target < 0 || target >= widget.ads.length) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pager.jumpToPage(target);
      return;
    }
    _pager.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ads = widget.ads;
    // Битта эълон бўлса сурилишнинг маъноси йўқ — одатдаги экран.
    if (ads.length <= 1) {
      return AdDetailsScreen(ad: ads.isEmpty ? widget.ads.first : ads.first);
    }
    // Фон саҳифа ранги билан бир хил: судраганда саҳифа сал сурилади ва
    // орқасида қора чизиқ кўринмасин (қурилмада кўрилган).
    return ColoredBox(
      color: AppColors.scaffold,
      child: Stack(
        children: [
          // Свайп Улгуржи бозор билан БИР ХИЛ (эга қарори, 2026-10-17):
          // маълумот тугагандан кейин юқорига суринг = кейинги эълон, тепада
          // пастга суринг = олдинги ([EdgeSwipePager]). Аввал `reverse: true`
          // (пастга тортиш = кейинги) эди ва скроллли саҳифа билан тўқнашарди.
          EdgeSwipePager(
            itemCount: ads.length,
            initialIndex: _index,
            controller: _pager,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => AdDetailsScreen(
              // Калит бўлмаса Flutter саҳифа ҳолатини қайта ишлатиб
              // юборади — бир эълоннинг «ўхшашлари» бошқасида кўриниб
              // қолар эди.
              key: ValueKey(ads[i].id),
              ad: ads[i],
            ),
          ),
          // Нечанчи эълон эканини кўрсатиб туради — фойдаланувчи
          // лентанинг ичида эканини билсин.
          // Тепада ЎРТАДА: ўнг томонда AppBar'нинг «шикоят» иконкаси бор,
          // чап томонда — орқага тугмаси (счётчик иконка устига тушарди).
          // Икки томонида — олдинги/кейинги тугмаси: свайп ягона йўл
          // бўлмасин (экран ўқувчи ва тугма билан ишловчилар учун).
          Positioned(
            top: MediaQuery.of(context).padding.top + 4,
            left: 0,
            right: 0,
            child: Center(
              child: AdSwipeNav(
                index: _index,
                count: ads.length,
                onStep: _step,
              ),
            ),
          ),
          // Сурса бўлишини биринчи эълондагина айтамиз — кейин халақит
          // бермасин.
          if (_index == 0)
            Positioned(
              left: 0,
              right: 0,
              // «Қўнғироқ қилиш» панелидан ЮҚОРИДА (панел ≈ 68 px) — аввал
              // тугма устига чиқиб қоларди (қурилмада кўрилган, 2026-10-17).
              bottom: MediaQuery.of(context).padding.bottom + 80,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.keyboard_double_arrow_up_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          context.tr('product_swipe_next_up'),
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// «‹ 3 / 12 ›» — нечанчи эълон эканини кўрсатади ва свайпга муқобил:
/// олдинги/кейинги эълонга тугма билан ўтиш (WCAG 2.5.7, экран ўқувчи учун
/// ҳам). Чегарада тегишли тугма ўчиқ.
class AdSwipeNav extends StatelessWidget {
  const AdSwipeNav({
    super.key,
    required this.index,
    required this.count,
    required this.onStep,
  });

  final int index;
  final int count;

  /// -1 = олдинги, +1 = кейинги.
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const ValueKey('ad-swipe-prev'),
            tooltip: context.tr('ad_swipe_prev'),
            color: Colors.white,
            disabledColor: Colors.white38,
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: index > 0 ? () => onStep(-1) : null,
          ),
          Text(
            '${index + 1} / $count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: AppText.labelSmall,
              fontWeight: FontWeight.w700,
            ),
          ),
          IconButton(
            key: const ValueKey('ad-swipe-next'),
            tooltip: context.tr('ad_swipe_next'),
            color: Colors.white,
            disabledColor: Colors.white38,
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: index < count - 1 ? () => onStep(1) : null,
          ),
        ],
      ),
    );
  }
}