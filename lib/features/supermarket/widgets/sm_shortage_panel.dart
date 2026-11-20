import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/idempotency_keys.dart';
import '../../../models/order_model.dart';
import '../../../shared/widgets/wallet_topup_ui.dart';
import '../data/supermarket_repository.dart';
import '../domain/sm_access.dart';
import '../domain/sm_offer.dart';
import '../domain/sm_qty.dart';
import '../domain/sm_shortage.dart';
import 'sm_widgets.dart';

/// Буюртма тафсилотида етишмовчилик қаторлари (2-босқич, эга 2026-11-21): ўрнини босувчи (нарх фарқи ва
/// ҳамёнга таъсири) / мавжуд миқдоргача камайтириш / олиб ташлаш. Юбориш пайтида ўчиқ; `clientRequestId`
/// ҳар қатор учун БИР МАРТА ясалади ва аниқ рад бўлгунча ўзгармайди (21-банд).
class SmShortagePanel extends StatefulWidget {
  const SmShortagePanel({super.key, required this.order, this.api, this.keys, this.openTopUp});

  final OrderModel order;

  /// Тест учун; бўлмаса — [FirebaseSupermarketApi].
  final SupermarketApi? api;
  final IdempotencyKeys? keys;
  final void Function(BuildContext context)? openTopUp;

  static List<SmShortage> shortagesOf(OrderModel o) =>
      [for (final i in o.items) if (SmShortage.fromItem(i.raw) case final s?) s];

  @override
  State<SmShortagePanel> createState() => _SmShortagePanelState();
}

class _SmShortagePanelState extends State<SmShortagePanel> {
  // Қайта қурилишда ҳам ЎША калитлар (иккинчи юбориш — иккинчи амал эмас).
  late final SupermarketApi _api = widget.api ?? FirebaseSupermarketApi();
  late final IdempotencyKeys _keys = widget.keys ?? IdempotencyKeys();

