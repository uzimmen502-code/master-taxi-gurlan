# Driver APK download folder

Bu papka **Master Taxi Gurlan** ҳайдовчилар иловасининг APK файлини веб сайтда
жойлаштириш учун. Релиз APK qуйидаги файл номи билан шу ерга қўйилиши керак:

```
master-taxi-gurlan-driver.apk
```

## APKни тайёрлаш

Терминалда (Flutter SDK ўрнатилган):

```powershell
cd c:\projects\master_taxi_gurlan
flutter build apk --release
copy build\app\outputs\flutter-apk\app-release.apk web\downloads\master-taxi-gurlan-driver.apk
```

## Деплой

Веб-сайтни деплой қилганда `web/downloads/` — `build/web/downloads/` ичига
автоматик кўчирилади (Flutter web build) ва **Firebase Hosting** орқали
`https://<sayt-domeni>/downloads/master-taxi-gurlan-driver.apk` манзилида
очиқ доступда бўлади.

`firebase.json`'даги rewrite қоидаси SPA учун — лекин агар фaйл реал мавжуд бўлса
(downloads/...apk), Firebase Hosting аввал унга жавоб қайтаради, шу сабабли
қўшимча конфигурация шарт эмас.

## Версияни янгилаш

Янги APK чиқарилганда — фойдаланувчиларга тушунарли бўлсин учун битта file
номини сақланг (`master-taxi-gurlan-driver.apk`). Версияни **AdminLoginScreen**
дaги "Driver app" блокидaги `_apkVersion` ўзгaртирувчисидан янгилaнг.
