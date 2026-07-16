import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/oil_vehicle.dart';
import '../../../repositories/oil_change_repository.dart';
import '../../../repositories/oil_catalog_repository.dart';
import '../../../repositories/user_repository.dart';
import '../../../services/oil_change_service.dart';
import '../data/oil_car_options.dart';
import '../data/oil_catalog.dart';
import '../widgets/oil_hub_widgets.dart';

/// Confidence B: марка/модель/йил/двигатель + ёқилғи/фойдаланиш.
class OilCarSetupScreen extends StatefulWidget {
  const OilCarSetupScreen({
    super.key,
    required this.uid,
    this.vehicle,
  });

  final String uid;
  final OilVehicle? vehicle;

  @override
  State<OilCarSetupScreen> createState() => _OilCarSetupScreenState();
}

class _OilCarSetupScreenState extends State<OilCarSetupScreen> {
  final _repo = OilChangeRepository();
  int _step = 0;
  bool _saving = false;

  late String _brand;
  late String _model;
  late int _year;
  late String _engine;
  String _fuel = 'cng';
  final Set<String> _usage = {'taxi'};
  late final TextEditingController _modelFreeCtrl;

  String _color = '';
  String _plate = '';
  int _seats = 4;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle;
    _brand = (v?.brand.isNotEmpty == true)
        ? v!.brand
        : OilCarOptions.brands.first;
    _model = (v?.model.isNotEmpty == true)
        ? v!.model
        : OilCarOptions.models.first;
    _year = (v != null && v.year > 0) ? v.year : OilCarOptions.years[2];
    _engine = (v?.engine.isNotEmpty == true)
        ? v!.engine
        : OilCarOptions.engines[1];
    _modelFreeCtrl = TextEditingController(text: _model);
    if (v != null) {
      if (v.fuelType.isNotEmpty) _fuel = v.fuelType;
      if (v.usageTags.isNotEmpty) {
        _usage
          ..clear()
          ..addAll(v.usageTags);
      }
      _color = v.color;
      _plate = v.plate;
      _seats = v.seats > 0 ? v.seats : 4;
    } else {
      _prefillProfile();
    }
    if (!OilCarOptions.brands.contains(_brand)) {
      _brand = OilCarOptions.brands.first;
    }
    if (!OilCarOptions.engines.contains(_engine)) {
      _engine = OilCarOptions.engines[1];
    }
  }

  @override
  void dispose() {
    _modelFreeCtrl.dispose();
    super.dispose();
  }

  Future<void> _prefillProfile() async {
    final car = await UserRepository().getCarInfo(widget.uid);
    if (car == null || !mounted) return;
    setState(() {
      final brand = (car['carBrand'] ?? '').trim();
      if (brand.isNotEmpty && OilCarOptions.brands.contains(brand)) {
        _brand = brand;
      }
      final m = (car['carModel'] ?? '').trim();
      if (m.isNotEmpty) {
        _model = m;
        _modelFreeCtrl.text = m;
      }
      final year = int.tryParse(car['carYear'] ?? '');
      if (year != null && OilCarOptions.years.contains(year)) _year = year;
      final engine = (car['carEngine'] ?? '').trim();
      if (engine.isNotEmpty && OilCarOptions.engines.contains(engine)) {
        _engine = engine;
      }
      final fuel = (car['carFuelType'] ?? '').trim();
      if (fuel.isNotEmpty) _fuel = fuel;
      final tags = (car['carUsageTags'] ?? '')
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (tags.isNotEmpty) {
        _usage
          ..clear()
          ..addAll(tags);
      }
      _color = (car['carColor'] ?? '').trim();
      _plate = (car['carPlate'] ?? '').trim();
      final seats = int.tryParse(car['carSeats'] ?? '');
      if (seats != null && seats > 0) _seats = seats;
    });
  }

  String _previewOil(BuildContext context) {
    final gas = _fuel == 'cng' || _fuel == 'lpg';
    final heavy = _usage.contains('taxi') ||
        _usage.contains('dust') ||
        _usage.contains('long');
    if (gas || heavy) return context.tr('oil_preview_gas_heavy');
    return context.tr('oil_preview_normal');
  }

  String _previewWhy(BuildContext context) {
    final gas = _fuel == 'cng' || _fuel == 'lpg';
    if (gas && _usage.contains('taxi')) {
      return context.tr('oil_preview_why_cng_taxi');
    }
    if (gas) return context.tr('oil_preview_why_gas');
    if (_usage.contains('taxi')) return context.tr('oil_preview_why_taxi');
    return context.tr('oil_preview_why_normal');
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final prev = widget.vehicle;
      final color = _color.isNotEmpty ? _color : '—';
      final plate = _plate.isNotEmpty
          ? _plate
          : 'TMP${DateTime.now().millisecondsSinceEpoch % 100000}';

      final intervalKm = (_fuel == 'cng' || _fuel == 'lpg' || _usage.contains('taxi'))
          ? 7000
          : 10000;

      final vehicle = OilVehicle(
        id: prev?.id ?? '',
        brand: _brand,
        model: _model,
        color: color,
        plate: plate,
        year: _year,
        engine: _engine,
        fuelType: _fuel,
        usageTags: _usage.toList(),
        seats: _seats,
        oilType: prev?.oilType ?? '',
        lastChangedAt: prev?.lastChangedAt,
        lastOdometerKm: prev?.lastOdometerKm ?? 0,
        currentOdometerKm: prev?.currentOdometerKm ?? 0,
        intervalKm: prev?.hasOilTracking == true ? prev!.intervalKm : intervalKm,
        intervalMonths: prev?.intervalMonths ?? 6,
        isPrimary: prev?.isPrimary ?? true,
      );

      final id = await _repo.saveVehicle(uid: widget.uid, vehicle: vehicle);
      final saved = vehicle.copyWith(id: id);
      await OilChangeService.scheduleDueReminder(saved);

      if (prev == null &&
          _color.isNotEmpty &&
          _plate.isNotEmpty &&
          _seats > 0) {
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
    return Scaffold(
      backgroundColor: oilHubBg,
      appBar: AppBar(
        title: Text(context.tr('oil_setup_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Row(
            children: [
              _stepDot(0),
              const SizedBox(width: 8),
              _stepDot(1),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _step == 0
                ? context.tr('oil_setup_step1')
                : context.tr('oil_setup_step2'),
            style: const TextStyle(color: oilHubMuted, height: 1.3),
          ),
          const SizedBox(height: 14),
          if (_step == 0) ..._step1() else ..._step2(),
        ],
      ),
    );
  }

  Widget _stepDot(int i) {
    final on = _step == i;
    return Expanded(
      child: Container(
        height: 5,
        decoration: BoxDecoration(
          color: on ? AppColors.primary : const Color(0xFFD5E5D6),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }

  List<Widget> _step1() {
    return [
      _dropdown<String>(
        context.tr('oil_brand'),
        _brand,
        OilCarOptions.brands,
        (v) => setState(() => _brand = v!),
      ),
      if (OilCarOptions.models.contains(_model))
        _dropdown<String>(
          context.tr('oil_model'),
          _model,
          OilCarOptions.models,
          (v) => setState(() {
            _model = v!;
            _modelFreeCtrl.text = v;
          }),
        )
      else
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: _modelFreeCtrl,
            onChanged: (v) => _model = v,
            decoration: InputDecoration(
              labelText: context.tr('oil_model'),
              filled: true,
              fillColor: Colors.white,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      _dropdown<int>(
        context.tr('oil_year'),
        OilCarOptions.years.contains(_year) ? _year : OilCarOptions.years.first,
        OilCarOptions.years,
        (v) => setState(() => _year = v!),
      ),
      _dropdown<String>(
        context.tr('oil_engine'),
        OilCarOptions.engines.contains(_engine)
            ? _engine
            : OilCarOptions.engines[1],
        OilCarOptions.engines,
        (v) => setState(() => _engine = v!),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: () {
          final free = _modelFreeCtrl.text.trim();
          if (free.isNotEmpty) _model = free;
          if (_model.trim().isEmpty) _model = OilCarOptions.models.first;
          setState(() => _step = 1);
        },
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          minimumSize: const Size.fromHeight(50),
        ),
        child: Text(context.tr('oil_continue_conditions')),
      ),
    ];
  }

  List<Widget> _step2() {
    return [
      Text(
        context.tr('oil_fuel'),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          _fuelChip('petrol', context.tr('oil_fuel_petrol')),
          _fuelChip('cng', context.tr('oil_fuel_cng')),
          _fuelChip('lpg', context.tr('oil_fuel_lpg')),
        ],
      ),
      const SizedBox(height: 16),
      Text(
        context.tr('oil_usage'),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _usageChip('personal', context.tr('oil_usage_personal')),
          _usageChip('taxi', context.tr('oil_usage_taxi')),
          _usageChip('corp', context.tr('oil_usage_corp')),
          _usageChip('dust', context.tr('oil_usage_dust')),
          _usageChip('long', context.tr('oil_usage_long')),
        ],
      ),
      const SizedBox(height: 16),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF6EB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFB7DFB9)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('oil_preview'),
              style: const TextStyle(
                color: Color(0xFF1B7A28),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _previewOil(context),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: oilHubInk,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _previewWhy(context),
              style: const TextStyle(color: oilHubMuted),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: () => setState(() => _step = 0),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: Text(context.tr('oil_back_to_model')),
      ),
      const SizedBox(height: 8),
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
    ];
  }

  Widget _fuelChip(String key, String label) {
    final on = _fuel == key;
    return ChoiceChip(
      label: Text(label),
      selected: on,
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        color: on ? Colors.white : oilHubInk,
        fontWeight: FontWeight.w700,
      ),
      onSelected: (_) => setState(() => _fuel = key),
    );
  }

  Widget _usageChip(String key, String label) {
    final on = _usage.contains(key);
    return FilterChip(
      label: Text(label),
      selected: on,
      selectedColor: AppColors.primary.withValues(alpha: 0.2),
      checkmarkColor: AppColors.primary,
      onSelected: (v) {
        setState(() {
          if (v) {
            _usage.add(key);
          } else if (_usage.length > 1) {
            _usage.remove(key);
          }
        });
      },
    );
  }

  Widget _dropdown<T>(
    String label,
    T value,
    List<T> items,
    ValueChanged<T?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: items.contains(value) ? value : items.first,
            isExpanded: true,
            items: items
                .map((e) => DropdownMenuItem(value: e, child: Text('$e')))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

/// Тўлиқ галерея — Мойлар / Фильтрлар таблари, вертикал скролл.
class OilGalleryScreen extends StatefulWidget {
  const OilGalleryScreen({super.key});

  @override
  State<OilGalleryScreen> createState() => _OilGalleryScreenState();
}

class _OilGalleryScreenState extends State<OilGalleryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _repo = OilCatalogRepository();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: oilHubBg,
      appBar: AppBar(
        title: Text(context.tr('oil_gallery_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: [
            Tab(text: context.tr('oil_oils')),
            Tab(text: context.tr('oil_filters')),
          ],
        ),
      ),
      body: StreamBuilder<List<OilProduct>>(
        stream: _repo.watchActive(),
        builder: (context, snap) {
          final catalog = OilCatalogRepository.resolveCatalog(snap.data);
          final oils = catalog.where((p) => p.isOil).toList();
          final filters = catalog.where((p) => p.isFilter).toList();
          return TabBarView(
            controller: _tabs,
            children: [
              _GalleryGrid(products: oils),
              _GalleryGrid(products: filters),
            ],
          );
        },
      ),
    );
  }
}

