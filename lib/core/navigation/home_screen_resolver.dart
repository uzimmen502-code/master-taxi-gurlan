/// Cold-start'da `MaterialApp.home` qaysi ekranga teng bo'lishini
/// hisoblovchi sof mantiq — `main.dart`dagi bool holatlardan.
/// Testlanadigan qilib alohida chiqarilgan (Firebase/Widget'siz).
enum HomeScreenKind {
  languageSelect,
  guestIntro,
  authRestore,
  home,
}

HomeScreenKind resolveHomeScreenKind({
  required bool languageSelected,
  required bool isReturningUser,
  required bool hasFirebaseAuth,
  required bool isAnonymousAuth,
}) {
  if (!languageSelected) return HomeScreenKind.languageSelect;
  if (isReturningUser) {
    return (hasFirebaseAuth && !isAnonymousAuth)
        ? HomeScreenKind.home
        : HomeScreenKind.authRestore;
  }
  // Hali hech qachon telefon-orqali ro'yxatdan o'tmagan:
  // anonim sessiya allaqachon bo'lsa (qaytgan guest) — to'g'ridan-to'g'ri
  // feed, aks holda (haqiqiy birinchi ochilish) — intro.
  return hasFirebaseAuth ? HomeScreenKind.home : HomeScreenKind.guestIntro;
}
