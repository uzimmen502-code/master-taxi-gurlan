# AVA Zona — Telegram Wallet Bot архитектураси (Phase 0)

> Ҳолат: **бошланғич этап тавсияси** (вақтинчалик).  
> Тил: ўзбекча (кирилл).  
> Асос: `docs/settlement_ledger_v1_uz.md`, мавжуд `cashExchange` / `walletToCash`.  
> Мақсад: фойдаланувчи ҳамёнини **Telegram бот** орқали тўлдириш ва ечиш аризаси.

---

## 1. Концепция

Telegram бот — **тўлов шлюзи эмас**, балки **интерфейс (канал)**.

- Бот пул сақламайди, баланс ҳисобламайди.
- Реал ҳисоб-китоб фақат **Settlement Ledger** орқали.
- Ҳамён баланси = `passenger_credit:{uid}` (= `users/{uid}.bonusBalance`) — ledger проекцияси.
- Бошланғич этапда тўлов: **шахсий банк картаси + чек + админ тасдиғи**.
- Кейинги этапда: Click/Payme Merchant + webhook (бот UI сақланади).

---

## 2. Асосий қоидалар

1. Бот фақат қабул қилади / кўрсатади / узатади.
2. Балансни фақат Ledger ёзади (`bonusBalance` қўлда ўзгартирилмайди).
3. Тўлдириш якуни — мавжуд **`cashExchange`** (ёки унга делегат қилувчи ички wrapper).
4. Ечиш якуни — мавжуд **`walletToCash`** (молия тасдиғидан кейин).
5. Бир чек / бир сўров → **бир** ledger ёзуви (idempotency).
6. Telegram аккаунт **битта** AVA `uid` (телефон) га боғланади.
7. `driver_float` ишлатилмайди (deprecated).
8. Аноним фойдаланувчига депозит/ечиш йўқ — ававал телефон боғланиши шарт.

---

## 3. Юқори даражадаги архитектура

```
┌─────────────────────────────────────────────────────────────┐
│                     INTERFACE                                │
│  Telegram Bot (AVA Wallet)     Flutter App (кейинги этап)   │
└───────────────┬──────────────────────────┬──────────────────┘
                │                          │
                └────────────┬─────────────┘
                             ▼
                    ┌────────────────┐
                    │  API Gateway   │
                    │ Cloud Functions│
                    │ (HTTPS + Auth) │
                    └────────┬───────┘
                             ▼
                    ┌────────────────┐
                    │ Wallet Facade  │
                    │ deposit        │
                    │ withdraw_req   │
                    │ link_telegram  │
                    │ get_balance    │
                    └────────┬───────┘
                             ▼
              ┌──────────────┴──────────────┐
              ▼                             ▼
     ┌─────────────────┐          ┌─────────────────┐
     │ Top-up /        │          │ Settlement      │
     │ Withdraw        │          │ Ledger          │
     │ Requests        │          │ cashExchange    │
     │ (Firestore)      │          │ walletToCash    │
     └────────┬────────┘          └────────┬────────┘
              │                            │
              └──────────────┬─────────────┘
                             ▼
                    ┌────────────────┐
                    │ Firestore      │
                    │ users.bonus…   │
                    │ wallet_ledger  │
                    │ journal        │
                    └────────┬───────┘
                             ▼
                    ┌────────────────┐
                    │ Notify         │
                    │ Telegram + FCM │
                    └────────────────┘
```

**Админ:** Finance Center / Admin Web — сўровларни кўриш, чекни текшириш, тасдиқ/рад.

---

## 4. Компонентлар

| Компонент | Вазифа |
|-----------|--------|
| **Telegram Bot** | Командалар, карта кўрсатиш, чек қабул, статус |
| **Bot Worker** | Telegram Update → CF чақириш (webhook ёки polling) |
| **Auth / Link** | `telegramUserId` ↔ `users/{uid}` (телефон OTP/илова орқали) |
| **Wallet Facade** | Бизнес буйруқлар; ledgerга тўғридан чиқмайди |
| **Requests store** | Депозит/ечиш аризалари ҳолати |
| **Settlement Ledger** | Якка манба (мавжуд двигатель) |
| **Admin UI** | Тасдиқ навбати |
| **Notify** | Бот хабари + илова FCM |

---

## 5. Оқимлар

### 5.1. Аккаунт боғлаш (мажбурий биринчи қадам)

```
/start
  → бот: «Иловадаги телефонни юборинг» ёки deep link
  → OTP / бир марталик код (AVA томонида)
  → users/{uid}.telegramId = <tg_id>
  → telegram_links/{tg_id} = { uid, linkedAt }
```

