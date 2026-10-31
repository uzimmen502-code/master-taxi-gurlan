import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../repositories/courier_scopes_repository.dart';

/// «Иш ҳудуди» — курьер тоифаларини ўзи танлайди (эга қарори 2026-10-31):
/// туман дарҳол; вилоят ва республика — машина + ҳужжат, админ тасдиқлайди
/// (ёки админда «Авто» ёқилган бўлса дарҳол). Қарорни сервер қилади.
class CourierScopesScreen extends StatefulWidget {
  const CourierScopesScreen({super.key, required this.uid, this.repository});

  /// Курьернинг канон (12 хонали) рақами.
  final String uid;
  final CourierScopesRepository? repository;

  @override
  State<CourierScopesScreen> createState() => _CourierScopesScreenState();
}

class _CourierScopesScreenState extends State<CourierScopesScreen> {
  late final CourierScopesRepository _repo = widget.repository ?? CourierScopesRepository();
  final _plate = TextEditingController();
  final _model = TextEditingController();
  final _license = TextEditingController();

  CourierScopes? _data;
  final Set<String> _picked = {};
  bool _hasCar = false;
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _plate.dispose();
    _model.dispose();
    _license.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final d = await _repo.load(widget.uid);
      if (!mounted) return;
      setState(() {
        _data = d;
        _picked
          ..clear()
          ..addAll(d.scopes);
        _hasCar = d.vehicle['vehicleType'] == 'car';
        _plate.text = d.vehicle['carPlate'] ?? '';
        _model.text = d.vehicle['carModel'] ?? '';
        _license.text = d.vehicle['driverLicenseNo'] ?? '';
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  bool get _needsVehicle => _picked.any(CourierScopes.reviewed.contains);

  bool get _vehicleComplete =>
      _hasCar &&
      _plate.text.trim().length >= 2 &&
      _model.text.trim().length >= 2 &&
      _license.text.trim().length >= 2;

  Future<void> _save() async {
    if (_picked.isEmpty) {
      setState(() => _error = context.tr('courier_scope_err_pick_one'));
      return;
    }
    if (_needsVehicle && !_vehicleComplete) {
      setState(() => _error = context.tr('courier_scope_err_vehicle'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_needsVehicle) {
        await _repo.saveVehicle(widget.uid, {
          'vehicleType': 'car',
          'carPlate': _plate.text.trim(),
          'carModel': _model.text.trim(),
          'driverLicenseNo': _license.text.trim(),
        });
      }
      await _repo.requestScopes(
        CourierScopes.all.where(_picked.contains).toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('courier_scope_saved')),
        behavior: SnackBarBehavior.floating,
      ));
      await _load();
    } on FirebaseFunctionsException catch (e) {
      final key = switch (e.message) {
        'SCOPE_REQUIREMENTS_MISSING' => 'courier_scope_err_vehicle',
        'COURIER_NOT_WORKING' || 'NOT_A_COURIER' => 'courier_scope_err_not_working',
        _ => 'courier_scope_err_save',
      };
      if (mounted) setState(() => _error = context.tr(key));
    } catch (_) {
      if (mounted) setState(() => _error = context.tr('courier_scope_err_save'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _statusChip(String scope) {
    final st = _data?.review[scope] ?? '';
    if (st.isEmpty || !(_data?.scopes.contains(scope) ?? false)) {
      return const SizedBox.shrink();
    }
    final (color, key) = switch (st) {
      'approved' => (AvaLight.ok, 'courier_scope_status_approved'),
      'rejected' => (Colors.red.shade700, 'courier_scope_status_rejected'),
      _ => (Colors.orange.shade800, 'courier_scope_status_pending'),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        context.tr(key),
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _scopeTile(String scope) {
    return CheckboxListTile(
      value: _picked.contains(scope),
      onChanged: _saving
          ? null
          : (v) => setState(() {
                if (v == true) {
                  _picked.add(scope);
                } else {
                  _picked.remove(scope);
                }
                _error = null;
              }),
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        context.tr('courier_scope_$scope'),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('courier_scope_${scope}_desc')),
          _statusChip(scope),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String labelKey) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        enabled: !_saving,
        maxLength: 40,
        textCapitalization: TextCapitalization.characters,
        onChanged: (_) => setState(() => _error = null),
        decoration: InputDecoration(
          labelText: context.tr(labelKey),
          counterText: '',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text(context.tr('courier_scope_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(context.tr('courier_scope_err_load')),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: Text(context.tr('courier_refresh')),
                    ),
                  ]),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        context.tr('courier_scope_hint'),
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final s in CourierScopes.all) _scopeTile(s),
                    if (!_picked.contains('district') && _picked.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: Text(
                          context.tr('courier_scope_district_off_note'),
                          style: TextStyle(fontSize: 13, color: Colors.orange.shade900),
                        ),
                      ),
                    if (_needsVehicle) ...[
                      const Divider(height: 32),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              context.tr('courier_scope_vehicle_title'),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _hasCar,
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(() {
                                        _hasCar = v;
                                        _error = null;
                                      }),
                              title: Text(context.tr('courier_scope_has_car')),
                            ),
                            if (_hasCar) ...[
                              _field(_plate, 'courier_scope_car_plate'),
                              _field(_model, 'courier_scope_car_model'),
                              _field(_license, 'courier_scope_license_no'),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(backgroundColor: AppColors.primaryDark),
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Text(context.tr('courier_scope_save')),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
