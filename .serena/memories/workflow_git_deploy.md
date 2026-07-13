# Git commit / push / deploy — foydalanuvchi roziligi (2026-07-13)

Foydalanuvchi topshirig‘i: **zarur bo‘lganda** `git commit`, `git push` va Firebase **deploy** ni **har doim** bajar — uning **doimiy roziligi** bilan (alohida «commit qil» deb kutib o‘tirma).

## Qachon
- Feature/fix/P0–Pn yakunlanganda; CF/rules/indexes o‘zgarganda; Play build uchun `pubspec` version bump bilan birga.
- Ish tugagach: analyze → commit → push → kerakli deploy (ketma-ket, o‘z vaqtida).

## Cheklovlar
- Force push / hard reset — yo‘q (ayniqsa main).
- Secrets, `.env`, `service-account.json` — commit qilma.
- `release/*.aab|*.apk` va tmp — default holda commitga kiritma (so‘ralmasa).
- Nima commit/deploy qilinishi noaniq bo‘lsa — qisqa so‘ra, keyin bajar.

Batafsil: `mem:task_completion`, `mem:suggested_commands`.