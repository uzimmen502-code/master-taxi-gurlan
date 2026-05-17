import 'package:flutter/material.dart';

/// Ҳайдовчи режимига **биринчи марта** ўтаётганда автомобиль маълумотларини
/// йиғадиган diалог.
///
/// Қайтариш қиймати:
///   - `DriverOnboardingResult` — фойдаланувчи 3 та майдонни тўлдириб,
///     "Сақлаб давом этиш" тугмасини босган бўлса.
///   - `null` — "Бекор қилиш" ёки orqaga қайтган бўлса.
///
/// Кейинги сафар [LocalTaxiScreen._onDriverTap] SharedPreferences'дан мавжуд
/// `car_model + car_plate`ни топса — бу диалогни кўрсатмай туриб тўғридан-тўғри
/// `master_taxi_driver` ташқи иловасини deep link билан очaди.
Future<DriverOnboardingResult?> showDriverAppPromoDialog(
  BuildContext context, {
  String initialModel = '',
  String initialColor = '',
  String initialPlate = '',
}) {
  return showDialog<DriverOnboardingResult>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => _DriverOnboardingDialog(
      initialModel: initialModel,
      initialColor: initialColor,
      initialPlate: initialPlate,
    ),
  );
}

/// Diалогдан қайтариладиган маълумотлар.
class DriverOnboardingResult {
  const DriverOnboardingResult({
    required this.model,
    required this.color,
    required this.plate,
  });

  final String model;
  final String color;
  final String plate;
}

class _DriverOnboardingDialog extends StatefulWidget {
  const _DriverOnboardingDialog({
    required this.initialModel,
    required this.initialColor,
    required this.initialPlate,
  });

  final String initialModel;
  final String initialColor;
  final String initialPlate;

  static const Color _orange = Color(0xFFF57F17);
  static const Color _green = Color(0xFF2E7D32);

  @override
  State<_DriverOnboardingDialog> createState() =>
      _DriverOnboardingDialogState();
}

class _DriverOnboardingDialogState extends State<_DriverOnboardingDialog> {
  late final TextEditingController _modelCtrl;
  late final TextEditingController _colorCtrl;
  late final TextEditingController _plateCtrl;

  @override
  void initState() {
    super.initState();
    _modelCtrl = TextEditingController(text: widget.initialModel);
    _colorCtrl = TextEditingController(text: widget.initialColor);
    _plateCtrl = TextEditingController(text: widget.initialPlate);
  }

  @override
  void dispose() {
    _modelCtrl.dispose();
    _colorCtrl.dispose();
    _plateCtrl.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _modelCtrl.text.trim().isNotEmpty &&
      _colorCtrl.text.trim().isNotEmpty &&
      _plateCtrl.text.trim().isNotEmpty;

  void _onSubmit() {
    if (!_isValid) return;
    Navigator.of(context).pop(
      DriverOnboardingResult(
        model: _modelCtrl.text.trim(),
        color: _colorCtrl.text.trim(),
        plate: _plateCtrl.text.trim().toUpperCase(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _hero(),
                const SizedBox(height: 18),
                _carForm(),
                const SizedBox(height: 18),
                _submitButton(),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                  ),
                  child: const Text('Бекор қилиш'),
                ),
              ]),
        ),
      ),
    );
  }

  Widget _hero() {
    return Column(children: [
      Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              _DriverOnboardingDialog._orange,
              Color(0xFFFFB300),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _DriverOnboardingDialog._orange.withOpacity(0.3),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(Icons.local_taxi, color: Colors.white, size: 32),
      ),
      const SizedBox(height: 12),
      const Text(
        'Ҳайдовчи режими',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 4),
      Text(
        'Илк маротаба — автомобилингиз ҳақида қисқа маълумот киритинг',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
    ]);
  }

  Widget _carForm() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _field(
        controller: _modelCtrl,
        label: 'Автомобиль русуми',
        hint: 'Масалан: Cobalt, Nexia, Damas',
        icon: Icons.directions_car,
      ),
      const SizedBox(height: 10),
      _field(
        controller: _colorCtrl,
        label: 'Ранги',
        hint: 'Масалан: Оқ, Қора, Кумушранг',
        icon: Icons.palette_outlined,
      ),
      const SizedBox(height: 10),
      _field(
        controller: _plateCtrl,
        label: 'Давлат рақами',
        hint: '01 A 123 BC',
        icon: Icons.confirmation_number_outlined,
        textCapitalization: TextCapitalization.characters,
      ),
    ]);
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
  }) {
    return TextField(
      controller: controller,
      textCapitalization: textCapitalization,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        prefixIcon: Icon(icon,
            size: 18, color: _DriverOnboardingDialog._green),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
              color: _DriverOnboardingDialog._green, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  Widget _submitButton() {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _isValid ? _onSubmit : null,
        icon: const Icon(Icons.arrow_forward, size: 18),
        label: const Text('Сақлаб давом этиш',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: _DriverOnboardingDialog._green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
