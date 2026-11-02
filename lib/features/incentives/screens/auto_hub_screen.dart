import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/geo/geo_context.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/map_launcher.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../models/oil_vehicle.dart';
import '../../../models/platform_product.dart';
import '../../../repositories/oil_change_repository.dart';
import '../../../repositories/platform_products_repository.dart';
import '../../../repositories/settings_repository.dart';
import '../../../repositories/user_repository.dart';
import '../../../shared/car/car_edit_dialog.dart';
import '../../ads/widgets/market_grid.dart';
import '../../ads/widgets/platform_market_card.dart';
import '../incentive_offers_flow.dart';
import '../incentive_service.dart';

/// «Менинг машинам» (аввалги «Авто шина» белгиси, эга 2026-11-02):
/// машина маълумоти · AVA бонуси (туркумлар бўйича) · AVA сервис (устунлик) · AVA дўконидаги
/// машина маҳсулотлари (шина, мой, аккумулятор, суғурта …). Бонус фақат AVA дўконида сарфланади —
/// ҳисоб серверда (`placeOrderPostPaid`), бу экран фақат кўрсатади.
const List<String> kAutoHubCategories = ['tire', 'oil', 'battery', 'insurance'];

/// Экрандаги маҳсулотлар: фаол, нархи бор, рағбат туркуми белгиланган.
/// [category] бўш — барча машина туркумлари.
@visibleForTesting
List<PlatformProduct> autoHubProducts(List<PlatformProduct> all, String category) {
  return [
    for (final p in all)
      if (p.active &&
          p.price > 0 &&
          p.incentiveCategory.isNotEmpty &&
          (category.isEmpty || p.incentiveCategory == category))
        p,
  ];
}

/// Грант қолдиқлари туркумлар бўйича йиғилган (фаол ва муддати ўтмаган).
@visibleForTesting
({Map<String, int> byCategory, DateTime? nearestExpiry}) autoHubBonusSummary(
  List<Map<String, dynamic>> grants,
  DateTime now,
) {
  final by = <String, int>{};
  DateTime? nearest;
  for (final g in grants) {
    if (g['status'] != 'active') continue;
    final exp = g['expiresAt'];
    final expAt = exp is Timestamp ? exp.toDate() : (exp is DateTime ? exp : null);
    if (expAt == null || !expAt.isAfter(now)) continue;
    final buckets = g['buckets'];
    if (buckets is! Map) continue;
    var added = false;
    for (final e in buckets.entries) {
      final v = e.value is num ? (e.value as num).toInt() : 0;
      if (v <= 0) continue;
      by['${e.key}'] = (by['${e.key}'] ?? 0) + v;
      added = true;
    }
    if (added && (nearest == null || expAt.isBefore(nearest))) nearest = expAt;
  }
  return (byCategory: by, nearestExpiry: nearest);
}

class AutoHubScreen extends StatefulWidget {
  const AutoHubScreen({super.key, required this.uid, this.initialCategory = ''});

  /// Телефон (исталган формат) — ичида `canonicalPhoneId`.
  final String uid;
  final String initialCategory;

  @override
  State<AutoHubScreen> createState() => _AutoHubScreenState();
}

class _AutoHubScreenState extends State<AutoHubScreen> {
  final _service = IncentiveService();
  late String _category =
      kAutoHubCategories.contains(widget.initialCategory) ? widget.initialCategory : '';
  late Future<Map<String, String>?> _car;
  late final Future<List<PlatformProduct>> _products = PlatformProductsRepository().fetchCatalog();
  /// Фаол (тепада кўрсатилган) туманнинг AVA Сервис маркази; йўқ бўлса — диспетчер телефони.
  late final Future<({OilServicePoint? center, String fallbackPhone})> _avaService = _loadService();

  Future<({OilServicePoint? center, String fallbackPhone})> _loadService() async {
    final results = await Future.wait<Object?>([
      OilChangeRepository().fetchAvaCenter(GeoContext.active.districtId),
      SettingsRepository().getDispatcherPhone(),
    ]);
    return (center: results[0] as OilServicePoint?, fallbackPhone: (results[1] as String?) ?? '');
  }
  late Future<List<IncentiveOffer>> _offers;

  String get _phone => canonicalPhoneId(widget.uid);

  @override
  void initState() {
    super.initState();
    _car = UserRepository().getCarInfo(_phone);
    _offers = _loadOffers();
  }

  Future<List<IncentiveOffer>> _loadOffers() async {
    try {
      return await _service.myOffers();
    } catch (e) {
      debugPrint('[AutoHub] offers: $e');
      return const [];
    }
  }

  Future<void> _editCar() async {
    final saved = await showCarEditDialog(context, uid: _phone);
    if (saved == true && mounted) {
      setState(() {
        _car = UserRepository().getCarInfo(_phone);
        _offers = _loadOffers();
      });
    }
  }

