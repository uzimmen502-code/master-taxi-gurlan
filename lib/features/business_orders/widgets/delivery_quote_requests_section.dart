// «Бозорлар» STAGE 11 — курьер ва админ: очиқ «Етказиш нархи сўровлари» (`listOpenDeliveryQuotes`) ва нарх
// юбориш (`respondDeliveryQuote`; биринчи жавоб ғолиб — сервер `QUOTE_ALREADY_ANSWERED`). Мижоз манзили ва
// телефон охири — фақат админга (сервер проекцияси, 40-қоида). Ягона виджет: курьер рўйхати ва админ панели.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../home/widgets/ava_chip.dart';
import '../../restaurants/widgets/restaurant_row.dart' show formatDistanceLabel;
import '../data/business_orders_repository.dart';
import '../domain/delivery_quote.dart';
import 'business_order_widgets.dart';

class DeliveryQuoteRequestsSection extends StatefulWidget {
  const DeliveryQuoteRequestsSection({
    super.key,
    required this.repository,
    this.lat,
    this.lng,
    this.radiusKm,
    this.refreshTick = 0,
    this.showErrors = false,
  });

  final BusinessOrdersRepository repository;
  final double? lat;
  final double? lng;
  final int? radiusKm;

  /// Ўзгарса — рўйхат қайта юкланади (ота экран «Янгилаш»).
  final int refreshTick;

  /// Админ: хато матни кўрсатилади. Курьер: хато (масалан тасдиқланмаган) — бўлим кўринмайди.
  final bool showErrors;

  @override
  State<DeliveryQuoteRequestsSection> createState() => _DeliveryQuoteRequestsSectionState();
}

class _DeliveryQuoteRequestsSectionState extends State<DeliveryQuoteRequestsSection> {
  late Future<OpenDeliveryQuotes> _future = _load();
  final Map<String, TextEditingController> _ctrls = {};
  String? _sendingId;

  Future<OpenDeliveryQuotes> _load() =>
      widget.repository.listOpenDeliveryQuotes(lat: widget.lat, lng: widget.lng, radiusKm: widget.radiusKm);

  @override
  void didUpdateWidget(covariant DeliveryQuoteRequestsSection old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick || old.radiusKm != widget.radiusKm || old.lat != widget.lat) {
      _future = _load();
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _reload() {
    final next = _load();
    setState(() {
      _future = next;
    });
  }

  Future<void> _respond(OpenDeliveryQuote q) async {
    if (_sendingId != null) return;
    final price = parseQuotePrice(_ctrls[q.id]?.text ?? '');
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (price == null) {
      messenger?.showSnackBar(SnackBar(content: Text(context.tr('dq_err_price_invalid'))));
      return;
    }
    setState(() => _sendingId = q.id);
    try {
      await widget.repository.respondDeliveryQuote(quoteId: q.id, priceUzs: price);
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text(context.tr('dq_respond_ok'))));
      _ctrls.remove(q.id)?.dispose();
      _reload();
    } catch (e) {
      if (!mounted) return;
      messenger?.showSnackBar(SnackBar(content: Text(bizOrderErrorText(context, e)), backgroundColor: context.ava.danger));
      _reload();
    } finally {
      if (mounted) setState(() => _sendingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return FutureBuilder<OpenDeliveryQuotes>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return widget.showErrors
              ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
              : const SizedBox.shrink();
        }
        if (snap.hasError) {
          if (!widget.showErrors) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(children: [
              Text(bizOrderErrorText(context, snap.error!), textAlign: TextAlign.center, style: TextStyle(color: c.ink2)),
              TextButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh, size: 18), label: Text(context.tr('restaurants_courier_refresh'))),
            ]),
          );
        }
        final res = snap.data ?? const OpenDeliveryQuotes([]);
        if (res.quotes.isEmpty && !widget.showErrors) return const SizedBox.shrink();
        return Column(
          key: const ValueKey('dq_requests_section'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('dq_requests_title'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c.ink)),
            const SizedBox(height: 2),
            Text(context.tr('dq_requests_hint'), style: TextStyle(fontSize: 12, color: c.ink2)),
            const SizedBox(height: 8),
            if (res.quotes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(context.tr('dq_requests_empty'), textAlign: TextAlign.center, style: TextStyle(color: c.ink2)),
              ),
            for (final q in res.quotes) ...[
              _QuoteCard(
                quote: q,
                admin: res.isAdmin,
                controller: _ctrls.putIfAbsent(q.id, TextEditingController.new),
                busy: _sendingId == q.id,
                disabled: _sendingId != null,
                onSend: () => _respond(q),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 6),
          ],
        );
      },
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    required this.quote,
    required this.admin,
    required this.controller,
    required this.busy,
    required this.disabled,
    required this.onSend,
  });

  final OpenDeliveryQuote quote;
  final bool admin;
  final TextEditingController controller;
  final bool busy;
  final bool disabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final q = quote;
    return Container(
      key: ValueKey('dq_card_${q.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(AvaRadius.card), border: Border.all(color: c.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q.itemTitle, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink)),
          Text(context.tr('dq_qty_line').replaceAll('{n}', '${q.qty}'), style: TextStyle(fontSize: 12, color: c.ink2)),
          if (q.sellerName.isNotEmpty || q.pickupAddress.isNotEmpty)
            Text(
              [q.sellerName, q.pickupAddress].where((s) => s.isNotEmpty).join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: c.ink2),
            ),
          if (admin && q.address.isNotEmpty)
            Text(
              '${context.tr('biz_order_address')}: ${q.address}${q.buyerPhoneTail.isNotEmpty ? ' · ***${q.buyerPhoneTail}' : ''}',
              style: TextStyle(fontSize: 12, color: c.ink),
            ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (q.courierToPickupM != null)
              AvaChip(
                icon: Icons.storefront_outlined,
                label: context.tr('biz_order_courier_to_shop').replaceAll('{dist}', formatDistanceLabel(context, q.courierToPickupM! / 1000)),
              ),
            if (q.distanceMeters != null)
              AvaChip(
                icon: Icons.person_pin_circle_outlined,
                label: context.tr('restaurants_courier_to_customer').replaceAll('{dist}', formatDistanceLabel(context, q.distanceMeters! / 1000)),
              ),
            if (q.floor != null)
              AvaChip(icon: Icons.stairs_outlined, label: context.tr('dq_floor_chip').replaceAll('{n}', '${q.floor}')),
          ]),
          if (q.note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(q.note, style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: c.ink2)),
          ],
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                key: ValueKey('dq_price_${q.id}'),
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(kQuotePriceMaxDigits)],
                decoration: InputDecoration(
                  labelText: context.tr('dq_price_label'),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: ValueKey('dq_send_${q.id}'),
              onPressed: disabled ? null : onSend,
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                foregroundColor: c.brandInk,
                minimumSize: const Size(96, 48),
              ),
              child: busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(context.tr('dq_respond')),
            ),
          ]),
        ],
      ),
    );
  }
}
