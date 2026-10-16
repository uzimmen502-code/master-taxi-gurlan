# Kuryer/Logistika auditi — production deploy paketi

Sana: 2026-10-16 · Branch: `fix/courier-audit-2026-10` · Worktree: `D:\projects\ava_wt_courier_audit`
Holat: kod tayyor va testlardan o'tgan; **production'da HALI yo'q** — sabab: Claude Code auto-mode
classifier production deploy'ni rad etdi, shuning uchun deploy'ni egasi o'zi ishga tushiradi.

## Nima o'zgardi (13 kod commiti, 30 fayl)
| Qism | O'zgarish |
|---|---|
| Naqd ledger (C-1) | `courier_cash_pending` niyati to'lov tranzaksiyasida; `courierCashPendingSweep` (5 daq) |
| Relay eskrou | `relayEscrowReconcile` (10 daq): qotib qolgan refund/release/earned |
| Relay API | bekor tranzaksiyada (L1), keyingi LEG qayta ochiladi + `legChainSweeper` (L3/L11), idempotent create (L5), `acceptLeg` qayta tekshiruv (L6), tarif upsert tranzaksiya (L12), kod urinishlari qulfi (L7), rasm URL (L13), `contactUnlocked` tozalanadi (L10), `maxValue` (L15) |
| Restoran | `ready`dan olmasdan «yetkazildi» yo'q (`ORDER_NOT_PICKED`) |
| Push | soxta presence kuryer ro'yxatiga tushmaydi (`isWorking` filtri) |
| Gilam/agro/yig'ish | Mark* tranzaksiyada, atomar place*, finalize egalik, recover filtr+tranzaksiya, 9/12 xonali telefon, push xato logi |
| Rules | `delivery_routes` status (completed faqat tugagach), `demand_matches` status |

## Tekshirilgan (barchasi emulatorda, 2026-10-16)
relay-escrow 14/14 · courier-auth 12/12 · courier-cf 8/8 · courier-orders 27/27 · restaurant-cf 33/33 ·
carpet-agro-tasks 24/24 · collection-pricing 9/9 · courier-push 25/25 · rules: routes 26, demand_matches 16,
couriers 16, caps 28, logistics 18, presence 29, orders-courier 20, carpet-agro 25 · functions_demand sof 687
(1 to'plam xato: `dictionary_fresh` — avvaldan bor, bu ishga aloqasiz) · demand emulator 61/61.

## Deploy
```powershell
powershell -ExecutionPolicy Bypass -File D:\projects\ava_wt_courier_audit\.claude\deploy-kit-courier-audit\deploy_all.ps1
```
Skript: branch/commit/toza daraxtni tekshiradi, har qadamdan oldin so'raydi. Tartib: **rules alohida** →
functions:default (20 ta, nom bilan) → functions:demand (11 ta, nom bilan). `--force` yo'q, indeks deploy yo'q.

Oldindan tekshirilgan: jonli rules `0c2154c2` == `cecf2ae` dagi `firestore.rules`; bizning farq faqat +20/−1 qator.
Yangi indeks kerak emas (faqat tenglik filtrlari). `delivery_routes.orders` — kanonik maydon (jonli
`assertOrderOnActiveRoute` ham shuni o'qiydi).

## Deploydan keyin tekshirish
1. `firebase firestore:...` emas — rules: Firebase konsol → Firestore → Rules: yangi release vaqti, ruleset ≠ `0c2154c2`.
2. `firebase functions:list --project master-taxi-gurlan` — 31 funksiya yangi versiya/vaqt bilan; `courierCashPendingSweep`,
   `relayEscrowReconcile`, `legChainSweeper` mavjud va `ACTIVE`.
3. 10–15 daqiqadan keyin loglar (Cloud Logging): `courierCashPendingSweep` / `relayEscrowReconcile` / `legChainSweeper`
   qatorlari `scanned/ok/failed` bilan; `FAILED_PRECONDITION` (indeks) bo'lmasligi kerak.
4. Qo'lda sinov (1 ta test buyurtma): kuryer buyurtmani oladi → yetib keldi → to'lov (naqd) → `courier_cash_pending`
   hujjati paydo bo'lmasligi yoki 1–5 daqiqada o'chishi; kuryerning naqd balansi oshgan.
5. Eski APK bilan kuryer marshrutni boshlaydi/tugatadi (rules C5 buzmasligi kerak).

## Rollback
- **Rules:** `git worktree add D:\projects\ava_wt_rollback cecf2ae`, so'ng u yerdan
  `firebase deploy --only firestore:rules --project master-taxi-gurlan --config D:\projects\ava_wt_rollback\firebase.json`
  (jonli ruleset = `0c2154c2-5a2d-4353-95be-738494b4feed` = `cecf2ae` dagi fayl).
- **Functions:** o'sha rollback worktree'dan xuddi shu nomlar bilan qayta deploy (`functions:default:<nom>` / `functions:demand:<nom>`).
  Yangi 3 sweeper (`courierCashPendingSweep`, `relayEscrowReconcile`, `legChainSweeper`) — `firebase functions:delete <nom>`.
- Ma'lumot migratsiyasi yo'q: `courier_cash_pending` va `shipments/{id}/private/codeAttempts_*` yangi hujjatlar, eski ma'lumotga tegilmaydi.

## Ochiq (egasi qarori)
- `legChainSweeper`/`relayEscrowReconcile`/`courierCashPendingSweep` birinchi ishga tushganda loglarni kuzating.
- `acceptLeg` endi `users.accountId → provider_capabilities` yo'lini ishlatadi (logistika hozir `internal`, hech kimga ochiq emas).
- Kodlar hamon LEG'ga bog'lanmagan (alohida qaror); tarif tahrirlash roli (dispatcher) o'zgarmagan.
