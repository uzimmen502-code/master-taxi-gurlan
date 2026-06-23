import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/payment_products.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/order_model.dart';
import '../../../models/procurement_product.dart';
import '../../../services/order_payment_service.dart';
import '../../../services/procurement_prices_service.dart';
import '../controllers/courier_controller.dart';

/// Курьер «Тўлов» — нақд / карта / кошелёк / маҳсулот(лар).
class CourierPaymentSheet extends StatefulWidget {
  const CourierPaymentSheet({
    super.key,
    required this.order,
    required this.onSubmit,
  });

  final OrderModel order;
  final Future<Map<String, dynamic>> Function(List<Map<String, dynamic>> lines)
      onSubmit;

  @override
  State<CourierPaymentSheet> createState() => _CourierPaymentSheetState();
}

class _CourierPaymentSheetState extends State<CourierPaymentSheet> {
  String _mode = 'cash';
  String _walletShortfallMode = 'cash';
  final _cashCtrl = TextEditingController();
  final _cardCtrl = TextEditingController();

  ProcurementProduct? _product;
  List<ProcurementProduct> _catalog = [];
  bool _catalogLoading = true;
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();
  final List<Map<String, dynamic>> _productLines = [];

  bool _busy = false;
  int? _walletBalance;
  bool _balanceLoading = true;
  Map<String, dynamic>? _confirmationSummary;
  List<Map<String, dynamic>> _submittedLines = const [];

  String _l(String key, [Map<String, String> params = const {}]) {
    var s = context.tr(key);
    for (final e in params.entries) {
      s = s.replaceAll('{${e.key}}', e.value);
    }
    return s;
  }

  String get _cur => context.tr('currency_sum');

  @override
  void initState() {
    super.initState();
    _cashCtrl.text = '${widget.order.total}';
    _cashCtrl.addListener(_onAmountChanged);
    _cardCtrl.addListener(_onAmountChanged);
    _loadCatalog();
    _loadWalletBalance();
  }

  List<ProcurementProduct> _fallbackCatalog() {
    return PaymentProducts.defaults
        .map(
          (p) => ProcurementProduct(
            code: p.code,
            label: p.labelUz,
            unit: p.unit,
            price: p.defaultUnitPrice,
            active: true,
          ),
        )
        .toList();
  }

