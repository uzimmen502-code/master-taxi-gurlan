import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';

/// Админ — Маҳаллий такси нархи (`settings/prices`):
///  • local_base   — бошланғич нарх (сўм)
///  • local_per_km — ҳар км учун (сўм)
class TaxiPriceScreen extends StatefulWidget {
  const TaxiPriceScreen({super.key});

  @override
  State<TaxiPriceScreen> createState() => _TaxiPriceScreenState();
}

class _TaxiPriceScreenState extends State<TaxiPriceScreen> {
  static const _green = AppColors.primaryDark;

  final _baseCtrl = TextEditingController();
  final _perKmCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _ok;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    _perKmCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('prices')
          .get();
      final data = doc.data() ?? const <String, dynamic>{};
      final base = (data['local_base'] as num?)?.toInt() ?? 5000;
      final perKm = (data['local_per_km'] as num?)?.toInt() ?? 1500;
      _baseCtrl.text = base.toString();
      _perKmCtrl.text = perKm.toString();
    } catch (e) {
      _error = 'Юклашда хатолик: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final base = int.tryParse(_baseCtrl.text.trim());
    final perKm = int.tryParse(_perKmCtrl.text.trim());
    if (base == null || base <= 0 || perKm == null || perKm <= 0) {
      setState(() {
        _error = 'Нарх мусбат бутун сон бўлиши керак.';
        _ok = null;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _ok = null;
    });
    try {
      await FirebaseFirestore.instance
          .collection('settings')
          .doc('prices')
          .set({
        'local_base': base,
        'local_per_km': perKm,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        setState(() => _ok = '✅ Сақланди. Янги нарх кучга кирди.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Сақлашда хатолик: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.local_taxi, color: _green, size: 26),
                const SizedBox(width: 10),
                Text('Маҳаллий такси нархи',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade900)),
              ]),
              const SizedBox(height: 8),
              Text(
                'Йўлкира формуласи: (бошланғич + масофа×км_нарх + кутиш) '
                '× коэффициентлар. Қуйидаги иккита асосий қиймат таҳрирланади.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              _field(
                label: 'Бошланғич нарх (сўм)',
                hint: 'Масалан: 5000',
                controller: _baseCtrl,
                icon: Icons.flag_outlined,
              ),
              const SizedBox(height: 16),
              _field(
                label: 'Ҳар км учун (сўм/км)',
                hint: 'Масалан: 1500',
                controller: _perKmCtrl,
                icon: Icons.route_outlined,
              ),
              const SizedBox(height: 8),
              Text(
                'Намуна: 5 км сафар → 5000 + 5×1500 = 12 500 сўм '
                '(коэффициентларсиз).',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!,
                    style: TextStyle(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w600)),
              ],
              if (_ok != null) ...[
                const SizedBox(height: 16),
                Text(_ok!,
                    style: const TextStyle(
                        color: _green, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Сақланмоқда...' : 'Сақлаш'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 20),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }
}
