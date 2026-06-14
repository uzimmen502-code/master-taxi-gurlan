import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/theme/app_theme.dart';
import '../../repositories/driver_repository.dart';

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
        content: Text(message),
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
