// Курьер — «Ресторан буюртмалари» (Б3, §12.9): яқиндаги олинмаган
// буюртмалар (`listNearbyRestaurantOrders` — проекция, мижоз телефони/манзили
// ЙЎҚ), «Олиш» (`courierClaimRestaurantOrder`, биринчи ғолиб) ва выкуп
// созламаси (`courierSetBuyoutPrefs`). Олинган буюртма курьернинг фаол
// маршрутига тушади — курьер панели уни ўзи кўрсатади.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../services/location_service.dart';
import '../../home/widgets/ava_chip.dart';
import '../data/restaurants_repository.dart';
import '../widgets/restaurant_checkout_sheet.dart' show restaurantsErrorText;
import '../widgets/restaurant_row.dart' show formatDistanceLabel;

typedef CourierLocate = Future<({double lat, double lng})?> Function();

class RestaurantNearbyOrdersScreen extends StatefulWidget {
  const RestaurantNearbyOrdersScreen({
    super.key,
    required this.courierUid,
    this.repository,
    this.locate,
  });

  /// Канон телефон ID (`998…`) — выкуп созламасини ўқиш учун.
  final String courierUid;
  final RestaurantsRepository? repository;

  /// Тестда алмаштириш учун; стандарт — [LocationService.getCurrentCoords]
  /// (GPS йўқ бўлса рўйхат масофасиз, сервер радиус фильтрисиз беради).
  final CourierLocate? locate;

  static const radiusOptions = [5, 15, 30];

  @override
  State<RestaurantNearbyOrdersScreen> createState() => _RestaurantNearbyOrdersScreenState();
}

class _RestaurantNearbyOrdersScreenState extends State<RestaurantNearbyOrdersScreen> {
  late final RestaurantsRepository _repo = widget.repository ?? RestaurantsRepository();
  int _radiusKm = 15;
  ({double lat, double lng})? _pos;
  bool _located = false;
  late Future<List<NearbyRestaurantOrder>> _future = _load();

  bool _prefsLoading = true;
  bool _prefsSaving = false;
  bool _buyoutEnabled = false;
  final _limitCtrl = TextEditingController();
  String? _claimingId;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _limitCtrl.dispose();
    super.dispose();
  }

  Future<({double lat, double lng})?> _locate() async {
    if (_located) return _pos;
    _located = true;
    try {
      final f = widget.locate;
      if (f != null) {
        _pos = await f();
      } else {
        final c = await const LocationService().getCurrentCoords();
        _pos = (lat: c.lat, lng: c.lng);
      }
    } catch (_) {
      _pos = null;
    }
    return _pos;
  }

  Future<List<NearbyRestaurantOrder>> _load() async {
    final p = await _locate();
    return _repo.listNearby(lat: p?.lat, lng: p?.lng, radiusKm: _radiusKm);
  }

  Future<void> _reload() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    try {
      await next;
    } catch (_) {
      // Хато FutureBuilder'да кўрсатилади.
    }
  }

  Future<void> _loadPrefs() async {
    try {
      final p = await _repo.getBuyoutPrefs(widget.courierUid);
      if (!mounted) return;
      setState(() {
        _buyoutEnabled = p?.enabled ?? false;
        _limitCtrl.text = (p == null || p.limit <= 0) ? '' : '${p.limit}';
        _prefsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _prefsLoading = false);
    }
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  Future<void> _savePrefs() async {
    final limit = int.tryParse(_limitCtrl.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
    setState(() => _prefsSaving = true);
    try {
      await _repo.setBuyoutPrefs(enabled: _buyoutEnabled, limit: limit);
      if (!mounted) return;
      _snack(context.tr('restaurants_courier_prefs_saved'));
      await _reload();
    } catch (e) {
      if (mounted) _snack(restaurantsErrorText(context, e), error: true);
    } finally {
      if (mounted) setState(() => _prefsSaving = false);
    }
  }

  Future<void> _claim(NearbyRestaurantOrder o) async {
    if (_claimingId != null) return;
    setState(() => _claimingId = o.id);
    try {
      await _repo.claim(o.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _snack(restaurantsErrorText(context, e), error: true);
      await _reload();
    } finally {
      if (mounted) setState(() => _claimingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(context.tr('restaurants_courier_nearby_title')),
        actions: [
          IconButton(
            tooltip: context.tr('restaurants_courier_refresh'),
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _prefsCard(context),
            const SizedBox(height: 10),
            _radiusRow(context),
            if (_located && _pos == null) ...[
              const SizedBox(height: 6),
              Text(context.tr('restaurants_courier_no_gps'), style: TextStyle(fontSize: 12, color: c.warn)),
            ],
            const SizedBox(height: 10),
            FutureBuilder<List<NearbyRestaurantOrder>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
                }
                if (snap.hasError) {
                  return _centered(context, restaurantsErrorText(context, snap.error!), retry: true);
                }
                final list = snap.data ?? const <NearbyRestaurantOrder>[];
                if (list.isEmpty) {
                  return _centered(context, context.tr('restaurants_courier_empty'), retry: true);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final o in list) ...[
                      _NearbyOrderCard(order: o, busy: _claimingId == o.id, disabled: _claimingId != null, onClaim: () => _claim(o)),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _centered(BuildContext context, String text, {bool retry = false}) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(children: [
        Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.ink2)),
        if (retry) ...[
          const SizedBox(height: 8),
          TextButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh, size: 18), label: Text(context.tr('restaurants_courier_refresh'))),
        ],
      ]),
    );
  }

  Widget _radiusRow(BuildContext context) {
    final c = context.ava;
    // Wrap: катта шрифтда чиплар иккинчи қаторга тушади, қатор тошмайди.
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(context.tr('restaurants_courier_radius'), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.ink2)),
        for (final r in RestaurantNearbyOrdersScreen.radiusOptions)
          ChoiceChip(
            label: Text(context.tr('restaurants_distance_km').replaceAll('{km}', '$r')),
            selected: _radiusKm == r,
            onSelected: (_) {
              if (_radiusKm == r) return;
              setState(() => _radiusKm = r);
              _reload();
            },
          ),
      ],
    );
  }

  Widget _prefsCard(BuildContext context) {
    final c = context.ava;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(context.tr('restaurants_courier_buyout_title'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink)),
            ),
            Switch(
              value: _buyoutEnabled,
              onChanged: _prefsLoading || _prefsSaving ? null : (v) => setState(() => _buyoutEnabled = v),
            ),
          ]),
          Text(context.tr('restaurants_courier_buyout_hint'), style: TextStyle(fontSize: 12, color: c.ink2)),
          if (_buyoutEnabled) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _limitCtrl,
              enabled: !_prefsLoading && !_prefsSaving,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
              decoration: InputDecoration(
                labelText: context.tr('restaurants_courier_buyout_limit'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: _prefsLoading || _prefsSaving ? null : _savePrefs,
              child: _prefsSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(context.tr('save')),
            ),
          ),
        ],
      ),
    );
  }
}

