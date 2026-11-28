# Reliz 1128b — klient (Flutter ilova + admin web)

> Branch: `rel/1128b-client` · asos: **jonli hosting `a9527153`** (`feat/factories-jobs`) · sana: 2026-11-28
> Ega: «ҳа, бошла» (2026-11-28). Hamkor to'lovi: «Тўлов занжирини кейин қайта кўриб чиқамиз» — **kiritilmadi**.
> Bu hujjat — tayyorlash hisoboti va deploy retsepti. **Hech narsa deploy qilinmagan, APK qurilmagan, prod'ga yozilmagan.**

Belgilar: **CONFIRMED** (kod/jonli tekshiruv bilan) · **INFERRED** (kuchli xulosa) · **PROPOSED** (taklif) · **UNKNOWN**.

## 1. Asos (jonli hosting) — CONFIRMED

- Jonli `main.dart.js` SHA-256 `5050CAA3FDDF…`, `admin/main.dart.js` `A7EEEB4A11B3…`, SW `7A5496E9…` —
  `.claude/worktrees/fjobs/build/hosting` (a9527153) bilan bayt-bayt bir xil (2026-11-28 tekshirildi).
- `firebase hosting:channel:list --site master-taxi-gurlan`: live release `2026-11-28 08:46:53`.
- `origin/feat/factories-jobs` = `a9527153`; quyidagi 9 branchning hammasi aynan shu SHA'dan boshlangan (merge-base = a9527153).

## 2. Nima kiritildi (merge tartibi, `git merge --no-ff`)

