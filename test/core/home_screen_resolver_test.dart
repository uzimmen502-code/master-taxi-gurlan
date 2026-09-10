import 'package:ava_gurlan/core/navigation/home_screen_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveHomeScreenKind', () {
    test('1) til hali tanlanmagan — har doim LanguageSelectScreen', () {
      expect(
        resolveHomeScreenKind(
          languageSelected: false,
          isReturningUser: false,
          hasFirebaseAuth: false,
          isAnonymousAuth: false,
        ),
        HomeScreenKind.languageSelect,
      );
    });

    test(
        '2) birinchi ochilish: til tanlangan, hech qanday sessiya yo\'q '
        '— GuestIntroScreen', () {
      expect(
        resolveHomeScreenKind(
          languageSelected: true,
          isReturningUser: false,
          hasFirebaseAuth: false,
          isAnonymousAuth: false,
        ),
        HomeScreenKind.guestIntro,
      );
    });

    test(
        '3) qaytgan anonim (guest) foydalanuvchi — intro qayta '
        'ko\'rsatilmaydi, to\'g\'ridan-to\'g\'ri Home', () {
      expect(
        resolveHomeScreenKind(
          languageSelected: true,
          isReturningUser: false,
          hasFirebaseAuth: true,
          isAnonymousAuth: true,
        ),
        HomeScreenKind.home,
      );
    });

    test(
        '4) telefon orqali ro\'yxatdan o\'tgan, sessiya tirik — '
        'to\'g\'ridan-to\'g\'ri Home', () {
      expect(
        resolveHomeScreenKind(
          languageSelected: true,
          isReturningUser: true,
          hasFirebaseAuth: true,
          isAnonymousAuth: false,
        ),
        HomeScreenKind.home,
      );
    });

    test(
        '5) telefon orqali qaytgan, lekin sessiya yo\'q (APK yangilash '
        'va h.k.) — AuthRestoreScreen', () {
      expect(
        resolveHomeScreenKind(
          languageSelected: true,
          isReturningUser: true,
          hasFirebaseAuth: false,
          isAnonymousAuth: false,
        ),
        HomeScreenKind.authRestore,
      );
    });

    test(
        'chetga chiqish: isReturningUser=true, lekin joriy sessiya '
        'anonim (kutilmagan holat) — AuthRestoreScreen (xavfsiz fallback, '
        'HomeScreenga emas)', () {
      expect(
        resolveHomeScreenKind(
          languageSelected: true,
          isReturningUser: true,
          hasFirebaseAuth: true,
          isAnonymousAuth: true,
        ),
        HomeScreenKind.authRestore,
      );
    });
  });
}
