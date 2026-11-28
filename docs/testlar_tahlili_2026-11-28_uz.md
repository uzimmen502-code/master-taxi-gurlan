# Тестлар таҳлили — 2026-11-28

**Вазифа (эга, 2026-11-28):** барча тест тўпламлари 0 хато билан, такрорланадиган тарзда ўтсин.
Ҳар бир йиқилган ёки «гоҳ ўтиб, гоҳ йиқиладиган» тестнинг илдиз сабаби топилсин ва синфланди:
**A** — маҳсулотдаги ҳақиқий хато (код тузатилади), **B** — эскирган тест (тасдиқланган хатти-ҳаракатга
мосланади), **C** — муҳитга боғлиқ (тест герметик/детерминистик қилинади).

**Манба:** сервер — `fix/failing-tests` (origin/feat/ev-trip-planner `d6ac6e18` устида);
клиент — `feat/factories-jobs` `dbddaf8c` (жонли). Deploy ҚИЛИНМАДИ, production'га ёзилмади.

## Қандай ишга туширилади (такрорлаш учун)

```
cd functions
npm run test:all          # functions/test — 250 файл
npm run test:all-demand   # functions_demand/test — 64 файл
```

`functions/test/run_all_suites.js` ҳар бир `*.test.js` файлни алоҳида node жараёнида, кетма-кет
ишга туширади. Ҳар файлдан олдин у ишлатадиган `demo-*` лойиҳаларнинг эмулятор маълумоти
тозаланади (олдинги файл қолдиғи таъсир қилмайди). Эмулятор конфиги — `firebase.tests.json`
(Firestore 18311, Storage 19311, Auth 19312 — Windows динамик диапазонидан ташқари, бошқа
сессияларнинг 18080/18180/19199 портлари билан тўқнашмайди).

Windows эслатмаси: `firebase emulators:exec` тугагач Firestore JVM жараёни баъзан ўчмай қолади ва
кейинги ишга туширишда «port taken» беради — фақат ЎЗ портингиздаги (18311) `java.exe`ни ўчиринг.

## Натижа (тузатишдан кейин, икки марта кетма-кет)

| Тўплам (файл даражасида) | 1-марта | 2-марта |
|---|---|---|
| functions/test (250 файл) | 250 ўтди, 0 йиқилди | 250 ўтди, 0 йиқилди |
| functions_demand/test (64 файл) | 64 ўтди, 0 йиқилди | 64 ўтди, 0 йиқилди |
| flutter test (fjobs, `dbddaf8c`) | 5072 ўтди, 33 skipped, 0 хато | 5072 ўтди, 33 skipped, 0 хато |

Сервер: \
pm run test:all\ + \	est:all-demand\, ҳар бири тоза эмуляторда, икки марта кетма-кет (commit 688449e5). Flutter 2-марта сервер тестлари билан БИР ВАҚТДА (юклама остида) ишлади — барибир 0 хато.

Тузатишдан ОЛДИН (биринчи тўлиқ ишга тушириш): functions 250 дан 8 файл йиқилди, functions_demand
64 дан 2 файл йиқилди; flutter 0 хато (5072 ўтди, 33 ўтказиб юборилди).

Flutter'даги 33 «skipped» — атайлаб: 2 та скриншот тўплами фақат `AVA_SCREENS=1` да ишлайди;
сервер↔клиент мослик тестлари клиент чекаутида сервер файллари бўлмагани учун ўтказилади
(`test/support/server_checkout.dart` — тўлиқ чекаутда ишлайди). Хато эмас.

## Жадвал: тест → сабаб → синф → тузатиш → commit

