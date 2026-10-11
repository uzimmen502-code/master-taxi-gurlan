// AVA LOGISTICS — «Посилка жўнатиш» формаси.
//
// Оқим: қаердан/қаерга (вилоят → туман → манзил) → посилка(лар): вазн ва
// ўлчам (ГРАММ, СМ — бутун сон, 12-банд) → қабул қилувчи → «Нархни
// билиш» (`quoteLogisticsOrder`) → «Буюртма бериш» (`createLogisticsOrder`).
//
// Нарх ФАҚАТ сервердан (44-банд): илова ҳеч нарса ҳисобламайди, фақат
// кўрсатади. `clientRequestId` экран очилганда БИР МАРТА яратилади —
// «Буюртма бериш» икки марта босилса ҳам битта буюртма (Т-12).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/geo_area.dart';
import '../../../repositories/service_config_repository.dart';
import '../data/logistics_repository.dart';
import '../domain/logistics_models.dart';
import '../ui/logistics_text.dart';
import 'logistics_order_screen.dart';

/// Сервер `MAX_PARCELS` билан бир хил (api/logistics.js).
const int kLogisticsMaxParcels = 5;

class LogisticsSendScreen extends StatefulWidget {
  const LogisticsSendScreen({
    super.key,
    required this.ownerId,
    this.repository,
    this.geoRepository,
  });

  final String ownerId;
  final LogisticsRepository? repository;
  final ServiceConfigRepository? geoRepository;

  @override
  State<LogisticsSendScreen> createState() => _LogisticsSendScreenState();
}

class _LogisticsSendScreenState extends State<LogisticsSendScreen> {
  late final LogisticsRepository _repo = widget.repository ?? LogisticsRepository();
  late final ServiceConfigRepository _geo = widget.geoRepository ?? ServiceConfigRepository();
  late final String _requestId = _repo.newRequestId();

  List<GeoRegion> _regions = const [];
  final Map<String, List<GeoDistrict>> _districts = {};

  LogisticsPoint _origin = const LogisticsPoint(regionId: '');
  LogisticsPoint _destination = const LogisticsPoint(regionId: '');
  final List<_ParcelDraft> _parcels = [_ParcelDraft()];
  final _recipientName = TextEditingController();
  final _recipientPhone = TextEditingController();
  final _note = TextEditingController();

