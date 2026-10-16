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

## 2-bosqich: D1 «Posilka yo'qoldi» (commitlar 422e546…76a9ec3)
Skript: `deploy_d1_lost_parcel.ps1` (faqat functions; default 5 ta → demand 12 ta, shu tartibda). Rules/indeks/migratsiya yo'q.
- `declaredValue` endi MAJBURIY (quote/create `declared_value_required`). Ilova hali yangilanmagan: bo'sh qoldirsa umumiy xato.
  Logistika yopiq (faqat testerlar, WEB), shu sabab xavfsiz; APK/WEB yangilanishi rejalashtirilsin.
- Yangi: `adminMarkShipmentLost` (demand), `adminRecordLostParcelPayment` (default). Ikkalasi faqat admin/superadmin.
- Pul: mijozga G (declaredValue) kuryer AVA hamyonidan darhol (mavjudicha, manfiy bo'lmaydi); yetmagani `debt.logistics`;
  kuryer tolagach admin yozadi → mijozga o'tadi. Kalitlar: `relayRelease:`, `relayLostUnearned:`, `relayLostRefund:`, `relayLostPayment:{id}:{opId}`.
- Tekshirish: test yuk (qiymatli) → in_transit → `adminMarkShipmentLost` → `shipments.paymentStatus` = `loss_settled`,
  `logistics_incidents/{id}` yaratilgan, mijoz/kuryer hamyoni o'zgargan, `platform_accrual` = 0.
- Rollback: o'sha nomlarni `cecf2ae`/oldingi deploy worktree'idan qayta deploy; yangi 2 callable → `firebase functions:delete`.

## 3-bosqich: Shaharlararo taksi auditi (commitlar 7accc51…aea0d8d, 11 ta)
Skript: `deploy_intercity.ps1` (functions:default 9 ta → rules alohida). `production'da HALI yo'q` (classifier rad etdi).
- H2 baho (`updateIntercityDriverRating`): faqat o'z yakunlangan broni, butun 1..5, bir bron = bir baho.
- publish/reschedule tekshiruvi: `departure_in_past` (now-5 daq), `route_required`, `seats_invalid` (1..8), `schedule_invalid`;
  `departureAt` yo'q bo'lsa eski tolerant xulq. Narx min/max QO'SHILMAGAN (qaror kerak).
- M1: ixtiyoriy `requestId` - takror chaqiruv ikkinchi marta yechmaydi (`taxi_publish_requests`, server-only).
- H3: `hadAvaBooking` serverda `intercity_bookings`dan hisoblanadi (mijoz qiymati e'tiborsiz). Qaytarish SIYOSATI o'zgarmagan.
- M4 `expirePendingTrips` har bron tranzaksiyada; M5 eslatma soati UTC+5; M6 avto-surish oldindan saralash; L2 `cancelCause`;
  H6 `rescheduleTaxiTrip`: bronlar + schedules + intercity_drivers + yo'lovchilarga 3 tilli xabar.
- H1 rules: qayta yoqish faqat `status=='published'` va o'z `taxi_trips`i bilan. Rules deploy ALOHIDA.
- INDEKS (egasi tasdig'i, --force YO'Q): `intercity_bookings` (status ASC, departureTime ASC) - eslatma uchun; fayl o'zgartirilmagan.
- Ilova (fix/courier-audit-flutter, 6 commit): o'tgan vaqt bloki + aqlli boshlang'ich vaqt, requestId, sabablar 3 tilda, yo'lovchi paneli
  faqat o'z broni, o'tgan reyslar yashirin, bo'sh holat, reysni tugatish tartibi. Eski serverda ham ishlaydi (requestId e'tiborsiz).
- Rollback: o'sha nomlar `cecf2ae` yoki oldingi deploy worktree'idan; rules - oldingi ruleset manbasini API'dan.

## Ochiq (egasi qarori)
- `legChainSweeper`/`relayEscrowReconcile`/`courierCashPendingSweep` birinchi ishga tushganda loglarni kuzating.
- `acceptLeg` endi `users.accountId → provider_capabilities` yo'lini ishlatadi (logistika hozir `internal`, hech kimga ochiq emas).
- Kodlar hamon LEG'ga bog'lanmagan (alohida qaror); tarif tahrirlash roli (dispatcher) o'zgarmagan.
