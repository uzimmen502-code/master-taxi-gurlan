import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/courier_order.dart';
import '../../../repositories/courier_orders_repository.dart';
import '../../../services/order_payment_service.dart';

const _bg = Color(0xFFF6FAF2);
const _cardBorder = Color(0xFFC8DDB8);
const _sectionLabel = Color(0xFF7A9070);
const _titleDark = Color(0xFF1A3A20);
const _primaryGreen = Color(0xFF2E7D32);

/// Kuryer — bitta buyurtma tafsilotlari va holat boshqaruvi.
class CourierOrderDetailScreen extends StatefulWidget {
  const CourierOrderDetailScreen({super.key, required this.order});

  final CourierOrder order;

  @override
  State<CourierOrderDetailScreen> createState() =>
      _CourierOrderDetailScreenState();
}

class _CourierOrderDetailScreenState extends State<CourierOrderDetailScreen> {
  late CourierOrder _order;
  bool _busy = false;
  String _courierPhone = '';

  int get _orderTotal => _order.totalPrice > 0
      ? _order.totalPrice
      : _order.estimatedPrice + _order.deliveryFee;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _loadCourierPhone();
  }

  Future<void> _loadCourierPhone() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _courierPhone = phoneDigits(prefs.getString('user_phone') ?? '');
    });
  }

  Future<void> _openMaps() async {
    final Uri uri;
    if (_order.deliveryLat != null && _order.deliveryLng != null) {
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query='
        '${_order.deliveryLat},${_order.deliveryLng}',
      );
    } else {
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query='
        '${Uri.encodeComponent(_order.deliveryAddress)}',
      );
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _markPickedUp() async {
    setState(() => _busy = true);
    try {
      await context.read<CourierOrdersRepository>().markPickedUp(_order.id);
      if (!mounted) return;
      setState(() {
        _order = _order.copyWith(status: CourierOrderStatus.pickedUp);
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('courier_order_en_route_btn'))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  Future<void> _openPayment() async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CourierOrderPaymentSheet(
        order: _order,
        orderTotal: _orderTotal,
        courierPhone: _courierPhone,
      ),
    );

    if (done != true || !mounted) return;

    setState(() {
      _order = _order.copyWith(status: CourierOrderStatus.delivered);
    });
    Navigator.pop(context);
  }

  String _statusLabel(CourierOrderStatus status) {
    return switch (status) {
      CourierOrderStatus.pending => context.tr('courier_status_waiting'),
      CourierOrderStatus.accepted => 'Qabul qilindi',
      CourierOrderStatus.pickedUp => context.tr('courier_status_en_route'),
      CourierOrderStatus.delivered =>
        context.tr('courier_order_delivered_badge'),
      CourierOrderStatus.cancelled => 'Bekor qilindi',
    };
  }

  Widget _sectionCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _titleDark,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _statusBadge() {
    final status = _order.status;
    final (bg, fg) = switch (status) {
      CourierOrderStatus.pending =>
        (Colors.orange.shade100, Colors.orange.shade900),
      CourierOrderStatus.accepted =>
        (Colors.blue.shade100, Colors.blue.shade900),
      CourierOrderStatus.pickedUp =>
        (Colors.purple.shade100, Colors.purple.shade900),
      CourierOrderStatus.delivered =>
        (Colors.green.shade100, Colors.green.shade900),
      CourierOrderStatus.cancelled =>
        (Colors.grey.shade200, Colors.grey.shade800),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  Widget? _buildActionButton() {
    if (_busy) {
      return const Center(
        child: CircularProgressIndicator(color: _primaryGreen),
      );
    }

    switch (_order.status) {
      case CourierOrderStatus.accepted:
        return FilledButton(
          onPressed: _markPickedUp,
          style: FilledButton.styleFrom(
            backgroundColor: _primaryGreen,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(context.tr('courier_order_en_route_btn')),
        );
      case CourierOrderStatus.pickedUp:
        return FilledButton(
          onPressed: _openPayment,
          style: FilledButton.styleFrom(
            backgroundColor: _primaryGreen,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(context.tr('courier_order_pay_btn')),
        );
      case CourierOrderStatus.delivered:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Text(
            context.tr('courier_order_delivered_badge'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _primaryGreen,
            ),
          ),
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = _buildActionButton();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _titleDark,
        elevation: 0,
        title: Text(
          context.tr('courier_order_detail_title'),
          style: const TextStyle(fontWeight: FontWeight.w600, color: _titleDark),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionCard(
              title: context.tr('courier_order_customer_card'),
              children: [
                Text(
                  _order.customerName.isNotEmpty
                      ? _order.customerName
                      : context.tr('courier_order_customer_card'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _titleDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _order.customerPhone,
                  style: const TextStyle(fontSize: 14, color: _sectionLabel),
                ),
                const SizedBox(height: 10),
                Text(
                  _order.deliveryAddress,
                  style: const TextStyle(
                    fontSize: 14,
                    color: _titleDark,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _openMaps,
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: Text(context.tr('courier_order_open_maps')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryGreen,
                    side: const BorderSide(color: _cardBorder),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _sectionCard(
              title: context.tr('courier_order_info_section'),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _statusBadge(),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _order.description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: _titleDark,
                    height: 1.4,
                  ),
                ),
                if (_order.estimatedPrice > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    context
                        .tr('courier_order_estimated_price')
                        .replaceAll(
                          '{price}',
                          formatPrice(_order.estimatedPrice),
                        ),
                    style: const TextStyle(fontSize: 13, color: _sectionLabel),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  context
                      .tr('courier_order_delivery_fee')
                      .replaceAll('{fee}', formatPrice(_order.deliveryFee)),
                  style: const TextStyle(fontSize: 13, color: _sectionLabel),
                ),
                if (_orderTotal > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    context
                        .tr('courier_order_total')
                        .replaceAll('{total}', formatPrice(_orderTotal)),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _primaryGreen,
                    ),
                  ),
                ],
              ],
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

class _CourierOrderPaymentSheet extends StatefulWidget {
  const _CourierOrderPaymentSheet({
    required this.order,
    required this.orderTotal,
    required this.courierPhone,
  });

  final CourierOrder order;
  final int orderTotal;
  final String courierPhone;

  @override
  State<_CourierOrderPaymentSheet> createState() =>
      _CourierOrderPaymentSheetState();
}

class _CourierOrderPaymentSheetState extends State<_CourierOrderPaymentSheet> {
  late final TextEditingController _cashCtrl;
  late final TextEditingController _cardCtrl;
  late final TextEditingController _walletCtrl;
  int? _walletBalance;
  bool _loadingBalance = true;
  bool _submitting = false;
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    _cashCtrl = TextEditingController(text: '${widget.orderTotal}');
    _cardCtrl = TextEditingController(text: '0');
    _walletCtrl = TextEditingController(text: '0');
    _cashCtrl.addListener(_onFieldsChanged);
    _cardCtrl.addListener(_onFieldsChanged);
    _walletCtrl.addListener(_onFieldsChanged);
    _loadBalance();
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    _cardCtrl.dispose();
    _walletCtrl.dispose();
    super.dispose();
  }

  void _onFieldsChanged() => setState(() {});

  Future<void> _loadBalance() async {
    final balance = await OrderPaymentService.getCustomerWalletBalance(
      courierPhone: widget.courierPhone,
      customerPhone: widget.order.customerPhone,
    );
    if (!mounted) return;
    setState(() {
      _walletBalance = balance ?? 0;
      _loadingBalance = false;
    });
  }

  int _parseField(TextEditingController c) {
    final raw = c.text.replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(raw) ?? 0;
  }

  int get _cash => _parseField(_cashCtrl);
  int get _card => _parseField(_cardCtrl);
  int get _wallet => _parseField(_walletCtrl);
  int get _covered => _cash + _card + _wallet;
  int get _remaining => widget.orderTotal - _covered;
  bool get _isFullyCovered => _covered >= widget.orderTotal;

  String _line(String key, String amount) {
    return context
        .tr(key)
        .replaceAll('{amount}', amount)
        .replaceAll('{currency}', context.tr('currency_sum'));
  }

  Future<void> _submit() async {
    if (!_isFullyCovered || _submitting) return;
    setState(() => _submitting = true);
    try {
      final result = await OrderPaymentService.courierSubmitCourierOrderPayment(
        courierPhone: widget.courierPhone,
        orderId: widget.order.id,
        cashGiven: _cash,
        cardGiven: _card,
        walletGiven: _wallet,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  Widget _amountField({
    required String label,
    required TextEditingController controller,
    int? max,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixText: context.tr('currency_sum'),
      ),
      onChanged: max != null
          ? (_) {
              final v = _parseField(controller);
              if (v > max) {
                controller.text = '$max';
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: controller.text.length),
                );
              }
            }
          : null,
    );
  }

  Widget _confirmationView() {
    final total = (_result!['total'] as num?)?.toInt() ?? widget.orderTotal;
    final cash = _cash;
    final card = _card;
    final wallet = _wallet;
    final change = (_result!['changeCredit'] as num?)?.toInt() ?? 0;

    Widget line(String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(text, style: const TextStyle(fontSize: 15)),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('courier_order_success_delivered'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: _primaryGreen,
          ),
        ),
        const SizedBox(height: 16),
        line(
          context
              .tr('courier_order_total')
              .replaceAll('{total}', formatPrice(total)),
        ),
        if (cash > 0)
          line(_line('courier_paid_cash_line', formatPrice(cash))),
        if (card > 0)
          line(_line('courier_paid_card_line', formatPrice(card))),
        if (wallet > 0)
          line(_line('courier_paid_wallet_line', formatPrice(wallet))),
        if (change > 0)
          line(
            context
                .tr('courier_pay_change_wallet')
                .replaceAll('{amount}', formatPrice(change))
                .replaceAll('{currency}', context.tr('currency_sum')),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: _primaryGreen,
            minimumSize: const Size.fromHeight(48),
          ),
          child: Text(context.tr('courier_order_finalize')),
        ),
      ],
    );
  }

  Widget _paymentForm() {
    final balance = _walletBalance ?? 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context
              .tr('courier_order_payment_title')
              .replaceAll('{total}', formatPrice(widget.orderTotal)),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _titleDark,
          ),
        ),
        const SizedBox(height: 16),
        _amountField(
          label: context.tr('courier_pay_mode_cash'),
          controller: _cashCtrl,
        ),
        const SizedBox(height: 12),
        _amountField(
          label: context.tr('courier_pay_mode_card'),
          controller: _cardCtrl,
        ),
        const SizedBox(height: 16),
        if (_loadingBalance)
          const LinearProgressIndicator(minHeight: 2)
        else
          Text(
            context
                .tr('courier_order_wallet_balance')
                .replaceAll('{bal}', formatPrice(balance)),
            style: const TextStyle(fontSize: 14, color: _sectionLabel),
          ),
        const SizedBox(height: 8),
        _amountField(
          label: context.tr('courier_pay_mode_wallet'),
          controller: _walletCtrl,
          max: balance,
        ),
        const SizedBox(height: 16),
        Text(
          _isFullyCovered
              ? context.tr('courier_order_coverage_full')
              : context
                  .tr('courier_order_coverage_deficit')
                  .replaceAll('{amount}', formatPrice(_remaining)),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: _isFullyCovered ? _primaryGreen : Colors.orange.shade800,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _isFullyCovered && !_submitting ? _submit : null,
          style: FilledButton.styleFrom(
            backgroundColor: _primaryGreen,
            minimumSize: const Size.fromHeight(48),
          ),
          child: _submitting
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(context.tr('courier_order_confirm_payment')),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottom),
      child: SingleChildScrollView(
        child: _result != null ? _confirmationView() : _paymentForm(),
      ),
    );
  }
}
