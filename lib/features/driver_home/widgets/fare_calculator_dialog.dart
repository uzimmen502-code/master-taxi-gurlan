import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
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
  bool _cashPaidEdited = false;

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
                color: selected ? AppColors.onPrimary : Colors.black87)),
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
    // Ҳайдовчи нақдни ўзи ўзгартирмагунча, у йўлкира билан бирга янгиланади
    // (аввал бир марта тўлдирилиб қоларди → км камайтирилса, сервер ортиқча
    // «қайтим» ҳисоблаб, ҳайдовчи ҳамёнидан йўловчига ўтказарди).
    if (!_cashPaidEdited) {
      final cashDefault = '${(fare - widget.passengerWalletIntent).clamp(0, fare)}';
      if (_cashPaidCtrl.text != cashDefault) _cashPaidCtrl.text = cashDefault;
    }
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        Icon(widget.fareLocked ? Icons.lock : Icons.calculate,
            color: AppColors.primaryText, size: 24),
        const SizedBox(width: 8),
        Text(widget.fareLocked
            ? context.tr('driver_map_locked_fare')
            : context.tr('fare_calc_title')),
      ]),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!widget.fareLocked) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(context.tr('fare_distance_label'),
                  style: const TextStyle(
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
            Align(
              alignment: Alignment.centerLeft,
              child: Text(context.tr('fare_wait_label'),
                  style: const TextStyle(
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
                  child: Text(
                      context.trMsg('fare_wait_value',
                          params: {'n': '$_waitMins'}),
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(fontWeight: FontWeight.bold))),
            ]),
            const Divider(height: 16),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _coefChip(context.tr('fare_coef_night'), _isNight,
                  (v) => setState(() => _isNight = v)),
              _coefChip(context.tr('fare_coef_urgent'), _isUrgent,
                  (v) => setState(() => _isUrgent = v)),
              _coefChip(context.tr('fare_coef_holiday'), _isHoliday,
                  (v) => setState(() => _isHoliday = v)),
              _coefChip(context.tr('fare_coef_rain'), _isRainy,
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
                context.trMsg('fare_passenger_wallet', params: {
                  'amount':
                      FareCalculator.format(widget.passengerWalletIntent),
                }),
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
                color: AvaLight.okSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _green.withValues(alpha: 0.3))),
            child: Column(children: [
              Text(
                  widget.fareLocked
                      ? context.tr('fare_locked_title')
                      : context.tr('fare_total_title'),
                  style: const TextStyle(
                      fontSize: AppText.bodyMedium, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(
                  context.trMsg('fare_amount_sum',
                      params: {'amount': FareCalculator.format(fare)}),
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryText)),
            ]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cashPaidCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.tr('fare_cash_given_label'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() => _cashPaidEdited = true),
          ),
          Builder(builder: (context) {
            // Ортиқча нақд — қайтим йўловчи ҳамёнига ўтказилади (settlement).
            // Ҳайдовчи нақд ҳам бериб юбормаслиги учун аниқ айтамиз.
            final paid = int.tryParse(
                    _cashPaidCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ??
                0;
            final due = (fare - widget.passengerWalletIntent).clamp(0, fare);
            if (paid <= due) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                context.trMsg('local_change_goes_wallet',
                    params: {'amount': FareCalculator.format(paid - due)}),
                style: const TextStyle(
                    fontSize: AppText.bodySmall,
                    fontWeight: FontWeight.w600,
                    color: Colors.deepOrange),
              ),
            );
          }),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('back'),
                style: const TextStyle(color: Colors.grey))),
        ElevatedButton.icon(
          onPressed: () {
            final paid = int.tryParse(
                    _cashPaidCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ??
                fare;
            Navigator.of(context).pop((fare: fare, cashPaid: paid));
          },
          icon: const Icon(Icons.check_circle, size: 18),
          label: Text(context.tr('fare_finish_btn')),
          style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: AppColors.onPrimary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
        ),
      ],
    );
  }
}
