// Улгуржи «Буюртма бериш» варағи (4-босқич, эга қарорлари 2026-10-31).
//
// Қадоқ ва миқдор — товар саҳифасидаги танловдан (бу ерда ўзгармайди).
// Етказиш манзили — сотувчи манзили формаси билан бир хил виджет
// ([ShipFromFields]: вилоят → туман → манзил, ихтиёрий GPS).
// Тўлов: AVA ҳамёндан олдиндан; 3b — етказилганда сотувчи картасига
// (фақат квота «мумкин» деса).
//
// НАРХ ФАҚАТ СЕРВЕРДАН (44-банд): ҳар ўзгаришда (debounce) `quoteWholesaleOrder`
// қайта сўралади, илова ҳеч нарсани ҳисобламайди. `clientRequestId` — ҳар
// квота учун БИР МАРТА; тармоқ хатосидан кейин қайта босилса ўша калит
// (сервер ўша буюртмани қайтаради, иккинчиси очилмайди — 21-банд).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/product_detail_dark.dart';
import '../../../core/utils/formatters.dart';
import '../../../repositories/service_config_repository.dart';
import '../../../shared/widgets/wallet_topup_ui.dart';
import '../models/wholesale_order.dart';
import '../models/wholesale_product.dart';
import '../models/wholesale_quote.dart';
import '../repositories/wholesale_orders_repository.dart';
import '../utils/wholesale_labels.dart';
import '../utils/wholesale_order_errors.dart';
import 'ship_from_fields.dart';

/// Ҳамён тўлдириш амали (тестда алмаштирилади). [amount] — етишмаётган сумма.
typedef WholesaleTopUp = void Function(NavigatorState navigator, int? amount);

/// Варақни очади. Буюртма берилса унинг ID'си қайтади ва [openOrder]
/// чақирилади (стандарт — ҳеч нарса; чақирувчи ўзи буюртма экранини очади).
Future<String?> showWholesaleCheckoutSheet(
  BuildContext context, {
  required WholesaleProduct product,
  required WholesalePack pack,
  required int qty,
  WholesaleOrdersRepository? repository,
  ServiceConfigRepository? geoRepository,
  Stream<int>? balance,
  ShipFromDraft? initialDestination,
  WholesaleTopUp? onTopUp,
  void Function(String orderId)? openOrder,
  Duration debounce = const Duration(milliseconds: 600),
}) async {
  final orderId = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: PdDark.surface,
    builder: (_) => WholesaleCheckoutSheet(
      product: product,
      pack: pack,
      qty: qty,
      repository: repository,
      geoRepository: geoRepository,
      balance: balance,
      initialDestination: initialDestination,
      onTopUp: onTopUp,
      debounce: debounce,
    ),
  );
  if (orderId != null && orderId.isNotEmpty) openOrder?.call(orderId);
  return orderId;
}

class WholesaleCheckoutSheet extends StatefulWidget {
  const WholesaleCheckoutSheet({
    super.key,
    required this.product,
    required this.pack,
    required this.qty,
    this.repository,
    this.geoRepository,
    this.balance,
    this.initialDestination,
    this.onTopUp,
    this.debounce = const Duration(milliseconds: 600),
  });

  final WholesaleProduct product;
  final WholesalePack pack;
  final int qty;
  final WholesaleOrdersRepository? repository;
  final ServiceConfigRepository? geoRepository;
  final Stream<int>? balance;
  final ShipFromDraft? initialDestination;
  final WholesaleTopUp? onTopUp;
  final Duration debounce;

  @override
  State<WholesaleCheckoutSheet> createState() => _WholesaleCheckoutSheetState();
}

class _WholesaleCheckoutSheetState extends State<WholesaleCheckoutSheet> {
  late final WholesaleOrdersRepository _repo = widget.repository ?? WholesaleOrdersRepository();

  /// Битта оқим — StreamBuilder қайта қурилганда қайта уланмасин.
  late final Stream<int> _balance = widget.balance ?? walletBalanceStream();

  late ShipFromDraft _dest = widget.initialDestination ?? shipFromDraftFromCurrentArea();
  String _method = WholesalePaymentMethod.wallet;

  WholesaleQuote? _quote;
  bool _quoting = false;
  String? _quoteError;

  /// Буюртма бериш шу фойдаланувчига ёпиқ (дарвоза) — тасдиқ тугмаси йўқ.
  bool _closed = false;

  /// Жорий квота учун идемпотентлик калити.
  String? _requestId;
  bool _placing = false;
  String? _placeError;

  /// Ҳамён етмаганда — «Ҳамённи тўлдириш» (етишмаётган сумма, бўлса).
  bool _placeTopUp = false;
  int? _shortfall;

