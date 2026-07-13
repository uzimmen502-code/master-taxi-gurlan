import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/oil_vehicle.dart';
import '../../../repositories/oil_change_repository.dart';
import '../../../repositories/user_repository.dart';
import '../../../services/oil_change_service.dart';

const _commonOils = [
  '5W-30',
  '5W-40',
  '10W-40',
  '0W-20',
  '0W-30',
  '15W-40',
];

/// Mashina + moy ma'lumotlarini kiritish / tahrirlash.
class OilVehicleEditScreen extends StatefulWidget {
  const OilVehicleEditScreen({
    super.key,
    required this.uid,
    this.vehicle,
  });

  final String uid;
  final OilVehicle? vehicle;

  @override
  State<OilVehicleEditScreen> createState() => _OilVehicleEditScreenState();
}

class _OilVehicleEditScreenState extends State<OilVehicleEditScreen> {
  final _repo = OilChangeRepository();
  final _modelCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _seatsCtrl = TextEditingController(text: '4');
  final _oilCtrl = TextEditingController();
  final _odoCtrl = TextEditingController();
  final _currentOdoCtrl = TextEditingController();
  final _intervalKmCtrl = TextEditingController(text: '5000');
  final _intervalMoCtrl = TextEditingController(text: '6');

  DateTime? _lastChanged;
  bool _isPrimary = true;
  bool _saving = false;
  bool _claimBonus = false;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle;
    if (v != null) {
      _modelCtrl.text = v.model;
      _colorCtrl.text = v.color;
      _plateCtrl.text = v.plate;
      if (v.year > 0) _yearCtrl.text = '${v.year}';
      _seatsCtrl.text = '${v.seats > 0 ? v.seats : 4}';
      _oilCtrl.text = v.oilType;
      if (v.lastOdometerKm > 0) _odoCtrl.text = '${v.lastOdometerKm}';
      if (v.currentOdometerKm > 0) {
        _currentOdoCtrl.text = '${v.currentOdometerKm}';
      }
      _intervalKmCtrl.text = '${v.intervalKm}';
      _intervalMoCtrl.text = '${v.intervalMonths}';
      _lastChanged = v.lastChangedAt;
      _isPrimary = v.isPrimary;
    } else {
      _prefillFromProfile();
    }
  }

  Future<void> _prefillFromProfile() async {
    final car = await UserRepository().getCarInfo(widget.uid);
    if (car == null || !mounted) return;
    setState(() {
      if (_modelCtrl.text.isEmpty) _modelCtrl.text = car['carModel'] ?? '';
      if (_colorCtrl.text.isEmpty) _colorCtrl.text = car['carColor'] ?? '';
      if (_plateCtrl.text.isEmpty) _plateCtrl.text = car['carPlate'] ?? '';
      final seats = car['carSeats'] ?? '';
      if (seats.isNotEmpty) _seatsCtrl.text = seats;
      _claimBonus = true;
    });
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    _colorCtrl.dispose();
    _plateCtrl.dispose();
    _yearCtrl.dispose();
    _seatsCtrl.dispose();
    _oilCtrl.dispose();
    _odoCtrl.dispose();
    _currentOdoCtrl.dispose();
    _intervalKmCtrl.dispose();
    _intervalMoCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _lastChanged ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      locale: const Locale('uz'),
    );
    if (picked != null) setState(() => _lastChanged = picked);
  }

  Future<void> _save() async {
    final model = _modelCtrl.text.trim();
    final color = _colorCtrl.text.trim();
    final plate = _plateCtrl.text.trim().toUpperCase();
    final seats = int.tryParse(_seatsCtrl.text.trim()) ?? 0;
    if (model.isEmpty || color.isEmpty || plate.isEmpty || seats <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('oil_fill_required'))),
      );
      return;
    }

    setState(() => _saving = true);
    final manualNote = context.tr('oil_note_manual');
    try {
      final oil = _oilCtrl.text.trim();
      final lastOdo = int.tryParse(_odoCtrl.text.trim()) ?? 0;
      final currentOdo = int.tryParse(_currentOdoCtrl.text.trim()) ?? lastOdo;
      final intervalKm = int.tryParse(_intervalKmCtrl.text.trim()) ?? 5000;
      final intervalMo = int.tryParse(_intervalMoCtrl.text.trim()) ?? 6;
      final year = int.tryParse(_yearCtrl.text.trim()) ?? 0;

      final vehicle = OilVehicle(
        id: widget.vehicle?.id ?? '',
        brand: widget.vehicle?.brand ?? '',
        model: model,
        color: color,
        plate: plate,
        year: year,
        engine: widget.vehicle?.engine ?? '',
        fuelType: widget.vehicle?.fuelType ?? '',
        usageTags: widget.vehicle?.usageTags ?? const [],
        seats: seats,
        oilType: oil,
        lastChangedAt: _lastChanged,
        lastOdometerKm: lastOdo,
        currentOdometerKm: currentOdo,
        intervalKm: intervalKm,
        intervalMonths: intervalMo,
        isPrimary: _isPrimary || widget.vehicle == null,
      );

      final id = await _repo.saveVehicle(uid: widget.uid, vehicle: vehicle);

      final prev = widget.vehicle;
      final oilChanged = prev == null ||
          prev.oilType != oil ||
          prev.lastOdometerKm != lastOdo ||
          prev.lastChangedAt?.toIso8601String() !=
              _lastChanged?.toIso8601String();
      if (oil.isNotEmpty &&
          _lastChanged != null &&
          lastOdo > 0 &&
          oilChanged) {
        await _repo.recordOilChange(
          uid: widget.uid,
          vehicleId: id,
          changedAt: _lastChanged!,
          odometerKm: lastOdo,
          oilType: oil,
          intervalKm: intervalKm,
          intervalMonths: intervalMo,
          note: manualNote,
        );
      }

      final saved = vehicle.copyWith(id: id);
      await OilChangeService.scheduleDueReminder(saved);

      if (_claimBonus) {
        try {
          await OilChangeService.claimCarProfileBonus(uid: widget.uid);
        } catch (_) {}
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('oil_save_failed').replaceAll('{error}', '$e'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy');
    final intervalKm =
        _intervalKmCtrl.text.isEmpty ? '5000' : _intervalKmCtrl.text;
    final intervalMo =
        _intervalMoCtrl.text.isEmpty ? '6' : _intervalMoCtrl.text;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.vehicle == null
            ? context.tr('oil_edit_add_title')
            : context.tr('oil_edit_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            context.tr('oil_profile_section'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 8),
          _field(_modelCtrl, context.tr('oil_field_model')),
          _field(_colorCtrl, context.tr('oil_field_color')),
          _field(
            _plateCtrl,
            context.tr('oil_field_plate'),
            textCapitalization: TextCapitalization.characters,
          ),
          Row(
            children: [
              Expanded(
                child: _field(
                  _yearCtrl,
                  context.tr('oil_field_year_opt'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(
                  _seatsCtrl,
                  context.tr('oil_field_seats'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.tr('oil_primary_car')),
            value: _isPrimary,
            onChanged: (v) => setState(() => _isPrimary = v),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('oil_tracking_section'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 8),
          _field(_oilCtrl, context.tr('oil_field_oil_type')),
          Wrap(
            spacing: 6,
            children: _commonOils
                .map(
                  (o) => ActionChip(
                    label: Text(o),
                    onPressed: () => setState(() => _oilCtrl.text = o),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _lastChanged == null
                  ? context.tr('oil_last_change_date')
                  : context.tr('oil_last_change_on').replaceAll(
                        '{date}',
                        df.format(_lastChanged!),
                      ),
            ),
            trailing: const Icon(Icons.calendar_today),
            onTap: _pickDate,
          ),
          _field(
            _odoCtrl,
            context.tr('oil_last_odo'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          _field(
            _currentOdoCtrl,
            context.tr('oil_current_odo'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          Row(
            children: [
              Expanded(
                child: _field(
                  _intervalKmCtrl,
                  context.tr('oil_interval_km'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _field(
                  _intervalMoCtrl,
                  context.tr('oil_interval_mo'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('oil_next_due_hint')
                .replaceAll('{km}', intervalKm)
                .replaceAll('{mo}', intervalMo),
            style: TextStyle(color: Colors.grey.shade700, height: 1.3),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(50),
            ),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(context.tr('oil_save')),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        textCapitalization: textCapitalization,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
