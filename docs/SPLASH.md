# Splash ekran

## Qisqa

- **Logo:** `assets/images/splash_logo.png`
- **Animatsiya:** `lib/core/widgets/app_launch_splash.dart` — markazdan scale-up + fade, keyin UI fade-in
- **Konfig:** `flutter_native_splash.yaml`
- **Native fon:** qora (`@color/splash_black` = `#000000`)

## Oqim

1. **Android 12+:** tizim splash — qora fon, bo'sh icon (`splash_icon_empty.xml`)
2. **Android ≤11:** `launch_background` — qora fon
3. **Flutter:** spiral kirish (1.5 s) → 3 s pulsatsiya (3 nafas) → ekrandan chiqish (0.9 s) → UI fade-in
4. **Tagline:** har pulsatsiyadan keyin logo tagida soʻz (`settings/splash`, admin: **Splash soʻzlari**)

Poster (`splash_full.png`) va `SplashScreenDrawable` ishlatilmaydi.

## Qayta generate

```bash
dart run flutter_native_splash:create
powershell -ExecutionPolicy Bypass -File scripts/patch_android12_splash.ps1
```

`patch_android12_splash.ps1` generator Android 12+ ni qayta poster/icon slotga aylantirishi mumkin — patch majburiy.

## Tekshirish

```powershell
Select-String -Path android\app\src\main\res\values-v31\styles.xml -Pattern splash_icon_empty
Select-String -Path android\app\src\main\AndroidManifest.xml -Pattern SplashScreenDrawable
# Ikkinchisi topilmasligi kerak
```