| Тест | Илдиз сабаб | Синф | Тузатиш | Commit |
|---|---|---|---|---|
| `functions/test/module_gate_cf` R1 (кафе рўйхатдан ўтиши) | Тест `status: 'applied'` кутарди. Эга қарори 2026-10-31 (commit `ac7f663e`): янги кафе ДОИМ дарҳол `approved`. Тест янгиланмай қолган. | B | Кутилган қиймат `approved` (иккала жавобда ҳам). | 688449e5 |
| `functions/test/wholesale_card_cf` (6 та текширув) | `refuse()` ёрдамчиси курьер «Етказилмади» деса буюртма дарҳол `refused` бўлади деб кутарди. Эга қарори 2026-11-01 (`8e131584`, `functions_demand/api/wholesale_failed.js`): курьер хабари фақат СЎРОВ, рад — харидор тасдиғи билан. `functions_demand` 25f8177d да кўчирилганда бу тест янгиланмаган. | B | Ёрдамчи икки қадамли ҳақиқий оқимни юради: курьер хабари (`in_delivery`, `awaitingBuyer`) → харидор `confirm` → `refused`. Пул текширувлари ўзгармаган. | 688449e5 |
| `functions_demand/test/offers_tx_emulator` (5 та LEG текшируви) | Курьер тоифаси қоидаси (эга 2026-10-31, `adapters/logistics.js` `courier_scope`): манзили йўқ LEG «republic» ҳисобланади ва оддий (district) курьерга берилмайди. Тест fixture'ида LEG манзилсиз эди. | B | Fixture'га туман ичидаги манзил (`gurlan → gurlan`) қўшилди — тест бекор қилиш/контакт мантиғини текширади, тоифани эмас. | 688449e5 |
| `functions/test/capabilities_model_parity`, `module_gate_parity` | Windows'да `core.autocrlf=true`: манба файл CRLF, нусха сарлавҳаси LF бўлиб, мазмун бир хил бўлса ҳам байт фарқ қиларди. | C | `sync_*` асбоблари ва тестлар қатор охирини LF'га келтириб солиштиради. | 688449e5 |
| `functions_demand/test/notify_dispatch` | `dispatchNotifications` ичида `new Date()` — тинч соатлар (23:00–07:00 Тошкент = 18:00–02:00 UTC) да тест `quiet_hours` сабабли йиқиларди. Соат +16 силжитилганда эски тест 3 та хато берди (исбот). | C | `makeDispatchNotifications({ nowFn })` — ихтиёрий соат манбаи (стандарт — ҳақиқий вақт, хатти-ҳаракат ўзгармаган). Тест қатъий 12:00 Тошкент ишлатади. Янги текширув: 23:30 да push йўқ, 22:59 да бор. | 688449e5 |
| `functions/test/realty_alerts_cf` «create» | Вақт бомбаси: fixture эълони муддати `2026-10-08 + 20 кун = 2026-10-28`; `createRealtyAlert` ҳақиқий `Date.now()` билан солиштиради — шу санадан кейин эълон «муддати ўтган». | C | Муддат ҳақиқий вақтга нисбатан ҳам келажакда (`max(DAY_NOON, now) + 20 кун`). | 688449e5 |
| `functions/test/supermarket_cf` C5, `splash_ads_cf` P6, `wallet_order_credit_cf` O1, `delivery_failed_cf`, `functions_demand/test/wholesale_failed_emulator` | Параллел транзакцияlар (иккита бир хил чақирув). Firestore emulator (v1.21.0) қулф тўқнашувида бирини `ABORTED` билан қайтаради (SDK қайта уради), иккинчисининг осилиб қолган ўқишини ~9 с дан кейин `3 INVALID_ARGUMENT: Transaction is invalid or closed.` билан ёпади. Admin SDK (`@google-cloud/firestore` 6.8 `isRetryableTransactionError`) INVALID_ARGUMENT'ни фақат `/transaction has expired/` матнида қайта уради — бу production backend'нинг матни; эмулятор матни бошқа. Юклама остида 5–6 тадан 2–3 тасида йиқиларди. | C | `functions_demand/test/helpers/emulator_hooks.js` `installEmulatorClosedTxRetry`: ФАҚАТ шу эмулятор матнида бутун транзакция қайта ишга туширилади (≤3 марта) — production SDK хатти-ҳаракатини такрорлайди. Бизнес хатолар ўзгармайди, «битта ғолиб / битта ёзув» инвариантлари текширилади. Runner ҳар файлга юклайди; 5 та тестда ҳам аниқ ёзилган. Текширув: юклама остида 12/12 ва 10/10 параллел ишга тушириш — 0 хато. | 688449e5 |
| `functions/test/admin_panel_audit_cf` M8/M9 | Admin PIN билан кириш `setCustomUserClaims` + `createCustomToken` чақиради — Auth emulator керак (тест сарлавҳасида ёзилган). Эмуляторсиз SDK `metadata.google.internal` дан токен сўраб йиқиларди. | C | Runner Auth emulator'ни ишга туширади ва уни фақат сарлавҳасида `--only firestore,auth` деб ёзилган тестларга беради (`order_index_cf` ҳам). | 688449e5 |
| `functions/test/storage_catalog_rules`, `storage_restaurant_rules` | Storage rules'даги cross-service `firestore.get()` Firestore'ни эмулятор ишга туширилган ЛОЙИҲАДА ўқийди; тест эса бошқа `demo-*` лойиҳага ёзарди → «unauthorized». | C | Runner storage тестларини эмулятор лойиҳасида ишга туширади. | 688449e5 |

## «Transaction is invalid or closed» — production'да бўладими?

Хулоса: **INFERRED — йўқ** (production'да бу ҳолат `ABORTED` ёки «transaction has expired» бўлиб, SDK
ўзи қайта уради; иккинчи чақирув сақланган натижани кўради — `duplicate`/`idempotent`). Далил:
SDK манбаси (`node_modules/@google-cloud/firestore/build/src/transaction.js`,
`isRetryableTransactionError`) ва хато фақат эмуляторда, ~8.5 с кутишдан кейин чиқиши
(`placeSupermarketOrder` логида `duration: 8514`). Шунинг учун маҳсулот коди ўзгартирилмади.
Эслатма: агар production'да 5 марта қайта уринишдан кейин ҳам тўқнашув қолса, SDK `ABORTED`
қайтаради ва фойдаланувчи «Қайта уриниб кўринг» кўради — пул/буюртма икки марта ёзилмайди
(транзакция + idempotency). Мавжуд намуна (`runTxRetryRaw`, `runCourierSubmitTx`) бошқа функцияларда бор.

## Production код ўзгаришлари

- `functions_demand/notify/dispatch.js` — `makeDispatchNotifications` ихтиёрий `nowFn` олади.
  Стандарт қиймат — ҳақиқий вақт, хатти-ҳаракат ЎЗГАРМАГАН. **Deploy шарт эмас** (кейинги
  demand deploy билан бирга кетса бўлади).
- Бошқа production код ўзгармади. Firestore/Storage rules, индекслар, конфиг — ўзгармаган.

## Очиқ масалалар

- Эмулятор тестларини вақт силжитиш билан текшириб бўлмади (сервер вақти эмуляторда) — соф
  тестлар (functions 56, demand 52 файл) +8 ва +16 соат силжитиш билан ўтди.
- `realtyAlerts.push` логида «Credential … metadata.google.internal» огоҳлантириши қолади (тест
  йиқилмайди; push ҳақиқий FCM'га уриниб ушланади).
