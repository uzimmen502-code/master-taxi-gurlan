// КУРЬЕР ТОИФАЛАРИ — админ (эга қарори 2026-10-31).
//
// «Туман» дарҳол ишлайди; «Вилоят» ва «Республика» — машина + ҳужжат,
// админ тасдиқлайди. Режим «Авто/Мануал» — `settings/courier.scopeApprovalMode`
// (стандарт Мануал). Ҳамма амал СЕРВЕРДА (us-central1, `functions/courier_scopes.js`):
//   • `adminSetCourierScopeApprovalMode` — режим + admin_audit;
//   • `adminListCourierScopeRequests` — сўровлар + машина маълумоти;
//   • `adminDecideCourierScope` — тасдиқ / рад (сабаб шарт) + capability_audit, admin_audit.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

const _scopeLabels = {'region': 'Вилоят', 'republic': 'Республика'};

HttpsCallable _callable(String name) => FirebaseFunctions.instance.httpsCallable(name);

Future<String?> _askText(BuildContext context, String title, String body, {bool required = false}) async {
  final ctrl = TextEditingController();
  final out = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (body.isNotEmpty) Text(body),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLength: 200,
              onChanged: (_) => setLocal(() {}),
              decoration: InputDecoration(
                hintText: required ? 'Сабаб (мажбурий)' : 'Audit учун қисқа сабаб',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Бекор')),
          FilledButton(
            onPressed: required && ctrl.text.trim().isEmpty ? null : () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Тасдиқлаш'),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
  return out;
}

void _snack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: error ? Colors.red.shade700 : null,
  ));
}

/// «Вилоят/Республика тасдиқлаш режими» — иккинчи Авто/Мануал тугмаси.
class CourierScopeModeCard extends StatefulWidget {
  const CourierScopeModeCard({super.key});

  @override
  State<CourierScopeModeCard> createState() => _CourierScopeModeCardState();
}

class _CourierScopeModeCardState extends State<CourierScopeModeCard> {
  bool _saving = false;

