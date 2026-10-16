import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/collection_task.dart';
import '../../../models/customer_confirm.dart';
import '../../../repositories/collection_tasks_repository.dart';
import '../../../services/collection_service.dart';
import '../../../services/order_payment_service.dart';
import '../../customer_confirm/widgets/courier_awaiting_notice.dart';

typedef CollectionFinalizeFn = Future<Map<String, dynamic>> Function({
  required String courierPhone,
  required String taskId,
  required List<Map<String, dynamic>> items,
  required int cashGiven,
});

/// Курьер — битта қабул вазифаси: маҳсулотларни текшириш ва миқдорни аниқлаш.
class CourierCollectionDetailScreen extends StatefulWidget {
  const CourierCollectionDetailScreen({
    super.key,
    required this.task,
    this.repository,
    this.pollInterval = const Duration(seconds: 8),
    this.finalize,
  });

  final CollectionTask task;

  /// Якунлаш callable'и — синовда алмаштирилади; одатда
  /// [CollectionService.finalizeCollection].
  final CollectionFinalizeFn? finalize;

  /// Мижоз тасдиғи кутилганда вазифа ҳолатини текшириш учун. Берилмаса —
  /// Provider'даги [CollectionTasksRepository]; у ҳам йўқ бўлса — текширув ўчиқ.
  final CollectionTasksRepository? repository;
  final Duration pollInterval;

  @override
  State<CourierCollectionDetailScreen> createState() =>
      _CourierCollectionDetailScreenState();
}

