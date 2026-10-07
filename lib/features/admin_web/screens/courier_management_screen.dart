// КУРЬЕРЛАР — админ (D-CLEAN-1, ега қарори 2026-10-07).
//
// Курьерлик ҳуқуқи энди фақат `provider_capabilities.status.courier`дан
// келади (`functions/index.js` → `resolveAuthorizedCourierUid`). Эски
// `couriers` ҳужжати ҲУҚУҚ БЕРМАЙДИ — шунинг учун бу экран унга ёзмайди.
//
// Амаллар СЕРВЕРДА (europe-west1):
//   • «Қўшиш» → `adminGrantCapability`: дарҳол `approved` (ега қарори),
//     фақат иловага кирган рақам ва фақат `not_registered`дан;
//   • «Тасдиқлаш» / «Тўхтатиш» → `adminSetCapabilityStatus`;
//   • «Тасдиқлаш режими» → `adminSetCourierApprovalMode` (D-15.3):
//     Мануал — ариза синовга тушади, админ шу ердан тасдиқлайди;
//     Авто — ариза дарҳол тасдиқланади. Режим `settings/courier`да.
// Ўтиш `canTransition(..., 'admin')` билан текширилади, ҳар амал
// `capability_audit`га тушади (41-қоида). Экран фақат чақиради.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../demand_offer/data/demand_repository.dart' show kDemandCoreRegion;

class CourierManagementScreen extends StatefulWidget {
  const CourierManagementScreen({super.key});
  @override
  State<CourierManagementScreen> createState() =>
      _CourierManagementScreenState();
}

class _CourierManagementScreenState extends State<CourierManagementScreen> {
  static const _filters = <String, String>{
    'trial': 'Тасдиқ кутяпти (синов)',
    'trial_expired': 'Тасдиқ кутяпти (охирги 5 кун)',
    'approved': 'Тасдиқланган',
    'suspended': 'Тўхтатилган',
  };

  final _db = FirebaseFirestore.instance;
  final _phoneCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _adding = false;
  bool _savingMode = false;
  String? _error;
  String _filter = 'trial';
  String? _busyAccountId;

  HttpsCallable _callable(String name) =>
      FirebaseFunctions.instanceFor(region: kDemandCoreRegion)
          .httpsCallable(name);

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  /// 25-қоида: фойдаланувчига тушунарли матн, ички код — фақат сабаб.
  String _grantErrorText(FirebaseFunctionsException e) {
    final details = e.details;
    final reason = details is Map ? details['reason']?.toString() : null;
    if (reason == 'user_not_registered') {
      return 'Бу рақам AVA иловасига ҳали кирмаган. Аввал иловага кирсин, '
          'кейин қайта қўшинг.';
    }
    if (reason == 'already_registered') {
      final st = details is Map ? details['status']?.toString() ?? '' : '';
      return 'Бу одам аллақачон рўйхатда (ҳолат: ${_filters[st] ?? st}). '
          'Пастдаги рўйхатдан амал қилинг.';
    }
    if (e.code == 'invalid-argument') return 'Телефон рақамни тўлиқ киритинг';
    if (e.code == 'permission-denied') return 'Бу амал учун рухсат йўқ';
    return 'Курьерни қўшиб бўлмади. Қайта уриниб кўринг.';
  }

