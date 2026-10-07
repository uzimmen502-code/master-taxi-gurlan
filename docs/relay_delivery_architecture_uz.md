# AVA Logistics — Relay Delivery: архитектура таҳлили

Сана: 2026-10-05 · База: `feat/ev-trip-planner` @ `f238c96`
Киришма: `AVA_RELAY_BRIEF.md` · Боғлиқ: `docs/talab_taklif_yadrosi_uz.md`

Белгилар (CLAUDE.md 47-банд): **CONFIRMED** — кодда/ҳужжатда текширилган ·
**INFERRED** — кучли хулоса · **PROPOSED** — таклиф · **UNKNOWN** — етарли
маълумот йўқ. Манба бўйича: **BTS_CONFIRMED** — BTS ҳужжатидан ·
**AVA_DECIDED** — эга қарори.

---

## 1. Хулоса

Relay учун янги ядро қуриш **керак эмас**. Репода `functions_demand`
codebase'ида талаб → таклиф ядроси аллақачон ишлаб турибди: статус
машинаси, таклиф бериш/қабул қилиш транзакциялари, тайинланганни қайта
очиш sweeper'и, trust, matching ва push сиёсати. LEG шу ядродаги `demand`
ҳужжатига деярли тўлиқ тушади — `location`/`destination`, `assignment`,
`termsAcceptedAt`, `tariffVersion`, `payment` майдонлари аллақачон жойида.

Ҳақиқатан етишмайдиган нарса учта: **занжир тартиби** (LEG(n) олдингисининг
топширувига боғлиқ), **атомар икки томонлама custody ҳодисаси**, ва
**ORDER/SHIPMENT устки қатлами**. Қолгани — нарх қатлами, QR инфратузилмаси
ва Flutter томони.

