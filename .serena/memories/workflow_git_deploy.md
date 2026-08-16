# Git commit / push / deploy — foydalanuvchi roziligi (2026-07-13)

Foydalanuvchi topshirig‘i: **zarur bo‘lganda** `git commit`, `git push` va Firebase **deploy** ni **har doim** bajar — uning **doimiy roziligi** bilan (alohida «commit qil» deb kutib o‘tirma).

## Qachon
- Feature/fix/P0–Pn yakunlanganda; CF/rules/indexes o‘zgarganda; Play build uchun `pubspec` version bump bilan birga.
- Ish tugagach: analyze → commit → push → kerakli deploy (ketma-ket, o‘z vaqtida).

## Google Play (2026-07-30)
- **Har o‘zgarishda Play yuklamang.** Batch: taxminan **2–3 kunda bir** release, yoki faqat **juda muhim** hotfix.
- Oddiy UI/fix → kod + CF/hosting deploy yetarli; AAB/Play — foydalanuvchi so‘raganda yoki batch kuni.
- Play build: `pubspec` bump (`+N`) + `scripts/build_play_release.ps1` → Desktop/releases AAB.

## Qurilmaga APK (2026-08-16)
- Har o‘zgarishdan keyin **adb install qilma**.
- Faqat foydalanuvchi aniq tasdiqlaganda (`o‘rnat`, `APK qo‘y`, `telefonga`).
- Doimiy commit/push/deploy roziligi APK o‘rnatishni o‘z ichiga olmaydi.
- Build ham so‘ralmasa shart emas; o‘rnatish = release APK only (`mem:task_completion`, `.cursor/rules/android-release-only.mdc`).

## Cheklovlar
- Force push / hard reset — yo‘q (ayniqsa main).
- Secrets, `.env`, `service-account.json` — commit qilma.
- `release/*.aab|*.apk` va tmp — default holda commitga kiritma (so‘ralmasa).
- Nima commit/deploy qilinishi noaniq bo‘lsa — qisqa so‘ra, keyin bajar.

Batafsil: `mem:task_completion`, `mem:suggested_commands`.