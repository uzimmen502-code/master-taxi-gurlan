import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/account_deletion_admin_service.dart';
import '../services/admin_auth_service.dart';

/// Админ: «Ҳисобни ўчириш» (docs/hisobni_ochirish_2026-10-24_uz.md §8). Рўйхат, тафсилот, бекор қилиш — admin|superadmin;
/// қўлда сўров, қайта юритиш ва дарвоза — фақат superadmin (СЕРВЕР ҳам шуни талаб қилади). Ҳар ўзгартирувчи амал сабаб билан
/// `admin_audit`га тушади. Фойдаланувчи ҳисобининг шахсий маълумоти (исм, манзил, ҳамён тарихи) бу ерда кўрсатилмайди.
class AccountDeletionAdminScreen extends StatefulWidget {
  const AccountDeletionAdminScreen({super.key, AccountDeletionAdminService? service, bool? isSuperAdmin})
      : _service = service,
        _isSuper = isSuperAdmin;

  final AccountDeletionAdminService? _service;
  final bool? _isSuper;

  @override
  State<AccountDeletionAdminScreen> createState() => _AccountDeletionAdminScreenState();
}

class _Filter {
  const _Filter(this.label, this.statuses);

  final String label;
  final List<String>? statuses; // null — сервер стандарти (фаол)
}

const _filters = <_Filter>[
  _Filter('Фаол', null),
  _Filter('Муваффақиятсиз', ['FAILED']),
  _Filter('Тугалланган', ['DONE']),
  _Filter('Бекор қилинган', ['CANCELLED']),
];

String _statusLabel(String s) => switch (s) {
      'PENDING' => 'Кутилмоқда',
      'POSTPONED' => 'Кечиктирилган',
      'EXECUTING' => 'Ижро этилмоқда',
      'FAILED' => 'Муваффақиятсиз',
      'DONE' => 'Тугалланган',
      'CANCELLED' => 'Бекор қилинган',
      _ => s,
    };

String _eventLabel(String t) => switch (t) {
      'requested' => 'Сўров юборилди',
      'executing' => 'Ижро бошланди',
      'postponed' => 'Кечиктирилди (тугамаган иш бор)',
      'step_error' => 'Қадамда хато',
      'failed' => 'Муваффақиятсиз тугади',
      'done' => 'Тугалланди',
      'cancelled' => 'Бекор қилинди',
      'admin_retry' => 'Админ қайта юритишга очди',
      _ => t,
    };

String _stepLabel(String s) => switch (s) {
      'forfeit_wallet' => 'Ҳамён сўндирилди',
      'delete_device_and_links' => 'Қурилма ва Telegram боғланиши',
      'delete_user_subcollections' => 'Шахсий ости-маълумотлар',
      'dating_own_side' => 'Танишув (ўз томони)',
      'delete_public_content' => 'Очиқ контент',
      'release_ev_stations' => 'EV станциялар (эгалик олинди)',
      'delete_provider_and_support' => 'Провайдер, чат, қариндошлар',
      'anonymize_records' => 'Буюртма/сафар анонимлаштирилди',
      'archive_wallet_ledger' => 'Ҳамён тарихи архивга',
      'user_shell' => 'Профил қобиққа айлантирилди',
      'auth_delete' => 'Кириш ҳисоби ўчирилди',
      _ => s,
    };

String _fmt(DateTime? d) => d == null
    ? '—'
    : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _errText(Object e) {
  final code = e is AdminDeletionFailure ? e.code : '';
  return switch (code) {
    'REASON_REQUIRED' => 'Сабабни ёзинг (камида 3 белги).',
    'ACCOUNT_DELETION_BLOCKED' => 'Ҳисобда тугамаган ишлар бор — ўчириб бўлмайди.',
    'ACCOUNT_DELETION_DISABLED' => 'Дарвоза ёпиқ ёки бу рақам ички рўйхатда йўқ.',
    'ACCOUNT_NOT_FOUND' => 'Ҳисоб топилмади.',
    'ACCOUNT_DELETION_NOT_PENDING' => 'Ўчириш сўрови йўқ.',
    'ACCOUNT_DELETION_IN_PROGRESS' => 'Ижро бошланган, бекор қилиб бўлмайди.',
    'ACCOUNT_DELETION_NOT_FAILED' => 'Фақат муваффақиятсиз сўровни қайта юритиш мумкин.',
    'INVALID_GATE' => 'Дарвоза қиймати нотўғри.',
    'permission-denied' => 'Бу амал учун рухсат йўқ.',
    _ => 'Бажариб бўлмади. Қайта уриниб кўринг.',
  };
}

