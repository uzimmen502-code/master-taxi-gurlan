// Курьер маршрутидаги РЕСТОРАН буюртмаси карточкаси (Б3, §12.9).
// Эски `CourierOrderTile` эмас: босқичлар бошқа (ресторан → код → мижоз →
// топшириш), пул AVA'ники эмас. Ҳолат `restaurantStatus`дан ЖОНЛИ ўқилади
// (`watchOrder`): ресторан «Тайёр» қилганда маршрут ҳужжати ўзгармайди,
// карточка ўзи янгиланиши керак. Мантиқ — `restaurant_courier_logic.dart`.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../models/order_model.dart';
import '../../home/widgets/ava_chip.dart';
import '../data/restaurants_repository.dart';
import '../domain/courier_tracking.dart';
import '../domain/restaurant_models.dart';
import '../widgets/restaurant_checkout_sheet.dart' show restaurantsErrorText;
import 'courier_live_publisher.dart';
import 'restaurant_courier_logic.dart';

typedef RestaurantCompleteFn = Future<CourierCompletionSummary> Function({
  required bool delivered,
  required String failReason,
});

class RestaurantCourierOrderCard extends StatefulWidget {
  const RestaurantCourierOrderCard({
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
    required this.onFinalizeRoute,
    this.livePositions,
  });

  /// Тест учун жойлашув манбаи (S6); бўш бўлса ҳақиқий GPS.
  final Stream<LivePosition> Function()? livePositions;

  /// Маршрутдаги snapshot; жонли ҳолат `repository.watchOrder` дан.
  final OrderModel order;
  final int index;
  final bool isDone;
  final bool isCurrent;
  final bool needsFinalize;
  final RestaurantsRepository repository;

  /// `courierPickupRestaurantOrder` — хато ташлайди (код нотўғри бўлса
  /// `PICKUP_CODE_MISMATCH` + `attemptsLeft`), диалог ўзи кўрсатади.
  final Future<void> Function(String code) onPickup;
  final Future<void> Function() onArrive;
  final RestaurantCompleteFn onComplete;
  final Future<void> Function() onFinalizeRoute;

  @override
  State<RestaurantCourierOrderCard> createState() => _RestaurantCourierOrderCardState();
}

class _RestaurantCourierOrderCardState extends State<RestaurantCourierOrderCard> {
  late Stream<OrderModel?> _stream = widget.repository.watchOrder(widget.order.id);
  bool _busy = false;

  @override
  void didUpdateWidget(covariant RestaurantCourierOrderCard old) {
    super.didUpdateWidget(old);
    if (old.order.id != widget.order.id) {
      _stream = widget.repository.watchOrder(widget.order.id);
    }
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Colors.red.shade700 : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Муваффақият хабари — контроллер (`info`) кўрсатади; бу ерда фақат хато.
  Future<bool> _run(Future<void> Function() fn) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await fn();
      return true;
    } catch (e) {
      if (mounted) _snack(restaurantsErrorText(context, e), error: true);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _callRestaurant(OrderModel o) async {
    String phone = '';
    try {
      phone = (await widget.repository.getRestaurant(o.restaurantId))?.contactPhone ?? '';
    } catch (_) {}
    if (!mounted) return;
    if (phone.trim().isEmpty) {
      _snack(context.tr('restaurants_courier_no_phone'), error: true);
      return;
    }
    await callPhone(phone);
  }

  Future<void> _navigate(OrderModel o) async {
    final t = courierNavTarget(o);
    if (t == null) return;
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${t.lat},${t.lng}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _pickup(OrderModel o) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => _PickupCodeDialog(
        buyoutAmount: courierBuyoutAmount(o),
        onSubmit: widget.onPickup,
      ),
    );
  }

