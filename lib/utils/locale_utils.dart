import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Qurilma va saqlangan til — Lotin/Kirill o‘zbek, rus.
class LocaleUtils {
  static const String _savedLanguageKey = 'saved_language';
  static const String _savedScriptKey = 'saved_script';
  static const String followDeviceSentinel = 'device';

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
    return savedLocaleFrom(prefs);
  }

  /// Sinxron: allaqachon yuklangan prefs'dan saqlangan qo'lda tanlov.
  /// Eski/boshqa ko'rinishdagi qiymatlar (`uz_Latn`, `uz-Cyrl`, `ru_RU`)
  /// ham normallashtiriladi. Tanlov yo'q yoki qurilma sentinel → null.
  static Locale? savedLocaleFrom(SharedPreferences prefs) {
    final raw = prefs.getString(_savedLanguageKey)?.trim();
    var scriptCode = prefs.getString(_savedScriptKey)?.trim();

    if (raw == null || raw.isEmpty) return null;
    if (raw == followDeviceSentinel) return null;
    final parts = raw.split(RegExp('[_-]'));
    final languageCode = parts.first.toLowerCase();
    if (parts.length > 1 && (scriptCode == null || scriptCode.isEmpty)) {
      scriptCode = parts[1];
    }
    if (languageCode == 'ru') return ru;
    if (languageCode == 'uz') {
      if (scriptCode?.toLowerCase() == 'latn') return uzLatn;
      return uzCyrl;
    }
    return Locale(languageCode, scriptCode);
  }

  /// Sinxron `effectiveLocale` — saqlangan tanlov yoki qurilma tili.
  /// Ishga tushishda `MaterialApp` locale'i null bo'lmasligi uchun.
  static Locale effectiveLocaleFrom(SharedPreferences prefs) {
    final saved = savedLocaleFrom(prefs);
    if (saved != null) return _normalize(saved);
    return resolveFromDevice();
  }

  /// `prefs.clear()` o'rniga: hamma kalitni o'chiradi, lekin til tanlovi
  /// (`saved_language`/`saved_script`) saqlanadi — chiqishda (logout) til
  /// qurilma tiliga qaytib ketmasligi uchun (ega 2026-11-19).
  static Future<void> clearPrefsKeepingLanguage(
      SharedPreferences prefs) async {
    final language = prefs.getString(_savedLanguageKey);
    final script = prefs.getString(_savedScriptKey);
    await prefs.clear();
    if (language != null) {
      await prefs.setString(_savedLanguageKey, language);
    }
    if (script != null) {
      await prefs.setString(_savedScriptKey, script);
    }
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

  static Future<void> saveFollowDeviceChoice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedLanguageKey, followDeviceSentinel);
    await prefs.remove(_savedScriptKey);
  }

  static Future<void> clearSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedLanguageKey);
    await prefs.remove(_savedScriptKey);
  }

  /// Foydalanuvchi aniq til tanlaganmi (qurilma sentinel emas).
  static Future<bool> hasManualLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_savedLanguageKey);
    if (code == null) return false;
    return code != followDeviceSentinel;
  }

  /// Birinchi til ekrani o'tkazilganmi (qattiq til yoki qurilma sentinel).
  static Future<bool> hasLanguageSetup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_savedLanguageKey);
  }

  /// Saqlangan til yoki (saqlanmagan bo'lsa) qurilma tili — hech qachon avtomatik saqlamaydi.
  static Future<Locale> effectiveLocale() async {
    final prefs = await SharedPreferences.getInstance();
    return effectiveLocaleFrom(prefs);
  }

  static Future<Locale> getInitialLocale() async => effectiveLocale();

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

  /// Ilova matn kodi: `uz_Cyrl` / `uz_Latn` / `ru` (assets/lang fayl nomi).
  static String contentLangCode(Locale locale) => switch (locale.languageCode) {
        'ru' => 'ru',
        'uz' => locale.scriptCode == 'Latn' ? 'uz_Latn' : 'uz_Cyrl',
        _ => 'uz_Cyrl',
      };

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
