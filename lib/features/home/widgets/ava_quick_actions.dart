import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';

/// Битта ўтиш катаги.
class AvaQuickAction {
  const AvaQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// «Барча хизматлар» — бренд фонида ажралиб туради.
  final bool highlighted;
}

/// 1-бўлим: асосий ўтишлар.
///
/// Эски «Маҳсулотлар карусели» ва «Хизматлар — танланг» карусели
/// ўрнига келди: айланмайди, ўз-ўзидан ҳаракатланмайди, ҳар катак
/// битта аниқ ўтиш. Тор экранда ёнга сурилади.
class AvaQuickActions extends StatelessWidget {
  const AvaQuickActions({super.key, required this.actions});

  final List<AvaQuickAction> actions;

  static const _tileWidth = 76.0;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++)
            Padding(
              padding: EdgeInsets.only(
                right: i == actions.length - 1 ? 0 : 8,
              ),
              child: _Tile(action: actions[i], width: _tileWidth),
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.action, required this.width});

  final AvaQuickAction action;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final bg = action.highlighted ? c.accentLime : c.surface;
    final fg = action.highlighted ? c.accentLimeInk : c.accentLimeIcon;
    final labelColor = c.ink;

    return Semantics(
      button: true,
      label: action.label,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        child: Container(
          width: width,
          // Шрифт 130% гача катталашса катак ўсади, ёрлиқ қирқилмайди.
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AvaRadius.card),
            border: Border.all(
              color: action.highlighted ? c.accentLime : c.line,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(action.icon, size: 24, color: fg),
              const SizedBox(height: 6),
              Text(
                action.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AvaText.caption.copyWith(color: labelColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Бош саҳифадаги стандарт ўтишлар рўйхати.
///
/// Модул кўринмаса (`HomeModuleGate`) катак ҳам чиқмайди — филтрлаш
/// чақирувчида, чунки бу виджет модул тизимига боғлиқ эмас.
List<AvaQuickAction> defaultQuickActions(
  BuildContext context, {
  required VoidCallback onOpenAll,
  required VoidCallback onTaxi,
  required VoidCallback onIntercity,
  required VoidCallback onMarket,
  required VoidCallback onAssistant,
  required VoidCallback onAvagram,
}) {
  return [
    AvaQuickAction(
      icon: Icons.apps_rounded,
      label: context.tr('home_services_all_title'),
      onTap: onOpenAll,
      highlighted: true,
    ),
    AvaQuickAction(
      icon: Icons.local_taxi_rounded,
      label: context.tr('home_module_local'),
      onTap: onTaxi,
    ),
    AvaQuickAction(
      icon: Icons.alt_route_rounded,
      label: context.tr('home_module_intercity'),
      onTap: onIntercity,
    ),
    AvaQuickAction(
      icon: Icons.storefront_rounded,
      label: context.tr('home_module_cheap_products'),
      onTap: onMarket,
    ),
    AvaQuickAction(
      icon: Icons.auto_awesome_rounded,
      label: context.tr('home_module_chatgpt'),
      onTap: onAssistant,
    ),
    AvaQuickAction(
      icon: Icons.play_circle_fill_rounded,
      label: context.tr('home_module_tv_market'),
      onTap: onAvagram,
    ),
  ];
}