  Future<void> _deliver(OrderModel o) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('restaurants_courier_deliver_btn')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CollectSummary(order: o),
            const SizedBox(height: 10),
            Text(ctx.tr('restaurants_courier_deliver_confirm')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('restaurants_courier_deliver_btn'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    CourierCompletionSummary? res;
    final ok = await _run(() async {
      res = await widget.onComplete(delivered: true, failReason: 'other');
    });
    final r = res;
    if (!ok || r == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('restaurants_status_delivered')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ctx.tr('restaurants_courier_delivered_ok').replaceAll('{amount}', formatPrice(r.cashCollected))),
            if (r.walletFallback) ...[
              const SizedBox(height: 8),
              Text(
                ctx.tr('restaurants_courier_wallet_fallback').replaceAll('{amount}', formatPrice(r.deliveryFee)),
                style: TextStyle(color: ctx.ava.danger, fontWeight: FontWeight.w700),
              ),
            ] else if (r.walletPaid > 0) ...[
              const SizedBox(height: 8),
              Text(ctx.tr('restaurants_courier_wallet_paid').replaceAll('{amount}', formatPrice(r.walletPaid))),
            ],
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('ok')))],
      ),
    );
    await widget.onFinalizeRoute();
  }

  Future<void> _fail(OrderModel o) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(ctx.tr('restaurants_courier_fail_title'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            for (final r in courierFailReasons)
              ListTile(
                dense: true,
                leading: const Icon(Icons.radio_button_unchecked),
                title: Text(ctx.tr('restaurants_courier_fail_$r')),
                onTap: () => Navigator.pop(ctx, r),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(ctx.tr('restaurants_courier_fail_note'), style: TextStyle(fontSize: 12, color: ctx.ava.ink2)),
            ),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;
    final ok = await _run(() => widget.onComplete(delivered: false, failReason: reason));
    if (!ok || !mounted) return;
    _snack(context.tr('restaurants_courier_failed_ok'));
    await widget.onFinalizeRoute();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<OrderModel?>(
      stream: _stream,
      initialData: widget.order,
      builder: (context, snap) {
        final o = snap.data ?? widget.order;
        // Фаол буюртмада курьернинг жонли нуқтаси мижоз ва ресторан эгасига кўринади (S6). Карточка
        // йўқолса (тугади/маршрут ёпилди) ёзиш ўзи тўхтайди.
        final live = !widget.isDone && (o.courierId ?? '').isNotEmpty && CourierTracking.activeStatuses.contains(o.restaurantStatus);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (live)
              CourierLivePublisher(
                key: ValueKey('live-${o.id}'),
                orderId: o.id,
                courierId: o.courierId!,
                repository: widget.repository,
                positions: widget.livePositions,
              ),
            _card(context, o),
          ],
        );
      },
    );
  }

  Widget _card(BuildContext context, OrderModel o) {
    final c = context.ava;
    final stage = courierStageFor(o);
    final toRestaurant = stage == CourierRestaurantStage.preparing || stage == CourierRestaurantStage.pickup;
    final muted = widget.isDone;
    final title = toRestaurant ? o.restaurantName : (o.userName.isNotEmpty ? o.userName : o.userPhone);
    final subtitle = toRestaurant ? o.restaurantAddress : o.address;
    final buyout = courierBuyoutAmount(o);
    final feeKey = o.deliveryPaymentMethod == 'wallet' ? 'restaurants_courier_fee_wallet' : 'restaurants_courier_fee_cash';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: muted ? c.surface2 : c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.isCurrent ? c.brandText : c.line,
          width: widget.isCurrent ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IndexBadge(index: widget.index, muted: muted, current: widget.isCurrent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ExcludeSemantics(child: Icon(Icons.restaurant_rounded, size: 16, color: muted ? c.ink2 : c.brandText)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: muted ? c.ink2 : c.ink),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      Text(subtitle, style: TextStyle(fontSize: 12, color: c.ink2), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    context.tr(RestaurantOrderStatus.labelKey(o.restaurantStatus)),
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: muted ? c.ink2 : c.brandText),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${context.tr('restaurants_courier_items').replaceAll('{n}', '${o.items.fold<int>(0, (s, i) => s + i.count)}')} · ${formatPrice(o.foodAmount)} ${context.tr('currency_sum')}',
                  style: TextStyle(fontSize: 12, color: c.ink2),
                ),
                AvaChip(
                  label: context.tr(feeKey).replaceAll('{amount}', formatPrice(o.deliveryFee)),
                  tone: AvaChipTone.ok,
                  icon: Icons.delivery_dining,
                ),
                if (buyout > 0)
                  AvaChip(
                    label: context.tr('restaurants_courier_buyout_badge').replaceAll('{amount}', formatPrice(buyout)),
                    tone: AvaChipTone.warn,
                    icon: Icons.payments_outlined,
                  ),
              ],
            ),
            if (o.note.trim().isNotEmpty && widget.isCurrent) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(child: Icon(Icons.notes_rounded, size: 16, color: c.ink2)),
                  const SizedBox(width: 4),
                  Expanded(child: Text(o.note, style: TextStyle(fontSize: 12, color: c.ink2), maxLines: 2, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ],
            if (stage == CourierRestaurantStage.cancelled) ...[
              const SizedBox(height: 8),
              _Notice(icon: Icons.block, text: context.tr('restaurants_courier_cancelled_note'), color: c.danger, bg: c.dangerSoft),
            ],
            if (widget.needsFinalize) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : () async => widget.onFinalizeRoute(),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(context.tr('courier_next_order'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ] else if (widget.isCurrent)
              ..._stageActions(context, o, stage, buyout),
          ],
        ),
      ),
    );
  }

  List<Widget> _stageActions(BuildContext context, OrderModel o, CourierRestaurantStage stage, int buyout) {
    final c = context.ava;
    final toRestaurant = stage == CourierRestaurantStage.preparing || stage == CourierRestaurantStage.pickup;
    final contactRow = Row(children: [
      Expanded(
        child: _SmallBtn(
          icon: Icons.call,
          label: context.tr(toRestaurant ? 'restaurants_courier_call_restaurant' : 'restaurants_courier_call_customer'),
          onTap: () => toRestaurant ? _callRestaurant(o) : callPhone(o.userPhone),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _SmallBtn(
          icon: Icons.navigation,
          label: context.tr('courier_navigate'),
          onTap: courierNavTarget(o) == null ? null : () => _navigate(o),
        ),
      ),
    ]);

    switch (stage) {
      case CourierRestaurantStage.preparing:
        return [
          const SizedBox(height: 8),
          _Notice(
            icon: Icons.hourglass_top_rounded,
            text: context.tr('restaurants_courier_preparing').replaceAll('{min}', '${o.prepTimeMin}'),
            color: c.warn,
            bg: c.warnSoft,
          ),
          const SizedBox(height: 8),
          contactRow,
        ];
      case CourierRestaurantStage.pickup:
        return [
          const SizedBox(height: 8),
          if (buyout > 0) ...[
            _Notice(
              icon: Icons.payments_outlined,
              text: context.tr('restaurants_courier_pay_restaurant').replaceAll('{amount}', formatPrice(buyout)),
              color: c.warn,
              bg: c.warnSoft,
            ),
            const SizedBox(height: 8),
          ],
          contactRow,
          const SizedBox(height: 8),
          _BigBtn(label: context.tr('restaurants_courier_pickup_btn'), busy: _busy, onTap: () => _pickup(o)),
        ];
      case CourierRestaurantStage.toCustomer:
        return [
          const SizedBox(height: 8),
          contactRow,
          const SizedBox(height: 8),
          _BigBtn(label: context.tr('restaurants_courier_arrive_btn'), busy: _busy, onTap: () => _run(widget.onArrive)),
          _failLink(context, o),
        ];
      case CourierRestaurantStage.handover:
        return [
          const SizedBox(height: 8),
          _CollectSummary(order: o),
          const SizedBox(height: 8),
          contactRow,
          const SizedBox(height: 8),
          _BigBtn(label: context.tr('restaurants_courier_deliver_btn'), busy: _busy, onTap: () => _deliver(o)),
          _failLink(context, o),
        ];
      case CourierRestaurantStage.done:
      case CourierRestaurantStage.cancelled:
        return const [];
    }
  }

  Widget _failLink(BuildContext context, OrderModel o) {
    if (!courierCanFail(o)) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: _busy ? null : () => _fail(o),
        style: TextButton.styleFrom(foregroundColor: context.ava.danger),
        child: Text(context.tr('restaurants_courier_fail_btn'), style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

/// «Мижоздан олинг»: выкуп · нақд етказиш · жами; ҳамён бўлса — изоҳ.
class _CollectSummary extends StatelessWidget {
  const _CollectSummary({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final buyout = courierBuyoutAmount(order);
    final feeCash = order.deliveryPaymentMethod == 'cash' ? order.deliveryFee : 0;
    final total = courierCashToCollect(order);
    final cur = context.tr('currency_sum');
    TextStyle line([Color? color]) => TextStyle(fontSize: 12.5, color: color ?? c.ink);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('restaurants_courier_collect_title'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.ink2)),
          const SizedBox(height: 4),
          if (buyout > 0) Text(context.tr('restaurants_courier_collect_food').replaceAll('{amount}', formatPrice(buyout)), style: line()),
          if (feeCash > 0) Text(context.tr('restaurants_courier_collect_fee').replaceAll('{amount}', formatPrice(feeCash)), style: line()),
          if (total > 0)
            Text('${formatPrice(total)} $cur', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.brandText))
          else
            Text(context.tr('restaurants_courier_collect_none'), style: line(c.ok)),
          if (order.deliveryPaymentMethod == 'wallet')
            Text(context.tr('restaurants_courier_fee_from_wallet'), style: TextStyle(fontSize: 12, color: c.ink2)),
        ],
      ),
    );
  }
}