  Future<void> _set(String mode) async {
    final toAuto = mode == 'auto';
    final reason = await _askText(
      context,
      toAuto ? 'Вилоят/Республика: Авто' : 'Вилоят/Республика: Мануал',
      toAuto
          ? 'Машина ва ҳужжат маълумотини тўлиқ киритган курьер вилоят ва республика '
              'бўйича ДАРҲОЛ иш ола бошлайди. Кутаётган сўровлар ўзгармайди — уларни '
              'рўйхатдан тасдиқланг.'
          : 'Янги сўровлар «Вилоят/Республика сўровлари» рўйхатига тушади. Курьер сиз '
              'тасдиқламагунча вилоят ва республика буюртмаларини ола олмайди.',
    );
    if (reason == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await _callable('adminSetCourierScopeApprovalMode').call<Object?>({'mode': mode, 'reason': reason});
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        _snack(context,
            e.code == 'permission-denied' ? 'Бу амал учун рухсат йўқ' : 'Режимни ўзгартириб бўлмади. Қайта уриниб кўринг.',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('settings').doc('courier').snapshots(),
      builder: (context, snap) {
        // Сервер билан бир хил: фақат аниқ 'auto' — авто, қолгани мануал.
        final mode = snap.data?.data()?['scopeApprovalMode'] == 'auto' ? 'auto' : 'manual';
        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Вилоят ва республика курьерини тасдиқлаш режими',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'manual', label: Text('Мануал'), icon: Icon(Icons.how_to_reg)),
                    ButtonSegment(value: 'auto', label: Text('Авто'), icon: Icon(Icons.bolt)),
                  ],
                  selected: {mode},
                  onSelectionChanged: !snap.hasData || _saving
                      ? null
                      : (s) {
                          if (s.first != mode) _set(s.first);
                        },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Вилоят/республика сўровлари — кутаётганлар (ёки бошқа ҳолат).
class CourierScopeRequestsList extends StatefulWidget {
  const CourierScopeRequestsList({super.key, required this.status});

  /// `pending` | `approved` | `rejected`.
  final String status;

  @override
  State<CourierScopeRequestsList> createState() => _CourierScopeRequestsListState();
}

class _CourierScopeRequestsListState extends State<CourierScopeRequestsList> {
  Future<List<Map>>? _future;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant CourierScopeRequestsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) _reload();
  }

  void _reload() {
    setState(() {
      _future = _callable('adminListCourierScopeRequests')
          .call<Object?>({'status': widget.status}).then((r) {
        final d = r.data is Map ? r.data as Map : const {};
        return (d['items'] is List ? d['items'] as List : const []).whereType<Map>().toList();
      });
    });
  }

  Future<void> _decide(String accountId, String scope, String decision) async {
    final approve = decision == 'approve';
    final reason = await _askText(
      context,
      '${_scopeLabels[scope]}: ${approve ? 'тасдиқлаш' : 'рад этиш'}',
      approve ? 'Машина ва ҳужжат маълумотини текширганингизга ишонч ҳосил қилинг.' : '',
      required: !approve,
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = '$accountId/$scope');
    try {
      await _callable('adminDecideCourierScope').call<Object?>({
        'accountId': accountId,
        'scope': scope,
        'decision': decision,
        'reason': reason,
      });
      if (mounted) _snack(context, approve ? '✅ Тасдиқланди' : 'Рад этилди');
      _reload();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        _snack(context,
            e.code == 'permission-denied' ? 'Бу амал учун рухсат йўқ' : 'Қарорни сақлаб бўлмади. Қайта уриниб кўринг.',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Рўйхатни юклаб бўлмади. Қайта уриниб кўринг.'),
              TextButton.icon(onPressed: _reload, icon: const Icon(Icons.refresh), label: const Text('Янгилаш')),
            ]),
          );
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        if (items.isEmpty) {
          return Center(
            child: Text('Сўровлар йўқ', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
          );
        }
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final it = items[i];
            final accountId = (it['accountId'] ?? '').toString();
            final phone = (it['phone'] ?? '').toString();
            final v = it['vehicle'] is Map ? it['vehicle'] as Map : const {};
            final reqs = it['requests'] is Map ? it['requests'] as Map : const {};
            return Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(phone.isEmpty ? 'Курьер' : '+$phone',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      'Машина: ${v['vehicleType'] == 'car' ? 'бор' : 'йўқ'}'
                      '  ·  Рақам: ${v['carPlate'] ?? '—'}'
                      '  ·  Модель: ${v['carModel'] ?? '—'}'
                      '  ·  Гувоҳнома: ${v['driverLicenseNo'] ?? '—'}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    for (final e in reqs.entries)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Chip(label: Text(_scopeLabels[e.key] ?? e.key.toString())),
                            if ((e.value as Map)['reason'].toString().isNotEmpty)
                              Text('Сабаб: ${(e.value as Map)['reason']}',
                                  style: const TextStyle(fontSize: 12)),
                            if (widget.status != 'approved')
                              OutlinedButton(
                                onPressed: _busy != null
                                    ? null
                                    : () => _decide(accountId, e.key.toString(), 'approve'),
                                style: OutlinedButton.styleFrom(foregroundColor: Colors.green.shade700),
                                child: const Text('Тасдиқлаш'),
                              ),
                            if (widget.status != 'rejected')
                              OutlinedButton(
                                onPressed: _busy != null
                                    ? null
                                    : () => _decide(accountId, e.key.toString(), 'reject'),
                                style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                                child: const Text('Рад этиш'),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Рўйхат фильтрлари (бош экран фильтрига қўшилади).
const courierScopeFilters = <String, String>{
  'scope:pending': 'Вилоят/Республика — сўровлар',
  'scope:approved': 'Вилоят/Республика — тасдиқланган',
  'scope:rejected': 'Вилоят/Республика — рад этилган',
};
