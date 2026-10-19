// Ресторан панели — «Буюртмалар» (§12.8): янги буюртмада овоз + титраш +
// 5 дақиқалик ҳисоб; «Қабул (тайёрлаш вақти)» / «Рад (сабаб)» / «Тайёр» /
// «Пул келди» / ўз курьери — «Етказдим». Ҳаракатлар жадвали —
// `merchant_order_actions.dart` (соф, тестланган).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../models/order_model.dart';
import '../../home/widgets/ava_chip.dart';
import '../../home/widgets/ava_section.dart';
import '../../profile/screens/wallet_screen.dart';
import '../data/restaurants_repository.dart';
import '../domain/preorder.dart';
import '../domain/restaurant_models.dart';
import '../widgets/restaurant_checkout_sheet.dart' show restaurantsErrorText;
import 'merchant_order_actions.dart';
import 'merchant_order_sounds.dart';

class MerchantOrdersTab extends StatefulWidget {
  const MerchantOrdersTab({super.key, required this.restaurant, required this.repository, this.playSound = true});

  final Restaurant restaurant;
  final RestaurantsRepository repository;
  final bool playSound;

  @override
  State<MerchantOrdersTab> createState() => _MerchantOrdersTabState();
}

class _MerchantOrdersTabState extends State<MerchantOrdersTab> {
  MerchantOrderBucket _bucket = MerchantOrderBucket.fresh;
  Set<String> _knownFresh = {};
  bool _firstLoad = true;
  Timer? _ticker;
  DateTime _now = DateTime.now();
  String? _busyId;

  /// Оқим бир марта очилади (ҳар rebuild'да янги listener эмас); ресторан
  /// алмашса таб `ValueKey` билан қайта яратилади.
  late final Stream<List<OrderModel>> _orders = widget.repository.watchRestaurantOrders(widget.restaurant.id);

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker(bool anyFresh) {
    if (anyFresh && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    } else if (!anyFresh && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  void _onOrders(List<OrderModel> list) {
    final fresh = list.where((o) => merchantBucketFor(o) == MerchantOrderBucket.fresh).map((o) => o.id).toSet();
    if (!_firstLoad && widget.playSound && fresh.difference(_knownFresh).isNotEmpty) {
      MerchantOrderSounds.playNewOrder();
    }
    _knownFresh = fresh;
    _firstLoad = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncTicker(fresh.isNotEmpty);
    });
  }