  @override
  Widget build(BuildContext context) {
    final list = SmShortagePanel.shortagesOf(widget.order);
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in list) ...[
          SmShortageCard(orderId: widget.order.id, shortage: s, api: _api, keys: _keys, openTopUp: widget.openTopUp),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class SmShortageCard extends StatefulWidget {
  const SmShortageCard({
    super.key,
    required this.orderId,
    required this.shortage,
    required this.api,
    required this.keys,
    this.openTopUp,
  });

  final String orderId;
  final SmShortage shortage;
  final SupermarketApi api;
  final IdempotencyKeys keys;
  final void Function(BuildContext context)? openTopUp;

  @override
  State<SmShortageCard> createState() => _SmShortageCardState();
}

class _SmShortageCardState extends State<SmShortageCard> {
  late final Future<List<SmOffer>> _subs = widget.shortage.substitutes.isEmpty
      ? Future.value(const <SmOffer>[])
      : widget.api.loadOffersByIds(widget.shortage.substitutes).catchError((Object e) {
          debugPrint('[Supermarket] SM_SHORTAGE_SUBS_FAILED: $e');
          return const <SmOffer>[];
        });

  SmShortageChoice? _choice;
  SmOffer? _sub;
  bool _busy = false;
  bool _done = false;
  String? _errorKey;
  Map<String, String> _errorMessages = const {};
  bool _needTopUp = false;

  String get _scope => 'sm_shortage:${widget.orderId}:${widget.shortage.productId}';

  Future<void> _submit() async {
    final choice = _choice;
    if (choice == null || _busy) return;
    setState(() {
      _busy = true;
      _errorKey = null;
      _errorMessages = const {};
      _needTopUp = false;
    });
    try {
      await widget.api.respondShortage(smShortagePayload(
        orderId: widget.orderId,
        shortage: widget.shortage,
        choice: choice,
        substitute: _sub,
        clientRequestId: widget.keys.keyFor(_scope),
      ));
      widget.keys.settled(_scope);
      if (mounted) setState(() => _done = true);
    } on SmCallError catch (e) {
      debugPrint('[Supermarket] SM_SHORTAGE_RESPOND_FAILED code=${e.code}');
      // Тармоқ хатоси — ўша калит билан қайта уриниш (иккинчи марта бажарилмайди); аниқ рад — янги калит.
      if (e.key != 'sm_err_network') widget.keys.settled(_scope);
      if (mounted) {
        setState(() {
          _errorKey = e.key;
          _errorMessages = e.messages;
          _needTopUp = e.key == 'sm_err_insufficient_funds';
        });
      }
    } catch (e) {
      debugPrint('[Supermarket] SM_SHORTAGE_RESPOND_FAILED: $e');
      if (mounted) setState(() => _errorKey = 'sm_err_network');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final s = widget.shortage;
    final lang = context.contentLang;
    return Container(
      key: ValueKey('sm_shortage_${s.productId}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.warn, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.inventory_2_outlined, color: c.warn),
            const SizedBox(width: 8),
            Expanded(
              child: Text(context.tr('sm_shortage_title'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            context
                .tr('sm_shortage_body')
                .replaceAll('{name}', s.name)
                .replaceAll('{qty}', smFormatQty(s.qtyMilli))
                .replaceAll('{avail}', smFormatQty(s.availableQtyMilli)),
            style: TextStyle(fontSize: 15, color: c.ink),
          ),
          if (_done) ...[
            const SizedBox(height: 8),
            Text(context.tr('sm_shortage_done'),
                key: ValueKey('sm_shortage_done_${s.productId}'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ok)),
          ] else ...[
            FutureBuilder<List<SmOffer>>(
              future: _subs,
              builder: (context, snap) {
                final subs = (snap.data ?? const <SmOffer>[]).where((o) => o.available).toList();
                if (snap.connectionState != ConnectionState.done && s.substitutes.isNotEmpty) {
                  return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (subs.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(context.tr('sm_shortage_substitute'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink)),
                      for (final o in subs)
                        _Option(
                          key: ValueKey('sm_shortage_sub_${o.id}'),
                          selected: _choice == SmShortageChoice.substitute && _sub?.id == o.id,
                          enabled: !_busy,
                          title: [o.name, o.qualityName(lang), o.packLabel].where((x) => x.isNotEmpty).join(' · '),
                          lines: [
                            '${smFormatQty(smShortageSubstituteQty(s, o))} ${smUnitLabel(context, o.unit)} × '
                                '${smPricePerUnit(context, o.price, o.unit)}',
                            _priceDiff(context, smLineTotal(o.price, smShortageSubstituteQty(s, o)) - s.lineTotal),
                          ],
                          delta: smShortageWalletDelta(s, SmShortageChoice.substitute, substitute: o),
                          onTap: () => setState(() {
                            _choice = SmShortageChoice.substitute;
                            _sub = o;
                          }),
                        ),
                    ],
                    const SizedBox(height: 4),
                    if (s.canReduce)
                      _Option(
                        key: const ValueKey('sm_shortage_reduce'),
                        selected: _choice == SmShortageChoice.reduce,
                        enabled: !_busy,
                        title: context.tr('sm_shortage_reduce').replaceAll('{avail}', smFormatQty(s.availableQtyMilli)),
                        lines: const [],
                        delta: smShortageWalletDelta(s, SmShortageChoice.reduce),
                        onTap: () => setState(() {
                          _choice = SmShortageChoice.reduce;
                          _sub = null;
                        }),
                      ),
                    _Option(
                      key: const ValueKey('sm_shortage_remove'),
                      selected: _choice == SmShortageChoice.remove,
                      enabled: !_busy,
                      title: context.tr('sm_shortage_remove'),
                      lines: const [],
                      delta: smShortageWalletDelta(s, SmShortageChoice.remove),
                      onTap: () => setState(() {
                        _choice = SmShortageChoice.remove;
                        _sub = null;
                      }),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 4),
            Text(context.tr('sm_shortage_estimate_note'), style: TextStyle(fontSize: 13, color: c.ink2)),
            if (_errorKey != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessages.isNotEmpty ? smServerMessage(_errorMessages, lang) : context.tr(_errorKey!),
                key: ValueKey('sm_shortage_error_${s.productId}'),
                style: TextStyle(fontSize: 15, color: c.danger),
              ),
            ],
            if (_needTopUp)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton(
                  key: ValueKey('sm_shortage_topup_${s.productId}'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () => widget.openTopUp != null
                      ? widget.openTopUp!(context)
                      : openWalletTopUp(Navigator.of(context)),
                  child: Text(context.tr('sm_topup'), style: const TextStyle(fontSize: 16)),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(
              key: ValueKey('sm_shortage_submit_${s.productId}'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _choice == null || _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(context.tr('sm_shortage_submit'), style: const TextStyle(fontSize: 16)),
            ),
          ],
        ],
      ),
    );
  }

  String _priceDiff(BuildContext context, int diff) {
    if (diff == 0) return context.tr('sm_shortage_same_price');
    final key = diff > 0 ? 'sm_shortage_more' : 'sm_shortage_less';
    return context.tr(key).replaceAll('{sum}', formatMoney(diff.abs()));
  }
}

class _Option extends StatelessWidget {
  const _Option({
    super.key,
    required this.selected,
    required this.enabled,
    required this.title,
    required this.lines,
    required this.delta,
    required this.onTap,
  });

  final bool selected;
  final bool enabled;
  final String title;
  final List<String> lines;

  /// Ҳамёнга тахминий таъсир: мусбат — яна ечилади, манфий — қайтади.
  final int delta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final wallet = delta == 0
        ? context.tr('sm_shortage_wallet_none')
        : context
            .tr(delta > 0 ? 'sm_shortage_wallet_charge' : 'sm_shortage_wallet_refund')
            .replaceAll('{sum}', formatMoney(delta.abs()));
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: selected ? c.brandSoft : c.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? c.brand : c.line, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: selected ? c.brandText : c.ink2),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink)),
                    for (final l in lines) Text(l, style: TextStyle(fontSize: 14, color: c.ink2)),
                    Text(wallet,
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600, color: delta > 0 ? c.warn : (delta < 0 ? c.ok : c.ink2))),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