class _AccountDeletionAdminScreenState extends State<AccountDeletionAdminScreen> {
  late final AccountDeletionAdminService _svc = widget._service ?? AccountDeletionAdminService();
  int _filter = 0;
  List<AdminDeletionRow> _rows = const [];
  AdminDeletionGate? _gate;
  bool _loading = true;
  bool _failed = false;

  bool get _isSuper => widget._isSuper ?? context.read<AdminAuthService>().isSuperAdmin;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final rows = await _svc.list(statuses: _filters[_filter].statuses);
      final gate = await _svc.gate();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _gate = gate;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _snack(String t) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t)));

  Future<String?> _askReason(String title, {String? subtitle, String action = 'Тасдиқлаш'}) {
    return showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(title: title, subtitle: subtitle, action: action),
    );
  }

  Future<void> _requestOnBehalf() async {
    final res = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _RequestDialog(),
    );
    if (res == null || !mounted) return;
    try {
      await _svc.request(res.$1, res.$2);
      _snack('Сўров қабул қилинди');
      await _load();
    } catch (e) {
      _snack(_errText(e));
    }
  }

  Future<void> _openDetail(AdminDeletionRow row) async {
    AdminDeletionDetail d;
    try {
      d = await _svc.detail(row.uid);
    } catch (e) {
      _snack(_errText(e));
      return;
    }
    if (!mounted) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _DetailDialog(detail: d, svc: _svc, isSuper: _isSuper, askReason: _askReason),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _editGate() async {
    final g = _gate;
    if (g == null) return;
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _GateDialog(gate: g, svc: _svc),
    );
    if (done == true && mounted) {
      _snack('Дарвоза янгиланди');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🗑 Ҳисобни ўчириш', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_isSuper)
            IconButton(
              key: const ValueKey('acct_admin_request'),
              tooltip: 'Қўлда сўров (илова йўқ фойдаланувчи)',
              icon: const Icon(Icons.person_remove_alt_1_outlined),
              onPressed: _requestOnBehalf,
            ),
          IconButton(tooltip: 'Янгилаш', icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Юклаб бўлмади. Қайта уриниб кўринг.'),
                    const SizedBox(height: 8),
                    OutlinedButton(key: const ValueKey('acct_admin_retry'), onPressed: _load, child: const Text('Қайта уриниш')),
                  ]),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (_gate != null) _GateCard(gate: _gate!, canEdit: _isSuper, onEdit: _editGate),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (var i = 0; i < _filters.length; i++)
                          ChoiceChip(
                            key: ValueKey('acct_admin_filter_$i'),
                            label: Text(_filters[i].label),
                            selected: _filter == i,
                            onSelected: (_) {
                              setState(() => _filter = i);
                              _load();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('Сўровлар йўқ', key: ValueKey('acct_admin_empty'))),
                      ),
                    for (final r in _rows)
                      Card(
                        child: ListTile(
                          key: ValueKey('acct_admin_row_${r.uid}'),
                          onTap: () => _openDetail(r),
                          title: Text('+${r.uid}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            [
                              'Сўров: ${_fmt(r.requestedAt)}',
                              if (r.status == 'PENDING' || r.status == 'POSTPONED') 'Ижро: ${_fmt(r.scheduledFor)}',
                              if (r.status == 'DONE') 'Тугади: ${_fmt(r.completedAt)}',
                              if (r.attempts > 0) 'уриниш: ${r.attempts}',
                              if (r.source == 'admin') 'қўлда',
                              if (r.lastError.isNotEmpty) 'хато: ${r.lastError}',
                            ].join(' · '),
                          ),
                          trailing: Chip(label: Text(_statusLabel(r.status))),
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _GateCard extends StatelessWidget {
  const _GateCard({required this.gate, required this.canEdit, required this.onEdit});

  final AdminDeletionGate gate;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final mode = switch (gate.mode) {
      'off' => 'ЁПИҚ (ҳеч ким сўров юбора олмайди, режали ижро тўхтаган)',
      'internal' => 'ИЧКИ СИНОВ — фақат ${gate.allow.length} та рақам',
      _ => 'ОЧИҚ — ҳамма учун',
    };
    return Card(
      key: const ValueKey('acct_admin_gate'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Дарвоза', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(mode, key: const ValueKey('acct_admin_gate_mode')),
              Text('Кутиш: ${gate.waitDays} кун'),
              if (gate.mode == 'internal') Text(gate.allow.join(', '), style: const TextStyle(fontSize: 12)),
            ]),
          ),
          if (canEdit)
            OutlinedButton(key: const ValueKey('acct_admin_gate_edit'), onPressed: onEdit, child: const Text('Ўзгартириш')),
        ]),
      ),
    );
  }
}

