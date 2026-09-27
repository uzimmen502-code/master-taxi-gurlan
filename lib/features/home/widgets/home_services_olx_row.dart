import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/ava_tokens.dart';
import '../home_module_gate.dart';
import 'service_circle_tile.dart';
import 'services_spotlight_carousel.dart' show ServiceSpotlightItem;

/// Бош саҳифадаги хизматлар блоки — OLX'нинг «Разделы на сервисе OLX»
/// жойлашуви: **2 қатор, ёнга скролл**.
///
/// olx.uz дан 2026-09-26 да ЖОНЛИ ўлчанган (мобил 375px, DOM):
/// ```
/// display: grid;  grid-auto-flow: row;
/// grid-template-rows: 196px 0px 216px;      // 2 қатор, оралиқ 0
/// grid-template-columns: 100px 131.6px 100px 117px 100px …  // 9 устун
/// ```
/// 13 та банд шундай жойлашган: **1–9 юқори қаторда, 10–13 пастда** —
/// яъни тўлдириш УСТУН бўйлаб эмас, ҚАТОР бўйлаб; устунлар иккала
/// қаторда бир хил `x` да турибди.
///
/// ФАРҚ (атайлаб): OLX устун энини ёрлиқ матнига қараб ўстиради
/// (камида 100px). Бизда ёзув ўзбекча ва катта ҳарфли — «ШАҲАРЛАРАРО
/// ТАКСИ» каби, узунлиги жуда ҳар хил. Шунинг учун устун эни ҚАТЪИЙ
/// ([_colWidth]): шунда иккала қатор аниқ бир-бирининг остига тушади
/// ва узун ёзув 3 қаторга ўралади — OLX'да ҳам ёзув 3 қаторгача
/// ўралади («Хобби, отдых и спорт»).
///
/// Автоматик айланиш ЙЎҚ — OLX'да ҳам йўқ, бу оддий скролл.
class HomeServicesOlxRow extends StatefulWidget {
  const HomeServicesOlxRow({
    super.key,
    required this.items,
    this.onTitleTap,
  });

  final List<ServiceSpotlightItem> items;

  /// Сарлавҳа босилса — «Барча хизматлар» экрани.
  final VoidCallback? onTitleTap;

  /// Устун эни. Доира 20% кичрайгандан кейин ҳам ЎЗГАРМАДИ: ёрлиқ
  /// («ШАҲАРЛАРАРО ТАКСИ») сиғиши учун кенглик керак, доиранинг ёнидаги
  /// ҳаво эса зарар қилмайди — OLX'да ҳам доира устун энидан кичик
  /// (88 доира / 100–132 устун).
  static const double _colWidth = 104;

  /// Қаторлар оралиғи — **0** (эга қарори, 2026-09-27: «қаторлар орасини
  /// максимал қисқартир»). OLX'нинг ўзида ҳам 0 (`grid-template-rows:
  /// 196px 0px 216px`).
  ///
  /// Олдин 6px заҳира бор эди, чунки ёзув 3 қаторга чиқиши мумкин деб
  /// ҳисобланган. Ёрлиқ шрифти 2 баробар кичрайгач бу заҳира керак
  /// бўлмай қолди: ўралиш ўрни катакнинг ўз ичида
  /// ([ServiceCircleTile.tileHeight]) ҳисобга олинган.
  static const double _rowGap = 0;

  @override
  State<HomeServicesOlxRow> createState() => _HomeServicesOlxRowState();
}

class _HomeServicesOlxRowState extends State<HomeServicesOlxRow> {
  VoidCallback? _configListener;

  @override
  void initState() {
    super.initState();
    // Админ модулни ёқиб/ўчирганда қатор ўзи янгиланади.
    _configListener = () {
      if (mounted) setState(() {});
    };
    ServiceConfigHolder.revision.addListener(_configListener!);
  }

  @override
  void dispose() {
    if (_configListener != null) {
      ServiceConfigHolder.revision.removeListener(_configListener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final visible = widget.items
        .where((e) => HomeModuleGate.showInGrid(e.moduleId))
        .toList(growable: false);
    if (visible.isEmpty) return const SizedBox.shrink();

    // ҚАТОР бўйлаб тўлдириш: биринчи ярми юқорида, қолгани пастда.
    final cols = (visible.length + 1) ~/ 2;
    final top = visible.take(cols).toList(growable: false);
    final bottom = visible.skip(cols).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTitleTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.tr('home_services_spotlight_title'),
                    style: AvaText.sectionTitle.copyWith(color: c.ink),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 22, color: c.ink),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AvaSpace.sectionHeaderGap),
        SizedBox(
          height: ServiceCircleTile.tileHeight * 2 +
              HomeServicesOlxRow._rowGap,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Row(items: top),
                const SizedBox(height: HomeServicesOlxRow._rowGap),
                _Row(items: bottom),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.items});

  final List<ServiceSpotlightItem> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ServiceCircleTile.tileHeight,
      child: Row(
        children: [
          for (final item in items)
            SizedBox(
              width: HomeServicesOlxRow._colWidth,
              child: ServiceCircleTile(item: item),
            ),
        ],
      ),
    );
  }
}
