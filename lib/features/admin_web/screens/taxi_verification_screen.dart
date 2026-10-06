// ТАКСИ ВЕРИФИКАЦИЯСИ — админ (D-TAXI-4, R-4).
//
// `provider_capabilities.status.taxi` бўйича рўйхат: `verification_required`
// (4 ой тугаган, админ текшируви кутаётганлар), `starter`, `verified`,
// `suspended`. Амаллар СЕРВЕРДА (`adminSetCapabilityStatus`, europe-west1):
// ўтиш `canTransition(..., 'admin')` билан текширилади, ҳар амал
// `capability_audit`га тушади (41-қоида). Экран фақат чақиради ва
// кўрсатади — ҳуқуқ бермайди.
//
// Ҳайдовчи профили (исм, машина) — `drivers/{primaryUid}`, статистика —
// `provider_stats/{primaryUid}` (бор бўлса).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../demand_offer/data/demand_repository.dart' show kDemandCoreRegion;

class TaxiVerificationScreen extends StatefulWidget {
  const TaxiVerificationScreen({super.key});

  @override
  State<TaxiVerificationScreen> createState() => _TaxiVerificationScreenState();
}

class _TaxiVerificationScreenState extends State<TaxiVerificationScreen> {
  static const _filters = <String, String>{
    'verification_required': 'Текширув кутяпти',
    'starter': 'Starter (синов)',
    'verified': 'Тасдиқланган',
    'suspended': 'Тўхтатилган',
  };
  String _filter = 'verification_required';
  String? _busyAccountId;

  Future<void> _setStatus(String accountId, String status) async {
    final reason = await _askReason(status);
    if (reason == null || !mounted) return;
    setState(() => _busyAccountId = accountId);
    try {
      await FirebaseFunctions.instanceFor(region: kDemandCoreRegion)
          .httpsCallable('adminSetCapabilityStatus')
          .call<Object?>({
        'accountId': accountId,
        'service': 'taxi',
        'status': status,
        'reason': reason,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Статус ўзгартирилди: $status')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text('Хато: ${e.message ?? e.code}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyAccountId = null);
    }
  }

  Future<String?> _askReason(String status) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Сабаб — $status'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Audit учун қисқа сабаб'),
          maxLength: 200,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Бекор')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Тасдиқлаш'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Text('Такси верификацияси',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              DropdownButton<String>(
                value: _filter,
                items: _filters.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _filter = v ?? _filter),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('provider_capabilities')
                .where('status.taxi', isEqualTo: _filter)
                .limit(200)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('Хато: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return Center(
                  child: Text('«${_filters[_filter]}» рўйхати бўш',
                      style: TextStyle(color: Colors.grey.shade600)),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _CapabilityCard(
                  accountId: docs[i].id,
                  data: docs[i].data(),
                  busy: _busyAccountId == docs[i].id,
                  onSetStatus: _setStatus,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({
    required this.accountId,
    required this.data,
    required this.busy,
    required this.onSetStatus,
  });

  final String accountId;
  final Map<String, dynamic> data;
  final bool busy;
  final Future<void> Function(String accountId, String status) onSetStatus;

  String _fmt(dynamic ts) {
    if (ts is! Timestamp) return '—';
    final d = ts.toDate();
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final identity = (data['identity'] as Map?) ?? const {};
    final phone = (identity['primaryUid'] ?? '').toString();
    final status = ((data['status'] as Map?)?['taxi'] ?? '').toString();
    final window = ((data['window'] as Map?)?['taxi'] as Map?) ?? const {};
    final taxi = (data['taxi'] as Map?) ?? const {};
    final types = (taxi['taxiTypes'] as List?)?.join(', ') ?? '—';
    final debt = ((data['debt'] as Map?)?['taxi'] as num?)?.toInt() ?? 0;

    // Admin uchun ruxsat etilgan o'tishlar (server ham tekshiradi).
    final actions = <(String, String, Color)>[
      if (status != 'verified') ('verified', 'Тасдиқлаш', Colors.green.shade700),
      if (status != 'suspended') ('suspended', 'Тўхтатиш', Colors.red.shade700),
      if (status == 'verified' || status == 'suspended')
        ('verification_required', 'Қайта текширув', Colors.orange.shade800),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: FirebaseFirestore.instance.collection('drivers').doc(phone).get(),
                    builder: (_, s) {
                      final p = s.data?.data() ?? const {};
                      return Text(
                        '${p['name'] ?? '—'}  ·  +$phone\n'
                        '${p['car'] ?? ''} ${p['plate'] ?? ''}'.trim(),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      );
                    },
                  ),
                ),
                Chip(label: Text(status)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Турлар: $types   ·   Бошланган: ${_fmt(window['startedAt'])}   ·   '
              'Текширув муддати: ${_fmt(window['verificationDueAt'])}'
              '${window['billingGraceUntil'] != null ? '   ·   Billing grace: ${_fmt(window['billingGraceUntil'])}' : ''}'
              '${debt > 0 ? '   ·   ҚАРЗ: $debt сўм' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: actions
                  .map((a) => OutlinedButton(
                        onPressed: busy ? null : () => onSetStatus(accountId, a.$1),
                        style: OutlinedButton.styleFrom(foregroundColor: a.$3),
                        child: Text(a.$2),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}
