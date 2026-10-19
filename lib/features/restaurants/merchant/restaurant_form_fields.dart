// Ресторан формаси майдонлари — рўйхатдан ўтиш ва «Дўкон» таби учун БИТТА
// виджет (ном, манзил, жойлашув, ошхона тури, етказиш, тўлов, вақтлар).
// Ҳолат — [RestaurantFormData] (соф модел, тестланган).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/map_picker_result.dart';
import '../../../services/location_service.dart';
import '../../map_picker/screens/map_picker_screen.dart';
import '../domain/restaurant_models.dart' show Restaurant;
import 'restaurant_register_form.dart';

class RestaurantFormFields extends StatefulWidget {
  const RestaurantFormFields({
    super.key,
    required this.data,
    required this.onChanged,
    this.showLegalType = true,
    this.showPaymentDetails = true,
    this.showMaxQty = false,
    this.legalTypeOptions = RestaurantFormData.legalTypes,
  });

  /// Танлаш мумкин бўлган юридик шакллар (кафе: `yatt`/`llc`; уй ошпази
  /// танловсиз — `showLegalType: false`).
  final List<String> legalTypeOptions;

  final RestaurantFormData data;
  final VoidCallback onChanged;

  /// Юридик шакл фақат рўйхатдан ўтишда (кейин ўзгармайди — server-only).
  final bool showLegalType;

  /// Карта рақами/эгаси — рўйхатдан ўтишда формада; «Дўкон»да алоҳида блок.
  final bool showPaymentDetails;

  /// «Бир таомдан энг кўпи» (D-REST-26) — фақат «Дўкон»да; рўйхатдан ўтишда default.
  final bool showMaxQty;

  @override
  State<RestaurantFormFields> createState() => _RestaurantFormFieldsState();
}

class _RestaurantFormFieldsState extends State<RestaurantFormFields> {
  late final _name = TextEditingController(text: widget.data.name);
  late final _desc = TextEditingController(text: widget.data.description);
  late final _address = TextEditingController(text: widget.data.address);
  late final _phone = TextEditingController(text: widget.data.contactPhone);
  late final _card = TextEditingController(text: widget.data.cardNumber);
  late final _holder = TextEditingController(text: widget.data.cardHolder);
  late final _minOrder = TextEditingController(text: widget.data.minOrderAmount == 0 ? '' : '${widget.data.minOrderAmount}');
  late final _maxQty = TextEditingController(text: '${widget.data.maxQtyPerItem}');
  late final _ownFixed = TextEditingController(text: widget.data.ownFeeFixed == 0 ? '' : '${widget.data.ownFeeFixed}');
  late final _ownBase = TextEditingController(text: widget.data.ownFeeBase == 0 ? '' : '${widget.data.ownFeeBase}');
  late final _ownPerKm = TextEditingController(text: widget.data.ownFeePerKm == 0 ? '' : '${widget.data.ownFeePerKm}');
  late final _ownFree = TextEditingController(text: widget.data.ownFeeFreeAbove == null ? '' : '${widget.data.ownFeeFreeAbove}');
  late final _ownMaxKm = TextEditingController(text: widget.data.ownFeeMaxKm == null ? '' : '${widget.data.ownFeeMaxKm}');
  bool _locating = false;

  RestaurantFormData get d => widget.data;

  @override
  void dispose() {
    for (final c in [_name, _desc, _address, _phone, _card, _holder, _minOrder, _maxQty, _ownFixed, _ownBase, _ownPerKm, _ownFree, _ownMaxKm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(void Function() fn) {
    setState(fn);
    widget.onChanged();
  }

  int _int(String s) => int.tryParse(s.replaceAll(RegExp(r'\D'), '')) ?? 0;
  int? _intOrNull(String s) => s.trim().isEmpty ? null : _int(s);

  Future<void> _locateGps() async {
    setState(() => _locating = true);
    try {
      final c = await context.read<LocationService>().getCurrentCoords();
      _set(() {
        d.lat = c.lat;
        d.lng = c.lng;
      });
    } on LocationException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(LocationException.userMessage(e.kind))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('restaurants_err_generic'))));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickOnMap() async {
    final res = await Navigator.push<MapPickerResult>(
      context,
      MaterialPageRoute(builder: (_) => MapPickerScreen(title: context.tr('restaurants_m_location'))),
    );
    if (res == null) return;
    _set(() {
      d.lat = res.lat;
      d.lng = res.lng;
      if (_address.text.trim().isEmpty && res.label.trim().isNotEmpty) {
        _address.text = res.label;
        d.address = res.label;
      }
    });
  }

  Future<void> _pickTime(bool open) async {
    final cur = open ? d.openTime : d.closeTime;
    final parts = cur.split(':');
    final init = TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0);
    final t = await showTimePicker(context: context, initialTime: init);
    if (t == null) return;
    final s = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    _set(() {
      if (open) {
        d.openTime = s;
      } else {
        d.closeTime = s;
      }
    });
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
      );

