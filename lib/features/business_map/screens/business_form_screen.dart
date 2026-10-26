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
import '../domain/website_link.dart';

/// Эга ўз объектини қўшади/таҳрирлайди (B-1). Жойни мавжуд [MapPickerScreen] билан белгилайди (B-5).
/// Ҳамма текширув серверда (`upsertMyBusiness`); бу ерда фақат тез инкор ва тушунарли хато матни.
class BusinessFormScreen extends StatefulWidget {
  const BusinessFormScreen({
    super.key,
    this.existing,
    this.initialCategory,
    this.lockCategory = false,
    this.branchParents = const [],
    BusinessRepository? repository,
  }) : _repo = repository;

  final Business? existing;

  /// Филиал танлови («Менинг дўконим»): эганинг филиал бўла олмайдиган (ўзи филиал эмас) йўналишлари.
  /// Бўш — танлов кўрсатилмайди. Сервер ота ва эгани текширади (`BRANCH_INVALID` / `BRANCH_NESTED`).
  final List<Business> branchParents;

  /// Янги объектда олдиндан танланган тур («Менинг дўконим» → «Янги дўкон» — чакана).
  /// Таҳрирда [existing]нинг тури устун.
  final BusinessCategory? initialCategory;

  /// «Менинг дўконим»: тур танлови яширилади (тур [initialCategory] ёки [existing]дан). Харита
  /// рўйхатидаги умумий форма (alse) аввалгидек тур танлайди.
  final bool lockCategory;
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

  /// Фақат онлайн (2026-10-25): жойи сўралмайди, харитага тушмайди (уй манзили мажбуран нуқта бўлмасин).
  bool _online = false;

  /// Филиал бўлса — ота йўналиш ID'си; бўш — алоҳида дўкон.
  String _branchOf = '';
  double? _lat;
  double? _lng;
  String _regionId = '';
  String _districtId = '';
  bool _busy = false;
  String? _error;

  /// Бир форма = бир калит: «Сақлаш» икки марта босилса ҳам битта объект (21-банд).
  final String _requestId = 'b${DateTime.now().microsecondsSinceEpoch}';

  bool get _isEdit => widget.existing != null;

  /// Ота бўла оладиганлар: ўзи эмас, ўзи филиал эмас, онлайн эмас.
  List<Business> get _parentChoices => [
        for (final p in widget.branchParents)
          if (p.id.isNotEmpty && p.id != widget.existing?.id && !p.isBranch && !p.isBlocked) p,
      ];

  /// Янги объектда телефон эганинг рақамидан бошланади (ўзгартириш мумкин). Firebase тайёр бўлмаса — бўш.
  static String _ownPhone() {
    try {
      return canonicalPhoneId(FirebaseAuth.instance.currentUser?.phoneNumber ?? '');
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    _name = TextEditingController(text: b?.name ?? '');
    _subtype = TextEditingController(text: b?.subtype ?? '');
    _description = TextEditingController(text: b?.description ?? '');
    _phone = TextEditingController(text: b?.phone ?? _ownPhone());
    _address = TextEditingController(text: b?.address ?? '');
    _hours = TextEditingController(text: b?.openingHours ?? '');
    _website = TextEditingController(text: b?.website ?? '');
    _category = b?.category ?? widget.initialCategory;
    _online = b?.online ?? false;
    _branchOf = b?.branchOf ?? '';
    _lat = (b == null || b.online) ? null : b.lat;
    _lng = (b == null || b.online) ? null : b.lng;
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
      case 'BRANCH_INVALID':
      case 'BRANCH_NESTED':
        return context.tr('my_shop_branch_err');
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
    if (!_online && (lat == null || lng == null)) return setState(() => _error = context.tr('bizmap_err_location'));
    if (_phone.text.replaceAll(RegExp(r'\D'), '').length < 9) {
      return setState(() => _error = context.tr('bizmap_err_phone'));
    }
    if (!websiteFieldValid(_website.text)) return setState(() => _error = context.tr('bizmap_err_website'));
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
        address: _online ? '' : _address.text.trim(),
        lat: _online ? 0 : lat!,
        lng: _online ? 0 : lng!,
        online: _online,
        branchOf: _online ? '' : _branchOf,
        regionId: _regionId,
        districtId: _districtId,
        openingHours: _hours.text.trim(),
        website: _website.text.trim(),
      );
      final id = await _repo.upsertMine(draft, businessId: widget.existing?.id, clientRequestId: _requestId);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(context.tr('bizmap_saved'))));
      // Янги объект (филиал эмас) — чақирувчи унинг ID'си билан маҳсулотлар экранини очиши мумкин (эга, 2026-10-26:
      // «янги дўкон қўшгандан кейин шу ернинг ўзида маҳсулот қўшиш»). Таҳрир ва филиал — аввалгидек `true`.
      final isNewMain = widget.existing == null && draft.branchOf.isEmpty && id.isNotEmpty;
      Navigator.of(context).pop(isNewMain ? id : true);
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
          if (!widget.lockCategory) ...[
            DropdownButtonFormField<BusinessCategory>(
              initialValue: _category,
              isExpanded: true,
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
          ],
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
          const SizedBox(height: 4),
          SwitchListTile(
            key: const ValueKey('biz_online_switch'),
            contentPadding: EdgeInsets.zero,
            value: _online,
            onChanged: _busy ? null : (v) => setState(() {
                  _online = v;
                  _error = null;
                }),
            title: Text(context.tr('bizmap_f_online')),
            subtitle: Text(context.tr('bizmap_f_online_hint')),
          ),
          if (!_online && _parentChoices.isNotEmpty) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const ValueKey('biz_branch_of'),
              initialValue: _parentChoices.any((p) => p.id == _branchOf) ? _branchOf : '',
              isExpanded: true,
              decoration: _dec('my_shop_branch_of'),
              items: [
                DropdownMenuItem(value: '', child: Text(context.tr('my_shop_branch_none'))),
                for (final p in _parentChoices)
                  DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: _busy ? null : (v) => setState(() => _branchOf = v ?? ''),
            ),
          ],
          if (!_online) ...[
            const SizedBox(height: 8),
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
          ],
          const SizedBox(height: 4),
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
            decoration: _dec('bizmap_f_website').copyWith(helperText: context.tr('bizmap_f_website_hint'), helperMaxLines: 2),
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
