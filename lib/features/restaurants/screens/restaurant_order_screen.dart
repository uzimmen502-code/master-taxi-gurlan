// Буюртмани кузатиш (§12.6): босқичлар · тўлов (реквизит, «Тўладим») ·
// таомлар · қўнғироқ · бекор (фақат `placed`).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../models/order_model.dart';
import '../../home/widgets/ava_section.dart';
import '../data/restaurants_repository.dart';
import '../domain/restaurant_models.dart';
import '../widgets/restaurant_checkout_sheet.dart' show restaurantsErrorText;

class RestaurantOrderScreen extends StatefulWidget {
  const RestaurantOrderScreen({super.key, required this.orderId, this.repository});

  final String orderId;
  final RestaurantsRepository? repository;

  @override
  State<RestaurantOrderScreen> createState() => _RestaurantOrderScreenState();
}

class _RestaurantOrderScreenState extends State<RestaurantOrderScreen> {
  late final RestaurantsRepository _repo = widget.repository ?? RestaurantsRepository();
  Future<Restaurant?>? _restaurant;
  String? _restaurantIdLoaded;
  bool _busy = false;

  Future<Restaurant?> _restaurantFor(String id) {
    if (_restaurantIdLoaded != id) {
      _restaurantIdLoaded = id;
      _restaurant = _repo.getRestaurant(id);
    }
    return _restaurant!;
  }