  LogisticsQuote? _quote;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  @override
  void dispose() {
    for (final p in _parcels) {
      p.dispose();
    }
    _recipientName.dispose();
    _recipientPhone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadRegions() async {
    final regions = await _geo.fetchRegions();
    if (mounted) setState(() => _regions = regions);
  }

  Future<void> _ensureDistricts(String regionId) async {
    if (regionId.isEmpty || _districts.containsKey(regionId)) return;
    final list = await _geo.fetchDistricts(regionId);
    if (mounted) setState(() => _districts[regionId] = list);
  }

  /// Ҳар қандай ўзгариш нархни эскиртиради — қайта сўралади.
  void _changed() {
    if (_quote != null || _error != null) {
      setState(() {
        _quote = null;
        _error = null;
      });
    }
  }

  String? _localValidation() {
    if (!_origin.isSet || !_destination.isSet) return context.tr('logistics_err_point_region_required');
    for (final p in _parcels) {
      if (!p.toSpec().isValid) return context.tr('logistics_err_parcel_invalid');
    }
    return null;
  }

  Future<void> _getQuote() async {
    final err = _localValidation();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    await _run(() async {
      final q = await _repo.quote(
        origin: _origin,
        destination: _destination,
        parcels: _parcels.map((p) => p.toSpec()).toList(),
      );
      if (mounted) setState(() => _quote = q);
    });
  }

  Future<void> _placeOrder() async {
    final err = _localValidation();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (_recipientName.text.trim().length < 2) {
      setState(() => _error = context.tr('logistics_err_recipient_name'));
      return;
    }
    if (_recipientPhone.text.replaceAll(RegExp(r'\D'), '').length < 9) {
      setState(() => _error = context.tr('logistics_err_recipient_phone'));
      return;
    }
    await _run(() async {
      final r = await _repo.createOrder(
        clientRequestId: _requestId,
        origin: _origin,
        destination: _destination,
        parcels: _parcels.map((p) => p.toSpec()).toList(),
        recipientName: _recipientName.text.trim(),
        recipientPhone: _recipientPhone.text.trim(),
        note: _note.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('logistics_order_created'))),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => LogisticsOrderScreen(
            orderId: r.orderId,
            ownerId: widget.ownerId,
            repository: _repo,
          ),
        ),
      );
    });
  }

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body();
    } catch (e) {
      if (mounted) setState(() => _error = logisticsErrorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface,
        elevation: 0,
        title: Text(
          context.tr('logistics_send'),
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section(context, 'logistics_from', Icons.outbox_outlined),
            _PointFields(
              point: _origin,
              regions: _regions,
              districts: _districts[_origin.regionId] ?? const [],
              onChanged: (p) {
                setState(() => _origin = p);
                _ensureDistricts(p.regionId);
                _changed();
              },
            ),
            const SizedBox(height: 18),
            _section(context, 'logistics_to', Icons.move_to_inbox_outlined),
            _PointFields(
              point: _destination,
              regions: _regions,
              districts: _districts[_destination.regionId] ?? const [],
              onChanged: (p) {
                setState(() => _destination = p);
                _ensureDistricts(p.regionId);
                _changed();
              },
            ),
            const SizedBox(height: 18),

            for (var i = 0; i < _parcels.length; i += 1) ...[
              Row(
                children: [
                  Expanded(
                    child: _section(
                      context,
                      'logistics_parcel',
                      Icons.inventory_2_outlined,
                      suffix: _parcels.length > 1 ? ' ${i + 1}' : '',
                    ),
                  ),
                  if (_parcels.length > 1)
                    IconButton(
                      tooltip: context.tr('logistics_remove_parcel'),
                      onPressed: _busy
                          ? null
                          : () {
                              setState(() => _parcels.removeAt(i).dispose());
                              _changed();
                            },
                      icon: Icon(Icons.delete_outline, color: c.danger),
                    ),
                ],
              ),
              _ParcelFields(draft: _parcels[i], onChanged: _changed),
              if (_quote != null && i < _quote!.parcels.length) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(context.tr('logistics_price_per_parcel'), style: TextStyle(fontSize: 12, color: c.ink2)),
                    const Spacer(),
                    Text(
                      '${logisticsMoney(_quote!.parcels[i].customerPrice)} ${context.tr('sum')}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
            ],
            if (_parcels.length < kLogisticsMaxParcels)
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () {
                        setState(() => _parcels.add(_ParcelDraft()));
                        _changed();
                      },
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.brand,
                  side: BorderSide(color: c.line),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.add),
                label: Text(context.tr('logistics_add_parcel')),
              ),
            const SizedBox(height: 18),

            _section(context, 'logistics_recipient', Icons.person_outline),
            _field(
              context,
              controller: _recipientName,
              labelKey: 'logistics_recipient_name',
              onChanged: (_) => _changed(),
            ),
            const SizedBox(height: 8),
            _field(
              context,
              controller: _recipientPhone,
              labelKey: 'logistics_recipient_phone',
              keyboardType: TextInputType.phone,
              onChanged: (_) => _changed(),
            ),
            const SizedBox(height: 8),
            _field(
              context,
              controller: _note,
              labelKey: 'logistics_note',
              maxLines: 2,
              onChanged: (_) {},
            ),
            const SizedBox(height: 18),

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(10)),
                child: Text(_error!, style: TextStyle(fontSize: 12, color: c.danger)),
              ),
              const SizedBox(height: 12),
            ],

            if (_quote != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    Text(
                      context.tr('logistics_price_total'),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink),
                    ),
                    const Spacer(),
                    Text(
                      '${logisticsMoney(_quote!.total)} ${context.tr('sum')}',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.brand),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _placeOrder,
                style: FilledButton.styleFrom(
                  backgroundColor: c.brand,
                  foregroundColor: c.brandInk,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(
                        context.tr('logistics_place_order'),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
              ),
            ] else
              FilledButton(
                onPressed: _busy ? null : _getQuote,
                style: FilledButton.styleFrom(
                  backgroundColor: c.brand,
                  foregroundColor: c.brandInk,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(
                        context.tr('logistics_get_quote'),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String key, IconData icon, {String suffix = ''}) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c.brand),
          const SizedBox(width: 6),
          Text(
            '${context.tr(key)}$suffix',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink),
          ),
        ],
      ),
    );
  }

  Widget _field(
    BuildContext context, {
    required TextEditingController controller,
    required String labelKey,
    required ValueChanged<String> onChanged,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    final c = context.ava;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: context.tr(labelKey),
        filled: true,
        fillColor: c.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.line),
        ),
      ),
      onChanged: onChanged,
    );
  }
}

