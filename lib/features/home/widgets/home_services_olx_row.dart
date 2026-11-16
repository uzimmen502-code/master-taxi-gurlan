import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/ava_tokens.dart';
import '../home_module_gate.dart';
import 'service_spotlight_item.dart';

/// Бош саҳифадаги «Барча хизматларни кўриш» сарлавҳаси (эга, 2026-11-16).
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

  /// Сарлавҳа услуби: [AvaText.homeSectionTitle] (14 px), қалинроқ — w800 (эга, 2026-11-16).
  static final TextStyle titleStyle =
      AvaText.homeSectionTitle.copyWith(fontWeight: FontWeight.w800);

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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('home_all_services_header'),
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  context.tr('home_services_spotlight_title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HomeAllServicesHeader.titleStyle.copyWith(color: c.ink),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 22, color: c.ink),
            ],
          ),
        ),
      ),
    );
  }
}
