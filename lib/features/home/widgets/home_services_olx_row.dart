import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/ava_tokens.dart';
import '../home_module_gate.dart';
import 'service_spotlight_item.dart';

/// Бош саҳифадаги «Барча хизматлар ›» қатори (эга, 2026-11-16; 2026-11-27 — қидирув тагига,
/// «Бозорлар»дан олдин кўчирилди, ёзуви «Барча хизматлар», 16/600, стрелка билан).
///
/// Аввал бу ерда OLX услубидаги 2 қаторли доира плиткалар қатори (`HomeServicesOlxRow`)
/// турарди; эга қарори билан плиткалар бош саҳифадан олиб ташланди — хизматларга фақат
/// шу сарлавҳа орқали «Барча хизматлар» экранида ([AllServicesScreen]) кирилади.
/// Плиткалар у экранда сақланган.
///
/// Дарвоза: аввалгидек — [items] ичида [HomeModuleGate.showInGrid] бўйича биронта ҳам
/// кўринадиган хизмат бўлмаса, сарлавҳа ҳам чиқмайди. Админ модулни ёқиб/ўчирганда
/// ўзи янгиланади.
class HomeAllServicesHeader extends StatefulWidget {
  const HomeAllServicesHeader({
    super.key,
    required this.items,
    this.onTap,
  });

  final List<ServiceSpotlightItem> items;

  /// Босилса — «Барча хизматлар» экрани.
  final VoidCallback? onTap;

  /// Ёзув услуби — «енгил дизайн» карточка сарлавҳаси [AvaText.homeCardTitle] (16/600)
  /// (эга 2026-11-27; аввал 2026-11-16 да 14 px w800 эди).
  static const TextStyle titleStyle = AvaText.homeCardTitle;

  /// Қатор баландлиги (камида) — бармоқ билан босишга қулай.
  static const double minHeight = 48;

  @override
  State<HomeAllServicesHeader> createState() => _HomeAllServicesHeaderState();
}

class _HomeAllServicesHeaderState extends State<HomeAllServicesHeader> {
  VoidCallback? _configListener;

  @override
  void initState() {
    super.initState();
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
    final anyVisible =
        widget.items.any((e) => HomeModuleGate.showInGrid(e.gate));
    if (!anyVisible) return const SizedBox.shrink();

    // Эга 2026-11-27: қидирув тагида, «Бозорлар»дан олдин — аниқ кўринадиган тўлиқ энли
    // қатор (оқ фон, ингичка чегара, радиус 16 — «енгил дизайн» карточкаси каби), ўнгда стрелка.
    final radius = BorderRadius.circular(AvaRadius.card);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('home_all_services_header'),
        onTap: widget.onTap,
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minHeight: HomeAllServicesHeader.minHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('home_services_all_title'),
                    key: const ValueKey('home_all_services_title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        HomeAllServicesHeader.titleStyle.copyWith(color: c.ink),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  key: const ValueKey('home_all_services_chevron'),
                  size: 26,
                  color: c.ink,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
