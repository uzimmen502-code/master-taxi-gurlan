# server.js: repoda Postgres paroli turibdi (2026-10-24)

**Holat:** kod tuzatildi (alohida branchda), **parol hali almashtirilmagan** — buni faqat ega Railway'da qila oladi.
**Parol bu hujjatda ham, commit xabarida ham, chatda ham yozilmagan.**

## Nima topildi

- `server.js` (eski Railway/Postgres backend: `users`, `drivers`, `orders`, `favourite_addresses`) 13-qatorida
  `process.env.DATABASE_URL || 'postgresql://postgres:<parol>@postgres.railway.internal:5432/railway'` —
  ya'ni muhit o'zgaruvchisi bo'lmasa, real ko'rinishdagi parol bilan ulanadi. CLAUDE.md 39-qoida (repoda sir bo'lmaydi) buzilgan.
- Fayl 2026-04-19 da GitHub veb-interfeysi orqali yaratilgan (commit `c4b97a83`, "Create server.js"). Shu faylga tegadigan **yagona** commit.
- Satr bugun `main`, `feat/ev-trip-planner` va **barcha 83 ta masofaviy branch**da bor (lokal+masofaviy jami 186 ta ref). Tag yo'q.
- **Repo OMMAVIY (public)**: `https://github.com/uzimmen502-code/master-taxi-gurlan` ga akkauntsiz (credential'siz) so'rov muvaffaqiyatli o'tdi.
  Demak parol 6 oydan beri istalgan odamga ochiq, uni allaqachon nusxalagan bo'lishi mumkin deb hisoblash kerak.
- Boshqa joyda (HEAD'dagi boshqa fayllarda) bunday literal topilmadi.

## Xavf qanchalik katta (bilmaymiz)

- Host `postgres.railway.internal` — Railway'ning **ichki** tarmoq manzili, internetdan to'g'ridan-to'g'ri ochilmaydi. Bu xavfni kamaytiradi.
  Lekin Railway'da bazaga **ommaviy TCP proxy** yoqilgan bo'lsa yoki loyiha tarmog'iga kirish mumkin bo'lsa, parol yetarli bo'ladi. Buni men tekshira olmayman.
- Bu server hozir ishlab turibdimi, bazada haqiqiy ma'lumot (haydovchilar, buyurtmalar, manzillar) bormi — **noma'lum**. `lib/` bu serverga murojaat qilmaydi.

## Nima qilindi (kodda)

Branch: `security/server-js-require-database-url` (`feat/ev-trip-planner`dan, yangi worktree).

- `server.js`: fallback literal olib tashlandi. `DATABASE_URL` yo'q yoki bo'sh bo'lsa, server `FATAL: DATABASE_URL environment variable is not set` deb yozib, `exit 1` bilan ishga tushmaydi.
- Tekshiruv: `node --check server.js` — OK; soxta (stub) modullar bilan `DATABASE_URL` yo'q/bo'sh holatda jarayon `exit 1` bilan to'xtashi tasdiqlandi.
- Hech narsa deploy qilinmadi, production'ga tegilmadi, tarixga tegilmadi.

## Ega nima qilishi kerak

1. **Parolni Railway'da ALMASHTIRING (rotate).** Bu asosiy chora. Faylni tuzatish parolni git tarixidan, klonlardan va fork'lardan o'chirmaydi — eski parol baribir ochiq turaveradi, shuning uchun u endi "yonib bo'lgan" hisoblanadi.
   Railway Postgres xizmatida parolni yangilang va uni ishlatadigan xizmatlar yangi qiymatni olishini tekshiring (Railway'ning joriy hujjatiga qarang — interfeys o'zgargan bo'lishi mumkin).
2. **Avval `DATABASE_URL` ni xizmat o'zgaruvchilarida (Variables) o'rnating/tekshiring, keyin** bu branchni `main`ga qo'shing. Aks holda Railway xizmati yangi kod bilan ishga tushmay qoladi (bu ataylab qilingan). Railway `main`dan avtomatik deploy qilsa, shuni hisobga oling.
3. Bu server va baza hali kerakmi? **Kerak bo'lmasa — Railway'da xizmat va bazani o'chirish eng xavfsiz yo'l** (avval zarur bo'lsa eksport qiling).
4. Agar ommaviy TCP proxy yoqilgan bo'lsa, o'chiring; Railway'da ulanishlar/loglarni begona kirishga qarab ko'zdan kechiring.

## Tarixni qayta yozish — ega qarori

Hozircha **qilinmagan va men o'zim qilmayman** (force-push yo'q, history rewrite yo'q).

- Foydasi: yangi kelganlar tarixda parolni ko'rmaydi. Cheklovi: repo public, parolni allaqachon nusxalagan odamga, mavjud klon/fork'larga va GitHub keshiga ta'sir qilmaydi — haqiqiy himoya faqat 1-bandda (rotate).
- Narxi: 83 ta masofaviy branch'ni (deploy/fix branchlari bilan) qayta yozish, hamma worktree va parallel sessiyalar uchun SHA'lar o'zgaradi, deploy zanjiri (hosting SHA'lari) buziladi.
- Tavsiya: avval rotate (1-band) va serverni o'chirish/tekshirish (3-band); keyin tarixni qayta yozish kerakmi — ega hal qiladi. Rotate qilingach parol endi sir emas, shuning uchun qayta yozish ko'pincha shart emas.
  Agar baribir qilinsa, alohida, aniq rejaga ega bo'lgan ish sifatida (barcha branchlar ro'yxati, bir vaqtda, parallel sessiyalar to'xtatilgan holda).

## Ochiq savollar (egaga)

| # | Savol |
|---|-------|
| 1 | Railway'dagi bu server va baza hozir ishlayaptimi? Ma'lumot bormi? |
| 2 | Railway Postgres'da ommaviy TCP proxy yoqilganmi? |
| 3 | Parol qachon almashtiriladi va kim qiladi? |
| 4 | Tarix qayta yozilsinmi (yuqoridagi tavsiyaga qarang)? |