  Future<void> _takeBonus(IncentiveOffer o) async {
    await IncentiveOffersFlow.offerCar(context, _phone, o, service: _service);
    if (mounted) {
      setState(() {
        _car = UserRepository().getCarInfo(_phone);
        _offers = _loadOffers();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('auto_hub_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
      ),
      body: FutureBuilder<List<PlatformProduct>>(
        future: _products,
        builder: (context, snap) {
          final all = snap.data ?? const <PlatformProduct>[];
          final items = autoHubProducts(all, _category);
          final catalog = autoHubProducts(all, '');
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _carCard(context)),
              SliverToBoxAdapter(child: _bonusCard(context)),
              SliverToBoxAdapter(child: _serviceCard(context)),
              SliverToBoxAdapter(child: _chips(context)),
              if (snap.connectionState != ConnectionState.done)
                const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                )
              else if (items.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      context.tr('auto_hub_empty'),
                      key: const ValueKey('auto_hub_empty'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  sliver: SliverLayoutBuilder(
                    builder: (context, c) {
                      const spacing = 10.0;
                      final cell = (c.crossAxisExtent - spacing) / 2;
                      return SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: spacing,
                          crossAxisSpacing: spacing,
                          mainAxisExtent: MarketGridMetrics.cellExtent(context, cell),
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => PlatformMarketCard(product: items[i], catalog: catalog),
                          childCount: items.length,
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _section({required Widget child, Key? key}) => Card(
        key: key,
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(padding: const EdgeInsets.all(14), child: child),
      );

  Widget _carCard(BuildContext context) {
    return FutureBuilder<Map<String, String>?>(
      future: _car,
      builder: (context, snap) {
        final car = snap.data;
        final model = (car?['carModel'] ?? '').trim();
        final plate = (car?['carPlate'] ?? '').trim();
        final color = (car?['carColor'] ?? '').trim();
        final has = model.isNotEmpty;
        return _section(
          key: const ValueKey('auto_hub_car'),
          child: Row(
            children: [
              Icon(Icons.directions_car_filled, size: 34, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      has ? model : context.tr('auto_hub_car_none'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    if (has && (plate.isNotEmpty || color.isNotEmpty))
                      Text(
                        [plate, color].where((s) => s.isNotEmpty).join(' · '),
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                  ],
                ),
              ),
              TextButton(
                key: const ValueKey('auto_hub_car_edit'),
                onPressed: _editCar,
                child: Text(context.tr(has ? 'auto_hub_car_edit' : 'auto_hub_car_add')),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bonusCard(BuildContext context) {
    final grants = FirebaseFirestore.instance
        .collection('incentive_grants')
        .where('uid', isEqualTo: _phone)
        .where('status', isEqualTo: 'active');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: grants.snapshots(),
      builder: (context, gs) {
        final summary = autoHubBonusSummary(
          [for (final d in gs.data?.docs ?? const []) d.data()],
          DateTime.now(),
        );
        return FutureBuilder<List<IncentiveOffer>>(
          future: _offers,
          builder: (context, os) {
            final steps = planIncentiveSteps(os.data ?? const []);
            final offer = steps.carOffers.isNotEmpty
                ? steps.carOffers.first
                : (steps.autoClaim.isNotEmpty ? steps.autoClaim.first : null);
            if (summary.byCategory.isEmpty && offer == null) return const SizedBox.shrink();
            final exp = summary.nearestExpiry;
            return _section(
              key: const ValueKey('auto_hub_bonus'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.card_giftcard, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(context.tr('auto_hub_bonus_title'),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ],
                  ),
                  if (summary.byCategory.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final e in summary.byCategory.entries)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text('${_catLabel(context, e.key)}: ${formatPrice(e.value)}'),
                          ),
                      ],
                    ),
                    if (exp != null)
                      Text(
                        context.tr('auto_hub_bonus_until').replaceAll('{date}', _day(exp.toLocal())),
                        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                      ),
                  ],
                  if (offer != null) ...[
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      key: const ValueKey('auto_hub_take_bonus'),
                      onPressed: () => _takeBonus(offer),
                      icon: const Icon(Icons.redeem),
                      label: Text(context
                          .tr('auto_hub_take_bonus')
                          .replaceAll('{amount}', formatPrice(offer.amount))),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// AVA сервис — биринчи ўринда (эга 2026-11-02: «устунлик АВА сервисга йўналтиришга»).
  Widget _serviceCard(BuildContext context) {
    return FutureBuilder<({OilServicePoint? center, String fallbackPhone})>(
      future: _avaService,
      builder: (context, snap) {
        final center = snap.data?.center;
        final phone = (center != null && center.phone.trim().isNotEmpty
                ? center.phone
                : (snap.data?.fallbackPhone ?? ''))
            .trim();
        final name = center != null && center.name.trim().isNotEmpty
            ? center.name.trim()
            : context.tr('auto_hub_service_title');
        final address = center?.address.trim() ?? '';
        return _section(
          key: const ValueKey('auto_hub_service'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.build_circle, size: 34, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        Text(
                          address.isNotEmpty ? address : context.tr('auto_hub_service_sub'),
                          key: const ValueKey('auto_hub_service_address'),
                          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (phone.isNotEmpty || (center?.hasLocation ?? false)) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (phone.isNotEmpty)
                      FilledButton.tonalIcon(
                        key: const ValueKey('auto_hub_call'),
                        onPressed: () => callPhone(phone),
                        icon: const Icon(Icons.phone),
                        label: Text(context.tr('auto_hub_call')),
                      ),
                    if (center != null && center.hasLocation)
                      OutlinedButton.icon(
                        key: const ValueKey('auto_hub_route'),
                        onPressed: () => openMapsNavigation(lat: center.lat!, lng: center.lng!, label: name),
                        icon: const Icon(Icons.directions),
                        label: Text(context.tr('auto_hub_route')),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _chips(BuildContext context) {
    final cats = ['', ...kAutoHubCategories];
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        children: [
          for (final c in cats)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey('auto_hub_cat_${c.isEmpty ? 'all' : c}'),
                label: Text(c.isEmpty ? context.tr('auto_hub_all') : _catLabel(context, c)),
                selected: _category == c,
                onSelected: (_) => setState(() => _category = c),
              ),
            ),
        ],
      ),
    );
  }

  static String _day(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  String _catLabel(BuildContext context, String key) {
    if (key == 'any') return context.tr('auto_hub_bucket_any');
    if (kAutoHubCategories.contains(key)) return context.tr('auto_cat_$key');
    return key;
  }
}