  Timer? _timer;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _scheduleQuote(immediate: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleQuote({bool immediate = false}) {
    _timer?.cancel();
    if (_dest.validate() != null) {
      // Манзил тўлиқ эмас — эски нарх кўрсатилмасин (бошқа манзилники).
      _seq++;
      setStateIfMounted(() {
        _quote = null;
        _quoting = false;
        _quoteError = null;
      });
      return;
    }
    if (immediate) {
      _requote();
    } else {
      _timer = Timer(widget.debounce, _requote);
    }
  }

  void setStateIfMounted(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  Future<void> _requote() async {
    final seq = ++_seq;
    setStateIfMounted(() {
      _quoting = true;
      _quoteError = null;
      _placeError = null;
      _placeTopUp = false;
    });
    try {
      final q = await _repo.quote(
        productId: widget.product.id,
        packId: widget.pack.id,
        qty: widget.qty,
        destination: WholesaleDestination(
          regionId: _dest.regionId,
          districtId: _dest.districtId,
          addressText: _dest.address,
          lat: _dest.lat,
          lng: _dest.lng,
        ),
        paymentMethod: _method,
      );
      if (!mounted || seq != _seq) return;
      // Карта танланган, лекин сервер «мумкин эмас» деди — ҳамёнга қайтиб
      // нархни шу усул учун қайта сўраймиз.
      if (_method == WholesalePaymentMethod.cardOnDelivery && !q.cardOnDeliveryAvailable) {
        setState(() => _method = WholesalePaymentMethod.wallet);
        unawaited(_requote());
        return;
      }
      setState(() {
        _quote = q;
        _quoting = false;
        _requestId = _repo.newRequestId();
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _quote = null;
        _quoting = false;
        _closed = isWholesaleOrdersClosed(e);
        _quoteError = wholesaleOrderErrorText(context, e);
      });
    }
  }

  Future<void> _place() async {
    final q = _quote;
    final requestId = _requestId;
    if (q == null || requestId == null || _placing || _quoting) return;
    if (q.isExpired(DateTime.now())) {
      setState(() => _placeError = context.tr('wholesale_order_err_quote_expired'));
      await _requote();
      return;
    }
    setState(() {
      _placing = true;
      _placeError = null;
      _placeTopUp = false;
    });
    try {
      final r = await _repo.place(quoteId: q.quoteId, clientRequestId: requestId);
      if (!mounted) return;
      Navigator.of(context).pop(r.orderId);
      return;
    } on WholesaleOrderException catch (e) {
      if (!mounted) return;
      final text = wholesaleOrderErrorText(context, e);
      switch (e.reason) {
        case 'insufficient_balance':
          final need = e.detailInt('required');
          final have = e.detailInt('balance');
          setState(() {
            _placeError = text;
            _placeTopUp = true;
            _shortfall = need != null && have != null && need > have ? need - have : null;
          });
        case 'quote_expired' || 'quote_used' || 'quote_not_found' || 'quote_invalid':
          // Янги квота — янги калит (эски калит эски квотага боғланган).
          await _requote();
          if (mounted) setState(() => _placeError = text);
        case 'insufficient_stock' || 'stock_unknown' || 'product_unavailable':
          setState(() {
            _placeError = text;
            _quote = null;
          });
        default:
          if (isWholesaleOrdersClosed(e)) _closed = true;
          // Тармоқ/сервер хатоси: калит САҚЛАНАДИ — қайта босилса ўша
          // буюртма (агар биринчиси аслида ўтган бўлса) қайтади.
          setState(() => _placeError = text);
      }
    } catch (e) {
      if (mounted) setState(() => _placeError = wholesaleOrderErrorText(context, e));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  void _topUp([int? amount]) {
    final nav = Navigator.of(context);
    final fn = widget.onTopUp;
    if (fn != null) {
      fn(nav, amount);
    } else {
      openWalletTopUp(nav, suggestedAmount: amount);
    }
  }

  void _setMethod(String m) {
    if (m == _method) return;
    setState(() => _method = m);
    _scheduleQuote(immediate: true);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final unit = wholesaleUnitLabel(context, p.unit);
    final maxH = MediaQuery.sizeOf(context).height * 0.9;
    return ProductDetailDark(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.tr('wholesale_checkout_title'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: PdDark.ink),
                ),
                const SizedBox(height: 10),
                _ItemCard(
                  title: p.title,
                  packLabel: p.hasPacks ? widget.pack.label : '',
                  qtyText: context.trMsg('wholesale_checkout_qty',
                      params: {'qty': '${widget.qty}', 'unit': unit}),
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr('wholesale_checkout_change_hint'),
                  style: const TextStyle(fontSize: 11, color: PdDark.muted),
                ),
                const SizedBox(height: 14),
                ShipFromFields(
                  value: _dest,
                  geoRepository: widget.geoRepository,
                  titleKey: 'wholesale_checkout_address_title',
                  helpKey: 'wholesale_checkout_address_help',
                  addressLabelKey: 'wholesale_checkout_address_label',
                  onChanged: (v) {
                    setState(() => _dest = v);
                    _scheduleQuote();
                  },
                ),
                const SizedBox(height: 14),
                _paymentSection(context),
                const SizedBox(height: 12),
                _quoteSection(context),
                const SizedBox(height: 10),
                if (_placeError != null)
                  WalletInlineError(
                    text: _placeError!,
                    onTopUp: _placeTopUp ? () => _topUp(_shortfall) : null,
                  ),
                if (_quote != null && _method == WholesalePaymentMethod.wallet)
                  WalletBalanceNotice(
                    balance: _balance,
                    price: _quote!.total,
                    onTopUp: () => _topUp(),
                    onTopUpAmount: _topUp,
                  ),
                Text(
                  context.tr('wholesale_checkout_courier_note'),
                  style: const TextStyle(fontSize: 11, height: 1.3, color: PdDark.muted),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    key: const ValueKey('wholesale-checkout-confirm'),
                    onPressed: (_quote == null || _quoting || _placing || _closed) ? null : _place,
                    style: FilledButton.styleFrom(
                      backgroundColor: PdDark.brand,
                      foregroundColor: PdDark.brandInk,
                      disabledBackgroundColor: PdDark.surface2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _placing
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(
                            context.tr('wholesale_checkout_confirm'),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _paymentSection(BuildContext context) {
    final q = _quote;
    final cardKnown = q?.paymentMethodsKnown ?? false;
    final cardOk = q?.cardOnDeliveryAvailable ?? false;
    final reason = q?.cardUnavailableReason ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('wholesale_checkout_payment_title'),
          style: const TextStyle(fontWeight: FontWeight.w600, color: PdDark.ink),
        ),
        RadioGroup<String>(
          groupValue: _method,
          onChanged: (v) {
            if (v != null && !_placing) _setMethod(v);
          },
          child: Column(
            children: [
              RadioListTile<String>(
                key: const ValueKey('wholesale-pay-wallet'),
                value: WholesalePaymentMethod.wallet,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(context.tr('wholesale_pay_wallet'),
                    style: const TextStyle(fontSize: 13, color: PdDark.ink)),
              ),
              // Карта — ФАҚАТ сервер «мумкин» деса (3b). Мумкин бўлмаса —
              // вариант кўрсатилмайди, сабаби (бўлса) матн билан.
              if (cardKnown && cardOk)
                RadioListTile<String>(
                  key: const ValueKey('wholesale-pay-card'),
                  value: WholesalePaymentMethod.cardOnDelivery,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(context.tr('wholesale_pay_card'),
                      style: const TextStyle(fontSize: 13, color: PdDark.ink)),
                ),
            ],
          ),
        ),
        if (cardKnown && !cardOk && reason.isNotEmpty)
          Text(
            context.tr(wholesaleCardUnavailableKey(reason)),
            key: const ValueKey('wholesale-card-unavailable'),
            style: const TextStyle(fontSize: 11, color: PdDark.muted),
          ),
      ],
    );
  }

  Widget _quoteSection(BuildContext context) {
    if (_quoting) {
      return Row(
        children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text(context.tr('wholesale_quote_loading'),
              style: const TextStyle(fontSize: 13, color: PdDark.muted)),
        ],
      );
    }
    if (_quoteError != null) {
      return Container(
        key: const ValueKey('wholesale-quote-error'),
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(color: PdDark.surface2, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18, color: Color(0xFFF0A868)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_quoteError!, style: const TextStyle(fontSize: 12, color: PdDark.ink)),
            ),
            if (!_closed)
              TextButton(
                onPressed: () => _scheduleQuote(immediate: true),
                child: Text(context.tr('wholesale_quote_retry')),
              ),
          ],
        ),
      );
    }
    final q = _quote;
    if (q == null) {
      return Text(
        context.tr('wholesale_quote_fill_address'),
        style: const TextStyle(fontSize: 12, color: PdDark.muted),
      );
    }
    String money(int v) => formatMoney(v);
    return Container(
      key: const ValueKey('wholesale-quote'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: PdDark.surface2, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          _MoneyLine(label: context.tr('wholesale_quote_goods'), value: money(q.goodsTotal)),
          _MoneyLine(label: context.tr('wholesale_quote_delivery'), value: money(q.deliveryFee)),
          const Divider(height: 10, color: PdDark.line),
          _MoneyLine(label: context.tr('wholesale_quote_total'), value: money(q.total), bold: true),
          if (_method == WholesalePaymentMethod.cardOnDelivery) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.trMsg('wholesale_quote_due_on_delivery', params: {'amount': money(q.total)}),
                key: const ValueKey('wholesale-due-on-delivery'),
                style: const TextStyle(fontSize: 12, color: PdDark.brand, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.title, required this.packLabel, required this.qtyText});

  final String title;
  final String packLabel;
  final String qtyText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: PdDark.surface2, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: PdDark.ink)),
          const SizedBox(height: 2),
          Text(
            [if (packLabel.isNotEmpty) packLabel, qtyText].join(' · '),
            style: const TextStyle(fontSize: 12, color: PdDark.muted),
          ),
        ],
      ),
    );
  }
}

class _MoneyLine extends StatelessWidget {
  const _MoneyLine({required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: PdDark.muted))),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 16 : 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: PdDark.ink,
            ),
          ),
        ],
      ),
    );
  }
}
