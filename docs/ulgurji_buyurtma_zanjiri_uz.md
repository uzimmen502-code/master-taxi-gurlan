# Улгуржи бозор — буюртма занжири: лойиҳа ва босқичлар

> Сана: 2026-10-31. Ҳолат: 1-босқич (қадоқ + қолдиқ) LIVE; 2–6 — қурилмоқда.
> Манба: эга қарорлари (чат, 2026-10-31) + код таҳлили (relay, ҳамён, ресторан).

## 1. Эга қарорлари — CONFIRMED

| # | Қарор |
|---|---|
| Q-1 | Харидор **ҳамёндан олдиндан** тўлайди (товар + етказиш). Пул AVA'да ушланади. |
| Q-2 | Ҳудуд — **бутун Ўзбекистон**. |
| Q-3 | Етказиш — **фақат AVA курьерлари** (сотувчи ўзи етказмайди). |
| Q-4 | AVA улуши ва курьер ҳақи — **админда таҳрирланади** (версияли, audit). |
| Q-5 | Пул сотувчига — курьер **«етказилди» кодини** киритганда, автоматик. |
| Q-6 | 14×14 вилоят матрицаси ва 20 кг+ нархлар — админда бўш жадвал, рақамларни эга/админ киритади. |
| Q-7 | Юридик тасдиқ кутилмайди — **ички синов режими** (тестчилар) билан қурилади; ҳаммага очиш — эга қарори. |
| Q-8 | Қадоқ ≤5 (ҳар бирининг поғонаси, ихтиёрий расми), сонли қолдиқ харидорга кўринади; битта ихтиёрий видео. |

## 2. Архитектура — PROPOSED (мавжуд тизимлар устида, параллел тизим йўқ)