| # | Branch (SHA) | Mazmuni | Konflikt |
|---|---|---|---|
| 1 | `fix/dup-payout-rounding-client` (5bcbcff1) | Supermarket admin: foiz 0.01 % aniqlikda (bps), ushlab turish, kuryer xizmat haqi namunasi yarmidan yuqoriga | yo'q |
| 2 | `fix/dup-audit-p2` (7c0ee3da) | Yagona «АВТО / ҚЎЛДА» paneli `ModerationModeBar` + `AdminModerationModesService` (6 ta moderatsiya ekrani), qurilma avto-tasdiq kaliti olib tashlandi | yo'q |
| 3 | `fix/dup-audit-p3` (2747617f) | 73 ta takror til kaliti birlashtirildi (×3 til), 108 `tr()` yangilandi, `assets/` ildizidagi 26 ta ishlatilmagan webp o'chirildi | yo'q |
| 4 | `feat/incentive-form-simple` (7644bb24) | Admin «Дастурни таҳрирлаш» soddalashtirildi (nom→kalit, turkumlar ro'yxatdan, yosh, «faqat yangilar», Toshkent kuni) | yo'q |
| 5 | `feat/sm-units-samples` (80483153) | Supermarket o'lchov birliklari yagona manbadan (`functions/supermarket_units.json` ↔ `sm_units.dart`), namuna narxi birliksiz; +7 kalit ×3 | yo'q |
| 6 | ~~`feat/partner-payout`~~ | **KIRITILMADI** — ega 2026-11-28: «Тўлов занжирини кейин қайта кўриб чиқамиз» | — |
| 7 | `feat/birthday-prompt` (1a88a41c) | «Туғилган кунингизни киритинг» push/«Хабарлар» → tug'ilgan sana ekrani; admin «Туғилган кун эслатмаси» tabi | yo'q |
| 8 | `feat/qr-web-login` (a2062644) | Kompyuterda QR orqali kirish (web ekran, telefon skaner/tasdiq, «Компьютерлар» ro'yxati), `mobile_scanner ^7.5.0`, iOS `NSCameraUsageDescription`, admin PIN sessiyasi tiklash tuzatishi | yo'q |
| 9 | `feat/splash-house-ad` (7b949ba1) | Splash: pastki «Реклама бериш» tugmasi olib tashlandi, banner bosilsa pullik reklama ekrani, namuna (uy) reklamasi, admin «Премиум тариф ва созлама» tabi | yo'q |

Barcha 8 merge matn konfliktsiz bo'ldi (ort strategiyasi avtomatik birlashtirdi: `admin_supermarket_service.dart`,
`sm_checkout_screen.dart`, `sm_widgets.dart`, `lib/main.dart`, 3 til fayli). Semantik tekshiruvlar 3-bo'limda.

## 3. Tekshiruvlar — CONFIRMED (shu branchda ishga tushirildi)

- **Til fayllari:** uz_Cyrl / uz_Latn / ru — har biri **6687 kalit** (asos 6708: +52, −73, 0 o'zgargan), kalitlar to'plami bir xil (0 yetishmaydi), 0 takror kalit, JSON yaroqli, BOM yo'q.
- **O'chirilgan 73 kalit:** lib/ va test/ da hech bir havola yo'q (birlashtirilgan barcha branchlar kodi bilan birga tekshirildi).
- **O'chirilgan 26 asset:** hech bir havola yo'q (lib, test, web, functions, pubspec); ular `pubspec.yaml`da e'lon qilinmagan edi → web build fayl ro'yxatiga ta'sir qilmaydi.
- **flutter analyze:** 69 issue — asos (a9527153) bilan **aynan bir xil** to'plam (7 error — `third_party/video_player_android/pigeons`, oldindan bor). Yangi error/warning: 0.
- **flutter test (to'liq):** **5145 passed / 33 skipped / 0 failed** (exit 0). Asos dbddaf8c: 5072 / 33 / 0 — +73 yangi test, regressiya yo'q.
- **flutter build web --release:** user (`--pwa-strategy=none`) va admin (`-t lib/main_admin.dart --base-href /admin/`) — ikkalasi exit 0.
  user `main.dart.js` `56607BA9D71F…`, admin `89E50DB68133…`. Fayl ro'yxati jonli build bilan bir xil (266 + downloads = 278);
  farq qiluvchi 14 fayl: 2 bundle, 3+3 til, `NOTICES` ×2 (mobile_scanner litsenziyasi), `MaterialIcons` ×2, SW ×2 (deploy'da jonli kill-switch bilan almashtiriladi).
- **Vizual tekshiruv (release web renderer, soxta servislar, Firebase init'siz — prod'ga so'rov yo'q):** admin ModerationModeBar, rag'bat formasi
  (yangi + car_200k tahriri), supermarket sozlamalari (12.5 % bps), «Туғилган кун эслатмаси», Splash admin (premium tarif tabi, «Намуна реклама» kaliti);
  foydalanuvchi: QR web kirish, telefon tasdiq ekrani, «Компьютерда кириш» ro'yxati, splash sukut banneri, splash namuna (uy) banneri — hammasi to'g'ri chizildi.
  Kichik kuzatuv: Splash admin TabBar'da tanlangan tab yozuvi to'q sariq fonda kam ko'rinadi (preview `AppTheme.light` bilan; admin temasida — UNKNOWN; yangi muammo emas, tablar oldin ham shu uslubda — INFERRED).

## 4. Crashlytics tuzatishlari 030ca74d / 74f47d6e — CONFIRMED

- Ikkala SHA jonli liniya (a9527153) ajdodi **emas**, lekin mazmuni 2026-11-06 da `fix/crash-port` **11a39c5f** sifatida ko'chirilgan
  va u a9527153 ning ajdodi (4d04525a orqali). Jonli kodda: `fcm_service.dart` raqamli alias filtri `^\d{9,}$` + `onError`;
  `customer_orders_hub.dart` da 4 ta `onError`. `news_hub_screen` qismi ataylab tashlangan (yangi «Хабарлар» o'zi himoyalangan).
- Xulosa: qo'shimcha merge kerak emas. Qayta Crashlytics tekshiruvi — yangi APK tarqalgandan keyin (PROPOSED).

## 5. Qaysi funksiya avval SERVERni talab qiladi

Jonli funksiyalar ro'yxati (`firebase functions:list`, 626 ta, 2026-11-28) bilan solishtirildi:

| Klient qismi | Server callable / o'zgarish | Jonlimi | Server deploy'gacha holat |
|---|---|---|---|
| ModerationModeBar (6 ekran + supermarket hamkor + ishlab chiqaruvchi) | `adminGetModerationModes`, `adminSetModerationMode` (`fix/dup-audit-p2-srv`) | **YO'Q** (CONFIRMED) | **XAVF:** eski to'g'ridan-to'g'ri yozish yo'llari klientdan olib tashlangan → admin avto/qo'lda rejimini **o'zgartira olmaydi** (o'qish `settings/app` orqali ishlaydi — INFERRED). **p2-srv funksiyalari (va rules) hostingdan OLDIN** deploy qilinishi shart |
| Admin «Туғилган кун эслатмаси» tabi | `adminGetBirthdayPromptSettings`, `adminSetBirthdayPromptSettings` + haftalik push (`feat/birthday-prompt-srv`) | **YO'Q** (CONFIRMED) | tab «Юклаб бўлмади» ko'rsatadi; push yo'nalishi zararsiz (push kelmaydi) |
| QR web kirish | `qrLoginStart/Peek/Approve/Consume`, `qrWebSessionsList/Revoke/Heartbeat` (`feat/qr-web-login-srv`) | **YO'Q** (CONFIRMED) | web tugmasi va profil «Компьютерлар» qatori **yashirin** (probe muvaffaqiyatsiz → ko'rinmaydi, kod CONFIRMED) |
| Splash namuna (uy) reklamasi | `splash_ads.js` `house`/`imageUrls` + `tools/create_splash_house_ad.js` (`feat/splash-house-ad-srv`) | **YO'Q** (INFERRED: jonli manba `AD_KEYS`da `house` yo'q) | admin «Намуна» kaliti saqlanmaydi (server e'tiborsiz qoldiradi — INFERRED); pastki tugma olib tashlanishi va sukut banner bosilishi darhol ishlaydi |
| Supermarket birliklari (g, ml, quti, m) | `supermarket.js` `supermarket_units.json`ni o'qishi (`feat/sm-sample-groups`) | UNKNOWN (jonli lineage'da topilmadi) | klient noma'lum birlikni ko'rsatmaydi (xavfsiz); yangi birliklarni server rad etishi mumkin |
| Foiz 0.01 % (bps) | `fix/dup-payout-rounding` (money_math.js) | **YO'Q** (d6ac6e18 ajdodi emas, CONFIRMED) | eski server `weighHoldPercent` kutishi mumkin — UNKNOWN; server avval |
| Rag'bat formasi | mavjud `adminUpsertIncentiveProgram` (jonli) ; `fix/incentive-validate-kind` (jonli emas) | qisman | INFERRED: forma jonli server bilan ishlaydi; maxsus dasturlar himoyasi server tomonda keyin |

**Tavsiya (PROPOSED) tartib:** 1) server: p2-srv (+ rules alohida), birthday-srv, qr-srv (stage OFF), splash-house-srv, payout-rounding, sm-sample-groups;
2) jonlida tekshirish; 3) keyin shu hosting; 4) keyin APK.

