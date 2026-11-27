# AVA тизимидаги ТАКРОРЛАНИШЛАР АУДИТИ — 2026-11-28

> Топшириқ (эга, 2026-11-28): тизим занжирлари бўйича такрорланишларни (дубликат бизнес қоидалар,
> тарифлар, ҳамён йўллари, модерация байроқлари, гео ёрдамчилар, хабар матнлари, параллел маълумот
> омборлари, клиент/админ экранлари, Cloud Functions, ўлик код) топиш ва тузатиш таклифини бериш.
>
> **Фақат ЎҚИШ аудити.** Код ўзгартирилмади, deploy қилинмади, production'га ёзилмади.

## 0. Манба ва усул

| Нима | Қаерда |
|---|---|
| Сервер (mainline = жонли деб эълон қилинган) | worktree `dup-audit`, `origin/feat/ev-trip-planner` **55596a4f** (`functions/`, `functions_demand/`, `firestore.rules`) |
| Клиент (жонли линия) | worktree `fjobs` HEAD **64a6bcd3** (`lib/`, `assets/lang/`) — фақат ўқилди |
| Карта | `memory/reference-app-current-state-map.md` |

Усул: мақсадли `git grep` (функция таърифлари, коллекция номлари, settings калитлари, `bonusBalance`/`wallet_ledger`
ёзувлари, `AutoApprove` калитлари, FCM чақирувлари, 3 тилли матнлар), иккала кодбазадаги бир хил номли файллар,
парите тестларини ишга тушириш, клиент `lib/` бўйича «ҳеч ким ишлатмайдиган класс/файл» скрипти ва
«клиент чақирмайдиган callable» скрипти (скриптлар scratchpad'да, репога қўшилмади).

Статус теглари (CLAUDE.md 47-банд): **CONFIRMED** — код/тест билан исботланган · **INFERRED** — кучли хулоса
(масалан, «клиентда чақирувчи йўқ», лекин эски APK номаълум) · **PROPOSED** — менинг таклифим · **UNKNOWN**.

Хавф турлари: 💰 пул · 🗄 маълумот бутунлиги · 🔒 хавфсизлик · 🙂 UX · 💸 харажат · 🔧 қўллаб-қувватлаш.
Устуворлик: **P1** (тез — пул/хавфсизлик) · **P2** (кейинги спринт) · **P3** (режали) · **P4** (тозалаш).
Ҳажм: **S** (≤1 кун) · **M** (2–5 кун) · **L** (>1 ҳафта / migration).

Барча «Таклиф» бандлари — **PROPOSED** (эга тасдиғисиз ҳеч нарса ўзгартирилмайди, 49-банд).

---

## 1. Қисқача натижа

| Бўлим | Топилмалар |
|---|---|
| A. Тариф / ҳақ / нарх ҳисоби | 11 |
| B. Ҳамён / ledger / қайтариш / тўлов | 4 |
| C. Модерация, авто-тасдиқ, босқич дарвозалари | 4 |
| D. Гео ёрдамчилар | 3 |
| E. Хабарнома матнлари ва тил калитлари | 3 |
| F. Параллел маълумот омборлари | 4 |
| G. Клиент: ўлик экран/виджетлар | 3 |
| H. Админ экранлари ва созламалар | 5 |
| I. Cloud Functions (такрор / ўлик) | 4 |
| J. Кодбазалар орасидаги нусхалар ва «жонли манба» | 3 |
| **Жами** | **44** |

---

## 2. ТОП-10 — энг юқори хавфли бандлар

| # | ID | Нима такрорланган | Хавф | Статус | Устуворлик / ҳажм |
|---|---|---|---|---|---|
| 1 | **W-1** | Ҳамён баланси 3 жойда (`users.bonusBalance` + `users/{uid}/wallet_ledger` + ledger `passenger_credit:{uid}`); `bonusBalance`ни **17 файл** тўғридан-тўғри ўзгартиради (index.js'да 50 жой) | 💰🗄 | CONFIRMED | P1 / L |
| 2 | **W-2** | Клиент чақирмайдиган эски пул callable'лари жонли: `debitForOrder` (dispatcher бошқанинг ҳамёнидан еча олади), `creditSupplier`, `requestPayout`/`checkWithdrawalLimit` (`payout_requests`) — янги `requestWalletWithdraw`/`walletToCash` йўлига параллел | 💰🔒 | INFERRED | P1 / S–M |
| 3 | **J-1** | `functions_demand/core/module_gate.js` нусхаси 25f8177d да ЎЧИБ КЕТГАН → `requestCapability(courier)`да сервер модул дарвозаси йўқ; парите тести йиқилади. Умуман: 513 жонли функция кўп бранчдан deploy қилинган | 🔒🗄 | CONFIRMED (mainline), жонли — INFERRED | P1 / S |
| 4 | **T-1** | AVA дўкон/супермаркет етказиш ҳақи формуласи 2 марта: `index.js:3425` ва `supermarket.js:216–235` (файлнинг ўзи «ОЧИҚ» деб ёзган) | 💰 | CONFIRMED | P1 / S |
| 5 | **T-3** | `platform_products` нархи — версияни (`pricingVersion`) **клиент** танлайди: v1 юборса поғонасиз ягона нарх (`platform_pricing.js:110–117`, `index.js:3125`) | 💰🔒 | CONFIRMED (код), суиистеъмол — INFERRED | P1 / S |
| 6 | **T-2** | Курьер ҳақи 4 хил двигателда: `settings/courier_task_payout` (bps, тарих, аудит), `settings/supermarket.courierPayout` (фоиз/қатъий), `courier_payout.js` хизмат ҳақи, relay LEG payout'лари — 4 админ муҳаррир | 💰🔧 | CONFIRMED | P2 / M |
| 7 | **C-1** | Авто-тасдиқ: `settings/app`да 9+ алоҳида калит, 2 хил ёзиш усули (callable+аудит vs клиент тўғридан-тўғри, аудитсиз), турли стандарт қиймат (realty йўқ бўлса = ЁҚИҚ); `realtyAutoApprove` 3 экранда | 🔒🙂 | CONFIRMED | P2 / M |
| 8 | **T-4** | bps→сўм яхлитлаш 7+ нусхада, турли йўналишда (ceil/floor/half-up); такси ставкаси 200 bps кодда қаттиқ ёзилган | 💰🔧 | CONFIRMED | P2 / M |
| 9 | **F-1** | Маҳсулот 4 омборда: `ads` cheap_product, `tv_shop_items`, `platform_products` (AVA дўкони + супермаркет), `wholesale_products` (ичида 59 та `pp_*` нусха синхронсиз); Аралаш 5 манбани ўқийди | 🗄💸🙂 | CONFIRMED | P2 / L |
| 10 | **C-4** | Супермаркет 2 марта дарвозаланган: модул id `supermarket` («Ҳудудлар ва хизматлар») + `settings/supermarket.stage/testerIds/districtIds` | 🙂🔧 | CONFIRMED | P2 / M |

Батафсил — пастдаги бўлимларда.

---

## 3. A. ТАРИФ / ҲАҚ / НАРХ ҲИСОБИ

### T-1 · Етказиш ҳақи (AVA дўкони ва супермаркет) — икки нусха  〔ТОП-4〕
- **Нима:** `functions/index.js:3425` `platformDeliveryFeeFromSettings()` (placeOrderPostPaid) ва
  `functions/supermarket.js:216` `feeConfigFromApp()` + `:230` `feeBpOf()` + `:235` `feeOf()` — бир хил қоида
  (`settings/app.platformDeliveryFeePercent`, bps = round(pct×100), fee = floor((goods×bps+5000)/10000)).
  `supermarket.js:209–214` изоҳи ўзи «икки нусха битта модулга кўчирилиши керак» деб ёзган. `holiday.js:373` ҳам шу %ни ишлатади.
- **Хавф:** 💰 — бир жойда яхлитлаш/чегара ўзгарса, иккинчисида эскиси қолади (буюртма ва тортиш/алмаштиришда фарқ).
- **Статус:** CONFIRMED.
- **Таклиф:** `functions/platform_delivery_fee.js` (соф функция: `resolve(appDoc)`, `feeOf(goods,bps)`); index.js ва
  supermarket.js уни `require` қилади; Node тестида умумий векторлар. Эски буюртмалар `deliveryFeePercent`ни ўзида
  сақлайди — migration керак эмас. Эски APK'га таъсир йўқ (сервер ичида).
- **Ҳажм/устуворлик:** S / P1. Эслатма: placeOrderPostPaid жонли манбаси `fix/courier-3bugs-srv` — аввал мерж (§29).

### T-2 · Курьер ҳақи двигателлари — 4 та  〔ТОП-6〕
- **Нима:**
  1. `functions/courier_task_payout.js:38,58` — `settings/courier_task_payout.modules.{carpet,agro,collection}.bps`, floor, тарих `courier_task_payout_history/v{n}`, `admin_audit`.
  2. `functions/supermarket.js:415–445` — `settings/supermarket.courierPayout {mode: percent|fixed}` (бутун фоиз, floor), 2026-11-26 да **алоҳида** қурилган.
  3. `functions/courier_payout.js:73` — курьер даромадидан хизмат ҳақи (`settings/courier_service_fee`, ceil).
  4. `functions_demand/api/logistics.js:403` `applyPayoutOverrides` — LEG payout'лари.
  Админда: `courier_service_fee_panel.dart`, `courier_tasks_admin_screen.dart` (PayoutPctTab), `supermarket_admin_screen.dart` (courierPayout), `logistics_chain_legs_dialog.dart` (PayoutOverrideDialog).
- **Хавф:** 💰🔧 — бир хил тушунча («курьерга қанча тегади») 4 жойда, турли формат (bps vs фоиз vs қатъий), турли аудит даражаси.
- **Статус:** CONFIRMED.
- **Таклиф:** `courier_task_payout` ни ягона двигатель қилиш: `modules.supermarket` + `mode: 'fixed'` қўшиш; супермаркет
  `courierPayoutSnapshot` уни чақиради. Эски буюртмаларда snapshot бор — қайта ҳисобланмайди (9-банд).
  `settings/supermarket.courierPayout` бир муддат «фақат ўқиш» (fallback) сифатида қолади, кейин dry-run migration.
  Админда битта «Курьер ҳақи» саҳифаси (модуллар жадвали). Relay LEG payout'лари — алоҳида қолади (бошқа модел, 13-банд).
- **Ҳажм/устуворлик:** M / P2.

### T-3 · `platform_products` нархини клиент танлайдиган версия  〔ТОП-5〕
- **Нима:** `functions/platform_pricing.js:110–117` `unitPriceForQty(product, qty, pricingVersion)` — `pricingVersion < 2`
  бўлса поғоналар эътиборга олинмайди, ягона `price`. Версия `orderBase.pricingVersion` — клиентдан (`index.js:3548`,
  `:3785`). Клиент нусхаси `lib/models/price_tier.dart` (векторлар `functions/test/fixtures/platform_price_vectors.json`).
- **Хавф:** 💰🔒 (18-банд «клиентга ишонма») — ўзгартирилган клиент 1–9 дона учун +5% поғонани ёки админ поғонасини четлаб ўтади.
- **Статус:** CONFIRMED (код йўли); амалда суиистеъмол бўлганми — UNKNOWN.
- **Таклиф:** версияни сервер ҳал қилсин: `config/app_version` минимал версияси ≥ 1.0.33 бўлгач v1 йўлини олиб ташлаш;
  ҳозирча — v1 фақат `appBuild` < 1.0.33 бўлса (сервер ўзи текширади). Эски APK (≤1.0.32): ўзгармайди, то минимал версия кўтарилгунча.
- **Ҳажм/устуворлик:** S / P1.

### T-4 · bps→сўм яхлитлаш ёрдамчилари — 7+ нусха  〔ТОП-8〕
- **Нима:**

  | Жой | Формула |
  |---|---|
  | `restaurant_delivery_tariff.js:89` computeAvaFee | ceil |
  | `functions_demand/api/wholesale_orders.js:168` avaFeeOf | ceil |
  | `courier_payout.js:73` computeFee | ceil |
  | `courier_task_payout.js:58` computePayout | floor |
  | `index.js:3425` / `supermarket.js:235` | round half-up |
  | `supermarket.js:204` holdExtraOf | ceil (фоиз) |
  | `taxi_billing.js:63,75` calculateTaxiFee | ceil, **RATE_BPS = 200 кодда** |

- **Хавф:** 💰🔧 — қоида тўғри (платформа ceil, ижрочи floor), лекин ҳар модул ўзича ёзган; такси комиссияси тарифи 9-бандга зид (hardcode).
- **Статус:** CONFIRMED.
- **Таклиф:** `functions/money_math.js` (`bpsCeil`, `bpsFloor`, `bpsRoundHalfUp`, `pctCeil`, safe-integer текшируви) + demand нусхаси `sync_*` тоол орқали (logistics_tariff каби). Такси ставкасини `settings/...` га версия билан чиқариш (эга қарори керак — UNKNOWN). Мавжуд буюртмалар ўзгармайди.
- **Ҳажм/устуворлик:** M / P2.

### T-5 · Улгуржи қадоқ/поғона танлови — икки кодбазада
- **Нима:** `functions_demand/api/wholesale_orders.js:113` `tierUnitPrice` + `resolvePack` ва `functions/wholesale_orders.js:433` `currentPackUnitPrice` (изоҳ: «demand `resolvePack` билан АЙНАН бир хил»); клиент `wholesale_pack.dart`.
- **Хавф:** 🔧💰 — квота нархи ва пул ечиш нархи фарқ қилиши мумкин (бири ўзгарса).
- **Статус:** CONFIRMED (паритет тести `test/wholesale_orders.test.js` деб айтилган — ишга туширилмади).
- **Таклиф:** `wholesale_pack.js` соф модул → default'да манба, demand'га `sync_*` тоол + байт-ба-байт тест.
- **Ҳажм/устуворлик:** S / P3.

### T-6 · «Миқдорга қараб нарх» алгоритми — 4 сервер + 3 клиент нусха
- **Нима:** `platform_pricing.js:110`, `functions_demand/api/wholesale_orders.js:113`, `restaurant_qty_tiers.js:45`, `wholesale_orders.js:433`; клиент: `lib/models/price_tier.dart`, `restaurants/domain/qty_tiers.dart:68`, `wholesale_pack.dart`.
- **Хавф:** 🔧. **Статус:** CONFIRMED (қисман паритет тестлари бор).
- **Таклиф:** серверда битта `tierUnitPrice(tiers, qty)` (platform_pricing'да), қолганлари чақиради. Клиент нусхалари — фақат кўрсатиш, векторли тест билан қолади.
- **Ҳажм/устуворлик:** S / P3.

### T-7 · Маҳаллий такси нархи клиентда (double, hardcode)
- **Нима:** `lib/utils/fare_calculator.dart:13–17` (`baseFare = 5000`, `pricePerKm = 1500`, `pricePerMin = 200`, double коэффициентлар) ва масофа коэффициенти `:62` — серверда `functions/local_taxi.js:56` `distanceCoefPermille` (бутун сон). `lib/features/local_taxi/services/price_service.dart` — ҳеч ким ишлатмайди.
- **Хавф:** 💰🙂 — эски APK клиент нархини кўрсатади/юборади; сервер нархи DEPLOYED (memory: «app build pending»).
- **Статус:** CONFIRMED (такрор); қайси APK қайси нархни ишлатаётгани — INFERRED.
- **Таклиф:** клиент фақат сервер quote'ини кўрсатсин; `FareCalculator` ни минимал версиядан кейин олиб ташлаш; `price_service.dart` — ўчириш.
- **Ҳажм/устуворлик:** M / P2.

### T-8 · Ресторан тарифи стандартлари local_taxi'дан кўчирилган
- **Нима:** `restaurant_delivery_tariff.js:26–33` (тун 1500‰, 23–06, йўл коэфф. 1300‰) = `local_taxi.js:25–30`; demand'да йўл коэфф. **1.35** (`functions_demand/core/config.js:67`, `geo/geo.js:27`).
- **Хавф:** 🔧 — бир хил «йўл коэффициенти» 1.30 ва 1.35. **Статус:** CONFIRMED.
- **Таклиф:** `tariff_defaults.js` (сервер) — ягона константалар; demand қиймати эга қарори билан бир хил қилинсин (UNKNOWN қайси тўғри).
- **Ҳажм/устуворлик:** S / P3.

### T-9 · AVA ҳақи — бир ҳужжат, икки маъно
- **Нима:** `settings/restaurant_delivery.avaFeeBps`: ресторанда йўқ бўлса **200 bps** (`restaurant_delivery_tariff.js:69`); бизнес буюртмада `business_orders.js:190` `resolveAvaFee` — **0**, >0 бўлса рад (ва `:639`да фақат `version` узатилади). Клиент `lib/features/admin_web/utils/restaurant_fee_draft.dart:13` `kRestaurantStandardFeeBps = 200` — сервер константасининг нусхаси.
- **Хавф:** 🔧🙂 (админ «2 %» кўради, бизнесда 0). **Статус:** CONFIRMED.
- **Таклиф:** бизнес буюртма учун алоҳида калит (`businessAvaFeeBps`) ёки ҳужжатда аниқ иккита майдон; стандарт қийматни сервер callable жавобида қайтариш, клиент константасини олиб ташлаш.
- **Ҳажм/устуворлик:** S / P3.

### T-10 · `weighHoldPercent` стандарти (10) 5 марта
- **Нима:** `supermarket.js:989, 1198, 1516, 1642` + клиент `admin_supermarket_service.dart:50,80`.
- **Хавф:** 🔧. **Статус:** CONFIRMED. **Таклиф:** `DEFAULT_WEIGH_HOLD_PERCENT` битта константа + `holdPercentOf(doc)`.
- **Ҳажм/устуворлик:** S / P4.

### T-11 · Логистика тарифи нусхаси — ТЎҒРИ бошқарилган (маълумот учун)
- `functions/logistics_tariff.js` = `functions_demand/core/tariff.js` нусхаси, `functions/tools/sync_logistics_tariff.js` + парите тести — **1/1 ўтди** (2026-11-28). Шу нақш (sync тоол + байт-ба-байт тест) бошқа нусхалар учун намуна. Ўзгартириш керак эмас.

---

## 4. B. ҲАМЁН / LEDGER / ҚАЙТАРИШ / ТЎЛОВ

### W-1 · Ҳамённинг 3 кўриниши ва 17 та тўғридан-тўғри ёзувчи  〔ТОП-1〕
- **Нима:** баланс `users/{uid}.bonusBalance` (проекция), тарих `users/{uid}/wallet_ledger` (кўзгу), ҳақиқий
  икки томонлама ledger `ledger_accounts` / `journal_entries` (`passenger_credit:{uid}`, `settlement_ledger.js`).
  `bonusBalance` ни ўзгартирадиган файллар: index.js (50), realty.js (8), settlement_ledger.js (8), telegram_wallet_bot.js (6),
  account_deletion, car_insurance, supermarket, restaurant_orders (5 тадан), assistant_chat, splash_ads (4), ev_charging (3),
  business_orders, incentives, wholesale_orders (2), courier_payout, restaurant_bookings, taxi_billing (1).
  `wallet_ledger` га тўғридан-тўғри ёзиш — 14 файл (index.js 36). Ҳар модулнинг ўз «кўзгу» функцияси бор
  (масалан `wholesale_orders.js:490` `mirrorWallet`, «restoran `commitFeeInTx` bilan bir xil»).
  Инвариант текшируви бор: `settlement_ledger.js:492` (`passenger_credit.balance == users.bonusBalance`).
- **Хавф:** 💰🗄 — бирор йўл ledger'ни четлаб `bonusBalance`ни ўзгартирса, проекция ва ledger ажралади; retry/idempotency ҳар жойда алоҳида.
- **Статус:** CONFIRMED (ёзувчилар сони); ҳозирги дрейф ҳажми — UNKNOWN (prod ўқилмади).
- **Таклиф:**
  1. `settlement_ledger.post(..., { mirrorBonus: true, walletLedgerType })` — ЯГОНА йўл (у аллақачон кўзгуни бир транзакцияда ёзади).
  2. Node «линт» тести: `bonusBalance` / `collection('wallet_ledger')` ни `settlement_ledger.js`дан ташқарида ёзиш — тақиқ (мавжудлари рухсат рўйхатида, ҳар модул кўчгач рўйхатдан чиқади).
  3. Аввал инвариант текширувини prod'да **dry-run** (фақат ўқиш) — дрейф борми.
  4. Кўчириш модуллар бўйича, ҳар бири алоҳида deploy (idempotency калитлари сақланади). Эски APK'га таъсир йўқ.
- **Ҳажм/устуворлик:** L / P1 (инвариант текшируви — S, дарҳол).

### W-2 · Клиент чақирмайдиган эски пул йўллари  〔ТОП-2〕
- **Нима:** `index.js:2773` `debitForOrder` — ўз ҳамёнидан ёки admin/superadmin/**dispatcher** бошқанинг ҳамёнидан
  ечади; `:2688` `creditSupplier`; `:5920` `requestPayout` + `:6188` `checkWithdrawalLimit` (`payout_requests`) —
  янги ечиш йўллари `requestWalletWithdraw` (Telegram бот, `adminReviewWalletWithdraw`) ва `walletToCash`/`cashExchange`
  билан **параллел**. `confirmPayout`/`rejectPayout` ва `payout_management_screen.dart` ҳали жонли.
  Жорий клиентда (`fjobs`) `debitForOrder`, `creditSupplier`, `requestPayout`, `checkWithdrawalLimit` га ҳавола **йўқ**.
- **Хавф:** 💰🔒 — фойдаланилмайдиган, лекин ишлайдиган пул эндпоинтлари; dispatcher роли ортиқча ҳуқуқ.
- **Статус:** INFERRED (жорий клиент чақирмайди; эски APK ва ички скриптлар — UNKNOWN).
- **Таклиф:** 30 кунлик чақирув логини текшириш (Cloud Logging, фақат ўқиш) → 0 бўлса `placeOrderWithWallet` каби
  `failed-precondition` стубга айлантириш → кейин ўчириш. `payout_requests`да `pending` ҳужжатлар борлигини олдин текшириш
  (бор бўлса — админ ёпади). `debitForOrder`дан dispatcher'ни дарҳол олиб ташлаш.
- **Ҳажм/устуворлик:** S–M / P1.

### W-3 · Икки бонус «валютаси»
- **Нима:** рағбат — `users.incentiveBalance` + `incentive_ledger` (`incentives.js`, эга қарори 2026-11-02), қариндош/оила бонуслари ҳам `incentive_grants` (`holiday.js`, `family_links.js`); лекин `grantBirthdayBonus` (index.js) ва `claimCarProfileBonus` — `bonusBalance` (ҳақиқий ҳамён пули).
- **Хавф:** 🔧🙂 — «бонус» қаерга тушиши модулга боғлиқ. **Статус:** CONFIRMED (дизайн — эга қарори).
- **Таклиф:** ҳужжатлаштириш (46-банд): қайси бонус ечиладиган пул, қайси — фақат харид учун; янги бонуслар фақат incentive двигатели орқали.
- **Ҳажм/устуворлик:** S / P3.

### W-4 · Модулларнинг ўз «кўзгу» ёрдамчилари
- W-1 нинг бир қисми: `mirrorWallet` (wholesale), restaurant `commitFeeInTx`, supermarket/realty/ev ичидаги ёзувлар — бир хил
  `{type, amount, module, refType, refId, meta, createdAt, createdBy}` шакли 14 жойда қўлда йиғилади.
- **Таклиф:** W-1 даги ягона `post()` га кўчганда ўз-ўзидан йўқолади. **Ҳажм/устуворлик:** W-1 билан.

---

## 5. C. МОДЕРАЦИЯ, АВТО-ТАСДИҚ, БОСҚИЧ ДАРВОЗАЛАРИ

### C-1 · Авто-тасдиқ калитлари — 9+ та, 2 хил ёзиш усули  〔ТОП-7〕
- **Нима (`settings/app`):**

  | Калит | Ўқийди | Ёзади | Аудит |
  |---|---|---|---|
  | `datingAutoApprove` | index.js:778 | `adminSetDatingAutoApprove` | callable |
  | `marketAutoApprove` | index.js:781 | `adminSetMarketAutoApprove` | callable |
  | `jobsAutoApprove` | index.js:786 | `adminSetJobsAutoApprove` | callable |
  | `producerVerifyAutoApprove` | factories.js:33 | `adminSetProducerAutoApprove` | callable + audit |
  | `deviceBindingAutoApprove` | index.js | `adminSetDeviceBindingAutoApprove` | callable |
  | `tvAutoApprove` | index.js:15177 | **клиент тўғридан-тўғри** `tv_clips_moderation_screen.dart:1008` | йўқ |
  | `shopItemAutoApprove` | market_moderation.js:180 | **клиент** `listing_moderation_screen.dart:39` | фақат `UpdatedBy` |
  | `wholesaleProductAutoApprove` | wholesale_import.js:147 | **клиент** `wholesale_moderation_screen.dart:489` | йўқ |
  | `realtyAutoApprove` (йўқ = **ЁҚИҚ**) | realty.js:497,637 | **клиент**, 3 экранда: `realty_moderation_screen`, `realty_settings_admin_panel.dart:169`, `listing_moderation_screen` | йўқ |
  | `restaurantAutoApprove` | **ўқилмайди** (restaurant_orders.js:693) | `adminSetRestaurantAutoApprove` (:1029) | ўлик |

- **Хавф:** 🔒 (41-банд — модерацияни ўчириш аудитсиз), 🙂 (стандарт қийматлар турлича), 🔧.
- **Статус:** CONFIRMED.
- **Таклиф:** битта callable `adminSetModerationMode({key, enabled, reason})` → `settings/app.<key>` (номлар ўзгармайди —
  backward compat) + `admin_audit`; rules'да бу калитларни клиент-админ ёзувидан ёпиш (alohida rules deploy); админда битта
  «Модерация режимлари» блоки (ҳар бир модерация экрани ўша виджетни қайта ишлатади). `restaurantAutoApprove` сеттерини
  стубга айлантириш. `realtyAutoApprove` стандартини ўзгартириш — фақат эга қарори билан (UNKNOWN).
- **Ҳажм/устуворлик:** M / P2.

### C-2 · Босқич дарвозалари (off/internal/pilot/public) — ҳар модулда ўзича
- **Нима:** `testerIds` + `stage` ни ўқийдиган 14 файл: business_orders, china_inquiries, customer_confirm, holiday,
  restaurant_bookings, restaurant_orders, restaurant_sections_config, supermarket, demand logistics/wholesale_orders/config…
  Ҳужжатлар: `module_config/{restaurants_all,logistics_all,wholesale_orders_all}`, `server_config/business_orders`,
  `settings/{assistant,supermarket,restaurant_bookings,restaurant_sections}`, `china_inquiry_config/main`, `insurance_config/main`, `incentive_programs.stage`.
- **Хавф:** 🔧🙂 — «pilot» маъноси турлича (баъзида internal'га тенг), хато бир жойда тузатилса бошқасида қолади.
- **Статус:** CONFIRMED. **Таклиф:** `functions/stage_gate.js` (`accessOf(cfg, uid, districtId)` — `business_orders.js:175` дагидек) + demand нусхаси sync тоол орқали; ҳужжат жойлари ўзгармайди.
- **Ҳажм/устуворлик:** M / P3.

### C-3 · Ҳолат ўтиш жадваллари
- **Нима:** 10 та `TRANSITIONS` (business_order_states, car_insurance, china_inquiries, restaurant_bookings, restaurant_orders ×2,
  splash_ads, index.js `ADMIN_ORDER_TRANSITIONS`:9302, CARPET/AGRO). `orders` коллекцияси учун фақат админ ўтишлари
  марказлашган; курьер/мижоз ўтишлари index.js бўйлаб сатр литераллари (`status` + `courierStatus` майдонлари).
  Клиентда сервер жадвалининг нусхаси: `restaurants_admin_screen.dart:129` `_adminTransitions`.
- **Хавф:** 🔧🗄 (17-банд). **Статус:** CONFIRMED (жадваллар), `orders` ўтишлари тарқоқлиги — INFERRED.
- **Таклиф:** `orders` учун `order_states.js` (бизнес буюртмадаги каби) — барча ёзувчилар `assertTransition()`; клиент жадвалини серверга `allowedNext` майдони сифатида чиқариш.
- **Ҳажм/устуворлик:** M / P3.

### C-4 · Супермаркет — икки қаватли дарвоза  〔ТОП-10〕
- **Нима:** `lib/models/service_module_config.dart:68` да модул id `supermarket` («Ҳудудлар ва хизматлар», `geo_district_modules`)
  ва `functions/supermarket.js:288–300, 408` `settings/supermarket.{stage, testerIds, districtIds}` — ўз туман рўйхати.
  Шу нақш ресторанда (`module_config/restaurants_all`) ва логистикада ҳам бор, лекин у ерда туман рўйхати такрорланмайди.
- **Хавф:** 🙂🔧 — админ бир жойда ёқади, иккинчисида ўчиқ қолади → «модул кўринади, лекин буюртма рад».
- **Статус:** CONFIRMED.
- **Таклиф:** қоида: гео дарвоза = кўриниш (қаерда), stage = чиқариш босқичи (кимга). `districtIds`ни
  `geo_district_modules`дан олиш ёки админда икки қаватни битта саҳифада кўрсатиш (ҳозирги ҳолат + огоҳлантириш).
- **Ҳажм/устуворлик:** M / P2.

---

## 6. D. ГЕО ЁРДАМЧИЛАР

### D-1 · Haversine — 4 сервер + 4 клиент нусха
- **Сервер:** `local_taxi.js:72` (R=6371000), `realty_alerts.js:53` (6371), `taxi_fraud.js:55` (6371), `functions_demand/geo/geo.js:50` (**6371.0088**).
- **Клиент:** `lib/core/geo/region_centers.dart:37`, `ev_charging/controllers/ev_trip_planner.dart:585`, `restaurants/domain/restaurant_models.dart:72`, `lib/services/geo_math_service.dart:26` (+ 16 жойда `Geolocator.distanceBetween`).
- **Хавф:** 🔧 (масофа чегарасида 1–2 м фарқ). **Статус:** CONFIRMED.
- **Таклиф:** серверда `geo_math.js` (local_taxi'дагини манба), клиентда `GeoMathService` ягона; demand — sync тоол.
- **Ҳажм/устуворлик:** S / P3.

### D-2 · Нусхалар паритет тести билан — ТЎҒРИ (маълумот)
- `geo_hash.js` (default ↔ demand) — тест **16/16 ўтди**; `local_taxi.resolveRegionKey` ↔ `lib/utils/taxi_price_region.dart`; `uz_bounds_parity_test.dart`. Ўзгартириш керак эмас.

### D-3 · Курьер тоифалари нусхаси қўлда
- **Нима:** `functions_demand/core/courier_scopes.js` (43 қатор) — `functions/courier_scopes.js` даги `requestedScopes/isScopeActive` нинг қўлда нусхаси (тест `functions_demand/test/courier_scopes_leg.test.js`).
- **Хавф:** 🔧🔒 — sync тоол йўқ. **Статус:** CONFIRMED.
- **Таклиф:** ўқиш мантиғини алоҳида `courier_scopes_core.js` га ажратиб, sync тоол + байт-ба-байт тест.
- **Ҳажм/устуворлик:** S / P3.

---

## 7. E. ХАБАРНОМА МАТНЛАРИ ВА ТИЛ КАЛИТЛАРИ

### E-1 · Push матнлари: 2 луғат + юзлаб ичма-ич матн
- **Нима:** `functions/notif_i18n.js` (66 калит, `render`, `appLang`) ва `functions_demand/notify/wholesale_notify.js:424,437`
  (74 калит, ўз `render` ва `appLang` ўқиши — кодбаза `require` қила олмагани учун). Луғатдан ташқари кирилл `title:`
  матнлари: index.js **57**, car_insurance 14, market_moderation 8, family_links 8, holiday 8, supermarket 6, splash_ads 5,
  telegram_wallet_bot 5, demand logistics 4, product_promo 4, yuk_local/yuk_intercity/shop_links 2… Кўпи фақат uz_Cyrl.
  FCM тўғридан-тўғри чақирувлари: index.js 19 + 6 файл.
- **Хавф:** 🙂 (3 тил қоидаси бузилади — рус/лотин фойдаланувчига кирилл), 🔧.
- **Статус:** CONFIRMED (сонлар), ҳар бир матн бир тилли эканлиги — қисман INFERRED.
- **Таклиф:** янги матн — фақат `notif_i18n` калити орқали (линт тести); demand луғатини `sync` тоол билан генерация
  қилинадиган нусхага айлантириш; index.js даги 57 матнни босқичма-босқич калитга кўчириш (энг кўп юбориладиганидан).
  Битта `sendPush(uid, key, params)` ёрдамчиси.
- **Ҳажм/устуворлик:** M / P2.

### E-2 · Клиент тил калитлари
- **Нима:** `assets/lang/uz_Cyrl.json` — 6 632 калит; **490** та матн бир нечта калитда (жами 973 ортиқча калит),
  масалан «Қайта уриниш» — 13 калит, «Сақлаш» — 13, «Бекор қилиш» — 11. Такрорий калит таърифи — 0.
- **Хавф:** 🔧 (таржимада номувофиқлик). **Статус:** CONFIRMED.
- **Таклиф:** мавжудларини тегмаслик (рус тилида контекст фарқ қилиши мумкин); янги код учун `common_*` калитлари ва `tools/check_lang_parity.js`га огоҳлантириш.
- **Ҳажм/устуворлик:** S / P4.

### E-3 · Транслитерация (кирилл↔лотин) — 4 нусха
- **Нима:** сервер: `functions/search_tokens.js` (`marketToLatin/marketToCyrillic`, index.js:8816 ишлатади) ва
  `functions/market_search_tokens.js:51–83` (`foldLatin/toLatin/toCyrillic` — клиентдан «сўзма-сўз» кўчирилган);
  клиент: `lib/core/utils/uz_script.dart:60,84` ва `lib/features/ads/utils/ad_search_text.dart:27,75`.
- **Хавф:** 🙂 — қидирув токенлари ва сўров токенлари турли қоидада ясалса, натижа топилмайди. **Статус:** CONFIRMED.
- **Таклиф:** серверда `search_tokens.js` ягона (market_search_tokens уни чақиради), клиентда `UzScript` ягона; умумий векторли тест (Node + Dart).
- **Ҳажм/устуворлик:** S / P3.

---

## 8. F. ПАРАЛЛЕЛ МАЪЛУМОТ ОМБОРЛАРИ

### F-1 · Маҳсулот — 4 коллекция, Аралаш 5 манба  〔ТОП-9〕
- **Нима:**
  - `ads` type `cheap_product` — ёзиш UI ўлик (`create_ad_screen.dart` фақат ўлик `sell_hub_screen.dart`дан), лекин `submitMarketAd` жонли ва клиентда `market_ad_service.dart:21` бор;
  - `tv_shop_items` — ягона дўкон омбори (Аралаш «+», «Менинг дўконим»);
  - `platform_products` — AVA дўкони **ва** супермаркет таклифлари (`smGroupId`) бир коллекцияда;
  - `wholesale_products` — ичида 59 та `pp_<platformId>` нусха (2026-11-01 migration); клиент уларни Аралашда яширади (`wholesale_product.dart:205`), серверда синхрон триггер **йўқ** (`platform_products` учун фақат promo триггери).
  - Аралаш `cheap_products_screen.dart` 5 манбани ўқийди (ads, tv_shop_items, platform_products, wholesale_products, search_index).
- **Хавф:** 🗄 (`pp_*` ва асли ўртасида нарх/қолдиқ ажралиши), 💸 (5 та query), 🙂.
- **Статус:** CONFIRMED.
- **Таклиф:**
  1. `pp_*`: ҳақиқат манбаини танлаш (эга қарори — UNKNOWN): ёки Улгуржидаги `pp_*` асосий (асли «AVA дўкони» сифатида
     фақат кўрсатилади), ёки `platform_products` → `pp_*` бир томонлама синхрон триггер (idempotent, dry-run).
  2. `ads` cheap_product: янги ёзишни ёпиш (`submitMarketAd` → минимал версиядан кейин стуб), фаол эълонларни
     `tv_shop_items`га dry-run/backup/rollback билан кўчириш (27-банд), эскиларни муддати тугагунча кўрсатиш.
  3. Супермаркет таклифлари — rules ҳимоя қилади (`firestore.rules:1927–1943`), ҳозирча бир коллекцияда қолиши мумкин.
- **Ҳажм/устуворлик:** L / P2.

### F-2 · Байрам саватлари (`holiday_baskets`) — янги клиентда ишлатилмайди
- **Нима:** янги ягона саватча `users/{uid}/sm_lists` (`supermarket/domain/sm_basket.dart`, эга 2026-11-28) 3 тайёр
  саватни алмаштирди. `buildHolidayBasket` клиент методи (`holiday_repository.dart:41`) — чақирувчи йўқ; лекин админ ҳали
  `holiday_baskets`ни таҳрирлайди (`admin_holiday_service.dart:39,61`), сервер `adminUpsertHolidayBasket`/`buildHolidayBasket`/`getHolidayCatalog` (holiday.js:712–768) жонли; `getHolidayCatalog` байрамлар учун ҳали керак.
- **Хавф:** 🔧🙂 (админ фойдасиз ишни қилади). **Статус:** INFERRED (янги APK ҳали ўрнатилмаган; эски APK саватни ишлатади).
- **Таклиф:** янги APK тарқалгач админдаги «Саватлар» бўлимини яшириш; `buildHolidayBasket` — минимал версиядан кейин стуб; коллекция маълумоти сақланади (ўчирмаслик).
- **Ҳажм/устуворлик:** S / P3.

### F-3 · Буюртма омборлари
- **Нима:** `orders` (platform, bread, restaurant, business, supermarket — subtype'лар), `carpet_wash_orders`, `agro_pickup_orders`,
  `collection_tasks`, `wholesale_orders`, `logistics_orders` + `shipments`, `splash_ad_orders`, `restaurant_bookings`, `insurance_*`.
  Умумий ўқиш модели `order_index` бор (`order_index.js`), memory бўйича prod'да бўш (backfill ишга туширилмаган) — UNKNOWN ҳозир.
- **Хавф:** 🔧🙂 (админ «Барча буюртмалар» тўлиқ эмас). **Статус:** CONFIRMED (омборлар), `order_index` ҳолати — UNKNOWN.
- **Таклиф:** омборларни бирлаштирмаслик (13-банд модели тўғри); `order_index`ни ягона ўқиш модели қилиш — барча турлар триггер билан, backfill dry-run.
- **Ҳажм/устуворлик:** M / P3.

### F-4 · `sm_weekly_screen.dart` номи эскирган
- Файлда энди `SmOtherListsScreen`, `SmSavedListScreen`, `SmListEditorScreen` (ҳафталик экран олиб ташланган). Маълумот ягона (`sm_lists`) — тўғри. Таклиф: файл номини ўзгартириш. S / P4. CONFIRMED.

---

## 9. G. КЛИЕНТ: ЎЛИК ЭКРАН ВА ВИДЖЕТЛАР

Усул: `lib/` даги ҳар файлнинг ҳамма класс/функция номлари бошқа ҳеч бир `lib/` файлида учрамаса — «ўлик» (тестлар ҳисобга олинмаган). Статус — **INFERRED** (динамик чақирув йўқлиги текширилган эмас).

### G-1 · Ўлик экранлар
| Файл | Изоҳ |
|---|---|
| `features/orders/screens/orders_screen.dart` (~560 қ.) | буюртмалар «Хабарлар»га кўчган (memory ҳам тасдиқлайди) |
| `features/sell/screens/sell_hub_screen.dart` (~330) + `features/ads/screens/create_ad_screen.dart` (~800, фақат sell_hub'дан) | эски cheap_product формаси (F-1) |
| `features/intercity_taxi/driver/screens/intercity_driver_messages_screen.dart` | — |
| `features/tv_market/screens/hls_spike_test_screen.dart` (~285) | спайк тест экрани |
| `features/tv_market/screens/tv_owner_clips_screen.dart` | — |
| `features/profile/screens/wallet_partner_program_screen.dart`, `wallet_operations_tab.dart` | — |

### G-2 · Ўлик виджет/модел/сервислар
`driver_home/widgets/{driver_hero_card, online_pulse_toggle, queue_card, seats_card, trip_request_card, trip_request_dialog}.dart`,
`marshrut/driver/widgets/online_toggle_tile.dart`, `profile/widgets/trip_card.dart`, `tv_market/widgets/{tv_ad_renew_sheet, tv_vitrine_section}.dart`,
`bread/widgets/bread_history_card.dart`, `models/{cart_item, driver_client_stats, driver_seat_live, feed_item, ride_model}.dart`,
`repositories/{marshrut_tariff_repository, pending_code_repository}.dart`, `services/driver_role_service.dart`,
`local_taxi/services/price_service.dart`, `core/splash_taglines_holder.dart`.

### G-3 · Эски бош саҳифа бўлимлари (енгил дизайндан кейин)
`home/widgets/home_intercity_section.dart`, `home_yuk_local_section.dart` — ҳеч ким импорт қилмайди; `home_realty_section.dart` —
импорт бор, символлари ишлатилмайди; `HomeServicesOlxRow` — фақат ўз файлида.

- **Хавф (G):** 🔧 (APK ҳажми, қидиришда чалғитиш; эски кодни «тузатиш»га вақт кетади). 
- **Таклиф:** битта «тозалаш» PR (refactor feature'дан алоҳида, 31-банд): ҳар файл учун `flutter analyze` + тестлар;
  `create_ad_screen.dart` — F-1 қарорига боғлиқ. Эски APK'га таъсир йўқ (клиент коди).
- **Ҳажм/устуворлик:** M / P3 (≈36 файл, бир неча минг қатор).

---

## 10. H. АДМИН ЭКРАНЛАРИ ВА СОЗЛАМАЛАР

### H-1 · Етказиш ҳақи % муҳаррири 2 жойда
- `platform_products_admin_screen.dart:723–837` (`_PlatformDeliveryFeeBar`) ва `supermarket_admin_screen.dart:1179–1355` (`SmDeliveryFeeSource`) — иккаласи `AdminMarketService.setPlatformDeliveryFeePercent` → `adminSetPlatformDeliveryFeePercent` (сервер версиялайди).
- **Хавф:** 🙂 (паст — манба битта). **Статус:** CONFIRMED (эга 2026-11-28 онгли қўшган).
- **Таклиф:** битта жойда таҳрир, иккинчисида «фақат ўқиш + ўша саҳифага ҳавола». S / P4.

### H-2 · `realtyAutoApprove` — 3 экранда (C-1 га қаранг). S / P2 (C-1 билан).

### H-3 · Курьер ҳақи — 4 муҳаррир (T-2 га қаранг). M / P2 (T-2 билан).

### H-4 · Ўлик ресторан авто-тасдиқ сеттери
- `restaurant_orders.js:1029` `adminSetRestaurantAutoApprove` «эски админ панеллар учун» қолдирилган, калит ўқилмайди; клиентда `admin_restaurants_service.dart` методи ҳали бор, UI олиб ташланган (`restaurants_admin_screen.dart:873`).
- **Хавф:** 🔧. **Статус:** CONFIRMED. **Таклиф:** клиент методини ўчириш, сервер — стуб. S / P4.

### H-5 · `platform_products` икки админ экранида
- `platform_products_admin_screen.dart` (AVA дўкони) ва `supermarket_admin_screen.dart` (таклифлар) — бир коллекция; rules супермаркет майдонларини ҳимоя қилади (`firestore.rules:1927–1943`).
- **Хавф:** 🙂 (паст). **Статус:** CONFIRMED. **Таклиф:** AVA дўкони экранида `smGroupId` борларни фильтрлаш/белгилаш. S / P4.

---

## 11. I. CLOUD FUNCTIONS — ТАКРОР ВА ЎЛИК

### I-1 · Deprecated стублар ҳали deploy'да
- `index.js:3007` `placeOrderWithWallet`, `:16631` `floatTopUp`, `:16638` `floatReturn` — фақат хато қайтаради.
- **Хавф:** 💸🔧 (кичик). **Статус:** CONFIRMED. **Таклиф:** чақирув логи 0 бўлса — ўчириш (`firebase functions:delete` — эга рухсати, 28-банд). S / P4.

### I-2 · Бир марталик migration callable'лари жонли
- `migrateCheapProductTitleLower` (index.js:13541), `migratePhoneFormats` (:16301), `migrateOldBindings` (:7806), `resetSoldStockNow` (:11746), `adminSeedSearchIndex` (:18387), `backfillEngagementIndex` (anon_session_merge.js:203). Ҳаммаси админ билан ҳимояланган (текширилди: тўрттаси), клиентда ҳавола йўқ.
- **Хавф:** 🔒 (админ ҳисоби ўғирланса — оммавий ёзув), 🔧. **Статус:** INFERRED (ишлатилмайди).
- **Таклиф:** `functions/tools/` скриптларига (Admin SDK, dry-run билан) кўчириш ва callable'ларни ўчириш. S / P3.

### I-3 · `functions/index.js` — 19 791 қатор, 200 export
- Ҳамён, буюртма, такси, модерация, push — бир файлда; W-1/E-1 даги такрорларнинг асосий манбаи.
- **Хавф:** 🔧. **Таклиф:** янги код — фақат модулларда; мавжудини W-1 (ҳамён) ва E-1 (push) доирасида босқичма-босқич ажратиш. L / P3.

### I-4 · Қидирув токени ясовчилар — 3 та
- `index.js:8816` `buildMarketSearchTokens`, `search_tokens.js` `buildSearchIndexTokens`, `market_search_tokens.js:83` `buildSearchTokens` (prefix'лар билан, лимит 60). E-3 билан бирга ҳал қилинади. S / P3. CONFIRMED.

---

## 12. J. КОДБАЗАЛАР ОРАСИДАГИ НУСХАЛАР ВА «ЖОНЛИ МАНБА»

### J-1 · `module_gate.js` нусхаси йўқолган + жонли код кўп бранчда  〔ТОП-3〕
- **Нима:**
  - Commit **00b0e0ae** (2026-10-31) `functions_demand/api/capabilities.js` га `moduleGate.moduleOpenFor(... activeDistrictId)` қўшган
    (`requestCapability(courier)` — модул ёпиқ туманда курьер аризаси рад).
  - Commit **25f8177d** (2026-11-27, «functions_demand = mainline + ЖОНЛИ demand линияси») `functions_demand/core/module_gate.js`
    (234 қ.) ва унинг эмулятор тестини **ўчирган**; ҳозир `functions_demand` да `module_gate` ҳаволаси йўқ.
  - `functions/tools/sync_module_gate.js` ва `functions/test/module_gate_parity.test.js` қолган → тест **ЙИҚИЛАДИ** (ENOENT, 2026-11-28 ишга туширилди).
  - Умумий сабаб (memory): 513 жонли функция кўп бранчдан ном бўйича deploy қилинган; mainline ↔ жонли фарқлари бор
    (масалан realty.js fix 5465ac6c жонли эмас, `purchaseRealty*` 3 та mainline'да янгироқ).
- **Хавф:** 🔒🗄 — нусха «тўхтаб» қолса ёки ўчса, хавфсизлик текшируви сезилмай йўқолади; кейинги mainline deploy жонли тузатишларни қайтариб юбориши мумкин.
- **Статус:** mainline'да йўқлиги — CONFIRMED; жонли demand'да ҳам йўқлиги — INFERRED (commit хабари «жонли линия» дейди; gcf-sources zip текширилмади).
- **Таклиф:**
  1. Жонли `requestCapability` манбасини gcf zip орқали текшириш (memory'даги рецепт).
  2. Йўқ бўлса — `node functions/tools/sync_module_gate.js` + `capabilities.js` га 00b0e0ae дарвозасини қайтариш, эмулятор тести, ном бўйича deploy.
  3. Барча парите тестларини битта `npm test` га улаш (ҳозир алоҳида ишга туширилади) — нусха ўчса deploy'дан олдин йиқилсин.
- **Ҳажм/устуворлик:** S / P1.

### J-2 · Парите тести CRLF'да йиқилади (сохта хато)
- `functions/test/capabilities_model_parity.test.js` — `core.autocrlf=true` worktree'да **0/1** (фақат сарлавҳа қатор охири фарқи);
  git blob'ларда нусха манба билан **айнан бир хил** (текширилди).
- **Хавф:** 🔧 (сохта хато ҳақиқий хатони яширади). **Статус:** CONFIRMED.
- **Таклиф:** тестда `\r\n` → `\n` нормаллаштириш ёки `.gitattributes` `eol=lf`. S / P4.

### J-3 · Нусха усуллари турлича
- Sync тоол + байт-ба-байт тест: `logistics_tariff` (1/1 ✔), `capabilities_model` (J-2), `module_gate` (J-1 ✘), `geo_hash` (16/16 ✔).
  Қўлда нусха + мантиқ тести: `courier_scopes` (D-3), `wholesale` қадоқ (T-5), `wholesale_notify` луғати (E-1).
- **Таклиф:** ҳамма нусхалар учун ягона `functions/tools/sync_shared.js` (манба→нусха рўйхати) + битта парите тести. S / P3.

---

## 13. Тавсия этилган тартиб (PROPOSED)

1. **Дарҳол (P1, S):** J-1 (жонли дарвозани текшириш/қайтариш), W-2 (лог → стуб, dispatcher'ни олиб ташлаш), T-1, T-3, W-1 инвариант dry-run.
2. **Кейинги спринт (P2):** W-1 кўчириш бошланиши, T-2, C-1 (+rules алоҳида), T-4, C-4, E-1, T-7, F-1 қарори.
3. **Режали (P3/P4):** қолганлари; G — битта тозалаш PR.

Ҳар бир қадам — алоҳида commit/deploy, тест + rollback билан (29, 31-бандлар). Rules — алоҳида командада.

## 14. Ҳисобот (51-банд)

- **Нима қилинди:** фақат ўқиш аудити; ушбу ҳужжат.
- **Нима ўзгармади:** код, config, Firestore rules, production маълумот, deploy — ҲЕЧ НАРСА.
- **Тестлар (фақат ўқиш, 2026-11-28, `dup-audit` worktree):** `logistics_tariff_parity` 1/1 ✔ · `geo_hash_parity` 16/16 ✔ ·
  `module_gate_parity` 0/1 ✘ (нусха файли йўқ — J-1) · `capabilities_model_parity` 0/1 ✘ (CRLF — J-2, blob'лар бир хил).
  Бошқа suite'лар ишга туширилмади (код ўзгармаган).
- **Migration:** ҳозир керак эмас; F-1, T-2, W-1 таклифлари migration режаси (dry-run/backup/rollback) билан.
- **Deploy:** йўқ.
- **Очиқ саволлар (эгага):**
  1. `pp_*` нусхалар: ҳақиқат манбаи Улгуржими ёки AVA дўкони (F-1)?
  2. `ads` cheap_product'ни ёпиб, `tv_shop_items`га кўчирамизми (F-1)?
  3. Такси комиссияси 200 bps — созламага чиқарамизми (T-4)?
  4. Йўл коэффициенти: 1.30 ёки 1.35 (T-8)?
  5. `realtyAutoApprove` стандарти (йўқ = ёқиқ) сақлансинми (C-1)?
  6. Эски `payout_requests` йўли (`requestPayout`) ва `debitForOrder` ни ёпишга рухсат (W-2)?
