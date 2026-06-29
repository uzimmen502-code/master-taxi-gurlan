import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../utils/fare_calculator.dart';

/// Р™СћР»РєРёСЂР° ТіРёСЃРѕР±Р»Р°С€ РґРёР°Р»РѕРіРё вЂ” РјР°СЃРѕС„Р°, РєСѓС‚РёС€, РєРѕСЌС„С„РёС†РёРµРЅС‚Р»Р°СЂ.
///
/// ТљР°Р№С‚Р°СЂРёС€: `(fare, cashPaid)` С‘РєРё `null` (Р±РµРєРѕСЂ Т›РёР»РёРЅРґРё).
Future<({int fare, int cashPaid})?> showFareCalculatorDialog(
    BuildContext context) {
  return showDialog<({int fare, int cashPaid})>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _FareCalculatorDialog(),
  );
}

class _FareCalculatorDialog extends StatefulWidget {
  const _FareCalculatorDialog();

  @override
  State<_FareCalculatorDialog> createState() => _FareCalculatorDialogState();
}

class _FareCalculatorDialogState extends State<_FareCalculatorDialog> {
  static const _blue = AppColors.primary;
  static const _green = AppColors.primaryDark;
  static const _orange = AppColors.primary;

  double _distanceKm = 3.0;
  int _waitMins = 0;
  bool _isNight = FareCalculator.isNightTime();
  bool _isHoliday = false;
  bool _isRainy = false;
  bool _isUrgent = false;
  final _cashPaidCtrl = TextEditingController();
  bool _cashPaidInitialized = false;

  @override
  void dispose() {
    _cashPaidCtrl.dispose();
    super.dispose();
  }

  Widget _coefChip(String label, bool selected, ValueChanged<bool> onChange) {
    return GestureDetector(
      onTap: () => onChange(!selected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _blue : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _blue : Colors.grey.shade300),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: AppText.labelSmall,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.black87)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fare = FareCalculator.calculate(
      distanceKm: _distanceKm,
      waitMinutes: _waitMins,
      isNight: _isNight,
      isHoliday: _isHoliday,
      isRainy: _isRainy,
      isUrgent: _isUrgent,
    );
    if (!_cashPaidInitialized) {
      _cashPaidCtrl.text = '$fare';
      _cashPaidInitialized = true;
    }
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(children: [
        Icon(Icons.calculate, color: _blue, size: 24),
        SizedBox(width: 8),
        Text('Р™СћР»РєРёСЂР° ТіРёСЃРѕР±Р»Р°С€'),
      ]),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('рџ“Ќ РњР°СЃРѕС„Р° (РєРј)',
                style: TextStyle(
                    fontSize: AppText.bodySmall,
                    fontWeight: FontWeight.w600)),
          ),
          Row(children: [
            Expanded(
                child: Slider(
                    value: _distanceKm,
                    min: 0.5,
                    max: 60,
                    divisions: 119,
                    activeColor: _blue,
                    onChanged: (v) => setState(() =>
                        _distanceKm = double.parse(v.toStringAsFixed(1))))),
            SizedBox(
                width: 50,
                child: Text(_distanceKm.toStringAsFixed(1),
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(fontWeight: FontWeight.bold))),
          ]),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('вЏі РљСѓС‚РёС€ (РґР°Т›)',
                style: TextStyle(
                    fontSize: AppText.bodySmall,
                    fontWeight: FontWeight.w600)),
          ),
          Row(children: [
            Expanded(
                child: Slider(
                    value: _waitMins.toDouble(),
                    min: 0,
                    max: 30,
                    divisions: 30,
                    activeColor: _orange,
                    onChanged: (v) =>
                        setState(() => _waitMins = v.round()))),
            SizedBox(
                width: 50,
                child: Text('$_waitMins РґР°Т›',
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(fontWeight: FontWeight.bold))),
          ]),
          const Divider(height: 16),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _coefChip('рџЊ™ РўСѓРЅРіРё', _isNight,
                (v) => setState(() => _isNight = v)),
            _coefChip('рџљЁ РЁРѕС€РёР»РёРЅС‡', _isUrgent,
                (v) => setState(() => _isUrgent = v)),
            _coefChip('рџЋ‰ Р‘Р°Р№СЂР°Рј', _isHoliday,
                (v) => setState(() => _isHoliday = v)),
            _coefChip('рџЊ§ РЃРјТ“РёСЂ', _isRainy,
                (v) => setState(() => _isRainy = v)),
          ]),
          const Divider(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _green.withValues(alpha: 0.3))),
            child: Column(children: [
              const Text('рџ’° Р™СћР»РєРёСЂР°',
                  style: TextStyle(
                      fontSize: AppText.bodyMedium, color: Colors.grey)),
              const SizedBox(height: 4),
              Text('${FareCalculator.format(fare)} СЃСћРј',
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: _green)),
            ]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cashPaidCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'РњРёР¶РѕР· Р±РµСЂРіР°РЅ РЅР°Т›Рґ (СЃСћРј)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('РћСЂТ›Р°РіР°',
                style: TextStyle(color: Colors.grey))),
        ElevatedButton.icon(
          onPressed: () {
            final paid = int.tryParse(
                    _cashPaidCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ??
                fare;
            Navigator.of(context).pop((fare: fare, cashPaid: paid));
          },
          icon: const Icon(Icons.check_circle, size: 18),
          label: const Text('РЇРљРЈРќР›РђРЁ'),
          style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
        ),
      ],
    );
  }
}
