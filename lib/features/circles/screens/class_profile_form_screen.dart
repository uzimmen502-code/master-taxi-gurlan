import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/circle.dart';
import '../../../models/circle_member.dart';
import '../../../repositories/circles_repository.dart';
import 'circle_screen.dart';

/// Sinf profili + avto-qo'shilish formasi.
///
/// Maktab + yil kiritiladi → mavjud davra bo'lsa taklif qilinadi, so'ng
/// qo'shiladi (yoki yangi yaratiladi). Telefon DEFAULT yashirin.
class ClassProfileFormScreen extends StatefulWidget {
  const ClassProfileFormScreen({super.key, required this.phone});

  final String phone;

  static const _accent = Color(0xFF6A4C93);

  @override
  State<ClassProfileFormScreen> createState() => _ClassProfileFormScreenState();
}

class _ClassProfileFormScreenState extends State<ClassProfileFormScreen> {
  final _repo = CirclesRepository();
  final _nameCtrl = TextEditingController();
  final _schoolCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _classCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _jobCtrl = TextEditingController();
  bool _phoneVisible = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
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
    _schoolCtrl.dispose();
    _yearCtrl.dispose();
    _classCtrl.dispose();
    _cityCtrl.dispose();
    _jobCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final school = _schoolCtrl.text.trim();
    final year = int.tryParse(_yearCtrl.text.trim());
    final nowYear = DateTime.now().year;
    if (name.isEmpty) {
      _snack('Исм-фамилияни киритинг.');
      return;
    }
    if (school.isEmpty) {
      _snack('Мактабни киритинг.');
      return;
    }
    if (year == null || year < 1950 || year > nowYear + 1) {
      _snack('Битирган йилни тўғри киритинг (масалан: 2008).');
      return;
    }

    // Mavjud davra taklifi (deterministik ID bo'yicha).
    final existing = await _repo.suggestClassCircle(school, year);
    if (!mounted) return;
    if (existing != null) {
      final ok = await _confirmJoin(existing);
      if (ok != true) return;
    }

    setState(() => _busy = true);
    try {
      final member = CircleMember(
        userId: widget.phone,
        fullName: name,
        classLabel: _classCtrl.text.trim(),
        currentCity: _cityCtrl.text.trim(),
        currentJob: _jobCtrl.text.trim(),
        phone: widget.phone,
        phoneVisible: _phoneVisible,
      );
      final circle = await _repo.joinOrCreateClassCircle(
        school: school,
        year: year,
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
        content: Text(
          '«${c.title}» — ${c.memberCount} аъзо.\n'
          'Шу даврага қўшиласизми?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Йўқ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: ClassProfileFormScreen._accent,
              foregroundColor: Colors.white,
            ),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Синф профили'),
        backgroundColor: ClassProfileFormScreen._accent,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field(_nameCtrl, 'Исм-фамилия *', Icons.person_outline),
          _field(_schoolCtrl, 'Мактаб * (масалан: 1-мактаб)',
              Icons.school_outlined),
          _field(_yearCtrl, 'Битирган йил * (масалан: 2008)',
              Icons.event_outlined,
              number: true),
          _field(_classCtrl, 'Синф (ихтиёрий, масалан: А)',
              Icons.class_outlined),
          _field(_cityCtrl, 'Ҳозирги шаҳар (ихтиёрий)',
              Icons.location_city_outlined),
          _field(_jobCtrl, 'Иш жойи (ихтиёрий)', Icons.work_outline),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _phoneVisible,
            activeThumbColor: ClassProfileFormScreen._accent,
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
                backgroundColor: ClassProfileFormScreen._accent,
                foregroundColor: Colors.white,
              ),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
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
