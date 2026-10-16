import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/theme/ava_tokens.dart';
import '../../repositories/driver_repository.dart';
import '../../repositories/marshrut_driver_repository.dart';
import '../../repositories/rides_repository.dart';
import '../../services/driver_force_leave_service.dart';

/// Ҳайдовчи панелидаги «Сменани тугатиш» ва «Ҳайдовчиликдан чиқиш».
///
/// Иккови ҳам аввал Кабинет (профиль) экранида эди; мантиқ ўзгармади — фақат
/// жойи (эга қарори, 2026-10-16). Матнлар ва тасдиқлар аввалгидек.

Future<bool> _confirm(
  BuildContext context, {
  required String titleKey,
  required String bodyKey,
  required String okKey,
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(ctx.tr(titleKey)),
      content: Text(ctx.tr(bodyKey)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.tr('cancel')),
        ),
        ElevatedButton(
          style: danger
              ? ElevatedButton.styleFrom(backgroundColor: Colors.red)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ctx.tr(okKey)),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Смена тугатиш: маршрут ва маҳаллий ҳайдовчи офлайн бўлади, ҳуқуқ қолади.
Future<void> endDriverShiftWithConfirm(
  BuildContext context, {
  required String uid,
  required DriverRepository driverRepo,
  MarshrutDriverRepository? marshrutRepo,
}) async {
  if (!await _confirm(
    context,
    titleKey: 'end_shift_confirm_title',
    bodyKey: 'end_shift_confirm_body',
    okKey: 'end_shift',
  )) {
    return;
  }
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final errText = context.tr('shift_end_error');
  final okText = context.tr('shift_ended_success');
  try {
    await (marshrutRepo ?? MarshrutDriverRepository()).goOffline(uid);
    await driverRepo.goOffline(uid);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('driver_is_online', false);
    messenger.showSnackBar(SnackBar(
      content: Text(okText),
      backgroundColor: Colors.grey.shade700,
    ));
  } catch (_) {
    messenger.showSnackBar(SnackBar(
      content: Text(errText),
      backgroundColor: Colors.red,
    ));
  }
}

/// «Ҳайдовчиликдан чиқиш»: сафарлар бекор, эълонлар ўчади, офлайн, роль
/// йўловчига қайтади (тасдиқ сақланади). Аввалги Кабинет оқими билан бир хил.
Future<void> leaveDriverModeWithConfirm(
  BuildContext context, {
  required RidesRepository ridesRepo,
}) async {
  if (!await _confirm(
    context,
    titleKey: 'leave_driver_permanent_title',
    bodyKey: 'leave_driver_permanent_body',
    okKey: 'confirm',
    danger: true,
  )) {
    return;
  }
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final okText = context.tr('leave_driver_force_success');
  final errText = context.tr('error_generic');
  try {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    await DriverForceLeaveService(ridesRepo: ridesRepo)
        .forceLeaveMarshrutDriver(userPhone: phone);
    messenger.showSnackBar(SnackBar(
      content: Text(okText),
      backgroundColor: AvaLight.ok,
    ));
  } catch (_) {
    messenger.showSnackBar(SnackBar(
      content: Text(errText),
      backgroundColor: Colors.red,
    ));
  }
}
