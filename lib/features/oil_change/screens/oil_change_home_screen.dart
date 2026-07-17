import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/oil_vehicle.dart';
import '../../../repositories/oil_change_repository.dart';
import '../../../repositories/oil_catalog_repository.dart';
import '../data/oil_car_data.dart';
import '../data/oil_catalog.dart';
import '../data/oil_l10n.dart';
import '../widgets/oil_hub_widgets.dart';
import 'oil_car_setup_screen.dart';
import 'oil_history_screen.dart';
import 'oil_prices_screen.dart';
import 'oil_ref_screen.dart';
import 'oil_services_screen.dart';
import 'oil_vehicle_edit_screen.dart';

/// Мой алмаштириш — прототип B хаб (AVA → авто → тур → галерея → премиум/оптимал/мақбул).
class OilChangeHomeScreen extends StatefulWidget {
  const OilChangeHomeScreen({super.key});

  @override
  State<OilChangeHomeScreen> createState() => _OilChangeHomeScreenState();
}

class _OilChangeHomeScreenState extends State<OilChangeHomeScreen> {
  final _repo = OilChangeRepository();
  final _catalogRepo = OilCatalogRepository();
  String _uid = '';
  bool _ready = false;
  OilVehicle? _selected;
  bool _didPromptSetup = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = phoneDigits(prefs.getString('user_phone') ?? '');
    if (uid.length >= 9) {
      await _repo.ensureFromProfile(uid);
    }
    if (!mounted) return;
    setState(() {
      _uid = uid;
      _ready = true;
    });
  }

  Future<void> _openSetup({OilVehicle? vehicle}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => OilCarSetupScreen(uid: _uid, vehicle: vehicle),
      ),
    );
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _openEdit({OilVehicle? vehicle}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => OilVehicleEditScreen(uid: _uid, vehicle: vehicle),
      ),
    );
    if (saved == true && mounted) setState(() {});
  }

  OilVehicle _pickSelected(List<OilVehicle> vehicles) {
    if (_selected != null) {
      for (final v in vehicles) {
        if (v.id == _selected!.id) return v;
      }
    }
    return vehicles.firstWhere((v) => v.isPrimary, orElse: () => vehicles.first);
  }

  void _maybePromptSetup(List<OilVehicle> vehicles) {
    if (_didPromptSetup || vehicles.isEmpty) return;
    final v = _pickSelected(vehicles);
    if (v.isRecommendationReady) return;
    _didPromptSetup = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openSetup(vehicle: v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: oilHubBg,
      appBar: AppBar(
        title: Text(context.tr('oil_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: context.tr('oil_setup'),
            onPressed: !_ready || _uid.length < 9
                ? null
                : () => _openSetup(vehicle: _selected),
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: context.tr('oil_prices'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OilPricesScreen()),
            ),
            icon: const Icon(Icons.sell_outlined),
          ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : _uid.length < 9
              ? Center(child: Text(context.tr('oil_fill_phone_first')))
              : StreamBuilder<List<OilVehicle>>(
                  stream: _repo.watchVehicles(_uid),
                  builder: (context, snap) {
                    final vehicles = snap.data ?? const <OilVehicle>[];
                    if (snap.connectionState == ConnectionState.waiting &&
                        !snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (vehicles.isEmpty) {
                      return _emptyState();
                    }
                    final selected = _pickSelected(vehicles);
                    _selected = selected;
                    _maybePromptSetup(vehicles);
                    return StreamBuilder<List<OilProduct>>(
                      stream: _catalogRepo.watchActive(),
                      builder: (context, catSnap) {
                        final catalog =
                            OilCatalogRepository.resolveCatalog(catSnap.data);
                        return _hub(selected, vehicles, catalog);
                      },
                    );
                  },
                ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.directions_car_filled_outlined,
              size: 72, color: AppColors.primary),
          const SizedBox(height: 16),
          Text(
            context.tr('oil_my_car'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: oilHubInk,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('oil_my_car_hint'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: oilHubMuted, height: 1.35),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => _openSetup(),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(context.tr('oil_my_car_setup_cta')),
          ),
        ],
      ),
    );
  }

  Widget _hub(
    OilVehicle selected,
    List<OilVehicle> vehicles,
    List<OilProduct> catalog,
  ) {
    final preview = OilCatalog.hubGalleryPreviewFrom(catalog);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        if (vehicles.length > 1) ...[
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: vehicles.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final v = vehicles[i];
                final on = v.id == selected.id;
                return ChoiceChip(
                  label: Text(
                    v.plate.isNotEmpty ? v.plate : v.model,
                    style: TextStyle(
                      color: on ? Colors.white : oilHubInk,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  selected: on,
                  selectedColor: AppColors.primary,
                  onSelected: (_) => setState(() => _selected = v),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
        _carBlock(selected),
        const SizedBox(height: 16),
        _doctorOilSectionTitle(),
        const SizedBox(height: 8),
        _mileageRecoTable(),
        const SizedBox(height: 10),
        _oilTypesCompact(),
        const SizedBox(height: 16),
        _sectionTitle(
          context.tr('oil_section_gallery'),
          context.tr('oil_section_gallery_hint'),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: preview.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => OilProductCard(product: preview[i]),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OilGalleryScreen()),
          ),
          child: Text(context.tr('oil_full_gallery')),
        ),
        const SizedBox(height: 8),
        _sectionTitle(context.tr('oil_section_reco')),
        const SizedBox(height: 8),
        _reco(selected, catalog),
        const SizedBox(height: 12),
        _linkTile(
          Icons.menu_book_outlined,
          context.tr('oil_ref_guide'),
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OilRefScreen(
                uid: _uid,
                initialVehicleId: selected.id,
              ),
            ),
          ),
        ),
        _linkTile(
          Icons.history,
          context.tr('oil_history'),
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  OilHistoryScreen(uid: _uid, vehicle: selected),
            ),
          ),
        ),
        _linkTile(
          Icons.storefront_outlined,
          context.tr('oil_service_points'),
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OilServicesScreen()),
          ),
        ),
        _linkTile(
          Icons.edit_outlined,
          context.tr('oil_odometer_edit'),
          () => _openEdit(vehicle: selected),
        ),
      ],
    );
  }

  Widget _carBlock(OilVehicle v) {
    if (!v.isRecommendationReady) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD5E5D6)),
        ),
        child: Row(
          children: [
            const Text('🚗', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('oil_my_car'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    context.tr('oil_my_car_hint'),
                    style: const TextStyle(fontSize: 12.5, color: oilHubMuted),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: () => _openSetup(vehicle: v),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text(context.tr('oil_setup')),
            ),
          ],
        ),
      );
    }

    final cap = OilCarData.resolveCapacity(v.model, engine: v.engine);
    final fuelKey = v.fuelType.trim().toLowerCase();
    final fuel = fuelKey.isEmpty
        ? ''
        : context.tr('oil_fuel_$fuelKey');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD5E5D6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  v.setupTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: oilHubInk,
                    height: 1.15,
                    letterSpacing: -0.25,
                  ),
                ),
              ),
              if (fuel.isNotEmpty) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    fuel,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1B5E20),
                      height: 1,
                    ),
                  ),
                ),
              ],
              IconButton(
                onPressed: () => _openSetup(vehicle: v),
                tooltip: context.tr('oil_edit_car'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                iconSize: 15,
                color: const Color(0xFF2E7D32),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          if (cap != null) ...[
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFD7E8D8)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Expanded(
                        child: _capCell(
                          context.tr('oil_capacity_crankcase_short'),
                          cap.oilCapacity,
                        ),
                      ),
                      Container(width: 1, color: const Color(0xFFE8F0E8)),
                      Expanded(
                        child: _capCell(
                          context.tr('oil_capacity_filter_short'),
                          cap.filterCapacity,
                        ),
                      ),
                      Container(width: 1, color: const Color(0xFFE8F0E8)),
                      Expanded(
                        child: _capCell(
                          context.tr('oil_capacity_total_label'),
                          cap.total,
                          emphasize: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _capCell(String label, String liters, {bool emphasize = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      color: emphasize ? const Color(0xFF2E7D32) : const Color(0xFFF7FAF7),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              height: 1,
              color: emphasize
                  ? Colors.white.withValues(alpha: 0.85)
                  : oilHubMuted,
            ),
          ),
          const SizedBox(height: 3),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: liters,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    letterSpacing: -0.2,
                    color: emphasize ? Colors.white : oilHubInk,
                  ),
                ),
                TextSpan(
                  text: ' L',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: emphasize
                        ? Colors.white.withValues(alpha: 0.8)
                        : oilHubMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mileageRecoTable() {
    final lang = oilLangOf(context);
    final rows = OilCarData.mileageRecos;
    final normal = rows.where((r) => !r.warn).toList();
    final warn = rows.where((r) => r.warn).toList();

    TextStyle headStyle({Color? color}) => TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          height: 1.15,
          color: color ?? oilHubMuted,
          letterSpacing: -0.1,
        );
    TextStyle cellStyle({
      Color? color,
      FontWeight weight = FontWeight.w700,
    }) =>
        TextStyle(
          fontSize: 11,
          fontWeight: weight,
          height: 1.2,
          color: color ?? oilHubInk,
          letterSpacing: -0.15,
        );

    TableRow buildHeader() => TableRow(
          decoration: const BoxDecoration(
            color: Color(0xFFEEF6EF),
          ),
          children: [
            _mileagePad(
              Text(context.tr('oil_mileage_col_km'), style: headStyle()),
              first: true,
            ),
            _mileagePad(
              Text(
                context.tr('oil_mileage_col_healthy_short'),
                style: headStyle(color: const Color(0xFF2E7D32)),
              ),
            ),
            _mileagePad(
              Text(
                context.tr('oil_mileage_col_neglected_short'),
                style: headStyle(color: const Color(0xFFEF6C00)),
              ),
              last: true,
            ),
          ],
        );

    TableRow buildRow(MileageReco r, {required bool zebra}) => TableRow(
          decoration: BoxDecoration(
            color: zebra ? const Color(0xFFF7FAF7) : Colors.white,
          ),
          children: [
            _mileagePad(
              Text(
                r.range.t(lang),
                style: cellStyle(
                  color: const Color(0xFF1B5E20),
                  weight: FontWeight.w800,
                ),
              ),
              first: true,
            ),
            _mileagePad(Text(r.healthy.t(lang), style: cellStyle())),
            _mileagePad(Text(r.neglected.t(lang), style: cellStyle()), last: true),
          ],
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD5E5D6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('oil_mileage_reco_title'),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: oilHubInk,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            context.tr('oil_mileage_reco_hint'),
            style: const TextStyle(
              fontSize: 10,
              height: 1.25,
              color: oilHubMuted,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD7E8D8)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(1.05),
                  1: FlexColumnWidth(1),
                  2: FlexColumnWidth(1),
                },
                border: TableBorder(
                  horizontalInside: BorderSide(
                    color: const Color(0xFFE8F0E8),
                    width: 1,
                  ),
                  verticalInside: BorderSide(
                    color: const Color(0xFFE8F0E8),
                    width: 1,
                  ),
                ),
                children: [
                  buildHeader(),
                  ...normal.asMap().entries.map(
                        (e) => buildRow(e.value, zebra: e.key.isOdd),
                      ),
                ],
              ),
            ),
          ),
          ...warn.map(
            (r) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFCC80)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      r.range.t(lang),
                      style: cellStyle(
                        color: const Color(0xFFE65100),
                        weight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    r.healthy.t(lang),
                    style: cellStyle(
                      color: const Color(0xFFBF360C),
                      weight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mileagePad(
    Widget child, {
    bool first = false,
    bool last = false,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(first ? 8 : 6, 6, last ? 8 : 6, 6),
      child: child,
    );
  }

  Widget _oilTypesCompact() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD5E5D6)),
      ),
      child: OilSequentialBarsTicker(
        builder: (context, phaseOf) {
          return Column(
            children: [
              ...OilCatalog.types.asMap().entries.map((e) {
                final i = e.key;
                final t = e.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () => showOilTypeDetail(context, t),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  t.title(context),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                              Text(
                                oilAnimatedKmLabel(context, t, phaseOf(i)),
                                style: const TextStyle(
                                  color: Color(0xFF1B7A28),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          OilTypeBar(
                            phase: phaseOf(i),
                            variant: oilBarVariantFor(t.key),
                            showLegend: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              Text(
                context.tr('oil_fine_print'),
                style: const TextStyle(
                  fontSize: 11,
                  color: oilHubMuted,
                  height: 1.3,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const OilTypesScreen()),
                  ),
                  child: Text(context.tr('oil_more_detail')),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _reco(OilVehicle v, List<OilProduct> catalog) {
    if (!v.isRecommendationReady) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F6F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD5E5D6)),
        ),
        child: Column(
          children: [
            Text(
              context.tr('oil_reco_locked'),
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.4, color: oilHubInk),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _openSetup(vehicle: v),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text(context.tr('oil_my_car_setup_cta')),
            ),
          ],
        ),
      );
    }

    final reco = OilCatalog.recommend(
      fuelType: v.fuelType,
      usageTags: v.usageTags,
      catalog: catalog,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          reco.intro(context),
          style: const TextStyle(color: oilHubMuted, height: 1.35),
        ),
        const SizedBox(height: 12),
        _recoTierRow(
          label: context.tr('oil_tier_premium'),
          products: reco.premium,
        ),
        const SizedBox(height: 12),
        _recoTierRow(
          label: context.tr('oil_tier_optimal'),
          products: reco.optimal,
        ),
        const SizedBox(height: 12),
        _recoTierRow(
          label: context.tr('oil_tier_acceptable'),
          products: reco.acceptable,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            context.tr('oil_choice_yours'),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: oilHubMuted,
              fontSize: 12.5,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD5E5D6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('oil_with_oil_reco'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ...reco.bundle.map((f) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    f.displayName(context),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(f.displayMeta(context)),
                  trailing: Text(
                    context.tr('oil_price_from').replaceAll(
                          '{price}',
                          formatPrice(f.price),
                        ),
                    style: const TextStyle(
                      color: oilHubViolet,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  onTap: () => showOilProductSheet(context, f),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _recoTierRow({
    required String label,
    required List<OilProduct> products,
  }) {
    if (products.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
            color: oilHubInk,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              return OilProductCard(product: products[i]);
            },
          ),
        ),
      ],
    );
  }

  Widget _doctorOilSectionTitle() {
    const base = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w800,
      height: 1.2,
      letterSpacing: 0,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE8F5E9), Color(0xFFE3F2FD)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFB7DFB9)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (context.tr('oil_section_types_prefix').isNotEmpty) ...[
              Text(
                context.tr('oil_section_types_prefix').trimRight(),
                style: base.copyWith(color: oilHubInk),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              '«DOCTOR OIL»',
              style: base.copyWith(color: const Color(0xFF2E7D32)),
            ),
            const SizedBox(width: 5),
            Text(
              context.tr('oil_section_types_mid').trim(),
              style: base.copyWith(color: oilHubInk),
            ),
            const SizedBox(width: 5),
            Text(
              'Chevrolet',
              style: base.copyWith(
                color: const Color(0xFF1565C0),
                fontWeight: FontWeight.w900,
              ),
            ),
            if (context.tr('oil_section_types_end').trim().isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(
                context.tr('oil_section_types_end').trim(),
                style: base.copyWith(color: oilHubInk),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, [String? hint]) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ),
        if (hint != null && hint.isNotEmpty)
          Text(hint, style: const TextStyle(fontSize: 11.5, color: oilHubMuted)),
      ],
    );
  }

  Widget _linkTile(IconData icon, String title, VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
