import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../data/family_links_repository.dart';

/// «Оила боғланиши» (эга 2026-11-28): турмуш ўртоғи ва яқин қариндошлар — иккинчи томон ТАСДИҚЛАСА боғланади,
/// бонус (дастур фаол бўлса) ҳар икки томонга. Кирувчи таклифлар (қабул/рад), ҳолат, ажратиш.
class FamilyLinksScreen extends StatefulWidget {
  const FamilyLinksScreen({super.key, this.api, this.focus = ''});

  /// Тест учун; бўлмаса — [FirebaseFamilyLinksApi].
  final FamilyLinksApi? api;

  /// 'spouse' — турмуш ўртоғи формасига; 'relatives' — қариндош қўшиш ойнаси очилади.
  final String focus;

  @override
  State<FamilyLinksScreen> createState() => _FamilyLinksScreenState();
}

class _FamilyLinksScreenState extends State<FamilyLinksScreen> {
  late final FamilyLinksApi _api = widget.api ?? FirebaseFamilyLinksApi();
  FamilyState? _state;
  bool _error = false;
  bool _busy = false;
  final _name = TextEditingController();
  final _birth = TextEditingController();
  final _phone = TextEditingController();
  List<String> _problems = const [];
  bool _autoOpened = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _birth.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = false);
    try {
      final s = await _api.load();
      if (!mounted) return;
      setState(() => _state = s);
      if (!_autoOpened && widget.focus == 'relatives') {
        _autoOpened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _addRelative();
        });
      }
    } catch (e) {
      debugPrint('[Family] FAMILY_LOAD_FAILED: $e');
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _run(Future<void> Function() op, {String? okKey}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await op();
      if (okKey != null && mounted) messenger..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(context.tr(okKey))));
      await _load();
    } catch (e) {
      debugPrint('[Family] FAMILY_OP_FAILED: $e');
      if (mounted) messenger..hideCurrentSnackBar()..showSnackBar(SnackBar(key: const ValueKey('fam_error'), content: Text(context.tr(familyErrorKey(e)))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _isoBirth(String raw) {
    final d = parseBirthDate(raw);
    if (d == null) return '';
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _inviteSpouse() async {
    final birth = _isoBirth(_birth.text);
    final p = familyInviteProblems(name: _name.text, phone: _phone.text, birthDate: birth, spouse: true);
    setState(() => _problems = p);
    if (p.isNotEmpty) return;
    await _run(() => _api.inviteSpouse(name: _name.text, birthDate: birth, phone: _phone.text), okKey: 'fam_invite_sent');
  }

  Future<void> _confirmUnlink(FamilyLink l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('fam_unlink')),
        content: Text(ctx.tr('fam_unlink_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('fam_cancel'))),
          TextButton(key: const ValueKey('fam_unlink_ok'), onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('fam_unlink'))),
        ],
      ),
    );
    if (ok == true) await _run(() => _api.unlink(l));
  }

  Future<void> _addRelative() async {
    final r = await showModalBottomSheet<({String name, String phone, String relation, String birth})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _RelativeForm(),
    );
    if (r == null || !mounted) return;
    await _run(
      () => _api.inviteRelative(name: r.name, phone: r.phone, relation: r.relation, birthDate: _isoBirth(r.birth)),
      okKey: 'fam_invite_sent',
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('fam_title'))),
      body: _error
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(context.tr('fam_err_generic'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 12),
                  FilledButton(key: const ValueKey('fam_retry'), onPressed: _load, child: Text(context.tr('fam_retry'))),
                ]),
              ),
            )
          : s == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      Text(context.tr('fam_intro'), style: const TextStyle(fontSize: 15)),
                      const SizedBox(height: 12),
                      for (final i in s.incoming) _incoming(context, i),
                      _spouseSection(context, s),
                      const SizedBox(height: 20),
                      _relativesSection(context, s),
                    ],
                  ),
                ),
    );
  }

  Widget _card(BuildContext context, {Key? key, required List<Widget> children, Color? color}) => Card(
        key: key,
        color: color,
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      );

  Widget _incoming(BuildContext context, FamilyInvite i) {
    final who = i.fromName.isEmpty ? context.tr('fam_someone') : i.fromName;
    return _card(
      context,
      key: ValueKey('fam_incoming_${i.inviteId}'),
      color: Theme.of(context).colorScheme.primaryContainer,
      children: [
        Text(
          context.tr(i.isSpouse ? 'fam_incoming_spouse' : 'fam_incoming_relative')
              .replaceAll('{name}', who)
              .replaceAll('{relation}', context.tr(familyRelationKey(i.relation))),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(
            key: ValueKey('fam_accept_${i.inviteId}'),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _busy ? null : () => _run(() async => _api.respond(i, accept: true), okKey: 'fam_accepted'),
            child: Text(context.tr('fam_accept')),
          ),
          OutlinedButton(
            key: ValueKey('fam_decline_${i.inviteId}'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _busy ? null : () => _run(() async => _api.respond(i, accept: false)),
            child: Text(context.tr('fam_decline')),
          ),
        ]),
      ],
    );
  }

  Widget _bonusNote(BuildContext context, String key, FamilyProgram p, Key k) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          context.tr(key).replaceAll('{amount}', formatMoney(p.amount)).replaceAll('{days}', '${p.validityDays}'),
          key: k,
          style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
        ),
      );

  Widget _spouseSection(BuildContext context, FamilyState s) {
    final linked = s.spouse;
    final pending = s.pendingSpouse;
    return Column(
      key: const ValueKey('fam_spouse_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.tr('fam_spouse_title'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (s.spouseProgram.active && linked == null) _bonusNote(context, 'fam_spouse_bonus', s.spouseProgram, const ValueKey('fam_spouse_bonus')),
        if (linked != null)
          _card(context, key: const ValueKey('fam_spouse_linked'), children: [
            Text(linked.name.isEmpty ? context.tr('fam_rel_spouse') : linked.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(context.tr('fam_status_linked'), style: const TextStyle(fontSize: 14)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(key: const ValueKey('fam_spouse_unlink'), onPressed: _busy ? null : () => _confirmUnlink(linked), child: Text(context.tr('fam_unlink'))),
            ),
          ])
        else if (pending != null)
          _card(context, key: const ValueKey('fam_spouse_pending'), children: [
            Text(pending.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(context.tr('fam_status_pending'), style: const TextStyle(fontSize: 14)),
          ])
        else ...[
          TextField(
            key: const ValueKey('fam_spouse_name'),
            controller: _name,
            maxLength: 60,
            decoration: InputDecoration(labelText: context.tr('fam_name'), border: const OutlineInputBorder()),
          ),
          TextField(
            key: const ValueKey('fam_spouse_birth'),
            controller: _birth,
            keyboardType: TextInputType.datetime,
            decoration: InputDecoration(labelText: context.tr('fam_birth'), hintText: '31.12.1990', border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('fam_spouse_phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: context.tr('fam_phone'), hintText: '+998 90 123 45 67', border: const OutlineInputBorder()),
          ),
          for (final p in _problems)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(context.tr(p), key: ValueKey('fam_problem_$p'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 8),
          Text(context.tr('fam_spouse_note'), style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          FilledButton(
            key: const ValueKey('fam_spouse_invite'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _busy ? null : _inviteSpouse,
            child: Text(context.tr('fam_send_invite')),
          ),
        ],
      ],
    );
  }

  Widget _relativesSection(BuildContext context, FamilyState s) {
    final rel = s.relatives;
    return Column(
      key: const ValueKey('fam_relatives_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.tr('fam_relatives_title'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (s.relativeProgram.active) _bonusNote(context, 'fam_relative_bonus', s.relativeProgram, const ValueKey('fam_relative_bonus')),
        Text(context.tr('fam_relatives_progress').replaceAll('{n}', '${rel.length}'),
            key: const ValueKey('fam_relatives_progress'), style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 8),
        for (final l in rel)
          _card(context, key: ValueKey('fam_link_${l.pairKey}'), children: [
            Text(l.name.isEmpty ? context.tr(familyRelationKey(l.relation)) : l.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text('${context.tr(familyRelationKey(l.relation))} · ${context.tr('fam_status_linked')}', style: const TextStyle(fontSize: 14)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(key: ValueKey('fam_unlink_${l.pairKey}'), onPressed: _busy ? null : () => _confirmUnlink(l), child: Text(context.tr('fam_unlink'))),
            ),
          ]),
        for (final i in s.relativeInvites)
          _card(context, key: ValueKey('fam_out_${i.inviteId}'), children: [
            Text(i.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text('${context.tr(familyRelationKey(i.relation))} · ${context.tr(i.pending ? 'fam_status_pending' : 'fam_status_declined')}',
                style: const TextStyle(fontSize: 14)),
          ]),
        OutlinedButton.icon(
          key: const ValueKey('fam_add_relative'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _busy ? null : _addRelative,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: Text(context.tr('fam_add_relative')),
        ),
      ],
    );
  }
}

/// Қариндош қўшиш формаси (бир оила: ота, она, ака-ука, опа-сингил, ўғил, қиз).
class _RelativeForm extends StatefulWidget {
  const _RelativeForm();

  @override
  State<_RelativeForm> createState() => _RelativeFormState();
}

class _RelativeFormState extends State<_RelativeForm> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _birth = TextEditingController();
  String _relation = 'father';
  List<String> _problems = const [];

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _birth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(context.tr('fam_add_relative'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const ValueKey('fam_rel_relation'),
            initialValue: _relation,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.tr('fam_relation'), border: const OutlineInputBorder()),
            items: [for (final r in kFamilyRelativeRelations) DropdownMenuItem(value: r, child: Text(context.tr(familyRelationKey(r))))],
            onChanged: (v) => setState(() => _relation = v ?? _relation),
          ),
          const SizedBox(height: 8),
          TextField(key: const ValueKey('fam_rel_name'), controller: _name, maxLength: 60,
              decoration: InputDecoration(labelText: context.tr('fam_name'), border: const OutlineInputBorder())),
          TextField(key: const ValueKey('fam_rel_phone'), controller: _phone, keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: context.tr('fam_phone'), hintText: '+998 90 123 45 67', border: const OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(key: const ValueKey('fam_rel_birth'), controller: _birth, keyboardType: TextInputType.datetime,
              decoration: InputDecoration(labelText: context.tr('fam_birth_optional'), hintText: '31.12.1960', border: const OutlineInputBorder())),
          for (final p in _problems)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(context.tr(p), style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 8),
          Text(context.tr('fam_relative_note'), style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          FilledButton(
            key: const ValueKey('fam_rel_send'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () {
              final p = familyInviteProblems(name: _name.text, phone: _phone.text);
              if (p.isNotEmpty) {
                setState(() => _problems = p);
                return;
              }
              Navigator.of(context).pop((name: _name.text.trim(), phone: _phone.text.trim(), relation: _relation, birth: _birth.text.trim()));
            },
            child: Text(context.tr('fam_send_invite')),
          ),
        ],
      ),
    );
  }
}
