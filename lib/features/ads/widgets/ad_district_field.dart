import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/geo_area.dart';
import '../../../repositories/service_config_repository.dart';

/// Эълоннинг ҳудуди — МАҲСУЛОТ қаерда, сотувчи қаерда яшаши эмас.
///
/// НЕГА КЕРАК (аудит, 2026-09-27): илгари эълоннинг ҳудуди сотувчи
/// профилидан олинарди (`ownerGeoStamp`). Помидор сотилганда иккиси
/// устма-уст тушади, лекин УЙ, ЕР ёки МАШИНА сотилганда йўқ: Тошкентда
/// яшаб Хоразмдаги уйини сотаётган одамнинг эълони Тошкентга ёзиларди.
///
/// Оқибати фақат «нотўғри ёзув» эмас — ҚИДИРУВ бузилади: Хоразмдаги
/// харидор ўз туманидан уй қидирса, уни топа олмасди.
///
/// Шунинг учун ҳудуд энди ЭЪЛОННИКИ. Стандарт қиймат — сотувчининг ўз
/// тумани (10 ҳолатдан 9 тасида тўғри), лекин ўзгартириш мумкин.
class AdDistrictValue {
  const AdDistrictValue({
    required this.districtId,
    required this.regionId,
    required this.label,
  });

  final String districtId;
  final String regionId;

  /// Кўрсатиш учун тайёр ёзув: «Гурлан тумани, Хоразм».
  final String label;

  bool get isEmpty => districtId.trim().isEmpty;

  static const empty = AdDistrictValue(districtId: '', regionId: '', label: '');
}

class AdDistrictField extends StatelessWidget {
  const AdDistrictField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final AdDistrictValue value;
  final ValueChanged<AdDistrictValue> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final bosh = value.isEmpty;
    return InkWell(
      onTap: () async {
        final picked = await pickAdDistrict(context, current: value);
        if (picked != null) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(AvaRadius.card),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: context.tr('ad_district_label'),
          helperText: context.tr('ad_district_hint'),
          helperMaxLines: 2,
          prefixIcon: const Icon(Icons.place_outlined),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AvaRadius.card),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                bosh ? context.tr('ad_district_choose') : value.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: bosh ? c.ink3 : c.ink,
                  fontWeight: bosh ? FontWeight.w400 : FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down_rounded, color: c.ink2),
          ],
        ),
      ),
    );
  }
}

/// Вилоят → туман танлаш. Бекор қилинса `null`.
///
/// Икки босқич атайлаб: фойдаланувчи БОШҚА вилоятдаги мулкини сота
/// олиши керак, шунинг учун рўйхат ўз вилояти билан чекланмайди.
Future<AdDistrictValue?> pickAdDistrict(
  BuildContext context, {
  required AdDistrictValue current,
}) async {
  final repo = ServiceConfigRepository();
  final regions = await repo.fetchRegions();
  if (!context.mounted || regions.isEmpty) return null;

  final region = await showModalBottomSheet<GeoRegion>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _PickSheet<GeoRegion>(
      title: ctx.tr('ad_district_region'),
      items: regions,
      labelOf: (r) => r.displayName,
      selectedId: current.regionId,
      idOf: (r) => r.id,
    ),
  );
  if (region == null || !context.mounted) return null;

  final districts = await repo.fetchDistricts(region.id);
  if (!context.mounted || districts.isEmpty) return null;

  final district = await showModalBottomSheet<GeoDistrict>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _PickSheet<GeoDistrict>(
      title: ctx.tr('ad_district_label'),
      items: districts,
      labelOf: (d) => d.displayName,
      selectedId: current.districtId,
      idOf: (d) => d.id,
    ),
  );
  if (district == null) return null;

  return AdDistrictValue(
    districtId: district.id,
    regionId: region.id,
    label: '${district.displayName}, ${region.displayName}',
  );
}

class _PickSheet<T> extends StatelessWidget {
  const _PickSheet({
    required this.title,
    required this.items,
    required this.labelOf,
    required this.idOf,
    required this.selectedId,
  });

  final String title;
  final List<T> items;
  final String Function(T) labelOf;
  final String Function(T) idOf;
  final String selectedId;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                title,
                style: AvaText.sectionTitle.copyWith(color: c.ink),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final item = items[i];
                  final tanlangan = idOf(item) == selectedId;
                  return ListTile(
                    title: Text(labelOf(item)),
                    trailing: tanlangan
                        ? Icon(Icons.check_rounded, color: c.brand)
                        : null,
                    onTap: () => Navigator.pop(context, item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