  Widget _section(String title) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _name,
          maxLength: 80,
          decoration: _dec(context.tr('restaurants_m_name')),
          onChanged: (v) => _set(() => d.name = v),
        ),
        if (widget.showLegalType) ...[
          _section(context.tr('restaurants_m_legal_type')),
          Wrap(
            spacing: 6,
            children: [
              for (final t in widget.legalTypeOptions)
                ChoiceChip(
                  label: Text(context.tr('restaurants_m_legal_$t')),
                  selected: d.legalType == t,
                  onSelected: (_) => _set(() => d.legalType = t),
                ),
            ],
          ),
        ],
        _section(context.tr('restaurants_m_cuisine')),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final t in RestaurantFormData.cuisineOptions)
              FilterChip(
                label: Text(context.tr('restaurants_cuisine_$t')),
                selected: d.cuisineTags.contains(t),
                onSelected: (v) => _set(() {
                  final tags = List<String>.from(d.cuisineTags);
                  if (v) {
                    if (tags.length < 3) tags.add(t);
                  } else {
                    tags.remove(t);
                  }
                  d.cuisineTags = tags;
                }),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _desc,
          maxLength: 500,
          maxLines: 2,
          decoration: _dec(context.tr('restaurants_m_description')),
          onChanged: (v) => _set(() => d.description = v),
        ),
        _section(context.tr('restaurants_m_location')),
        TextField(
          controller: _address,
          maxLength: 300,
          decoration: _dec(context.tr('restaurants_m_address')),
          onChanged: (v) => _set(() => d.address = v),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _locating ? null : _locateGps,
                icon: _locating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location_rounded, size: 18),
                label: Text(context.tr('restaurants_m_location_gps')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickOnMap,
                icon: const Icon(Icons.map_outlined, size: 18),
                label: Text(context.tr('restaurants_m_location_map')),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            d.hasLocation
                ? '${context.tr('restaurants_m_location_set')} · ${d.lat!.toStringAsFixed(5)}, ${d.lng!.toStringAsFixed(5)}'
                : context.tr('restaurants_m_err_location'),
            style: TextStyle(fontSize: 12, color: d.hasLocation ? c.ok : c.warn),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: _dec(context.tr('restaurants_m_contact_phone'), hint: '+998 90 123 45 67'),
          onChanged: (v) => _set(() => d.contactPhone = v),
        ),
        _section(context.tr('restaurants_m_delivery_mode')),
        Wrap(
          spacing: 6,
          children: [
            for (final m in RestaurantFormData.deliveryModes)
              ChoiceChip(
                label: Text(context.tr('restaurants_m_delivery_${m == 'ava_courier' ? 'ava' : 'own'}')),
                selected: d.deliveryMode == m,
                onSelected: (_) => _set(() => d.deliveryMode = m),
              ),
          ],
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(context.tr('restaurants_m_pickup'), style: TextStyle(fontSize: 13, color: c.ink)),
          value: d.pickup,
          onChanged: (v) => _set(() => d.pickup = v),
        ),
        if (d.deliveryMode == 'own_courier') ...[
          Wrap(
            spacing: 6,
            children: [
              ChoiceChip(
                label: Text(context.tr('restaurants_m_own_fee_type_fixed')),
                selected: d.ownFeeType == 'fixed',
                onSelected: (_) => _set(() => d.ownFeeType = 'fixed'),
              ),
              ChoiceChip(
                label: Text(context.tr('restaurants_m_own_fee_type_distance')),
                selected: d.ownFeeType == 'distance',
                onSelected: (_) => _set(() => d.ownFeeType = 'distance'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (d.ownFeeType == 'fixed')
            TextField(
              controller: _ownFixed,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _dec(context.tr('restaurants_m_own_fee_fixed')),
              onChanged: (v) => _set(() => d.ownFeeFixed = _int(v)),
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ownBase,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _dec(context.tr('restaurants_m_own_fee_base')),
                    onChanged: (v) => _set(() => d.ownFeeBase = _int(v)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _ownPerKm,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _dec(context.tr('restaurants_m_own_fee_per_km')),
                    onChanged: (v) => _set(() => d.ownFeePerKm = _int(v)),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ownFree,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _dec(context.tr('restaurants_m_own_fee_free_above')),
                  onChanged: (v) => _set(() => d.ownFeeFreeAbove = _intOrNull(v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _ownMaxKm,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _dec(context.tr('restaurants_m_own_fee_max_km')),
                  onChanged: (v) => _set(() => d.ownFeeMaxKm = _intOrNull(v)),
                ),
              ),
            ],
          ),
        ],
        _section(context.tr('restaurants_m_payment')),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(context.tr('restaurants_m_payment_prepay'), style: TextStyle(fontSize: 13, color: c.ink)),
          value: d.prepay,
          onChanged: (v) => _set(() => d.prepay = v),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(context.tr('restaurants_m_payment_cash'), style: TextStyle(fontSize: 13, color: c.ink)),
          value: d.cash,
          onChanged: (v) => _set(() => d.cash = v),
        ),
        if (widget.showPaymentDetails && d.prepay) ...[
          const SizedBox(height: 6),
          TextField(
            controller: _card,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(16)],
            decoration: _dec(context.tr('restaurants_m_card_number'), hint: '8600 0000 0000 0000'),
            onChanged: (v) => _set(() => d.cardNumber = v),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _holder,
            maxLength: 60,
            decoration: _dec(context.tr('restaurants_m_card_holder')),
            onChanged: (v) => _set(() => d.cardHolder = v),
          ),
        ],
        _section(context.tr('restaurants_m_prep_time')),
        Wrap(
          spacing: 6,
          children: [
            for (final m in const [10, 15, 20, 30, 45, 60, 90])
              ChoiceChip(
                label: Text('$m'),
                selected: d.prepTimeMin == m,
                onSelected: (_) => _set(() => d.prepTimeMin = m),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _minOrder,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _dec(context.tr('restaurants_m_min_order')),
          onChanged: (v) => _set(() => d.minOrderAmount = _int(v)),
        ),
        if (widget.showMaxQty) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _maxQty,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
            decoration: _dec(context.tr('restaurants_m_max_qty')).copyWith(
              helperText: context.tr('restaurants_m_max_qty_hint').replaceAll('{max}', '${Restaurant.maxQtyPerItemCeiling}'),
              helperMaxLines: 3,
            ),
            // Бўш/0 — хато (`validate` → `max_qty`), жимгина default қўйилмайди.
            onChanged: (v) => _set(() => d.maxQtyPerItem = _int(v)),
          ),
          // Олдиндан буюртма (S4b): профилни таҳрирлашда (рўйхатдан ўтишда эмас).
          SwitchListTile(
            key: const ValueKey('accepts-preorder'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('restaurants_m_preorder'), style: TextStyle(fontSize: 13, color: c.ink)),
            subtitle: Text(context.tr('restaurants_m_preorder_hint'), style: TextStyle(fontSize: 12, color: c.ink2)),
            value: d.acceptsPreorder,
            onChanged: (v) => _set(() => d.acceptsPreorder = v),
          ),
        ],
        _section(context.tr('restaurants_m_hours')),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(context.tr('restaurants_m_always_open'), style: TextStyle(fontSize: 13, color: c.ink)),
          value: d.alwaysOpen,
          onChanged: (v) => _set(() => d.alwaysOpen = v),
        ),
        if (!d.alwaysOpen)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickTime(true),
                  child: Text('${context.tr('restaurants_m_open_at')}: ${d.openTime}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickTime(false),
                  child: Text('${context.tr('restaurants_m_close_at')}: ${d.closeTime}'),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
