# Settlement Ledger — V1 дизайн ҳужжати

> Ҳолат: **қулфланган (locked)** — амалга ошириш учун тасдиқланган.
> Тил: ўзбекча (кирилл). Код изоҳлари инглиз/ўзбек аралаш бўлиши мумкин.

## 1. Концепция қисқача

Тизимда анъанавий "электрон ҳамён" эмас, **Settlement Ledger** (ҳисоб-китоб дафтари)
ишлайди. Реал пул тизим ичида ҳаракатланмайди — фақат иштирокчилар ўртасидаги
**ҳисоб-китоб мажбуриятлари** (қарздорлик/талаб) ўзгаради. Ҳар бир операция
**double-entry** (икки томонлама) принципида журналга ёзилади ва аудит қилинади.

Асосий иш — трип қайтими (сдача): ҳайдовчи қайтимни қисман нақд, қисман
Settlement орқали бериши мумкин. Settlement қисми ҳайдовчининг **Float**идан
йўловчининг **Credit**ига кўчади.

### Мисол
- Сафар ҳақи: 83 000 сўм; йўловчи 100 000 нақд берди → қайтим 17 000.
- Ҳайдовчида 10 000 нақд бор: 10 000 нақд + 7 000 Settlement.
- Натижа: `driver_float` 200 000 → 193 000; `passenger_credit` +7 000;
  админ умумий мажбурияти ўзгармайди (фақат ҳайдовчидан йўловчига кўчди).

## 2. Асосий қоидалар

1. Тизим электрон ҳамён эмас — Settlement Ledger.
2. Реал пул ичкарида ҳаракатланмайди, фақат мажбуриятлар ўзгаради.
3. Ҳар операция журналга алоҳида, **балансланган** транзакция сифатида ёзилади
   (баланс ҳеч қачон қўлда ўзгартирилмайди).
4. Ҳайдовчи даромади (Earnings) ва қайтим фонди (Float) — алоҳида.
5. Йўловчи тасдиқламасдан Settlement якунланмайди: `Pending → Confirmed → Completed`.
6. Админ/бухгалтер реал вақтда кузатади; аудит тарихи доим текширилади.
7. **Фақат идентификациядан ўтган фойдаланувчилар** учун (қуйида 7-бўлим).

## 3. Идентификация талаби

- "Идентификациядан ўтган" = **OTP (SMS) билан тасдиқланган телефон** +
  `users/{phoneDigits}` ҳужжати.
- **Йўловчи (V1, closed-loop):** 1-даража — тасдиқланган телефон + `name`. KYC шарт эмас.
- **Ҳайдовчи:** тасдиқланган (админ тасдиғидан ўтган) ҳайдовчи профили.
- Биронта томон **аноним** бўлса → Settlement яратилмайди → **фақат нақд**.
- KYC (паспорт/лимит) фақат келажакда **нақд ечиш (payout)** очилганда мажбурий.

## 4. Ҳисоблар режаси (Chart of Accounts)

Платформа дафтари нуқтаи назаридан. Мажбурият **кредит** билан ошади,
актив **дебет** билан ошади.

| Ҳисоб | Тури | Маъноси |
|---|---|---|
| `admin_cash` | Актив | Касса (Cash In / Wallet→Cash / инкасса) |
| `courier_cash:{courierPhone}` | Актив | Курьер қўлидаги компания нақд/картаси (инкассациягача) |
| `driver_float:{driverUid}` | Мажбурият | **DEPRECATED** — `migrateFloatToWallet` орқали ҳамёнга кўчирилади |
| `passenger_credit:{userUid}` | Мажбурият | Фойдаланувчи ҳамёни (= `bonusBalance`) — қайтим, хизмат |
| `supplier_payable:{supplierUid}` | Мажбурият | Провайдерга тўланадиган (V2) |
| `admin_clearing` | Клиринг | Оралиқ/мувозанат (миграция, V1 кредит сарфи, field cash) |

**Инвариант:** `Σ барча ёзув оёқлари = 0` ва
`Σ активлар (admin_cash + courier_cash + admin_clearing ± …) = Σ мажбуриятлар`.

## 5. Асосий оқимлар (double-entry ёзувлари)

**A. Ҳайдовчи Float топширади (200 000 нақд):**
- Дебет `admin_cash` 200 000
- Кредит `driver_float:driver` 200 000

**B. Трип settlement (7 000, float орқали):**
- Дебет `driver_float:driver` 7 000
- Кредит `passenger_credit:passenger` 7 000
- (`admin_cash` ўзгармайди)

**C. Йўловчи кредитни хизматда сарфлайди (7 000):**
- Дебет `passenger_credit:passenger` 7 000
- Кредит `admin_clearing` 7 000 *(V1)* → `supplier_payable:supplier` *(V2)*

**D. Ҳайдовчи Float'ини қайтариб олади (депозит қайтими):**
- Дебет `driver_float:driver` X
- Кредит `admin_cash` X