/// Ресторан коди (4 рақам). Нотўғри код — диалог очиқ қолади, қолган
/// уринишлар кўрсатилади (`PICKUP_CODE_MISMATCH.attemptsLeft`).
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
      setState(() => _error = context.tr('restaurants_courier_pickup_hint'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(code);
      if (mounted) Navigator.pop(context, true);
    } on RestaurantsException catch (e) {
      if (!mounted) return;
      final left = (e.details?['attemptsLeft'] as num?)?.toInt();
      setState(() => _error = e.reason == 'PICKUP_CODE_MISMATCH' && left != null
          ? context.tr('restaurants_courier_pickup_wrong').replaceAll('{n}', '$left')
          : restaurantsErrorText(context, e));
    } catch (e) {
      if (mounted) setState(() => _error = restaurantsErrorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return AlertDialog(
      title: Text(context.tr('restaurants_courier_pickup_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('restaurants_courier_pickup_hint'), style: TextStyle(fontSize: 12, color: c.ink2)),
          if (widget.buyoutAmount > 0) ...[
            const SizedBox(height: 6),
            Text(
              context.tr('restaurants_courier_pay_restaurant').replaceAll('{amount}', formatPrice(widget.buyoutAmount)),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.warn),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            autofocus: true,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 8),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              counterText: '',
              errorText: _error,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text(context.tr('cancel'))),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(context.tr('restaurants_courier_pickup_btn')),
        ),
      ],
    );
  }
}

class _IndexBadge extends StatelessWidget {
  const _IndexBadge({required this.index, required this.muted, required this.current});

  final int index;
  final bool muted;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: muted
            ? c.line
            : current
                ? AppColors.primaryDark
                : c.brandSoft,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '${index + 1}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: muted
                ? c.ink2
                : current
                    ? AppColors.onPrimary
                    : c.brandText,
          ),
        ),
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  const _SmallBtn({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const color = AppColors.primaryText;
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigBtn extends StatelessWidget {
  const _BigBtn({required this.label, required this.busy, required this.onTap});

  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonal(
        onPressed: busy ? null : onTap,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          minimumSize: const Size(0, 48),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        child: busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.color, required this.bg});

  final IconData icon;
  final String text;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color))),
      ]),
    );
  }
}
