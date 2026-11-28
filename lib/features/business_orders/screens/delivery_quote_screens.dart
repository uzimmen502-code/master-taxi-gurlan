// «Бозорлар» STAGE 11 (эга 2026-11-16) — йирик маиший техника: «Етказиш нархини сўраш».
//
// Харидор: сўров варағи (миқдор · манзил харитада · қават · изоҳ) → `requestDeliveryQuote` → ҳолат экрани
// (`delivery_quotes/{id}` оқими): кутилмоқда → нарх таклиф қилинди → «Тасдиқлаш» (`acceptDeliveryQuote`) → мавжуд
// буюртма экрани ([BusinessOrderScreen]). Нарх, муддат ва ўтишлар — фақат серверда (18/44-қоида).
// Ҳолат ҳужжатини ўқиш rules'и ҳали deploy қилинмаган бўлиши мумкин — рухсат хатосида «кутилмоқда» + қўлда янгилаш.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/map_picker_result.dart';
import '../../../repositories/user_repository.dart';
import '../../map_picker/screens/map_picker_screen.dart';
import '../../tv_market/models/tv_shop.dart';
import '../data/business_orders_repository.dart';
import '../domain/delivery_quote.dart';
import '../widgets/business_order_widgets.dart';
import 'business_order_screen.dart';

/// Харитадан танланган нуқта ёки профил манзили (0,0 — йўқ).
typedef DqPlace = ({double lat, double lng, String label});

bool _validPlace(double lat, double lng) => lat.abs() <= 90 && lng.abs() <= 180 && !(lat == 0 && lng == 0);

/// Сўров варағини очади; юборилса — ҳолат экранига ўтади.
Future<void> openDeliveryQuoteRequest(
  BuildContext context, {
  required TvShopItem item,
  required BusinessOrdersRepository repository,
}) async {
  final quoteId = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: context.ava.surface,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: DeliveryQuoteRequestSheet(item: item, repository: repository),
    ),
  );
  if (quoteId == null || quoteId.isEmpty || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => DeliveryQuoteStatusScreen(quoteId: quoteId, repository: repository, fallbackTitle: item.title),
  ));
}

class DeliveryQuoteRequestSheet extends StatefulWidget {
  const DeliveryQuoteRequestSheet({
    super.key,
    required this.item,
    required this.repository,
    @visibleForTesting this.loadPlace,
    @visibleForTesting this.pickPlace,
  });

  final TvShopItem item;
  final BusinessOrdersRepository repository;

  /// Тест учун: бошланғич манзил (бўлмаса — профилдаги манзил).
  final Future<DqPlace?> Function()? loadPlace;

  /// Тест учун: харитада танлаш (бўлмаса — мавжуд [MapPickerScreen]).
  final Future<DqPlace?> Function(BuildContext context)? pickPlace;

  @override
  State<DeliveryQuoteRequestSheet> createState() => _DeliveryQuoteRequestSheetState();
}

class _DeliveryQuoteRequestSheetState extends State<DeliveryQuoteRequestSheet> {
  final _floorCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  int _qty = 1;
  DqPlace? _place;
  bool _sending = false;
  String? _floorError;

  @override
  void initState() {
    super.initState();
    _loadPlace();
  }

  @override
  void dispose() {
    _floorCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<DqPlace?> _profilePlace() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = phoneDigits(prefs.getString('user_phone') ?? '');
    if (phone.length < 9 || !mounted) return null;
    final a = (await context.read<UserRepository>().getById(phone))?.address;
    if (a == null || a.lat == null || a.lng == null || !_validPlace(a.lat!, a.lng!)) return null;
    return (lat: a.lat!, lng: a.lng!, label: a.formatted);
  }

  Future<void> _loadPlace() async {
    try {
      final p = await (widget.loadPlace?.call() ?? _profilePlace());
      if (mounted && p != null && _place == null) setState(() => _place = p);
    } catch (e) {
      debugPrint('[DeliveryQuote] profile place: $e');
    }
  }