class _GalleryGrid extends StatelessWidget {
  const _GalleryGrid({required this.products});

  final List<OilProduct> products;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return Center(
        child: Text(
          context.tr('oil_ref_empty'),
          style: const TextStyle(color: oilHubMuted),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: products.length,
      itemBuilder: (_, i) => Align(
        alignment: Alignment.topCenter,
        child: OilProductCard(product: products[i]),
      ),
    );
  }
}

/// Мой турлари (HTML #oilTypes): оддий статик карталар — карта босилса,
/// содда тилдаги батафсил мақола очилади (showOilTypeDetail).
class OilTypesScreen extends StatelessWidget {
  const OilTypesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // HTML tartibi: Mineral → Semi → Full.
    const order = ['mineral', 'semi', 'full'];
    final types = [
      for (final k in order) OilCatalog.types.firstWhere((t) => t.key == k),
    ];
    return Scaffold(
      backgroundColor: oilHubBg,
      appBar: AppBar(
        title: Text(context.tr('oil_types_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Text(
            context.tr('oil_types_hint'),
            style: const TextStyle(
              color: oilHubMuted,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          for (final t in types) ...[
            _OilTypeCard(type: t),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 2),
          Text(
            context.tr('oil_fine_print'),
            style: const TextStyle(
              fontSize: 11.5,
              color: oilHubMuted,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _OilTypeCard extends StatelessWidget {
  const _OilTypeCard({required this.type});

  final OilTypeInfo type;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showOilTypeDetail(context, type),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD5E5D6)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      type.title(context),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                        color: oilHubInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    type.km(context),
                    style: const TextStyle(
                      color: Color(0xFF1B7A28),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                type.short(context),
                style: const TextStyle(
                  height: 1.35,
                  color: oilHubInk,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${context.tr('oil_tap_read')} →',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
