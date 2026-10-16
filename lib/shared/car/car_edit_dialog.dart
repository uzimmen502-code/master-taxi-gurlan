import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/theme/ava_tokens.dart';
import '../../core/utils/driver_car_prefill.dart';
import '../../repositories/user_repository.dart';

/// Автомобиль маълумотини таҳрирлаш ва ўчириш — ЯГОНА жой.
///
/// Аввал бу ойна Кабинет (профиль) экранининг ичида эди ва 4 та ҳайдовчи
/// оқими уни `ProfileScreen(autoOpenCarEdit)` орқали очарди. Энди Кабинетга
/// боғланмаган: ҳайдовчи панели ҳам, онбординг оқимлари ҳам шу ердан чақиради.
///
/// Маълумот `users/{uid}` да (`carModel` ва ҳ.к.) — уни «Мойни алмаштириш»
/// модули ҳам ўқийди, шунинг учун ўчириш матни шуни айтади.

/// Таҳрир ойнаси. Сақланса `true`, бекор қилинса `false`, хато бўлса `false`
/// (хато ҳақида хабар кўрсатилади). [driverFlow] — ойна ёпилмайди (онбординг:
/// автомобилсиз давом этиб бўлмайди) ва ихчамроқ.
Future<bool?> showCarEditDialog(
  BuildContext context, {
  required String uid,
  bool driverFlow = false,
  UserRepository? repository,
}) async {
  final repo = repository ?? UserRepository();
  final car = await repo.getCarInfo(uid);
  if (!context.mounted) return false;
  return showDialog<bool>(
    context: context,
    barrierDismissible: !driverFlow,
    builder: (ctx) => _CarEditDialog(
      uid: uid,
      initial: car,
      driverFlow: driverFlow,
      repo: repo,
    ),
  );
}

/// Контроллерлар шу ердаги `State`да: ойна ёпилиш анимацияси тугамасдан
/// `dispose` бўлиб қолмасин.
class _CarEditDialog extends StatefulWidget {
  const _CarEditDialog({
    required this.uid,
    required this.initial,
    required this.driverFlow,
    required this.repo,
  });

  final String uid;
  final Map<String, String>? initial;
  final bool driverFlow;
  final UserRepository repo;

  @override
  State<_CarEditDialog> createState() => _CarEditDialogState();
}

class _CarEditDialogState extends State<_CarEditDialog> {
  late final _model = TextEditingController(text: widget.initial?['carModel'] ?? '');
  late final _color = TextEditingController(text: widget.initial?['carColor'] ?? '');
  late final _plate = TextEditingController(text: widget.initial?['carPlate'] ?? '');
  late final _seats = TextEditingController(text: '$_initialSeats');

  int get _initialSeats {
    final stored = int.tryParse(widget.initial?['carSeats'] ?? '') ?? 0;
    return stored > 0 ? stored : 4;
  }

  bool _saving = false;

  @override
  void dispose() {
    _model.dispose();
    _color.dispose();
    _plate.dispose();
    _seats.dispose();
    super.dispose();
  }

  bool get _compact => widget.driverFlow;

  InputDecoration _decoration(String labelKey, {String? hint}) => InputDecoration(
        labelText: context.tr(labelKey),
        hintText: hint,
        isDense: _compact,
        contentPadding:
            _compact ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10) : null,
      );

  void _clampSeatsToModel() {
    final max = DriverCarPrefill.maxSeatsForModel(_model.text.trim());
    final parsed = int.tryParse(_seats.text.trim());
    if (parsed == null || parsed < 1) return;
    if (parsed > max) {
      _seats.text = '$max';
      _seats.selection = TextSelection.collapsed(offset: _seats.text.length);
    }
  }

  Future<void> _save() async {
    final model = _model.text.trim();
    final color = _color.text.trim();
    final plate = _plate.text.trim();
    final max = DriverCarPrefill.maxSeatsForModel(model);
    final parsed = int.tryParse(_seats.text.trim()) ?? 0;
    final seats = parsed.clamp(1, max);
    if (model.isEmpty || color.isEmpty || plate.isEmpty || parsed <= 0) return;
    if (_saving) return;
    setState(() => _saving = true);
    var ok = false;
    try {
      await widget.repo.saveCarInfo(
        uid: widget.uid,
        carModel: model,
        carColor: color,
        carPlate: plate,
        carSeats: seats,
      );
      ok = true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('error_generic'))),
        );
      }
    }
    if (mounted) Navigator.pop(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    final maxSeats = DriverCarPrefill.maxSeatsForModel(_model.text.trim());
    final gap = SizedBox(height: _compact ? 6 : 8);
    return AlertDialog(
      insetPadding:
          _compact ? const EdgeInsets.symmetric(horizontal: 20, vertical: 24) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(context.tr('car_info_edit')),
      contentPadding: _compact ? const EdgeInsets.fromLTRB(20, 12, 20, 0) : null,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _model,
              decoration: _decoration('car_model'),
              onChanged: (_) => setState(_clampSeatsToModel),
            ),
            gap,
            TextField(
              controller: _color,
              decoration: _decoration('car_color'),
            ),
            gap,
            TextField(
              controller: _plate,
              decoration: _decoration('car_plate'),
              textCapitalization: TextCapitalization.characters,
            ),
            gap,
            TextField(
              controller: _seats,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(1),
              ],
              decoration: _decoration('car_seats_label', hint: '1–$maxSeats'),
              onChanged: (_) => setState(_clampSeatsToModel),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(context.tr('cancel')),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: Text(context.tr('save')),
        ),
      ],
    );
  }
}

/// Тасдиқ сўраб автомобилни ўчиради. Ўчирилса `true`.
Future<bool> confirmAndDeleteCar(
  BuildContext context, {
  required String uid,
  UserRepository? repository,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(ctx.tr('car_delete_confirm_title')),
      content: Text(ctx.tr('car_delete_confirm_body')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.tr('cancel')),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ctx.tr('delete')),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    await (repository ?? UserRepository()).clearCarInfo(uid);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('error_generic'))),
      );
    }
    return false;
  }
  if (!context.mounted) return true;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(context.tr('car_deleted_success')),
    backgroundColor: AvaLight.ok,
  ));
  return true;
}