  Future<void> _run(OrderModel o, Future<void> Function() fn, {String? okKey}) async {
    setState(() => _busyId = o.id);
    try {
      await fn();
      if (okKey != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(okKey))));
      }
    } on RestaurantsException catch (e) {
      if (!mounted) return;
      final insufficient = e.reason == 'RESTAURANT_WALLET_INSUFFICIENT';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(restaurantsErrorText(context, e)),
          backgroundColor: Colors.red.shade700,
          action: insufficient
              ? SnackBarAction(
                  label: context.tr('restaurants_m_wallet_topup'),
                  textColor: Colors.white,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => WalletScreen(phone: widget.restaurant.ownerUid)),
                  ),
                )
              : null,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(restaurantsErrorText(context, e)), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _accept(OrderModel o) async {
    final prep = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ctx.tr('restaurants_m_prep_pick'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                ctx.tr('restaurants_m_fee_note').replaceAll('{amount}', formatPrice(o.avaFeeAmount)),
                style: TextStyle(fontSize: 12, color: ctx.ava.ink2),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in const [10, 15, 20, 30, 45, 60])
                    FilledButton.tonal(onPressed: () => Navigator.pop(ctx, m), child: Text('$m ${ctx.tr('restaurants_minutes_short')}')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (prep == null) return;
    await _run(o, () => widget.repository.accept(o.id, prepTimeMin: prep), okKey: 'restaurants_m_accepted_ok');
  }

  Future<void> _reject(OrderModel o) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('restaurants_m_reject')),
        content: TextField(
          controller: ctrl,
          maxLength: 200,
          decoration: InputDecoration(hintText: ctx.tr('restaurants_m_reject_reason_hint')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('restaurants_m_reject'))),
        ],
      ),
    );
    if (ok != true) return;
    await _run(o, () => widget.repository.reject(o.id, reason: ctrl.text.trim()));
  }

  Future<void> _do(OrderModel o, MerchantAction a) {
    switch (a) {
      case MerchantAction.accept:
        return _accept(o);
      case MerchantAction.reject:
        return _reject(o);
      case MerchantAction.ready:
        return _run(o, () => widget.repository.markReady(o.id));
      case MerchantAction.markDelivered:
        return _run(o, () => widget.repository.markDelivered(o.id));
      case MerchantAction.confirmPayment:
        return _run(o, () => widget.repository.confirmPayment(o.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return StreamBuilder<List<OrderModel>>(
      stream: _orders,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: AvaNoticeRow(text: context.tr('home_section_error'), icon: Icons.cloud_off_rounded, color: c.warn),
          );
        }
        final all = snap.data ?? const <OrderModel>[];
        _onOrders(all);
        final counts = {for (final b in MerchantOrderBucket.values) b: all.where((o) => merchantBucketFor(o) == b).length};
        final list = all.where((o) => merchantBucketFor(o) == _bucket).toList(growable: false);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: SegmentedButton<MerchantOrderBucket>(
                segments: [
                  for (final b in MerchantOrderBucket.values)
                    ButtonSegment(
                      value: b,
                      label: Text('${context.tr('restaurants_m_bucket_${b.name}')} ${counts[b]! > 0 ? counts[b] : ''}'.trim()),
                    ),
                ],
                selected: {_bucket},
                onSelectionChanged: (s) => setState(() => _bucket = s.first),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: AvaNoticeRow(text: context.tr('restaurants_m_no_orders'), icon: Icons.inbox_outlined, color: c.ink3),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _MerchantOrderCard(
                        order: list[i],
                        now: _now,
                        busy: _busyId == list[i].id,
                        repository: widget.repository,
                        onAction: (a) => _do(list[i], a),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _MerchantOrderCard extends StatelessWidget {
  const _MerchantOrderCard({
    required this.order,
    required this.now,
    required this.busy,
    required this.repository,
    required this.onAction,
  });

  final OrderModel order;
  final DateTime now;
  final bool busy;
  final RestaurantsRepository repository;
  final void Function(MerchantAction) onAction;

  String _label(BuildContext context, MerchantAction a) => switch (a) {
        MerchantAction.accept => context.tr('restaurants_m_accept'),
        MerchantAction.reject => context.tr('restaurants_m_reject'),
        MerchantAction.ready => context.tr('restaurants_m_ready'),
        MerchantAction.markDelivered => context.tr('restaurants_m_delivered'),
        MerchantAction.confirmPayment => context.tr('restaurants_m_payment_received'),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final o = order;
    final actions = merchantActionsFor(o);
    final secs = secondsToDeadline(o, now);
    final isFresh = o.restaurantStatus == RestaurantOrderStatus.placed;
    final created = o.createdAt;
    final timeStr = created == null ? '' : '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
    final modeKey = switch (o.deliveryMode) {
      'pickup' => 'restaurants_m_mode_pickup',
      'own_courier' => 'restaurants_m_mode_own',
      _ => 'restaurants_m_mode_delivery',
    };
    final showCode = o.deliveryMode == 'ava_courier' &&
        (o.restaurantStatus == RestaurantOrderStatus.accepted || o.restaurantStatus == RestaurantOrderStatus.ready);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        border: Border.all(color: isFresh ? c.brand : c.line, width: isFresh ? 1.4 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '#${o.id.substring(0, o.id.length < 6 ? o.id.length : 6).toUpperCase()} · $timeStr',
                  style: TextStyle(fontSize: 12, color: c.ink2),
                ),
              ),
              AvaChip(
                label: context.tr(RestaurantOrderStatus.labelKey(o.restaurantStatus)),
                tone: RestaurantOrderStatus.isFailed(o.restaurantStatus)
                    ? AvaChipTone.warn
                    : (o.restaurantStatus == RestaurantOrderStatus.delivered ? AvaChipTone.ok : AvaChipTone.brand),
              ),
            ],
          ),
          // Олдиндан буюртма (S4b): бажарилиш вақти кўриниб туради; муддат дақиқалар эмас, соатлар — сония ҳисоби йўқ.
          if (o.scheduledFor != null) ...[
            const SizedBox(height: 6),
            Row(
              key: const ValueKey('preorder-badge'),
              children: [
                Icon(Icons.event_rounded, size: 16, color: c.brandText),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.tr('restaurants_preorder_for').replaceAll('{when}', Preorder.format(o.scheduledFor!)),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.brandText),
                  ),
                ),
              ],
            ),
          ],
          if (isFresh && secs != null && o.scheduledFor == null) ...[
            const SizedBox(height: 6),
            Text(
              secs > 0
                  ? context.tr('restaurants_m_deadline').replaceAll('{s}', '$secs')
                  : context.tr('restaurants_m_deadline_passed'),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: secs > 60 ? c.brandText : c.danger),
            ),
          ],
          const SizedBox(height: 8),
          for (final it in o.items)
            Text('• ${it.name} × ${it.count}  —  ${formatPrice(it.lineTotal)}', style: TextStyle(fontSize: 13, color: c.ink)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              AvaChip(label: context.tr(modeKey)),
              AvaChip(
                label: context.tr('restaurants_food_payment_${o.foodPaymentMethod.isEmpty ? 'prepay' : o.foodPaymentMethod}'),
                tone: o.paymentStatus == 'paid' ? AvaChipTone.ok : AvaChipTone.neutral,
              ),
              if (o.paymentStatus == 'paid_declared') AvaChip(label: context.tr('restaurants_pay_declared'), tone: AvaChipTone.warn),
              if (o.utensils > 0) AvaChip(label: context.tr('restaurants_m_utensils').replaceAll('{n}', '${o.utensils}')),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${context.tr('restaurants_items_total')}: ${formatPrice(o.foodAmount)}'
            '${o.deliveryFee > 0 ? ' · ${context.tr('restaurants_delivery_fee')}: ${formatPrice(o.deliveryFee)}' : ''}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink),
          ),
          if (o.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('${context.tr('restaurants_note')}: ${o.note}', style: TextStyle(fontSize: 12, color: c.ink2)),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.person_outline_rounded, size: 16, color: c.ink3),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${o.userName.isEmpty ? context.tr('restaurants_m_customer') : o.userName}'
                  '${o.deliveryMode != 'pickup' && o.address.isNotEmpty ? ' · ${o.address}' : ''}',
                  style: TextStyle(fontSize: 12, color: c.ink2),
                ),
              ),
              if (o.userPhone.isNotEmpty)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.call_outlined, color: c.brandText),
                  onPressed: () => callPhone(o.userPhone),
                ),
            ],
          ),
          if (showCode)
            StreamBuilder<String?>(
              stream: repository.watchPickupCode(o.id),
              builder: (context, s) {
                final code = s.data;
                final courier = o.courierId ?? '';
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          courier.isEmpty
                              ? context.tr('restaurants_m_waiting_courier')
                              : context.tr('restaurants_m_courier_assigned').replaceAll('{phone}', courier),
                          style: TextStyle(fontSize: 12, color: c.ink2),
                        ),
                      ),
                      if (code != null)
                        Text(
                          context.tr('restaurants_m_pickup_code').replaceAll('{code}', code),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c.brandText, letterSpacing: 1),
                        ),
                    ],
                  ),
                );
              },
            ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (var i = 0; i < actions.length; i++)
                  if (i == 0 && actions[i] != MerchantAction.reject)
                    FilledButton(
                      onPressed: busy ? null : () => onAction(actions[i]),
                      style: FilledButton.styleFrom(backgroundColor: c.brand, foregroundColor: c.brandInk),
                      child: Text(_label(context, actions[i])),
                    )
                  else
                    OutlinedButton(
                      onPressed: busy ? null : () => onAction(actions[i]),
                      style: actions[i] == MerchantAction.reject
                          ? OutlinedButton.styleFrom(foregroundColor: c.danger, side: BorderSide(color: c.danger))
                          : null,
                      child: Text(_label(context, actions[i])),
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
