import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

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
