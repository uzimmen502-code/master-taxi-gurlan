# repositories/

**Maʼlumotlarga kirish qatlami** — Firestore, Cloud Functions, REST API bilan ishlovchi yagona joy.

## Qoidalar:
1. Screen yoki widget hech qachon `FirebaseFirestore.instance` ni to'g'ridan-to'g'ri chaqirmaydi — faqat repository orqali.
2. Har bir repository: `<Entity>Repository` deb nomlanadi (`UserRepository`, `RidesRepository`, ...).
3. Repository **`Map<String, dynamic>` qaytarmaydi** — faqat `models/` dagi tipli model qaytaradi.
4. Repository **UI ga bog'liq emas** — `BuildContext`, `setState` ishlatmaydi.
5. Cloud Functions chaqiruvlari → `services/` ga (chunki ular ko'pincha "amal"; faqat ma'lumot olish bo'lsa, bu yerga).

## Misol:
```dart
class UserRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<UserModel?> getByPhone(String phone) async { ... }
  Stream<UserModel> watchByPhone(String phone) { ... }
  Future<void> updateProfile(UserModel user) async { ... }
}
```
