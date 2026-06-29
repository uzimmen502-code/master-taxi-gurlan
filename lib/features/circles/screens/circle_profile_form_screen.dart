import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/circle.dart';
import '../../../models/circle_member.dart';
import '../../../repositories/circles_repository.dart';
import '../utils/circle_type_spec.dart';
import 'circle_screen.dart';

/// Universal profil + avto-qo'shilish formasi (tipga bog'liq `spec`).
class CircleProfileFormScreen extends StatefulWidget {
  const CircleProfileFormScreen({
    super.key,
    required this.spec,
    required this.phone,
  });

  final CircleTypeSpec spec;
  final String phone;

  static const _accent = Color(0xFF6A4C93);

  @override
  State<CircleProfileFormScreen> createState() =>
      _CircleProfileFormScreenState();
}

class _CircleProfileFormScreenState extends State<CircleProfileFormScreen> {
  final _repo = CirclesRepository();
  final _nameCtrl = TextEditingController();
  final _ctrls = <String, TextEditingController>{};
  bool _phoneVisible = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final f in [
      ...widget.spec.identityFields,
      ...widget.spec.profileFields
    ]) {
      _ctrls[f.key] = TextEditingController();
    }
    _prefillName();
  }

  Future<void> _prefillName() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.phone)
          .get();
      final name = (snap.data()?['name'] ?? '').toString();
      if (name.isNotEmpty && mounted && _nameCtrl.text.isEmpty) {
        _nameCtrl.text = name;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> _inputs() {
    final m = <String, String>{};
    _ctrls.forEach((k, c) => m[k] = c.text.trim());
    return m;
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Исм-фамилияни киритинг.');
      return;
    }
    for (final f in widget.spec.identityFields) {
      final val = _ctrls[f.key]!.text.trim();
      if (f.required && val.isEmpty) {
        _snack('«${f.label.replaceAll(' *', '')}» ни киритинг.');
        return;
      }
      if (f.number && val.isNotEmpty) {
        final n = int.tryParse(val);
        if (n == null || n < 1900 || n > DateTime.now().year + 1) {
          _snack('«${f.label.replaceAll(' *', '')}» ни тўғри киритинг.');
          return;
        }
      }
    }

    final inputs = _inputs();
    final existing = await _repo.suggestCircle(spec: widget.spec, inputs: inputs);
    if (!mounted) return;
    if (existing != null) {
      final ok = await _confirmJoin(existing);
      if (ok != true) return;
    }

    setState(() => _busy = true);
    try {
      final extra = <String, String>{};
      for (final f in widget.spec.profileFields) {
        extra[f.key] = _ctrls[f.key]!.text.trim();
      }
      final member = CircleMember(
        userId: widget.phone,
        fullName: name,
        extra: extra,
        phone: widget.phone,
        phoneVisible: _phoneVisible,
      );
      final circle = await _repo.joinOrCreateCircle(
        spec: widget.spec,
        inputs: inputs,
        member: member,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CircleScreen(circleId: circle.id, phone: widget.phone),
        ),
      );
    } catch (e) {
      if (mounted) _snack('Хатолик: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmJoin(Circle c) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Мавжуд давра топилди'),
        content: Text('«${c.title}» — ${c.memberCount} аъзо.\n'
            'Шу даврага қўшиласизми?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Йўқ')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: CircleProfileFormScreen._accent,
                foregroundColor: Colors.white),
            child: const Text('Ҳа, қўшиламан'),
          ),
        ],
      ),
    );
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final fields = [...widget.spec.identityFields, ...widget.spec.profileFields];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.spec.title),
        backgroundColor: CircleProfileFormScreen._accent,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field(_nameCtrl, 'Исм-фамилия *', Icons.person_outline),
          for (final f in fields)
            _field(_ctrls[f.key]!, f.label, Icons.edit_outlined,
                number: f.number),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _phoneVisible,
            activeThumbColor: CircleProfileFormScreen._accent,
            contentPadding: EdgeInsets.zero,
            title: const Text('Телефонимни давра аъзоларига кўрсатиш'),
            subtitle: Text(
              _phoneVisible
                  ? 'Аъзолар телефонингизни кўради.'
                  : 'Телефонингиз яширин (тавсия).',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            onChanged: (v) => setState(() => _phoneVisible = v),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                  backgroundColor: CircleProfileFormScreen._accent,
                  foregroundColor: Colors.white),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Давранга қўшилиш'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    IconData icon, {
    bool number = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        inputFormatters:
            number ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}
