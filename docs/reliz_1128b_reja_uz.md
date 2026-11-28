# Релиз 1128b (сервер) — deploy режаси

> Эга 2026-11-28: «ҳа, бошла» — ҳаммасини битта шохчага бирлаштириш ва тўлиқ тестлар.
> Production — фақат эганинг аниқ «чиқар» сўзидан кейин. Бу ҳужжат ёзилганда deploy ҚИЛИНМАГАН,
> production'га ҳеч нарса ёзилмаган.

- Шохча: `rel/1128b-srv` (worktree `D:\projects\ava_gurlan\.claude\worktrees\rel-1128b-srv`).
- Асос: `origin/feat/ev-trip-planner` `d6ac6e18` (жонли mainline; 2026-11-28 01:23–04:25Z deploy).
- Белгилар: **CONFIRMED** — код/тест/эга сўзи билан текширилган; **INFERRED** — кучли хулоса;
  **PROPOSED** — таклиф; **UNKNOWN** — текширилмаган.

## 0. Бирлаштирилган шохчалар (тартиб билан, `git merge --no-ff`)

| # | Шохча | HEAD | Зиддият |
|---|---|---|---|
| 1 | `fix/failing-tests` | bc152b49 | йўқ |
| 2 | `fix/dup-payout-rounding` | 04466990 | йўқ |
| 3 | `fix/dup-audit-p2-srv` | 680d8631 | йўқ |
| 4 | `fix/dup-audit-p3-srv` | 6cdb35b5 | `functions/index.js` — пастда |
| 5 | `fix/incentive-validate-kind` | ef733da2 | йўқ |
| 6 | `feat/wallet-single-path` | d0762c3c | йўқ |
| 7 | `feat/sm-sample-groups` | 0363b271 | йўқ |
| — | `feat/partner-payout-srv` | — | **БИРЛАШТИРИЛМАДИ** — эга: «Тўлов занжирини кейин қайта кўриб чиқамиз». Шохча ўзгармаган ҳолда қолди. |
| 8 | `feat/birthday-prompt-srv` | 819e128c | йўқ |
| 9 | `feat/qr-web-login-srv` | 3e316960 | йўқ |
| 10 | `feat/splash-house-ad-srv` | 2fcd0f9f | йўқ |

