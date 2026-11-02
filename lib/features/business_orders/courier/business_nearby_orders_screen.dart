// Курьер — «Дўкон буюртмалари» («Менинг бизнесим», 2026-11-03): яқиндаги олинмаган буюртмалар
// (`listNearbyBusinessOrders` — проекция, мижоз телефони/манзили ЙЎҚ) ва «Олиш» (`courierClaimBusinessOrder`,
// биринчи ғолиб — 22-қоида). Олинган буюртма курьернинг фаол маршрутига тушади — курьер панели уни ўзи
// кўрсатади. Выкуп лимити — ресторан буюртмаларидаги ўша созлама (`restaurant_courier_prefs`, сервер).

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../services/location_service.dart';
import '../../home/widgets/ava_chip.dart';
import '../../restaurants/widgets/restaurant_row.dart' show formatDistanceLabel;
import '../data/business_orders_repository.dart';
import '../domain/business_order.dart';
import '../widgets/business_order_widgets.dart';

typedef BizCourierLocate = Future<({double lat, double lng})?> Function();

class BusinessNearbyOrdersScreen extends StatefulWidget {
  const BusinessNearbyOrdersScreen({super.key, this.repository, this.locate});

  final BusinessOrdersRepository? repository;

  /// Тестда алмаштириш учун; стандарт — [LocationService.getCurrentCoords] (GPS йўқ — масофасиз рўйхат).
  final BizCourierLocate? locate;

  static const radiusOptions = [5, 15, 30];

  @override
  State<BusinessNearbyOrdersScreen> createState() => _BusinessNearbyOrdersScreenState();
}

class _BusinessNearbyOrdersScreenState extends State<BusinessNearbyOrdersScreen> {
  late final BusinessOrdersRepository _repo = widget.repository ?? BusinessOrdersRepository();
  int _radiusKm = 15;
  ({double lat, double lng})? _pos;
  bool _located = false;
  late Future<NearbyBusinessOrders> _future = _load();
  String? _claimingId;

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

  Future<NearbyBusinessOrders> _load() async {
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

  Future<void> _claim(NearbyBusinessOrder o) async {
    if (_claimingId != null) return;
    setState(() => _claimingId = o.id);
    try {
      await _repo.claim(o.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(bizOrderErrorText(context, e)), backgroundColor: context.ava.danger),
      );
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
        title: Text(context.tr('biz_order_courier_nearby_title')),
        actions: [
          IconButton(tooltip: context.tr('restaurants_courier_refresh'), onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(AvaSpace.screen, 12, AvaSpace.screen, 24),
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(context.tr('restaurants_courier_radius'), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.ink2)),
                for (final r in BusinessNearbyOrdersScreen.radiusOptions)
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
            ),
            if (_located && _pos == null) ...[
              const SizedBox(height: 6),
              Text(context.tr('restaurants_courier_no_gps'), style: TextStyle(fontSize: 12, color: c.warn)),
            ],
            const SizedBox(height: 10),
            FutureBuilder<NearbyBusinessOrders>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
                }
                if (snap.hasError) return _centered(context, bizOrderErrorText(context, snap.error!));
                final res = snap.data ?? const NearbyBusinessOrders([]);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BizOrderNotice(
                      key: const ValueKey('biz_courier_buyout_limit'),
                      icon: Icons.payments_outlined,
                      text: context.tr('biz_order_courier_buyout_limit').replaceAll('{amount}', formatMoney(res.buyoutLimit)),
                      color: c.warn,
                      background: c.warnSoft,
                    ),
                    const SizedBox(height: 10),
                    if (res.orders.isEmpty) _centered(context, context.tr('biz_order_courier_empty')),
                    for (final o in res.orders) ...[
                      _NearbyCard(
                        order: o,
                        busy: _claimingId == o.id,
                        disabled: _claimingId != null || !o.buyoutAllowed,
                        onClaim: () => _claim(o),
                      ),
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

  Widget _centered(BuildContext context, String text) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(children: [
        Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.ink2)),
        const SizedBox(height: 8),
        TextButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh, size: 18), label: Text(context.tr('restaurants_courier_refresh'))),
      ]),
    );
  }
}

class _NearbyCard extends StatelessWidget {
  const _NearbyCard({required this.order, required this.busy, required this.disabled, required this.onClaim});

  final NearbyBusinessOrder order;
  final bool busy;
  final bool disabled;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final o = order;
    final ready = o.status == BusinessOrderStatus.ready;
    final feeKey = o.deliveryPaymentMethod == 'wallet' ? 'biz_order_courier_fee_wallet' : 'biz_order_courier_fee_cash';
    return Container(
      key: ValueKey('biz_nearby_${o.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(AvaRadius.card), border: Border.all(color: c.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            ExcludeSemantics(child: Icon(Icons.storefront_rounded, size: 16, color: c.brandText)),
            const SizedBox(width: 4),
            Expanded(
              child: Text(o.businessName, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink)),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: AvaChip(
                label: context.tr(ready ? 'biz_order_status_ready' : 'biz_order_status_accepted'),
                tone: ready ? AvaChipTone.ok : AvaChipTone.neutral,
                icon: ready ? Icons.check_circle_outline : Icons.hourglass_top_rounded,
              ),
            ),
          ]),
          if (o.businessAddress.isNotEmpty)
            Text(o.businessAddress, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.ink2)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (o.courierToPickupM != null)
                AvaChip(
                  icon: Icons.storefront_outlined,
                  label: context.tr('biz_order_courier_to_shop').replaceAll('{dist}', formatDistanceLabel(context, o.courierToPickupM! / 1000)),
                ),
              if (o.distanceMeters != null)
                AvaChip(
                  icon: Icons.person_pin_circle_outlined,
                  label: context.tr('restaurants_courier_to_customer').replaceAll('{dist}', formatDistanceLabel(context, o.distanceMeters! / 1000)),
                ),
              AvaChip(icon: Icons.delivery_dining, tone: AvaChipTone.ok, label: context.tr(feeKey).replaceAll('{amount}', formatMoney(o.deliveryFee))),
              AvaChip(
                icon: Icons.payments_outlined,
                tone: AvaChipTone.warn,
                label: context.tr('biz_order_courier_buyout').replaceAll('{amount}', formatMoney(o.buyoutAmount)),
              ),
              AvaChip(icon: Icons.inventory_2_outlined, label: context.tr('biz_order_courier_items').replaceAll('{n}', '${o.itemsCount}')),
            ],
          ),
          if (!o.buyoutAllowed) ...[
            const SizedBox(height: 6),
            Text(context.tr('biz_order_courier_buyout_over'), style: TextStyle(fontSize: 12, color: c.danger, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: ValueKey('biz_nearby_claim_${o.id}'),
              onPressed: disabled ? null : onClaim,
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                foregroundColor: c.brandInk,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AvaRadius.card)),
              ),
              child: busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(context.tr('biz_order_courier_claim'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
