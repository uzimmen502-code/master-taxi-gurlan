import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _nameCtrl  = TextEditingController();
  final _streetCtrl = TextEditingController();

  final List<String> _districts = [
    'Гурлан', 'Урганч', 'Хива', 'Шовот', 'Боғот',
    'Хонқа', 'Янгиариқ', 'Қўшкўпир', 'Тошовуз',
  ];

  final Map<String, List<String>> _mfyByDistrict = {
    'Гурлан': ['Гурлан МФЙ','Хоразм МФЙ','Навоий МФЙ','Тинчлик МФЙ','Мустақиллик МФЙ'],
    'Урганч': ['Марказ МФЙ','Достлик МФЙ','Ёшлик МФЙ','Нурлик МФЙ'],
    'Хива':   ['Ичанқалъа МФЙ','Дилкушод МФЙ','Баҳор МФЙ'],
  };

  String? _selectedDistrict;
  String? _selectedMfy;
  bool _loading = false;
  int _step = 0; // 0=телефон, 1=маълумотлар

  List<String> get _mfyList =>
      _mfyByDistrict[_selectedDistrict] ?? ['Марказ МФЙ','Бошқа МФЙ'];

  Future<void> _checkPhone() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length < 9) return;
    setState(() => _loading = true);
    final doc = await FirebaseFirestore.instance
        .collection('users').doc(phone).get();
    if (!mounted) return;
    if (doc.exists) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userId', phone);
      await prefs.setString('userName', doc['name'] ?? '');
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      setState(() { _step = 1; _loading = false; });
    }
  }

  Future<void> _register() async {
    if (_nameCtrl.text.isEmpty || _selectedDistrict == null ||
        _selectedMfy == null || _streetCtrl.text.isEmpty) return;
    setState(() => _loading = true);
    final phone = _phoneCtrl.text.trim();
    await FirebaseFirestore.instance.collection('users').doc(phone).set({
      'phone':    phone,
      'name':     _nameCtrl.text.trim(),
      'district': _selectedDistrict,
      'mfy':      _selectedMfy,
      'street':   _streetCtrl.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId', phone);
    await prefs.setString('userName', _nameCtrl.text.trim());
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              const Text('Master', style: TextStyle(
                  fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white)),
              const Text('Taxi Gurlan', style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w300,
                  color: Color(0xFFF9CB42))),
              const SizedBox(height: 48),

              if (_step == 0) ...[
                const Text('Телефон рақам',
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  decoration: _inputDecor('+998 XX XXX XX XX'),
                ),
                const SizedBox(height: 24),
                _btn('Давом этиш', _loading ? null : _checkPhone),
              ],

              if (_step == 1) ...[
                const Text('Исм ва манзил',
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecor('Исм Фамилия'),
                ),
                const SizedBox(height: 12),
                _dropdown('Туман', _districts, _selectedDistrict, (v) {
                  setState(() { _selectedDistrict = v; _selectedMfy = null; });
                }),
                const SizedBox(height: 12),
                _dropdown('МФЙ', _mfyList, _selectedMfy, (v) {
                  setState(() => _selectedMfy = v);
                }),
                const SizedBox(height: 12),
                TextField(
                  controller: _streetCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecor('Кўча / Уй рақами'),
                ),
                const SizedBox(height: 24),
                _btn('Рўйхатдан ўтиш', _loading ? null : _register),
              ],
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecor(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white30),
    filled: true,
    fillColor: Colors.white10,
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );

  Widget _dropdown(String label, List<String> items,
      String? value, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      dropdownColor: const Color(0xFF2A2A3E),
      style: const TextStyle(color: Colors.white),
      decoration: _inputDecor(label),
      hint: Text(label, style: const TextStyle(color: Colors.white30)),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _btn(String text, VoidCallback? onTap) => SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFF9CB42),
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: _loading
          ? const SizedBox(width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
          : Text(text, style: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.bold)),
    ),
  );
}