**Зиддият (4):** `functions/index.js`, `retiredEndpoint` блоки. p2 шу блокдаги `ENDPOINT_RETIRED_MESSAGES.uz_Latn`
матнини янги алифбога ўтказган; p3 эса бутун блокни (12 та ишлатилмайдиган функция stub'и билан) олиб ташлаган.
Ечим: p3 томони (блок йўқ). Сабаб: `retiredEndpoint` бошқа жойда ишлатилмайди (текширилди: `retiredAuthEndpoint` —
бошқа функция, `deviceSecurity.secError` орқали, ўзгармаган). p2 нинг uz_Latn ўзгариши шу ўчирилган матнда эди —
йўқолган маъно йўқ. **CONFIRMED** (index.js юкланади, `legacy_money_retired_cf` 12 ном йўқлигини текширади).

**Пул/ҳамён текшируви:** `test/wallet_single_path_lint.test.js` бирлаштирилгандан кейин 6/6 — рухсат рўйхатидан ташқари
янги `bonusBalance`/`wallet_ledger` ёзувчи йўқ, рўйхат кенгаймади. **CONFIRMED.**

## 1. Тестлар (бу шохчада, ҳақиқий ишга тушириш)

Ҳаммаси `functions/test/run_all_suites.js` (ҳар файл алоҳида node жараёни, ҳар файлдан олдин тоза эмулятор),
ўз портлари (Firestore 18531/18551, hub 18532/18552 — >15000), фақат ўз JVM'лари ўчирилди. **CONFIRMED.**

| Тўплам | Натижа |
|---|---|
| functions/test (274 файл), якуний тоза тўлиқ ишга тушириш (`e60d24a2`) | **274 ўтди, 0 йиқилди** |
| functions_demand/test (64 файл, runner) | **64 ўтди, 0 йиқилди** |
| functions_demand `node test/run_all.js` | **1165 тест, 0 хато** |
| `index.js` юкланиши | default **565** export, demand **77** export |
| `npm run build:rules -- --check` | 152 567 B (чегара 262 144), токенлар бир хил |
| `wallet_single_path_lint` | 6/6 |

Биринчи тўлиқ ишга туширишда (бирлаштирилгандан кейин) 3 та файл йиқилди — ҳаммаси **янги** (базада `d6ac6e18` ўтади),
сабаб битта: p2 server uz_Latn матнларини янги алифбога ўтказган, бу 3 тест эски матнни кутарди (синф B — эскирган тест):
`order_news_flow_cf` N13 («AVA do'koni» → «AVA dökoni»), `taxi_intercity_audit_cf` H6 («ga ko'chirildi» → «ga köçirildi»),
`wholesale_debt_pay_cf` («Qarz to'landi» → «Qarz tölandi»). Тузатиш — фақат тест кутилмаси (`e60d24a2`); база 3/3, rel 3/3.
Бир марта `storage_catalog_rules` 600 с осилиб, Storage/hub эмулятори қулади (demand тўплами билан параллел юклама,
muhit — C); қолган 65 файл қайта ишга туширилди ва якуний тоза ишга туширишда ҳаммаси ўтди.
Шунингдек step 0 (`feat/birthday-prompt-srv` 819e128c): `birthday_prompt_cf` 20/20, `birthday_prompt_pure` 13/13.

## 2. Нима ўзгарди — функциялар (ишончли усул)

Усул: иккала дарахтда `index.js` ҳақиқатан юкланди (export рўйхати + `__endpoint` конфиги), кейин ҳар функциянинг
**статик ёпилиши** (export танаси + у ишлатадиган барча top-level декларациялар ва `require` қилинган модуллар аъзолари,
изоҳ ва бўшлиқсиз) SHA-1 билан солиштирилди (`fp.js`, 2026-11-27 жонли инвентаризацияда ишлатилган восита).
Иккинчи ўтишда орқага мос умумий ёрдамчилар асосий нусхага қайтарилиб ҳисобланди («нейтрал»):
`notifyUserInApp` (янги ихтиёрий `newsDocId`, бермаса хатти-ҳаракат айнан эски), `settlement_ledger.js` (янги
`walletPost` экспортлари; `prepareBonusInTx` ctx'га `db` қўшилди) — `reconcile()` ўзгаргани учун уни ишлатувчи
`reconcileLedger`, `closePeriod` қўлда қўшилди.

**Default codebase:** d6ac6e18 — 564 export, rel — 565 export.
- ЯНГИ: 13 · ЎЧИРИЛГАН (манбадан): 12 · ЎЗГАРГАН (хатти-ҳаракат): 142 ·
  фақат орқага мос умумий ёрдамчи ўзгарган: 159 · айнан бир хил: 251 · endpoint конфиги ўзгаргани: 0.

**Demand codebase:** 77 / 77 export. ЎЗГАРГАН: 17 · бир хил: 60.

## 3. Deploy тартиби (хавфсиз)

Ҳамма буйруқлар ШУ пинланган worktree'дан, `--config D:\projects\ava_gurlan\.claude\worktrees\rel-1128b-srv\firebase.json`,
`--project master-taxi-gurlan`. Бирор буйруқ бошқа нарса билан бирлаштирилмайди.

### 3a. Firestore rules — ЁЛҒИЗ, stripped build

```
cd D:\projects\ava_gurlan\.claude\worktrees\rel-1128b-srv
npm --prefix functions run build:rules            # build/firestore_rules/firestore.rules
npm --prefix functions run build:rules -- --check # токенлар бир хил
```
Ҳажм: манба 291 887 B → stripped **152 567 B** (чегара 262 144, бўш 109 577). **CONFIRMED** (`--check`).
Deploy — фақат `build/firestore_rules/firestore.rules` (REST рецепти: ruleset яратиш → матнни build билан
солиштириш → жорий release `0134adf0` эканини текшириш → PATCH release; 503 бўлса release'ни қайта ўқиш).

Ўзгаришлар (жонли `0134adf0` = d6ac6e18 build'ига нисбатан, 51 қатор):
1. `qr_login_watch` (get — 64 hex ID, list йўқ), `qr_web_sessions` (эгаси get) — қўшимча, хавфсиз.
2. `settings/birthday_prompt` — фақат админ ўқийди (мижоз ўқимайди), ёзиш CF.
3. `ledger_reconcile_runs` — `isFinanceReader()` ўқийди, ёзиш CF.
4. **`settings/app` даги 12 та `*AutoApprove` майдонини админ клиенти тўғридан-тўғри ёза олмайди**
   (`moderationModeSettingKeys`). ⚠ Бу банд **admin web `adminSetModerationMode`га ўтгандан КЕЙИН** чиқиши керак
   (p2 коммит изоҳи: «alohida deploy, web'dan KEYIN»). Акс ҳолда эски админ панелдаги автотасдиқ калитлари
   PERMISSION_DENIED беради. **INFERRED** (эски admin web шу майдонларни тўғридан-тўғри ёзиши —
   p2 коммит изоҳидан; клиент коди бу ҳужжатда текширилмади).
   Вариант (PROPOSED): web кечикса — rules'ни 4-бандсиз (вақтинча) чиқариш, кейин тўлиқ.

Rollback: ruleset `0134adf0-4426-4ae4-8632-9327fb7c110c` га release PATCH.

### 3b. Индекслар

`firestore.indexes.json` d6ac6e18 га нисбатан **ЎЗГАРМАГАН** (186 индекс, 4 override). Янги сўровлар (`qr_web_sessions`
phone+status тенглик, `users` bonusBalance `!=` бир майдон, `birthday_prompt_runs` startedAt) — композит индекс
талаб қилмайди. **Deploy шарт эмас.** Агар барибир: `firebase deploy --only firestore:indexes` — `--force`СИЗ.

### 3c. Functions — номи бўйича, гуруҳлаб

Умумий шакл (default): `firebase deploy --only "functions:default:A,functions:default:B" --config <abs> --project master-taxi-gurlan`.
Demand алоҳида буйруқда: `--only "functions:demand:X,..."`. ⚠ Ҳеч қачон `--only functions` (ном йўқ) — CLI
12 та ўчирилган функцияни ўчиришни сўрайди.

**Гуруҳ 1 — ЯНГИ (13), стадиялари OFF:**
- `walletInvariantDailyCheck` (ҳар куни 04:00 Тошкент; фақат ўқийди; `ledger_reconcile_runs`)
- `birthdayPromptDaily`, `adminGetBirthdayPromptSettings`, `adminSetBirthdayPromptSettings` (`settings/birthday_prompt` йўқ = OFF)
- `adminSetModerationMode`, `adminGetModerationModes`
- `qrLoginStart`, `qrLoginPeek`, `qrLoginApprove`, `qrLoginConsume`, `qrWebSessionHeartbeat`, `qrWebSessionsList`,
  `qrWebSessionRevoke` (`server_config/qr_web_login` йўқ = OFF)

**Гуруҳ 2 — ЎЗГАРГАН (142), модуль бўйича:**
- 2A пул/яхлитлаш/ҳамён ягона йўли:
  - restaurant_orders (33): adminCancelRestaurantOrder, adminSetRestaurantAutoApprove, adminSetRestaurantDeliveryPrices, adminSetRestaurantFeeSettings, adminSetRestaurantStatus, adminSetRestaurantsStage, courierAcceptRestaurantHandover, courierArriveRestaurantOrder, courierCancelRestaurantHandover, courierClaimRestaurantOrder, courierCompleteRestaurantDelivery, courierPickupRestaurantOrder, courierSetBuyoutPrefs, courierStartRestaurantHandover, customerCancelRestaurantOrder, customerMarkRestaurantOrderPaid, escalateRestaurantDeliveryFailed, expireReturnedRestaurantOrders, expireUnacceptedRestaurantOrders, getRestaurantsAccess, listNearbyRestaurantOrders, placeRestaurantOrder, quoteRestaurantDelivery, restaurantAcceptOrder, restaurantAcceptReturn, restaurantConfirmPayment, restaurantCourierSharePendingSweep, restaurantMarkDelivered, restaurantMarkReady, restaurantRegister, restaurantRejectOrder, restaurantResolveDeliveryFailed, sweepRestaurantCourierLive
  - business_orders (10): businessAcceptOrder, businessMarkReady, businessRejectOrder, courierClaimBusinessOrder, courierCompleteBusinessOrder, courierPickupBusinessOrder, customerCancelBusinessOrder, expireUnacceptedBusinessOrders, placeBusinessOrder, quoteBusinessOrder
  - restaurant_bookings (2): adminRefundBookingFee, restaurantAcceptBooking
  - realty (5): purchaseRealtyPackage, purchaseRealtyProPackage, purchaseRealtyTier, submitRealtyListing, updateRealtyListing
  - car_insurance (2): insuranceAgentCancel, insurancePayRequest
  - splash_ads (4): adminDeleteSplashAd, adminModerateSplashAdOrder, adminUpsertSplashAd, splashAdPurchase
  - holiday (1): buildHolidayBasket
  - taxi_billing (4): publishTaxiTrip, quoteTaxiFee, repriceTaxiTrip, rescheduleTaxiTrip
  - courier_payout (2): courierPayoutReconcile, onRelayEarnedCourierPayout
  - delivery_failed (4): courierReportDeliveryFailed, escalateDeliveryFailed, listDeliveryFailedPending, resolveDeliveryFailed
  - delivery_quotes (4): acceptDeliveryQuote, listOpenDeliveryQuotes, requestDeliveryQuote, respondDeliveryQuote
  - customer_confirm (3): adminSetCustomerConfirmation, customerConfirmHandover, getCustomerPendingConfirmations
  - relay_cash (2): onRelayCashShipmentUpdate, relayCashReconcile
  - relay_escrow (3): adminRecordLostParcelPayment, onLogisticsShipmentUpdate, relayEscrowReconcile
  - wholesale_orders (7): adminRecordWholesaleLostFeePayment, onWholesaleCustodyEvent, onWholesaleOrderStatusChange, onWholesaleShipmentLoss, payWholesaleBuyerDebt, placeWholesaleOrder, wholesaleOrdersReconcile
  - index.js (19): adminSetAgroPickupStatus, adminSetCarpetWashStatus, adminSetDatingAutoApprove, adminSetJobsAutoApprove, adminSetMarketAutoApprove, autoUpdateDepartureTime, closePeriod, courierFinalizeCollection, courierMarkAgroPickedUp, courierMarkCarpetDelivered, courierMarkCarpetPickedUp, onAdUpdate, onOrderUpdate, onTvClipVideoReplacedV2, placeOrderPostPaid, reconcileLedger, saveDatingProfile, submitJobAd, submitMarketAd
- 2B модерация/матн/бошқа:
  - account_deletion (11): adminCancelAccountDeletion, adminGetAccountDeletion, adminGetAccountDeletionGate, adminListAccountDeletions, adminRequestAccountDeletion, adminRetryAccountDeletion, adminSetAccountDeletionGate, cancelAccountDeletion, executeAccountDeletions, previewAccountDeletion, requestAccountDeletion
  - factories (2): adminSetProducerAutoApprove, setMyFactoryOptions
  - incentives (2): adminSetIncentiveStage, adminUpsertIncentiveProgram
  - market_moderation (1): renewMarketListing · wholesale_import (1): wholesaleImportConfirm
  - china_inquiries (1): adminAddChinaQuote · deal_chats (1): sendDealMessage
- **2C AVA Супермаркет — WEB + APK ДАН КЕЙИН** (эга: «аввал web ва APK, кейин server functions»; бирликлар g/ml/box/m):
  - supermarket (12): adminRemoveSupermarketLine, adminReportSupermarketShortage, adminSetSupermarketPartnerAutoApprove, adminSetSupermarketSettings, adminSetSupermarketTaxonomy, adminSettleSupermarketWeights, adminUpsertSupermarketOffer, getSupermarketAccess, onSupermarketOrderCancelStock, partnerUpsertSupermarketOffer, placeSupermarketOrder, respondSupermarketShortage
  - supermarket_import (6): adminSupermarketImportConfirm, adminSupermarketImportPreview, adminSupermarketImportTemplate, partnerSupermarketImportConfirm, partnerSupermarketImportPreview, partnerSupermarketImportTemplate
  - ⚠ Шу файлда ҳамён ягона йўли ва яхлитлаш ҳам бор — 2C кечикса, супермаркетнинг шу ўзгаришлари ҳам кечикади (жонли код ишлайверади).

**Гуруҳ 3 — фақат орқага мос умумий ёрдамчи ўзгарган (159):** deploy ШАРТ ЭМАС (хатти-ҳаракат айнан эски).
Кейинги ўз ўзгариши билан бирга кетади. (Рўйхат: шу ҳужжат охирида, илова А.)

**Гуруҳ 4 — d6ac6e18 билан бир хил, лекин жонлида бўлмаслиги мумкин:** default'да 251 бир хил функция;
11-28 01:31Z ва 04:25Z deploy'дан кейин уларнинг жонли нусхаси = d6ac6e18 деб хотирада ёзилган (**INFERRED**, бу ҳужжатда
жонли манба қайта солиштирилмади). Demand `requestCapability` — 11-28 deploy'да чиқарилмаган (хотира); бу релизда
ўзгармаган. Deploy'дан олдин жонли инвентаризация (fp.js) билан текшириш керак — **UNKNOWN**.

**Demand codebase — алоҳида буйруқ (17):** createDemand, cancelAssignment, scanHandover, adminPlanShipmentRoute,
adminReactivateLeg, adminReopenChainLeg, quoteWholesaleOrder, onWholesaleOrderCreated, markWholesaleBuyerRefused,
respondWholesaleDeliveryFailed, resolveWholesaleDeliveryFailed, wholesaleDeliveryFailedSweeper, onWholesaleOrderUpdated,
wholesaleShipmentReconcile, onShipmentFunded, legChainSweeper, onProviderAvailable
(сабаб: `core/money_math.js` + Ulgurji avaFeeOf half_up, `notify/wholesale_notify.js` ва `api/logistics.js` uz_Latn
матнлари, `notify/dispatch.js` nowFn).

Тавсия тартиби: 1 → 2B → 2A → demand → (web+APK) → 2C. Ҳар гуруҳдан кейин функция версияси ва логлар.

### 3d. `functions:delete` — ЭНГ ОХИРИДА, фақат эга «ҳа» деганда

12 та функция (17-банд, `docs/takrorlanishlar_17_band_2026-11-28_uz.md`): debitForOrder, requestPayout,
checkWithdrawalLimit, placeOrderWithWallet, floatTopUp, floatReturn, driverFloatStatus, adminWebSignInWithCode,
promoteToAdminWithPin, appendAdminSystemChat, migrateCheapProductTitleLower, migratePhoneFormats.
```
firebase functions:delete <12 ном> --region us-central1 --project master-taxi-gurlan --config D:\projects\ava_gurlan\.claude\worktrees\rel-1128b-srv\firebase.json
```
Rollback: d6ac6e18 дан номи бўйича қайта deploy (базада stub сифатида бор).

### 3e. Эга / production скриптлари (тартиб билан, ҳаммаси аввал DRY RUN)

1. `node functions/tools/hide_platform_copies_in_wholesale.js` (dry-run) → `--apply` (`--expect 59`, backup, admin_audit, rollback).
2. `node functions/tools/wallet_history_corrections.js --apply` — **ҲАЛИ БАЖАРИЛМАГАН** (classifier рад этди, эга ўзи
   ишга туширади: ***3355 −153 211 601, ***8777 −1 500). `walletInvariantDailyCheck` биринчи ишлашидан ОЛДИН маъқул
   (акс ҳолда биринчи ҳисобот маълум фарқни кўрсатиши мумкин — **INFERRED**).
3. `node functions/tools/create_splash_house_ad.js` (dry-run) → `--apply` — splash_ads функциялари (2A) deploy'дан КЕЙИН.
4. Бажарилган (такрорланмайди): `fix_wallet_8777_cancel_refund.js --apply` (11-28), taxonomy v1→v2 + assign 10 + mark 10
   (11-28 ~10:12Z). Ресторан номлари lotin migration: 0 та ўзгариш (хотира) — керак эмас.

### 3f. Эга админда/консолда қўядиган созламалар (ҳаммаси сукут бўйича OFF)

- `settings/birthday_prompt` — админ callable `adminSetBirthdayPromptSettings` (stage off → internal → pilot → public).
- `server_config/qr_web_login` {stage, testerIds} — админ callable ЙЎҚ; эга консолда қўяди (**CONFIRMED**: qr_web_login.js
  фақат ўқийди). Ихтиёрий: `qr_login_sessions`/`qr_login_watch` учун Firestore TTL (`expireAt`) — эга қарори.
- Модерация режимлари — қийматлар ўзгармайди (ўша майдонлар), фақат ёзиш йўли `adminSetModerationMode`.
- Супермаркет `courierPayout.percentBps` / `weighHoldBps` — эски `percent`/`weighHoldPercent` ×100 ўқилади, шарт эмас.
- Splash уй рекламаси — скрипт `--off` билан ўчирилади.

### 3g. Rollback (ҳар қадам)

| Қадам | Rollback |
|---|---|
| Rules | release → `0134adf0` (REST PATCH) |
| Индекслар | ўзгармаган |
| Functions (ўзгарган) | базавий worktree `d6ac6e18` дан ўша номлар бўйича deploy (`--config <база>\firebase.json`) |
| Functions (янги) | стадия OFF (ҳужжат йўқ = OFF); зарур бўлса `functions:delete` (эга OK) |
| functions:delete | d6ac6e18 дан номи бўйича қайта deploy |
| Скриптлар | ҳар бирида backup + `--rollback` |

### 3h. Клиент / APK боғлиқлиги

- Супермаркет бирликлари: `feat/sm-units-samples` web + APK → кейин 2C.
- Модерация rules банди (3a-4): admin web (`fix/dup-audit-p2` клиент) аввал.
- QR кириш: web + APK (`feat/qr-web-login`) — сервер OFF стадияда олдин чиқса зарари йўқ.
- Туғилган кун эслатмаси: клиент `user_info` экрани (`birthday_prompt` push тури) — APK'да йўқ бўлса push «Хабарлар»га
  тушади (**INFERRED**). Хабар энди битта: `admin_news/birthday_prompt_{998…}` ҳар юборишда алмаштирилади.
- Splash уй рекламаси: `feat/splash-house-ad` клиент (Бош экран мегафони, тугмасиз).
- Яхлитлаш: `getSupermarketAccess` эски APK учун `weighHoldPercent` қайтаради (орқага мос).

## 4. Хавфлар

- Rules 3a-4 web'дан олдин чиқса — админ автотасдиқ калитлари ишламайди.
- 2C кечикса — супермаркет ҳамён/яхлитлаш ўзгариши ҳам кечикади (жонли код ишлайверади, инвариант текшируви фақат ўқийди).
- 142 функция — катта deploy; гуруҳлаб, ҳар гуруҳдан кейин логлар.
- `walletInvariantDailyCheck`: ҳар куни `bonusBalance != 0` фойдаланувчилар + ledger ҳисоблари + шу uid'лар
  `wallet_ledger` ўқилади — reads/кун фойдаланувчилар сонига боғлиқ (**INFERRED**, ўлчанмаган).
- Шериклар тўлови (`feat/partner-payout-srv`) — бу релизда йўқ.

## 5. Очиқ саволлар (эга)

- Шериклар тўлови занжири — эга кейин қайта кўради (комиссия яхлитлаш ceil → half_up масаласи ҳам шу ерда).
- Rules 3a-4: admin web қачон? Ёки rules'ни икки босқичда чиқарамизми?
- `server_config/qr_web_login` стадиясини ким/қачон қўяди; TTL ёқилсинми?
- Гуруҳ 3 (159) ва 4 ни ҳам ҳозир чиқарамизми (бир хил хатти-ҳаракат) ёки фақат 1/2?

## Илова А — Гуруҳ 3 (159, фақат орқага мос ёрдамчи)

addRealtyTeamMember, adminAutoApproveDeviceBinding, adminCloseChinaInquiry, adminDecideDeviceApproval, adminDeleteRealtyListing, adminGetCourierServiceFee, adminGetFamilyBonusPrograms, adminGetTaxiCommission, adminGetWalletBotSettings, adminInsuranceGetSettings, adminInsurancePublishTariff, adminInsuranceSaveCampaign, adminInsuranceSaveConfig, adminListDeviceApprovals, adminListLossIncidents, adminManualApproveDeviceBinding, adminMarkChinaInquirySent, adminModerateListing, adminModeratePromo, adminRejectDeviceBinding, adminResolveEvReport, adminRestoreRestaurantBookings, adminReviewWalletTopUp, adminReviewWalletWithdraw, adminSetChinaInquiryConfig, adminSetChinaInquiryTextZh, adminSetCourierServiceFee, adminSetEvStationActive, adminSetOrderStatus, adminSetOrderStatusBatch, adminSetProductDiscount, adminSetRealtyCounts, adminSetRealtyStatus, adminSetRestaurantBookings, adminSetTaxiCommission, adminSetWalletBotSettings, adminSplashAdGetSettings, adminSplashAdPublishTariff, adminSplashAdSaveConfig, adminUpdateEvStationStatus, adminUpsertChinaSupplier, adminUpsertFamilyBonusProgram, adminUpsertHolidayBasket, adminUpsertHolidayOccasion, adminUpsertRelativesBonusProgram, adminWithdrawChinaQuote, assistantBuyPackage, assistantChat, assistantDeleteConversation, assistantDeleteMemory, assistantGetStatus, assistantPriceSearch, assistantRenameConversation, cancelChinaInquiry, cancelRestaurantBooking, cancelTaxiTrip, checkDeviceBinding, claimCarProfileBonus, claimRelativesBonus, completeLocalTrip, completeTaxiTrip, confirmPayout, courierMarkAgroPickupArrived, courierMarkArrived, courierMarkCarpetArrived, courierMarkCollectionArrived, courierSubmitPayment, createChinaInquiry, createTelegramLinkCode, creditChange, creditSupplier, customerCancelOrder, deleteRealtyListing, ensureMyTree, expireRestaurantBookings, fundShipmentEscrow, getChinaInquiryAccess, getEvStationTariffs, getHolidayCatalog, getMoneyControlSnapshot, getMyFamilyLinks, getRealtyPackagePricing, getRealtyPricing, getRealtyProPlans, getRealtyQuota, getWalletTopUpReceiptUrl, getWalletTopUpStatus, grantBirthdayBonus, holidayReminders, insuranceAgentCorrect, insuranceAgentIssuePolicy, insuranceAgentListRequests, insuranceAgentStart, insuranceCancelMyRequest, insuranceChooseCarOffer, insuranceCreateRequest, insuranceExpiryReminders, insuranceGetMyState, insuranceGetPolicyLink, insuranceGetTechPassportLinks, insuranceListServiceReports, insuranceQuote, insuranceSetMyExpiry, insuranceSubmitServiceReport, insuranceTechPassportPurge, insuranceUploadTechPassport, inviteRelative, inviteSpouse, linkRealtyVideo, marketListingsExpirySweep, marketListingsExpiryWarning, onAssistantMessageCreated, onBirthDateRequestUpdate, onDeviceChangeRequestUpdate, onEvConfirmationWrite, onEvReportCreate, onLogisticsCustodyEvent, onPlatformProductPromoWrite, onRelativeBirthdayIndex, onRelativePersonWrite, onSellSubmissionUpdate, onShopItemModeration, onShopItemPromoWrite, onTvClipApproved, onTvClipRejected, onUserProfileReady, onWholesaleProductPromoWrite, onWholesaleStockBadge, payAndCreateEvStation, placeRestaurantBooking, productPromoExpirySweep, publishTvAd, realtyExpirySweep, realtyExpiryWarning, recordSplashImpressions, removeRealtyTeamMember, renewTvAd, requestDeviceAdminReview, requestDeviceTransfer, requestWalletWithdraw, respondDeviceTransfer, respondRelativeInvite, respondSpouseInvite, restaurantCancelBooking, restaurantRejectBooking, sellerPlaceSale, sellerSubmitPickupPayment, sendTreeLinkInvite, smGiftPiiSweep, splashAdGetPurchaseInfo, splashAdListMyOrders, splashAdQuote, splashAdsExpireDaily, telegramWalletBotWebhook, unlinkRealtyVideo, unlinkRelative, unlinkSpouse, unlockRealtyListing, walletTopUpExpirySweep
