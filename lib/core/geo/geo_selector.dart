import 'package:flutter/material.dart';

import '../../repositories/service_config_repository.dart';
import '../brand_labels.dart';
import '../l10n/l10n_extension.dart';
import '../theme/app_theme.dart';
import '../widgets/service_area_picker.dart';
import 'geo_context.dart';
import 'geo_names.dart';

/// ID → қисқа номлар («Гурлан», «Хоразм»).
class GeoAreaResolver {
  GeoAreaResolver({ServiceConfigRepository? repo}) : _repo = repo ?? ServiceConfigRepository();

  final ServiceConfigRepository _repo;

  Future<GeoArea> resolve(String regionId, String districtId) async {
    var r = '';
    var d = '';
    try {
      if (regionId.isNotEmpty) {
        final region = await _repo.fetchRegion(regionId);
        if (region != null) GeoNames.remember(regions: [region]);
        r = region?.displayName.trim() ?? '';
      }
      if (districtId.isNotEmpty) {
        final district = await _repo.fetchDistrict(districtId);
        if (district != null) GeoNames.remember(districts: [district]);
        final raw = district?.displayName.trim() ?? '';
        d = raw.isEmpty ? '' : BrandLabels.shortDistrictName(raw);
      }
    } catch (e) {
      debugPrint('GeoAreaResolver: $e');
    }
    return GeoArea(regionId: regionId, districtId: districtId, regionLabel: r, districtLabel: d);
  }
}

/// Бош саҳифадаги ҳудуд тугмаси ойнаси (1-такомиллаштириш): фаол ҳудудни
/// танлайди, ПРОФИЛНИ ЎЗГАРТИРМАЙДИ. Яшаш жойи — алоҳида ҳавола орқали.
///
/// [current] — локациядан аниқланган туман (бўлмаса пункт кўринмайди).
Future<void> showGeoSelectorSheet(
  BuildContext context, {
  GeoArea? current,
  required Future<void> Function() onChangeHome,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final active = GeoContext.active;
      final home = GeoContext.home;
      // Ёрлиқлар фойдаланувчи тилида (сақланган кирилл — fallback).
      final lang = ctx.contentLang;
      Widget tile({
        required IconData icon,
        required String title,
        required String subtitle,
        required bool selected,
        required VoidCallback onTap,
        Key? key,
      }) =>
          ListTile(
            key: key,
            leading: Icon(icon, color: AppColors.primaryText),
            title: Text(title),
            subtitle: subtitle.isEmpty ? null : Text(subtitle),
            trailing: selected ? const Icon(Icons.check, color: AppColors.primaryText) : null,
            onTap: onTap,
          );
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(ctx.tr('geo_selector_title'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            if (current != null && !current.isEmpty)
              tile(
                key: const ValueKey('geo_opt_current'),
                icon: Icons.my_location,
                title: ctx.tr('geo_selector_current'),
                subtitle: GeoNames.area(current, lang),
                selected: active.sameAs(current) && GeoContext.activeSource == GeoAreaSource.location,
                onTap: () async {
                  Navigator.pop(ctx);
                  await GeoContext.setActive(current, GeoAreaSource.location);
                },
              ),
            tile(
              key: const ValueKey('geo_opt_home'),
              icon: Icons.home_outlined,
              title: ctx.tr('geo_selector_home'),
              subtitle: GeoNames.area(home, lang),
              selected: !GeoContext.isAway,
              onTap: () async {
                Navigator.pop(ctx);
                await GeoContext.resetToHome();
              },
            ),
            tile(
              key: const ValueKey('geo_opt_other'),
              icon: Icons.travel_explore,
              title: ctx.tr('geo_selector_other'),
              subtitle: GeoContext.isAway && GeoContext.activeSource == GeoAreaSource.manual
                  ? GeoNames.area(active, lang)
                  : '',
              selected: GeoContext.isAway && GeoContext.activeSource == GeoAreaSource.manual,
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await Navigator.of(context).push<GeoArea>(
                  MaterialPageRoute(builder: (_) => const GeoAreaPickScreen()),
                );
                if (picked != null) await GeoContext.setActive(picked, GeoAreaSource.manual);
              },
            ),
            const Divider(height: 1),
            TextButton.icon(
              key: const ValueKey('geo_change_home'),
              onPressed: () async {
                Navigator.pop(ctx);
                await onChangeHome();
              },
              icon: const Icon(Icons.edit_location_alt_outlined),
              label: Text(ctx.tr('geo_selector_change_home')),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// «Бошқа ҳудуд» — вилоят + туман танлаш; натижа [GeoArea] (профилга
/// ёзилмайди).
class GeoAreaPickScreen extends StatefulWidget {
  const GeoAreaPickScreen({super.key, this.resolver});

  final GeoAreaResolver? resolver;

  @override
  State<GeoAreaPickScreen> createState() => _GeoAreaPickScreenState();
}

class _GeoAreaPickScreenState extends State<GeoAreaPickScreen> {
  String _regionId = '';
  String _districtId = '';
  bool _busy = false;

  bool get _valid => _regionId.isNotEmpty && _districtId.isNotEmpty;

  Future<void> _apply() async {
    if (!_valid || _busy) return;
    setState(() => _busy = true);
    final area = await (widget.resolver ?? GeoAreaResolver()).resolve(_regionId, _districtId);
    if (!mounted) return;
    Navigator.of(context).pop(area);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('geo_pick_title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ServiceAreaPicker(
              showAreaDropdown: false,
              onChanged: (r, d, _) => setState(() {
                _regionId = r;
                _districtId = d;
              }),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _valid && !_busy ? _apply : null,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(context.tr('geo_pick_apply')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
