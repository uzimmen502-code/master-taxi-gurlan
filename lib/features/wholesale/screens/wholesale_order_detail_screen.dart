// Улгуржи буюртма тафсилоти — харидор ҳам, сотувчи ҳам шу экранни кўради;
// кимга қайси амал кўринишини [WholesaleOrderActions] белгилайди.
//
// Эга қарори (2026-11-13; 31.10 дагисининг ўрнига): янги буюртмани сотувчи 2 иш
// кунида «Қабул қилиш» ёки «Рад этиш» қилади, курьер фақат қабулдан кейин.
// Карта буюртмасида «Пул тушди» ҳам бор. Банк ўтказмасида (эга, 2026-11-13/14)
// қабулдан кейин сотувчи 5 иш кунида «Пул тушди»ни босади, курьер шундан кейин;
// товар пули иловадан ташқарида — унинг қайтиши ҳақида матн йўқ (эга, 2026-11-14).
// Ҳолатни фақат сервер ўзгартиради.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/wallet_topup_ui.dart';
import '../../logistics/ui/logistics_text.dart' show logisticsDateLabel;
import '../models/wholesale_order.dart';
import '../models/wholesale_quote.dart';
import '../repositories/wholesale_orders_repository.dart';
import '../services/wholesale_storage_service.dart';
import '../utils/wholesale_order_errors.dart';
import '../widgets/wholesale_order_status.dart';

/// Чек расмини танлаб юклайди, Storage йўлини қайтаради (бекор — `null`).
typedef WholesaleReceiptUploader = Future<String?> Function(String buyerId, String orderId);

class WholesaleOrderDetailScreen extends StatelessWidget {
  const WholesaleOrderDetailScreen({
    super.key,
    required this.orderId,
    required this.viewerId,
    this.repository,
  });

  final String orderId;

  /// Жорий фойдаланувчи телефони (канон шакл) — харидор/сотувчи шундан.
  final String viewerId;
  final WholesaleOrdersRepository? repository;

  @override
  Widget build(BuildContext context) {
    final repo = repository ?? WholesaleOrdersRepository();
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface,
        elevation: 0,
        title: Text(
          context.tr('wholesale_order_title'),
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink),
        ),
      ),
      body: StreamBuilder<WholesaleOrder?>(
        stream: repo.watchOrder(orderId),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text(wholesaleOrderErrorText(context, snap.error!)));
          }
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final order = snap.data;
          if (order == null) {
            return Center(child: Text(context.tr('wholesale_order_err_order_not_found')));
          }
          return WholesaleOrderDetailView(order: order, viewerId: viewerId, repository: repo);
        },
      ),
    );
  }
}

/// Оқимсиз кўриниш (тест учун алоҳида).
class WholesaleOrderDetailView extends StatefulWidget {
  const WholesaleOrderDetailView({
    super.key,
    required this.order,
    required this.viewerId,
    required this.repository,
    this.uploadReceipt,
    this.now,
  });

  final WholesaleOrder order;
  final String viewerId;
  final WholesaleOrdersRepository repository;
  final WholesaleReceiptUploader? uploadReceipt;

  /// Тест учун соат («етказилмади» муддати).
  final DateTime Function()? now;

  @override
  State<WholesaleOrderDetailView> createState() => _WholesaleOrderDetailViewState();
}

class _WholesaleOrderDetailViewState extends State<WholesaleOrderDetailView> {
  bool _busy = false;
  String? _error;