  Future<void> _pick() async {
    final custom = widget.pickPlace;
    DqPlace? next;
    if (custom != null) {
      next = await custom(context);
    } else {
      final r = await Navigator.of(context).push<MapPickerResult>(
        MaterialPageRoute(builder: (_) => MapPickerScreen(title: context.tr('dq_pick_address'))),
      );
      if (r != null && _validPlace(r.lat, r.lng)) next = (lat: r.lat, lng: r.lng, label: r.label);
    }
    if (!mounted || next == null) return;
    setState(() => _place = next);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(Navigator.of(context, rootNavigator: true).context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: context.ava.danger, behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _send() async {
    final p = _place;
    if (_sending) return;
    if (p == null) {
      _showError(context.tr('biz_order_err_address_required'));
      return;
    }
    final floor = parseQuoteFloor(_floorCtrl.text);
    if (floor == -1) {
      setState(() => _floorError =
          context.tr('dq_err_floor_invalid').replaceAll('{max}', '${DeliveryQuoteLimits.maxFloor}'));
      return;
    }
    setState(() {
      _floorError = null;
      _sending = true;
    });
    try {
      final label = p.label.trim();
      final res = await widget.repository.requestDeliveryQuote(
        itemId: widget.item.id,
        qty: _qty,
        lat: p.lat,
        lng: p.lng,
        address: label.length > DeliveryQuoteLimits.maxText ? label.substring(0, DeliveryQuoteLimits.maxText) : label,
        floor: floor,
        note: _noteCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(res.quoteId);
    } catch (e) {
      if (!mounted) return;
      _showError(bizOrderErrorText(context, e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final it = widget.item;
    final p = _place;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AvaSpace.screen, 0, AvaSpace.screen, AvaSpace.screen),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('dq_request_title'), style: AvaText.sectionTitle.copyWith(color: c.ink)),
            const SizedBox(height: 4),
            Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: c.ink2)),
            const SizedBox(height: 8),
            BizOrderNotice(
              icon: Icons.local_shipping_outlined,
              text: context.tr('dq_request_explain'),
              color: c.brandText,
              background: c.brandSoft,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(context.tr('dq_qty'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
                ),
                IconButton.filledTonal(
                  key: const ValueKey('dq_qty_minus'),
                  tooltip: context.tr('biz_order_qty_less'),
                  onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(bizOrderQtyLabel(context, _qty, it.priceUnit),
                      key: const ValueKey('dq_qty'),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.ink)),
                ),
                IconButton.filledTonal(
                  key: const ValueKey('dq_qty_plus'),
                  tooltip: context.tr('biz_order_qty_more'),
                  onPressed: _qty < DeliveryQuoteLimits.maxQty ? () => setState(() => _qty++) : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(context.tr('biz_order_address'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 4),
            InkWell(
              key: const ValueKey('dq_address'),
              onTap: _pick,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                constraints: const BoxConstraints(minHeight: AvaTap.minSize),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: p != null ? c.surface2 : c.warnSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p != null ? c.line : c.warn),
                ),
                child: Row(children: [
                  Icon(Icons.place_outlined, size: 18, color: p != null ? c.ink2 : c.warn),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p == null
                          ? context.tr('biz_order_address_needed')
                          : (p.label.trim().isNotEmpty ? p.label : context.tr('dq_address_on_map')),
                      style: TextStyle(fontSize: 13, color: p != null ? c.ink : c.warn),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(context.tr('biz_order_address_change'), style: TextStyle(fontSize: 12, color: c.brandText)),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('dq_floor'),
              controller: _floorCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
              decoration: InputDecoration(
                labelText: context.tr('dq_floor_label'),
                hintText: context.tr('dq_floor_hint'),
                errorText: _floorError,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('dq_note'),
              controller: _noteCtrl,
              maxLength: DeliveryQuoteLimits.maxText,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: context.tr('dq_note_hint'),
                counterText: '',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('dq_send'),
              onPressed: _sending ? null : _send,
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                foregroundColor: c.brandInk,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AvaRadius.card)),
              ),
              child: _sending
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(context.tr('dq_request_send'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Харидор: сўров ҳолати (`delivery_quotes/{quoteId}` оқими).
class DeliveryQuoteStatusScreen extends StatefulWidget {
  const DeliveryQuoteStatusScreen({
    super.key,
    required this.quoteId,
    required this.repository,
    this.fallbackTitle = '',
    @visibleForTesting this.now,
    @visibleForTesting this.openOrder,
  });

  final String quoteId;
  final BusinessOrdersRepository repository;
  final String fallbackTitle;
  final DateTime Function()? now;

  /// Тест учун: буюртма экрани ўрнига.
  final void Function(BuildContext context, String orderId)? openOrder;

  @override
  State<DeliveryQuoteStatusScreen> createState() => _DeliveryQuoteStatusScreenState();
}

class _DeliveryQuoteStatusScreenState extends State<DeliveryQuoteStatusScreen> {
  late Stream<DeliveryQuote?> _stream = widget.repository.watchDeliveryQuote(widget.quoteId);
  String _payment = 'cash';
  bool _accepting = false;

  void _refresh() => setState(() => _stream = widget.repository.watchDeliveryQuote(widget.quoteId));

  void _openOrder(String orderId) {
    final custom = widget.openOrder;
    if (custom != null) return custom(context, orderId);
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => BusinessOrderScreen(orderId: orderId, repository: widget.repository),
    ));
  }

  Future<void> _accept() async {
    if (_accepting) return;
    setState(() => _accepting = true);
    try {
      final res = await widget.repository.acceptDeliveryQuote(quoteId: widget.quoteId, deliveryPaymentMethod: _payment);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.tr('biz_order_placed_ok'))));
      _openOrder(res.orderId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(bizOrderErrorText(context, e)), backgroundColor: context.ava.danger),
      );
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(context.tr('dq_status_title')),
        actions: [
          IconButton(
            key: const ValueKey('dq_refresh'),
            tooltip: context.tr('restaurants_courier_refresh'),
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: StreamBuilder<DeliveryQuote?>(
        stream: _stream,
        builder: (context, snap) {
          final q = snap.hasError ? null : snap.data;
          final waitingNoData = q == null && (snap.hasError || snap.connectionState != ConnectionState.waiting);
          if (q == null && !waitingNoData) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.fromLTRB(AvaSpace.screen, 16, AvaSpace.screen, 24),
            children: [
              Text(
                q?.itemTitle.isNotEmpty == true ? q!.itemTitle : widget.fallbackTitle,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink),
              ),
              if (q != null && q.sellerName.isNotEmpty)
                Text(q.sellerName, style: TextStyle(fontSize: 13, color: c.ink2)),
              if (q != null)
                Text(context.tr('dq_qty_line').replaceAll('{n}', '${q.qty}'), style: TextStyle(fontSize: 13, color: c.ink2)),
              const SizedBox(height: 14),
              if (q == null) ..._waiting(context, manual: true) else ..._body(context, q),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _waiting(BuildContext context, {required bool manual, DateTime? expiresAt}) {
    final c = context.ava;
    return [
      BizOrderNotice(
        key: const ValueKey('dq_waiting'),
        icon: Icons.hourglass_top_rounded,
        text: context.tr('dq_status_waiting'),
        color: c.brandText,
        background: c.brandSoft,
      ),
      if (expiresAt != null) ...[
        const SizedBox(height: 6),
        Text(
          context.tr('dq_expires_at').replaceAll('{time}', bizOrderTimeLabel(expiresAt)),
          style: TextStyle(fontSize: 12, color: c.ink2),
        ),
      ],
      if (manual) ...[
        const SizedBox(height: 8),
        Text(context.tr('dq_status_refresh_hint'), style: TextStyle(fontSize: 12.5, color: c.ink2)),
        TextButton.icon(
          onPressed: _refresh,
          icon: const Icon(Icons.refresh, size: 18),
          label: Text(context.tr('restaurants_courier_refresh')),
        ),
      ],
    ];
  }

  List<Widget> _body(BuildContext context, DeliveryQuote q) {
    final c = context.ava;
    final status = q.effectiveStatus(widget.now?.call() ?? DateTime.now());
    switch (status) {
      case DeliveryQuoteStatus.answered:
        return [
          BizOrderMoneyLine(
            key: const ValueKey('dq_price'),
            label: context.tr('dq_status_title'),
            amount: q.priceUzs ?? 0,
            bold: true,
          ),
          if (q.expiresAt != null)
            Text(
              context.tr('dq_expires_at').replaceAll('{time}', bizOrderTimeLabel(q.expiresAt!)),
              style: TextStyle(fontSize: 12, color: c.ink2),
            ),
          const SizedBox(height: 10),
          Text(context.tr('biz_order_delivery_payment'),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
          Wrap(spacing: 8, children: [
            ChoiceChip(
              key: const ValueKey('dq_pay_cash'),
              label: Text(context.tr('biz_order_delivery_cash')),
              selected: _payment == 'cash',
              onSelected: (_) => setState(() => _payment = 'cash'),
            ),
            ChoiceChip(
              key: const ValueKey('dq_pay_wallet'),
              label: Text(context.tr('biz_order_delivery_wallet')),
              selected: _payment == 'wallet',
              onSelected: (_) => setState(() => _payment = 'wallet'),
            ),
          ]),
          const SizedBox(height: 6),
          BizOrderNotice(
            icon: Icons.payments_outlined,
            text: context.tr('biz_order_goods_cash_explain'),
            color: c.brandText,
            background: c.brandSoft,
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('dq_accept'),
            onPressed: _accepting ? null : _accept,
            style: FilledButton.styleFrom(
              backgroundColor: c.brand,
              foregroundColor: c.brandInk,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AvaRadius.card)),
            ),
            child: _accepting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.tr('dq_accept'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ];
      case DeliveryQuoteStatus.used:
        return [
          BizOrderNotice(
            key: const ValueKey('dq_used'),
            icon: Icons.check_circle_outline,
            text: context.tr('dq_status_used'),
            color: c.ok,
            background: c.okSoft,
          ),
          if (q.orderId.isNotEmpty) ...[
            const SizedBox(height: 10),
            FilledButton(
              key: const ValueKey('dq_open_order'),
              onPressed: () => _openOrder(q.orderId),
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                foregroundColor: c.brandInk,
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(context.tr('dq_open_order')),
            ),
          ],
        ];
      case DeliveryQuoteStatus.expired:
        return [
          BizOrderNotice(
            key: const ValueKey('dq_expired'),
            icon: Icons.timer_off_outlined,
            text: context.tr('dq_status_expired'),
            color: c.danger,
            background: c.dangerSoft,
          ),
        ];
      default:
        return _waiting(context, manual: false, expiresAt: q.expiresAt);
    }
  }
}
