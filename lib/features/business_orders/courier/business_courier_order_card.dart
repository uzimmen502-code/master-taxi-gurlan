// Курьер маршрутидаги «Менинг бизнесим» буюртмаси карточкаси (ресторан карточкаси андозаси):
//   accepted → сотувчи тайёрламоқда (дўконга боради)
//   ready    → код киритиб олади (`courierPickupBusinessOrder`), маҳсулот пулини сотувчига нақд тўлайди (выкуп)
//   picked   → мижозга кетмоқда → «Етиб келдим» (`courierArriveBusinessOrder`)
//   arrived  → мижоздан нақд олади → «Топширдим» (`courierCompleteBusinessOrder`; мижоз «Олдим» тасдиғи кутилиши
//              мумкин — `awaitingCustomer`)
//   picked/arrived → «Етказиб бўлмади» — умумий [DeliveryFailedCourierControls] (`module: business`).
// Ҳолат `businessStatus`дан ЖОНЛИ (`watchOrder`): сотувчи «Тайёр» қилганда маршрут ҳужжати ўзгармайди.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/map_launcher.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../models/order_model.dart';
import '../../customer_confirm/widgets/courier_awaiting_notice.dart';
import '../../customer_confirm/widgets/delivery_failed_courier_controls.dart';
import '../data/business_orders_repository.dart';
import '../domain/business_order.dart';
import '../widgets/business_order_widgets.dart';

class BusinessCourierOrderCard extends StatefulWidget {
  const BusinessCourierOrderCard({
    super.key,
    required this.order,
    required this.index,
    required this.isDone,
    required this.isCurrent,
    this.needsFinalize = false,
    required this.repository,
    required this.onPickup,
    required this.onArrive,
    required this.onComplete,
    required this.onReportFailed,
    required this.onFinalizeRoute,
  });

  /// Маршрутдаги snapshot; жонли ҳолат `repository.watchOrder` дан.
  final OrderModel order;
  final int index;
  final bool isDone;
  final bool isCurrent;
  final bool needsFinalize;
  final BusinessOrdersRepository repository;

  /// Хато ташлайди (`PICKUP_CODE_MISMATCH` + `attemptsLeft`) — диалог ўзи кўрсатади.
  final Future<void> Function(String code) onPickup;
  final Future<void> Function() onArrive;
  final Future<BusinessCompleteResult> Function() onComplete;
  final Future<void> Function(String reason) onReportFailed;
  final Future<void> Function() onFinalizeRoute;

  @override
  State<BusinessCourierOrderCard> createState() => _BusinessCourierOrderCardState();
}

class _BusinessCourierOrderCardState extends State<BusinessCourierOrderCard> {
  late Stream<BusinessOrder?> _stream = widget.repository.watchOrder(widget.order.id);
  bool _busy = false;

  /// Мижоз тасдиғи кутилаётганда (`awaitingCustomer`) ўша пайтдаги ҳолат; ҳолат ўзгарса — кутиш тугади.
  String? _awaitingStatus;

  @override
  void didUpdateWidget(covariant BusinessCourierOrderCard old) {
    super.didUpdateWidget(old);
    if (old.order.id != widget.order.id) _stream = widget.repository.watchOrder(widget.order.id);
  }

