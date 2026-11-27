import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/firebase_functions_client.dart';

/// «Қурилма тасдиқлари» (эга 2026-11-28): «Эски телефоним йўқ» деган
/// фойдаланувчиларнинг янги қурилмасини админ тасдиқлайди ёки рад этади.
/// Сервер: `adminListDeviceApprovals`, `adminDecideDeviceApproval` (admin/
/// superadmin; админ/панел рақами — фақат superadmin; ҳар қарор `admin_audit`
/// ва `device_binding_events`га ёзилади). Тасдиқдан кейин ҳисобда 24 соат пул
/// ечиш ва ўтказмалар ёпиқ.
class DeviceApprovalItem {
  const DeviceApprovalItem({
    required this.requestId,
    required this.phone,
    this.name = '',
    this.role = '',
    this.accountExists = false,
    this.newDeviceLabel = '',
    this.oldDeviceLabel = '',
    this.platform = '',
    this.approxCity = '',
    this.note = '',
    this.privileged = false,
    this.canDecide = false,
    this.hasBoundDevice = false,
    this.createdAtMs = 0,
    this.expiresAtMs = 0,
    this.status = 'pending',
    this.channel = 'admin_review',
    this.decidable = false,
  });

  factory DeviceApprovalItem.fromMap(Map<String, dynamic> m) {
    int n(Object? v) => v is num ? v.toInt() : 0;
    String s(Object? v) => (v ?? '').toString();
    return DeviceApprovalItem(
      requestId: s(m['requestId']),
      phone: s(m['phone']),
      name: s(m['name']),
      role: s(m['role']),
      accountExists: m['accountExists'] == true,
      newDeviceLabel: s(m['newDeviceLabel']),
      oldDeviceLabel: s(m['oldDeviceLabel']),
      platform: s(m['platform']),
      approxCity: s(m['approxCity']),
      note: s(m['note']),
      privileged: m['privileged'] == true,
      canDecide: m['canDecide'] == true,
      hasBoundDevice: m['hasBoundDevice'] == true,
      createdAtMs: n(m['createdAtMs']),
      expiresAtMs: n(m['expiresAtMs']),
      status: s(m['status']),
      channel: m['channel'] == null ? 'admin_review' : s(m['channel']),
      decidable: m['decidable'] == null ? s(m['status']) == 'pending' : m['decidable'] == true,
    );
  }

  final String requestId;
  final String phone;
  final String name;
  final String role;
  final bool accountExists;
  final String newDeviceLabel;
  final String oldDeviceLabel;
  final String platform;
  final String approxCity;
  final String note;
  final bool privileged;
  final bool canDecide;
  final bool hasBoundDevice;
  final int createdAtMs;
  final int expiresAtMs;
  final String status;

  /// `admin_review` («Эски телефоним йўқ») ёки `old_device_push` (эски APK «эски қурилмадан тасдиқлаш»).
  final String channel;

  /// Сервер: 72 соат ичида ва ҳал қилинмаган — админ қарор қила олади.
  final bool decidable;
}

abstract class DeviceApprovalsApi {
  /// [phone] берилса — шу рақамнинг охирги 72 соатдаги барча сўровлари.
  Future<List<DeviceApprovalItem>> list(String status, {String phone = ''});
  Future<void> decide({
    required String requestId,
    required bool approve,
    String note,
    String identityCheck,
  });
}

class CallableDeviceApprovalsApi implements DeviceApprovalsApi {
  CallableDeviceApprovalsApi({FirebaseFunctions? functions})
      : _fn = functions ?? AvaFunctions.auth;
  final FirebaseFunctions _fn;