**E. Курьер нақд/карта қабул қилди (`courierSubmitPayment`, cash+card):**
- Дебет `courier_cash:courier` (cash+card сумма)
- Кредит `admin_clearing`
- kind: `courier_field_cash`, id: `courierCash:{orderId}`

**F. Инкассация (`receiveCourierCash` — finance):**
- Дебет `admin_cash`
- Кредит `courier_cash:courier`
- kind: `courier_inkassa`

**G. Cash Exchange (`cashExchange` — finance):**
1. `cash_in`: Dr `admin_cash` / Cr `admin_clearing`
2. `cash_to_wallet`: Dr `admin_clearing` / Cr `passenger_credit:{uid}`
- Манфий ҳамён тақиқланади. `floatTopUp` / `floatReturn` ёпилган.

**H. Wallet → Cash (`walletToCash`):**
- Dr `passenger_credit` / Cr `admin_cash`

**I. Сафар қайтими (`confirmSettlement`):**
- Dr `passenger_credit:{driver}` / Cr `passenger_credit:{passenger}`
- (эски: driver_float → passenger_credit)

## 6. Маълумотлар модели (Firestore)

```
ledger_accounts/{accountId}
   { type, ownerUid, balance, updatedAt }            // materialized баланс

journal_entries/{entryId}                              // append-only, ўзгармас
   { ts, kind, idempotencyKey, refType, refId,
     postedBy, postedRole,
     legs: [ { account, dr, cr } ... ],                // Σdr == Σcr, > 0
     status: 'posted' }

settlements/{settlementId}                             // трип settlement ҳолати
   { tripId, driverUid, passengerUid,
     totalChange, cashGiven, settlementAmount,
     state: pending|confirmed|completed|deferred|cancelled,
     idempotencyKey, journalEntryId,
     createdAt, confirmedAt, completedAt }

period_closings/{periodId}                             // Daily Closing (давр қулфи)
   { from, to, closedBy, totals, closedAt, locked: true }

users/{uid}.bonusBalance        ← passenger_credit проекцияси (айни txn'да)
users/{uid}/wallet_ledger       ← фойдаланувчига кўринадиган тарих (қолади)
settings/settlement             ← config (лимитлар, зоналар)
```

### account ID формати
`{type}` ёки `{type}:{ownerUid}`. Мисол: `admin_cash`, `admin_clearing`,
`driver_float:998901234567`, `passenger_credit:998907654321`.

## 7. Ҳолат машинаси (трип settlement)

```
Pending ──(йўловчи тасдиғи)──▶ Confirmed ──(double-entry post)──▶ Completed
   │
   └─(интернет йўқ + нақд етмайди + йўловчи танилган + headroom етади)──▶ Deferred
            └─(reconnect)──▶ сервер post ──▶ Completed
                 └─ float етмаса → driver_float манфий (ҳайдовчи қарзи),
                    ҳайдовчи блок: токи float ≥ 0 бўлгунча янги трип йўқ
```

- Аноним томон / идентификация йўқ → settlement яратилмайди (фақат нақд).
- Йўловчи доим reconnect'да **дарров** кредит олади; камомад — ҳайдовчи зиммасида.

## 8. Float сиёсати (`settings/settlement`да созланувчи)

| Зона | Қиймат | Хатти-ҳаракат |
|---|---|---|
| 🟢 Соғлом | ≥ 100 000 (`floatMin`) | Settlement тўлиқ ишлайди |
| 🟡 Паст | 20 000 – 100 000 | Ишлайди + "тўлдиринг" огоҳлантириши |
| 🔴 Критик | < 20 000 (`floatCritical`) | Settlement ўчади (фақат нақд) |
| ⛔ Макс | > 500 000 (`floatMax`) | Депозит қабул қилинмайди (cap) |

Deferred (манфий float):
- `deferredNegativeFloatPct = 10` — охирги депозитнинг %игача рухсат.
- `deferredTimeoutHours = 48` — тугаса: ҳайдовчи блок + finance аларм + камомад
  келажак даромаддан ушланади.
- Лимит **трип пайтида** текширилади (headroom сиғмаса deferred таклиф қилинмайди).

## 9. Cloud Function'лар (CF-only ёзув, idempotent)

| CF | Вазифа | Ёзув |
|---|---|---|
| `floatTopUp` | Ҳайдовчи депозити | A |
| `floatReturn` | Float қайтими (finance тасдиғи) | D |
| `openSettlement` | Трип settlement яратиш (Pending) | — |
| `confirmSettlement` | Йўловчи тасдиғи → post → Completed | B |
| `submitDeferredSettlement` | Reconnect'да pending'ни post | B |
| `spendCredit` | Кредитни хизматда сарфлаш | C |
| `reconcileLedger` | Кунлик: Σ=0, проекция текшируви, аларм | — |

Ҳар post **айни Firestore транзакцияда**: `journal_entries` + `ledger_accounts`
+ `bonusBalance` проекция + (тегишли) `wallet_ledger` тарихи.

**Idempotency:** ҳар post `idempotencyKey` билан — қайта юборилса икки марта ёзилмайди.

## 10. Firestore rules + роллар (RBAC)

