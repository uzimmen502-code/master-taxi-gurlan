import 'package:ava_gurlan/core/l10n/locale_notifier.dart';
import 'package:ava_gurlan/utils/locale_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regressiya (ega 2026-11-19): profildan chiqishda (`logout`) `prefs.clear()`
/// `saved_language`/`saved_script` ni ham o'chirib, til qurilma tiliga qaytib
/// ketardi. Endi `LocaleUtils.clearPrefsKeepingLanguage` til kalitlarini
/// saqlab qoladi; ishga tushishda locale sinxron hisoblanadi (null oyna yo'q).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('clearPrefsKeepingLanguage — logout tilni saqlaydi', () {
    test('qo\'lda tanlangan uz_Latn saqlanadi, boshqa kalitlar o\'chadi',
        () async {
      SharedPreferences.setMockInitialValues({
        'saved_language': 'uz',
        'saved_script': 'Latn',
        'userId': 'u1',
        'role': 'courier',
        'onboarding_done': true,
      });
      final prefs = await SharedPreferences.getInstance();
      await LocaleUtils.clearPrefsKeepingLanguage(prefs);
      expect(prefs.getString('saved_language'), 'uz');
      expect(prefs.getString('saved_script'), 'Latn');
      expect(prefs.containsKey('userId'), isFalse);
      expect(prefs.containsKey('role'), isFalse);
      expect(prefs.containsKey('onboarding_done'), isFalse);
      expect(await LocaleUtils.getSavedLocale(), LocaleUtils.uzLatn);
    });

    test('ru (script yo\'q) saqlanadi, saved_script paydo bo\'lmaydi',
        () async {
      SharedPreferences.setMockInitialValues(
          {'saved_language': 'ru', 'x': 1});
      final prefs = await SharedPreferences.getInstance();
      await LocaleUtils.clearPrefsKeepingLanguage(prefs);
      expect(prefs.getString('saved_language'), 'ru');
      expect(prefs.containsKey('saved_script'), isFalse);
      expect(prefs.containsKey('x'), isFalse);
    });

    test('qurilma sentinel ham saqlanadi', () async {
      SharedPreferences.setMockInitialValues(
          {'saved_language': LocaleUtils.followDeviceSentinel});
      final prefs = await SharedPreferences.getInstance();
      await LocaleUtils.clearPrefsKeepingLanguage(prefs);
      expect(prefs.getString('saved_language'),
          LocaleUtils.followDeviceSentinel);
    });

    test('til tanlanmagan bo\'lsa — hech narsa yozilmaydi (chegara)',
        () async {
      SharedPreferences.setMockInitialValues({'userId': 'u1'});
      final prefs = await SharedPreferences.getInstance();
      await LocaleUtils.clearPrefsKeepingLanguage(prefs);
      expect(prefs.getKeys(), isEmpty);
    });
  });

  group('savedLocaleFrom — normalizatsiya', () {
    Future<Locale?> saved(Map<String, Object> v) async {
      SharedPreferences.setMockInitialValues(v);
      final prefs = await SharedPreferences.getInstance();
      return LocaleUtils.savedLocaleFrom(prefs);
    }

    test('eski "uz_Latn" qiymati → uzLatn', () async {
      expect(await saved({'saved_language': 'uz_Latn'}), LocaleUtils.uzLatn);
    });
    test('eski "uz_Cyrl" qiymati → uzCyrl', () async {
      expect(await saved({'saved_language': 'uz_Cyrl'}), LocaleUtils.uzCyrl);
    });
    test('"uz-Latn" (chiziqcha) → uzLatn', () async {
      expect(await saved({'saved_language': 'uz-Latn'}), LocaleUtils.uzLatn);
    });
    test('uz + Latn → uzLatn; uz yolg\'iz → uzCyrl', () async {
      expect(await saved({'saved_language': 'uz', 'saved_script': 'Latn'}),
          LocaleUtils.uzLatn);
      expect(await saved({'saved_language': 'uz'}), LocaleUtils.uzCyrl);
    });
    test('ru_RU → ru', () async {
      expect(await saved({'saved_language': 'ru_RU'}), LocaleUtils.ru);
    });
    test('yo\'q yoki sentinel → null', () async {
      expect(await saved({}), isNull);
      expect(await saved({'saved_language': 'device'}), isNull);
    });
    test('getSavedLocale ham normalizatsiya qiladi', () async {
      SharedPreferences.setMockInitialValues({'saved_language': 'uz_Latn'});
      expect(await LocaleUtils.getSavedLocale(), LocaleUtils.uzLatn);
    });
  });

  group('LocaleNotifier boshlang\'ich qiymati — null oyna yo\'q', () {
    test('initialLocale berilsa — init kutilmasdan locale tayyor', () {
      final n = LocaleNotifier(initialLocale: LocaleUtils.uzLatn);
      expect(n.locale, LocaleUtils.uzLatn);
    });

    test('effectiveLocaleFrom: saqlangan qo\'lda tanlov ustun', () async {
      SharedPreferences.setMockInitialValues(
          {'saved_language': 'uz', 'saved_script': 'Latn'});
      final prefs = await SharedPreferences.getInstance();
      expect(LocaleUtils.effectiveLocaleFrom(prefs), LocaleUtils.uzLatn);
    });

    test('effectiveLocaleFrom: tanlov yo\'q → hech qachon null emas', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(LocaleUtils.effectiveLocaleFrom(prefs), isNotNull);
    });

    test('init() saqlangan tilni o\'zgartirmaydi', () async {
      SharedPreferences.setMockInitialValues({'saved_language': 'ru'});
      final n = LocaleNotifier(initialLocale: LocaleUtils.ru);
      await n.init();
      expect(n.locale, LocaleUtils.ru);
      n.dispose();
    });
  });
}