/// Сабаб сўрайдиган ойна: камида 3 белги бўлмагунча тугма ўчиқ (41-банд).
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, this.subtitle, required this.action});

  final String title;
  final String? subtitle;
  final String action;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _c.text.trim().length >= 3;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.subtitle != null) ...[Text(widget.subtitle!), const SizedBox(height: 8)],
        TextField(
          key: const ValueKey('acct_admin_reason'),
          controller: _c,
          autofocus: true,
          maxLength: 300,
          decoration: const InputDecoration(labelText: 'Сабаб (шарт)'),
          onChanged: (_) => setState(() {}),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ёпиш')),
        FilledButton(
          key: const ValueKey('acct_admin_reason_ok'),
          onPressed: ok ? () => Navigator.pop(context, _c.text.trim()) : null,
          child: Text(widget.action),
        ),
      ],
    );
  }
}

class _RequestDialog extends StatefulWidget {
  const _RequestDialog();

  @override
  State<_RequestDialog> createState() => _RequestDialogState();
}

class _RequestDialogState extends State<_RequestDialog> {
  final _phone = TextEditingController();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    final ok = (digits.length == 9 || digits.length == 12) && _reason.text.trim().length >= 3;
    return AlertDialog(
      title: const Text('Қўлда ўчириш сўрови'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'Илова йўқ фойдаланувчи email ёки чат орқали сўраганда. Шахсини ТАСДИҚЛАШ — сизнинг масъулиятингиз. '
            'Кутиш муддати одатдагидек, шу вақтда ҳисоб эгаси иловага кириб бекор қила олади.',
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('acct_admin_phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Телефон (998XXXXXXXXX)'),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            key: const ValueKey('acct_admin_reason'),
            controller: _reason,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Сабаб (шарт)'),
            onChanged: (_) => setState(() {}),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ёпиш')),
        FilledButton(
          key: const ValueKey('acct_admin_request_ok'),
          onPressed: ok ? () => Navigator.pop(context, (digits, _reason.text.trim())) : null,
          child: const Text('Сўров юбориш'),
        ),
      ],
    );
  }
}

class _DetailDialog extends StatefulWidget {
  const _DetailDialog({required this.detail, required this.svc, required this.isSuper, required this.askReason});

  final AdminDeletionDetail detail;
  final AccountDeletionAdminService svc;
  final bool isSuper;
  final Future<String?> Function(String title, {String? subtitle, String action}) askReason;

  @override
  State<_DetailDialog> createState() => _DetailDialogState();
}

class _DetailDialogState extends State<_DetailDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _act(String title, String action, Future<void> Function(String reason) run) async {
    final reason = await widget.askReason(title, action: action);
    if (reason == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await run(reason);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _errText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final r = d.row;
    return AlertDialog(
      title: Text('+${r.uid}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ҳолат: ${_statusLabel(r.status)}', key: const ValueKey('acct_admin_detail_status'), style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('Сўров: ${_fmt(r.requestedAt)}'),
            if (r.scheduledFor != null) Text('Режалаштирилган ижро: ${_fmt(r.scheduledFor)}'),
            if (r.nextCheckAt != null) Text('Кейинги текширув: ${_fmt(r.nextCheckAt)}'),
            Text('Уринишлар: ${r.attempts}   Манба: ${r.source == 'admin' ? 'админ' : 'илова'}'),
            Text('Сўров пайтидаги ҳамён: ${r.walletAtRequest} сўм'),
            if (d.hiddenCount > 0) Text('Яширилган ҳужжатлар: ${d.hiddenCount}'),
            if (r.hidePending) const Text('⚠ Яшириш тўлиқ бажарилмаган (қайта уринилади)'),
            if (r.lastError.isNotEmpty) Text('Охирги хато: ${r.lastError}', style: const TextStyle(color: Colors.red)),
            if (r.blockers.isNotEmpty) Text('Тўсиқлар: ${r.blockers.join(', ')}'),
            if (d.steps.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Қадамлар', style: TextStyle(fontWeight: FontWeight.w800)),
              for (final e in d.steps.entries) Text('${e.value ? '✓' : '…'} ${_stepLabel(e.key)}'),
            ],
            const SizedBox(height: 10),
            const Text('Воқеалар', style: TextStyle(fontWeight: FontWeight.w800)),
            for (final e in d.events)
              Text('${_fmt(e.at)} — ${_eventLabel(e.type)}${e.meta['by'] != null ? ' (${e.meta['by']})' : ''}'),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, key: const ValueKey('acct_admin_detail_error'), style: const TextStyle(color: Colors.red))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Ёпиш')),
        if (r.canRetry && widget.isSuper)
          OutlinedButton(
            key: const ValueKey('acct_admin_retry_btn'),
            onPressed: _busy ? null : () => _act('Қайта юритишга очиш', 'Қайта юритиш', (reason) => widget.svc.retry(r.uid, reason)),
            child: const Text('Қайта юритиш'),
          ),
        if (r.canCancel)
          FilledButton(
            key: const ValueKey('acct_admin_cancel_btn'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: _busy ? null : () => _act('Ўчиришни бекор қилиш', 'Бекор қилиш', (reason) => widget.svc.cancel(r.uid, reason)),
            child: const Text('Бекор қилиш'),
          ),
      ],
    );
  }
}

