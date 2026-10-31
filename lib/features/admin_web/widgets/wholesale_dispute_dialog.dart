// Улгуржи «етказилганда карта орқали» — ТЎЛОВ НИЗОСИ (3b, параллел агент):
// харидор чек юборган, сотувчи вақтида тасдиқламаган → `payment_dispute`.
// Админ чек расмини кўради ва қарор қилади:
//   adminResolveWholesaleCardDispute({orderId, decision: 'confirm'|'reject', reason})
// (demand, europe-west1). Сабаб МАЖБУРИЙ (audit, 41-банд); пул/ҳолат — СЕРВЕРДА.

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../services/admin_callable.dart';
import '../services/admin_wholesale_orders_service.dart';
import '../utils/wholesale_orders_admin.dart';

/// Чек расми URL'и (Storage йўли → download URL). Тестда алмаштирилади.
typedef ReceiptUrlLoader = Future<String> Function(String storagePath);

Future<String> defaultReceiptUrl(String path) => FirebaseStorage.instance.ref(path).getDownloadURL();

/// Муваффақиятда сервер жавоби, бекор қилинса `null`.
Future<Map<String, dynamic>?> showWholesaleDisputeDialog(
  BuildContext context, {
  required AdminWholesaleOrdersService svc,
  required WholesaleOrderAdminView order,
  ReceiptUrlLoader? receiptUrl,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => WholesaleDisputeDialog(svc: svc, order: order, receiptUrl: receiptUrl ?? defaultReceiptUrl),
  );
}

class WholesaleDisputeDialog extends StatefulWidget {
  const WholesaleDisputeDialog({super.key, required this.svc, required this.order, required this.receiptUrl});

  final AdminWholesaleOrdersService svc;
  final WholesaleOrderAdminView order;
  final ReceiptUrlLoader receiptUrl;

  @override
  State<WholesaleDisputeDialog> createState() => _WholesaleDisputeDialogState();
}

class _WholesaleDisputeDialogState extends State<WholesaleDisputeDialog> {
  static const _minReason = 3;
  final _reason = TextEditingController();
  Future<String>? _url;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final path = widget.order.receiptPath;
    if (path.isNotEmpty) _url = widget.receiptUrl(path);
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _reasonOk => _reason.text.trim().length >= _minReason;

  Future<void> _decide(String decision) async {
    if (!_reasonOk) {
      setState(() => _error = 'Сабабни ёзинг (камида $_minReason белги, audit)');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.svc.resolveCardDispute(
        orderId: widget.order.id,
        decision: decision,
        reason: _reason.text.trim(),
      );
      if (mounted) Navigator.pop(context, res);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is AdminCallableException && e.code == 'not-found' && e.reason.isEmpty
            ? 'Callable топилмади — карта занжири server\'и deploy қилинмаган бўлиши мумкин'
            : adminErrorText(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _receipt() {
    final path = widget.order.receiptPath;
    if (path.isEmpty) {
      return Text('Чек юборилмаган (cardPayment.receiptPath йўқ)', style: TextStyle(color: Colors.red.shade700));
    }
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError || !snap.hasData) {
          return Text(
            'Чек расми очилмади (Storage рухсати?): $path',
            style: TextStyle(fontSize: 12, color: Colors.red.shade700),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            snap.data!,
            height: 320,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Text('Расм юкланмади: $path', style: TextStyle(color: Colors.red.shade700)),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    String money(int? v) => v == null ? '—' : '${wholesaleMoney(v)} сўм';
    final submitted = wholesaleTimeOf(o.cardPayment?['submittedAt']);
    return AlertDialog(
      title: Text('Тўлов низоси — ${o.productTitle.isEmpty ? o.id : o.productTitle}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Буюртма: ${o.id}\nТовар: ${money(o.goodsTotal)} · етказиш: ${money(o.deliveryFee)} · жами: ${money(o.total)}\n'
                'Харидор: ${o.buyerId} · сотувчи: ${o.sellerId}\n'
                'Карта тўлови: ${o.cardStatus.isEmpty ? '—' : o.cardStatus}'
                '${submitted != null ? ' · чек: ${_fmt(submitted)}' : ''}',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              _receipt(),
              const SizedBox(height: 12),
              Text(
                '«Тасдиқлаш» — пул сотувчига тушган (етказиш давом этади). «Рад этиш» — тўлов йўқ '
                '(буюртма рад этилганга ўтади, товар сотувчига қайтарилади). Аниқ оқибат — сервер.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('dispute-reason'),
                controller: _reason,
                enabled: !_busy,
                maxLength: 300,
                maxLines: 2,
                onChanged: (_) => setState(() => _error = null),
                decoration: const InputDecoration(
                  labelText: 'Сабаб (мажбурий, audit)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null)
                Text(_error!, key: const ValueKey('dispute-error'), style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Бекор')),
        OutlinedButton(
          onPressed: _busy || !_reasonOk ? null : () => _decide('reject'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
          child: const Text('Рад этиш'),
        ),
        FilledButton(
          onPressed: _busy || !_reasonOk ? null : () => _decide('confirm'),
          child: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Тўловни тасдиқлаш'),
        ),
      ],
    );
  }

  static String _fmt(DateTime d) {
    final l = d.toLocal();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
  }
}