Энг катта риск кодда эмас: `couriers` коллекцияси ҳозир продакшнда очиқ
турибди (`read: if true`, auth'сиз ёзиш) — бу Relay қарорини кутмайдиган,
амалдаги шахсий маълумот оқими. Иккинчи риск — брифдаги намунавий нарх
(90 000 сўм) реал бозор нархининг ~42% и; архитектура кўтара олмайдиган
нарх атрофида қурилмаслиги керак.

---

## 2. Қарорлар реестри

| # | Қарор | Белги | Сана |
|---|---|---|---|
| D-1 | `couriers` сақлаб қолинмайди, provider моделига кўчирилади | AVA_DECIDED | 2026-10-05 |
| D-1.1 | D-1 нинг presence қисми бажарилди (4.3). Қолган қисми — `couriers`ни ЧИҚАРИШ — ЎЛЧОВ БЎЙИЧА БЛОКЛАНГАН, 8-bis бўлимга қаранг | INFERRED | 2026-10-06 |
| **D-12** | **`users.role` ва ХИЗМАТ ҲУҚУҚИ қатъий ажратилади.** `users.role` — фақат аккаунтнинг тизим даражасидаги роли (`user` `admin` `superadmin` `staff`). Хизмат кўрсатиш ҳуқуқи — `provider_capabilities`да. `users.role == 'courier'` каби текширувлардан босқичма-босқич чиқилади | AVA_DECIDED | 2026-10-06 |
| **D-13** | **Битта фойдаланувчида бир нечта capability ПАРАЛЛЕЛ актив бўлиши мумкин** — `taxi` `courier` `freight` `seller` бир-бирини истисно қилмайди. Authorization ҳар бир функция учун ЎЗ capability'сини текширади | AVA_DECIDED | 2026-10-06 |
| **D-14** | **Capability статусини фойдаланувчи ЎЗИГА БЕРА ОЛМАЙДИ.** У фақат ариза беради, ҳужжат юклайди ва ўз presence'ини ўзгартиради. `trial` `approved` `rejected` `suspended` — фақат ишончли сервер ёки админ | AVA_DECIDED | 2026-10-06 |
| **D-15** | **Курьер lifecycle:** `not_registered → trial → document_submitted → under_review → approved`, ёндош ҳолатлар `trial_expired` `document_rejected` `suspended`. Янги курьерга **3 кун** синов; шу муддатда ягона дарча орқали ўзини ўзи банд қилган шахс сифатида рўйхатдан ўтиб, ҳужжат юклаши шарт | AVA_DECIDED | 2026-10-06 |
| **D-15.1** | **3 кун HARD CUTOFF ЭМАС.** Талаб бажарилмаса — **бир марта** 5 кунлик `grace period`. Extension фақат БИР МАРТА берилади. 5 кун ҳам тугаса → courier capability `suspended`, янги буюртма олиш ёпилади. **Аккаунтнинг ўзи очиқ қолади**; ҳужжат юклаб тасдиқдан ўтгач capability қайта `approved` бўлиши мумкин | AVA_DECIDED | 2026-10-06 |
| **D-16** | **Масъулият бўлиниши:** `users` — бу ким · `provider_capabilities` — нима қилишга рухсати бор · `provider_presence` — ҳозир онлайнми ва қаерда · `provider_stats` — қандай ишлаяпти · `courier_documents` — ҳужжатлари борми. `couriers` — ўтиш даври манбаси, якуний authorization source ЭМАС | AVA_DECIDED | 2026-10-06 |
| **D-TAXI / D-SERVICE** | Такси billing (2% = `farePerSeat × 4 × 2%`, 4 ой starter, verification) ва бошқа хизматлар учун умумий қоидалар — **алоҳида реестр:** [taxi_billing_uz.md](taxi_billing_uz.md). Capability lifecycle хизмат бўйича фарқ қилади (T-2); `providerId` барқарорлиги (T-1) ҳал қилиниши керак | AVA_DECIDED | 2026-10-06 |
| D-2 | Тариф архитектураси BTS модели асосида; `ZONE_0`…`ZONE_5`, 6 зона; зона origin↔destination matrix орқали; зона «маъноси» кодга ёзилмайди; эски Z1–Z5 бекор | AVA_DECIDED | 2026-10-05 |
| D-3 | `ORDER` 1:N `SHIPMENT` 1:N `LEG` | AVA_DECIDED | 2026-10-05 |
| D-4 | `SHIPMENT` = битта жисмоний қути, битта штрих-код, битта custody занжири | AVA_DECIDED | 2026-10-05 |
| D-5 | Shipment identity **рақамли** пайдо бўлади: буюртма тасдиқланганда сервер `shipmentId` + `trackingNumber` + `shipmentQR` яратади. Физик стикер мажбурий эмас | AVA_DECIDED | 2026-10-05 |
| D-6 | QR'ни **фақат сервер** яратади. Провайдер ўз телефонида янги QR ярата олмайди — у мавжудини сканерлайди | AVA_DECIDED | 2026-10-05 |
| D-7 | QR яратилиши custody'ни ўтказмайди. Custody фақат физик қабулда ўзгаради | AVA_DECIDED | 2026-10-05 |
| D-8 | **Нарх олдиндан қотади, маршрут қотмайди.** Commercial commitment (зона, вазн, тариф версияси, якуний нарх) буюртмада `PriceSnapshot` сифатида муҳрланади; LEG занжири динамик | AVA_DECIDED | 2026-10-05 |
| D-9 | `Planned Route` ва `Executed Route` ажратилади. `RoutePlan` версияланади (v1, v2…), эскиси ўчирилмайди | AVA_DECIDED | 2026-10-05 |
| D-10 | `Route planning → Leg creation → Provider assignment → Execution` — тўрт алоҳида босқич | AVA_DECIDED | 2026-10-05 |
| D-11 | Тўлов: жўнатувчи → **AVA эскроу** → етказиш тасдиқлангач → провайдерлар + AVA комиссияси. `ESCROW` / `LEDGER` / `PAYOUT` аралаштирилмайди, `EARNED ≠ PAID`. Биринчи версияда фақат `payerSide: 'sender'`. Ҳуқуқий асос ЎРҚ-1173 24 ва 13¹-моддалари (7.5-bis) | AVA_DECIDED | 2026-10-05 |

Қотадиган ва динамик қоладиган нарсалар (D-8…D-10 дан):

| Нима | Қачон қотади |
|---|---|
| `shipmentId`, `trackingNumber`, digital QR | Shipment яратилганда |
| `tariffZone`, `tariffVersion`, `chargeableWeight`, `customerPrice` | Нарх тасдиқланганда |
| Custody | Фақат физик қабул-топширишда |
| Planned route, LEG'лар, LEG provider | Динамик |
| Executed route, provider payout | Амалда бажарилгани бўйича |
| Custody history | Immutable |

---

## 3. Брифни текшириш натижаси

Бу сессияда **ҳаммаси эмас** текширилди. Текширилмаганини «тасдиқланди»
деб кўрсатиш мумкин эмас (CLAUDE.md 33, 47-бандлар).

| # | Даъво | Натижа |
|---|---|---|
| F4 | `couriers/{uid}` да фақат name, phone, isOnline, lat, lng, fcmToken | ⚠️ **қисман** — rules'даги ёзиш рўйхати: `isOnline, lat, lng, name, phone, fcmToken, updatedAt, lastSeen` (`firestore.rules:2464`). Транспорт/ҳужжат/тасдиқлаш йўқ — тасдиқланди |
| F5 | Курьерни аниқлаш `couriers` ёки `users.role=='courier'` | ✅ **тасдиқланди** — `resolveAuthorizedCourierUid` (`functions/index.js:2397`), 9 ва 12 хонали иккала шаклни пайпаслайди |
| F7 | QR, OTP, код ва расм орқали топшириш йўқ | ✅ **тасдиқланди** — бутун репода QR/barcode/scanner/OTP/PIN кутубхонаси ҳам, коди ҳам йўқ |
| F11 | Кузатув `couriers/{uid}` lat/lng, Realtime Database йўқ | ✅ **тасдиқланди** — клиент `couriers_repository.dart:13` орқали тўғридан-тўғри ёзади |
| F17 | Релей, хаб, қабул пункти тушунчаси кодда йўқ | ✅ **тасдиқланди** — `relay/handoff/hub/pickup_point` бўйича фақат `functions_demand` ва тил файлларидаги алоқасиз мослар |
| F1, F2, F3, F6, F8, F9, F10, F12, F13, F14, F15, F16 | — | ⏳ **ҳали текширилмади** — кейинги ўтишда |

### Хавфсизлик

| # | Муаммо | Натижа |
|---|---|---|
| S1 | `delivery_routes`: `read: if true`; `update` да `hasAny([...])` доим ўтади | ✅ тасдиқланди → **тузатилди** (2026-10-06). Тешик кутилгандан кенг эди: курьер ҳатто `orders` ни ҳам алмаштира оларди. `hasAny` → `diff().affectedKeys().hasOnly()` + эгалик + `courierId` ўзгармаслиги. Тест: `functions/test/delivery_routes_rules.test.js` — 18/18. **Деплой қилинмаган** |
| S2 | `couriers`: create/update'да auth ҳам, эгалик ҳам йўқ; read очиқ | ✅ тасдиқланди → **тузатилди** (2026-10-06). `read` → `isAdmin() \|\| isOwner(id)`; create/update'га эгалик шарти қўшилди, майдон рўйхати сақланди. Тест: `functions/test/couriers_rules.test.js` — 16/16. **Деплой қилинмаган** |
| S3 | `payout_requests`: `read: if true` | ✅ тасдиқланди → **тузатилди** (2026-10-06). `read` энди `isFinanceReader() \|\| isAdmin() \|\| isOwner(userPhone)`. Тест: `functions/test/payout_requests_rules.test.js` — 12/12. **Деплой қилинмаган** |
| S4 | **Янги:** `courier_cash:{phone}` калити каноникаллаштирилмаган | ✅ топилди ва **тузатилди** — commit `0d53fdb`; продакшнда бундай ҳисоб бўлмагани учун солиштириш керак бўлмади |

**S2 — Relay қарорини кутмайди.** Бу брифнинг ўз 1-бўлимидаги ЗРУ-547
қизил чизиғининг ҳозир, продакшнда бузилиб туриши.

---

## 4. Ҳозир нима мавжуд

### 4.1 Талаб → таклиф ядроси — `functions_demand`

Алоҳида codebase (`demand`), ~5 000 қатор код + ~3 500 қатор тест.

| Қисм | Файл | Нима қилади |
|---|---|---|
| Статус машинаси | `core/state_machine.js` | `draft → active → accepted → in_progress → completed`; `cancelled · expired · disputed`; `matching.state` статусдан ажратилган; noto'g'ri ўтишда хато ташлайди |
| Таклиф оқими | `api/offers.js` | `submitOffer`, `withdrawOffer`, `acceptOffer`, `cancelDemand`, `cancelAssignment` — ҳаммаси `runTransaction` ичида |
| Талаб яратиш | `api/create_demand.js` | idempotency калити, geo stamp, синхрон matching |
| Қайта очиш | `api/maintenance.js:116` + `index.js:144` | `reopenStaleAssignments` — pubsub, ҳар 10 дақиқа; `assignmentDeadline()` бўйича |
| Муддат | `index.js:135` | `expireDemandsSweeper` — ҳар 5 дақиқа |
| Matching | `matching/orchestrator.js`, `scoring.js` | номзод манбалари + баҳолаш |
| Имкониятлар | `sources/capabilities.js` | `provider_capabilities/{uid}_{module}` — `acceptsParcels`, `vehicle`, `regionIds`, `districtIds` аллақачон бор |
| Trust | `trust/compute.js`, `events.js` | фақат серверда |
| Push | `notify/policy.js`, `fcm.js`, `dispatch.js` | тўлқин ва лимит сиёсати |

**`demand` ҳужжатининг шакли** (`api/create_demand.js:140–185`) — LEG учун
нима аллақачон тайёр:

```
schemaVersion · ownerId · module · mode · categoryId
status · matching{state, matchedBucket, wave}
location · destination              ← LEG'нинг иккита учи
timeWindow{neededBy, expiresAt}
media{images}                       ← handover далили учун жой
contact · attributes                ← LEG'га хос майдонлар учун
payerSide
termsAcceptedAt                     ← рамка шартлар акцепти (1-қатлам)
assignment{providerId, offerId, acceptedAt}
tariffVersion                       ← аллақачон резервда
payment
createdAt · updatedAt
+ private/stats субҳужжати (мижозга кўринмайдиган ҳисоблагичлар)
```

### 4.2 Шахсни аниқлаш модели — CONFIRMED

Фойдаланувчи ID — `request.auth.uid` **эмас**, балки
`request.auth.token.phone_number` → рақамлар, `users/{998901234567}`.
Rules'да `isOwner()`, `phoneDocIdsMatch()`. **9 ва 12 хонали иккита шакл
бир вақтда мавжуд** (`functions/index.js:2397` шунинг учун иккаласини
пайпаслайди). Веб — Anonymous Auth, `token.phone_number` йўқ.

### 4.3 `provider_presence` — ТЎЛИҚ ҚУРИЛДИ (2026-10-06)

Аввал фақат қоида ва индекс бор эди; на ёзувчи, на ўқувчи. Ҳозир тўрт
томон ҳам ёзилган:

| Томон | Файл | Тест |
|---|---|---|
| Ўқувчи (matching манбаси) | `functions_demand/sources/presence_geo.js` | 16 |
| Модул адаптери | `functions_demand/adapters/courier.js` | 17 |
| Тозалаш (sweep, ҳар 2 дақиқа) | `functions_demand/api/maintenance.js` → `makePresenceSweeper` | 16 |
| Ёзувчи (илова) | `lib/repositories/provider_presence_repository.dart` + `lib/models/provider_presence.dart` | 28 (Dart) |
| Қоида | `firestore.rules` → `presenceClientFieldsOk` | 29 |
| Push истеъмолчиси | `functions/courier_push.js` | 23 |

**Шартнома (учта қатъий банд):**

1. `updatedAt == request.time` — вақтни СЕРВЕР қўяди. Акс ҳолда курьер
   келажак вақтни ёзиб доимо «янги» бўлиб туради: sweep уни ҳеч қачон
   offline қилмайди, matching фильтри тутмайди, GPS янгилиги бонусини
   доимо тўлиқ олади. Қоида билан қулфланган.
2. Таклифчи кимлиги — ФАҚАТ ҳужжат калитидан. Ҳужжат ичидаги
   `providerId` майдонини клиент ёзади, шунинг учун сервер унга
   ишонмайди (18-қоида); қоида эса майдонни калит билан мос бўлишга
   мажбурлайди.
3. Ҳар heartbeat `isOnline: true` ни ҳам ёзади. Sweep эскирган ёзувни
   offline қилади ва `updatedAt`га ТЕГМАЙДИ (эски
   `cleanupStaleDrivers` уни ўзгартириб юборади — шунинг учун у ердаги
   «эскилик» мезони ўз-ўзини йўқ қилади).

Эскириш чегараси ҳамма жойда битта: `maxLocationAgeSec = 120` с
(`functions_demand/core/config.js`). Sweep ҳар 2 дақиқада ишлайди —
чегарадан тез-тез, акс ҳолда ёлғон «онлайн» ойнаси чегарадан катта
бўларди.

### 4.4 Пул қатлами

`wallet_ledger`, `wallet_idempotency`, `functions/settlement_ledger.js`,
манфий float = қарз, `blockedReason: 'deferred_debt'`. Relay ўз ledger'ини
ўйлаб чиқармайди.

### 4.5 Нима умуман йўқ — CONFIRMED

- tracking number / order number схемаси — репода ҳеч қандай
- QR / barcode / scanner кутубхонаси — `pubspec.yaml` да йўқ
- OTP / PIN код механизми — йўқ
- `android.permission.CAMERA` — `AndroidManifest.xml` да йўқ
  (`image_picker` ва `permission_handler` бор, лекин камера рухсати эмас)

---

## 5. Нима моделга мос — LEG ↔ `demand`

| LEG учун керак | `demand` да | Ҳолат |
|---|---|---|
| Иккита уч (қаердан, қаерга) | `location`, `destination` | ✅ тайёр |
| Провайдерга таклиф ва акцепт | `demands/{id}/offers` + `submitOffer`/`acceptOffer` | ✅ тайёр, транзакцияли |
| Ким олди | `assignment{providerId, offerId, acceptedAt}` | ✅ тайёр |
| Рамка шартлар акцепти | `termsAcceptedAt` | ✅ тайёр |
| Тариф версияси | `tariffVersion` | ✅ майдон бор, тўлдирилмайди |
| Статус машинаси | `core/state_machine.js` | ✅ тайёр |
| Келмаса қайта тайинлаш | `cancelAssignment` + `reopenStaleAssignments` | ✅ тайёр, уланган |
| Низо | `disputed` + 48 соат SLA | ✅ тайёр |
| Далил расми | `media.images` | ✅ жой бор |
| Тўлов | `payment` | ✅ майдон бор |
| Idempotency | `IDEMPOTENCY` коллекцияси + idemKey | ✅ намуна бор |

**Хулоса:** Relay — `functions_demand` ядросининг `adapters/` даги модули.
Ҳозир у ерда фақат битта адаптер бор (`adapters/service.js`), яъни
кенгайтириш нуқтаси тайёр.

---

## 6. Нима етишмайди

### 6.1 Занжир тартиби

Ядрода `demand`'лар бир-биридан мустақил. LEG-2 эса LEG-1 нинг топшируви
тугамагунча **очилмаслиги** керак. Бу янги статус машинаси эмас — янги
боғланиш ва очиш шарти.

### 6.2 Атомар икки томонлама custody

Ядронинг `completed` си бир томонлама: ижрочи «бажардим» дейди. Handover
эса битта ҳодисада «A топширди» ва «B қабул қилди» ни ёзиши керак: вақт,
GPS, ҳолат белгиси, расм. Қисман бажарилган топшириш бўлмаслиги шарт.

### 6.3 ORDER / SHIPMENT устки қатлами

Ядрода мижознинг битта буюртмаси остида бир нечта жўнатма ва уларнинг
участкалари тушунчаси йўқ.

### 6.4 Нарх қатлами

`tariffVersion` майдони бор, лекин тариф двигатели, зона матрицаси ва
`module_tariffs` йўқ.

### 6.5 QR инфратузилмаси

Сканер кутубхонаси, камера рухсати, QR токен генерацияси — ҳаммаси янги.
**Эътибор:** камера рухсати қўшилиши Google Play Data Safety ва Permissions
декларациясини янгилашни талаб қилади (6-бўлим, L13). Илова Play'да
«AVA Zona» (`uz.ava.gurlan`) номи билан нашр қилинган — бу назарий эмас.

---

## 7. Таклиф этилаётган архитектура — PROPOSED

### 7.1 Коллекциялар

Мавжуд қарорлар (`docs/talab_taklif_yadrosi_uz.md` 2.3-жадвали) бузилмайди.
Янги ном фақат эквиваленти йўқ бўлганда.

| Коллекция | Ҳолат | Изоҳ |
|---|---|---|
| `demands` + `demands/{id}/offers` | мавжуд | LEG шу ерда яшайди |
| `provider_capabilities`, `provider_presence`, `provider_stats` | мавжуд | провайдер профили |
| `courier_documents` | номи қарор қилинган | onboarding ҳужжатлари |
| `complaints` | мавжуд | низо/даъво |
| `wallet_ledger`, `demand_penalties` | мавжуд | пул |
| `module_tariffs` | номи қарор қилинган, йўқ | тариф, версияли |
| **`logistics_orders`** | янги | ORDER — мижознинг буюртмаси |
| **`shipments`** | янги | битта жисмоний қути |
| **`custody_events`** | янги | ўзгармас, фақат қўшилади |
| **`route_plans`** | янги | версияланган режа (D-9) |

Номлаш: snake_case. Ҳужжат калити — 12 хонали канон шакл
(`998XXXXXXXXX`) бўлган жойларда сервер нормаллаштиргандан кейин ёзилади.

### 7.2 Майдонлар

```
logistics_orders/{orderId}
  ownerId                     12 хонали канон
  status                      ҲИСОБЛАНАДИГАН (derived), ўз машинаси йўқ
  shipmentIds[]
  consolidation{ count, discountApplied, tariffVersion }
  customerPriceTotal          integer, сўм (CLAUDE.md 8-банд)
  createdAt · updatedAt

shipments/{shipmentId}
  orderId
  trackingNumber              AVA-YY-NNNN-NNNNNN, сервер яратади (D-5)
  qrSecret                    сервер яратади, клиент кўрмайди (D-6)
  actualWeight · length · width · height
  volumetricWeight · chargeableWeight     (CLAUDE.md 12-банд)
  priceSnapshot{ zone, tariffVersion, chargeableWeight,
                 customerPrice, extras[], calculatedAt }   (D-8)
  declaredValue · declaredValueFeePaid
  currentCustodian{ kind, id, since }      (D-7)
  currentLegId
  status                      SHIPMENT машинаси
  createdAt · updatedAt

demands/{legId}                ← LEG, мавжуд ядро ҳужжати
  module: 'logistics'
  attributes{ shipmentId, legIndex, dependsOnLegId,
              handoverFromKind, handoverToKind }
  location · destination · assignment · tariffVersion · payment

custody_events/{eventId}       ← ЎЗГАРМАС (CLAUDE.md 15, 16-бандлар)
  shipmentId · legId
  from{ kind, id } · to{ kind, id }
  timestamp · location{ lat, lng, accuracy }
  proof{ qrVerified, photoUrls[], conditionFlags[] }
  createdBy · idempotencyKey

route_plans/{shipmentId}/versions/{n}      (D-9)
  version · legs[] · reason · createdAt · supersededAt
```

### 7.3 Босқичлар ажратилиши (D-10)

```
Route planning  →  route_plans/{shipmentId}/versions/{n}
Leg creation    →  demands/{legId}, status: draft
Provider assign →  demands/{legId}, status: active → offers → accepted
Execution       →  custody_events + status: in_progress → completed
```

**Занжир тартиби — AVA_DECIDED (2026-10-07).** «Олдингиси `completed`
бўлгандагина» деган дастлабки ёзув deadlock эди: LEG(n) фақат LEG(n+1)
ижрочиси посилкани олганда тугайди. Қарор — **matching олдиндан, custody
эмас**:

```
LEG-1 in_progress (ижрочи посилкани ОЛДИ, scanHandover)
  → LEG-2 active: matching + push          (api/logistics.js activateLeg)
LEG-2 accepted → иккинчи ижрочи тайёр туради (олиш нуқтаси = LEG-1 ижрочиси)
LEG-2 ижрочиси LEG-1 ижрочисидан код/QR билан scanHandover
  → БИТТА транзакция: LEG-1 completed + LEG-2 in_progress + custody_event
```

Custody handover сканидан олдин очилмайди. Конфиг калити
`module_config.logistics.openNextLegOn = 'in_progress'` — «кейинги LEG
matching'и қачон очилади» маъносида. Иккита ҳимоя (2026-10-07):
`reopenStaleAssignments` логистика LEG'ига тегмайди (кутаётган ижрочи 120
дақиқадан кейин чиқариб ташланмайди); LEG ижрочисиз муддати тугаса
`expireDemandsSweeper` жўнатмага `legProblem` ёзади ва admin
`adminReactivateLeg` билан қайта очади (matching қайтадан, payout ва
маршрут ўзгармайди, audit). Очиқ: LEG-2 ижрочиси қанча кута олади —
алоҳида қарор.

