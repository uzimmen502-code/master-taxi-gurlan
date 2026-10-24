import 'dart:async';
import 'dart:io' show SocketException;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/widgets.dart';

import '../l10n/l10n_extension.dart';

/// Foydalanuvchiga ko'rsatiladigan xato matni (CLAUDE.md §25: foydalanuvchiga —
/// tushunarli matn, diagnostika kodi esa faqat logga).
///
/// `catch (e)` ichida `Text('$e')` / `'Xatolik: $e'` / `e.message` ISHLATILMASIN —
/// ular `Exception: …`, `[cloud_firestore/permission-denied] …` kabi xom matnni
/// ekranga chiqaradi. Buning o'rniga:
///
/// ```dart
/// } catch (e) {
///   ScaffoldMessenger.of(context).showSnackBar(
///     SnackBar(content: Text(userErrorMessage(context, e))),
///   );
/// }
/// ```
///
/// Controller'larda (kontekst yo'q) — [userErrorKey] kalitini saqlang, ekranda
/// esa `context.trMsg(key)` bilan chiqaring.
///
/// [fallbackKey] — xato turi aniqlanmaganda (yoki `failed-precondition` kabi
/// umumiy kodda) ko'rsatiladigan, o'sha amalga xos l10n kaliti
/// (masalan `local_cancel_failed`). [byServerMessage] — server `HttpsError`
/// xabari (`insufficient_balance` kabi) → l10n kaliti xaritasi.
String userErrorMessage(
  BuildContext context,
  Object error, {
  String fallbackKey = 'err_unexpected',
  Map<String, String> byServerMessage = const {},
}) {
  return context.tr(
    userErrorKey(
      error,
      fallbackKey: fallbackKey,
      byServerMessage: byServerMessage,
    ),
  );
}

/// Xato → l10n kaliti (kontekstsiz; controller'lar uchun). Xom xato matni
/// hech qachon qaytarilmaydi — faqat `debugPrint` ga yoziladi.
String userErrorKey(
  Object error, {
  String fallbackKey = 'err_unexpected',
  Map<String, String> byServerMessage = const {},
}) {
  // Ichki diagnostika — faqat log; foydalanuvchiga chiqmaydi.
  debugPrint('[userError] ${error.runtimeType}: $error');
  return _keyFor(error, fallbackKey, byServerMessage);
}

/// Faqat xato KODI ma'lum bo'lganda (masalan `DemandException.code`):
/// callable kodi -> l10n kaliti. Server matni hech qachon ishlatilmaydi.
String userErrorKeyFromCode(
  String code, {
  String fallbackKey = 'err_unexpected',
}) {
  debugPrint('[userError] code=$code');
  return _keyForCode(code, fallbackKey);
}

/// Sof tanlov (log yo'q) — testlar uchun.
@visibleForTesting
String userErrorKeyPure(
  Object error, {
  String fallbackKey = 'err_unexpected',
  Map<String, String> byServerMessage = const {},
}) =>
    _keyFor(error, fallbackKey, byServerMessage);

String _keyFor(
  Object error,
  String fallbackKey,
  Map<String, String> byServerMessage,
) {
  if (error is FirebaseFunctionsException) {
    final byMsg = byServerMessage[error.message?.trim() ?? ''];
    if (byMsg != null) return byMsg;
    return _keyForCode(error.code, fallbackKey);
  }
  if (error is FirebaseException) {
    return _keyForCode(error.code, fallbackKey);
  }
  if (error is TimeoutException) return 'err_timeout';
  if (error is SocketException) return 'err_network';
  return fallbackKey;
}

String _keyForCode(String rawCode, String fallbackKey) {
  switch (rawCode.trim().toLowerCase()) {
    case 'unavailable':
    case 'network-request-failed':
      return 'err_network';
    case 'deadline-exceeded':
    case 'timeout':
      return 'err_timeout';
    case 'resource-exhausted':
      return 'err_too_many';
    case 'unauthenticated':
      return 'err_auth';
    case 'permission-denied':
      return 'err_permission';
    case 'not-found':
      return 'err_not_found';
    case 'invalid-argument':
    case 'out-of-range':
      return 'err_invalid';
    case 'internal':
    case 'unknown':
    case 'data-loss':
    case 'unimplemented':
      return 'err_server';
    case 'failed-precondition':
    case 'aborted':
    case 'already-exists':
      // Domen xatosi: o'sha amalga xos matn bo'lsa — shuni; bo'lmasa umumiy.
      return fallbackKey == 'err_unexpected' ? 'err_conflict' : fallbackKey;
    default:
      return fallbackKey;
  }
}
