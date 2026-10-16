// Админ: «Йўқолди» ва «Тўлов ёзиш» диалоглари (D1).
//
// Диалог чақирувни ЎЗИ бажаради: `opId` диалог очилганда бир марта
// яратилади ва шу диалогдаги қайта уринишларда ўша ишлатилади (хато/
// интернет узилганда такрор босиш икки марта ёзмайди). Диалог ёпилиб қайта
// очилса — янги амал, янги `opId`.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/admin_callable.dart';
import '../services/admin_logistics_service.dart';
import '../utils/loss_incident.dart';

/// Муваффақиятда сервер жавоби (Map), бекорда `null`.
Future<Map<String, dynamic>?> showMarkShipmentLostDialog(
  BuildContext context, {
  required AdminLogisticsService service,
  required String shipmentId,
  required String label,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => MarkShipmentLostDialog(service: service, shipmentId: shipmentId, label: label),
  );
}

Future<Map<String, dynamic>?> showRecordLostPaymentDialog(
  BuildContext context, {
  required AdminLogisticsService service,
  required LossIncident incident,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => RecordLostPaymentDialog(service: service, incident: incident),
  );
}

class MarkShipmentLostDialog extends StatefulWidget {
  const MarkShipmentLostDialog({
    super.key,
    required this.service,
    required this.shipmentId,
    required this.label,
  });

  final AdminLogisticsService service;
  final String shipmentId;
  final String label;

  @override
  State<MarkShipmentLostDialog> createState() => _MarkShipmentLostDialogState();
}

class _MarkShipmentLostDialogState extends State<MarkShipmentLostDialog> {
  final _reason = TextEditingController();
  final _note = TextEditingController();
  final String _opId = newAdminOpId();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason.text.trim();
    if (reason.length < 3) {
      setState(() => _error = 'Йўқолиш сабабини ёзинг (камида 3 белги)');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.service.markShipmentLost(
        shipmentId: widget.shipmentId,
        reason: reason,
        note: _note.text,
        opId: _opId,
      );
      if (mounted) Navigator.pop(context, res);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = adminErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('«Йўқолди» — ${widget.label}'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Посилка «йўқолган» деб белгиланади. Бу амални қайтариб бўлмайди: '
              'пул ҳисоб-китоби сервер томонидан автоматик бажарилади ва тарихга ёзилади.',
              style: TextStyle(fontSize: 12.5, color: Colors.red.shade800),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reason,
              enabled: !_busy,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Сабаб (мажбурий)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _note,
              enabled: !_busy,
              maxLength: 1000,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Изоҳ (ихтиёрий)', border: OutlineInputBorder()),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_error!, style: TextStyle(fontSize: 12.5, color: Colors.red.shade700)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Бекор')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          child: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Йўқолди деб белгилаш'),
        ),
      ],
    );
  }
}

class RecordLostPaymentDialog extends StatefulWidget {
  const RecordLostPaymentDialog({super.key, required this.service, required this.incident});

  final AdminLogisticsService service;
  final LossIncident incident;

  @override
  State<RecordLostPaymentDialog> createState() => _RecordLostPaymentDialogState();
}

class _RecordLostPaymentDialogState extends State<RecordLostPaymentDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final String _opId = newAdminOpId();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = parsePositiveSom(_amount.text);
    if (amount == null) {
      setState(() => _error = 'Суммани бутун мусбат сўмда киритинг');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.service.recordLostParcelPayment(
        shipmentId: widget.incident.shipmentId,
        amount: amount,
        note: _note.text,
        opId: _opId,
      );
      if (mounted) Navigator.pop(context, res);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = adminErrorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inc = widget.incident;
    final amount = parsePositiveSom(_amount.text);
    return AlertDialog(
      title: Text('Тўлов ёзиш — ${inc.trackingNumber.isEmpty ? inc.shipmentId : inc.trackingNumber}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Товар қиймати: ${lossMoneyText(inc.goodsValue)} сўм · '
              'қайтарилган: ${lossMoneyText(inc.refundedNow)} · '
              'қолган қарз: ${lossMoneyText(inc.outstanding)} сўм',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Тўланган сумма, сўм', border: OutlineInputBorder()),
            ),
            if (amount != null && inc.outstanding != null && amount > inc.outstanding!)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Эътибор: сумма қолган қарздан катта (${lossMoneyText(inc.outstanding)}). '
                  'Қабул қилиш-қилмасликни сервер ҳал қилади.',
                  style: TextStyle(fontSize: 11.5, color: Colors.orange.shade900),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              enabled: !_busy,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Изоҳ (ихтиёрий)', border: OutlineInputBorder()),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_error!, style: TextStyle(fontSize: 12.5, color: Colors.red.shade700)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Бекор')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Ёзиш'),
        ),
      ],
    );
  }
}
