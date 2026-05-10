import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleUtils {
  static const String _savedLanguageKey = 'saved_language';
  static const String _savedScriptKey = 'saved_script';

  // Телефон тили ва алифбосини аниқлаш
  static Future<Locale> getSystemLocale() async {
    String systemLanguage = Platform.localeName;

    debugPrint("Система тили: $systemLanguage");

    // Ўзбек тилини текшириш (лотин ёки кирилл)
    if (systemLanguage.toLowerCase().contains('uz')) {
      // Кирилл алифбосини аниқлаш
      if (systemLanguage.toLowerCase().contains('cyrillic') ||
          systemLanguage.toLowerCase().contains('cyrl') ||
          systemLanguage.toLowerCase().contains('uz_uz@cyrillic')) {
        return const Locale('uz', 'Cyrl');  // Ўзбек (Кирилл)
      } else {
        return const Locale('uz', 'Latn');  // Ўзбек (Лотин)
      }
    }

    // Рус тили (кирилл)
    if (systemLanguage.toLowerCase().contains('ru')) {
      return const Locale('ru', 'RU');
    }

    // Инглиз тили (лотин)
    if (systemLanguage.toLowerCase().contains('en')) {
      return const Locale('en', 'US');
    }

    // Стандарт (Ўзбек Лотин)
    return const Locale('uz', 'Latn');
  }

  // Сақланган тилни ўқиш
  static Future<Locale?> getSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final String? languageCode = prefs.getString(_savedLanguageKey);
    final String? scriptCode = prefs.getString(_savedScriptKey);

    if (languageCode != null) {
      if (scriptCode != null) {
        return Locale(languageCode, scriptCode);
      }
      return Locale(languageCode);
    }
    return null;
  }

  // Тилни сақлаш
  static Future<void> saveLocale(Locale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedLanguageKey, locale.languageCode);
    if (locale.scriptCode != null) {
      await prefs.setString(_savedScriptKey, locale.scriptCode!);
    }
  }

  // Фойдаланувчи танлаган тилни олиш (ёки систем автоматик)
  static Future<Locale> getInitialLocale() async {
    Locale? savedLocale = await getSavedLocale();
    if (savedLocale != null) {
      debugPrint("Сақланган тил: ${savedLocale.languageCode}_${savedLocale.scriptCode}");
      return savedLocale;
    }

    Locale systemLocale = await getSystemLocale();
    debugPrint("Телефон тилидан аниқланди: ${systemLocale.languageCode}_${systemLocale.scriptCode}");
    return systemLocale;
  }

  // Алифбосни текшириш (лотин ёки кирилл)
  static bool isCyrillic(Locale locale) {
    return locale.scriptCode == 'Cyrl' || locale.languageCode == 'ru';
  }

  static bool isLatin(Locale locale) {
    return locale.scriptCode == 'Latn' || locale.languageCode == 'en';
  }

  // Текстни алифбога мослаш (агар керак бўлса)
  static String translateText(String latinText, String cyrillicText, Locale locale) {
    if (isCyrillic(locale)) {
      return cyrillicText;
    }
    return latinText;
  }
}