### 7.4 Handover оқими — ✅ амалга оширилган (2026-10-07; сканер L13 кейин, код қўлда)

1. Жўнатувчи иловада `shipmentQR` ни кўрсатади (сервер яратган, D-6).
2. Провайдер сканерлайди → сервер токенни, `shipmentId` ни ва LEG'нинг
   `active`/`accepted` эканини текширади.
3. Провайдер ҳолат белгисини танлайди: бут · қадоқ шикастланган · очилиш
   аломати · намланган · бошқа. Расм мажбурий.
4. Битта callable, битта транзакция: `custody_events` га ёзув +
   `shipments.currentCustodian` янгиланиши + LEG статуси ўзгариши.
   Idempotency калити билан — иккинчи чақирув иккинчи ҳодиса яратмайди
   (CLAUDE.md 21-банд).
5. Эски custody ёзуви **ўчирилмайди** (CLAUDE.md 15-банд).

Офлайн ҳолат: сканер натижаси навбатга қўйилади, сервер idempotency калити
бўйича такрорни рад этади. — **UNKNOWN**: офлайн навбатнинг муддати ва
конфликт қоидаси ҳал қилинмаган.

### 7.5 Нарх

Икки қатлам, аралаштирилмайди (CLAUDE.md 14-банд):

```
ТАШҚИ (мижоз кўради)
  ZONE_0 … ZONE_5, origin↔destination matrix орқали   (D-2)
  зона маъноси кодга ёзилмайди — matrix authoritative

ИЧКИ (мижоз кўрмайди)
  вазн + ҳажмий вазн + first-mile + agent + hub/sort
  + line-haul + last-mile + risk/payment/IT/admin
```

Ҳар бир ички компонент учун **атрибуция мажбурий**: қайси LEG, қайси
провайдер, кимнинг жойида. Акс ҳолда `hub/sort` ва `agent` жимгина AVA
HUB'ини қайта тиклайди — қизил чизиқ №3.

Ҳажмий вазн: `chargeableWeight = max(actualWeight, volumetricWeight)`,
`volumetricWeight = L × W × H / divisor`. BTS domestic divisor = 6000
(**BTS_CONFIRMED**, «Умумий шартлар» 1-Илова, 20-бет). AVA учун divisor
`module_tariffs.volumetricDivisor` конфиг қиймати — **UNKNOWN**, эга
тасдиғини кутади.

**Ўлчам ва вазн — AVA_DECIDED (2026-10-07):** жўнатувчи (сотувчи) вазн,
L/W/H ни киритади; тизим ҳажмий вазнни ҳисоблайди,
`chargeableWeight = max(actual, volumetric)` бўйича нархлайди
(`tariff.js quoteParcel`). Курьер ўлчам киритмайди, ҳажмий вазн
ҳисобламайди, нарх белгиламайди. Учта текширув аралашмайди:
`limits.maxWeightG` — **ҳақиқий** вазн лимити; `maxDimCm`/`maxSumDimCm` —
физик ўлчам; `chargeable` — фақат нарх учун. 21 кг — тариф чегараси
(`weightBrackets: [21000]`), максимал вазн эмас (максимал вазн — алоҳида
қарор, ҳали белгиланмаган). Custody'да яширин нарх ўзгармайди (D-8);
«мос / мос эмас» назорати ва қайта нархлаш — алоҳида кейинги қарор.

**Тариф модели — AVA_DECIDED (2026-10-07):** N=1 — 0–21 кг базавий нарх,
21 кг дан кейин ҳар **бошланган** кг `extraPerKg`. ZONE_0 130 000 / +2 500;
ZONE_1 250 000 / +6 000; ZONE_4 310 000 / +8 500. ZONE_2/3/5 — нарх
берилмаган, матрицада йўналиш ҳам йўқ. Менинг аввалги 5 поғонали
`[1,3,5,10,20] кг` жадвалим эга қарори эмас эди — бекор қилинган.

### 7.6 Тўлов ва эскроу

**Эга қарорлари (2026-10-07):** (1) AVA тушуми — **фақат комиссия**
(`platformShare` → `earnings:ava_logistics_fee`; `providerPool` →
`supplier_payable:{курьер}` — AVA'нинг курьерларга мажбурияти; ledger шундай
қурилган, `relay_escrow.js`). (2) Чекни тўловчига (жўнатувчига) **AVA**
беради; курьерларга тўлов ва ҳужжатни ҳам AVA ички ҳисоб-китоб орқали
беради — ҳозир курьерга тўлов: EARNED → `supplier_payable` → finance
`creditSupplier` (қўлда) → ҳамён; **фискал чек механизми кодда йўқ**
(ОФД/провайдер — UNKNOWN). (3) Бир нечта провайдерга AVA'нинг тўғридан-
тўғри тўлови — тўғри деб қабул қилинди, ҳуқуқий текширув PUBLIC'гача
(L6c). Declared value: ҳар курьер **ўз LEG'ида** жавобгар (custody бўйича);
компенсация механизми — кейинги алоҳида қарор (L15).

Ҳуқуқий асос — ЎРҚ-1173, 12.12.2026 дан кучга кирадиган таҳрир
(`lex.uz/docs/-6213382?ONDATE=12.12.2026+01`, 2026-10-05 да текширилган):

| Норма | Матн | Ҳолат |
|---|---|---|
| 24-модда | агрегатор оператори «oʻz axborot tizimlariga yoki bank hisobvaraqlariga "eskrou" xizmatini joriy etishi mumkin» | CONFIRMED |
| 24-модда | «deponentlangan pul mablagʻlari "eskrou" xizmatini koʻrsatuvchining mulki hisoblanmaydi» | CONFIRMED |
| 13¹-модда | агрегатор харидор учун якуний қийматни мустақил белгилаши | CONFIRMED |
| 23-модда | электрон тижорат ҳисоб-китоблари алоҳида банк ҳисоби орқали | CONFIRMED |
| 23-модда 5–7 | ўзини ўзи банд қилганлар алоҳида ҳисоб ва/ёки **электрон ҳамён** орқали; учинчи шахс учун тўлов қабул қилиш ҳуқуқи | CONFIRMED |
| Агрегатор провайдерлар билан **қандай ҳисоблашади** | — | **қонунда ЙЎҚ** |
| Тўлов ташкилоти лицензияси | — | 23–24-моддаларда талаб ҳам, рухсат ҳам ёзилмаган |

Эътибор: 23-модда 4-хатбошидаги «учинчи шахс учун тўлов олиш» ҳуқуқи
**тескари йўналишда** — етказиб берувчи сотувчи учун олади. AVA'нинг
«мижоздан ол → провайдерларга тарқат» оқими бу норма эмас; уни 24-модда
(эскроу) ёпади, тарқатиш эса қонунда очиқ қолган.

**Модель — AVA_DECIDED (D-11, 2026-10-05):**

```
Жўнатувчи → AVA эскроу → етказиш тасдиқланди → провайдерлар + AVA комиссияси
```

Ҳисоб режаси. Мавжуд `functions/settlement_ledger.js` double-entry
двигатели ишлатилади (`journal_entries` ўзгармас, `ledger_accounts`
баланс, Σdebit == Σcredit, суммалар integer сўм). Мавжуд ҳисоб турлари:
`admin_cash · admin_clearing · courier_cash · driver_float ·
passenger_credit · supplier_payable · earnings`. **Янгидан керак бўладигани
биттаси — `escrow`.**

```
1. Мижоз тўлади
   Dr escrow_bank                70 000      ажратилган банк ҳисоби (23-модда)
   Cr escrow:{shipmentId}        70 000      AVA'нинг мулки эмас (24-модда)

2. LEG бажарилди — EARNED (пул ҳаракатланмайди)
   Dr platform_accrual            7 000
   Cr earnings:{providerId}       7 000

3. DELIVERED — эскроу ечилади
   Dr escrow:{shipmentId}        70 000
   Cr platform_accrual           48 000
   Cr platform_revenue           22 000

4. PAYOUT — ҳақиқий пул чиқади
   Dr supplier_payable:{uid}
   Cr escrow_bank
```

**Учта тушунча аралаштирилмайди:** `ESCROW` (мижознинг депонентланган
пули) · `LEDGER` (ким қанча ишлаб топгани) · `PAYOUT` (пулнинг ҳақиқатан
чиқиши). Ва `EARNED ≠ PAID`.

**Муҳим қоида:** EARNED ёзуви `escrow:{shipmentId}` ни **камайтирмайди**.
Эскроу `DELIVERED` гача тўлиқ туради. Акс ҳолда қути йўқолганда мижозга
қайтариш учун пул қолмайди. Провайдернинг ҳақи AVA'нинг provision
ҳисобига ёзилади — шунда бажарилган меҳнат йўқолмайди, мижознинг пули ҳам
тўлиқ ҳимояланган бўлади, зарарни эса AVA кўтариб, айбдор участкадан
`demand_penalties` орқали ундиради.

