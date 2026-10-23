import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/geo/location_area_service.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/map_picker_result.dart';
import '../../map_picker/screens/map_picker_screen.dart';
import '../data/business_repository.dart';
import '../domain/business.dart';
import '../domain/business_category.dart';

/// Эга ўз объектини қўшади/таҳрирлайди (B-1). Жойни мавжуд [MapPickerScreen] билан белгилайди (B-5).
/// Ҳамма текширув серверда (`upsertMyBusiness`); бу ерда фақат тез инкор ва тушунарли хато матни.
class BusinessFormScreen extends StatefulWidget {
  const BusinessFormScreen({super.key, this.existing, BusinessRepository? repository})
      : _repo = repository;

  final Business? existing;
  final BusinessRepository? _repo;

  @override
  State<BusinessFormScreen> createState() => _BusinessFormScreenState();
}

class _BusinessFormScreenState extends State<BusinessFormScreen> {
  late final BusinessRepository _repo = widget._repo ?? BusinessRepository();

  late final TextEditingController _name;
  late final TextEditingController _subtype;
  late final TextEditingController _description;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _hours;
  late final TextEditingController _website;

  BusinessCategory? _category;
  double? _lat;
  double? _lng;
  String _regionId = '';
  String _districtId = '';
  bool _busy = false;
  String? _error;

  /// Бир форма = бир калит: «Сақлаш» икки марта босилса ҳам битта объект (21-банд).
  final String _requestId = 'b${DateTime.now().microsecondsSinceEpoch}';

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    _name = TextEditingController(text: b?.name ?? '');
    _subtype = TextEditingController(text: b?.subtype ?? '');
    _description = TextEditingController(text: b?.description ?? '');
    _phone = TextEditingController(
        text: b?.phone ?? canonicalPhoneId(FirebaseAuth.instance.currentUser?.phoneNumber ?? ''));
    _address = TextEditingController(text: b?.address ?? '');
    _hours = TextEditingController(text: b?.openingHours ?? '');
    _website = TextEditingController(text: b?.website ?? '');
    _category = b?.category;
    _lat = b?.lat;
    _lng = b?.lng;
    _regionId = b?.regionId ?? '';
    _districtId = b?.districtId ?? '';
  }

  @override
  void dispose() {
    for (final c in [_name, _subtype, _description, _phone, _address, _hours, _website]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final r = await Navigator.of(context).push<MapPickerResult>(
      MaterialPageRoute(builder: (_) => MapPickerScreen(title: context.tr('bizmap_pick_location'))),
    );
    if (r == null || !mounted) return;
    setState(() {
      _lat = r.lat;
      _lng = r.lng;
      if (_address.text.trim().isEmpty) _address.text = r.label;
      _error = null;
    });
    // Туман/вилоят — ихтиёрий (веб'да geocoder йўқ → бўш қолади, сервер рад этмайди).
    final area = await LocationAreaService().areaAt(r.lat, r.lng);
    if (!mounted || area == null) {
      _regionId = '';
      _districtId = '';
      return;
    }
    _regionId = area.regionId;
    _districtId = area.districtId;
  }

  String _errorFor(Object e) {
    switch (BusinessRepository.errorCode(e)) {
      case 'BUSINESS_NAME_INVALID':
        return context.tr('bizmap_err_name');
      case 'BUSINESS_CATEGORY_INVALID':
        return context.tr('bizmap_err_category');
      case 'BUSINESS_LOCATION_INVALID':
        return context.tr('bizmap_err_location');
      case 'BUSINESS_PHONE_INVALID':
        return context.tr('bizmap_err_phone');
      case 'BUSINESS_FIELD_INVALID':
        return context.tr('bizmap_err_field');
      case 'BUSINESS_LIMIT_REACHED':
        return context.tr('bizmap_err_limit');
      default:
        return context.tr('bizmap_err_generic');
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2) return setState(() => _error = context.tr('bizmap_err_name'));
    final category = _category;
    if (category == null) return setState(() => _error = context.tr('bizmap_err_category'));
    final lat = _lat;
    final lng = _lng;
    if (lat == null || lng == null) return setState(() => _error = context.tr('bizmap_err_location'));
    if (_phone.text.replaceAll(RegExp(r'\D'), '').length < 9) {
      return setState(() => _error = context.tr('bizmap_err_phone'));
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final draft = Business(
        id: widget.existing?.id ?? '',
        ownerId: widget.existing?.ownerId ?? '',
        name: name,
        category: category,
        subtype: _subtype.text.trim(),
        description: _description.text.trim(),
        phone: _phone.text.trim(),
        address: _address.text.trim(),
        lat: lat,
        lng: lng,
        regionId: _regionId,
        districtId: _districtId,
        openingHours: _hours.text.trim(),
        website: _website.text.trim(),
      );
      await _repo.upsertMine(draft, businessId: widget.existing?.id, clientRequestId: _requestId);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(context.tr('bizmap_saved'))));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _errorFor(e);
      });
    }
  }

  InputDecoration _dec(String labelKey, {String? hintKey}) => InputDecoration(
        labelText: context.tr(labelKey),
        hintText: hintKey == null ? null : context.tr(hintKey),
        border: const OutlineInputBorder(),
      );

  @override
  Widget build(BuildContext context) {
    final hasLocation = _lat != null && _lng != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(_isEdit ? 'bizmap_form_edit' : 'bizmap_form_new')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            enabled: !_busy,
            maxLength: 80,
            decoration: _dec('bizmap_f_name'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<BusinessCategory>(
            initialValue: _category,
            decoration: _dec('bizmap_f_category'),
            items: [
              for (final c in BusinessCategory.values)
                DropdownMenuItem(
                  value: c,
                  child: Row(children: [
                    Icon(c.icon, size: 18),
                    const SizedBox(width: 8),
                    Flexible(child: Text(context.tr(c.labelKey), overflow: TextOverflow.ellipsis)),
                  ]),
                ),
            ],
            onChanged: _busy ? null : (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _subtype,
            enabled: !_busy,
            maxLength: 60,
            decoration: _dec('bizmap_f_subtype', hintKey: 'bizmap_f_subtype_hint'),
          ),
          TextField(
            controller: _description,
            enabled: !_busy,
            maxLines: 3,
            maxLength: 500,
            decoration: _dec('bizmap_f_description'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _phone,
            enabled: !_busy,
            keyboardType: TextInputType.phone,
            decoration: _dec('bizmap_f_phone'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickLocation,
            icon: Icon(hasLocation ? Icons.check_circle_rounded : Icons.add_location_alt_rounded,
                color: hasLocation ? Colors.green.shade700 : null),
            label: Text(context.tr(hasLocation ? 'bizmap_location_set' : 'bizmap_pick_location')),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            enabled: !_busy,
            maxLength: 200,
            decoration: _dec('bizmap_f_address'),
          ),
          TextField(
            controller: _hours,
            enabled: !_busy,
            maxLength: 120,
            decoration: _dec('bizmap_f_hours', hintKey: 'bizmap_f_hours_hint'),
          ),
          TextField(
            controller: _website,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            maxLength: 120,
            decoration: _dec('bizmap_f_website'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ),
          FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryDark,
              foregroundColor: AppColors.onPrimary,
              minimumSize: const Size.fromHeight(50),
            ),
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.tr('bizmap_save')),
          ),
        ],
      ),
    );
  }
}
