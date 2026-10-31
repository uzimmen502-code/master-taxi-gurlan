// Улгуржи — ЙЎҚОЛГАН ПОСИЛКА: масъул курьернинг етказиш пули қарзи (эга, 2026-10-31).
//
// Сервер (`functions/wholesale_orders.js` `settleLost`, feat/ulg-card 2fec8ce8) ҳамён буюртмаси
// йўқолганда етказиш пулини харидорга курьер ҳамёнидан қайтаради; етмаган қисми —
// `lost.deliveryFeeOutstanding` (курьер қарзи `debt.logistics`). Курьер қарзни ЎЗИ тўлаганда админ
// олинган суммани ёзади:
//   adminRecordWholesaleLostFeePayment({orderId, amount, opId, note})  — default codebase.
//
// Диалог чақирувни ЎЗИ бажаради. `opId` диалог очилганда бир марта яратилади ва шу диалогдаги
// ҳар қайта уринишда ўша юборилади (жавоб йўқолса/хато бўлса такрор босиш икки марта ёзмайди;
// сервер журнали бор бўлса — ўша сумма `idempotent`, бошқа сумма `op_id_reused`). Ёпилиб қайта
// очилса — янги амал, янги `opId` (`logistics_loss_dialogs.dart` билан бир хил қоида).
// Сумма/қарз чегараси, audit, history — СЕРВЕРДА (18, 21, 41, 44-банд); бу ерда фақат ақлли текширув.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/admin_callable.dart';
import '../services/admin_logistics_service.dart' show newAdminOpId;
import '../services/admin_wholesale_orders_service.dart';
import '../utils/loss_incident.dart' show parsePositiveSom;
import '../utils/wholesale_orders_admin.dart';

/// Изоҳ — мажбурий (audit, 41-банд). Сервер 300 белгигача сақлайди.
const int kLostFeeNoteMin = 3;
const int kLostFeeNoteMax = 300;

/// Сервер `details.reason` → админ матни. Номаълум — умумий `adminErrorText`.
String wholesaleLostFeeErrorText(Object error) {
  if (error is AdminCallableException) {
    final outstanding = adminInt(error.details?['outstanding']);
    final text = switch (error.reason) {
      'exceeds_outstanding' || 'amount_exceeds_outstanding' =>
        'Сумма қолган қарздан катта${outstanding != null ? ' (қолган: ${wholesaleMoney(outstanding)} сўм)' : ''}. '
            'Буюртмани янгилаб, суммани қайта киритинг',
      'nothing_outstanding' || 'no_debt' =>
        'Бу буюртма бўйича курьер қарзи қолмаган (аллақачон тўланган бўлиши мумкин)',
      'debt_mismatch' =>
        'Курьер ҳисобидаги қарз (debt.logistics) бу суммадан кам — маълумот мос эмас, тўлов ёзилмади. Техник текширув керак',
      'op_id_reused' =>
        'Бу амал аввал бошқа сумма билан ёзилган — тўлов аллақачон ёзилган бўлиши мумкин. Диалогни ёпиб, буюртмани янгиланг',
      'not_lost' => 'Буюртма «йўқолди» ҳолатида эмас',
      'fee_debt_not_recorded' => 'Курьер қарзи ёзилмаган (аномалия ёки курьер номаълум) — қўлда ҳал қилинади',
      'bad_amount' => 'Сумма мусбат бутун сўм бўлиши керак',
      'bad_op_id' => 'Амал идентификатори хато — диалогни ёпиб, қайта очинг',
      'order_required' || 'order_missing' => 'Буюртма топилмади',
      'roles_unavailable' => 'Сервер созланмаган (рухсат текшируви йўқ)',
      _ => null,
    };
    if (text != null) return text;
    if (error.code == 'not-found' && error.reason.isEmpty) {
      return 'Callable топилмади — server deploy қилинмаган бўлиши мумкин';
    }
  }
  return adminErrorText(error);
}

/// Буюртма тафсилотидаги «Йўқолган посилка» бўлими (фақат `status: lost`): етказиш пули ҳолати
/// read-only + «Курьер қарзини тўлади» тугмаси (фақат қолган қарз > 0 бўлса).
class WholesaleLostFeeSection extends StatelessWidget {
  const WholesaleLostFeeSection({super.key, required this.order, this.onRecordPayment});

  final WholesaleOrderAdminView order;
  final VoidCallback? onRecordPayment;