  WholesaleOrder get _o => widget.order;

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body();
    } catch (e) {
      if (mounted) setState(() => _error = wholesaleOrderErrorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(key))));
  }

  Future<bool> _confirm(String body, {String? title}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: title == null ? null : Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(ctx.tr('consent_no'))),
          FilledButton(
            key: const ValueKey('wholesale-confirm-yes'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('logistics_confirm')),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _cancel() async {
    // Банк ўтказмаси: товар пули иловада йўқ — фақат ушланган етказиш ҳақи қайтиши айтилади.
    final body = [
      context.tr('wholesale_order_cancel_confirm'),
      if (_o.isBankOrder)
        context.tr('wholesale_order_cancel_refund_note_bank')
      else if (!_o.isCardOrder)
        context.tr('wholesale_order_cancel_refund_note'),
    ].join('\n');
    if (!await _confirm(body)) return;
    await _run(() async {
      await widget.repository.cancel(_o.id);
      _snack('wholesale_order_status_cancelled');
    });
  }

  /// Сўров `_run` ичида (спиннер), ойна эса ундан ТАШҚАРИДА: акс ҳолда ойна
  /// очиқ турганда тугма «банд» бўлиб қолади.
  Future<void> _showCode() async {
    WholesaleDeliveryCode? code;
    await _run(() async => code = await widget.repository.deliveryCode(_o.id));
    final c = code;
    if (c == null || !mounted) return;
    await showDialog<void>(context: context, builder: (_) => _DeliveryCodeDialog(code: c));
  }

  Future<void> _showCardInfo() async {
    WholesaleCardInfo? info;
    await _run(() async => info = await widget.repository.cardPaymentInfo(_o.id));
    final i = info;
    if (i == null || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _CardInfoSheet(info: i),
    );
  }

  Future<void> _uploadReceipt() => _run(() async {
        final upload = widget.uploadReceipt ?? _defaultUpload;
        final path = await upload(canonicalPhoneId(widget.viewerId), _o.id);
        if (path == null || path.isEmpty) return;
        await widget.repository.submitCardReceipt(orderId: _o.id, receiptPath: path);
        _snack('wholesale_order_receipt_sent');
      });

  /// Фақат РАСМ (Storage қоидаси PDF'ни қабул қилмайди), сиқилган JPEG < 8 МБ.
  static Future<String?> _defaultUpload(String buyerId, String orderId) async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 2000);
    if (file == null) return null;
    return WholesaleStorageService().uploadReceipt(buyerId: buyerId, orderId: orderId, image: file);
  }

  Future<void> _confirmMoney() async {
    final ok = await _confirm(
      context.trMsg('wholesale_order_money_received_confirm', params: {'amount': formatMoney(_o.total)}),
      title: context.tr('wholesale_order_money_received_btn'),
    );
    if (!ok) return;
    await _run(() async {
      await widget.repository.confirmCardPayment(_o.id);
      _snack('wholesale_order_card_confirmed');
    });
  }

  /// Банк ўтказмаси: «Пул тушди» (товар суммаси сотувчи банк ҳисобига тушди) → курьер.
  Future<void> _confirmBankMoney() async {
    final ok = await _confirm(
      context.trMsg('wholesale_order_bank_confirm_dialog', params: {'amount': formatMoney(_o.goodsTotal)}),
      title: context.tr('wholesale_order_money_received_btn'),
    );
    if (!ok) return;
    await _run(() async {
      await widget.repository.confirmBankPayment(_o.id);
      _snack('wholesale_order_bank_confirmed');
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final o = _o;
    final a = WholesaleOrderActions.of(o, widget.viewerId, now: (widget.now ?? DateTime.now)());
    final unitPrice = formatMoney(o.unitPrice);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _card(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      o.productTitle,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: WholesaleOrderStatusChip(status: o.status, awaitingSeller: o.awaitingSellerDecision),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [if (o.packLabel.isNotEmpty) o.packLabel, '${o.qty} × $unitPrice'].join(' · '),
                style: TextStyle(fontSize: 12, color: c.ink2),
              ),
              if (o.createdAt != null)
                Text(logisticsDateLabel(o.createdAt), style: TextStyle(fontSize: 11, color: c.ink3)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _card(context, WholesaleOrderTimeline(status: o.status, awaitingSeller: o.awaitingSellerDecision)),
        if (a.canDecide || a.awaitingDecision) ...[
          const SizedBox(height: 10),
          _decisionCard(context, a),
        ],
        if (a.canConfirmBankPayment || a.awaitingBankPayment || a.bankPaymentLate) ...[
          const SizedBox(height: 10),
          _bankCard(context, a),
        ],
        if (o.bankConfirmed && o.status == WholesaleOrderStatus.placed && (a.isBuyer || a.isSeller)) ...[
          const SizedBox(height: 10),
          _notice(context, 'wholesale_order_bank_confirmed', ok: true, key: const ValueKey('wholesale-bank-confirmed')),
        ],
        if (_cancelReasonKey(o) != null) ...[
          const SizedBox(height: 10),
          _notice(context, _cancelReasonKey(o)!, warn: true, key: const ValueKey('wholesale-cancel-reason')),
        ],
        if (a.answerDeliveryFailed || a.decideDeliveryFailed) ...[
          const SizedBox(height: 10),
          _deliveryFailedCard(context, a),
          if (_error != null) ...[const SizedBox(height: 8), WalletInlineError(text: _error!)],
        ],
        if (o.status == WholesaleOrderStatus.paymentDispute) ...[
          const SizedBox(height: 10),
          _notice(context, 'wholesale_order_status_payment_dispute', warn: true,
              key: const ValueKey('wholesale-dispute-banner')),
        ],
        if (o.lostNoticeKey(widget.viewerId) != null) ...[
          const SizedBox(height: 10),
          Container(
            key: const ValueKey('wholesale-lost-notice'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(10)),
            child: Text(
              context.trMsg(o.lostNoticeKey(widget.viewerId)!, params: {'amount': formatMoney(o.lostRefunded)}),
              style: TextStyle(fontSize: 12, color: c.warn, fontWeight: FontWeight.w600),
            ),
          ),
        ],
        if (o.walletRefundNoticeKey(widget.viewerId) != null) ...[
          const SizedBox(height: 10),
          Container(
            key: const ValueKey('wholesale-wallet-refund-notice'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.okSoft, borderRadius: BorderRadius.circular(10)),
            child: Text(
              context.trMsg(o.walletRefundNoticeKey(widget.viewerId)!, params: {
                'refund': formatMoney(o.walletRefundGoods),
                'fee': formatMoney(o.walletReturnFeeCharged),
              }),
              style: TextStyle(fontSize: 12, color: c.ok, fontWeight: FontWeight.w600),
            ),
          ),
        ],
        if (_showsReturn(o)) ...[
          const SizedBox(height: 10),
          _returnCard(context, o),
        ],
        const SizedBox(height: 10),
        _card(
          context,
          Column(
            children: [
              _line(context, context.tr('wholesale_quote_goods'), formatMoney(o.goodsTotal)),
              _line(context, context.tr('wholesale_quote_delivery'), formatMoney(o.deliveryFee)),
              Divider(height: 10, color: c.line),
              _line(context, context.tr('wholesale_quote_total'), formatMoney(o.total), bold: true),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.tr(o.isBankOrder
                      ? 'wholesale_order_payment_bank'
                      : (o.isCardOrder ? 'wholesale_order_payment_card' : 'wholesale_order_payment_wallet')),
                  style: TextStyle(fontSize: 12, color: c.ink2),
                ),
              ),
              if (o.trackingNumber.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    context.trMsg('wholesale_order_tracking', params: {'number': o.trackingNumber}),
                    style: TextStyle(fontSize: 12, color: c.ink2),
                  ),
                ),
              if (o.destinationText.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.trMsg('wholesale_order_address', params: {'address': o.destinationText}),
                    style: TextStyle(fontSize: 12, color: c.ink2),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // «Етказилмади» ёки қарор картаси кўринса, хато шу карта остида (юқорида) — такрорланмасин.
        if (_error != null &&
            !a.answerDeliveryFailed &&
            !a.decideDeliveryFailed &&
            !a.canDecide &&
            !a.canConfirmBankPayment)
          WalletInlineError(text: _error!),
        ..._buyerActions(context, a),
        ..._sellerActions(context, a),
        const SizedBox(height: 24),
      ],
    );
  }

  List<Widget> _buyerActions(BuildContext context, WholesaleOrderActions a) {
    if (!a.isBuyer) return const [];
    final c = context.ava;
    return [
      if (a.showBuyerReturnDebt) ...[
        Container(
          key: const ValueKey('wholesale-buyer-return-debt'),
          child: WalletInlineError(
            text: context.trMsg('wholesale_order_return_debt_buyer', params: {'amount': formatMoney(_o.returnDebt)}),
            onTopUp: () => openWalletTopUp(Navigator.of(context), suggestedAmount: _o.returnDebt),
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (a.showDeliveryCode) ...[
        _primary(context, 'wholesale_order_delivery_code_btn', Icons.pin_outlined, _showCode,
            key: const ValueKey('wholesale-delivery-code')),
        const SizedBox(height: 4),
        Text(context.tr('wholesale_order_delivery_code_hint'), style: TextStyle(fontSize: 12, color: c.ink2)),
        const SizedBox(height: 10),
      ],
      if (a.codeAfterCardConfirm) ...[
        _notice(context, 'wholesale_order_err_card_payment_unconfirmed'),
        const SizedBox(height: 10),
      ],
      if (a.showCardInfo) ...[
        _secondary(context, 'wholesale_order_card_info_btn', Icons.credit_card, _showCardInfo,
            key: const ValueKey('wholesale-card-info')),
        const SizedBox(height: 8),
      ],
      if (a.canUploadReceipt) ...[
        _secondary(context, 'wholesale_order_receipt_upload', Icons.receipt_long_outlined, _uploadReceipt,
            key: const ValueKey('wholesale-receipt-upload')),
        const SizedBox(height: 8),
      ],
      if (a.waitingSeller) ...[
        _notice(context, 'wholesale_order_wait_seller', key: const ValueKey('wholesale-wait-seller')),
        const SizedBox(height: 8),
      ],
      if (_o.isCardOrder && _o.cardConfirmed) ...[
        _notice(context, 'wholesale_order_card_confirmed', ok: true),
        const SizedBox(height: 8),
      ],
      if (a.canCancel) ...[
        const SizedBox(height: 6),
        OutlinedButton(
          key: const ValueKey('wholesale-order-cancel'),
          onPressed: _busy ? null : _cancel,
          style: OutlinedButton.styleFrom(
            foregroundColor: c.danger,
            side: BorderSide(color: c.line),
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(context.tr('wholesale_order_cancel_btn')),
        ),
      ],
    ];
  }

  List<Widget> _sellerActions(BuildContext context, WholesaleOrderActions a) {
    if (!a.isSeller) return const [];
    final o = _o;
    return [
      if (a.showReturnDebt) ...[
        Container(
          key: const ValueKey('wholesale-return-debt'),
          child: WalletInlineError(
            text: context.trMsg('wholesale_order_return_debt', params: {'amount': formatMoney(o.returnDebt)}),
            onTopUp: () => openWalletTopUp(Navigator.of(context), suggestedAmount: o.returnDebt),
          ),
        ),
      ],
      if (a.canConfirmCardPayment &&
          o.cardPaymentStatus != WholesaleCardPaymentStatus.receiptSubmitted) ...[
        _notice(context, 'wholesale_order_card_awaiting_seller'),
        const SizedBox(height: 8),
      ],
      if (a.canConfirmCardPayment &&
          o.cardPaymentStatus == WholesaleCardPaymentStatus.receiptSubmitted) ...[
        _notice(context, 'wholesale_order_receipt_window', warn: true),
        const SizedBox(height: 8),
      ],
      if (a.showReceipt) ...[
        _ReceiptImage(url: o.receiptUrl),
        const SizedBox(height: 8),
      ],
      if (a.canConfirmCardPayment)
        _primary(context, 'wholesale_order_money_received_btn', Icons.payments_outlined, _confirmMoney,
            key: const ValueKey('wholesale-money-received')),
      if (o.isCardOrder && o.cardConfirmed) _notice(context, 'wholesale_order_card_confirmed', ok: true),
    ];
  }

  // ── Сотувчи қарори (эга, 2026-11-13): 2 иш кунида қабул ёки рад ─────

  static String? _cancelReasonKey(WholesaleOrder o) {
    if (o.status != WholesaleOrderStatus.cancelled) return null;
    // Банк ўтказмаси: фақат етказиш ҳақи қайтиши айтилади (товар пули иловада бўлмаган).
    final bank = o.isBankOrder ? '_bank' : '';
    return switch (o.cancelReason) {
      'seller_rejected' => 'wholesale_order_cancel_seller_rejected$bank',
      'seller_timeout' => 'wholesale_order_cancel_seller_timeout$bank',
      'bank_payment_timeout' => 'wholesale_order_cancel_bank_payment_timeout',
      _ => null,
    };
  }

  /// Банк ўтказмаси картаси: сотувчига — «Пул тушди» (муддат билан), харидорга — банк
  /// орқали тўлаш изоҳи, муддат ўтган бўлса — бекор бўлиши ҳақида.
  Widget _bankCard(BuildContext context, WholesaleOrderActions a) {
    final c = context.ava;
    final until = _o.bankPayDeadlineAt;
    final dateText = until == null ? '' : _ddmmHHmm(until);
    final String key;
    if (a.bankPaymentLate) {
      key = 'wholesale_order_bank_late';
    } else if (a.canConfirmBankPayment) {
      key = 'wholesale_order_bank_seller_await';
    } else {
      key = 'wholesale_order_bank_buyer_await';
    }
    return Container(
      key: const ValueKey('wholesale-bank-card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr(key).replaceAll('{date}', dateText),
            key: const ValueKey('wholesale-bank-text'),
            style: TextStyle(fontSize: 13, color: c.warn, fontWeight: FontWeight.w600),
          ),
          if (a.canConfirmBankPayment) ...[
            const SizedBox(height: 10),
            _primary(context, 'wholesale_order_money_received_btn', Icons.account_balance_outlined, _confirmBankMoney,
                key: const ValueKey('wholesale-bank-money-received')),
            if (_error != null) ...[const SizedBox(height: 8), WalletInlineError(text: _error!)],
          ],
        ],
      ),
    );
  }

  static String _ddmmHHmm(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
  }

  Future<void> _accept() async {
    // Банк ўтказмасида курьер қабулдан кейин эмас, «Пул тушди»дан кейин.
    final bank = _o.isBankOrder ? '_bank' : '';
    if (!await _confirm(context.tr('wholesale_order_accept_confirm$bank'),
        title: context.tr('wholesale_order_accept_btn'))) {
      return;
    }
    await _run(() async {
      await widget.repository.acceptOrder(_o.id);
      _snack('wholesale_order_accepted_snack$bank');
    });
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectReasonDialog(),
    );
    if (reason == null || !mounted) return;
    await _run(() async {
      await widget.repository.rejectOrder(orderId: _o.id, reason: reason);
      _snack('wholesale_order_rejected_snack');
    });
  }

  Widget _decisionCard(BuildContext context, WholesaleOrderActions a) {
    final c = context.ava;
    final until = _o.acceptDeadlineAt;
    final dateText = until == null ? '' : _ddmmHHmm(until);
    final text = a.canDecide
        ? context.tr('wholesale_order_decide_until').replaceAll('{date}', dateText)
        : context
            .tr(_o.isBankOrder ? 'wholesale_order_decision_wait_bank' : 'wholesale_order_decision_wait')
            .replaceAll('{date}', dateText);
    return Container(
      key: const ValueKey('wholesale-decision-card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.warnSoft, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(text, style: TextStyle(fontSize: 13, color: c.warn, fontWeight: FontWeight.w600)),
          if (a.canDecide) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('wholesale-order-reject'),
                    onPressed: _busy ? null : _reject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.danger,
                      side: BorderSide(color: c.line),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(context.tr('wholesale_order_reject_btn')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('wholesale-order-accept'),
                    onPressed: _busy ? null : _accept,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(context.tr('wholesale_order_accept_btn')),
                  ),
                ),
              ],
            ),
          ],
          if (_error != null && a.canDecide) ...[const SizedBox(height: 8), WalletInlineError(text: _error!)],
        ],
      ),
    );
  }

  // ── «Етказилмади» (эга, 2026-11-01) ───────────────────────────────

  static String _hhmm(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  /// Тасдиқ ойнаси матни: карта — аввалгидек; ҳамён (эга, 2026-11-01) — пул оқибати сабабга қараб
  /// (харидор сабаби — қайтариш ҳақи қайтадиган суммадан; курьер сабаби — ҳақни курьер тўлайди).
  String get _buyerConfirmDialogKey {
    if (_o.isCardOrder) return 'wholesale_df_buyer_confirm_dialog';
    // Банк ўтказмаси — ҳамён айб қоидаси, лекин товар пули ҳақида гап йўқ (эга, 2026-11-14).
    final m = _o.isBankOrder ? 'bank' : 'wallet';
    return _o.deliveryFailed.reasonCode == 'courier_problem'
        ? 'wholesale_df_buyer_confirm_dialog_${m}_courier'
        : 'wholesale_df_buyer_confirm_dialog_${m}_buyer';
  }

  /// «Етказилмади» матнлари калити: карта / ҳамён / банк (банкда товар пули қайтиши айтилмайди).
  String _dfKey(String card, String wallet, String bank) =>
      _o.isCardOrder ? card : (_o.isBankOrder ? bank : wallet);

  /// Харидор: «Тасдиқлайман» (буюртма ёпилади — тасдиқ ойнаси) ёки «Олмоқчиман».
  Future<void> _answerFailed({required bool confirm}) async {
    if (confirm && !await _confirm(context.tr(_buyerConfirmDialogKey))) return;
    await _run(() async {
      await widget.repository.respondDeliveryFailed(orderId: _o.id, confirm: confirm);
      _snack(confirm ? 'wholesale_df_done_failed' : 'customer_confirm_rejected_done');
    });
  }

  /// Сотувчи (муддат ўтгач): «Етказилмади» (тасдиқ ойнаси) ёки «Етказилсин».
  Future<void> _decideFailed({required bool failed}) async {
    if (failed &&
        !await _confirm(
            context.tr(_dfKey('wholesale_df_seller_failed_dialog', 'wholesale_df_seller_failed_dialog_wallet',
                'wholesale_df_seller_failed_dialog_bank')),
            title: context.tr('delivery_failed_decide_failed_title'))) {
      return;
    }
    await _run(() async {
      await widget.repository.resolveDeliveryFailed(orderId: _o.id, failed: failed);
      _snack(failed ? 'wholesale_df_done_failed' : 'wholesale_df_decided_deliver');
    });
  }

  Widget _deliveryFailedCard(BuildContext context, WholesaleOrderActions a) {
    final c = context.ava;
    final df = _o.deliveryFailed;
    final now = (widget.now ?? DateTime.now)();
    final until = df.escalateAt;
    final late = df.canDecide(now);
    final String waitText;
    if (a.answerDeliveryFailed) {
      waitText = late || until == null
          ? context.tr('wholesale_df_buyer_late')
          : context.tr('wholesale_df_buyer_until').replaceAll('{time}', _hhmm(until));
    } else {
      waitText = late || until == null
          ? context.tr('wholesale_df_seller_decide')
          : context.tr('wholesale_df_seller_wait').replaceAll('{time}', _hhmm(until));
    }
    final List<Widget> buttons;
    if (a.answerDeliveryFailed) {
      buttons = [
        Expanded(
          child: OutlinedButton(
            key: const ValueKey('wholesale-df-want-it'),
            onPressed: _busy ? null : () => _answerFailed(confirm: false),
            child: Text(context.tr('customer_confirm_btn_want_it'), textAlign: TextAlign.center),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            key: const ValueKey('wholesale-df-confirm'),
            onPressed: _busy ? null : () => _answerFailed(confirm: true),
            style: FilledButton.styleFrom(backgroundColor: c.danger),
            child: Text(context.tr('customer_confirm_btn_confirm'), textAlign: TextAlign.center),
          ),
        ),
      ];
    } else {
      final enabled = !_busy && late;
      buttons = [
        Expanded(
          child: OutlinedButton(
            key: const ValueKey('wholesale-df-deliver'),
            onPressed: enabled ? () => _decideFailed(failed: false) : null,
            child: Text(context.tr('wholesale_df_btn_deliver'), textAlign: TextAlign.center),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            key: const ValueKey('wholesale-df-failed'),
            onPressed: enabled ? () => _decideFailed(failed: true) : null,
            style: FilledButton.styleFrom(backgroundColor: c.danger),
            child: Text(context.tr('delivery_failed_btn_failed'), textAlign: TextAlign.center),
          ),
        ),
      ];
    }
    return Container(
      key: const ValueKey('wholesale-delivery-failed-card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.warn, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.report_problem_outlined, size: 18, color: c.warn),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context.tr(a.answerDeliveryFailed ? 'wholesale_df_buyer_title' : 'wholesale_df_seller_title'),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink),
                ),
              ),
            ],
          ),
          if (a.answerDeliveryFailed) ...[
            const SizedBox(height: 4),
            Text(context.tr(_dfKey('wholesale_df_buyer_body', 'wholesale_df_buyer_body_wallet', 'wholesale_df_buyer_body_bank')),
                key: const ValueKey('wholesale-df-buyer-body'), style: TextStyle(fontSize: 12.5, color: c.ink)),
          ],
          const SizedBox(height: 4),
          Text(
            '${context.tr('customer_confirm_fail_reason')}: ${context.tr(wholesaleDeliveryFailedReasonKey(df.reasonCode))}',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.ink),
          ),
          const SizedBox(height: 2),
          Text(waitText, key: const ValueKey('wholesale-df-wait'), style: TextStyle(fontSize: 12, color: c.warn)),
          const SizedBox(height: 8),
          Row(children: buttons),
        ],
      ),
    );
  }

  /// Қайтиш жараёни (3b) — харидорга ҳам, сотувчига ҳам кўринади.
  static bool _showsReturn(WholesaleOrder o) =>
      o.returnStatus.isNotEmpty ||
      o.status == WholesaleOrderStatus.refused ||
      o.status == WholesaleOrderStatus.returning ||
      o.status == WholesaleOrderStatus.returned;

  Widget _returnCard(BuildContext context, WholesaleOrder o) {
    final c = context.ava;
    final key = o.returnStatusKey() ??
        (o.status == WholesaleOrderStatus.returned
            ? 'wholesale_return_status_returned'
            : 'wholesale_return_status_pending_shipment');
    return _card(
      context,
      Column(
        key: const ValueKey('wholesale-return-progress'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assignment_return_outlined, size: 18, color: c.brand),
              const SizedBox(width: 6),
              Text(context.tr('wholesale_return_title'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
            ],
          ),
          const SizedBox(height: 4),
          Text(context.tr(key), style: TextStyle(fontSize: 12, color: c.ink2)),
          if (o.returnTrackingNumber.isNotEmpty)
            SelectableText(
              context.trMsg('wholesale_order_tracking', params: {'number': o.returnTrackingNumber}),
              style: TextStyle(fontSize: 11, color: c.ink3),
            ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Widget child) {
    final c = context.ava;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: child,
    );
  }

  Widget _line(BuildContext context, String label, String value, {bool bold = false}) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: c.ink2))),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 15 : 13,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              color: bold ? c.brand : c.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice(BuildContext context, String textKey, {bool warn = false, bool ok = false, Key? key}) {
    final c = context.ava;
    final (bg, fg) = ok ? (c.okSoft, c.ok) : (warn ? (c.warnSoft, c.warn) : (c.chip, c.ink2));
    return Container(
      key: key,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(context.tr(textKey), style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w600)),
    );
  }

  Widget _primary(BuildContext context, String textKey, IconData icon, VoidCallback onTap, {Key? key}) {
    final c = context.ava;
    return FilledButton.icon(
      key: key,
      onPressed: _busy ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: c.brand,
        foregroundColor: c.brandInk,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: _busy
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon, size: 18),
      label: Text(context.tr(textKey), style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _secondary(BuildContext context, String textKey, IconData icon, VoidCallback onTap, {Key? key}) {
    final c = context.ava;
    return OutlinedButton.icon(
      key: key,
      onPressed: _busy ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: c.brand,
        side: BorderSide(color: c.line),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(context.tr(textKey)),
    );
  }
}

class _DeliveryCodeDialog extends StatelessWidget {
  const _DeliveryCodeDialog({required this.code});

  final WholesaleDeliveryCode code;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return AlertDialog(
      title: Text(context.tr('wholesale_order_delivery_code_btn')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(
            code.deliveryCode,
            key: const ValueKey('wholesale-delivery-code-value'),
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 6, color: c.ink),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('wholesale_order_delivery_code_hint'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: c.ink2),
          ),
          if (code.trackingNumber.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              context.trMsg('wholesale_order_tracking', params: {'number': code.trackingNumber}),
              style: TextStyle(fontSize: 11, color: c.ink3),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('close'))),
      ],
    );
  }
}