  BusinessOrder get _fromSnapshot {
    final o = widget.order;
    return BusinessOrder(
      id: o.id,
      status: o.businessStatus,
      businessName: o.businessName,
      userName: o.userName,
      userPhone: o.userPhone,
      address: o.address,
      lat: o.lat,
      lng: o.lng,
      itemsTotal: o.itemsTotal,
      deliveryFee: o.deliveryFee,
      total: o.total,
      deliveryPaymentMethod: o.deliveryPaymentMethod.isEmpty ? 'cash' : o.deliveryPaymentMethod,
      courierId: o.courierId ?? '',
    );
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? context.ava.danger : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<bool> _run(Future<void> Function() fn) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await fn();
      return true;
    } catch (e) {
      if (mounted) _snack(bizOrderErrorText(context, e), error: true);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _navigate(BusinessOrder o, {required bool toShop}) async {
    final lat = toShop ? o.businessLat : o.lat;
    final lng = toShop ? o.businessLng : o.lng;
    if (lat == null || lng == null) return;
    await openMapsNavigation(lat: lat, lng: lng, label: toShop ? o.businessName : o.userName);
  }

  Future<void> _pickup(BusinessOrder o) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => _PickupCodeDialog(buyoutAmount: o.itemsTotal, onSubmit: widget.onPickup),
    );
  }

  Future<void> _deliver(BusinessOrder o) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('biz_order_courier_deliver_btn')),
        content: _CollectSummary(order: o),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(
            key: const ValueKey('biz_courier_deliver_confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('biz_order_courier_deliver_btn')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    BusinessCompleteResult? res;
    final ok = await _run(() async => res = await widget.onComplete());
    final r = res;
    if (!ok || r == null || !mounted) return;
    if (r.awaitingCustomer) {
      // Ҳали етказилмаган: мижоз ўз қурилмасида «Олдим»ни босади; маршрут олдинга сурилмайди.
      setState(() => _awaitingStatus = o.status);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('biz_order_status_delivered')),
        content: Text(
          [
            ctx.tr('biz_order_courier_delivered_ok').replaceAll('{amount}', formatMoney(r.cashCollected)),
            if (r.walletPaid > 0) ctx.tr('biz_order_courier_wallet_paid').replaceAll('{amount}', formatMoney(r.walletPaid)),
          ].join('\n'),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('ok')))],
      ),
    );
    await widget.onFinalizeRoute();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BusinessOrder?>(
      stream: _stream,
      builder: (context, snap) => _card(context, snap.data ?? _fromSnapshot),
    );
  }

  Widget _card(BuildContext context, BusinessOrder o) {
    final c = context.ava;
    final s = o.status;
    final toShop = s == BusinessOrderStatus.accepted || s == BusinessOrderStatus.ready || s == BusinessOrderStatus.placed;
    final muted = widget.isDone;
    final title = toShop ? o.businessName : (o.userName.isNotEmpty ? o.userName : context.tr('biz_order_courier_customer'));
    final subtitle = toShop ? o.businessAddress : o.address;
    final waiting = _awaitingStatus != null && _awaitingStatus == s;
    final showNext = widget.needsFinalize || (widget.isCurrent && o.isFinal);
    final feeKey = o.deliveryPaymentMethod == 'wallet' ? 'biz_order_courier_fee_wallet' : 'biz_order_courier_fee_cash';

    return Container(
      key: ValueKey('biz_courier_card_${o.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: muted ? c.surface2 : c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.isCurrent ? c.brandText : c.line, width: widget.isCurrent ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: muted ? c.line : (widget.isCurrent ? c.brand : c.brandSoft),
                child: Text('${widget.index + 1}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: muted ? c.ink2 : c.brandInk)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      ExcludeSemantics(child: Icon(Icons.storefront_rounded, size: 16, color: muted ? c.ink2 : c.brandText)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: muted ? c.ink2 : c.ink)),
                      ),
                    ]),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.ink2)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Flexible(child: BusinessOrderStatusPill(status: s)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(context.tr('biz_order_courier_buyout').replaceAll('{amount}', formatMoney(o.itemsTotal)),
                  style: TextStyle(fontSize: 12, color: c.ink2)),
              Text(context.tr(feeKey).replaceAll('{amount}', formatMoney(o.deliveryFee)), style: TextStyle(fontSize: 12, color: c.ok)),
            ],
          ),
          if (o.note.isNotEmpty && widget.isCurrent) ...[
            const SizedBox(height: 4),
            Text(o.note, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.ink2)),
          ],
          if (s == BusinessOrderStatus.rejected || s == BusinessOrderStatus.cancelled) ...[
            const SizedBox(height: 8),
            BizOrderNotice(
              icon: Icons.block,
              text: context.tr('biz_order_courier_cancelled_note'),
              color: c.danger,
              background: c.dangerSoft,
            ),
          ],
          if (showNext) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: ValueKey('biz_courier_next_${o.id}'),
                onPressed: _busy ? null : () async => widget.onFinalizeRoute(),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: Text(context.tr('courier_next_order'), style: const TextStyle(fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(backgroundColor: c.brand, foregroundColor: c.brandInk, minimumSize: const Size.fromHeight(48)),
              ),
            ),
          ] else if (widget.isCurrent)
            ..._actions(context, o, waiting),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context, BusinessOrder o, bool waiting) {
    final c = context.ava;
    final s = o.status;
    final toShop = s == BusinessOrderStatus.accepted || s == BusinessOrderStatus.ready;
    final phone = toShop ? o.sellerUid : o.userPhone;
    final contact = Row(children: [
      Expanded(
        child: OutlinedButton.icon(
          key: ValueKey('biz_courier_call_${o.id}'),
          onPressed: phone.isEmpty ? null : () => callPhone(phone),
          icon: const Icon(Icons.call, size: 16),
          label: Text(context.tr(toShop ? 'biz_order_courier_call_seller' : 'restaurants_courier_call_customer'),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, AvaTap.minSize)),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: (toShop ? o.hasBusinessCoordinates : o.hasCustomerCoordinates) ? () => _navigate(o, toShop: toShop) : null,
          icon: const Icon(Icons.navigation, size: 16),
          label: Text(context.tr('courier_navigate'), maxLines: 1, overflow: TextOverflow.ellipsis),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, AvaTap.minSize)),
        ),
      ),
    ]);
    Widget big(String key, String label, VoidCallback? onTap) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              key: ValueKey(key),
              onPressed: _busy ? null : onTap,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        );
    final failed = Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DeliveryFailedCourierControls(
        key: ValueKey('biz_courier_df_${o.id}'),
        state: o.deliveryFailed,
        canReport: o.courierCanReportFailed && !waiting,
        decider: 'seller',
        onReport: (reason) async {
          await _run(() => widget.onReportFailed(reason));
        },
      ),
    );
    switch (s) {
      case BusinessOrderStatus.accepted:
        return [
          const SizedBox(height: 8),
          BizOrderNotice(
            icon: Icons.hourglass_top_rounded,
            text: context.tr('biz_order_courier_preparing'),
            color: c.warn,
            background: c.warnSoft,
          ),
          const SizedBox(height: 8),
          contact,
        ];
      case BusinessOrderStatus.ready:
        return [
          const SizedBox(height: 8),
          BizOrderNotice(
            icon: Icons.payments_outlined,
            text: context.tr('biz_order_courier_pay_seller').replaceAll('{amount}', formatMoney(o.itemsTotal)),
            color: c.warn,
            background: c.warnSoft,
          ),
          const SizedBox(height: 8),
          contact,
          big('biz_courier_pickup_${o.id}', context.tr('biz_order_courier_pickup_btn'), () => _pickup(o)),
        ];
      case BusinessOrderStatus.picked:
        return [
          const SizedBox(height: 8),
          contact,
          if (!o.deliveryFailedPending)
            big('biz_courier_arrive_${o.id}', context.tr('restaurants_courier_arrive_btn'), () => _run(widget.onArrive)),
          failed,
        ];
      case BusinessOrderStatus.arrived:
        return [
          const SizedBox(height: 8),
          _CollectSummary(order: o),
          if (waiting) ...[const SizedBox(height: 8), const CourierAwaitingNotice()],
          const SizedBox(height: 8),
          contact,
          big(
            'biz_courier_deliver_${o.id}',
            context.tr(waiting ? 'customer_confirm_waiting' : 'biz_order_courier_deliver_btn'),
            waiting || o.deliveryFailedPending ? null : () => _deliver(o),
          ),
          failed,
        ];
      default:
        return const [];
    }
  }
}