Икки сервер коди умумий код ишлатмайди (`functions` = ҳамён/ledger, `functions_demand` = relay/курьер).
Улар **Firestore ҳужжатлари орқали** боғланади (relay'даги `shipments.paymentStatus` каби).

```
харидор ── quoteWholesaleOrder (demand) ──► wholesale_quotes/{id}   (сервер ёзади, 15 дақиқа)
        └─ placeWholesaleOrder (default) ─► 1 транзакция: квота текшируви, қолдиқ −N,
                                            ҳамён Dr passenger_credit / Cr escrow:wholesale:{order},
                                            wholesale_orders/{id} = placed
demand триггер `onWholesaleOrderCreated` (wholesale_orders onCreate, `placed`) ─► relay shipment АВТОМАТИК (эга = сотувчи, олувчи = харидор),
                                            1 direct LEG (вилоятлараро — икки ҳудудни қамраган
                                            курьер/юк; бўлиш — admin `adminPlanShipmentRoute`)
         (сотувчи қабул/рад ҚИЛМАЙДИ — эга, 2026-10-31; буюртма дарҳол етказишга ўтади)
default триггер (wholesale_orders onUpdate):
   placed → in_delivery (shipment очилганда) → етказиш ҳақи escrow:wholesale → escrow:{shipmentId}
   cancelled → харидорга тўлиқ қайтариш + қолдиқ +N (идемпотент)
default триггер (custody delivery, мавжуд onLogisticsCustodyEvent):
   wholesaleOrderId бор → товар пули: сотувчига (товар − AVA улуши), AVA улуши earnings:ava_wholesale_fee
```

- **Нарх** — фақат серверда: қадоқ поғонаси (`priceForQty` қоидаси, `platform_pricing.js` билан бир хил)
  × миқдор; етказиш — relay тарифи (`module_tariffs/logistics_v*`, `tariffVersion` муҳрланади).
- **AVA улуши** — `settings/wholesale_orders.avaFeeBps` (админ callable, audit, версия буюртмада муҳрланади).
- **Қолдиқ** — `wholesale_stock/{productId}` (1-босқич), камайиш/қайтиш фақат транзакцияда.
- **Идемпотентлик** — ҳар пул ҳаракати ўз калити билан (`wholesaleHold:{order}`, `wholesaleRelease:{order}`,
  `wholesaleRefund:{order}`, `wholesaleShipFund:{order}`); `placeWholesaleOrder` — `clientRequestId`.
- **Дарвоза** — `module_config/wholesale_orders_all.{enabled, stage, testerIds}` (logistics андозаси):
  `internal` + тестчилар; ҳаммага очиш — эга.
- **Relay ўзгаришлари** (минимал): shipment'да `recipientId` (харидор) — `getShipmentSecrets`
  deliveryCode'ни олувчига ҳам беради; `source: 'wholesale'`, `wholesaleOrderId`; ички яратиш
  ёрдамчиси (callable'сиз, `createShipmentInternal`) — эга текшируви чақирувчи функцияда.

### Буюртма ҳолатлари (сервер state machine)

`placed → in_delivery → delivered`; `placed → cancelled` (харидор, етказиш очилмагунча);
`placed | in_delivery → cancelled` (admin, курьер ҳали олмаган бўлса); ҳар ўтиш — `history` (immutable). **Сотувчи буюртмага аралашмайди** (қабул/рад йўқ, эга 2026-10-31).

## 3. Босқичлар

| # | Нима | Ҳолат |
|---|---|---|
| 1 | Қадоқ, қолдиқ (`setWholesaleStock`), битта видео | **LIVE** 2026-10-31 |
| 2 | Сервер: квота, буюртма, ушлаш, қолдиқ −N, бекор + қайтариш, дарвоза, AVA улуши созламаси (сотувчи қабул/рад йўқ) | **LIVE** 2026-10-31 (ёпиқ: дарвоза ҳужжати йўқ), rules c2dc93b7 |
| 3 | Relay боғлаш: буюртма берилиши билан shipment АВТОМАТИК, етказиш ҳақи escrow'га, етказилганда товар пули сотувчига | код + тест тайёр (`feat/ulg-orders`), **production'да ҲАЛИ йўқ** (deploy қилинмаган) |
| 3b | «Етказилганда карта орқали» (сервер): сотувчи картаси, ушлаш сотувчи ҳамёнидан, чек + 30 дақ → низо → админ, рад → автоматик қайтиш (ҳақи сотувчидан, қарз/блок), хабарлар — §5 | код + тест (`feat/ulg-card`), **production'да ҲАЛИ йўқ** |
| 4 | Илова: «Буюртма бериш», харидор буюртмалари + кузатув; сотувчига фақат «янги буюртма — курьер олиб кетади» хабари ва рўйхат (қабул/рад тугмаси ЙЎҚ) | — |
| 5 | Админ: буюртмалар, AVA улуши, вилоят матрицаси + 20 кг+ нархлар жадвали (бўш), тестчилар | — |
| 6 | Аҳоли бозори қадоқлари | — |

Ҳар босқич: тест (позитив/негатив/чегара) → rules алоҳида → функциялар номма-ном → hosting.
APK — фақат эга рухсати билан.

## 4. Хавфлар / UNKNOWN

- Шаҳарлараро LEG'ни ким олади — икки вилоятни қамраган курьер ёки «юк» провайдери; бўлмаса LEG
  муддати ўтади → admin `adminReactivateLeg` / `adminPlanShipmentRoute`.
- Тариф матрицаси тўлдирилмаса — квота `zone_not_found` / `tariff_extra_price_missing` → харидорга
  «етказиш нархи ҳали белгиланмаган», буюртма йўқ.
- Курьерга тўлов ҳозир қўлда (`supplier_payable`) — relay каби.
- **3-босқич relay guard'лари ҲАЛИ ЖОНЛИДА ЙЎҚ** (`feat/ulg-relay-guards` бранчи, 2026-10-31): жонли
  relay функциялари (`getShipmentSecrets`, `cancelLogisticsOrder`, `cancelDemand`, `acceptOffer`,
  `fundShipmentEscrow`, `onLogisticsShipmentUpdate`, `onLogisticsCustodyEvent`) lineage'дан фарқ қилади —
  бошқа сессияларнинг тасдиқланмаган ўзгаришлари туфайли қайта deploy қилинмади. Шу пайтгача Ulgurji
  жўнатмасининг эгаси (сотувчи) API орқали: жўнатмани бекор қилиши (`cancelLogisticsOrder`), LEG'ни
  бекор қилиши (`cancelDemand`), ўзи тўлаши (`fundShipmentEscrow` → SHIP_FUND аномалия), **етказиш
  кодини олиши** (`getShipmentSecrets` эгага беради → курьер билан келишиб харидорсиз «етказилди»)
  мумкин; relay REFUND етказиш ҳақини **сотувчи ҳамёнига** қайтаради. Тестларда қулфланган.
  **`module_config/wholesale_orders_all` дарвозаси guard'лар live-merge билан deploy бўлгунча ЁПИҚ турсин.**
  Харидор коди — алоҳида `getWholesaleDeliveryCode`; товар пули — алоҳида `onWholesaleCustodyEvent`.
- Firestore rules ҳажми чегарада (262 031 / 262 144) — янги қоидадан олдин изоҳлар қисқартирилади.

## 5. 3b-босқич — «Етказилганда карта орқали» (сервер)

> Эга қарорлари — CONFIRMED (2026-10-31, якуний; 30 дақиқа — ўша куни 15 дан ўзгартирилган).

| # | Қарор |
|---|---|
| K-1 | Харидор `paymentMethod: 'card_on_delivery'` танлаши мумкин (`wallet` — аввалгидек, стандарт). |
| K-2 | Харидор ҲАММАСИНИ (товар + етказиш) эшик олдида **сотувчи картасига** ўтказади (эквайринг йўқ). |
| K-3 | Сотувчининг ягона амали — «Пул тушди» (`confirmWholesaleCardPayment`). Буюртмани қабул/рад қилмайди. |
| K-4 | Курьер ҳақи + AVA улуши буюртма пайтида **сотувчи ҳамёнидан** ушланади; етмаса — карта усули шу буюртмага ёпиқ. |
| K-5 | Рад/тўламаслик → товар сотувчига қайтади; қайтиш **автоматик**, ҳақи **сотувчи ҳамёнидан** (жорий тариф); етмаса — манфийга тушмайди: `returnDebt` + сотувчининг карта усули ёпилади, ҳамён тўлдирилгач reconcile (10 дақ) тўлайди. |
| K-6 | Қолдиқ **фақат** товар сотувчига қайтганда (`returned`) тикланади; чиқишдаги курьер ҳақи қайтарилмайди. |
| K-7 | Харидор 2 марта рад этгач карта усули унга ёпилади (`CARD_REFUSAL_LIMIT = 2`). |
| K-8 | Харидор чек юборади; сотувчи **30 дақиқада** (`RECEIPT_TIMEOUT_MS`, ягона константа) тасдиқламаса → `payment_dispute` → админ ҳал қилади (confirm → коди очилади; reject → рад + қайтиш). Чек юборилгач курьер «рад» белгилай олмайди. |
| K-9 | Хабарлар (ички + push, 3 тил): сотувчига — янги карта буюртма, чек; харидорга — тўлов тасдиқланди, рад; админларга — низо, қайтиш қарзи; сотувчига — қарз, қайтмоқда, қайтди; қайтиш курьерига — иш бириктирилди. |
| PROPOSED | Рад этилганда сотувчидан ушланган AVA улуши унга қайтарилади (сотув бўлмади). Админ reject ҳам харидор ҳисоблагичига +1. Хабар матнлари. |

### Ҳолатлар (ягона жадвал — `functions_demand/core/wholesale_orders.js`)

```
placed ─► in_delivery ─► delivered
  │            ├─► refused ──(қайтиш тўланди, system)──► returning ──(сотувчига етди, system)──► returned
  │            ├─► payment_dispute ─(admin confirm)─► in_delivery
  │            │                   └(admin reject)──► refused
  └─► cancelled (buyer/admin)      └─► cancelled (admin)
```
Актёрлар: courier — `in_delivery → refused` (фақат охирги LEG ижрочиси, посилка қўлида, тўлов `awaiting`);
system — `in_delivery → payment_dispute`, `refused → returning`, `returning → returned`; admin — низо.
`order.cardPayment.status`: `awaiting → receipt_submitted → confirmed | disputed`. `order.returnStatus`:
`pending_shipment → awaiting_payment → in_transit → returned`.

### Пул (ledger — `functions/settlement_ledger.js`, бутун сўм)

| Қадам | Ёзув | Калит (`journal_entries/…`) |
|---|---|---|
| Буюртма (карта) | Dr `passenger_credit:{сотувчи}` / Cr `escrow:wholesale:{id}` = deliveryFee + avaFee | `bonus:wholesaleHold:{id}` |
| Етказиш эскрови | Dr `escrow:wholesale:{id}` / Cr `escrow:{shipmentId}` = deliveryFee (ўзгармаган) | `wholesaleShipFund:{id}` |
| Етказилди | Dr `escrow:wholesale:{id}` / Cr `earnings:ava_wholesale_fee` = avaFee (сотувчига AVA орқали 0; avaFee=0 — ёзув йўқ) | `wholesaleRelease:{id}` |
| Бекор (эскровдан олдин) | Dr `escrow:wholesale:{id}` / Cr `passenger_credit:{сотувчи}` = тўлиқ ушланма | `bonus:wholesaleRefund:{id}` |
| Рад | Dr `escrow:wholesale:{id}` / Cr `passenger_credit:{сотувчи}` = avaFee (эскров 0) | `bonus:wholesaleRefused:{id}` |
| Рад — чиқиш EARNED (ҳар ишланган LEG) | Dr `platform_accrual` / Cr `supplier_payable:{курьер}` = legPayout (relay ёзуви, курьер тўлови триггери кўради) | `relayEarned:{shipmentId}:{legId}` |
| Рад — чиқиш RELEASE | Dr `escrow:{shipmentId}` = customerPrice / Cr `platform_accrual` Σишланган / Cr `earnings:ava_logistics_fee` platformShare / Cr `passenger_credit:{сотувчи}` Σишланмаган (PROPOSED); эскров 0; жўнатма `paymentStatus: settled` + `wholesaleOutcome: 'refused'` (`status` ўзгармайди — relay машинасида «рад» йўқ), жорий LEG `completed` (`outcome: 'buyer_refused'`), посилка етмаган LEG'лар `cancelled` | `relayRelease:{shipmentId}` |
| Қайтиш ушлаш | Dr `passenger_credit:{сотувчи}` / Cr `escrow:wholesale_return:{id}` = қайтиш нархи | `bonus:wholesaleReturnHold:{id}` |
| Қайтиш эскрови | Dr `escrow:wholesale_return:{id}` / Cr `escrow:{returnShipmentId}` | `wholesaleReturnFund:{id}` |
| Қайтиш етказилди | relay RELEASE (`escrow:{returnShipmentId}` → курьер/AVA), бизда пул йўқ; қолдиқ +N | — |

### Сервер-only ҳужжатлар
`wholesale_sellers/{tel}/private/payout` (тўлиқ карта; тарих `…/history/v{n}` — фақат last4),
`wholesale_buyer_stats/{tel}.cardRefusals`, `wholesale_seller_stats/{tel}.{cardBlocked, debtOrderIds}`.
Оммавий сотувчи ҳужжатида: `hasPayoutCard`, `cardLast4`.

### Карта шифрлаш (эга қарори, 2026-10-31)
- **Нима:** `private/payout` = `{cardNumberEnc, holderNameEnc, last4, encVersion: 1, version, …}` —
  карта рақами ва эгаси исми Cloud KMS (симметрик, ENCRYPT_DECRYPT) билан шифрланган, очиқ
  `cardNumber`/`holderName` ЁЗИЛМАЙДИ. Шакл: `kms:v1:<base64 ciphertext>`; AAD =
  `wholesale_seller_card|v1|{канон тел}|{майдон}` (ciphertext бошқа сотувчига кўчса — KMS рад этади).
- **Калит:** env `WHOLESALE_CARD_KMS_KEY`, default
  `projects/master-taxi-gurlan/locations/europe-west1/keyRings/ava-secrets/cryptoKeys/wholesale-seller-card`
  (`functions_demand/core/card_crypto.js`); функциялар `master-taxi-gurlan@appspot.gserviceaccount.com`.
- **KMS ишламаса:** `setWholesaleSellerCard` — FAIL CLOSED (`card_encryption_unavailable`, ҳеч нарса
  ёзилмайди); `getWholesaleCardPaymentInfo` — `unavailable` / `card_decryption_unavailable`.
  Квота ва `placeWholesaleOrder` декрипт қилмайди (фақат «карта бор» шакли: `payoutDocHasCard`, иккала
  codebase'да бир хил қоида).
- **Эски очиқ ҳужжатлар:** ўқилади (`legacy_plaintext_card` огоҳлантириши); кўчириш —
  `functions_demand/tools/encrypt_seller_cards.js` (dry-run → `--write`; текширувдан кейингина очиқ
  майдонлар ўчади + `admin_audit`; `--restore-plaintext` — фавқулодда орқага).

### Қайтиш жўнатмаси
`refused` бўлиши билан demand триггери `onWholesaleOrderUpdated` жўнатма очади: origin = харидор манзили,
destination = сотувчи, эгаси = олувчи = сотувчи, `source: 'wholesale_return'`, нарх — ўша пайтдаги фаол
тариф (муҳрланади). LEG-1 посилкани ушлаб турган курьерга бириктирилган (`accepted` + match), relay
matching ишламайди; курьер `getWholesaleReturnHandoverCode` коди билан relay `scanHandover`, сотувчи
коди (relay `getShipmentSecrets`) билан relay `confirmDelivery`. Relay функцияларига тегилмаган.

### Очиқ масалалар (UNKNOWN / эга)
- Рад этилганда чиқиш жўнатмаси relay'нинг ўша калитлари (`relayEarned`/`relayRelease`) билан ёпилади — relay кейин ўзи юрса ҳам иккинчи тўлов йўқ (тест билан исботланган). «Ишланган LEG» = индекси ≤ `currentLegId`; посилка етмаган LEG улуши сотувчига — PROPOSED.
- Бириктирилган курьер қайтишни олмаса — LEG'ни админ relay `adminPlanShipmentRoute` билан қайта режалайди.
- `returnAnomaly` (масалан қайтиш нархи муҳрга мос эмас) — ушланма `escrow:wholesale_return` да туради, админ ҳал қилади.
- Рад ҳисоблагичини камайтириш/ноллаш (админ) — қурилмаган.
- Чек: файл Storage'да борлиги сервер томонидан текширилади (`receipt_not_found`), сотувчи чекни `cardPayment.receiptUrl` (Firebase token ҳавола) орқали кўради — Storage'га сотувчи рухсати ЙЎҚ (IAM берилмаган). Storage қоидаси: харидор ўз йўлига ёзади/ўқийди (image/*, <8MB), админ — `isCatalogAdmin()`.