class _NearbyOrderCard extends StatelessWidget {
  const _NearbyOrderCard({required this.order, required this.busy, required this.disabled, required this.onClaim});

  final NearbyRestaurantOrder order;
  final bool busy;
  final bool disabled;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final o = order;
    final ready = o.restaurantStatus == 'ready';
    final feeKey = o.deliveryPaymentMethod == 'wallet' ? 'restaurants_courier_fee_wallet' : 'restaurants_courier_fee_cash';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Row(children: [
                ExcludeSemantics(child: Icon(Icons.restaurant_rounded, size: 16, color: c.brandText)),
                const SizedBox(width: 4),
                Expanded(child: Text(o.restaurantName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ),
            const SizedBox(width: 6),
            AvaChip(
              label: ready
                  ? context.tr('restaurants_courier_ready_badge')
                  : context.tr('restaurants_courier_preparing').replaceAll('{min}', '${o.prepTimeMin ?? 0}'),
              tone: ready ? AvaChipTone.ok : AvaChipTone.neutral,
              icon: ready ? Icons.check_circle_outline : Icons.hourglass_top_rounded,
            ),
          ]),
          if (o.restaurantAddress.isNotEmpty)
            Text(o.restaurantAddress, style: TextStyle(fontSize: 12, color: c.ink2), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (o.courierToRestaurantM != null)
                AvaChip(
                  icon: Icons.storefront_outlined,
                  label: context.tr('restaurants_courier_to_restaurant').replaceAll('{dist}', formatDistanceLabel(context, o.courierToRestaurantM! / 1000)),
                ),
              if (o.distanceMeters != null)
                AvaChip(
                  icon: Icons.person_pin_circle_outlined,
                  label: context.tr('restaurants_courier_to_customer').replaceAll('{dist}', formatDistanceLabel(context, o.distanceMeters! / 1000)),
                ),
              AvaChip(
                icon: Icons.delivery_dining,
                tone: AvaChipTone.ok,
                label: context.tr(feeKey).replaceAll('{amount}', formatPrice(o.deliveryFee)),
              ),
              if (o.isBuyout)
                AvaChip(
                  icon: Icons.payments_outlined,
                  tone: AvaChipTone.warn,
                  label: context.tr('restaurants_courier_buyout_badge').replaceAll('{amount}', formatPrice(o.buyoutAmount)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: disabled ? null : onClaim,
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                foregroundColor: c.brandInk,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(context.tr('restaurants_courier_claim'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
