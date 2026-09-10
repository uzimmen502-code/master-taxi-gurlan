import 'package:ava_gurlan/core/l10n/locale_notifier.dart';
import 'package:ava_gurlan/utils/locale_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regressiya: `LocaleNotifier.setLocale()` — Profildan til almashtirish
/// yo'lining (`lib/core/l10n/language_picker_sheet.dart:89` →
/// `lib/features/profile/widgets/language_settings_tile.dart:44`,
/// shuningdek `lib/features/intercity_taxi/passenger/screens/
/// intercity_taxi_screen.dart:453`) asosida turadigan metod — hamon
/// DARHOL persist qilishini tasdiqlaydi. `language_select_screen.dart`
/// (guest onboarding)dagi preview/confirm tuzatishi bu metodning o'ziga
/// tegmagan, faqat o'sha ekran ICHIDAGI chaqiruvlarni yangi, alohida
/// `previewLocale()` metodiga o'tkazgan — bu test aynan shu farqni
/// (setLocale = darhol persist, previewLocale = persistsiz) ko'rsatadi.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LocaleNotifier.setLocale — Profil/language_picker_sheet yo\'li', () {
    test(
        'chaqirilganda saved_language SharedPreferences\'ga DARHOL '
        'yoziladi (asl, o\'zgarmagan xatti-harakat)', () async {
      final notifier = LocaleNotifier();

      await notifier.setLocale(LocaleUtils.ru);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('saved_language'), 'ru');
      expect(notifier.locale, LocaleUtils.ru);
    });

    test('uz_Latn tanlansa til + skript ikkalasi ham darhol saqlanadi',
        () async {
      final notifier = LocaleNotifier();

      await notifier.setLocale(LocaleUtils.uzLatn);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('saved_language'), 'uz');
      expect(prefs.getString('saved_script'), 'Latn');
    });

    test(
        'ketma-ket ikki marta chaqirilsa (masalan foydalanuvchi Profilda '
        'tilni ikki marta almashtirsa) — har safar darhol qayta yoziladi',
        () async {
      final notifier = LocaleNotifier();

      await notifier.setLocale(LocaleUtils.uzCyrl);
      var prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('saved_language'), 'uz');
      expect(prefs.getString('saved_script'), 'Cyrl');

      await notifier.setLocale(LocaleUtils.ru);
      prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('saved_language'), 'ru');
      // Uz-ga xos skript kaliti rus tiliga o'tganda tozalanadi.
      expect(prefs.getString('saved_script'), isNull);
    });
  });

  group('LocaleNotifier.previewLocale — faqat guest intro/til ekrani uchun', () {
    test(
        'chaqirilganda SharedPreferences\'ga HECH NARSA yozmaydi — faqat '
        'jonli (in-memory) holatni yangilaydi', () async {
      final notifier = LocaleNotifier();

      notifier.previewLocale(LocaleUtils.ru);

      expect(notifier.locale, LocaleUtils.ru);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('saved_language'), isFalse);
    });
  });
}