/// Вилоят → туман → манзил.
class _PointFields extends StatelessWidget {
  const _PointFields({
    required this.point,
    required this.regions,
    required this.districts,
    required this.onChanged,
  });

  final LogisticsPoint point;
  final List<GeoRegion> regions;
  final List<GeoDistrict> districts;
  final ValueChanged<LogisticsPoint> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    InputDecoration deco(String key) => InputDecoration(
          labelText: context.tr(key),
          filled: true,
          fillColor: c.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.line),
          ),
        );
    final regionValue = regions.any((r) => r.id == point.regionId) ? point.regionId : null;
    final districtValue = districts.any((d) => d.id == point.districtId) ? point.districtId : '';

    // `initialValue` фақат яратилганда ўқилади — ташқаридан ўзгарса
    // (вилоят алмашганда туман тозаланади) виджет калит билан қайта
    // яратилади.
    return Column(
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('region-${regions.length}-$regionValue'),
          initialValue: regionValue,
          decoration: deco('logistics_region'),
          items: [
            for (final r in regions)
              DropdownMenuItem(value: r.id, child: Text(r.nameFor(context.contentLang))),
          ],
          onChanged: (v) => onChanged(LogisticsPoint(regionId: v ?? '', addressText: point.addressText)),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('district-${point.regionId}-${districts.length}-$districtValue'),
          initialValue: districtValue,
          decoration: deco('logistics_district'),
          items: [
            DropdownMenuItem(value: '', child: Text(context.tr('logistics_district_any'))),
            for (final d in districts)
              DropdownMenuItem(value: d.id, child: Text(d.nameFor(context.contentLang))),
          ],
          onChanged: point.regionId.isEmpty
              ? null
              : (v) => onChanged(point.copyWith(districtId: v ?? '')),
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: point.addressText,
          decoration: deco('logistics_address'),
          maxLength: 300,
          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
          onChanged: (v) => onChanged(point.copyWith(addressText: v)),
        ),
      ],
    );
  }
}

class _ParcelDraft {
  final weight = TextEditingController();
  final length = TextEditingController();
  final width = TextEditingController();
  final height = TextEditingController();
  final value = TextEditingController();
  final description = TextEditingController();
  bool fragile = false;

  int _int(TextEditingController c) => int.tryParse(c.text.replaceAll(RegExp(r'\D'), '')) ?? 0;

  ParcelSpec toSpec() => ParcelSpec(
        actualWeightG: _int(weight),
        lengthCm: _int(length),
        widthCm: _int(width),
        heightCm: _int(height),
        declaredValue: _int(value),
        description: description.text.trim(),
        fragile: fragile,
      );

  void dispose() {
    for (final c in [weight, length, width, height, value, description]) {
      c.dispose();
    }
  }
}

class _ParcelFields extends StatefulWidget {
  const _ParcelFields({required this.draft, required this.onChanged});

  final _ParcelDraft draft;
  final VoidCallback onChanged;

  @override
  State<_ParcelFields> createState() => _ParcelFieldsState();
}

class _ParcelFieldsState extends State<_ParcelFields> {
  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final d = widget.draft;
    Widget num(TextEditingController ctrl, String key) => TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: context.tr(key),
            filled: true,
            fillColor: c.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: c.line),
            ),
          ),
          onChanged: (_) => widget.onChanged(),
        );

    return Column(
      children: [
        num(d.weight, 'logistics_weight_g'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: num(d.length, 'logistics_length_cm')),
            const SizedBox(width: 8),
            Expanded(child: num(d.width, 'logistics_width_cm')),
            const SizedBox(width: 8),
            Expanded(child: num(d.height, 'logistics_height_cm')),
          ],
        ),
        const SizedBox(height: 8),
        num(d.value, 'logistics_declared_value'),
        const SizedBox(height: 8),
        TextField(
          controller: d.description,
          maxLength: 200,
          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
          decoration: InputDecoration(
            labelText: context.tr('logistics_description'),
            filled: true,
            fillColor: c.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: c.line),
            ),
          ),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: d.fragile,
          activeThumbColor: c.brand,
          title: Text(context.tr('logistics_fragile'), style: TextStyle(fontSize: 13, color: c.ink)),
          onChanged: (v) => setState(() => d.fragile = v),
        ),
      ],
    );
  }
}