`paymentStatus` машинаси:

```
PENDING → ESCROW_FUNDED → RELEASE_APPROVED → SETTLED
             ├─ ESCROW_FROZEN      (DISPUTED бўлганда, автомат payout тўхтайди)
             └─ REFUND_PENDING → REFUNDED
```

**Биринчи версияда фақат `payerSide: 'sender'`.** Схемада
`['sender','recipient']` иккаласи ҳам бор (CONFIRMED,
`demand_input.schema.json:123`), лекин олувчи тўлайдиган вариант занжирга
нақд пул киритади ва уни биринчи версияда ёқмаймиз.

**Payout стратегияси — интерфейс сифатида қолдирилади:**

```
payoutStrategy: 'direct'      ҳар бир провайдерга алоҳида
                'via_primary' битта асосий ижрочига, қолганлари субпудратчи
```

Ledger иккала ҳолатда ҳам бир хил ишлайди — фақат охирги банк кўрсатмаси
фарқ қилади. `PROPOSED`: `direct` асосий йўл, чунки у AVA'нинг агрегатор
позициясига ва «ҳар бир LEG мустақил мажбурият» қоидасига мос.
`via_primary` мажбуриятни битта жойга йиғади ва relay моделига зид —
фақат ҳуқуқий зарурат бўлса ишлатилади.

**Бугунги ҳолат — CONFIRMED:** репода карта тўлов шлюзи (Payme/Click/
merchant/acquiring) **йўқ**. Мавжуд усуллар `cash · card · product ·
wallet` (`functions/index.js:4302`); ҳамён Telegram бот орқали, чек расми
ва админ қўлда тасдиғи билан тўлдирилади (`functions/telegram_wallet_bot.js`).
Эскроу модели учун ҳақиқий acquiring интеграцияси керак — бу алоҳида иш.

`fiscalIssuer` майдони қолдирилади, мантиғи ёзилмайди (9-бўлим, L6).

### 7.7 Security rules — PROPOSED

- `logistics_orders`, `shipments`, `custody_events`, `route_plans` —
  **клиент ёзмайди**, фақат CF. `delivery_routes` ва `couriers` намунаси
  такрорланмайди.
- Ўқиш: `isOwner(ownerId) || isAdmin()`; LEG провайдери фақат ўз
  LEG'ига тегишли shipment'нинг чекланган проекциясини кўради.
- Қабул қилувчининг телефони — профилнинг очиқ майдони эмас; фақат
  охирги участка провайдерига ва фақат фаол етказиш пайтида
  (CLAUDE.md 40-банд).
- `demand_matches` намунаси бўйича: проекция орқали махфийлик.

### 7.8 Cloud Functions — PROPOSED

