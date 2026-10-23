import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import 'ava_section.dart';

/// Бош саҳифа бўлими «Яқин атрофдаги бизнеслар» (B-7). Маълумот ЮКЛАМАЙДИ: бош саҳифа ҳар очилишида
/// Firestore ўқиши бўлмасин (37-банд) — харита ўзи фақат босилганда ўқийди.
/// Дарвоза: `business_map` модули (`HomeModuleGate.showInGrid`).
class HomeBusinessSection extends StatelessWidget {
  const HomeBusinessSection({super.key, required this.onOpenMap, required this.onAddMine});

  final VoidCallback onOpenMap;
  final VoidCallback onAddMine;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return AvaSection(
      moduleId: 'business_map',
      title: context.tr('bizmap_home_title'),
      status: AvaSectionStatus.ready,
      onSeeAll: onOpenMap,
      child: InkWell(
        onTap: onOpenMap,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AvaRadius.card),
            border: Border.all(color: c.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.map_rounded, color: c.brand, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(context.tr('bizmap_home_sub'), style: AvaText.caption.copyWith(color: c.ink3)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: onOpenMap,
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: Text(context.tr('bizmap_open_map')),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: onAddMine,
                    child: Text(context.tr('bizmap_add_mine')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
