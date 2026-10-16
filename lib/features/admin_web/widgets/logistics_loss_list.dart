// Админ: «Йўқолган посилкалар» рўйхати (D1) — `adminListLossIncidents`
// (default, us-central1). Пул ҳисоби серверда тайёр келади; экран кўрсатади
// ва «Тўлов ёзиш» диалогини очади (`adminRecordLostParcelPayment`).

import 'package:flutter/material.dart';

import '../services/admin_callable.dart';
import '../services/admin_logistics_service.dart';
import '../utils/loss_incident.dart';
import 'logistics_loss_dialogs.dart';

class LogisticsLossList extends StatefulWidget {
  const LogisticsLossList({super.key, required this.service});

  final AdminLogisticsService service;

  @override
  State<LogisticsLossList> createState() => _LogisticsLossListState();
}

class _LogisticsLossListState extends State<LogisticsLossList> {
  List<LossIncident>? _items;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.service.listLossIncidents();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = adminErrorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _recordPayment(LossIncident inc) async {
    final res = await showRecordLostPaymentDialog(context, service: widget.service, incident: inc);
    if (res == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Тўлов ёзилди')));
    await _load();
  }

  static String _date(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  Color _statusColor(String s) => switch (s) {
        'declared' => Colors.orange.shade800,
        'settled' => Colors.blue.shade700,
        'repaid' => Colors.green.shade700,
        _ => Colors.grey.shade700,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            children: [
              Text('Йўқолган посилкалар${_items != null ? ' (${_items!.length})' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Янгилаш'),
              ),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading && _items == null) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Хато: $_error', style: TextStyle(color: Colors.red.shade700)),
            TextButton(onPressed: _load, child: const Text('Қайта')),
          ],
        ),
      );
    }
    final items = _items ?? const <LossIncident>[];
    if (items.isEmpty) {
      return Center(child: Text('Йўқолган посилка йўқ', style: TextStyle(color: Colors.grey.shade600)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) => _tile(items[i]),
    );
  }

  Widget _tile(LossIncident inc) {
    final color = _statusColor(inc.status);
    return Card(
      child: ListTile(
        isThreeLine: true,
        title: Row(
          children: [
            Flexible(child: Text(inc.trackingNumber.isEmpty ? inc.shipmentId : inc.trackingNumber)),
            const SizedBox(width: 8),
            Chip(
              label: Text(lossStatusLabel(inc.status), style: TextStyle(fontSize: 11, color: color)),
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: color.withValues(alpha: 0.5)),
            ),
          ],
        ),
        subtitle: Text(
          'товар қиймати: ${lossMoneyText(inc.goodsValue)} сўм · '
          'қайтарилган: ${lossMoneyText(inc.refundedNow)} · '
          'қолган қарз: ${lossMoneyText(inc.outstanding)}'
          '${inc.paidTotal == null ? '' : ' · курьер тўлаган: ${lossMoneyText(inc.paidTotal)}'}\n'
          '${inc.courierPhoneMasked.isEmpty ? '' : 'курьер: ${inc.courierPhoneMasked} · '}'
          '${_date(inc.declaredAt)}'
          '${inc.reason.isEmpty ? '' : ' · сабаб: ${inc.reason}'}',
        ),
        trailing: inc.canRecordPayment
            ? FilledButton.tonalIcon(
                onPressed: () => _recordPayment(inc),
                icon: const Icon(Icons.payments_outlined, size: 16),
                label: const Text('Тўлов ёзиш'),
              )
            : null,
      ),
    );
  }
}