Ҳаммаси `functions_demand` codebase'ида (`firebase deploy --only
functions:demand`), 690 КБ'лик `functions/index.js` монолитига қўшилмайди.

| Номи | Тури | Вазифаси |
|---|---|---|
| `createLogisticsOrder` | callable | ORDER + SHIPMENT'лар + QR + PriceSnapshot |
| `planShipmentRoute` | callable/internal | `route_plans` янги версияси |
| `openNextLeg` | trigger | олдинги LEG `completed` → кейингиси `active` |
| `scanHandover` | callable | 7.4 даги атомар транзакция |
| `confirmDelivery` | callable | охирги участка, OTP |
| `recalculateOrderStatus` | trigger | derived ORDER статуси |

Мавжудлари ўзгартирилмайди: `submitOffer`, `acceptOffer`,
`cancelAssignment`, `reopenStaleAssignments` LEG учун шундайлигича ишлайди.

### 7.9 Flutter

`lib/features/demand_offer/` конвенциясига мос, `features/logistics/`.
Янги dependency: QR сканер. Бу камера рухсатини, у эса Play Data Safety
янгиланишини келтиради (6.5). UI матнлари `uz_Cyrl` + `uz_Latn` + `ru` —
учаласи биргаликда, `test/core/locale_sync_test.dart` қулфлайди.

Мижозга `LEG`, `ZONE_4`, `settlement` каби ички тушунчалар кўрсатилмайди
(CLAUDE.md 45-банд): битта буюртма, битта нарх, битта кузатув тасмаси.

---

## 8. Нимани ўзгартириш керак — устуворлик билан

**1-гуруҳ — Relay'дан мустақил, кутмайди**

1. ~~S2 — `couriers` ўқиш/ёзиш қоидалари.~~ **Бажарилди 2026-10-06** (16/16).
   ID миграцияси кутилмади: `isOwner()` → `phoneDocIdsMatch()` 9 ва 12
   хонали иккала шаклни ҳам қабул қилади, бу тест билан қулфланган.

   **Продакшнда текширилди (2026-10-06, фақат ўқиш, эга рухсати билан):**

   | Коллекция | Ҳолат | Деплой риски |
   |---|---|---|
   | `payout_requests` | **0 ҳужжат** | йўқ — оқадиган нарса ҳам, синадигани ҳам йўқ |
   | `couriers` | 3 ҳужжат, ҳаммаси 12 хонали каноник, ҳар бирининг `users` ҳужжати бор ва `id == phone`, **0 таси онлайн** | йўқ — учаласи ҳам `isOwner()` дан ўтади |
   | `delivery_routes` | 73 ҳужжат, **ҳаммаси `completed`**, `courierId` ҳаммасида 12 хонали | йўқ — ready/active рейс умуман йўқ |

   200 фойдаланувчидан **2 таси** телефон алмаштириш номувофиқлигида
   (`doc id != phone`), ва **иккаласи ҳам курьер эмас**. Яъни қуйидаги
   хато амалда ҳеч бир курьерга тегмайди — лекин латент хато сифатида
   қолади ва алоҳида тузатилади.

   **⚠️ Хатонинг ўзи — кодда тасдиқланган, тахмин эмас.**
   `changeDevicePhone` (`functions/index.js:6284`) фақат Firestore'га
   тегади: `device_bindings`, `device_aliases` ва `users` ҳужжатининг
   `phone` майдони. **Firebase Auth'га тегмайди** ва ҳужжат ID'сини
   кўчирмайди. Иловa томони (`profile_controller.dart:747`) эса
   `prefs['user_phone']` ни янги рақамга ёзиб, сессияни қайта тикламайди.
   Натижада:

   ```
   token.phone_number    → ЭСКИ      ← isOwner() шунга қарайди
   prefs['user_phone']   → ЯНГИ      ← илова шунга ёзади
   users/{ЭСКИ_id}.phone → ЯНГИ
   ```

   Яъни телефонини алмаштирган курьер `couriers/{ЯНГИ}` га ёзади ва янги
   қоида уни рад этади. Бу қоида туғдирган нуқсон эмас — аллақачон мавжуд
   латент хато, фақат энди кўринадиган бўлди. Илдизини тузатиш алоҳида
   вазифа сифатида ажратилди.

   Қоидани `phone` майдонига қараб юмшатиш **ярамайди**: `phone` клиент
   ёза оладиган майдонлар рўйхатида, яъни ҳужум қилувчи уни ўзиникига
   ўзгартириб бировнинг ҳужжатини эгаллаб олади.

   **Канарейка:** `cleanupStaleDrivers` 2 дақиқа ёзув келмаса курьерни
   offline қилади — ёзув синса, онлайн курьерлар 2 дақиқада йўқолади.
2. ~~S1 — `delivery_routes` `update` шарти.~~ **Бажарилди 2026-10-06** (18/18).
   Қўшимча топилма: `getNextReady()` (`delivery_routes_repository.dart:28`)
   ни ҳеч ким чақирмайди — ўлик код. Эгасиз рейс энди курьерга
   кўринмайди; агар келажакда «эгасиз рейсни эгаллаш» оқими керак бўлса,
   қоидага алоҳида шарт қўшилиши керак.
3. ~~S3 — `payout_requests` ўқиш.~~ **Бажарилди 2026-10-06**, тести билан
   (12/12). Деплой кутилмоқда — қоидалар ўз деплойи билан чиқади.

Эслатма: rules тест харниси аллақачон мавжуд экан
(`@firebase/rules-unit-testing` + `functions/test/*_rules.test.js`) — уни
нолдан қуриш керак эмас. Янги қоида ёзилганда шу намунага эргашилади.

**1-гуруҳ (давоми) — қолган очиқ ўқишлар**

Деплойдан кейин жонли ruleset текширилганда (2026-10-06) файлда яна
**39 та `allow read: if true`** қолгани аниқланди. Кўпчилиги ўринли
(каталог, гео маълумотнома, оммавий контент: `bread_products`,
`geo_regions`, `taxonomy`, `tv_clips`, `config` ва ҳ.к.), лекин
қуйидагилар биз ҳозир тузатган синфга тегишли — шахсий маълумот ёки
операцион ҳолат. Продакшндаги ҳажм (2026-10-06, фақат ўқиш):

| Коллекция | Ҳужжат | Нима очиқ |
|---|---|---|
| `notifications` | **953** | фойдаланувчи хабарлари, `targetPhone` |
| `device_bindings` + `_legacy` | **557** | қурилма изи ↔ телефон боғланиши |
| `drivers` | 16 | телефон + жонли GPS — **`couriers`нинг айнан эгизаги** |
| `queue` | 6 | ҳайдовчи навбати |
| `intercity_drivers` | 6 | ҳайдовчи профили |
| `wholesale_sellers` | 1 | |
| `local_taxi_drivers`, `local_taxi_requests` | 0 | ҳозир бўш |
| `users/{id}/driverProfiles`, `users/{id}/marshrut_state`, `support_chats/{id}/messages`, `intercity_booking_locks`, `marshrut_dispatch_events` | — | ўлчанмади |

Алоҳида эътибор: `birthdate_change_requests` да `create: if true` ва
`read, update: if true` — яъни ёзиш ҳам очиқ. Кодда изоҳ бор: «Admin web
hozir PIN session bilan ishlaydi; Phone Auth admin bo'lgach `isAdmin()`ga
qaytaramiz». Админ панел эса аллақачон Phone Auth'да
(`admin_auth_service.dart:114–122`) — демак бу изоҳ эскирган.

**Иккинчи ўтиш — бажарилди 2026-10-06** (деплой қилинмаган):

| Коллекция | Нима ўзгарди | Тест |
|---|---|---|
| `notifications` | `read` эгасига боғланди; **`create` да `isAuth()` қўшилди** — аввал ташқаридан ҳар ким исталган рақамга push юбора оларди (`onNotificationCreate` уни ҳақиқий push қилади). Клиентнинг бошқа фойдаланувчига хабар ёзиши сақланди | 16/16 |
| `birthdate_change_requests` | `create/read/update` — учаласи ҳам `if true` эди. Энди: ўзи учун яратади, эгаси ёки админ ўқийди, тасдиқлаш фақат админда | 14/14 |
| `device_bindings` | `get` очиқ қолди (илова ўз hash'ини auth'дан олдин ўқийди), **`list` админга** — 557 боғланиш энумерацияси ёпилди | 11/11 |
| `device_bindings_legacy` | тўлиқ админга — клиент уни умуман ўқимайди | ↑ |
| `drivers` | `get: isAuth()`, **`list: isAdmin()`** — йўловчи ўз ҳайдовчисини ID бўйича ўқийди, рўйхатни фақат админ | 8/8 |

**`drivers.create` да ҳамон auth йўқ** — тегилмади. Унинг `update` қоидаси
учта махсус ёрдамчига таянади (`driverWorkPatchOnly`,
`marshrutDriverRegisterPatch`, `driverApprovalPatchOnly`); ҳайдовчи
рўйхатдан ўтиш оқимини бузмаслик учун алоҳида ўтишда ўрганилади.

**Учинчи ўтиш — бажарилди 2026-10-06** (деплой қилинмаган):

| Коллекция | Нима ўзгарди | Тест |
|---|---|---|
| `support_chats/{id}/messages` | `read: if true` ва **`update: if true`** эди — 18 шахсий суҳбат очиқ, ва ҳар ким исталган хабарни қайта ёза оларди. Эгалик + админга боғланди | 18/18 |
| `intercity_booking_locks` | `read` ва **`create, update: if true`** эди — ҳар ким ўриндиқ қулфи ярата ёки бузa оларди. Клиент бу коллекцияга умуман тегмайди, шунинг учун ўқиш админга, ёзиш тўлиқ ёпилди | 8/8 |

**Илдиз сабаб топилди — `support_chats`.** Ота қоидада
`request.auth.uid == chatId` ёзилган эди, лекин `chatId` — телефон
рақами, `auth.uid` эса Phone Auth'да Firebase берган тасодифий сатр. Яъни
шарт оддий фойдаланувчи учун ҳеч қачон бажарилмасди: у ўз чатининг ота
ҳужжатини ўқий ҳам, ёза ҳам олмасди. Тест буни кўрсатди —
`sendMessage` → `PERMISSION_DENIED`. Субколлекция эса шу сабабли
бутунлай очиб қўйилган эди. Тузатиш иккала муаммони ҳам ҳал қилди:
тешиклар ёпилди **ва бузуқ хусусият тикланди**. Эски
`auth.uid == chatId` йўли орқага мослик учун сақланди.

**Тўртинчи ўтиш — бажарилди 2026-10-06** (деплой қилинмаган). Ҳар бири
алоҳида таҳлил қилинди, чунки оқимлари ҳар хил:

| Коллекция | Оқим | Ечим |
|---|---|---|
| `queue` (6) | **йўловчи рўйхат сўрайди** (`marshrut_search_controller.dart:366`) ва бошқа ҳайдовчининг ҳужжатини ўқийди | `isAuth()` — эгаликка боғлаб бўлмайди |
| `marshrut_dispatch_events` (194) | клиент фақат яратади; ягона ўқиш йўли `watchRecentMarshrutDispatchEvents()` — **ҳеч ким чақирмайди, ўлик код** | `isAdmin()` |
| `users/{id}/driverProfiles` | фақат эгаси ўқийди (`push_navigation.dart:186, :338` — доим ўз uid'и) | `isOwner(userId) \|\| isAdmin()` |
| `users/{id}/marshrut_state` | **ҳайдовчи йўловчининг ҳолатини синхронлайди** (`rides_repository.dart:1274`) — ўқиш кесишган | `isAuth()` |

Тест: `functions/test/marshrut_misc_rules.test.js` — 7/14 → **14/14**.

**⚠️ Қоида ҳал қилмайдиган масала:** `queue` ҳужжатида `driverPhone` бор
ва у ҳар бир йўловчига кўринади. Йўловчи рўйхатни кўриши — маҳсулот
талаби, шунинг учун уни ёпиб бўлмайди. Бу **маълумот модели** масаласи:
телефон алоҳида жойга чиқарилиб, фақат фаол сафарда очилиши керак.
Relay'даги «охирги участка курьерига фақат фаол етказиш пайтида» қоидаси
билан бир хил намуна.

**Қолган иккитаси — атайин оммавий деб баҳоланди, тегилмади:**
`intercity_drivers` (6) ва `wholesale_sellers` (1) — эълон тахтаси ва
сотувчи каталоги, йўловчи/харидор уларни кўриши керак. Ёзув томони
иккаласида ҳам аллақачон эгаликка боғланган.

Қолганлари (каталог, гео, `tv_*`, `config`, `taxonomy`) — оммавий
бўлиши ўринли.

**2-гуруҳ — `couriers` → provider моделига кўчириш (D-1)**

Тартиб: сервер кўзгуси ва ID каноникаллаштириш → янги илова версияси →
қоидани ёпиш → `resolveAuthorizedCourierUid` даги 9 хонали тармоқни олиб
ташлаш. `courier_cash` тўсиғи ёпилган (`0d53fdb`).

**3-гуруҳ — Relay**

Нарх қатлами → shipment/ORDER қатлами → custody ҳодисаси → занжир →
Flutter.

---

## 9. Ҳуқуқий текширувсиз final деб ҳисобланмайдиган — БЛОКЛАНГАН

L1–L5, L7–L12 брифдагидек қолади. **L6 (тўлов) қайта ёзилди** — асосий
механизм энди очиқ эмас, фақат учта аниқ савол қолди:

| # | Масала | Таъсири |
|---|---|---|
| **L6a** | ~~70 000 сўмдан AVA'нинг тушуми 22 000 ми ёки бутун 70 000 ми~~ **Эга қарори (2026-10-07): фақат комиссия.** Ledger шунга мос (§7.6). Солиқ расмийлаштириш — ҳуқуқшунос текшируви PUBLIC'гача | AVA агент/платформа, хизмат сотувчиси эмас |
| **L6b** | **Эга қарори (2026-10-07): чекни тўловчига AVA беради; курьерларга тўлов ва ҳужжатни ҳам AVA.** Кодда фискал чек йўқ (ОФД/провайдер UNKNOWN) — PUBLIC'гача амалга ошириш керак | `fiscalIssuer = AVA`; чек интеграцияси — алоҳида иш |
| **L6c** | **Эга қарори: тўғри (текшириш керак).** Код ҳар курьерга алоҳида `supplier_payable` юритади | `payoutStrategy = direct`; ҳуқуқий текширув PUBLIC'гача |
| L13 | Google Play Data Safety: камера рухсати, паспорт нусхаси, фон жойлашуви | Onboarding, QR, кузатув. Ҳуқуқшунос эмас, эга ҳал қилади |
| L14 | BTS'нинг бренд остидаги франшиза қатлами AVA'га мос келадими | Провайдер onboarding'и, номлаш, оферта тарафлари |
| L15 | Эълон қилинган қиймат режими. BTS: эълон қилинмаса ташиш ҳақининг **2 баравари**; эълон қилинса **қиймат + ташиш ҳақи**, опсия нархи қийматнинг **1%** и (BTS_CONFIRMED) | «2 баравар» қоидаси LEG'ларга табиий бўлинади; эълон қилинган режим бўлинмайди — қайси LEG кўтариши ҳал қилинмаган |

---

## 9-bis. `couriers`ни чиқариш — ЎЛЧОВ БЎЙИЧА БЛОКЛАНГАН (2026-10-06)

D-1 `couriers`ни provider моделига кўчиришни талаб қилади. **Presence
қисми бажарилди** (4.3). Лекин коллекцияни БУТУНЛАЙ чиқариш ҳозир
продакшнни бузади. Сабаб — ўлчов, тахмин эмас (фақат ўқиш, REST):

| `couriers/{id}` | `users.role` | `users.fcmToken` |
|---|---|---|
| `998912778777` | **superadmin** | бор |
| `998932774779` | **user** | бор |
| `998941110504` | **user** | бор |

`users` ичида `role == 'courier'` — **жами 1 ҳужжат**, ва у шу учтанинг
ҳеч бири эмас. `provider_capabilities` — **0 ҳужжат**.

**Нега бу тўсиқ.** `functions/index.js` → `resolveAuthorizedCourierUid`
курьерни ИККИ манбадан тасдиқлайди: аввал `couriers/{uid}` мавжудлиги,
кейин `users/{uid}.role === 'courier'`. Ҳозирги маълумотда ИККИНЧИ
манба учтасининг ҲЕЧ БИРИНИ тасдиқламайди. Яъни `couriers` олиб
ташланса, `courierMarkPicked` · `courierMarkArrived` ·
`courierSubmitPayment` ҳаммаси `permission-denied` билан тўхтайди —
етказиб бериш оқими бутунлай ишламайди.

**Иккинчи тўсиқ.** `couriers` УЧ вазифани бажаряпти:

| Вазифа | Янги модели | Ҳолат |
|---|---|---|
| Жонли ҳолат (онлайн, GPS) | `provider_presence` | ✅ қурилди |
| Push токени | `users.fcmToken` | ✅ кўчирилди (`courier_push.js`) |
| **Реестр** — ким умуман курьер (админ одам иловага кирмасдан ҳам яратади) | `provider_capabilities` + роль | ❌ йўқ |

Presence реестр ЎРНИНИ БОСМАЙДИ: presence «ҳозир қаердасан» деган
маълумот, реестр эса «сен курьерсан» деган ҲУҚУҚ.

### 9-bis.1 А/Б саволидан олдин ҳал қилиниши керак — ҲУҚУҚ ЎЗИГА БЕРИЛАДИ

**2026-10-06 да аниқланди.** Аввалги А/Б таклифи ЧАЛА эди: у реестрнинг
қайси коллекцияда туришини сўрарди, аслида муаммо чуқурроқ —
**иккала номзод реестр ҳам КЛИЕНТ ёзадиган жой**, яъни ҳуқуқни
фойдаланувчи ўзига ўзи бериши мумкин (18 ва 19-қоида).

`functions/index.js:2399` → `resolveAuthorizedCourierUid` курьерни икки
манбадан тасдиқлайди, **иккаласи ҳам клиентга ёзиладиган**:

| # | Манба | Клиент ёза оладими | Қоида |
|---|---|---|---|
| 1 | `couriers/{uid}` мавжудлиги | **ҲА** — `allow create: if (isAdmin() \|\| isOwner(id)) && hasAll(['isOnline','name','phone'])` | `firestore.rules:2630` |
| 2 | `users/{uid}.role == 'courier'` | **ҲА** — `usersCourierRolePromotion`: роли `user` ёки бўш бўлган ҳар ким ўзига `role: 'courier'` ёзади | `firestore.rules:149, 693` |

Профиль экранидаги PIN (`profile_screen.dart:943`) — фақат интерфейс
қулфи, қоида уни талаб қилмайди. Яъни тўғридан-тўғри Firestore ёзуви
PIN'сиз ўтади.

**Шу ҳуқуқ нима очади.** 14 та callable: `courierCreateRoute` ·
`courierRecoverOrphanRoute` · `courierGetCustomerWalletBalance` ·
`courierMarkCollectionArrived` · `courierFinalizeCollection` + 8 та
гилам/агро вазифасини олиш функцияси. Улардан **энг оғири**
`courierGetCustomerWalletBalance` (`index.js:4201`): текширувдан кейин
у **исталган телефон рақами** бўйича `users.bonusBalance` ни
қайтаради — яъни бошқа одамларнинг ҳисоб қолдиғи.

**Бу йўл ЖОНЛИ ва ишлатилган.** `role == 'courier'` бўлган ягона
фойдаланувчи — `998941111184` (Azamat), ва унинг `couriers` ҳужжати
**йўқ**; `updatedAt` 2026-10-06 07:14, яъни ҳисоб бугун фаол. Жами 200
фойдаланувчи, демак ~197 таси ўзини курьер қилиб олиши мумкин.

**S2 ни ҳам тан оламан:** S2 да `couriers` `create` қоидаси
«аутентификациясиз ҳар ким» дан «ўзи ёки админ» га торайтирилди — бу
яхшиланиш, лекин етарли эмас эди, чунки ўша пайтда коллекция
**ҳуқуқ реестри** сифатида ҳам ишлатилаётгани эътиборга олинмаган эди.

### 9-bis.2 Тўғри йўл — реестр СЕРВЕР қўлида бўлсин

Қайси коллекция эмас, КИМ ЁЗАДИ — асосий савол. Босқичлар:

1. **`couriers` ёзувини ажратиш.** Реестр майдонлари (`name`, `phone`,
   ҳужжатнинг ўзини яратиш) → фақат `isAdmin()`. Курьернинг ўзи
   МАВЖУД ҳужжатда фақат жонли майдонларни янгилайди (`isOnline`,
   `lat`, `lng`, `fcmToken`, `updatedAt`) — `create` эмас, `update`.
   Бу 1-йўлни ёпади.
2. **Azamat'га админ ҳужжати яратиш** (ёки у кимлигини аниқлаш) —
   2-йўлни ёпишдан ОЛДИН, акс ҳолда у ҳуқуқини йўқотади.
3. **`users.role == 'courier'` заҳирасини олиб ташлаш**
   (`index.js:2408-2413`). Шундан кейин ҳуқуқ фақат админ ёзган
   ҳужжатдан келади. Учта мавжуд курьерда ҳужжат бор — улар
   таъсирланмайди.
4. **Шундан кейингина** реестрни `provider_capabilities`га кўчириш
   маъно касб этади — лекин у ҳам ҳозир клиент ёзадиган коллекция
   (`firestore.rules:3213`), яъни кўчиришда ёзиш ҳуқуқи ҳам
   админга ўтиши керак.

`usersCourierRolePromotion` қоидасини сақлаб қолиш мумкин: 3-қадамдан
кейин у фақат профиль кўринишини ўзгартиради, курьерлик ҳуқуқини
бермайди.

**Эгадан керак:** `998912778777` (роли `superadmin`, курьер ҳужжати
бор) ва `998941111184` (Azamat) — булар ким? Биринчиси сизнинг синов
аккаунтингиз бўлса, «кўп қийматли роль» (аввалги Б варианти) умуман
керак бўлмайди.

Қарорсиз ҳолда `couriers` ТЕГИЛМАЙДИ: ҳозир у ёнма-ён ишлайди ва ҳеч
нарса йўқолмайди.

---

## 9-ter. Capability модели (D-12…D-16) — мавжуд код билан солиштириш

Қарор қабул қилинди ва реестрга ёзилди. Имплементациядан олдин **иккита
зиддият** ва **иккита янги хавфсизлик топилмаси** бор.

### 9-ter.1 ЗИДДИЯТ 1 — ҳужжат шакли

Қарорда мисол сифатида **битта uid = битта ҳужжат, ичида хизматлар**
кўрсатилган:

```
provider_capabilities/{uid}
  taxi:    { status: approved }
  courier: { status: trial }
```

Репода эса `provider_capabilities` аллақачон бор ва шакли бошқача:
**битта (uid, модул) жуфти = битта ҳужжат**, калит `{uid}_{module}`
(`functions_demand/core/ids.js:113` → `capabilityKey`). Унга боғлиқлар:

| Нима | Жой |
|---|---|
| Калит ясовчи | `core/ids.js:113` |
| Matching манбаси | `sources/capabilities.js` (`module` + `active` + `regionIds` сўрови) |
| Триггер | `onProviderAvailable` — `provider_capabilities/{key}` onWrite, **бугун деплой қилинди** |
| Индекслар | 3 та composite, ҳаммаси `module + active` билан бошланади |
| Қоида | `firestore.rules:3208`, `key.split('_')[0]` |
| Илова | `provider_capabilities_screen.dart:105` |

**ТАКЛИФ (PROPOSED): мавжуд `{uid}_{module}` шакли сақлансин.** Қарорнинг
маъноси тўлиқ бажарилади — параллел capability'лар шунчаки параллел
ҲУЖЖАТЛАР бўлади (`{uid}_taxi`, `{uid}_courier`, `{uid}_seller`), ҳеч
бири иккинчисини истисно қилмайди.

Нега шакл муҳим — бу қулайлик эмас, **хавфсизлик**: Firestore
қоидасида `diff().affectedKeys()` фақат ЮҚОРИ ДАРАЖАДАГИ калитларни
қайтаради. Ички map билан ёзилганда қоида «клиент `taxi.categoryIds`ни
ўзгартирдими ёки `taxi.status`ни?» деган саволга жавоб бера олмайди —
ҳар бир хизмат учун `request.resource.data.taxi.status ==
resource.data.taxi.status` деб қўлда санаб ёзиш керак бўлади, ва янги
хизмат қўшилганда қоида уни ЖИМГИНА очиб қўяди. D-14 (ўзига ўзи
`approved` бермаслик) айни шу жойда бузилади.

Қўшимча сабаблар: иккита хизмат бир вақтда ёзганда битта ҳужжатда
конфликт бўлади (22-қоида); `onProviderAvailable` битта ҳужжатда
ҳар бир taxi ўзгаришида courier matching'ни ҳам қайта ишга туширади;
`module + active + regionIds` индекси фақат ҳужжат-бўйича шаклда
ишлайди.

### 9-ter.2 ЗИДДИЯТ 2 — `active` ва `status` икки хил тушунча

Мавжуд ҳужжатда `active: bool` бор ва уни КЛИЕНТ ёзади. Қарордаги
`status` эса ҳуқуқ. Иккиси аралаштирилмаслиги керак:

| Майдон | Маъноси | Ким ёзади |
|---|---|---|
| `status` | **ҲУҚУҚ** — `trial` `approved` `rejected` `suspended`… | ФАҚАТ сервер/админ (D-14) |
| `active` | **ХОҲИШ** — «ҳозир сўров олмоқчиман» | фойдаланувчи |

Matching ИККАЛАСИНИ ҳам талаб қилади: `status ∈ {trial, approved}`
**ва** `active == true`. Мавжуд `consentGiven` семантикаси шу билан
сақланади (`sources/capabilities.js:78`).

### 9-ter.3 ЯНГИ ТОПИЛМА — taxi томонида ҲАМ ўзига ўзи тасдиқ бор

D-14 ни текшираётганда маълум бўлди: бу муаммо курьерда эмас, **ҳозир
такси томонида, продакшнда** ҳам бор ва у ердагиси оғирроқ:

```javascript
// firestore.rules:938 — AUTH УМУМАН ЙЎҚ
allow create: if request.resource.data.keys().hasAll(['phone', 'name']);

// firestore.rules:429 — AUTH УМУМАН ЙЎҚ
function driverApprovalPatchOnly() {
  return request.resource.data.diff(resource.data).affectedKeys()
          .hasOnly([... 'approved', 'approvalStatus', 'approvedAt', ...])
      && request.resource.data.approved == true
      && request.resource.data.approvalStatus == 'approved';
}
// firestore.rules:946 — `allow update: ... || driverApprovalPatchOnly()`
```

Яъни **аутентификациясиз** ҳам `drivers/{истalган id}` яратиб, уни
`approved: true` қилиш мумкин. Шундан кейин `approvedDriverForTaxi()`
(rules:353) ўтади ва `queue`, жадвал, сафар оқимлари очилади.

`driver_requests` да ҳам: `allow read: if isAdmin() || true` — яъни
аризачиларнинг исми ва телефони очиқ (40-қоида).

Хулоса: D-12…D-16 фақат курьер учун эмас, **таксига ҳам** тегишли.
`drivers.approved` + `taxiTypes` — бу аслида `taxi` capability'сининг
эски шакли (rules:353), яъни модел янги эмас, умумлаштирилади.

### 9-ter.4 Босқичлар — ТАКЛИФ

| # | Нима | Шакл қарорига боғлиқми |
|---|---|---|
| 0a | ✅ **БАЖАРИЛДИ** — `couriers` `create` → фақат админ | ❌ мустақил |
| 0b | ✅ **БАЖАРИЛДИ** — `drivers` `create` → эгаси/админ ва тасдиқлаш майдонлари тақиқланган; `driverApprovalPatchOnly()` ЎЧИРИЛДИ; эганинг `update`'и `driverApprovalFieldsUntouched()` билан чекланди | ❌ мустақил |
| 0c | ✅ **БАЖАРИЛДИ** — `driver_requests`: `get` очиқ (аризачи ID бўйича), `list` фақат админ | ❌ мустақил |
| 1 | ✅ **БАЖАРИЛДИ** — шакл ўзгарди (битта uid, хизматлар ичида), сервер калитлари `status` `trial` `review` `suspend`, қоида битта қатор билан ҳимоялайди. Модел: `functions_demand/core/capabilities.js` | — |
| 2a | ✅ **БАЖАРИЛДИ** — `requestCapability` callable'и: `not_registered → trial` + 3 кунлик ойна, идемпотент | — |
| 2b | ❌ `courier_documents` + `submitCapabilityDocument` | кейинги |
| 3 | ❌ Админ томони: `approveCapability` / `rejectCapability` / `suspendCapability` + audit log (41-қоида) | кейинги |
| 4 | ✅ **БАЖАРИЛДИ** — `capabilitySweeper` (ҳар соат): `trial` → (бир марта) `trial_expired`/grace → `suspended` | — |
| 5 | ❌ Authorization кўчиши: `resolveAuthorizedCourierUid` → capability; `users.role == 'courier'` ва `isStaff()` даги `courier`/`seller` олиб ташланади | кейинги |
| 6 | ❌ `couriers` ўтиш манбаси сифатида қолади, кейин чиқарилади | кейинги |

**Бажарилган қисмнинг шакли** (жонли, 2026-10-06 кечки деплой — T-1a ва
T-2 билан янгиланган; тўлиқ қарорлар [taxi_billing_uz.md](taxi_billing_uz.md)):

```
provider_capabilities/{accountId}          ← калит: users/{phone}.accountId
  identity: { accountId, primaryUid }       ← ФАҚАТ СЕРВЕР (матчинг primaryUid билан)
  courier:  { active, categoryIds, regionIds, districtIds,
              pushOptOut, digestOnly, updatedAt }  ← КЛИЕНТ
  taxi:     { active, ... }                        ← КЛИЕНТ
  status:   { courier: 'trial', taxi: 'starter' }  ← ФАҚАТ СЕРВЕР
  window:   { courier: { startedAt, endsAt, graceGrantedAt, graceEndsAt },
              taxi:    { startedAt, verificationDueAt, billingGraceUntil } }
  review:   { courier: { reviewedBy, at } }        ← ФАҚАТ СЕРВЕР
  suspend:  { courier: { at, reason, by } }        ← ФАҚАТ СЕРВЕР
```

Lifecycle хизмат бўйича: курьер `trial → trial_expired → document_submitted
→ under_review → approved`; такси `starter → verification_required →
verified`; оддийлар `enabled`. Ҳужжатни фақат сервер яратади
(`requestCapability`), клиент фақат ўз хизмат map'ини янгилайди.

Ўзгарган жойлар: `core/capabilities.js` (янги, модел) ·
`api/capabilities.js` (янги, callable + sweeper) ·
`sources/capabilities.js` (ўқувчи) · `api/maintenance.js`
(тескари matching) · `index.js` (триггер + экспортлар) ·
`core/ids.js` (`capabilityKey` олиб ташланди) ·
`firestore.indexes.json` (хизмат бўйича индекслар) ·
`provider_capabilities_screen.dart` + `demand_activity_entry.dart`.

`courier_documents` учун репода тайёр намуна бор: `driver_requests`
(ариза → `status: 'pending'` → админ тасдиқлайди). Янги механизм
ўйлаб топилмайди, шу намуна ишлатилади (4 ва 43-қоида).

### 9-ter.5 Муддат механикаси (D-15.1) — сервер майдонлари

Ҳаммаси СЕРВЕР қўлида (D-14), клиент биронтасига тегмайди:

| Майдон | Маъноси |
|---|---|
| `trialStartedAt` | синов бошланган вақт |
| `trialEndsAt` | `trialStartedAt + 3 кун` |
| `graceGrantedAt` | extension берилган вақт — **`null` бўлса ҳали берилмаган** |
| `graceEndsAt` | `graceGrantedAt + 5 кун` |
| `suspendedAt`, `suspendedReason` | `'documents_missing'` |

Sweeper мантиғи (ҳар соат):

```
status == 'trial'  &&  now > trialEndsAt:
    graceGrantedAt == null  →  graceGrantedAt = now
                               graceEndsAt    = now + 5 кун
                               status         = 'trial'  (ЎЗГАРМАЙДИ)
    aks holda               →  status = 'suspended'

status == 'trial'  &&  graceEndsAt != null  &&  now > graceEndsAt:
    status = 'suspended',  suspendedReason = 'documents_missing'
```

**Extension БИР МАРТА** — `graceGrantedAt == null` шарти транзакция
ичида текширилади, акс ҳолда sweeper иккинчи марта ишга тушганда
муддат чўзилиб кетарди (21-қоида: идемпотентлик).

**Аккаунт очиқ қолади:** `users` ҳужжатига ва бошқа capability'ларга
ТЕГИЛМАЙДИ. Курьер такси ҳайдовчиси ҳам бўлса, такси иши давом этади
(D-13).

**Тикланиш:** `suspended` → ҳужжат юклайди → `document_submitted` →
`under_review` → админ тасдиқлайди → `approved`. Яъни `suspended`
тупик эмас.

**ОЧИҚ САВОЛ (эга ҳал қилади):** `suspended` бўлган курьернинг
**қўлида турган** жўнатма нима бўлади? Таклифим: suspension ЯНГИ
тайинлашни тўхтатади (matching + `acceptOffer`), лекин мавжуд фаол
маршрутни тугатишга рухсат беради — акс ҳолда посилка йўлда «эгасиз»
қолади ва custody занжири узилади (15-қоида).

---

## 10. Жорий этиш босқичлари

`OFF → INTERNAL → PILOT → PUBLIC` (CLAUDE.md 42-банд).
Пилот: Хоразм ичи → Урганч ↔ Тошкент. Мавжуд `orders` ва
`delivery_routes` тегилмайди, AVA'нинг ўз товарлари учун ишлашда давом
этади.

### 10.1 Деплой ҳолати — 2026-10-06

Ҳаммаси чиқди. Биллинг тўсиғи (`generateUploadUrl` → 403) тўлов билан
ҳал қилинди ва деплой белгиланган тартибда қайта бажарилди.

| # | Нима | Ҳолат |
|---|---|---|
| 1 | `firestore.rules` (`presenceClientFieldsOk`) | ✅ Ruleset `7b886b60-a8ef-4426-8657-c421bacbe9bb`, 05:50 UTC. Эскиси `11c4b305-6c46-41dd-9bf2-ce4ab39e7a9e` — rollback манбаси сақланган. Деплойдан кейин жонли мантиқ локал файл билан 2387/2387 қатор мос |
| 2 | `functions:default` — `onDeliveryRouteCreate`, `onDeliveryRouteAssign` | ✅ `ACTIVE`, `nodejs20`, `updateTime` 06:46 UTC (аввал 10-01) |
| 3 | `functions:demand` — 15 функция | ✅ ҳаммаси `ACTIVE`, `nodejs22`, europe-west1, 06:48 UTC |
| 3a | `firestore.rules` — 0a·0b·0c (ўзига ўзи ҳуқуқ бериш) | ✅ Ruleset `8d3c8de7-bd63-47eb-a7a5-a69d662df805`, 08:23 UTC. Жонли мантиқ локал файл билан 2388/2388 мос. Rollback: `7b886b60-a8ef-4426-8657-c421bacbe9bb` |
| 3b | Capability модели — индекслар + қоида + `functions:demand` | ✅ 08:55 UTC. `requestCapability` ва `capabilitySweeper` `ACTIVE`; scheduler `every 60 minutes` `ENABLED`; `demandCoreStatus` → `modules: service, courier`. Индекслар: жонли ҳолат файл билан **айнан мос** (0 етишмайди, 0 ортиқча) |

**Индекс деплойи ҳақида огоҳлик.** `firebase deploy --only
firestore:indexes --force` буйруғи **4 та** индексни ўчирди, ҳолбуки
мен фақат 3 тасини (эски capability индекслари) олиб ташлаганман.
Тўртинчиси — репо файлида бўлмаган, продакшнда қўлда яратилган индекс
(drift). Деплойдан кейинги солиштириш: жонли ҳолат файл билан **айнан
мос**, яъни файл энди ягона ҳақиқат манбаси. Агар бирорта сўров
индекссиз қолса, Firestore логида «The query requires an index» хатоси
ва яратиш ҳаволаси билан кўринади. Кейинги индекс деплойида `--force`
ишлатилмайди — ўчирилаётганлар рўйхати қўлда кўрилади.
| 4 | Cloud Scheduler | ✅ 4 иш `ENABLED`: `presenceSweeper` (2 дақиқа), `expireDemandsSweeper` (5), `reopenStaleAssignments` (10), `aggregateDemandAnalytics` (02:30) — ҳаммаси Asia/Tashkent |
| 5 | Индекслар | ✅ аввалдан бор, янгиси керак эмас |
| 6 | Илова build'и | ⏸ эга ҳал қилади |

**Жонли текширув (тахмин эмас):**

- `demandCoreStatus` → `region: europe-west1`,
  **`modules: ["service", "courier"]`**, `taxonomyVersion: 1`,
  40 категория, 397 калит сўз. Яъни курьер адаптери продакшнда рўйхатда.
- `presenceSweeper` биринчи ишга тушиши: 06:50:00 UTC,
  `finished with status: 'ok'` (4618 ms — совуқ старт).
- europe-west1 да охирги 20 дақиқада `severity>=ERROR` — **битта ҳам йўқ**.

**Ядро OFF босқичида** (42-қоида). `module_config` коллекциясида 0
ҳужжат, яъни ҳар бир модул `DEFAULTS` билан ишлайди:
`enabled: false` → `createDemand` талабни рад этади,
`pushEnabled: false` → ҳеч кимга хабар кетмайди. Ядро жонли, лекин
ҳозир фойдаланувчига кўринмайди. `INTERNAL`га ўтиш —
`module_config/courier_xorazm` ҳужжатини яратиш билан, бу алоҳида қарор.

**Қоида илова build'ини КУТМАДИ:** `provider_presence` да 0 ҳужжат,
яъни чиқарилган ҳеч бир илова версияси у ерга ёзмайди — янги қатъий
қоида ҳозирги фойдаланувчиларга таъсир қилмайди. Янги илова
версиясидаги ёзувчи эса қоидага мос (29 текширув).

**`demand` codebase'ини деплой қилишда ШАРТ:**

```powershell
$env:FUNCTIONS_DISCOVERY_TIMEOUT=90
firebase deploy --only "functions:demand" --project master-taxi-gurlan
```

Усиз деплой «User code failed to load. Timeout after 10000» деб
тўхтайди — бу ЁЛҒОН хато: `index.js` тўғридан-тўғри 353 ms да 15
экспорт билан юкланади, тўсиқ CLI'нинг localhost handshake'и.

### 10.2 Relay — код ҳолати, 2026-10-07 (implementation completed, deploy pending)

Эга қарори (2026-10-05/06, D-1…D-11) **кодга киритилди**, лекин
**production'га ЧИҚАРИЛМАГАН** (29-банд). Ҳаммаси `feat/ev-trip-planner`
ветвида, иккита commit: сервер/қоида ва Flutter/admin.

| Қатлам | Файл(лар) | Ҳолат |
|---|---|---|
| Тариф engine (D-2, D-8) | `functions_demand/core/tariff.js` | версияли `module_tariffs/logistics` + `logistics_v{N}` (draft/active/retired); 6 зона matrix (region→district override); `chargeableWeight = max(actual, ceil(L×W×H×1000/divisor))` грамм; `PriceSnapshot` ҳар жўнатмада; ички тақсимот `internal.platformMarginBps`/`legShareBps` — null бўлса фаоллашмайди |
| Қоралама тариф | `core/seed/logistics_tariff_draft.json`, `tools/seed_logistics_tariff.js` | `prices: {}` — **НАРХЛАР ЙЎҚ, эга беради** (UNKNOWN); dry-run стандарт, `--write` билан `logistics_v1` draft |
| ORDER / SHIPMENT / LEG (D-3, D-4, D-10) | `core/logistics.js`, `api/logistics.js` | `logistics_orders` 1:N `shipments` 1:N LEG = мавжуд `demands` ҳужжати (`module: logistics`); status machine сервер томонда; `route_plans/{shipmentId}/versions/{n}` |
| Custody (D-5, D-6, D-7) | `api/logistics.js` → `custody_events` | `scanHandover` (код **ёки** QR + расм мажбурий + ҳолат белгиси, БИТТА транзакция), `confirmDelivery` (алоҳида 6 хонали код), idempotency `{ship}_{leg}_{kind}`; тарих immutable (rules `write: false`) |
| Занжир (6.1) | `api/logistics.js` `activateLeg` | кейинги LEG олдингиси **`in_progress`** бўлганда очилади (`openNextLegOn`, конфиг) — ҳужжат 7.3 даги «completed» deadlock бўлгани учун ўзгартирилди (INFERRED, эга тасдиғи кутилади) |
| Matching | `adapters/logistics.js`, `sources/logistics_candidates.js` | courier (`acceptsParcels: true`) + freight; проекцияда `shipmentId`, tracking, LEG k/n, ўлчам, **payout** (ижрочига очиқ), мижоз нархи ЙЎҚ (14-банд) |
| Конфиг | `core/config.js` → `module_config/logistics_all` | `CONFIG_REGION = 'all'` (PROPOSED): ядро `moduleRegionKey` `_`ли ҳудуд ID'ни олмайди; логистика ҳудудлараро |
| Пул (D-11, 7.6) | `functions/relay_escrow.js`, `settlement_ledger.js` | default codebase: `fundShipmentEscrow` (ҳамён → `escrow:{shipmentId}`), `onLogisticsCustodyEvent` (EARNED → `supplier_payable:{provider}`), RELEASE (эскроу → accrual + `earnings:ava_logistics_fee`), REFUND (`refund_pending` → ҳамён); ҳаммаси idempotent калит билан; frozen'да RELEASE йўқ, EARNED бор |
| Rules / indexes / storage | `firestore.rules`, `firestore.indexes.json`, `storage.rules` | мижоз ҳеч нарса ёзмайди; `shipments/private/*` ҳеч ким ўқимайди; `module_tariffs/logistics*` фақат admin ўқийди (умумий блокда истисно); сўровлар `ownerId` филтри билан (қоида исботи); `logistics/{uploader}/…` расм йўли |
| Flutter — мижоз | `lib/features/logistics/` | «Жўнатма» плиткаси (`kKnownModuleIds` → admin ёқади), форма (вилоят/туман/манзил, посилка ×5, қабул қилувчи), `quote` → `create`, буюртма экрани: ҳамёндан тўлаш, кодлар + QR (`qr_flutter`), кузатув тасмаси, бекор |
| Flutter — ижрочи | `ui/logistics_ui_adapter.dart`, `ui/leg_actions.dart` | ядро `DemandUiAdapter.buildMatchActions` (янги hook): «олиш» → «посилкани олдим» (код + расм + ҳолат) → охирги LEG «топширдим» (код) / ўрта LEG «код ва QR кўрсатиш»; `MatchStatus` + `in_progress`/`completed`; `MatchContact` + 2-поғона майдонлари |
| Admin web | `admin_web/screens/logistics_admin_screen.dart` | тариф версиялари (JSON қоралама → фаоллаштириш), жўнатмалар рўйхати, custody тарихи, маршрутни LEG'ларга бўлиш — ҳаммаси callable орқали, audit билан |
| Capability | `provider_capabilities_screen.dart` | курьер учун «Посилка ҳам оламан» (`courier.acceptsParcels`, стандарт ЎЧИҚ — opt-in) |

**Паритет қулфи.** `functions_demand/test/fixtures/logistics_parity.json`
— `docs` бўлими серверни FakeFirestore'да ҳақиқий оқимда юритиб ёзилади
(`node functions_demand/test/logistics_parity.test.js --update`); Dart
тести (`test/features/logistics/logistics_parity_test.dart`) айни шу
ҳужжатларни ўқийди. `reason` кодлари манбадан (api + tariff + escrow)
икки томонлама солиштирилади; `logistics_err_*` матн калитлари фақат
мавжуд кодлар учун.

**Тестлар (2026-10-07, ҳақиқий натижа):** `functions_demand` run_all —
614 ўтди, 0 хато (tariff 18, logistics_core 13, logistics_api 11,
logistics_parity 7 шу ичида); emulator: `logistics_rules` 18/18,
`taxi_billing_rules` 13/13, `relay_escrow_cf` 10/10, `taxi_billing_cf`
26/26; Flutter: logistics + demand parity + locale sync + tile тестлари
77 ўтди; `flutter analyze` ўзгарган файлларда 0 муаммо.

**Emulator — Windows огоҳлиги.** TCP динамик диапазон 1024–15000;
Hyper-V ҳар юкланишда шу ичидан блоклар банд қилади (2026-10-07 да 9500
→ 9440–9539 ичида қолди). Порт энди **18080** (диапазондан ташқари).
`emulators:exec` тугагач JVM (`cloud-firestore-emulator`) ўчмай қолади —
кейинги run'дан олдин ўша `java.exe` тўхтатилади, акс ҳолда «port taken».

**Деплой — 2026-10-07, 01:43–01:50 UTC (эга буйруғи билан, ҳар бири алоҳида):**

| # | Нима | Ҳолат |
|---|---|---|
| 1 | `functions:default` — **фақат** `fundShipmentEscrow`, `onLogisticsCustodyEvent`, `onLogisticsShipmentUpdate` (номма-ном) | ✅ ACTIVE 01:43 UTC, v1. Тўлиқ `functions:default` деплойи **ҚИЛИНМАДИ** — пастдаги огоҳликка қаранг |
| 2 | `functions:demand` — тўлиқ | ✅ 11 яратилди, 20 янгиланди, 0 хато; `demandCoreStatus` → `modules: service, courier, logistics` |
| 3 | indexes (`--force` йўқ) | ✅ 5 та logistics индекси CREATING → READY; эски `taxi_trips(…refunded…)` индекси **ўчирилмади** (CLI фақат огоҳлантирди, 1 та) |
| 4 | rules — алоҳида | ✅ Ruleset `d7e1405a-9a7f-4e24-af94-05e2903e107a`, 01:48 UTC; жонли матн HEAD билан айнан мос. Rollback: `2dc6b7fa-1e2b-4b6d-bc42-0012cccd7af7` (== commit `b29a8df~1`) |
| 5 | storage rules | ✅ released; жонли матн HEAD билан мос. Rollback: `ab3a29fd-0863-4d08-a4a4-ef71ad933f79` |

Деплойдан кейин 20 дақиқада `cloud_function severity>=ERROR` — йўқ.

**ОГОҲЛИК — production default codebase бир нечта ветвдан йиғилган.**
Тўлиқ `functions:default` деплойи бу ветвдан бошланганда CLI
`reconcileTvProfileViews`ни ўчиришни талаб қилди (non-interactive'да
abort). У ва `clipPage` v3 2026-10-06 06:39 UTC да `fix/realty-audit-p1`
ветвидаги `606509e` («Phase 2: playbackStats») commit'идан чиққан — бу
ветвда йўқ. Шунинг учун бу ветвдан `functions:default`ни **тўлиқ деплой
қилиб бўлмайди**: у бошқа сессия функциясини ўчиради ва `clipPage`ни эски
версияга қайтаради. Default codebase функциялари фақат номма-ном
(`functions:default:<name>`) деплой қилинади, то ветвлар бирлаштирилмагунча.

**Тариф — эга модели N=1 (2026-10-07, AVA_DECIDED, §7.5).**
`weightBrackets: [21000]`; ZONE_0 `130 000 / +2 500`, ZONE_1
`250 000 / +6 000`, ZONE_4 `310 000 / +8 500` (ҳар бошланган кг);
ZONE_2/3/5 — нарх йўқ (матрицада ҳам йўқ). Seed:
`core/seed/logistics_tariff_draft.json`; seed tool draft'ни **тўлиқ
алмаштиради** (merge эмас — акс ҳолда эски `prices.ZONE_x` қолиб кетарди).
Production'даги `logistics_v1` draft ҳали **эски 5 поғонали** кўринишда
(01:55 UTC seed) — эга қарори (2026-10-07): **B** — эга admin JSON
муҳаррири орқали тайёр JSON билан ўзи алмаштиради (callable тўлиқ
алмаштиради, `logistics_audit`). `limits.maxWeightG = 20000` — эга белгилагунча ўзгартирилмади
(21 кг чегара билан зиддиятли: 20–21 кг рад, `extraPerKg` ишламайди —
тест билан қулфланган). Фаоллаштириш учун етишмайди:
`internal.platformMarginBps`, `internal.legShareBps` (эга беради; admin
«Нархлар» муҳарририда ҳам тўлдирилади). Admin панел: нарх жадвали
муҳаррири (устунлар `weightBrackets`дан динамик), ички улушлар,
**«Барча нархларни % га»** тугмаси (яхлитлаш 1/100/1000 сўм; фаол
версиядан — янги қоралама); ҳисоб `tariff_adjust.dart` (соф Dart, тест).

**Pilot'гача ёпилган бўшлиқлар (2026-10-07, эга рухсати; деплой қилинди
04:25 UTC — `functions:demand` 1 яратилди/31 янгиланди/0 хато,
`adminReactivateLeg` ACTIVE, sweeper'лар v8; hosting `/`+`/admin/` қайта
чиқарилди, жонли бандлда текширилди):**
(А) `reopenStaleAssignments` логистика LEG'ларини ўтказиб юборади
(`api/maintenance.js`) — акс ҳолда LEG-1 келгунча кутаётган LEG-2 ижрочиси
120 дақиқадан кейин чиқариб ташланиб NO_SHOW жазоси оларди; (Б)
`expireDemandsSweeper` муддати тугаган LEG учун `shipments.legProblem`
ёзади, admin панелда «⚠ LEG муддати тугаган» филтри ва «LEG'ни қайта
очиш» тугмаси → `adminReactivateLeg` (matching қайтадан, payout/маршрут
ўзгармайди, `logistics_audit`). Тестлар: `maintenance.test.js`,
`logistics_api.test.js` (LEG-2 expired → reactivate → занжир давом этади).

**Ёқиш калитлари (2026-10-07, эга рухсати билан):**
`module_config/logistics_all` ← `{enabled, matchingEnabled, pushEnabled:
true}` — `functions_demand/tools/enable_module.js --write` билан яратилди
(real код йўли `resolveFlags` орқали текширилди: enabled/matching/push
true, killReason бўш). `config/module_defaults.modules.logistics` аллақачон
`enabled` эди (эга ўзи қўйган, `enforce=true`) — тегилмади.
**Hosting (2026-10-07, эга рухсати):** `scripts/build_combined_web.ps1`
→ `firebase deploy --only hosting` — `/` ва `/admin/` шу ветвдан (жонли
версия аввал ҳам 1.0.33+71 эди, бошқа ветв йўқ); `/admin/`да «AVA
Logistics» бўлими ва «Ҳудудлар ва хизматлар → logistics» бор (жонли
`main.dart.js`да текширилди). Диққат: `/` веб-илова ҳам янги — модул
enabled бўлгани учун веб фойдаланувчи «Жўнатма» плиткасини кўради; тариф
фаол бўлмагунча нарх сўрови «хизмат ҳали ишга тушмаган» дейди.
**Хизмат ҳали ишламайди:** фаол тариф йўқ (`module_tariffs/logistics`
pointer йўқ — v1 қоралама `internal.*` сиз фаоллашмайди) → `createLogisticsOrder`
`tariff_not_active` қайтаради; мобил плитка эса фақат янги илова build'ида
(1.0.34 ҳали қурилмаган, эга қарори). Ёқиш — эга қарорлари: тариф рақамлари →
`seed --write` → `adminActivateLogisticsTariff`; `module_config/logistics_all`
(`enabled/matchingEnabled/pushEnabled: true`); admin web rebuild
(`scripts/build_combined_web.ps1` → `hosting`) → «Ҳудудлар ва хизматлар»
→ `logistics` Очиқ (ёки `config/module_defaults.modules.logistics.status =
enabled`); янги илова build'и 1.0.34 (плитка ва оқимлар фақат унда).

**Кейинга қолган (эга билан):** L6a–L6c, L13 (камера сканери — ҳозир
код қўлда киритилади, QR кўрсатилади), L14 (шартлар матни —
`termsAcceptedAt` юборилмайди), L15; GPS нуқтаси handover'да
(ихтиёрий майдон бор, илова ҳали юбормайди); офлайн навбат (6.2).

---

## 11. Очиқ саволлар

1. F1, F2, F3, F6, F8, F9, F10, F12–F16 — кодда текширилмади. Кейинги ўтиш.
2. AVA'нинг `volumetricDivisor` қиймати — BTS'нинг 6000 и бозор мўлжали,
   AVA қарори эмас.
3. Офлайн handover навбатининг муддати ва конфликт қоидаси.
4. Консолидация чегирмаси кимнинг ҳисобидан: платформа маржасиданми ёки
   провайдер тўловиданми.
5. Ўлчам номувофиқлигида толерантлик чегараси ва қайта нархлаш оқими.
6. `trackingNumber` форматининг аниқ таркиби ва коллизия стратегияси.
7. Брифдаги намунавий нарх (5 кг Гурлан → Тошкент/Чилонзор = 90 000 сўм)
   BTS бўйича ≈215 000 сўм. Мисол тузатилсинми ёки AVA'нинг арзонлиги
   қайси компонент ҳисобига эканлиги асослансинми.
