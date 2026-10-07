import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/oil_vehicle.dart';
import '../../../repositories/oil_change_repository.dart';

/// ⚡ «Менинг автомобилим» — EV маълумоти БИР МАРТА киритилади.
///
/// Алоҳида коллекция яратилмайди: ёзув мавжуд гаражга
/// (`users/{uid}/vehicles`, `OilVehicle`) тушади — машина битта, уни
/// иккита жойда сақлаш маълумотни айирар эди. `firestore.rules`да бу йўл
/// эга учун аллақачон очиқ, шунинг учун янги қоида/деплой керак эмас.
class EvCarSheet extends StatefulWidget {
  const EvCarSheet({super.key, required this.uid, this.vehicle});

  final String uid;

  /// Гараждаги асосий машина — бўлмаса янгиси яратилади.
  final OilVehicle? vehicle;

  static Future<OilVehicle?> show(
    BuildContext context, {
    required String uid,
    OilVehicle? vehicle,
  }) {
    return showModalBottomSheet<OilVehicle>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => EvCarSheet(uid: uid, vehicle: vehicle),
    );
  }

  @override
  State<EvCarSheet> createState() => _EvCarSheetState();
}

class _EvCarSheetState extends State<EvCarSheet> {
  static const _connectorOptions = ['CCS2', 'Type 2', 'GB/T', 'CHAdeMO'];

  final _repo = OilChangeRepository();
  late final TextEditingController _modelCtrl;
  late final TextEditingController _batteryCtrl;
  late final TextEditingController _consumptionCtrl;
  late final Set<String> _connectors;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle;
    _modelCtrl = TextEditingController(text: v?.model ?? '');
    _batteryCtrl = TextEditingController(
        text: (v?.evBatteryKwh ?? 0) > 0 ? _num(v!.evBatteryKwh) : '');
    _consumptionCtrl = TextEditingController(
        text: (v?.evConsumptionKwhPer100Km ?? 0) > 0
            ? _num(v!.evConsumptionKwhPer100Km)
            : '');
    _connectors = {...?v?.evConnectors};
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  @override
  void dispose() {
    _modelCtrl.dispose();
    _batteryCtrl.dispose();
    _consumptionCtrl.dispose();
    super.dispose();
  }

  double _parse(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.')) ?? 0;

  Future<void> _save() async {
    final battery = _parse(_batteryCtrl.text);
    final consumption = _parse(_consumptionCtrl.text);

    // Ўйлаб топилган қиймат билан режа тузилмайди — иккиси ҳам шарт.
    if (battery <= 0 || consumption <= 0) {
      setState(() => _error = context.tr('ev_trip_car_invalid'));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final prev = widget.vehicle;
      final vehicle = (prev ??
              OilVehicle(
                id: '',
                model: _modelCtrl.text.trim(),
                color: '',
                plate: '',
                isPrimary: true,
              ))
          .copyWith(
        model: _modelCtrl.text.trim(),
        fuelType: 'ev',
        evBatteryKwh: battery,
        evConsumptionKwhPer100Km: consumption,
        evConnectors: _connectors.toList(),
      );

      final id = await _repo.saveVehicle(uid: widget.uid, vehicle: vehicle);
      if (!mounted) return;
      Navigator.pop(context, vehicle.copyWith(id: id));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = context.tr('ev_trip_car_save_failed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.electric_car_rounded,
                    color: AppColors.primaryText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('ev_trip_car_title'),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('ev_trip_car_subtitle'),
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _modelCtrl,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: context.tr('ev_trip_car_model'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _batteryCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: context.tr('ev_trip_battery'),
                helperText: context.tr('ev_trip_battery_hint'),
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _consumptionCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: context.tr('ev_trip_consumption'),
                helperText: context.tr('ev_trip_consumption_hint'),
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('ev_trip_connectors'),
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _connectorOptions)
                  FilterChip(
                    label: Text(c),
                    selected: _connectors.contains(c),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _connectors.add(c);
                      } else {
                        _connectors.remove(c);
                      }
                    }),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style:
                      const TextStyle(color: Color(0xFFC62828), fontSize: 13)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: AppColors.onPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.onPrimary),
                      )
                    : Text(context.tr('save')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
