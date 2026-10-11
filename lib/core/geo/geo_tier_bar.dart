import 'package:flutter/material.dart';

import '../l10n/l10n_extension.dart';
import 'geo_context.dart';
import 'geo_names.dart';
import 'geo_selector.dart';
import 'module_geo_policy.dart';

/// «Туман · Вилоят бўйича · Бутун Ўзбекистон» тугмалари (2-такомиллаштириш)
/// + «Бошқа ҳудуд» (модулда атайлаб танланган ҳудуд — сақланади).
///
/// Танлов [GeoContext.setScope] орқали — модул қоидасига кўра сақланади
/// ёки йўқ (Улгуржи, D-GEO-10).
class GeoTierBar extends StatelessWidget {
  const GeoTierBar({
    super.key,
    required this.moduleId,
    required this.scope,
    required this.onChanged,
    this.showOtherArea = true,
  });

  final String moduleId;
  final GeoScope scope;
  final ValueChanged<GeoScope> onChanged;
  final bool showOtherArea;

  String _label(BuildContext context, GeoLevel l) {
    switch (l) {
      case GeoLevel.district:
        final d = GeoNames.district(scope.area.districtId, context.contentLang,
                fallback: scope.area.districtLabel)
            .trim();
        return d.isEmpty ? context.tr('geo_level_district') : d;
      case GeoLevel.region:
        final r = GeoNames.region(scope.area.regionId, context.contentLang,
                fallback: scope.area.regionLabel)
            .trim();
        return r.isEmpty ? context.tr('geo_level_region') : r;
      case GeoLevel.nation:
        return context.tr('geo_level_nation');
    }
  }

  Future<void> _pickOther(BuildContext context) async {
    final picked = await Navigator.of(context).push<GeoArea>(
      MaterialPageRoute(builder: (_) => const GeoAreaPickScreen()),
    );
    if (picked == null) return;
    final level = scope.level == GeoLevel.nation ? GeoLevel.district : scope.level;
    final next = GeoScope(level: level, area: picked, pinned: true);
    await GeoContext.setScope(moduleId, next);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        // Тилли ном фонда келгач қайта чизиш.
        valueListenable: GeoNames.revision,
        builder: (context, _, __) => _build(context),
      );

  Widget _build(BuildContext context) {
    final policy = geoPolicyFor(moduleId);
    if (policy.levels.length < 2) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          for (final l in policy.levels) ...[
            ChoiceChip(
              key: ValueKey('geo_tier_${l.name}'),
              avatar: Icon(
                l == GeoLevel.nation ? Icons.public : Icons.place_outlined,
                size: 16,
              ),
              label: Text(_label(context, l)),
              selected: scope.level == l,
              onSelected: (_) async {
                if (scope.level == l) return;
                final next = scope.copyWith(level: l);
                await GeoContext.setScope(moduleId, next);
                onChanged(next);
              },
            ),
            const SizedBox(width: 8),
          ],
          if (showOtherArea)
            ActionChip(
              key: const ValueKey('geo_tier_other'),
              avatar: const Icon(Icons.travel_explore, size: 16),
              label: Text(context.tr('geo_other_area')),
              onPressed: () => _pickOther(context),
            ),
        ],
      ),
    );
  }
}

/// Натижа кам бўлганда кенгроқ ҳудудга таклиф (2-такомиллаштириш):
/// автоматик ўтиб кетмайди — фойдаланувчи танлайди.
class GeoWiderHint extends StatelessWidget {
  const GeoWiderHint({
    super.key,
    required this.moduleId,
    required this.scope,
    required this.onChanged,
  });

  final String moduleId;
  final GeoScope scope;
  final ValueChanged<GeoScope> onChanged;

  @override
  Widget build(BuildContext context) {
    final levels = geoPolicyFor(moduleId).levels;
    final idx = levels.indexOf(scope.level);
    if (idx < 0 || idx >= levels.length - 1) return const SizedBox.shrink();
    final wider = levels.sublist(idx + 1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Text(context.tr('geo_few_results'), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final l in wider)
                OutlinedButton(
                  key: ValueKey('geo_wider_${l.name}'),
                  onPressed: () async {
                    final next = scope.copyWith(level: l);
                    await GeoContext.setScope(moduleId, next);
                    onChanged(next);
                  },
                  child: Text(context.tr(
                      l == GeoLevel.region ? 'geo_show_region' : 'geo_show_nation')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
