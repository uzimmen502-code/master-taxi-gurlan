import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../services/location_service.dart';
import '../models/yuk_local_driver.dart';
import '../repositories/yuk_local_drivers_repository.dart';
import '../yuk_accept_radius.dart';
import '../yuk_vehicle_types.dart';

/// Ҳайдовчи: машинани туман ичида жойлаштириш / радиус.
Future<bool?> showYukLocalDriverSheet({
  required BuildContext context,
  required String ownerId,
  required String ownerName,
  required String ownerPhone,
  YukLocalDriver? initial,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF131A22),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _YukLocalDriverSheet(
      ownerId: ownerId,
      ownerName: ownerName,
      ownerPhone: ownerPhone,
      initial: initial,
    ),
  );
}

class _YukLocalDriverSheet extends StatefulWidget {
  const _YukLocalDriverSheet({
    required this.ownerId,
    required this.ownerName,
    required this.ownerPhone,
    this.initial,
  });

  final String ownerId;
  final String ownerName;
  final String ownerPhone;
  final YukLocalDriver? initial;

  @override
  State<_YukLocalDriverSheet> createState() => _YukLocalDriverSheetState();
}

class _YukLocalDriverSheetState extends State<_YukLocalDriverSheet> {
  static const _muted = Color(0xFF94A3B8);
  static const _accent = Color(0xFFFACC15);
  static const _border = Color(0xFF252B36);

  final _repo = YukLocalDriversRepository();
  final _plate = TextEditingController();
  final _capacity = TextEditingController();
  final _len = TextEditingController();
  final _width = TextEditingController();
  final _height = TextEditingController();
  final _location = TextEditingController();

  String _vehicle = 'gazel';
  int _radiusKm = YukAcceptRadius.defaultKm;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i != null) {
      _vehicle = i.vehicleType;
      _plate.text = i.plateNumber;
      if (i.capacityTons > 0) {
        _capacity.text = _fmtNum(i.capacityTons);
      }
      if (i.bodyLengthM > 0) _len.text = _fmtNum(i.bodyLengthM);
      if (i.bodyWidthM > 0) _width.text = _fmtNum(i.bodyWidthM);
      if (i.bodyHeightM > 0) _height.text = _fmtNum(i.bodyHeightM);
      _radiusKm = i.acceptRadiusKm;
      _location.text = i.locationLabel;
    }
  }

  String _fmtNum(double v) {
    if (v == v.roundToDouble()) return '${v.round()}';
    return v.toStringAsFixed(1);
  }

  double _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  @override
  void dispose() {
    _plate.dispose();
    _capacity.dispose();
    _len.dispose();
    _width.dispose();
    _height.dispose();
    _location.dispose();
    super.dispose();
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: const Color(0xFF0B0E14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _accent),
        ),
      );

  Future<void> _submit({required bool goOnline}) async {
    if (widget.ownerId.isEmpty) {
      setState(() => _error = context.tr('yuk_need_phone'));
      return;
    }
    // Мажбурий: машина тури + қамров радиуси (ҳар доим танланган).
    // Қолган майдонлар ихтиёрий.
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!goOnline) {
        await _repo.setOffline(widget.ownerId);
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }
      LocationCoords coords;
      try {
        coords = await const LocationService().getCurrentCoords();
      } catch (_) {
        setState(() {
          _busy = false;
          _error = context.tr('yuk_local_need_gps');
        });
        return;
      }
      String label = _location.text.trim();
      if (label.isEmpty) {
        final addr = await const LocationService()
            .addressFromCoords(coords.lat, coords.lng);
        label = (addr ?? '').trim();
      }
      await _repo.publishPresence(
        ownerId: widget.ownerId,
        ownerName: widget.ownerName,
        phone: widget.ownerPhone,
        vehicleType: _vehicle,
        plateNumber: _plate.text.trim(),
        capacityTons: _num(_capacity),
        bodyLengthM: _num(_len),
        bodyWidthM: _num(_width),
        bodyHeightM: _num(_height),
        acceptRadiusKm: _radiusKm,
        loadStatus: YukLocalLoadStatus.empty,
        lat: coords.lat,
        lng: coords.lng,
        locationLabel: label,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.tr('yuk_local_publish_fail');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('yuk_local_publish_title'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('yuk_local_publish_hint'),
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _vehicle,
              dropdownColor: const Color(0xFF131A22),
              decoration: _deco(context.tr('yuk_vehicle_all')),
              items: [
                for (final t in kYukVehicleTypes)
                  DropdownMenuItem(
                    value: t.value,
                    child: Text(
                      context.tr(t.labelKey),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _vehicle = v);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _plate,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.characters,
              decoration: _deco(context.tr('yuk_local_plate_hint')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _capacity,
              style: const TextStyle(color: Colors.white),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: _deco(context.tr('yuk_capacity_tons')),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _len,
                    style: const TextStyle(color: Colors.white),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _deco(context.tr('yuk_local_body_l')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _width,
                    style: const TextStyle(color: Colors.white),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _deco(context.tr('yuk_local_body_w')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _height,
                    style: const TextStyle(color: Colors.white),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _deco(context.tr('yuk_local_body_h')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _location,
              style: const TextStyle(color: Colors.white),
              decoration: _deco(context.tr('yuk_local_location_hint')),
            ),
            const SizedBox(height: 14),
            Text(
              context.tr('yuk_local_radius_title'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in YukAcceptRadius.options)
                  ChoiceChip(
                    label: Text(context.tr(o.labelKey)),
                    selected: _radiusKm == o.valueKm,
                    selectedColor: _accent.withValues(alpha: 0.25),
                    labelStyle: TextStyle(
                      color: _radiusKm == o.valueKm ? _accent : _muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    side: BorderSide(
                      color: _radiusKm == o.valueKm ? _accent : _border,
                    ),
                    backgroundColor: const Color(0xFF0B0E14),
                    onSelected: (_) =>
                        setState(() => _radiusKm = o.valueKm),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : () => _submit(goOnline: true),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.tr('yuk_local_go_online')),
            ),
            if (widget.initial?.online == true) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : () => _submit(goOnline: false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _muted,
                  side: const BorderSide(color: _border),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(context.tr('yuk_local_go_offline')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
