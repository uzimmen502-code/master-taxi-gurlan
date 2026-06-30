# APK — Variant A (bitta QR)

Йўловчи ва ҳайдовчи **битта илова** — QR to'g'ridan APK havolasiga yo'naltiriladi.

## QR / havola

```
https://master-taxi-gurlan.web.app/downloads/master-taxi-gurlan-driver.apk
```

Chop etish sahifasi (QR + yo'riqnoma): `https://master-taxi-gurlan.web.app/downloads/`

## APKni tayyorlash

```powershell
cd c:\projects\ava_gurlan
flutter build apk --release
copy build\app\outputs\flutter-apk\app-release.apk web\downloads\master-taxi-gurlan-driver.apk
```

## Deploy

`web/downloads/` Flutter web build bilan `build/hosting/downloads/` ga tushadi.
Keyin `firebase deploy --only hosting`.

Eski `master-taxi-gurlan-driver.apk` nomi ishlatilmasin — bitta standart fayl nomi.