  @override
  Future<List<DeviceApprovalItem>> list(String status, {String phone = ''}) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final r = await _fn.httpsCallable('adminListDeviceApprovals').call<Object?>({
      'status': status,
      if (digits.length >= 9) 'phone': digits.length == 9 ? '998$digits' : digits,
    });
    final data = r.data;
    final raw = data is Map ? data['items'] : null;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => DeviceApprovalItem.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<void> decide({
    required String requestId,
    required bool approve,
    String note = '',
    String identityCheck = '',
  }) async {
    await _fn.httpsCallable('adminDecideDeviceApproval').call<Object?>({
      'requestId': requestId,
      'approve': approve,
      if (note.trim().isNotEmpty) 'note': note.trim(),
      if (identityCheck.trim().isNotEmpty) 'identityCheck': identityCheck.trim(),
    });
  }
}

class DeviceApprovalsScreen extends StatefulWidget {
  const DeviceApprovalsScreen({super.key, this.api});

  final DeviceApprovalsApi? api;

  @override
  State<DeviceApprovalsScreen> createState() => _DeviceApprovalsScreenState();
}

class _DeviceApprovalsScreenState extends State<DeviceApprovalsScreen> {
  late final DeviceApprovalsApi _api = widget.api ?? CallableDeviceApprovalsApi();
  String _status = 'pending';
  String _phone = '';
  final _phoneCtrl = TextEditingController();
  Future<List<DeviceApprovalItem>>? _future;

  static const _statuses = {
    'pending': 'Кутилмоқда',
    'approved': 'Тасдиқланган',
    'rejected': 'Рад этилган',
  };

