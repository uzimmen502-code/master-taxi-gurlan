import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/oil_vehicle.dart';
import '../../../repositories/oil_change_repository.dart';
import '../../../repositories/oil_catalog_repository.dart';
import '../data/oil_catalog.dart';
import '../widgets/oil_hub_widgets.dart';
import 'oil_booking_screen.dart';
import 'oil_car_setup_screen.dart';
import 'oil_history_screen.dart';
import 'oil_prices_screen.dart';
import 'oil_services_screen.dart';
import 'oil_vehicle_edit_screen.dart';

/// Мой алмаштириш — прототип B хаб (AVA → авто → тур → галерея → 1/2/3).
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

  Color _levelColor(OilDueLevel level) => switch (level) {
        OilDueLevel.ok => const Color(0xFF2E7D32),
        OilDueLevel.soon => const Color(0xFFF9A825),
        OilDueLevel.overdue => const Color(0xFFC62828),
      };

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
        _avaPromise(),
        const SizedBox(height: 12),
        _carBlock(selected),
        const SizedBox(height: 16),
        _sectionTitle(context.tr('oil_section_types')),
        const SizedBox(height: 8),
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
        _sectionTitle(
          context.tr('oil_section_reco'),
          context.tr('oil_section_reco_hint'),
        ),
        const SizedBox(height: 8),
        _reco(selected, catalog),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const OilDriverTipsScreen(),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(context.tr('oil_for_driver')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        OilBookingScreen(uid: _uid, vehicle: selected),
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(context.tr('oil_book')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 8),
        Text(
          context.tr('oil_disclaimer'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11.5, color: oilHubMuted, height: 1.35),
        ),
      ],
    );
  }

  Widget _avaPromise() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6EB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFB7DFB9)),
      ),
      child: Text(
        context.tr('oil_ava_promise_title'),
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15,
          color: oilHubInk,
          height: 1.25,
        ),
      ),
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

    final due = v.computeDueStatus();
    final color = _levelColor(due.level);
    final df = DateFormat('dd.MM.yyyy');
    String big;
    if (!v.hasOilTracking) {
      big = context.tr('oil_fill_tracking');
    } else {
      final parts = <String>[];
      if (due.kmLeft != null) {
        parts.add(due.kmLeft! > 0
            ? context.tr('oil_km_left').replaceAll(
                  '{km}',
                  formatPrice(due.kmLeft!),
                )
            : context.tr('oil_km_overdue'));
      }
      if (due.daysLeft != null) {
        parts.add(due.daysLeft! > 0
            ? context.tr('oil_days_left').replaceAll(
                  '{days}',
                  '${due.daysLeft}',
                )
            : context.tr('oil_date_overdue'));
      }
      big = parts.isEmpty ? due.levelLabelUz : parts.join(' · ');
    }
    final subParts = <String>[
      if (v.fuelLabelUz.isNotEmpty) v.fuelLabelUz,
      if (v.usageSummaryUz.isNotEmpty) v.usageSummaryUz,
      if (due.nextDate != null)
        context.tr('oil_next_date').replaceAll(
              '{date}',
              df.format(due.nextDate!),
            ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                v.setupTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: oilHubInk,
                ),
              ),
            ),
            ActionChip(
              label: Text(context.tr('oil_by_model')),
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(ctx.tr('oil_by_model')),
                    content: Text(ctx.tr('oil_by_model_body')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(ctx.tr('ok')),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  due.levelLabelUz,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                big,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: oilHubInk,
                ),
              ),
              if (subParts.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subParts.join(' · '),
                  style: const TextStyle(color: oilHubMuted, height: 1.3),
                ),
              ],
            ],
          ),
        ),
        TextButton(
          onPressed: () => _openSetup(vehicle: v),
          child: Text(context.tr('oil_edit_car')),
        ),
      ],
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
                            widthFraction: t.width,
                            phase: phaseOf(i),
                            variant: oilBarVariantFor(t.key),
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
        const SizedBox(height: 10),
        ...List.generate(reco.ranked.length, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OilRankCard(product: reco.ranked[i], rank: i + 1),
          );
        }),
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
