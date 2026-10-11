// Сотувчининг ЖЎНАТИШ МАНЗИЛИ формаси (У1, 2026-10-09) — рўйхатдан ўтишда
// ва кейин («Менинг маҳсулотларим» баннери) бир хил виджет.
//
// Вилоят/туман — `geo_regions`/`geo_districts` (логистика формаси билан
// бир хил манба, `ServiceConfigRepository`); етказиш ҳақи зонаси туман
// бўйича аниқланади, шунинг учун иккаласи мажбурий. Манзил матни — курьер
// олиб кетиши учун. Координата ихтиёрий (GPS тугмаси).

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../models/geo_area.dart';
import '../../../repositories/service_config_repository.dart';
import '../../../services/location_service.dart';

/// Форма қиймати — соф, Firestore'сиз (тест учун).
class ShipFromDraft {
  const ShipFromDraft({
    this.regionId = '',
    this.districtId = '',
    this.address = '',
    this.lat,
    this.lng,
  });

  final String regionId;
  final String districtId;
  final String address;
  final double? lat;
  final double? lng;

  ShipFromDraft copyWith({
    String? regionId,
    String? districtId,
    String? address,
    double? lat,
    double? lng,
    bool clearCoords = false,
  }) =>
      ShipFromDraft(
        regionId: regionId ?? this.regionId,
        districtId: districtId ?? this.districtId,
        address: address ?? this.address,
        lat: clearCoords ? null : (lat ?? this.lat),
        lng: clearCoords ? null : (lng ?? this.lng),
      );

  /// Хато калити ёки `null` (тўғри). Вилоят + туман + манзил (≥5) шарт.
  String? validate() {
    if (regionId.trim().isEmpty) return 'wholesale_err_region_required';
    if (districtId.trim().isEmpty) return 'wholesale_err_district_required';
    if (address.trim().length < 5) return 'wholesale_err_address_required';
    if (address.trim().length > 300) return 'wholesale_err_address_required';
    return null;
  }
}

class ShipFromFields extends StatefulWidget {
  const ShipFromFields({
    super.key,
    required this.value,
    required this.onChanged,
    this.geoRepository,
    this.locate,
  });

  final ShipFromDraft value;
  final ValueChanged<ShipFromDraft> onChanged;
  final ServiceConfigRepository? geoRepository;

  /// Тестда алмаштириш учун; стандарт — GPS.
  final Future<({double lat, double lng})?> Function()? locate;

  @override
  State<ShipFromFields> createState() => _ShipFromFieldsState();
}

class _ShipFromFieldsState extends State<ShipFromFields> {
  late final ServiceConfigRepository _geo = widget.geoRepository ?? ServiceConfigRepository();
  List<GeoRegion> _regions = const [];
  final Map<String, List<GeoDistrict>> _districts = {};
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final regions = await _geo.fetchRegions();
    if (!mounted) return;
    setState(() => _regions = regions);
    if (widget.value.regionId.isNotEmpty) await _ensureDistricts(widget.value.regionId);
  }

  Future<void> _ensureDistricts(String regionId) async {
    if (regionId.isEmpty || _districts.containsKey(regionId)) return;
    final list = await _geo.fetchDistricts(regionId);
    if (mounted) setState(() => _districts[regionId] = list);
  }

  Future<void> _locateMe() async {
    setState(() => _locating = true);
    try {
      ({double lat, double lng})? p;
      if (widget.locate != null) {
        p = await widget.locate!();
      } else {
        final c = await const LocationService().getCurrentCoords();
        p = (lat: c.lat, lng: c.lng);
      }
      if (!mounted) return;
      if (p == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('wholesale_locate_failed'))),
        );
        return;
      }
      widget.onChanged(widget.value.copyWith(lat: p.lat, lng: p.lng));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('wholesale_locate_failed'))),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final districts = _districts[v.regionId] ?? const <GeoDistrict>[];
    final regionValue = _regions.any((r) => r.id == v.regionId) ? v.regionId : null;
    final districtValue = districts.any((d) => d.id == v.districtId) ? v.districtId : null;
    InputDecoration deco(String key) =>
        InputDecoration(labelText: context.tr(key), border: const OutlineInputBorder(), isDense: true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('wholesale_ship_from_title'), style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(context.tr('wholesale_ship_from_help'), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: ValueKey('ship-region-${_regions.length}-$regionValue'),
          initialValue: regionValue,
          decoration: deco('logistics_region'),
          items: [for (final r in _regions) DropdownMenuItem(value: r.id, child: Text(r.nameFor(context.contentLang)))],
          onChanged: (id) {
            final rid = id ?? '';
            widget.onChanged(v.copyWith(regionId: rid, districtId: ''));
            _ensureDistricts(rid);
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('ship-district-${v.regionId}-${districts.length}-$districtValue'),
          initialValue: districtValue,
          decoration: deco('logistics_district'),
          items: [for (final d in districts) DropdownMenuItem(value: d.id, child: Text(d.nameFor(context.contentLang)))],
          onChanged: v.regionId.isEmpty ? null : (id) => widget.onChanged(v.copyWith(districtId: id ?? '')),
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: v.address,
          maxLength: 300,
          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
          decoration: deco('wholesale_field_ship_address'),
          onChanged: (s) => widget.onChanged(v.copyWith(address: s)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          OutlinedButton.icon(
            onPressed: _locating ? null : _locateMe,
            icon: _locating
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location, size: 18),
            label: Text(context.tr('wholesale_locate_me')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              v.lat != null && v.lng != null
                  ? context.tr('wholesale_location_set')
                  : context.tr('wholesale_location_optional'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        ]),
      ],
    );
  }
}

/// Стандарт қиймат — илова ҳозир қайси ҳудудда бўлса (сотувчи кўпинча ўз
/// туманида рўйхатдан ўтади); ўзгартириш мумкин.
ShipFromDraft shipFromDraftFromCurrentArea() => ShipFromDraft(
      regionId: ServiceConfigHolder.regionId,
      districtId: ServiceConfigHolder.districtId,
    );
