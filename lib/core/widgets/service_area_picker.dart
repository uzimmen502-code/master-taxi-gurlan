import 'package:flutter/material.dart';

import '../../models/geo_area.dart';
import '../../repositories/service_config_repository.dart';
import '../theme/app_theme.dart';

/// Region → District → Service Area (MFY) kaskad tanlovi.
///
/// Configuration-driven platforma: foydalanuvchi zonasini tanlash uchun.
/// Har tanlovda [onChanged] chaqiriladi (bo'sh ID = tanlanmagan).
/// Ma'lumot topilmasa (offline yoki seed yo'q) — jimgina bo'sh qoladi,
/// hech narsani bloklamaydi.
class ServiceAreaPicker extends StatefulWidget {
  const ServiceAreaPicker({
    super.key,
    this.initialRegionId = '',
    this.initialDistrictId = '',
    this.initialServiceAreaId = '',
    required this.onChanged,
    this.repository,
    this.showAreaDropdown = true,
  });

  final String initialRegionId;
  final String initialDistrictId;
  final String initialServiceAreaId;

  /// `false` bo'lsa — MFY/zona dropdown ko'rsatilmaydi. Foydalanuvchi faqat
  /// Viloyat → Tuman tanlaydi; tumanning birlamchi zonasi avtomatik
  /// [onChanged] ga serviceAreaId sifatida beriladi.
  final bool showAreaDropdown;

  /// (regionId, districtId, serviceAreaId) — har biri bo'sh bo'lishi mumkin.
  final void Function(String regionId, String districtId, String serviceAreaId)
      onChanged;

  final ServiceConfigRepository? repository;

  @override
  State<ServiceAreaPicker> createState() => _ServiceAreaPickerState();
}

class _ServiceAreaPickerState extends State<ServiceAreaPicker> {
  late final ServiceConfigRepository _repo =
      widget.repository ?? ServiceConfigRepository();

  List<GeoRegion> _regions = const [];
  List<GeoDistrict> _districts = const [];
  List<ServiceArea> _areas = const [];

  String _regionId = '';
  String _districtId = '';
  String _areaId = '';

  bool _loadingRegions = true;
  bool _loadingDistricts = false;
  bool _loadingAreas = false;

  @override
  void initState() {
    super.initState();
    _regionId = widget.initialRegionId;
    _districtId = widget.initialDistrictId;
    _areaId = widget.initialServiceAreaId;
    _loadRegions();
  }

  Future<void> _loadRegions() async {
    final regions = await _repo.fetchRegions();
    if (!mounted) return;
    setState(() {
      _regions = regions;
      _loadingRegions = false;
      if (_regionId.isEmpty && regions.length == 1) {
        _regionId = regions.first.id;
      }
    });
    if (_regionId.isNotEmpty) await _loadDistricts(_regionId);
  }

  Future<void> _loadDistricts(String regionId) async {
    setState(() {
      _loadingDistricts = true;
      _districts = const [];
      _areas = const [];
    });
    final districts = await _repo.fetchDistricts(regionId);
    if (!mounted) return;
    setState(() {
      _districts = districts;
      _loadingDistricts = false;
      if (_districtId.isEmpty && districts.length == 1) {
        _districtId = districts.first.id;
      }
      if (!districts.any((d) => d.id == _districtId)) _districtId = '';
    });
    if (_districtId.isNotEmpty) await _loadAreas(_districtId);
    _emit();
  }

  Future<void> _loadAreas(String districtId) async {
    setState(() {
      _loadingAreas = true;
      _areas = const [];
    });
    final areas = await _repo.fetchServiceAreas(districtId);
    if (!mounted) return;
    setState(() {
      _areas = areas;
      _loadingAreas = false;
      if (widget.showAreaDropdown) {
        if (_areaId.isEmpty && areas.length == 1) _areaId = areas.first.id;
        if (!areas.any((a) => a.id == _areaId)) _areaId = '';
      } else {
        // Tuman darajasi: birlamchi (eng past order) zonani avto-tanlash.
        if (!areas.any((a) => a.id == _areaId)) {
          _areaId = areas.isNotEmpty ? areas.first.id : '';
        }
      }
    });
    _emit();
  }

  void _emit() => widget.onChanged(_regionId, _districtId, _areaId);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dropdown<GeoRegion>(
          label: 'Viloyat',
          icon: Icons.public,
          value: _regionId.isEmpty ? null : _regionId,
          loading: _loadingRegions,
          items: _regions,
          idOf: (r) => r.id,
          labelOf: (r) => r.displayName,
          onChanged: (id) {
            setState(() {
              _regionId = id ?? '';
              _districtId = '';
              _areaId = '';
            });
            if (_regionId.isNotEmpty) {
              _loadDistricts(_regionId);
            } else {
              _emit();
            }
          },
        ),
        const SizedBox(height: 12),
        _dropdown<GeoDistrict>(
          label: 'Tuman',
          icon: Icons.location_city,
          value: _districtId.isEmpty ? null : _districtId,
          loading: _loadingDistricts,
          items: _districts,
          idOf: (d) => d.id,
          labelOf: (d) => d.displayName,
          onChanged: (id) {
            setState(() {
              _districtId = id ?? '';
              _areaId = '';
            });
            if (_districtId.isNotEmpty) {
              _loadAreas(_districtId);
            } else {
              _emit();
            }
          },
        ),
        if (widget.showAreaDropdown) ...[
          const SizedBox(height: 12),
          _dropdown<ServiceArea>(
            label: 'Mahalla / xizmat zonasi',
            icon: Icons.holiday_village,
            value: _areaId.isEmpty ? null : _areaId,
            loading: _loadingAreas,
            items: _areas,
            idOf: (a) => a.id,
            labelOf: (a) => a.displayName,
            onChanged: (id) {
              setState(() => _areaId = id ?? '');
              _emit();
            },
          ),
        ],
      ],
    );
  }

  Widget _dropdown<T>({
    required String label,
    required IconData icon,
    required String? value,
    required bool loading,
    required List<T> items,
    required String Function(T) idOf,
    required String Function(T) labelOf,
    required ValueChanged<String?> onChanged,
  }) {
    final enabled = !loading && items.isNotEmpty;
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        prefixIcon: Icon(icon, size: 18, color: AppColors.primaryDark),
        suffixIcon: loading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: AppColors.primaryDark, width: 1.5),
        ),
      ),
      hint: Text(
        loading ? 'Yuklanmoqda...' : '—',
        style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
      ),
      items: [
        for (final it in items)
          DropdownMenuItem(
            value: idOf(it),
            child: Text(labelOf(it), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}