## 6. Hosting deploy retsepti (jonli SHA ustiga) — PROPOSED

`reference-hosting-live-lineage` retsepti bo'yicha, **shu branch HEAD** (`rel/1128b-client`) dan:

1. Worktree: `D:\projects\ava_gurlan\.claude\worktrees\rel-1128b-client` (allaqachon a9527153 ustida). `lib/config.dart` hash'i fjobs bilan bir xil (C18A8C43…, CONFIRMED).
   `web/downloads/*` (3 APK + README/index/QR) ni `.claude\worktrees\fjobs\web\downloads\` dan nusxalash (gitignored).
2. `flutter pub get` → `git checkout HEAD -- linux macos windows`.
3. `flutter build web --release --pwa-strategy=none -o build/user_out` va
   `flutter build web --release -t lib/main_admin.dart --base-href /admin/ --pwa-strategy=none -o build/admin_out`.
4. `build/hosting` = user_out + `hosting/admin` = admin_out; jonli SW (597 bayt, `7A5496E9`) ni `hosting/` va `hosting/admin/` ga nusxalash;
   APK'larni `hosting/downloads/` **va** `hosting/admin/downloads/` ga.
5. Isbot: fayl ro'yxati fjobs `build/hosting` (278) bilan solishtiriladi; farq faqat kutilgan fayllar (2 bundle, 3+3 til, AssetManifest/FontManifest ehtimol);
   til farqi (CONFIRMED, har uchala til): asos 6708 → 6687 kalit; **+52** (sm_/smp_ 7, qrl_ 45) **−73** (p3), 0 matn o'zgargan.
6. Guard: deploy oldidan jonli `main.dart.js` = `5050CAA3FDDF…`, `admin/main.dart.js` = `A7EEEB4A11B3…` (boshqa sessiya deploy qilmaganini tekshirish).
7. `firebase deploy --project master-taxi-gurlan --only hosting:master-taxi-gurlan --config D:\projects\ava_gurlan\.claude\worktrees\rel-1128b-client\firebase.json`
   (hech qachon bare `--only hosting`).
8. Jonlini isbotlash: hash = build, release vaqti, til fayllari, SW, 6 APK URL 200, `version.json`.

**Rollback:** a9527153 — build `D:\projects\ava_gurlan\.claude\worktrees\fjobs\build\hosting` (user `5050CAA3FDDF` / admin `A7EEEB4A11B3`);
Firebase release tarixidan oldingi versiyani qayta chiqarish (a9527153 hosting version id xotirada o'qilmagan — UNKNOWN; release tarixidan olinadi).
Undan oldingi: dbddaf8c, hosting version `828e617b6112ac84`.

**Deploydan keyingi kuzatuv:** adminlar bir marta PIN bilan qayta kirishi mumkin (yangi `admin_web_pin_uid` belgisi eski sessiyada yo'q — INFERRED, `admin_auth_service.restoreSession`).

## 7. APK ehtiyojlari — PROPOSED (ega roziligi bilan, bitta build)

- **mobile_scanner 7.5.0** (CONFIRMED pubspec.lock): Android'da CameraX + ML Kit barcode (`play-services-mlkit-barcode-scanning 18.3.1`,
  `com.google.mlkit:barcode-scanning 17.3.0`) — APK hajmi oshadi (UNKNOWN qancha; build'da o'lchash).
- **Kamera ruxsati:** plagin manifesti `android.permission.CAMERA` + `uses-feature camera required=false` ni o'zi qo'shadi (CONFIRMED pub cache);
  ilova `AndroidManifest.xml`ga qo'shish shart emas (manifest merge — APK build'da tekshirish). iOS: `NSCameraUsageDescription` qo'shilgan (faqat uz_Cyrl matn).
- **minSdk:** mobile_scanner 23 talab qiladi; ilova `flutter.minSdkVersion` = 24 (Flutter SDK, CONFIRMED) — mos.
- **versionCode:** pubspec `1.0.35+76` (build'da `--build-name/--build-number` beriladi). Xotiradagi eng katta ma'lum: `1.0.37+128` (AAB, yuklanmagan) — INFERRED.
  Taklif: **1.0.38+129** yoki undan katta (Play Console'dagi oxirgi kod bilan tekshirish — UNKNOWN).
- QR skaner, birthday push ochilishi, splash o'zgarishi — APK'da; web'da QR faqat web kirish ekrani.

## 8. Xavflar

1. ModerationModeBar server'siz → admin rejimlarni o'zgartira olmaydi (5-bo'lim). Server avval.
2. p3: 73 kalit o'chirilgan — eski APK'lar til fayllarini o'z ichida olib yuradi (bundled assets) → eski APK'ga ta'sir yo'q (INFERRED); web darhol yangi fayllarni oladi.
3. QR web `QrWebSessionGuard` hamma web foydalanuvchida ishga tushadi, lekin saqlangan QR sessiya bo'lmasa hech narsa qilmaydi (INFERRED, testlar bor).
4. Hamkor to'lovi (`feat/partner-payout`) kiritilmagan — admin «Hamkor to'lovlari» tabi yo'q (ega qarori).
