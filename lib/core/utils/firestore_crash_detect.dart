/// Firestore veb (JS) SDK'sining "INTERNAL ASSERTION FAILED: Unexpected state"
/// bug'ini matn bo'yicha aniqlaydi. Bu xato otilgach SDK klienti to'liq
/// buziladi — yagona tiklash yo'li sahifani qayta yuklash.
bool isFatalFirestoreAssertion(Object error) {
  final s = error.toString();
  return s.contains('INTERNAL ASSERTION FAILED') ||
      (s.contains('FIRESTORE') && s.contains('Unexpected state'));
}
