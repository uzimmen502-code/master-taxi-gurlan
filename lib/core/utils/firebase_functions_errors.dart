import 'package:cloud_functions/cloud_functions.dart';

import 'user_error.dart';

/// Onboarding (telefon / qurilma tasdig'i) callable xatolari -> l10n kaliti.
///
/// Umumiy xatolar (tarmoq, vaqt, limit, server) [userErrorKey] bilan bir xil;
/// faqat tasdiq kodi va qurilma bog'lash oqimiga xos uch kod alohida matn oladi.
/// Server `message` matni (lotincha / dasturchi matni) HECH QACHON ko'rsatilmaydi
/// (CLAUDE.md §25) — natija kalit, ekran uni `context.tr` bilan chiqaradi.
String onboardingErrorKey(FirebaseFunctionsException e) {
  switch (e.code.trim().toLowerCase()) {
    case 'not-found':
      return 'ob_err_code_request_not_found';
    case 'permission-denied':
      return 'ob_err_code_wrong';
    case 'failed-precondition':
      return 'ob_err_device_mismatch';
    default:
      return userErrorKey(e);
  }
}
