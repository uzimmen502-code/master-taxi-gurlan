import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Qurilma va saqlangan til — Lotin/Kirill o‘zbek, rus.
class LocaleUtils {
  static const String _savedLanguageKey = 'saved_language';
  static const String _savedScriptKey = 'saved_script';

  static const Locale uzCyrl =
      Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Cyrl');
  static const Locale uzLatn =
      Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Latn');
  static const Locale ru = Locale('ru');

  static List<Locale> get supportedAppLocales => [uzCyrl, uzLatn, ru];

  /// Flutter `platformDispatcher` yoki `Platform.localeName` dan locale.
  static Locale resolveFromDevice([Locale? device]) {
    final d = device ?? WidgetsBinding.instance.platformDispatcher.locale;
    final lc = d.languageCode.toLowerCase();
    final sc = d.scriptCode?.toLowerCase();

    if (lc == 'ru') return ru;

    if (lc == 'uz') {
      if (sc == 'latn') return uzLatn;
      if (sc == 'cyrl') return uzCyrl;
      final country = (d.countryCode ?? '').toUpperCase();
      if (country == 'UZ') return uzCyrl;
      return uzLatn;
    }

    if (!kIsWeb) {
      final name = Platform.localeName.toLowerCase();
      if (name.contains('ru')) return ru;
      if (name.contains('uz')) {
        if (name.contains('cyrillic') ||
            name.contains('cyrl') ||
            name.contains('@cyrillic')) {
          return uzCyrl;
        }
        return uzLatn;
      }
    }

    return uzCyrl;
  }

  static Future<Locale> getSystemLocale() async =>
      resolveFromDevice();

  static Future<Locale?> getSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString(_savedLanguageKey);
    final scriptCode = prefs.getString(_savedScriptKey);

    if (languageCode == null) return null;
    if (languageCode == 'ru') return ru;
    if (languageCode == 'uz') {
      if (scriptCode == 'Latn') return uzLatn;
      return uzCyrl;
    }
    return Locale(languageCode, scriptCode);
  }

  static Future<void> saveLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedLanguageKey, locale.languageCode);
    if (locale.languageCode == 'uz' && locale.scriptCode != null) {
      await prefs.setString(_savedScriptKey, locale.scriptCode!);
    } else {
      await prefs.remove(_savedScriptKey);
    }
  }

  static Future<Locale> getInitialLocale() async {
    final saved = await getSavedLocale();
    if (saved != null) return _normalize(saved);
    final system = await getSystemLocale();
    await saveLocale(system);
    return system;
  }

  static Locale _normalize(Locale locale) {
    if (locale.languageCode == 'ru') return ru;
    if (locale.languageCode == 'uz') {
      if (locale.scriptCode == 'Latn') return uzLatn;
      return uzCyrl;
    }
    return resolveFromDevice(locale);
  }

  static Locale? localeResolutionCallback(
    Locale? locale,
    Iterable<Locale> supportedLocales,
  ) {
    final resolved = _normalize(locale ?? resolveFromDevice());
    for (final s in supportedLocales) {
      if (s.languageCode == resolved.languageCode &&
          (s.scriptCode == null ||
              s.scriptCode == resolved.scriptCode ||
              resolved.scriptCode == null)) {
        return s;
      }
    }
    return uzCyrl;
  }

  static bool isCyrillic(Locale locale) =>
      locale.scriptCode == 'Cyrl' || locale.languageCode == 'ru';

  static bool isLatin(Locale locale) => locale.scriptCode == 'Latn';

  static String translateText(
    String latinText,
    String cyrillicText,
    Locale locale,
  ) {
    if (isCyrillic(locale)) return cyrillicText;
    return latinText;
  }
}