/// «Мижоздан олинг»: маҳсулот пули (выкуп) + нақд етказиш ҳақи.
class _CollectSummary extends StatelessWidget {
  const _CollectSummary({required this.order});

  final BusinessOrder order;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final o = order;
    final feeCash = o.deliveryPaymentMethod == 'cash' ? o.deliveryFee : 0;
    return Container(
      key: const ValueKey('biz_courier_collect'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('restaurants_courier_collect_title'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.ink2)),
          const SizedBox(height: 4),
          Text(context.tr('biz_order_courier_collect_goods').replaceAll('{amount}', formatMoney(o.itemsTotal)),
              style: TextStyle(fontSize: 12.5, color: c.ink)),
          if (feeCash > 0)
            Text(context.tr('restaurants_courier_collect_fee').replaceAll('{amount}', formatPrice(feeCash)),
                style: TextStyle(fontSize: 12.5, color: c.ink)),
          Text(formatMoney(o.cashAtDoor), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.brandText)),
          if (o.deliveryPaymentMethod == 'wallet')
            Text(context.tr('restaurants_courier_fee_from_wallet'), style: TextStyle(fontSize: 12, color: c.ink2)),
        ],
      ),
    );
  }
}

/// Сотувчи коди (4 рақам). Нотўғри — диалог очиқ, қолган уринишлар кўрсатилади.
class _PickupCodeDialog extends StatefulWidget {
  const _PickupCodeDialog({required this.buyoutAmount, required this.onSubmit});

  final int buyoutAmount;
  final Future<void> Function(String code) onSubmit;

  @override
  State<_PickupCodeDialog> createState() => _PickupCodeDialogState();
}

class _PickupCodeDialogState extends State<_PickupCodeDialog> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _ctrl.text.trim();
    if (code.length != 4) {
      setState(() => _error = context.tr('biz_order_courier_code_hint'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(code);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = bizOrderErrorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return AlertDialog(
      title: Text(context.tr('biz_order_courier_pickup_btn')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('biz_order_courier_code_hint'), style: TextStyle(fontSize: 12, color: c.ink2)),
          const SizedBox(height: 6),
          Text(
            context.tr('biz_order_courier_pay_seller').replaceAll('{amount}', formatMoney(widget.buyoutAmount)),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.warn),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('biz_courier_code_field'),
            controller: _ctrl,
            autofocus: true,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 8),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            decoration: InputDecoration(border: const OutlineInputBorder(), counterText: '', errorText: _error, errorMaxLines: 3),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text(context.tr('cancel'))),
        FilledButton(
          key: const ValueKey('biz_courier_code_submit'),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(context.tr('biz_order_courier_pickup_btn')),
        ),
      ],
    );
  }
}