  Future<void> _run(Future<void> Function() fn, {String? okKey}) async {
    setState(() => _busy = true);
    try {
      await fn();
      if (okKey != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(okKey))));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(restaurantsErrorText(context, e)), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('order_cancel')),
        content: Text(ctx.tr('order_cancel_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('order_cancel'))),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => _repo.cancel(widget.orderId), okKey: 'order_cancel_ok');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface,
        elevation: 0,
        title: Text(context.tr('restaurants_order_title'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
      ),
      body: StreamBuilder<OrderModel?>(
        stream: _repo.watchOrder(widget.orderId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final o = snap.data;
          if (o == null) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: AvaNoticeRow(text: context.tr('home_section_error'), icon: Icons.cloud_off_rounded, color: c.warn),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              _StatusCard(order: o),
              const SizedBox(height: 10),
              _PaymentCard(order: o, busy: _busy, onMarkPaid: () => _run(() => _repo.markPaid(o.id), okKey: 'restaurants_pay_declared_ok')),
              const SizedBox(height: 10),
              _ItemsCard(order: o),
              const SizedBox(height: 10),
              FutureBuilder<Restaurant?>(
                future: _restaurantFor(o.restaurantId),
                builder: (context, rs) => _ContactsCard(order: o, restaurant: rs.data),
              ),
              if (o.restaurantStatus == RestaurantOrderStatus.placed) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _busy ? null : _cancel,
                  style: OutlinedButton.styleFrom(foregroundColor: c.danger, side: BorderSide(color: c.danger)),
                  child: Text(context.tr('order_cancel')),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        border: Border.all(color: c.line),
      ),
      child: child,
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final s = order.restaurantStatus;
    final failed = RestaurantOrderStatus.isFailed(s);
    final idx = RestaurantOrderStatus.stepIndex(s);
    final steps = order.deliveryMode == 'pickup' || order.deliveryMode == 'own_courier'
        ? const [RestaurantOrderStatus.placed, RestaurantOrderStatus.accepted, RestaurantOrderStatus.ready, RestaurantOrderStatus.delivered]
        : RestaurantOrderStatus.steps;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(order.restaurantName.isEmpty ? context.tr('home_module_restaurants') : order.restaurantName,
              style: AvaText.sectionTitle.copyWith(color: c.ink)),
          const SizedBox(height: 8),
          if (failed)
            AvaNoticeRow(
              text: s == RestaurantOrderStatus.rejected && order.rejectReason == 'timeout'
                  ? context.tr('restaurants_status_rejected_timeout')
                  : '${context.tr(RestaurantOrderStatus.labelKey(s))}${order.rejectReason.isNotEmpty && order.rejectReason != 'timeout' ? ' · ${order.rejectReason}' : ''}',
              icon: Icons.cancel_outlined,
              color: c.danger,
            )
          else
            for (var i = 0; i < steps.length; i++)
              _Step(
                label: context.tr(RestaurantOrderStatus.labelKey(steps[i])),
                done: idx > RestaurantOrderStatus.stepIndex(steps[i]) || s == RestaurantOrderStatus.delivered,
                active: steps[i] == s,
                last: i == steps.length - 1,
                note: steps[i] == RestaurantOrderStatus.accepted && s == RestaurantOrderStatus.accepted && order.prepTimeMin > 0
                    ? context.tr('restaurants_prep_time').replaceAll('{min}', order.prepTimeMin.toString())
                    : null,
              ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.done, required this.active, required this.last, this.note});

  final String label;
  final bool done;
  final bool active;
  final bool last;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final color = done ? c.ok : (active ? c.brand : c.ink3);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Icon(done ? Icons.check_circle_rounded : (active ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded), size: 18, color: color),
              if (!last) Expanded(child: Container(width: 2, color: done ? c.ok : c.line)),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w400, color: active || done ? c.ink : c.ink3)),
                  if (note != null) Text(note!, style: TextStyle(fontSize: 11, color: c.ink2)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.order, required this.busy, required this.onMarkPaid});

  final OrderModel order;
  final bool busy;
  final VoidCallback onMarkPaid;

  String _card(String digits) =>
      digits.length == 16 ? '${digits.substring(0, 4)} ${digits.substring(4, 8)} ${digits.substring(8, 12)} ${digits.substring(12)}' : digits;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final o = order;
    final closed = RestaurantOrderStatus.isFailed(o.restaurantStatus);
    final foodAmount = o.foodAmount;
    final pay = o.restaurantPayment;
    final cardNo = (pay?['cardNumber'] ?? '') as String;
    final holder = (pay?['cardHolder'] ?? '') as String;
    final children = <Widget>[
      Text(context.tr('restaurants_payment_title'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
      const SizedBox(height: 6),
    ];
    switch (o.foodPaymentMethod) {
      case 'prepay':
        children.add(Text(
          context.tr('restaurants_pay_prepay_line').replaceAll('{amount}', formatPrice(foodAmount)),
          style: TextStyle(fontSize: 13, color: c.ink),
        ));
        if (cardNo.isNotEmpty) {
          children.add(const SizedBox(height: 6));
          children.add(Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_card(cardNo), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink, letterSpacing: 1)),
                    if (holder.isNotEmpty) Text(holder, style: TextStyle(fontSize: 12, color: c.ink2)),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.tr('restaurants_copy'),
                icon: const Icon(Icons.copy_rounded),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: cardNo));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('restaurants_copied'))));
                },
              ),
            ],
          ));
        }
        children.add(const SizedBox(height: 6));
        if (o.paymentStatus == 'paid') {
          children.add(_Badge(text: context.tr('restaurants_pay_confirmed'), color: c.ok));
        } else if (o.paymentStatus == 'paid_declared') {
          children.add(_Badge(text: context.tr('restaurants_pay_declared'), color: c.warn));
        } else if (!closed) {
          children.add(FilledButton.tonal(
            onPressed: busy ? null : onMarkPaid,
            child: Text(context.tr('restaurants_i_paid')),
          ));
        }
        break;
      case 'cash_buyout':
        children.add(Text(
          context.tr('restaurants_pay_cash_courier').replaceAll('{amount}', formatPrice(foodAmount + (o.deliveryPaymentMethod == 'cash' ? o.deliveryFee : 0))),
          style: TextStyle(fontSize: 13, color: c.ink),
        ));
        break;
      default:
        children.add(Text(
          context.tr('restaurants_pay_cash_restaurant').replaceAll('{amount}', formatPrice(foodAmount)),
          style: TextStyle(fontSize: 13, color: c.ink),
        ));
    }
    if (o.deliveryMode == 'ava_courier' && o.deliveryFee > 0) {
      children.add(const SizedBox(height: 6));
      children.add(Text(
        context
            .tr(o.deliveryPaymentMethod == 'wallet' ? 'restaurants_pay_delivery_wallet' : 'restaurants_pay_delivery_cash')
            .replaceAll('{amount}', formatPrice(o.deliveryFee)),
        style: TextStyle(fontSize: 12, color: c.ink2),
      ));
    }
    return _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children));
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      );
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final o = order;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final it in o.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(child: Text('${it.name} × ${it.count}', style: TextStyle(fontSize: 13, color: c.ink))),
                  Text(formatPrice(it.lineTotal), style: TextStyle(fontSize: 13, color: c.ink)),
                ],
              ),
            ),
          Divider(color: c.line),
          _Total(label: context.tr('restaurants_items_total'), value: o.itemsTotal),
          if (o.packagingTotal > 0) _Total(label: context.tr('restaurants_packaging'), value: o.packagingTotal),
          if (o.deliveryFee > 0) _Total(label: context.tr('restaurants_delivery_fee'), value: o.deliveryFee),
          _Total(label: context.tr('restaurants_total'), value: o.total, bold: true),
          if (o.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('${context.tr('restaurants_note')}: ${o.note}', style: TextStyle(fontSize: 12, color: c.ink2)),
          ],
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value, this.bold = false});

  final String label;
  final int value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final style = TextStyle(fontSize: bold ? 14 : 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: c.ink);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Expanded(child: Text(label, style: style)), Text('${formatPrice(value)} ${context.tr('sum')}', style: style)]),
    );
  }
}

class _ContactsCard extends StatelessWidget {
  const _ContactsCard({required this.order, required this.restaurant});

  final OrderModel order;
  final Restaurant? restaurant;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final r = restaurant;
    final courier = order.courierId ?? '';
    final showCourier = courier.isNotEmpty &&
        (order.restaurantStatus == RestaurantOrderStatus.picked || order.restaurantStatus == RestaurantOrderStatus.arrived);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (order.deliveryMode == 'pickup' && r != null && r.address.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Icon(Icons.place_outlined, size: 16, color: c.ink3),
                const SizedBox(width: 6),
                Expanded(child: Text(r.address, style: TextStyle(fontSize: 13, color: c.ink))),
              ]),
            ),
          Row(
            children: [
              if (r != null && r.contactPhone.isNotEmpty)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => callPhone(r.contactPhone),
                    icon: const Icon(Icons.storefront_rounded, size: 18),
                    label: Text(context.tr('restaurants_call_restaurant')),
                  ),
                ),
              if (showCourier) ...[
                if (r != null && r.contactPhone.isNotEmpty) const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => callPhone(courier),
                    icon: const Icon(Icons.delivery_dining_rounded, size: 18),
                    label: Text(context.tr('restaurants_call_courier')),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