Қоида: бир `telegramId` → бир `uid`; қайта боғлаш — админ ёки қатъий қайта-верификация.

### 5.2. Тўлдириш (Phase 0 — шахсий карта)

```
Фойдаланувчи
  → /deposit 100000
  → тизим: wallet_topup_requests/{id} (status=awaiting_transfer)
  → бот: карта рақами + сумма + сўров ID
  → фойдаланувчи банк орқали ўтказади
  → ботга чек (фото) юклайди
  → status=awaiting_review, receiptUrl=...
  → Admin кўради → тасдиқлайди
  → CF: approveWalletTopUp
       → cashExchange({ userUid, amount, opId: topup_{id} })
       → Ledger → bonusBalance
       → status=credited
  → бот + FCM: «Ҳамёнга +100000»
```

Рад этилса: `rejected` + сабаб; ledger ёзилмайди.

### 5.3. Ечиш (ариза — автомат ечилмайди)

```
Фойдаланувчи
  → /withdraw 50000
  → баланс текширилади (етарлими)
  → wallet_withdraw_requests/{id} (pending)
  → Admin/молия тасдиқлайди
  → CF: approveWalletWithdraw
       → walletToCash({ userUid, amount, opId: withdraw_{id} })
       → статус paid / completed
       → картага ўтказма (қўлда ёки кейин автомат)
  → бот: «Ечиш тасдиқланди / йўналтирилди»
```

**Phase 0:** картага ўтказма ҳам қўлда бўлиши мумкин; тизимдаги муҳим қисм — ҳамёндан ечиш ledgerда тўғри ёрилсин.

### 5.4. Баланс ва тариx

```
/balance  → users.bonusBalance (фақат ўқиш)
/history  → oxirgi N ta wallet_ledger
```

---

## 6. Маълумот модели

### 6.1. `telegram_links/{telegramUserId}`

```
uid: string            // 998 remapping
linkedAt: timestamp
linkedBy: 'bot'|'app'|'admin'
status: 'active'|'revoked'
```

### 6.2. `wallet_topup_requests/{id}`

```
uid: string
telegramUserId: string
amount: number
currency: 'UZS'
channel: 'telegram_card_manual'
status: 'awaiting_transfer'|'awaiting_review'|'credited'|'rejected'|'expired'|'cancelled'
cardHint: string           // oxirgi 4 raqam (to'liq raqam logda saqlanmasin)
receiptStoragePath: string
receiptUploadedAt: timestamp?
reviewedBy: string?
reviewedAt: timestamp?
rejectReason: string?
ledgerOpId: string         // cashExchange_*:topup_{id}
createdAt, updatedAt, expiresAt
source: 'telegram'
```

### 6.3. `wallet_withdraw_requests/{id}`

```
uid: string
telegramUserId: string
amount: number
status: 'pending'|'approved'|'paid'|'rejected'|'cancelled'
payoutCardLast4: string?
reviewedBy, reviewedAt, rejectReason
ledgerOpId: string         // walletToCash:withdraw_{id}
createdAt, updatedAt
source: 'telegram'
```

### 6.4. Storage

`topup_receipts/{uid}/{requestId}.jpg` — фақат эга / admin / finance ўқийди.

---

## 7. Cloud Functions (тавсия этилган API)

| CF | Ким чақиради | Вазифа |
|----|--------------|--------|
| `linkTelegramAccount` | App / Bot backend | tg ↔ uid |
| `botCreateTopUp` | Bot backend | депозит сўрови |
| `botAttachTopUpReceipt` | Bot backend | чек |
| `adminReviewTopUp` | Admin/Finance | approve→`cashExchange` / reject |
| `botCreateWithdraw` | Bot backend | ечиш аризаси |
| `adminReviewWithdraw` | Admin/Finance | approve→`walletToCash` / reject |
| `botGetWalletSummary` | Bot backend | баланс + oxirgi tarix |

**Идемпотентлик:**

- Top-up credit: `opId = topup_{requestId}` → `cashExchange`га шу `opId`.
- Withdraw: `opId = withdraw_{requestId}` → `walletToCash`.

Такрорий «тасдиқ» — иккинчи пул ёзилмаслиги керак.

---

## 8. Админ / молия UI

Finance Centerга янги таб ёки бўлим:

- **Топ-up навбати:** awaiting_review, чек превью, тасдиқ/рад  
- **Withdraw навбати:** pending  
- Фильтр: сана, сумма, uid  
- Аудит: ким тасдиқлагани

Иловадаги мавжуд Cash Exchange экрани билан параллел ишлаши мумкин; мақсад — сўровсиз қўлда «чалкаш» ёзишни камайтириш.

---

## 9. Бот командалари (Phase 0)

