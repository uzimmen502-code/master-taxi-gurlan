// Улгуржи буюртма тафсилоти — харидор ҳам, сотувчи ҳам шу экранни кўради;
// кимга қайси амал кўринишини [WholesaleOrderActions] белгилайди.
//
// Эга қарори (2026-10-31): СОТУВЧИ буюртмани ҚАБУЛ/РАД ҚИЛМАЙДИ — бу экранда
// бундай тугма йўқ. Сотувчининг ягона амали — карта буюртмасида «Пул тушди».
// Ҳолатни фақат сервер ўзгартиради; экран оқимни кўрсатади.

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
  });

  final WholesaleOrder order;
  final String viewerId;
  final WholesaleOrdersRepository repository;
  final WholesaleReceiptUploader? uploadReceipt;

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
    final body = [
      context.tr('wholesale_order_cancel_confirm'),
      if (!_o.isCardOrder) context.tr('wholesale_order_cancel_refund_note'),
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

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final o = _o;
    final a = WholesaleOrderActions.of(o, widget.viewerId);
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
                  Flexible(child: WholesaleOrderStatusChip(status: o.status)),
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
        _card(context, WholesaleOrderTimeline(status: o.status)),
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
                  context.tr(o.isCardOrder ? 'wholesale_order_payment_card' : 'wholesale_order_payment_wallet'),
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
        if (_error != null) WalletInlineError(text: _error!),
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

  /// Қайтиш жараёни (3b) — харидорга ҳам, сотувчига ҳам кўринади.
  static bool _showsReturn(WholesaleOrder o) =>
      o.returnStatus.isNotEmpty ||
      o.status == WholesaleOrderStatus.refused ||
      o.status == WholesaleOrderStatus.returning ||
      o.status == WholesaleOrderStatus.returned;

  Widget _returnCard(BuildContext context, WholesaleOrder o) {
    final c = context.ava;
    final key = WholesaleReturnStatus.l10nKey(o.returnStatus) ??
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