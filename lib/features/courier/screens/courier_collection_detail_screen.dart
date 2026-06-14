import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/collection_task.dart';
import '../../../services/collection_service.dart';
import '../../../services/order_payment_service.dart';

/// Курьер — битта қабул вазифаси: маҳсулотларни текшириш ва миқдорни аниқлаш.
class CourierCollectionDetailScreen extends StatefulWidget {
  const CourierCollectionDetailScreen({super.key, required this.task});

  final CollectionTask task;

  @override
  State<CourierCollectionDetailScreen> createState() =>
      _CourierCollectionDetailScreenState();
}

class _CourierCollectionDetailScreenState
    extends State<CourierCollectionDetailScreen> {
  late final List<TextEditingController> _qtyCtrls;

  @override
  void initState() {
    super.initState();
    _qtyCtrls = [
      for (final item in widget.task.items)
        TextEditingController(text: _qtyText(item.qty)),
    ];
  }

  @override
  void dispose() {
    for (final c in _qtyCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  static String _qtyText(num qty) {
    if (qty == qty.roundToDouble()) return qty.toInt().toString();
    return qty.toString();
  }

  num _adjustedQty(int index) {
    final raw = _qtyCtrls[index].text.replaceAll(',', '.');
    return num.tryParse(raw) ?? 0;
  }

  int _lineTotal(int index) {
    final item = widget.task.items[index];
    return (_adjustedQty(index) * item.unitPrice).round();
  }

  int get _grandTotal {
    var total = 0;
    for (var i = 0; i < widget.task.items.length; i++) {
      total += _lineTotal(i);
    }
    return total;
  }

  /// B3 учун — курьер аниқлаган миқдорлар билан қаторлар.
  List<Map<String, dynamic>> get adjustedItems => [
        for (var i = 0; i < widget.task.items.length; i++)
          {
            'code': widget.task.items[i].code,
            'label': widget.task.items[i].label,
            'unit': widget.task.items[i].unit,
            'qty': _adjustedQty(i),
            'unitPrice': widget.task.items[i].unitPrice,
            'lineTotal': _lineTotal(i),
          },
      ];

  Future<void> _openMaps() async {
    final url = widget.task.mapsUrl;
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _onFinalizePressed() async {
    for (var i = 0; i < widget.task.items.length; i++) {
      if (_adjustedQty(i) <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${widget.task.items[i].label}: миқдорни киритинг',
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SettlementSheet(
        taskId: widget.task.id,
        customerPhone: widget.task.customerPhone,
        totalValue: _grandTotal,
        items: adjustedItems,
      ),
    );
    if (done == true && mounted) {
      // Вазифа якунланди — рўйхатга қайтамиз (фаол рўйхатдан чиқади).
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: const Text('📦 Қабул вазифаси'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _customerCard(task),
          const SizedBox(height: 12),
          const Text(
            'Маҳсулотлар',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Ҳақиқатда йиғилган миқдорни киритинг — нарх админ белгилаган.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < task.items.length; i++) _itemCard(i),
          const SizedBox(height: 80),
        ],
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  Widget _customerCard(CollectionTask task) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline,
                  size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.customerName.isNotEmpty
                      ? task.customerName
                      : 'Мижоз',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (task.customerPhone.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(
                '+${task.customerPhone}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ),
          ],
          if (task.pickupAddress.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.place_outlined,
                    size: 20, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.pickupAddress,
                    style: const TextStyle(fontSize: 13, height: 1.35),
                  ),
                ),
              ],
            ),
          ],
          if (task.hasPickupGps) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openMaps,
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('Google Maps\'да очиш'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryDark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _itemCard(int index) {
    final item = widget.task.items[index];
    final lineTotal = _lineTotal(index);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${formatPrice(item.unitPrice)} сўм / ${item.unit}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Режа: ${_qtyText(item.qty)} ${item.unit}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qtyCtrls[index],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Йиғилди (${item.unit})',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Қатор',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  Text(
                    lineTotal > 0 ? '${formatPrice(lineTotal)} сўм' : '—',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade300)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Жами қиймат:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${formatPrice(_grandTotal)} сўм',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: _onFinalizePressed,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Йиғишни якунлаш',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ҳисоб-китоб sheet — нақд берилган сумма + кошелёк ҳаракати (B3).
/// Нақд V дан ошса — фарқ мижоз кошелёгидан ечилади (V + баланс гача).
class _SettlementSheet extends StatefulWidget {
  const _SettlementSheet({
    required this.taskId,
    required this.customerPhone,
    required this.totalValue,
    required this.items,
  });

  final String taskId;
  final String customerPhone;
  final int totalValue;
  final List<Map<String, dynamic>> items;

  @override
  State<_SettlementSheet> createState() => _SettlementSheetState();
}

class _SettlementSheetState extends State<_SettlementSheet> {
  final _cashCtrl = TextEditingController(text: '0');
  bool _busy = false;
  Map<String, dynamic>? _result;

  int _customerBalance = 0;
  bool _balanceLoading = true;
  bool _balanceUnknown = false;

  @override
  void initState() {
    super.initState();
    _cashCtrl.addListener(() => setState(() {}));
    _loadCustomerBalance();
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCustomerBalance() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final courierPhone = prefs.getString('user_phone') ?? '';
      if (courierPhone.isEmpty || widget.customerPhone.isEmpty) {
        if (mounted) {
          setState(() {
            _balanceLoading = false;
            _balanceUnknown = true;
          });
        }
        return;
      }
      final balance = await OrderPaymentService.getCustomerWalletBalance(
        courierPhone: courierPhone,
        customerPhone: widget.customerPhone,
      );
      if (!mounted) return;
      setState(() {
        _customerBalance = balance ?? 0;
        _balanceUnknown = balance == null;
        _balanceLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _balanceLoading = false;
        _balanceUnknown = true;
      });
    }
  }

  int get _cashGiven =>
      int.tryParse(_cashCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;

  int get _maxCash => widget.totalValue + _customerBalance;

  /// Ишорали: + кошелёкка қўшилади, - кошелёкдан ечилади.
  int get _walletDelta => widget.totalValue - _cashGiven;

  int get _newBalance => _customerBalance + _walletDelta;

  bool get _cashTooBig => _cashGiven > _maxCash;

  String get _cashTooBigMessage =>
      'Нақд жами қиймат + кошелёк баланси (=${formatPrice(_maxCash)})дан ошмасин';

  Future<void> _submit() async {
    if (_cashTooBig) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_cashTooBigMessage),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Нақд V дан ошса — кошелёкдан ечишни алоҳида тасдиқлатамиз.
    final withdrawal = _cashGiven - widget.totalValue;
    if (withdrawal > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Диққат — кошелёкдан ечиш'),
          content: Text(
            'Мижозга товар қийматидан ${formatPrice(withdrawal)} сўм ортиқ '
            'нақд беряпсиз. Бу сумма унинг кошелёгидан ечилади.\n'
            'Янги баланс: ${formatPrice(_newBalance)} сўм. Тасдиқлайсизми?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Бекор'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade800,
              ),
              child: const Text('Ҳа, тасдиқлайман'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final courierPhone = prefs.getString('user_phone') ?? '';
      if (courierPhone.isEmpty) {
        throw Exception('Курьер телефони топилмади — қайта киринг');
      }
      final result = await CollectionService.finalizeCollection(
        courierPhone: courierPhone,
        taskId: widget.taskId,
        items: widget.items,
        cashGiven: _cashGiven,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 12,
      ),
      child: SingleChildScrollView(
        child: _result != null ? _confirmationView() : _formView(),
      ),
    );
  }

  Widget _formView() {
    final isWithdrawal = _cashGiven > widget.totalValue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Ҳисоб-китоб · ${formatPrice(widget.totalValue)} сўм',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Жами қиймат: ${formatPrice(widget.totalValue)} сўм',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (_balanceLoading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Text(
                '💼 Мижоз кошелёги: ${formatPrice(_customerBalance)} сўм'
                '${_balanceUnknown ? ' (баланс аниқланмади)' : ''}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _balanceUnknown
                      ? Colors.orange.shade800
                      : Colors.grey.shade800,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _cashCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Нақд берилди (мижозга)',
            suffixText: 'сўм',
            helperText: 'Макс: ${formatPrice(_maxCash)} сўм',
            border: const OutlineInputBorder(),
            errorText: _cashTooBig ? _cashTooBigMessage : null,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isWithdrawal ? Colors.orange.shade50 : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isWithdrawal
                  ? Colors.orange.shade300
                  : AppColors.primary.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 20,
                    color: isWithdrawal
                        ? Colors.orange.shade800
                        : AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isWithdrawal
                          ? '💼 Кошелёкдан ечилади: '
                              '${formatPrice(_cashGiven - widget.totalValue)} сўм'
                          : '💼 Кошелёкка қўшилади: '
                              '${formatPrice(_walletDelta)} сўм',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isWithdrawal
                            ? Colors.orange.shade900
                            : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  '💼 Янги баланс: ${formatPrice(_newBalance)} сўм',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Бекор'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: (_busy || _cashTooBig) ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
                    : const Text(
                        'Тасдиқлаш',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _confirmationView() {
    final r = _result!;
    final v = (r['V'] as num?)?.toInt() ?? widget.totalValue;
    final cashGiven = (r['cashGiven'] as num?)?.toInt() ?? 0;
    final walletCredit = (r['walletCredit'] as num?)?.toInt() ?? 0;
    final withdrawnFromBalance =
        (r['withdrawnFromBalance'] as num?)?.toInt() ?? 0;
    final newBalance = (r['newBalance'] as num?)?.toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '✅ Маҳсулот қабул қилинди',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'Жами: ${formatPrice(v)} сўм',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        if (cashGiven > 0) ...[
          const SizedBox(height: 6),
          Text('💵 Нақд берилди: ${formatPrice(cashGiven)} сўм'),
        ],
        if (walletCredit > 0) ...[
          const SizedBox(height: 6),
          Text('💼 Кошелёкка қўшилди: ${formatPrice(walletCredit)} сўм'),
        ],
        if (withdrawnFromBalance > 0) ...[
          const SizedBox(height: 6),
          Text(
            '💼 Кошелёкдан нақд олинди: ${formatPrice(withdrawnFromBalance)} сўм',
            style: TextStyle(
              color: Colors.orange.shade900,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.account_balance_wallet,
                color: AppColors.primary,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  newBalance != null
                      ? '💼 Мижоз янги баланси:\n${formatPrice(newBalance)} сўм'
                      : '💼 Аввал якунланган вазифа',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryDark,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text(
            'Якунлаш',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
