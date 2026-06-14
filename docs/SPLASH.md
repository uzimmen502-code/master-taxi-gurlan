# Splash ekran (native)

## Qisqa

- **Fayl:** `assets/images/splash_full.png`
- **Konfig:** `flutter_native_splash.yaml`
- **Android ≤11:** `values/styles.xml` → `windowBackground` = `@drawable/launch_background`
- **Android 12+:** `values-v31/styles.xml` → poster + bo'sh markaz ikonka (alohida!)

## Nima uchun yashil fon + launcher ikonka chiqdi?

Ko'pchilik qurilmalar **Android 12+ (API 31+)**.

`flutter_native_splash:create` ishga tushganda `android_12:` bo'limida faqat `color` bo'lsa:

1. `windowSplashScreenBackground` → **faqat yashil rang** (`#C8E6C9`), `splash_full` emas
2. `windowSplashScreenAnimatedIcon` yo'q → tizim **`@mipmap/ic_launcher`** ni markazda ko'rsatadi
3. `values/styles.xml` dagi `launch_background` (poster) **API 31+ da ishlatilmaydi**

Natija: yashil fon + ilova ikonkasi — `splash_full` ko'rinmaydi.

## Qayta generate qilganda

```bash
dart run flutter_native_splash:create
powershell -ExecutionPolicy Bypass -File scripts/patch_android12_splash.ps1
```

**Keyin tekshiring:**

- `values-v31/styles.xml` — faqat `android:windowBackground` = `@drawable/launch_background` (**icon slotga poster qo‘ymang!**)
- `AndroidManifest.xml` — `io.flutter.embedding.android.SplashScreenDrawable` = `@drawable/launch_background`
- `MainActivity` — oddiy `FlutterActivity` (`installSplashScreen` + `launch_background` icon = markazda kichik rasm)
- Flutter — `AppLaunchSplash` birinchi frame gacha `splash_full.png` to‘liq ekran

Generator ba'zan `values-v31` ni buzadi — `docs/SPLASH.md` va ushbu fayldagi namunaga qaytaring.

## Tekshirish

```powershell
# APK ichida poster bormi?
# build dan keyin drawable/background.png ~500KB atrofida bo'lishi kerak

Select-String -Path android\app\src\main\res\values-v31\styles.xml -Pattern launch_background
```

## Xato qilmaslik

| Qilmaslik | Sabab |
|-----------|--------|
| `android_12` da faqat `color` | Poster o'rniga rang + launcher ikonka |
| `fullscreen: true` = to'liq poster | Faqat status bar yashirinadi |
| Faqat `assets/` ga PNG qo'yish | Native `res/drawable*` yangilanishi shart |
| `create` dan keyin v31 ni tekshirmaslik | Generator Android 12+ ni buzishi mumkin |