| Команда | Тавсиф |
|---------|--------|
| `/start` | Хуш келибсиз + боғлаш |
| `/link` | Телефон боғлаш |
| `/deposit <summa>` | Тўлдириш бошлаш |
| `/withdraw <summa>` | Ечиш аризаси |
| `/balance` | Баланс |
| `/history` | Охирги операциялар |
| `/status` | Охирги сўров ҳолати |
| `/support` | Ёрдам (матн/админга) |
| `/cancel` | Кутилаётган сўровни бекор |

Чек: фото юборилganda фаол `awaiting_transfer` сўровга бириктирилади.

---

## 10. Хавфсизлик

| Чора | Изоҳ |
|------|------|
| Telegram ↔ битта uid | Фишинг/бошқа ҳамёнга тушишни камайтиради |
| Админсиз credit йўқ | Phase 0 да шарт |
| Лимитлар | Бир сўров max; кунлик max (масалан 100k–500k — бизнес қарори) |
| Чек фақат Storage + request | Оммавий чатга ишонмаслик |
| Карта тўлиқ рақами логда йўқ | Фақат кўрсатиш вақтида / last4 |
| Rate limit | Сўров спами |
| Рол | `adminReview*` фақат finance/admin |
| Anomaly | Катта сумма → мавжуд risk/Telegram огоҳлантириш |

---

## 11. Хабарномалар

| Воқеа | Канал |
|-------|--------|
| Сўров қабул | Telegram |
| Тасдиқ / рад | Telegram + FCM (`screen: wallet`) |
| Credit бўldi | Telegram + FCM + `wallet_ledger` |

---

## 12. Босқичлар

### Phase 0 (ҳозир — шу ҳужжат)
- Бот + боғлаш  
- Шахсий карта + чек  
- Админ тасдиқ → `cashExchange` / `walletToCash`  
- `/balance`, `/history`

### Phase 1
- Wallet Facade бирлаштириш  
- Иловада ҳам «Тўлдириш сўрови» (худди шу request коллекция)  
- Яхшиланган админ навбат

### Phase 2 (Merchant)
- Click/Payme  
- Webhook → автомат `credited` (админ чексиз)  
- Reconcile  
- Бот UI сақланади; канал `gateway` бўлади

### Phase 3 (ихтиёрий)
- AVA Assistant (orders/queue) — **алоҳида** маҳсулот

---

## 13. Аниқ чегаралари (қилмаймиз)

- Ботда баланс сақлаш  
- Чексиз автомат `bonusBalance++`  
- `driver_float` қайтариш  
- Ботдан тўғридан Firestore ledgerга ёзиш (фасадсиз)  
- Ечишни админсиз бир босишда очиш (Phase 0)  
- Dating боти билан бирлаштириш (`bilish_tanish_bot` — бошқа мақсад)

---

## 14. Муваффақият мезонлари (Phase 0)

1. Боғланган фойдаланувчи `/deposit` қила олади.  
2. Чек юклангач админ навбатда кўринади.  
3. Тасдиқдан кейин ҳамён ва `wallet_ledger` тўғри ошади.  
4. Худди шу сўровни қайта тасдиқлаш — иккинчи пул бермайди.  
5. Рад — ҳамён ўзгармайди, фойдаланувчи хабар олади.  
6. `/withdraw` фақат ариза; тасдиқсиз баланс камаймайди.

---

## 15. Хулоса

`Telegram Bot → Request → Admin → cashExchange/walletToCash → Ledger → Ҳамён → Notify`

---

## 16. Ишга тушириш (ops)

### 16.1. Env (`.env`) — `functions.config` ИШЛАТМАНГ
`functions/.env` яратинг (намуна: `.env.example`):
```env
TELEGRAM_WALLET_BOT_TOKEN=...
TELEGRAM_WALLET_BOT_USERNAME=YourBotName
TELEGRAM_WALLET_WEBHOOK_SECRET=RANDOM_SECRET
```
Кейин:
```bash
firebase deploy --only functions,firestore:rules,firestore:indexes,storage
```
Батафсил: `docs/telegram_wallet_bot_setup.md`

### 16.2. Webhook
```
https://REGION-PROJECT.cloudfunctions.net/telegramWalletBotWebhook?key=RANDOM_SECRET
```
Telegram:
```
https://api.telegram.org/bot<TOKEN>/setWebhook?url=<URL>&secret_token=RANDOM_SECRET
```

### 16.3. Админ
Finance Center → **Telegram ҳамён** → Созлама: карта рақами + эгаси.

### 16.4. Фойдаланувчи
Илова → Кошелёк → «Боғлаш коди олиш» → ботда `/link` ёки deep link → `/deposit`.

