import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/locale_utils.dart';

/// Repository va push matnlari uchun kontekstsiz tarjima.
///
/// Foydalanuvchi tanlagan til (`SharedPreferences`) bo'yicha `assets/lang/*.json`
/// dan o'qiladi.
class OfflineL10n {
  OfflineL10n._();

  static Locale? _cachedLocale;
  static Map<String, String>? _strings;

  static Future<String> tr(String key) async {
    final locale = await LocaleUtils.getInitialLocale();
    await _ensureLoaded(locale);
    return _strings![key] ?? key;
  }

  static Future<void> _ensureLoaded(Locale locale) async {
    if (_strings != null && _cachedLocale == locale) return;
    _cachedLocale = locale;

    final langCode = switch (locale.languageCode) {
      'ru' => 'ru',
      'uz' => locale.scriptCode == 'Latn' ? 'uz_Latn' : 'uz_Cyrl',
      _ => 'uz_Cyrl',
    };

    try {
      final raw = await rootBundle.loadString('assets/lang/$langCode.json');
      final map = json.decode(raw) as Map<String, dynamic>;
      _strings = map.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      _strings = const {};
    }
  }
}
