# APK — Variant A (bitta QR)

Битта AVA иловаси (такси, маршрут, дўкон, бозор ва бошқа хизматлар) — QR to'g'ridan APK havolasiga yo'naltiriladi.

## QR / havola

```
https://master-taxi-gurlan.web.app/downloads/master-taxi-gurlan.apk
```

Chop etish sahifasi (QR + yo'riqnoma): `https://master-taxi-gurlan.web.app/downloads/`

## APKni tayyorlash

```powershell
cd c:\projects\ava_gurlan
flutter build apk --release
copy build\app\outputs\flutter-apk\app-release.apk web\downloads\master-taxi-gurlan.apk
```

## Deploy

`web/downloads/` Flutter web build bilan `build/hosting/downloads/` ga tushadi.
Keyin `firebase deploy --only hosting`.
