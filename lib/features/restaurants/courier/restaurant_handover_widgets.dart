// Буюртмани топшириш UI (эга, 2026-10-31): курьер → бошқа курьер / ресторан.
// Рухсат, код, муддат ва пул — серверда; бу ерда фақат танлаш, кодни кўрсатиш ва киритиш.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/order_model.dart';
import '../data/restaurants_repository.dart';
import '../domain/handover.dart';
import '../widgets/restaurant_checkout_sheet.dart' show restaurantsErrorText;

typedef HandoverLocation = ({double lat, double lng})? Function();

String _hhmm(DateTime t) {
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

void _snack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: error ? Colors.red.shade700 : null,
    behavior: SnackBarBehavior.floating,
  ));
}

/// «Топшириш» оқими. Олишдан олдин — тасдиқ ва қўйиб юбориш; олгандан кейин —
/// кимга (курьер / ресторан) танланади, код ойнаси очилади.
Future<void> showCourierHandoverFlow(
  BuildContext context, {
  required RestaurantsRepository repository,
  required OrderModel order,
  HandoverLocation? location,
}) async {
  if (handoverIsRelease(order)) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('restaurants_handover_release_title')),
        content: Text(ctx.tr('restaurants_handover_release_q')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('restaurants_handover_release_btn'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await repository.startHandover(order.id, target: 'seller');
      if (context.mounted) _snack(context, context.tr('restaurants_handover_released'));
    } catch (e) {
      if (context.mounted) _snack(context, restaurantsErrorText(context, e), error: true);
    }
    return;
  }
  final target = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(ctx.tr('restaurants_handover_title'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          ListTile(
            key: const ValueKey('handover-to-courier'),
            leading: const Icon(Icons.delivery_dining),
            title: Text(ctx.tr('restaurants_handover_to_courier')),
            subtitle: handoverToCourierAllowed(order) ? null : Text(ctx.tr('restaurants_handover_buyout_note')),
            enabled: handoverToCourierAllowed(order),
            onTap: () => Navigator.pop(ctx, 'courier'),
          ),
          ListTile(
            key: const ValueKey('handover-to-seller'),
            leading: const Icon(Icons.storefront_outlined),
            title: Text(ctx.tr('restaurants_handover_to_seller')),
            onTap: () => Navigator.pop(ctx, 'seller'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(ctx.tr('restaurants_handover_note'), style: TextStyle(fontSize: 12, color: ctx.ava.ink2)),
          ),
        ],
      ),
    ),
  );
  if (target == null || !context.mounted) return;
  final loc = location?.call();
  HandoverStart res;
  try {
    res = await repository.startHandover(order.id, target: target, lat: loc?.lat, lng: loc?.lng);
  } catch (e) {
    if (context.mounted) _snack(context, restaurantsErrorText(context, e), error: true);
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => HandoverCodeDialog(
      code: res.code,
      target: target,
      expiresAt: res.expiresAt,
      onCancel: () => repository.cancelHandover(order.id),
    ),
  );
}

/// Курьер экранида: кодни бошқа курьерга ёки ресторанга айтинг.
class HandoverCodeDialog extends StatefulWidget {
  const HandoverCodeDialog({super.key, required this.code, required this.target, this.expiresAt, required this.onCancel});

  final String code;
  final String target;
  final DateTime? expiresAt;
  final Future<void> Function() onCancel;

  @override
  State<HandoverCodeDialog> createState() => _HandoverCodeDialogState();
}

class _HandoverCodeDialogState extends State<HandoverCodeDialog> {
  bool _busy = false;

  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      await widget.onCancel();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _snack(context, restaurantsErrorText(context, e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final exp = widget.expiresAt;
    return AlertDialog(
      title: Text(context.tr(widget.target == 'seller' ? 'restaurants_handover_code_seller' : 'restaurants_handover_code_courier')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(
            widget.code,
            key: const ValueKey('handover-code'),
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 6, color: c.brandText),
          ),
          if (exp != null) ...[
            const SizedBox(height: 6),
            Text(context.tr('restaurants_handover_code_until').replaceAll('{time}', _hhmm(exp)),
                style: TextStyle(fontSize: 12, color: c.ink2)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _cancel,
          style: TextButton.styleFrom(foregroundColor: c.danger),
          child: Text(context.tr('restaurants_handover_cancel')),
        ),
        FilledButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(context.tr('ok'))),
      ],
    );
  }
}

/// Курьер Б: бошқа курьердан буюртмани олиш — 6 хонали код. [onSubmit] хато
/// бўлса ташлайди (ойна очиқ қолади ва хато кўрсатилади).
class AcceptHandoverDialog extends StatefulWidget {
  const AcceptHandoverDialog({super.key, required this.onSubmit});

  final Future<void> Function(String code) onSubmit;

  @override
  State<AcceptHandoverDialog> createState() => _AcceptHandoverDialogState();
}

class _AcceptHandoverDialogState extends State<AcceptHandoverDialog> {
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
    if (!isHandoverCode(code)) {
      setState(() => _error = context.tr('restaurants_handover_code_hint'));
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
      if (mounted) setState(() => _error = restaurantsErrorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('restaurants_handover_accept_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('restaurants_handover_accept_hint'), style: TextStyle(fontSize: 12, color: context.ava.ink2)),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('handover-accept-code'),
            controller: _ctrl,
            autofocus: true,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 6),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            decoration: InputDecoration(border: const OutlineInputBorder(), counterText: '', errorText: _error, errorMaxLines: 3),
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
              : Text(context.tr('restaurants_handover_accept_btn')),
        ),
      ],
    );
  }
}

/// Ресторан панели: курьер буюртмани қайтармоқда — курьер экранидаги кодни киритинг.
class MerchantReturnPanel extends StatefulWidget {
  const MerchantReturnPanel({super.key, required this.order, required this.onSubmit});

  final OrderModel order;

  /// `restaurantAcceptReturn`; хато бўлса ташлайди.
  final Future<void> Function(String code) onSubmit;

  @override
  State<MerchantReturnPanel> createState() => _MerchantReturnPanelState();
}

class _MerchantReturnPanelState extends State<MerchantReturnPanel> {
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
    if (!isHandoverCode(code)) {
      setState(() => _error = context.tr('restaurants_handover_code_hint'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(code);
      if (mounted) {
        _ctrl.clear();
        _snack(context, context.tr('restaurants_m_return_ok'));
      }
    } on RestaurantsException catch (e) {
      final left = (e.details?['attemptsLeft'] as num?)?.toInt();
      if (mounted) {
        setState(() => _error = e.reason == 'HANDOVER_CODE_MISMATCH' && left != null
            ? context.tr('restaurants_courier_pickup_wrong').replaceAll('{n}', '$left')
            : restaurantsErrorText(context, e));
      }
    } catch (e) {
      if (mounted) setState(() => _error = restaurantsErrorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      key: ValueKey('return-panel-${widget.order.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('restaurants_m_return_title'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c.warn)),
          const SizedBox(height: 4),
          Text(context.tr('restaurants_m_return_hint'), style: TextStyle(fontSize: 12.5, color: c.ink2)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: ValueKey('return-code-${widget.order.id}'),
                  controller: _ctrl,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), counterText: '', errorText: _error, errorMaxLines: 3),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(context.tr('restaurants_m_return_btn')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
