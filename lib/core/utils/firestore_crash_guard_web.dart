// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'firestore_crash_detect.dart';

/// Firestore veb SDK "Unexpected state" bug'i otilganda sahifani avto-reload
/// qiladi. Klient buzilgach boshqa iloj yo'q — qayta yuklash uni tiklaydi.
void installFirestoreCrashGuard() {
  // 1. SDK ichidan otilgan JS xatolar.
  html.window.addEventListener('error', (event) {
    try {
      if (event is html.ErrorEvent &&
          isFatalFirestoreAssertion(event.message ?? '')) {
        _reload();
      }
    } catch (_) {}
  });
  html.window.addEventListener('unhandledrejection', (event) {
    try {
      final reason = '${(event as dynamic).reason}';
      if (isFatalFirestoreAssertion(reason)) _reload();
    } catch (_) {}
  });

  // 2. Dart zonasiga yetib kelgan xatolar (zaxira yo'l).
  final priorOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (isFatalFirestoreAssertion(details.exception)) {
      _reload();
      return;
    }
    priorOnError?.call(details);
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    if (isFatalFirestoreAssertion(error)) {
      _reload();
      return true;
    }
    return false;
  };
}

/// Loop oldini olish: 15 soniya ichida qayta reload qilmaymiz.
void _reload() {
  try {
    final store = html.window.sessionStorage;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = int.tryParse(store['fs_crash_reload_at'] ?? '') ?? 0;
    if (now - last < 15000) return;
    store['fs_crash_reload_at'] = '$now';
    html.window.location.reload();
  } catch (_) {}
}
