import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../repositories/driver_repository.dart';
import 'celebration_dialog.dart';

/// Ҳайдовчи аризаси ТАСДИҚЛАНДИ — табрик (эга, 2026-10-31: конфетти, «янги иш бошланди»).
///
/// Ҳар телефон (+ тур маълум бўлса — `local` / `marshrut` / `intercity`) учун БИР МАРТА
/// ([CelebrationOnce]: `driver_approved_<телефон>[_<тур>]`). Ойна «Давом этиш» босилгунча кутади.
///
/// `true` — табрик кўрсатилди; `false` — кўрсатилмади (аввал кўрсатилган, телефон номаълум ёки
/// бу контекстда ойна хавфсиз очилмайди) — чақирувчи аввалги snack хабарини кўрсатади.
/// Хато/рад этишда чақирилмайди — фақат тасдиқ лаҳзасида.
Future<bool> showDriverApprovedCelebrationOnce(
  BuildContext context, {
  required String phone,
  String? taxiType,
}) async {
  final id = canonicalPhoneId(phone);
  if (id.length < 9 || !_canShowCelebration(context)) return false;
  final type = (taxiType ?? '').trim();
  final key = type.isEmpty ? 'driver_approved_$id' : 'driver_approved_${id}_$type';
  if (!await CelebrationOnce.claim(key)) return false;
  if (!context.mounted || !_canShowCelebration(context)) return false;
  await showCelebration(
    context,
    icon: Icons.local_taxi_rounded,
    title: context.tr('driver_request_approved_title'),
    subtitle: context.tr('driver_request_approved_sub'),
    buttonLabel: context.tr('celebration_continue'),
  );
  return true;
}

/// Ойна очиш мумкинми: контекст тирик, устида Navigator ва MaterialLocalizations бор
/// (push'дан келган `navigatorKey` контексти учун ҳам — акс ҳолда snack қолади).
bool _canShowCelebration(BuildContext context) =>
    context.mounted &&
    Navigator.maybeOf(context, rootNavigator: true) != null &&
    Localizations.of<MaterialLocalizations>(context, MaterialLocalizations) != null;

/// Admin tasdiqini kutayotgan haydovchi arizasi yuborilgach xabarlar.
Future<void> showDriverApplicationPendingFeedback(
  BuildContext context, {
  required DriverApplicationSubmitResult result,
  String resentMessageKey = 'driver_request_sent',
  Color? snackColor,
}) async {
  if (result.autoApproved || !context.mounted) return;

  final color = snackColor ?? Colors.orange.shade700;
  final messenger = ScaffoldMessenger.of(context);

  void showSnack(String message, {Duration? duration}) {
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: duration ?? const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Text(
          message,
          style: color == AppColors.button
              ? const TextStyle(color: AppColors.onPrimary)
              : null,
        ),
      ),
    );
  }

  if (result.isFirstSubmission) {
    showSnack(context.tr('driver_request_first_submitted'));
    await Future<void>.delayed(const Duration(milliseconds: 2800));
    if (!context.mounted) return;
    showSnack(
      context.tr('driver_request_review_soon'),
      duration: const Duration(seconds: 5),
    );
  } else {
    showSnack(context.tr(resentMessageKey));
  }
}

/// Avto-tasdiq yoki manual kutish — bitta joydan chaqirish.
Future<void> handleDriverApplicationSubmitResult(
  BuildContext context, {
  required DriverApplicationSubmitResult result,
  required VoidCallback onAutoApproved,
  String resentMessageKey = 'driver_request_sent',
  Color? pendingSnackColor,
}) async {
  if (result.autoApproved) {
    onAutoApproved();
    return;
  }
  await showDriverApplicationPendingFeedback(
    context,
    result: result,
    resentMessageKey: resentMessageKey,
    snackColor: pendingSnackColor ?? AppColors.button,
  );
}
