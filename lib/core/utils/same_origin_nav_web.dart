// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Локалда user ↔ admin турли entry болганда user томондан ochilgan админ URL.
///
/// Масалан: `flutter run ... main.dart --web-port=8080` ва алоҳида терминалда
/// `flutter run ... main_admin.dart --web-port=5174 ...`.
/// Keyin user иловасида — `--dart-define=ADMIN_DEV_URL=http://localhost:5174/admin/`
const String _kAdminDevOverride = String.fromEnvironment('ADMIN_DEV_URL');

/// Локалда админ `/` да (`main_admin.dart` без `--base-href /admin/`) ochilganда
/// фойдаланувчи иловаси URL и — қайта юклашни чексиз админ қайтарmasлиги учун.
///
/// Масалан: `--dart-define=USER_DEV_URL=http://localhost:8080/`
const String _kUserDevOverride = String.fromEnvironment('USER_DEV_URL');

/// Тўлиқ саҳифани юклайди. Агар navigation қилинмаган булса `false` (faqat debug).
bool navigateSameOriginPath(String path) {
  final p = path.startsWith('/') ? path : '/$path';
  final adminOverride = _kAdminDevOverride.trim();
  final userOverride = _kUserDevOverride.trim();

  if (_isAdminPath(p) && adminOverride.isNotEmpty) {
    final target =
        adminOverride.endsWith('/') ? adminOverride : '$adminOverride/';
    html.window.location.assign(target);
    return true;
  }

  if (_isAdminPath(p) && adminOverride.isEmpty && kDebugMode) {
    debugPrint(
      '[Admin] /admin/ ҳозирги dev серверда user entry билан бир xil — '
      'алоҳида `lib/main_admin.dart` ochинг ва '
      '`--dart-define=ADMIN_DEV_URL=http://localhost:PORT/admin/` беринг.',
    );
  }

  final origin = html.window.location.origin;

  // Фойдаланувчи иловаси туб манзили (`/`).
  if (p == '/') {
    final pathname = html.window.location.pathname ?? '';
    // Firebase Hosting / `--base-href /admin/` — админ ҳар доим `/admin...` остида.
    if (pathname.startsWith('/admin')) {
      html.window.location.assign('$origin/');
      return true;
    }
    // Локал: админ ҳозир "/" да → қайта "/" юклаш шу админни қайта очади.
    if (userOverride.isNotEmpty) {
      html.window.location.assign(
        userOverride.endsWith('/') ? userOverride : '$userOverride/',
      );
      return true;
    }
    if (kDebugMode) {
      debugPrint(
        '[navigateSameOriginPath] Админ ҳозир "/" URL да ишлайди — бу тугма '
        'фойдаланувчи bundle ни очолмайди. Йечимлар: '
        '(1) `flutter run ... main_admin.dart --base-href /admin/` '
        '(портдан кейин `--web-port` билан); '
        '(2) ёки user иловасини алоҳида порта ochинг ва '
        '`--dart-define=USER_DEV_URL=http://localhost:PORT/` беринг.',
      );
      return false;
    }
    html.window.location.assign('$origin/');
    return true;
  }

  html.window.location.assign('$origin$p');
  return true;
}

bool _isAdminPath(String p) => p == '/admin' || p.startsWith('/admin/');