  Future<void> _loadCatalog() async {
    try {
      final items = await ProcurementPricesService().getAll();
      if (!mounted) return;
      final active = items.where((p) => p.active).toList();
      setState(() {
        _catalog = active.isNotEmpty ? active : _fallbackCatalog();
        _catalogLoading = false;
        if (_catalog.isNotEmpty) {
          _product = _catalog.first;
          _priceCtrl.text = '${_product!.price}';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _catalog = _fallbackCatalog();
        _catalogLoading = false;
        if (_catalog.isNotEmpty) {
          _product = _catalog.first;
          _priceCtrl.text = '${_product!.price}';
        }
      });
    }
  }

  Future<void> _loadWalletBalance() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final courierPhone = prefs.getString('user_phone') ?? '';
      if (courierPhone.isEmpty || widget.order.userPhone.isEmpty) {
        if (mounted) setState(() => _balanceLoading = false);
        return;
      }
      final balance = await OrderPaymentService.getCustomerWalletBalance(
        courierPhone: courierPhone,
        customerPhone: widget.order.userPhone,
      );
      if (!mounted) return;
      setState(() {
        _walletBalance = balance;
        _balanceLoading = false;
        if (_mode == 'wallet') {
          _fillCashOrCardForMode('wallet');
        }
      });
    } catch (_) {
      if (mounted) setState(() => _balanceLoading = false);
    }
  }

  void _onAmountChanged() => setState(() {});

  @override
  void dispose() {
    _cashCtrl.removeListener(_onAmountChanged);
    _cardCtrl.removeListener(_onAmountChanged);
    _cashCtrl.dispose();
    _cardCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  int _productLinesSum() {
    var sum = 0;
    for (final l in _productLines) {
      sum += (l['amount'] as num?)?.toInt() ?? 0;
    }
    return sum;
  }

  int get _remainingDue {
    final due = widget.order.total - _productLinesSum();
    return due > 0 ? due : 0;
  }

  /// Кошелёк ҚОЛДИҚни қоплайди: нақд/карта биринчи, фарқи кошелёкдан
  /// (ҳеч қачон ортиқча тўламайди).
  int get _walletPayable {
    if (_mode != 'wallet') return 0;
    final bal = _walletBalance ?? 0;
    if (bal <= 0) return 0;
    final need = _remainingDue - _walletCashCardEntered;
    if (need <= 0) return 0;
    return need < bal ? need : bal;
  }

  /// Кошелёк режимида курьер киритган нақд/карта (маҳсулот _remainingDue'да).
  int get _walletCashCardEntered {
    if (_mode != 'wallet') return 0;
    if (_walletShortfallMode == 'cash') {
      return int.tryParse(_cashCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
    }
    if (_walletShortfallMode == 'card') {
      return int.tryParse(_cardCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
    }
    return 0;
  }

  /// Камида олиниши керак бўлган нақд (баланс буюртмани тўлиқ қопламаса).
  int get _walletMinCash {
    if (_mode != 'wallet') return 0;
    final bal = _walletBalance ?? 0;
    final m = _remainingDue - bal;
    return m > 0 ? m : 0;
  }

  /// Ҳали қопланмаган қисм (кошелёк + киритилган нақд/картадан кейин).
  int get _walletShortfall {
    if (_mode != 'wallet') return 0;
    final s = _remainingDue - _walletPayable - _walletCashCardEntered;
    return s > 0 ? s : 0;
  }

  int _enteredCashOrCard() {
    if (_mode == 'cash') {
      return int.tryParse(_cashCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
    }
    if (_mode == 'card') {
      return int.tryParse(_cardCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
    }
    return 0;
  }

  /// Нақд/карта/маҳсулot режимида киритилган сумма буюртмадан кам бўлса,
  /// қолган қисм автоматик кошелёкдан ечилади (баланс етганча).
  int get _autoWalletTopUp {
    if (_mode != 'cash' && _mode != 'card' && _mode != 'product') return 0;
    final deficit = _remainingDue - _enteredCashOrCard();
    if (deficit <= 0) return 0;
    final bal = _walletBalance ?? 0;
    if (bal <= 0) return 0;
    return deficit < bal ? deficit : bal;
  }

  bool get _walletModeUnavailable =>
      _mode == 'wallet' &&
      !_balanceLoading &&
      (_walletBalance == null || _walletBalance == 0);

  int _paymentSum() {
    var sum = _productLinesSum();
    if (_mode == 'cash') {
      sum += int.tryParse(_cashCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
      sum += _autoWalletTopUp;
    } else if (_mode == 'card') {
      sum += int.tryParse(_cardCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
      sum += _autoWalletTopUp;
    } else if (_mode == 'wallet') {
      sum += _walletPayable;
      sum += _walletCashCardEntered;
    }
    return sum;
  }

  void _fillWalletShortfallFields() {
    // Дефолт: камида керак бўлган нақд (кошелёк қолганини қоплайди).
    final minCash = _walletMinCash;
    if (minCash <= 0) {
      _cashCtrl.clear();
      _cardCtrl.clear();
      return;
    }
    if (_walletShortfallMode == 'cash') {
      _cardCtrl.clear();
      _cashCtrl.text = '$minCash';
    } else if (_walletShortfallMode == 'card') {
      _cashCtrl.clear();
      _cardCtrl.text = '$minCash';
    } else {
      _cashCtrl.clear();
      _cardCtrl.clear();
    }
  }

  void _fillCashOrCardForMode(String mode) {
    final productSum = _productLinesSum();
    final shortfall = widget.order.total - productSum;
    if (mode == 'cash') {
      _cardCtrl.clear();
      _cashCtrl.text = productSum == 0
          ? '${widget.order.total}'
          : (shortfall > 0 ? '$shortfall' : '');
    } else if (mode == 'card') {
      _cashCtrl.clear();
      _cardCtrl.text = productSum == 0
          ? '${widget.order.total}'
          : (shortfall > 0 ? '$shortfall' : '');
    } else if (mode == 'wallet') {
      _fillWalletShortfallFields();
    } else {
      _cashCtrl.clear();
      _cardCtrl.clear();
    }
  }

  Widget? _buildWalletBalanceBanner() {
    if (!_balanceLoading && _walletBalance == null) return null;

    final String text;
    if (_balanceLoading) {
      text = _l('courier_wallet_checking');
    } else {
      text = _l('courier_wallet_balance', {
        'amount': formatPrice(_walletBalance!),
        'currency': _cur,
      });
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          if (_balanceLoading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(
              Icons.account_balance_wallet_outlined,
              size: 20,
              color: AppColors.primary,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentStatus() {
    final sum = _paymentSum();
    final diff = sum - widget.order.total;
    final underLabel = _mode == 'wallet' && _walletShortfall > 0
        ? _l('courier_pay_deficit')
        : _l('courier_pay_shortfall');
    final topUp = _autoWalletTopUp;

    Widget withTopUpNote(Widget status) {
      if (topUp <= 0) return status;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _l('courier_wallet_debit_live', {
              'amount': formatPrice(topUp),
              'currency': _cur,
            }),
            style: TextStyle(
              color: Colors.orange.shade800,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          status,
        ],
      );
    }

    if (diff < 0) {
      return withTopUpNote(
        Text(
          '$underLabel: ${formatPrice(-diff)} $_cur',
          style: TextStyle(
            color: Colors.red.shade700,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    if (diff == 0) {
      return withTopUpNote(
        Text(
          _l('courier_pay_complete'),
          style: TextStyle(color: Colors.grey.shade700),
        ),
      );
    }
    final changeNote = _mode == 'wallet'
        ? _l('courier_pay_change_wallet_mode', {
            'amount': formatPrice(diff),
            'currency': _cur,
          })
        : _l('courier_pay_change_wallet', {
            'amount': formatPrice(diff),
            'currency': _cur,
          });
    return Text(
      changeNote,
      style: const TextStyle(
        color: AppColors.primaryDark,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  void _onModeChanged(String mode) {
    setState(() {
      _mode = mode;
      if (mode == 'wallet') {
        _walletShortfallMode = 'cash';
      }
      _fillCashOrCardForMode(mode);
    });
  }

  void _onWalletShortfallModeChanged(String mode) {
    setState(() {
      _walletShortfallMode = mode;
      _fillWalletShortfallFields();
    });
  }

  Widget _buildProductEntry() {
    if (_catalogLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_catalog.isEmpty) {
      return const SizedBox();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<ProcurementProduct>(
          value: _product,
          decoration: InputDecoration(
            labelText: _l('courier_product_field'),
            border: OutlineInputBorder(),
          ),
          items: [
            for (final p in _catalog)
              DropdownMenuItem(
                value: p,
                child: Text(p.label),
              ),
          ],
          onChanged: (p) {
            if (p == null) return;
            setState(() {
              _product = p;
              _priceCtrl.text = '${p.price}';
            });
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: _l('courier_qty_field', {
                    'unit': _product?.unit ?? '',
                  }),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _priceCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: _l('courier_price_field', {'currency': _cur}),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _addProductLine,
          icon: const Icon(Icons.add),
          label: Text(_l('courier_add_product')),
        ),
      ],
    );
  }

  Widget _buildWalletModeContent() {
    if (_balanceLoading) {
      return Text(_l('courier_wallet_checking'));
    }
    if (_walletModeUnavailable) {
      return Text(
        _l('courier_wallet_empty'),
        style: TextStyle(
          color: Colors.grey.shade700,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    final walletPayable = _walletPayable;
    final minCash = _walletMinCash;

    if (minCash <= 0) {
      // Баланс буюртмани тўлиқ қоплайди — нақд керак эмас.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _l('courier_wallet_pays_full', {
              'amount': formatPrice(_remainingDue),
              'currency': _cur,
            }),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 8),
          _buildPaymentStatus(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade300),
          ),
          child: Text(
            _l('courier_wallet_partial_hint', {
              'balance': formatPrice(_walletBalance ?? 0),
              'minCash': formatPrice(minCash),
              'currency': _cur,
            }),
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: Colors.orange.shade900,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'cash', label: Text(_l('courier_pay_cash_emoji'))),
            ButtonSegment(value: 'card', label: Text(_l('courier_pay_card_emoji'))),
            ButtonSegment(
              value: 'product',
              label: Text(_l('courier_pay_product_emoji')),
            ),
          ],
          selected: {_walletShortfallMode},
          onSelectionChanged: (s) => _onWalletShortfallModeChanged(s.first),
        ),
        const SizedBox(height: 12),
        if (_walletShortfallMode == 'cash')
          TextField(
            controller: _cashCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: _l('courier_cash_min_label', {
                'amount': formatPrice(minCash),
                'currency': _cur,
              }),
              border: const OutlineInputBorder(),
            ),
          ),
        if (_walletShortfallMode == 'card')
          TextField(
            controller: _cardCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: _l('courier_card_min_label', {
                'amount': formatPrice(minCash),
                'currency': _cur,
              }),
              border: const OutlineInputBorder(),
            ),
          ),
        if (_walletShortfallMode == 'product') _buildProductEntry(),
        const SizedBox(height: 10),
        if (walletPayable > 0)
          Text(
            _l('courier_wallet_debit_live', {
              'amount': formatPrice(walletPayable),
              'currency': _cur,
            }),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.primaryDark,
            ),
          ),
        const SizedBox(height: 6),
        _buildPaymentStatus(),
      ],
    );
  }

  void _addProductLine() {
    final p = _product;
    if (p == null) return;
    final qty = double.tryParse(_qtyCtrl.text.replaceAll(',', '.')) ?? 0;
    final unitPrice =
        int.tryParse(_priceCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
    if (qty <= 0 || unitPrice <= 0) return;
    final amount = (qty * unitPrice).round();
    setState(() {
      _productLines.add({
        'kind': 'product',
        'productCode': p.code,
        'productLabel': p.label,
        'qty': qty,
        'unit': p.unit,
        'unitPrice': unitPrice,
        'suggestedUnitPrice': p.price,
        'amount': amount,
      });
      _fillCashOrCardForMode(_mode);
    });
  }

  List<Map<String, dynamic>> _buildLines() {
    final lines = <Map<String, dynamic>>[..._productLines];
    if (_mode == 'cash') {
      final cash =
          int.tryParse(_cashCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
      if (cash > 0) {
        lines.add({'kind': 'cash', 'amount': cash, 'qty': 1, 'unit': 'сўм'});
      }
      final topUp = _autoWalletTopUp;
      if (topUp > 0) {
        lines.add({'kind': 'wallet', 'amount': topUp});
      }
    } else if (_mode == 'card') {
      final card =
          int.tryParse(_cardCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
      if (card > 0) {
        lines.add({'kind': 'card', 'amount': card, 'qty': 1, 'unit': 'сўм'});
      }
      final topUp = _autoWalletTopUp;
      if (topUp > 0) {
        lines.add({'kind': 'wallet', 'amount': topUp});
      }
    } else if (_mode == 'product') {
      // Маҳсулот суммаси буюртмадан кам бўлса — қолгани кошелёкдан.
      final topUp = _autoWalletTopUp;
      if (topUp > 0) {
        lines.add({'kind': 'wallet', 'amount': topUp});
      }
    } else if (_mode == 'wallet') {
      final walletPayable = _walletPayable;
      if (walletPayable > 0) {
        lines.add({'kind': 'wallet', 'amount': walletPayable});
      }
      final entered = _walletCashCardEntered;
      if (entered > 0) {
        if (_walletShortfallMode == 'cash') {
          lines.add({'kind': 'cash', 'amount': entered, 'qty': 1, 'unit': 'сўм'});
        } else if (_walletShortfallMode == 'card') {
          lines.add({'kind': 'card', 'amount': entered, 'qty': 1, 'unit': 'сўм'});
        }
      }
    }
    return lines;
  }

  Future<void> _submit() async {
    if (_walletModeUnavailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l('courier_wallet_empty_use_cash')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final lines = _buildLines();
    final sum = lines.fold<int>(
      0,
      (s, l) => s + ((l['amount'] as num?)?.toInt() ?? 0),
    );

    final walletUsed = lines
        .where((l) => l['kind'] == 'wallet')
        .fold<int>(0, (s, l) => s + ((l['amount'] as num?)?.toInt() ?? 0));
    final balance = _walletBalance ?? 0;
    if (walletUsed > balance) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l('courier_wallet_insufficient', {
              'balance': formatPrice(balance),
              'used': formatPrice(walletUsed),
              'currency': _cur,
            }),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (sum < widget.order.total - 1) {
      final short = widget.order.total - sum;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _mode == 'wallet'
                ? _l('courier_pay_incomplete_wallet', {
                    'short': formatPrice(short),
                    'currency': _cur,
                  })
                : _l('courier_pay_underpaid', {
                    'sum': formatPrice(sum),
                    'total': formatPrice(widget.order.total),
                    'currency': _cur,
                  }),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final summary = await widget.onSubmit(lines);
      if (!mounted) return;
      setState(() {
        _confirmationSummary = summary;
        _submittedLines = lines;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted && _confirmationSummary == null) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _finishConfirmation() async {
    setState(() => _busy = true);
    try {
      await CourierController.active?.confirmAndAdvance(
        orderId: widget.order.id,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Тасдиқ экранидаги кошелёк блоки: эски қолдиқ → қайтим/ечим → янги қолдиқ.
  Widget _buildWalletBreakdownBox({
    required int oldBalance,
    required int changeCredit,
    required int walletSum,
    required int newBalance,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet,
                  color: AppColors.primary, size: 24),
              const SizedBox(width: 8),
              Text(
                _l('courier_customer_wallet'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _walletBreakdownRow(_l('courier_wallet_old'), oldBalance),
          if (changeCredit > 0) ...[
            const SizedBox(height: 6),
            _walletBreakdownRow(
              _l('courier_wallet_change'),
              changeCredit,
              color: AppColors.primaryDark,
            ),
          ],
          if (walletSum > 0) ...[
            const SizedBox(height: 6),
            _walletBreakdownRow(
              _l('courier_wallet_debit'),
              walletSum,
              color: Colors.orange.shade800,
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          _walletBreakdownRow(_l('courier_wallet_new'), newBalance, bold: true),
        ],
      ),
    );
  }

  Widget _walletBreakdownRow(
    String label,
    int amount, {
    Color? color,
    bool bold = false,
  }) {
    final style = TextStyle(
      fontSize: bold ? 17 : 14,
      fontWeight: bold ? FontWeight.bold : FontWeight.w600,
      color: color,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(label, style: style)),
        const SizedBox(width: 8),
        Text('${formatPrice(amount)} $_cur', style: style),
      ],
    );
  }

  Widget _buildConfirmationView() {
    final summary = _confirmationSummary!;
    final orderTotal =
        (summary['orderTotal'] as num?)?.toInt() ?? widget.order.total;
    final changeCredit = (summary['changeCredit'] as num?)?.toInt() ?? 0;
    final newBalance = (summary['newBalance'] as num?)?.toInt() ?? 0;

    var cashSum = 0;
    var cardSum = 0;
    var walletSum = 0;
    final productLines = <Map<String, dynamic>>[];
    for (final line in _submittedLines) {
      final kind = (line['kind'] as String?) ?? '';
      final amount = (line['amount'] as num?)?.toInt() ?? 0;
      if (kind == 'cash') {
        cashSum += amount;
      } else if (kind == 'card') {
        cardSum += amount;
      } else if (kind == 'wallet') {
        walletSum += amount;
      } else if (kind == 'product') {
        productLines.add(line);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _l('courier_payment_accepted_title'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          _l('courier_order_total_line', {
            'amount': formatPrice(orderTotal),
            'currency': _cur,
          }),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Text(
          _l('courier_payment_breakdown'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        if (walletSum > 0)
          Text(_l('courier_paid_wallet_line', {
            'amount': formatPrice(walletSum),
            'currency': _cur,
          })),
        if (cashSum > 0)
          Text(_l('courier_paid_cash_line', {
            'amount': formatPrice(cashSum),
            'currency': _cur,
          })),
        if (cardSum > 0)
          Text(_l('courier_paid_card_line', {
            'amount': formatPrice(cardSum),
            'currency': _cur,
          })),
        if (productLines.isNotEmpty) ...[
          Text(_l('courier_paid_products_line')),
          for (final p in productLines)
            Text(
              '     • ${p['productLabel'] ?? p['productCode']}: '
              '${formatPrice((p['amount'] as num?)?.toInt() ?? 0)} сўм',
            ),
        ],
        const SizedBox(height: 16),
        _buildWalletBreakdownBox(
          oldBalance: _walletBalance ?? (newBalance + walletSum - changeCredit),
          changeCredit: changeCredit,
          walletSum: walletSum,
          newBalance: newBalance,
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _finishConfirmation,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryDark,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _busy
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  _l('courier_finalize'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_confirmationSummary != null) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 12,
        ),
        child: SingleChildScrollView(child: _buildConfirmationView()),
      );
    }

    final walletBanner = _buildWalletBalanceBanner();
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 12,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _l('courier_payment_title', {
                'total': formatPrice(widget.order.total),
                'currency': _cur,
              }),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (walletBanner != null) ...[
              const SizedBox(height: 8),
              walletBanner,
            ],
            if (_mode != 'wallet' || _walletModeUnavailable || _balanceLoading) ...[
              const SizedBox(height: 8),
              _buildPaymentStatus(),
            ],
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'cash',
                  label: Text(_l('courier_pay_mode_cash')),
                ),
                ButtonSegment(
                  value: 'card',
                  label: Text(_l('courier_pay_mode_card')),
                ),
                ButtonSegment(
                  value: 'wallet',
                  label: Text(_l('courier_pay_mode_wallet')),
                ),
                ButtonSegment(
                  value: 'product',
                  label: Text(_l('courier_pay_mode_product')),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => _onModeChanged(s.first),
            ),
            const SizedBox(height: 12),
            if (_mode == 'wallet') _buildWalletModeContent(),
            if (_mode == 'cash')
              TextField(
                controller: _cashCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: _l('courier_cash_field', {'currency': _cur}),
                  border: OutlineInputBorder(),
                ),
              ),
            if (_mode == 'card')
              TextField(
                controller: _cardCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: _l('courier_card_field', {'currency': _cur}),
                  border: OutlineInputBorder(),
                ),
              ),
            if (_mode == 'product') _buildProductEntry(),
            if (_productLines.isNotEmpty &&
                (_mode == 'product' ||
                    (_mode == 'wallet' && _walletShortfallMode == 'product'))) ...[
              const SizedBox(height: 12),
              Text(
                _l('courier_added_products'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              for (var i = 0; i < _productLines.length; i++)
                ListTile(
                  dense: true,
                  title: Text(
                    '${_productLines[i]['productLabel']} · '
                    '${_productLines[i]['qty']} · '
                    '${formatPrice((_productLines[i]['amount'] as num?)?.toInt() ?? 0)} $_cur',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() {
                      _productLines.removeAt(i);
                      _fillCashOrCardForMode(_mode);
                    }),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: (_busy || _walletModeUnavailable) ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _l('courier_submit_payment'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