class _CourierCollectionDetailScreenState
    extends State<CourierCollectionDetailScreen> {
  late final List<TextEditingController> _qtyCtrls;
  bool _hasArrived = false;
  bool _markingArrived = false;

  /// Мижоз тасдиғи (D2/D7): `courierFinalizeCollection` `awaitingCustomer: true`
  /// қайтарди — мижоз курьер киритган миқдор/суммани тасдиқламагунча пул
  /// ўтмайди. Миқдорлар қулфланади, тугма ўчади, вазифа ҳолати текшириб турилади.
  bool _awaitingCustomer = false;
  Timer? _pollTimer;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _hasArrived = widget.task.hasArrived;
    _qtyCtrls = [
      for (final item in widget.task.items)
        TextEditingController(text: _qtyText(item.qty)),
    ];
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    for (final c in _qtyCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  CollectionTasksRepository? _repo() {
    if (widget.repository != null) return widget.repository;
    try {
      return context.read<CollectionTasksRepository>();
    } catch (_) {
      return null;
    }
  }

  void _onAwaitingCustomer() {
    if (!mounted || _awaitingCustomer) return;
    setState(() => _awaitingCustomer = true);
    _pollTimer ??= Timer.periodic(widget.pollInterval, (_) => _checkTask());
  }

  /// Вазифа фаол рўйхатдан чиқди (мижоз тасдиқлади → `completed`, ёки бекор) →
  /// кутиш тугади, рўйхатга қайтамиз. Хато бўлса индамай кейинги уринишни кутамиз.
  Future<void> _checkTask() async {
    if (_polling || !mounted) return;
    final repo = _repo();
    if (repo == null) return;
    _polling = true;
    try {
      final t = await repo.getById(widget.task.id);
      if (!mounted) return;
      if (t != null && t.isActive) return;
      // Ҳисоб-китоб варағи ҳали очиқ бўлса, `pop` уни ёпарди — кейинги уринишда.
      if (ModalRoute.of(context)?.isCurrent != true) return;
      _pollTimer?.cancel();
      _pollTimer = null;
      Navigator.of(context).pop();
    } catch (_) {
      // Тармоқ узилди — тугма «Янгилаш» орқали қўлда ҳам текширилади.
    } finally {
      _polling = false;
    }
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

  Future<void> _markArrived() async {
    if (_hasArrived || _markingArrived) return;
    setState(() => _markingArrived = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final courierPhone = prefs.getString('user_phone') ?? '';
      await CollectionService.markCollectionArrived(
        courierPhone: courierPhone,
        taskId: widget.task.id,
      );
      if (!mounted) return;
      setState(() {
        _hasArrived = true;
        _markingArrived = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _markingArrived = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
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
        onAwaitingCustomer: _onAwaitingCustomer,
        finalize: widget.finalize,
      ),
    );
    if (done == true && mounted) {
      // Вазифа якунланди — рўйхатга қайтамиз (фаол рўйхатдан чиқади).
      Navigator.of(context).pop();
      return;
    }
    // Мижоз тасдиғи кутилмоқда: варақ ёпилди, вазифа ҳали фаол — ҳолатни бир
    // марта текширамиз (мижоз улгурган бўлиши мумкин); кейин — таймер.
    if (_awaitingCustomer) _checkTask();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: const Text('📦 Қабул вазифаси'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
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
                  size: 20, color: AppColors.primaryText),
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
                  foregroundColor: AppColors.primaryText,
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
                '${formatMoney(item.unitPrice)} / ${item.unit}',
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
                  // Мижоз кўриб чиқаётганда рақамлар ўзгармайди.
                  enabled: !_awaitingCustomer,
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
                    lineTotal > 0 ? '${formatMoney(lineTotal)}' : '—',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryText,
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
                  '${formatMoney(_grandTotal)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_awaitingCustomer) ...[
              const CourierAwaitingNotice(),
              const SizedBox(height: 8),
              // Кутишда амал ўчиқ; қўлда текшириш мумкин (тармоқ узилган бўлса).
              FilledButton(
                onPressed: null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  context.tr('customer_confirm_waiting'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              TextButton(
                onPressed: _checkTask,
                child: Text(context.tr('customer_confirm_refresh')),
              ),
            ] else if (!_hasArrived)
              FilledButton(
                onPressed: _markingArrived ? null : _markArrived,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _markingArrived
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : Text(
                        context.tr('courier_arrived_btn'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              )
            else
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
    required this.onAwaitingCustomer,
    this.finalize,
  });

  final CollectionFinalizeFn? finalize;

  final String taskId;
  final String customerPhone;
  final int totalValue;
  final List<Map<String, dynamic>> items;

  /// Сервер `awaitingCustomer: true` қайтарганда чақирилади (варақ ёпилишидан
  /// мустақил — фойдаланувчи варақни суриб ёпиб қўйса ҳам ҳолат йўқолмасин).
  final VoidCallback onAwaitingCustomer;

  @override
  State<_SettlementSheet> createState() => _SettlementSheetState();
}

class _SettlementSheetState extends State<_SettlementSheet> {
  final _cashCtrl = TextEditingController(text: '0');
  bool _busy = false;
  Map<String, dynamic>? _result;

  /// Жавобда `awaitingCustomer: true` — пул ҳали ўтмаган, «қабул қилинди»
  /// кўрсатилмайди (мижоз тасдиқлайди).
  bool _awaiting = false;

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
            'Мижозга товар қийматидан ${formatMoney(withdrawal)} ортиқ '
            'нақд беряпсиз. Бу сумма унинг кошелёгидан ечилади.\n'
            'Янги баланс: ${formatMoney(_newBalance)}. Тасдиқлайсизми?',
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
      final result = await (widget.finalize ?? CollectionService.finalizeCollection)(
        courierPhone: courierPhone,
        taskId: widget.taskId,
        items: widget.items,
        cashGiven: _cashGiven,
      );
      // Эски сервер `awaitingCustomer` бермайди → аввалги якунлаш кўриниши.
      final awaiting = CourierActionResult.fromResponse(result).awaitingCustomer;
      if (awaiting) widget.onAwaitingCustomer();
      if (!mounted) return;
      setState(() {
        _result = result;
        _awaiting = awaiting;
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
        child: _result == null
            ? _formView()
            : _awaiting
                ? _awaitingView()
                : _confirmationView(),
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
          'Ҳисоб-китоб · ${formatMoney(widget.totalValue)}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Жами қиймат: ${formatMoney(widget.totalValue)}',
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
                '💼 Мижоз кошелёги: ${formatMoney(_customerBalance)}'
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
            helperText: 'Макс: ${formatMoney(_maxCash)}',
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
                        : AppColors.primaryText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isWithdrawal
                          ? '💼 Кошелёкдан ечилади: '
                              '${formatMoney(_cashGiven - widget.totalValue)}'
                          : '💼 Кошелёкка қўшилади: '
                              '${formatMoney(_walletDelta)}',
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
                  '💼 Янги баланс: ${formatMoney(_newBalance)}',
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
                          color: AppColors.onPrimary,
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

  /// Мижоз тасдиғи кутилмоқда: муваффақият ҳам, хато ҳам эмас. Курьер киритган
  /// сумма кўрсатилади; пул ва омбор ҳаракати мижоз тасдиқлагач серверда.
  Widget _awaitingView() {
    final r = _result!;
    final v = (r['V'] as num?)?.toInt() ?? widget.totalValue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const CourierAwaitingNotice(),
        const SizedBox(height: 12),
        Text(
          context
              .tr('customer_confirm_details_amount')
              .replaceAll('{amount}', formatPrice(v)),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.pop(context, false),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryDark,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(
            context.tr('ok'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
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
          'Жами: ${formatMoney(v)}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        if (cashGiven > 0) ...[
          const SizedBox(height: 6),
          Text('💵 Нақд берилди: ${formatMoney(cashGiven)}'),
        ],
        if (walletCredit > 0) ...[
          const SizedBox(height: 6),
          Text('💼 Кошелёкка қўшилди: ${formatMoney(walletCredit)}'),
        ],
        if (withdrawnFromBalance > 0) ...[
          const SizedBox(height: 6),
          Text(
            '💼 Кошелёкдан нақд олинди: ${formatMoney(withdrawnFromBalance)}',
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
                color: AppColors.primaryText,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  newBalance != null
                      ? '💼 Мижоз янги баланси:\n${formatMoney(newBalance)}'
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