  @override
  void initState() {
    super.initState();
    _future = _api.list(_status);
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = _api.list(_status, phone: _phone);
    });
  }

  void _search() {
    _phone = _phoneCtrl.text.trim();
    _reload();
  }

  Future<void> _decide(DeviceApprovalItem it, bool approve) async {
    final identity = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Янги қурилмани тасдиқлаш' : 'Сўровни рад этиш'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${it.phone} · ${it.newDeviceLabel.isEmpty ? 'янги қурилма' : it.newDeviceLabel}'),
              const SizedBox(height: 8),
              if (approve)
                const Text(
                  'Тасдиқлашдан олдин шахсни текширинг (қўнғироқ, паспорт, '
                  'буюртмалар тарихи). Тасдиқдан кейин 24 соат пул ечиш ёпиқ.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('devApprovalIdentity'),
                controller: identity,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Шахс текшируви (масалан: қўнғироқ қилинди, паспорт кўрилди)',
                ),
              ),
              TextField(
                key: const Key('devApprovalNote'),
                controller: note,
                maxLength: 300,
                decoration: const InputDecoration(labelText: 'Изоҳ'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Бекор')),
          FilledButton(
            key: const Key('devApprovalConfirm'),
            style: FilledButton.styleFrom(
              backgroundColor: approve ? Colors.green.shade700 : Colors.red.shade700,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(approve ? 'Тасдиқлаш' : 'Рад этиш'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _api.decide(
        requestId: it.requestId,
        approve: approve,
        note: note.text,
        identityCheck: identity.text,
      );
      messenger.showSnackBar(SnackBar(
        content: Text(approve ? 'Тасдиқланди' : 'Рад этилди'),
        backgroundColor: approve ? Colors.green.shade700 : Colors.orange,
      ));
      _reload();
    } on FirebaseFunctionsException catch (e) {
      final d = e.details;
      final code = d is Map ? (d['code'] ?? '').toString() : '';
      final text = switch (code) {
        'ADMIN_TARGET_NEEDS_SUPERADMIN' => 'Бу админ рақами — фақат superadmin тасдиқлайди.',
        'REQUEST_NOT_PENDING' => 'Сўров аллақачон кўриб чиқилган ёки муддати тугаган.',
        _ => 'Хатолик: ${e.code}',
      };
      messenger.showSnackBar(SnackBar(content: Text(text), backgroundColor: Colors.red));
      _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Хатолик: $e'), backgroundColor: Colors.red));
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _time(int ms) {
    if (ms <= 0) return '—';
    final t = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    return '${_two(t.day)}.${_two(t.month)}.${t.year} ${_two(t.hour)}:${_two(t.minute)}';
  }

  static String _platform(String p) => switch (p) {
        'android' => 'Android',
        'ios' => 'iPhone',
        'web' => 'Веб браузер',
        _ => p,
      };

  Widget _card(DeviceApprovalItem it) {
    final pending = it.decidable;
    final peer = it.channel == 'old_device_push';
    return Card(
      key: Key('devApproval_${it.requestId}'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${it.phone}${it.name.isEmpty ? '' : ' · ${it.name}'}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                if (it.privileged)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('АДМИН РАҚАМИ · ${it.role}',
                        style: TextStyle(color: Colors.red.shade800, fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Янги қурилма: ${it.newDeviceLabel.isEmpty ? '—' : it.newDeviceLabel}'
                '${it.platform.isEmpty ? '' : ' (${_platform(it.platform)})'}'
                '${it.approxCity.isEmpty ? '' : ' · ${it.approxCity}'}'),
            Text('Эски қурилма: ${it.hasBoundDevice ? (it.oldDeviceLabel.isEmpty ? 'бор' : it.oldDeviceLabel) : 'йўқ'}'),
            Text('Ҳисоб: ${it.accountExists ? 'бор' : 'топилмади'} · сўров: ${_time(it.createdAtMs)}'
                '${it.status == 'pending' && !peer ? ' · муддат: ${_time(it.expiresAtMs)}' : ''}'),
            if (peer)
              Text('Тури: эски қурилмадан тасдиқлаш сўрови (эски илова) · ҳолат: ${it.status}',
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700)),
            if (it.note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Фойдаланувчи изоҳи: ${it.note}',
                  style: const TextStyle(fontStyle: FontStyle.italic)),
            ],
            if (it.hasBoundDevice && pending) ...[
              const SizedBox(height: 6),
              Text(
                'Эски қурилмага «Бу сизми?» сўрови юборилган — эгаси «Йўқ» деса сўров ёпилади.',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              ),
            ],
            if (pending) ...[
              const SizedBox(height: 10),
              if (!it.canDecide)
                Text('Фақат superadmin қарор қилади.',
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
              Row(
                children: [
                  FilledButton.icon(
                    key: Key('devApprove_${it.requestId}'),
                    onPressed: it.canDecide ? () => _decide(it, true) : null,
                    style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                    icon: const Icon(Icons.check),
                    label: const Text('Тасдиқлаш'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    key: Key('devReject_${it.requestId}'),
                    onPressed: it.canDecide ? () => _decide(it, false) : null,
                    icon: const Icon(Icons.block),
                    label: const Text('Рад этиш'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Қурилма тасдиқлари',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
              IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '«Эски телефоним йўқ» сўровлари. Тасдиқдан олдин шахсни текширинг.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final e in _statuses.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _phone.isEmpty && _status == e.key,
                  onSelected: (_) {
                    _status = e.key;
                    _phone = '';
                    _phoneCtrl.clear();
                    _reload();
                  },
                ),
              // Эски иловада «Эски телефоним йўқ» йўқ: оператор рақам бўйича охирги 72 соат
              // сўровларини (эски қурилмадан тасдиқлаш сўрови ҳам) топиб тасдиқлайди.
              SizedBox(
                width: 260,
                child: TextField(
                  key: const Key('devApprovalPhoneSearch'),
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Рақам бўйича (72 соат)',
                    suffixIcon: IconButton(
                      key: const Key('devApprovalPhoneSearchGo'),
                      icon: const Icon(Icons.search),
                      onPressed: _search,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: FutureBuilder<List<DeviceApprovalItem>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Юклаб бўлмади: ${snap.error}'));
                }
                final items = snap.data ?? const [];
                if (items.isEmpty) {
                  return const Center(child: Text('Сўровлар йўқ'));
                }
                return ListView(children: [for (final it in items) _card(it)]);
              },
            ),
          ),
        ],
      ),
    );
  }
}