class _GateDialog extends StatefulWidget {
  const _GateDialog({required this.gate, required this.svc});

  final AdminDeletionGate gate;
  final AccountDeletionAdminService svc;

  @override
  State<_GateDialog> createState() => _GateDialogState();
}

class _GateDialogState extends State<_GateDialog> {
  late String _mode = widget.gate.mode;
  late final _days = TextEditingController(text: '${widget.gate.waitDays}');
  late final _allow = TextEditingController(text: widget.gate.allow.join('\n'));
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _days.dispose();
    _allow.dispose();
    _reason.dispose();
    super.dispose();
  }

  /// Рақамлар қатор/вергул/нуқтали вергул билан ажратилади (БЎШЛИҚ билан эмас: «+998 90 111-22-33» бир рақам).
  List<String> get _phones => [
        for (final p in _allow.text.split(RegExp(r'[\n,;]+')))
          if (p.replaceAll(RegExp(r'\D'), '').isNotEmpty) p.replaceAll(RegExp(r'\D'), ''),
      ];

  bool get _valid {
    final days = int.tryParse(_days.text.trim());
    if (days == null || days < 1 || days > 60) return false;
    if (_reason.text.trim().length < 3) return false;
    if (_mode == 'internal') {
      final p = _phones;
      if (p.isEmpty || p.any((x) => !(x.length == 9 || x.length == 12))) return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (_mode == 'public') {
      final sure = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Ҳамма учун очилсинми?'),
          content: const Text('Ўчириш ҚАЙТАРИЛМАС. Ички синов, матнлар (веб-саҳифа, махфийлик) ва ҳисобчилик масаласи тайёр бўлгандан кейингина.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Йўқ')),
            FilledButton(key: const ValueKey('acct_admin_public_yes'), onPressed: () => Navigator.pop(c, true), child: const Text('Ҳа, очилсин')),
          ],
        ),
      );
      if (sure != true) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.svc.setGate(
        enabled: _mode != 'off',
        waitDays: int.parse(_days.text.trim()),
        allow: _mode == 'internal' ? _phones : const [],
        reason: _reason.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _errText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Дарвозани ўзгартириш'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final m in const [('off', 'Ёпиқ'), ('internal', 'Ички синов (рўйхатдаги рақамлар)'), ('public', 'Очиқ (ҳамма учун)')])
              ListTile(
                key: ValueKey('acct_admin_mode_${m.$1}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(_mode == m.$1 ? Icons.radio_button_checked : Icons.radio_button_off),
                title: Text(m.$2),
                onTap: _busy ? null : () => setState(() => _mode = m.$1),
              ),
            TextField(
              key: const ValueKey('acct_admin_days'),
              controller: _days,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Кутиш (кун, 1–60)'),
              onChanged: (_) => setState(() {}),
            ),
            if (_mode == 'internal')
              TextField(
                key: const ValueKey('acct_admin_allow'),
                controller: _allow,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Рақамлар (ҳар қаторга биттадан, 998XXXXXXXXX)'),
                onChanged: (_) => setState(() {}),
              ),
            TextField(
              key: const ValueKey('acct_admin_reason'),
              controller: _reason,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Сабаб (шарт)'),
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) Text(_error!, key: const ValueKey('acct_admin_gate_error'), style: const TextStyle(color: Colors.red)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Ёпиш')),
        FilledButton(key: const ValueKey('acct_admin_gate_save'), onPressed: (_valid && !_busy) ? _save : null, child: const Text('Сақлаш')),
      ],
    );
  }
}
