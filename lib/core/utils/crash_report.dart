import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Vaqtinchalik tarmoq xatosimi (ilovani yiqitmaydi, kodda bug emas):
/// Firestore `unavailable` / `deadline-exceeded`, Storage/Auth tarmoq
/// xatolari, socket/HTTP uzilishlari. `permission-denied` va boshqalar —
/// YO'Q (ular haqiqiy bug, fatal bo'lib ko'rinishi kerak).
bool isTransientNetworkError(Object error) {
  if (error is FirebaseException) {
    return const {
      'unavailable',
      'deadline-exceeded',
      'network-request-failed',
      'retry-limit-exceeded',
    }.contains(error.code);
  }
  // dart:io'ni import qilmaslik uchun (veb) tur nomi bo'yicha.
  return const {'SocketException', 'ClientException', 'HttpException'}
      .contains(error.runtimeType.toString());
}

/// Play Vitals + Firebase Crashlytics. Web — no-op.
class CrashReport {
  CrashReport._();

  static Future<void> nonFatal(
    Object error,
    StackTrace stack, {
    String? reason,
    Map<String, Object> keys = const {},
  }) async {
    debugPrint('[CrashReport] ${reason ?? error}');
    if (kIsWeb) return;
    try {
      final crash = FirebaseCrashlytics.instance;
      for (final e in keys.entries) {
        await crash.setCustomKey(e.key, e.value);
      }
      await crash.recordError(error, stack, reason: reason, fatal: false);
    } catch (e) {
      debugPrint('[CrashReport] send $e');
    }
  }
}
