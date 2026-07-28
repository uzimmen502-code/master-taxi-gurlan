import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../utils/fare_calculator.dart';

/// Йўлкира ҳисоблаш диалоги — масофа, кутиш, коэффициентлар.
///
/// Қайтариш: `(fare, cashPaid)` ёки `null` (бекор қилинди).
Future<({int fare, int cashPaid})?> showFareCalculatorDialog(
  BuildContext context, {
  int? initialFare,
  double? initialDistanceKm,
  int passengerWalletIntent = 0,
  bool fareLocked = false,
}) {
  return showDialog<({int fare, int cashPaid})>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _FareCalculatorDialog(
      initialFare: initialFare,
      initialDistanceKm: initialDistanceKm,
      passengerWalletIntent: passengerWalletIntent,
      fareLocked: fareLocked,
    ),
  );
}

class _FareCalculatorDialog extends StatefulWidget {
  const _FareCalculatorDialog({
    this.initialFare,
    this.initialDistanceKm,
    this.passengerWalletIntent = 0,
    this.fareLocked = false,
  });

  final int? initialFare;
  final double? initialDistanceKm;
  final int passengerWalletIntent;
  final bool fareLocked;

  @override
  State<_FareCalculatorDialog> createState() => _FareCalculatorDialogState();
}

class _FareCalculatorDialogState extends State<_FareCalculatorDialog> {
  static const _blue = AppColors.primary;
  static const _green = AppColors.primaryDark;
  static const _orange = AppColors.primary;

  late double _distanceKm;
  int _waitMins = 0;
  bool _isNight = FareCalculator.isNightTime();
  bool _isHoliday = false;
  bool _isRainy = false;
  bool _isUrgent = false;
  final _cashPaidCtrl = TextEditingController();
  bool _cashPaidInitialized = false;

  @override
  void initState() {
    super.initState();
    _distanceKm = widget.initialDistanceKm ?? 3.0;
  }

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
    final fare = widget.fareLocked && (widget.initialFare ?? 0) > 0
        ? widget.initialFare!
        : FareCalculator.calculate(
            distanceKm: _distanceKm,
            waitMinutes: _waitMins,
            isNight: _isNight,
            isHoliday: _isHoliday,
            isRainy: _isRainy,
            isUrgent: _isUrgent,
          );
    if (!_cashPaidInitialized) {
      final cashDefault = (fare - widget.passengerWalletIntent).clamp(0, fare);
      _cashPaidCtrl.text = '$cashDefault';
      _cashPaidInitialized = true;
    }
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        Icon(widget.fareLocked ? Icons.lock : Icons.calculate,
            color: _blue, size: 24),
        const SizedBox(width: 8),
        Text(widget.fareLocked ? 'Қулфланган йўлкира' : 'Йўлкира ҳисоблаш'),
      ]),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!widget.fareLocked) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('📍 Масофа (км)',
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
              child: Text('⏱ Кутиш (дақ)',
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
                  child: Text('$_waitMins дақ',
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(fontWeight: FontWeight.bold))),
            ]),
            const Divider(height: 16),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _coefChip('🌙 Тунги', _isNight,
                  (v) => setState(() => _isNight = v)),
              _coefChip('🚨 Шошилинч', _isUrgent,
                  (v) => setState(() => _isUrgent = v)),
              _coefChip('🎉 Байрам', _isHoliday,
                  (v) => setState(() => _isHoliday = v)),
              _coefChip('🌧 Ёмғир', _isRainy,
                  (v) => setState(() => _isRainy = v)),
            ]),
            const Divider(height: 20),
          ],
          if (widget.passengerWalletIntent > 0) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '💳 Yo\'lovchi hamyon: ${FareCalculator.format(widget.passengerWalletIntent)} сўм',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.blue.shade900,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _green.withValues(alpha: 0.3))),
            child: Column(children: [
              Text(widget.fareLocked ? '🔒 Қулфланган йўлкира' : '💰 Йўлкира',
                  style: const TextStyle(
                      fontSize: AppText.bodyMedium, color: Colors.grey)),
              const SizedBox(height: 4),
              Text('${FareCalculator.format(fare)} сўм',
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
              labelText: 'Мижоз берган нақд (сўм)',
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
            child: const Text('Орқага',
                style: TextStyle(color: Colors.grey))),
        ElevatedButton.icon(
          onPressed: () {
            final paid = int.tryParse(
                    _cashPaidCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ??
                fare;
            Navigator.of(context).pop((fare: fare, cashPaid: paid));
          },
          icon: const Icon(Icons.check_circle, size: 18),
          label: const Text('ЯКУНЛАШ'),
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