  @override
  Widget build(BuildContext context) {
    final o = order;
    if (o.status != 'lost') return const SizedBox.shrink();
    final l = o.lost ?? const <String, dynamic>{};
    String money(int? v) => v == null ? '—' : '${wholesaleMoney(v)} сўм';
    final muted = TextStyle(fontSize: 12.5, color: Colors.grey.shade700);
    Widget row(String k, String v, {Key? key, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 170, child: Text(k, style: muted)),
            Expanded(child: SelectableText(v, key: key, style: TextStyle(fontSize: 12.5, color: color))),
          ]),
        );
    final anomaly = o.lostFeeAnomaly;
    final review = l['review'] == true;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.orange.shade200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Йўқолган посилка — етказиш пули', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        if (review)
          Text(
            'Карта тўлови кўриб чиқилмоқда (lost_review) — пул ҳаракати йўқ, админ ҳал қилади.',
            style: TextStyle(fontSize: 12.5, color: Colors.orange.shade900),
          ),
        row('Товар пули қайтарилди', money(adminInt(l['refunded']))),
        row('Етказиш пули', money(adminInt(l['deliveryFee']))),
        row('Дарҳол қайтарилди', money(o.lostFeeRefunded), key: const ValueKey('lost-fee-refunded')),
        row('Курьер тўлади (ёзилган)', money(o.lostFeePaidTotal), key: const ValueKey('lost-fee-paid-total')),
        row(
          'Қолган курьер қарзи',
          money(o.lostFeeOutstanding),
          key: const ValueKey('lost-fee-outstanding'),
          color: o.hasLostFeeOutstanding ? Colors.red.shade700 : null,
        ),
        row('Масъул курьер (accountId)', o.lostCourierAccountId.isEmpty ? '—' : o.lostCourierAccountId,
            key: const ValueKey('lost-fee-courier')),
        if (anomaly.isNotEmpty)
          row('Аномалия', anomaly, key: const ValueKey('lost-fee-anomaly'), color: Colors.red.shade700),
        if (o.hasLostFeeOutstanding) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('lost-fee-pay'),
              onPressed: o.canRecordLostFeePayment ? onRecordPayment : null,
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: const Text('Курьер қарзини тўлади'),
            ),
          ),
          if (!o.canRecordLostFeePayment)
            Text(
              'Тўловни ёзиб бўлмайди: курьер қарзи серверда ёзилмаган (аномалия ёки курьер номаълум) — қўлда ҳал қилинади.',
              style: TextStyle(fontSize: 11.5, color: Colors.red.shade700),
            ),
        ],
      ]),
    );
  }
}

/// Муваффақиятда сервер жавоби, бекор қилинса `null`.
Future<Map<String, dynamic>?> showWholesaleLostFeePaymentDialog(
  BuildContext context, {
  required AdminWholesaleOrdersService svc,
  required WholesaleOrderAdminView order,
  String Function()? newOpId,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => WholesaleLostFeePaymentDialog(svc: svc, order: order, newOpId: newOpId),
  );
}

class WholesaleLostFeePaymentDialog extends StatefulWidget {
  const WholesaleLostFeePaymentDialog({super.key, required this.svc, required this.order, this.newOpId});

  final AdminWholesaleOrdersService svc;
  final WholesaleOrderAdminView order;

  /// Тестда алмаштирилади; йўқ — UUID v4 (`^[A-Za-z0-9_-]{6,64}$`).
  final String Function()? newOpId;

  @override
  State<WholesaleLostFeePaymentDialog> createState() => _WholesaleLostFeePaymentDialogState();
}

class _WholesaleLostFeePaymentDialogState extends State<WholesaleLostFeePaymentDialog> {
  late final TextEditingController _amount = TextEditingController(text: '$_outstanding');
  final _note = TextEditingController();
  late final String _opId;
  bool _busy = false;
  String? _error;

  int get _outstanding => widget.order.lostFeeOutstanding ?? 0;

  @override
  void initState() {
    super.initState();
    // Битта диалог = битта амал: opId ҳозир, бир марта (қайта уринишлар ўшани юборади).
    _opId = (widget.newOpId ?? newAdminOpId)();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String? get _amountError {
    final v = parsePositiveSom(_amount.text);
    if (v == null) return 'Суммани бутун мусбат сўмда киритинг';
    if (v > _outstanding) return 'Қолган қарздан катта бўлмасин (кўпи билан ${wholesaleMoney(_outstanding)} сўм)';
    return null;
  }

  bool get _noteOk => _note.text.trim().length >= kLostFeeNoteMin;
  bool get _canSubmit => !_busy && _amountError == null && _noteOk;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.svc.recordLostFeePayment(
        orderId: widget.order.id,
        amount: parsePositiveSom(_amount.text)!,
        opId: _opId,
        note: _note.text,
      );
      if (mounted) Navigator.pop(context, res);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = wholesaleLostFeeErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final amountError = _amountError;
    return AlertDialog(
      title: Text('Курьер қарзини тўлади — ${o.productTitle.isEmpty ? o.id : o.productTitle}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Буюртма: ${o.id}\n'
                'Масъул курьер: ${o.lostCourierAccountId.isEmpty ? '—' : o.lostCourierAccountId}\n'
                'Қолган қарз: ${wholesaleMoney(_outstanding)} сўм',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Курьер нақд/картада тўлаган суммани ёзинг. Пул харидор ҳамёнига тушади, курьер қарзи камаяди '
                '(сервер, audit). Қайтариб бўлмайди.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('lost-fee-amount'),
                controller: _amount,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  labelText: 'Тўланган сумма, сўм (1..${wholesaleMoney(_outstanding)})',
                  border: const OutlineInputBorder(),
                  errorText: amountError,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('lost-fee-note'),
                controller: _note,
                enabled: !_busy,
                maxLength: kLostFeeNoteMax,
                maxLines: 2,
                onChanged: (_) => setState(() => _error = null),
                decoration: const InputDecoration(
                  labelText: 'Изоҳ (мажбурий, камида 3 белги, audit)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _error!,
                    key: const ValueKey('lost-fee-error'),
                    style: TextStyle(fontSize: 12.5, color: Colors.red.shade700),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Бекор')),
        FilledButton(
          key: const ValueKey('lost-fee-confirm'),
          onPressed: _canSubmit ? _submit : null,
          child: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Тасдиқлаш'),
        ),
      ],
    );
  }
}