class _CardInfoSheet extends StatelessWidget {
  const _CardInfoSheet({required this.info});

  final WholesaleCardInfo info;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('wholesale_order_card_info_title'),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    info.cardNumberGrouped,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1, color: c.ink),
                  ),
                ),
                IconButton(
                  tooltip: context.tr('wholesale_order_copy'),
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final copied = context.tr('wholesale_order_copied');
                    await Clipboard.setData(ClipboardData(text: info.cardNumber.replaceAll(RegExp(r'\D'), '')));
                    messenger.showSnackBar(SnackBar(content: Text(copied)));
                  },
                ),
              ],
            ),
            Text(context.trMsg('wholesale_order_card_amount', params: {'amount': formatMoney(info.amount)}),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.brand)),
            if (info.holderName.isNotEmpty)
              Text(context.trMsg('wholesale_order_card_holder', params: {'name': info.holderName}),
                  style: TextStyle(fontSize: 13, color: c.ink2)),
            if (info.sellerName.isNotEmpty)
              Text(context.trMsg('wholesale_order_card_seller', params: {'name': info.sellerName}),
                  style: TextStyle(fontSize: 13, color: c.ink2)),
          ],
        ),
      ),
    );
  }
}

/// Харидор юборган чек — сервер ёзган токенли URL (`cardPayment.receiptUrl`).
/// Сотувчида Storage ўқиш ҳуқуқи йўқ, шунинг учун йўлдан URL олинмайди.
class _ReceiptImage extends StatelessWidget {
  const _ReceiptImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Column(
      key: const ValueKey('wholesale-receipt'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('wholesale_order_receipt_title'),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: CachedNetworkImage(
            imageUrl: url,
            height: 260,
            width: double.infinity,
            fit: BoxFit.contain,
            // Статик ўринбосар (чексиз анимациясиз).
            placeholder: (_, __) => SizedBox(
              height: 120,
              child: Center(child: Icon(Icons.receipt_long_outlined, size: 40, color: c.ink3)),
            ),
            errorWidget: (_, __, ___) => Text(context.tr('wholesale_order_receipt_load_failed'),
                style: TextStyle(fontSize: 12, color: c.danger)),
          ),
        ),
      ],
    );
  }
}

/// Рад этиш сабаби (3..300 белги — сервер ҳам текширади). Сабаб харидорга
/// хабарномада юборилмайди (шахсий маълумот бўлиши мумкин), буюртмада сақланади.
class _RejectReasonDialog extends StatefulWidget {
  const _RejectReasonDialog();

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final _ctrl = TextEditingController();
  bool _err = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _ctrl.text.trim();
    if (t.length < 3) {
      setState(() => _err = true);
      return;
    }
    Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('wholesale_order_reject_title')),
      content: TextField(
        key: const ValueKey('wholesale-reject-reason'),
        controller: _ctrl,
        autofocus: true,
        maxLength: 300,
        maxLines: 3,
        onChanged: (_) {
          if (_err) setState(() => _err = false);
        },
        decoration: InputDecoration(
          hintText: context.tr('wholesale_order_reject_hint'),
          errorText: _err ? context.tr('wholesale_order_reject_err') : null,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('consent_no'))),
        FilledButton(
          key: const ValueKey('wholesale-reject-submit'),
          onPressed: _submit,
          child: Text(context.tr('wholesale_order_reject_btn')),
        ),
      ],
    );
  }
}