  Future<void> _addCourier() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.replaceAll(RegExp(r'\D'), '').length < 9) {
      setState(() => _error = 'Телефон рақамни тўлиқ киритинг');
      return;
    }
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      final res = await _callable('adminGrantCapability').call<Object?>({
        'phone': phone,
        'service': 'courier',
        'reason': _reasonCtrl.text.trim(),
      });
      final data = res.data is Map ? res.data as Map : const {};
      _phoneCtrl.clear();
      _reasonCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['changed'] == false
                ? 'Бу курьер аллақачон тасдиқланган'
                : '✅ Курьер қўшилди ва тасдиқланди'),
            backgroundColor: AvaLight.ok,
          ),
        );
        setState(() => _filter = 'approved');
      }
    } on FirebaseFunctionsException catch (e) {
      setState(() => _error = _grantErrorText(e));
    } catch (_) {
      setState(() => _error = 'Курьерни қўшиб бўлмади. Қайта уриниб кўринг.');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// Тўхтатилган курьер қўлидаги рейсни ҳозир тугата олмайди (сервер
  /// `isWorking`ни текширади) — шунинг учун фаол рейс бўлса тўхтатилмайди.
  Future<bool> _hasActiveRoute(String courierId) async {
    final snap = await _db
        .collection('delivery_routes')
        .where('courierId', isEqualTo: courierId)
        .where('status', whereIn: ['ready', 'active'])
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  Future<void> _setStatus(
      String accountId, String primaryUid, String status) async {
    if (status == 'suspended' && await _hasActiveRoute(primaryUid)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Курьер фаол рейсда — аввал рейсни якунланг'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final reason = await _askReason(status);
    if (reason == null || !mounted) return;
    setState(() => _busyAccountId = accountId);
    try {
      await _callable('adminSetCapabilityStatus').call<Object?>({
        'accountId': accountId,
        'service': 'courier',
        'status': status,
        'reason': reason,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ҳолат ўзгартирилди: ${_label(status)}')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text(e.code == 'failed-precondition'
              ? 'Бу ҳолатдан «${_label(status)}»га ўтиб бўлмайди'
              : 'Ҳолатни ўзгартириб бўлмади. Қайта уриниб кўринг.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyAccountId = null);
    }
  }

  Future<void> _setApprovalMode(String mode) async {
    final toAuto = mode == 'auto';
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(toAuto ? 'Авто тасдиқни ёқиш' : 'Мануал тасдиққа ўтиш'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(toAuto
                ? 'Курьер аризаси ҳеч қандай текширувсиз ДАРҲОЛ тасдиқланади. '
                    'Ҳозир синовдаги курьерлар ўзгармайди — уларни рўйхатдан '
                    'тасдиқланг.'
                : 'Янги аризалар синовга тушади (3 кун + 5 кун). Тасдиқламасангиз, '
                    'курьер 8 кунда тўхтатилади.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration:
                  const InputDecoration(hintText: 'Audit учун қисқа сабаб'),
              maxLength: 200,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Бекор')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Тасдиқлаш'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (reason == null || !mounted) return;
    setState(() => _savingMode = true);
    try {
      await _callable('adminSetCourierApprovalMode')
          .call<Object?>({'mode': mode, 'reason': reason});
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text(e.code == 'permission-denied'
              ? 'Бу амал учун рухсат йўқ'
              : 'Режимни ўзгартириб бўлмади. Қайта уриниб кўринг.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingMode = false);
    }
  }

  Widget _approvalModeCard() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db.collection('settings').doc('courier').snapshots(),
      builder: (context, snap) {
        // Сервер билан бир хил: фақат аниқ 'auto' — авто, қолгани мануал.
        final mode =
            snap.data?.data()?['approvalMode'] == 'auto' ? 'auto' : 'manual';
        return Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Курьер аризасини тасдиқлаш режими',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'manual',
                      label: Text('Мануал'),
                      icon: Icon(Icons.how_to_reg),
                    ),
                    ButtonSegment(
                      value: 'auto',
                      label: Text('Авто'),
                      icon: Icon(Icons.bolt),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: !snap.hasData || _savingMode
                      ? null
                      : (s) {
                          if (s.first != mode) _setApprovalMode(s.first);
                        },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _label(String status) => switch (status) {
        'approved' => 'Тасдиқланган',
        'suspended' => 'Тўхтатилган',
        _ => _filters[status] ?? status,
      };

  Future<String?> _askReason(String status) async {
    final ctrl = TextEditingController();
    final out = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Сабаб — ${_label(status)}'),
        content: TextField(
          controller: ctrl,
          decoration:
              const InputDecoration(hintText: 'Audit учун қисқа сабаб'),
          maxLength: 200,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Бекор')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Тасдиқлаш'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _approvalModeCard(),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '➕ Янги курьер қўшиш',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Одам AVA иловасига камида бир марта кирган бўлиши керак. '
                    'Қўшилган курьер дарҳол тасдиқланади.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9 +\-]'),
                            ),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Телефон рақам',
                            hintText: '+998 90 123 45 67',
                            prefixIcon: const Icon(Icons.phone),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _reasonCtrl,
                          maxLength: 200,
                          decoration: InputDecoration(
                            labelText: 'Изоҳ (ихтиёрий, audit учун)',
                            counterText: '',
                            prefixIcon: const Icon(Icons.notes),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 56,
                        child: FilledButton.icon(
                          onPressed: _adding ? null : _addCourier,
                          icon: _adding
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.add),
                          label: const Text('Қўшиш'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Курьерлар',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              DropdownButton<String>(
                value: _filter,
                items: _filters.entries
                    .map((e) =>
                        DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _filter = v ?? _filter),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db
                  .collection('provider_capabilities')
                  .where('status.courier', isEqualTo: _filter)
                  .limit(200)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Center(
                    child: Text('Рўйхатни юклаб бўлмади. Қайта уриниб кўринг.'),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.delivery_dining,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '«${_filters[_filter]}» рўйхати бўш',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _CourierCapabilityCard(
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
      ),
    );
  }
}

class _CourierCapabilityCard extends StatelessWidget {
  const _CourierCapabilityCard({
    required this.accountId,
    required this.data,
    required this.busy,
    required this.onSetStatus,
  });

  final String accountId;
  final Map<String, dynamic> data;
  final bool busy;
  final Future<void> Function(String accountId, String primaryUid, String status)
      onSetStatus;

  String _fmt(dynamic ts) {
    if (ts is! Timestamp) return '—';
    final d = ts.toDate();
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  /// Исм — `users/{телефон}`; эски ҳужжатлар 9 хонали калитда бўлиши мумкин.
  static Future<String> _loadName(String phone) async {
    if (phone.isEmpty) return '';
    final ids = [phone, if (phone.length == 12) phone.substring(3)];
    for (final id in ids) {
      final s =
          await FirebaseFirestore.instance.collection('users').doc(id).get();
      if (s.exists) return (s.data()?['name'] ?? '').toString().trim();
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final identity = (data['identity'] as Map?) ?? const {};
    final phone = (identity['primaryUid'] ?? '').toString();
    final status = ((data['status'] as Map?)?['courier'] ?? '').toString();
    final window = ((data['window'] as Map?)?['courier'] as Map?) ?? const {};

    // Админ учун рухсат этилган ўтишлар (сервер ҳам текширади).
    final actions = <(String, String, Color)>[
      if (status != 'approved')
        ('approved', 'Тасдиқлаш', Colors.green.shade700),
      if (status != 'suspended')
        ('suspended', 'Тўхтатиш', Colors.red.shade700),
    ];

    final dates = <String>[
      if (window['startedAt'] != null) 'Бошланган: ${_fmt(window['startedAt'])}',
      if (status == 'trial' && window['endsAt'] != null)
        'Синов тугайди: ${_fmt(window['endsAt'])}',
      if (status == 'trial_expired' && window['graceEndsAt'] != null)
        'Тўхтатилади: ${_fmt(window['graceEndsAt'])}',
    ];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: FutureBuilder<String>(
                    future: _loadName(phone),
                    builder: (_, s) {
                      final name = s.data ?? '';
                      return Text(
                        '${name.isEmpty ? 'Курьер' : name}  ·  +$phone',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      );
                    },
                  ),
                ),
                Chip(label: Text(status)),
              ],
            ),
            if (dates.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                dates.join('   ·   '),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: actions
                  .map((a) => OutlinedButton(
                        onPressed: busy || phone.isEmpty
                            ? null
                            : () => onSetStatus(accountId, phone, a.$1),
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