- Янги роллар: `finance` (амал қилади), `auditor` (фақат ўқийди/экспорт).
  Мавжуд `admin/superadmin/dispatcher` сақланади.
- `journal_entries`, `ledger_accounts`, `settlements`, `period_closings` —
  **клиент ёза олмайди** (фақат Cloud Functions, мавжуд `walletFieldsUntouched`
  намунасига мос).
- `journal_entries` — **append-only**: `update`/`delete` ҳеч ким учун (ҳатто
  finance) — тузатиш фақат **компенсация (storno)** ёзуви орқали.
- `auditor` — барча ledger жойларида **read-only**.
- **V1 кўриниш:** Finance Center'ни `admin` **ҳам кўради** (+ finance/auditor/superadmin).
  Кейинги этапда SoD қўлланиб, оддий `admin`дан яширилади (битта RBAC флаги).

## 11. Reconciliation ва инвариантлар

- Кунлик `reconcileLedger`:
  1. Барча `journal_entries` оёқлари йиғиндиси = 0.
  2. Ҳар `passenger_credit:{uid}.balance == users/{uid}.bonusBalance`.
  3. `admin_cash == Σ liabilities (± clearing)`.
- Мос келмаса → **Exceptions**'га ёзилади + finance'га аларм.

## 12. Миграция (бир марталик, хавфсиз)

1. Ҳар мавжуд `bonusBalance > 0` учун **очилиш ёзуви**:
   - Дебет `admin_clearing`
   - Кредит `passenger_credit:{uid}`
   - `kind: 'opening_balance'`, `idempotencyKey: 'opening:{uid}'`
2. `ledger_accounts` materialized баланслар яратилади.
3. `reconcileLedger` ишга туширилиб, проекция == ҳисоб тасдиқланади.
4. Эски CF'лар (`creditChange`, `placeOrderWithWallet` ...) аста-секин шу
   двигателга кўчирилади; `bonusBalance` тўлиқ **derived** бўлиб қолади.

## 13. Finance Center (веб админ панел ичида, RBAC)

```
Finance Center
├── Назорат (Money Control) → getMoneyControlSnapshot KPI + навбат + инкасса/payout
├── Settlement Ledger      → journal_entries (ўзгармас журнал)
├── Driver Float           → driver_float:* + topUp/return
├── Passenger Credits      → passenger_credit:* (Назорат KPI)
├── Provider Payables      → V1: admin_clearing → V2: supplier_payable:*
├── Payout Requests        → Назорат + алоҳида Молия экрани
├── Courier cash           → courier_cash:* + receiveCourierCash
├── Reconciliation         → reconcileLedger натижалари
├── Daily Closing          → period_closings (давр қулфи)
├── Accounting Reports     → экспорт (CSV/PDF)
├── Audit Trail            → журнал + ким-нима қилди
└── Exceptions             → deferred / манфий float / низо / сверка хатоси
```

## 14. Иш босқичлари

1. **Ledger ядроси** — `journal_entries` + `ledger_accounts` + atomic/idempotent
   post helper + rules (append-only, CF-only) + `reconcileLedger` + миграция.
2. **Driver Float** — topUp/return + зона сиёсати.
3. **Трип settlement** — open/confirm (онлайн) + йўловчи тасдиқ UI.
4. **Deferred** — offline-lite + headroom gate + блок/қарз/таймер.
5. **spendCredit** — мавжуд wallet тўловларини двигателга улаш. ✅ (барча
   бонус оқимлари: creditChange, creditSupplier, debitForOrder, confirmPayout,
   placeOrderWithWallet, grantBirthdayBonus, courierSubmitPayment,
   courierSubmitCourierOrderPayment, courierFinalizeCollection — ledger
   ко'згуси prepare/commitBonusInTx + commitBonusInBatch орқали; reconcile яшил).
6. **Finance Center** — RBAC (finance/auditor) + Daily Closing + Audit Trail. ✅
   - RBAC: `isFinanceReader()` (admin/superadmin/finance/auditor) + ledger
     коллекциялари CF-only ёзув; V1'да оддий `admin` ҳам кўради.
   - Daily Closing: `closePeriod` CF (idempotent, кунлик `period_closings/{YYYY-MM-DD}`
     — давр оборотлари + global reconcile снапшоти, `locked`) + Finance Center
     "Давр қулфи" таби.
   - Audit Trail: журнал таби `ts`/`postedBy`/`postedRole`/`refType` кўрсатади;
     "Истиснолар" таби `ledger_exceptions` (deferred камомад) ни кўрсатади.

## 15. Келажак (V2+)

- Offline Settlement (Local Queue → Reconnect → Cloud Confirm).
- `supplier_payable` (провайдерга тўғридан-тўғри).
- Нақд ечиш (payout) — KYC + лимит + антифрод + maker–checker.
- Бонус/кешбэк/промокод/корпоратив — айни Settlement Engine орқали.

---

*Бу ҳужжат келишилган қарорларни акс эттиради ва амалга ошириш давомида
янгиланиб борилади.*
