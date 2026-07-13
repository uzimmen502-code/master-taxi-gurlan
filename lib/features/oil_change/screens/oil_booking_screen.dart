import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/oil_vehicle.dart';
import '../../../repositories/oil_change_repository.dart';
import '../../../repositories/settings_repository.dart';

class OilBookingScreen extends StatefulWidget {
  const OilBookingScreen({
    super.key,
    required this.uid,
    required this.vehicle,
  });

  final String uid;
  final OilVehicle vehicle;

  @override
  State<OilBookingScreen> createState() => _OilBookingScreenState();
}

class _OilBookingScreenState extends State<OilBookingScreen> {
  final _repo = OilChangeRepository();
  List<OilPricePackage> _packages = OilPricePackage.defaults;
  List<OilServicePoint> _points = const [];
  OilPricePackage? _package;
  OilServicePoint? _point;
  DateTime? _slot;
  bool _loading = true;
  bool _submitting = false;
  String _name = '';
  String _phone = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final packages = await _repo.loadPricePackages();
    final points = await _repo.watchServicePoints().first;
    var list = points;
    if (list.isEmpty) {
      final phone = await SettingsRepository().getDispatcherPhone();
      if (!mounted) return;
      list = [
        OilServicePoint(
          id: 'default_gurlan',
          name: context.tr('oil_service_default_name'),
          phone: phone,
          address: context.tr('oil_service_default_address'),
        ),
      ];
    }
    if (!mounted) return;
    setState(() {
      _packages = packages;
      _points = list;
      _package = packages.isNotEmpty ? packages.first : null;
      _point = list.isNotEmpty ? list.first : null;
      _name = prefs.getString('user_name') ?? '';
      _phone = phoneDigits(prefs.getString('user_phone') ?? '');
      _loading = false;
    });
  }

  Future<void> _pickSlot() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
    );
    if (time == null) return;
    setState(() {
      _slot = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    if (_package == null || _point == null || _slot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('oil_book_pick_all'))),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await _repo.createBooking(
        uid: widget.uid,
        vehicle: widget.vehicle,
        package: _package!,
        point: _point!,
        slotAt: _slot!,
        phone: _phone,
        name: _name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('oil_book_ok'))),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('oil_book_error').replaceAll('{error}', '$e'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _packageSubtitle(OilPricePackage p) {
    return '${p.description} · ${context.tr('oil_price_from').replaceAll('{price}', formatPrice(p.priceFrom))}';
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('oil_book_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.vehicle.displayTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  context.tr('oil_package'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                ..._packages.map(
                  (p) => RadioListTile<OilPricePackage>(
                    value: p,
                    groupValue: _package,
                    onChanged: (v) => setState(() => _package = v),
                    title: Text(p.name),
                    subtitle: Text(_packageSubtitle(p)),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('oil_point'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                ..._points.map(
                  (p) => RadioListTile<OilServicePoint>(
                    value: p,
                    groupValue: _point,
                    onChanged: (v) => setState(() => _point = v),
                    title: Text(p.name),
                    subtitle: Text(p.address),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _slot == null
                        ? context.tr('oil_pick_time')
                        : df.format(_slot!),
                  ),
                  trailing: const Icon(Icons.schedule),
                  onTap: _pickSlot,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(context.tr('oil_confirm_book')),
                ),
              ],
            ),
    );
  }
}
