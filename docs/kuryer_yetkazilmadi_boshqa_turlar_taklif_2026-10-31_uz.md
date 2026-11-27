# «Етказилмади» — ресторандан бошқа курьер турлари учун таҳлил ва таклиф

**Сана:** 2026-10-31 · **Ҳолат:** фақат таҳлил ва таклиф. Код, rules, маълумотлар ўзгармади, деплой қилинмади.

**Манба:** `.claude/worktrees/deploy-cfh-a` (commit `dabf2371`, курьер функцияларининг production манбаи), `functions/` ва `functions_demand/`.
Мижоз иловаси учун жонли хостинг lineage ишлатилди: `.claude/worktrees/deploy-ulg-hosting/lib`.
Ҳужжатлар: `docs/kuryer_qarorlar_loyiha_2026-10-31_uz.md`, `docs/kuryer_paneli_audit_2026-10-31_uz.md`.

**Белгилар:**
- **CONFIRMED** — кодда кўрилди (`файл:қатор`, `functions/` ичида бўлса файл номи қисқа ёзилган);
- **INFERRED** — коддан кучли хулоса;
- **PROPOSED** — менинг таклифим;
- **UNKNOWN** — маълумот йўқ, эга тасдиқлаши керак.

**Эга қарори (2026-10-31):** «Етказилмади» барча курьер турларида мижоз тасдиғи билан бўлади. Мижоз 15 дақиқада жавоб бермаса (бу вақтни админ ўзгартиради), сотувчи ҳал қилади. Ресторан буюртмасида ресторан ҳал қилади.

---

## 0. Ресторанда тайёр бўлган намуна (қайта ишлатилади)

| Қисм | Қаерда | Ҳолат |
|---|---|---|
| Курьер `outcome:'failed'` юборади. Ҳолат ҳам, пул ҳам ўзгармайди. Буюртмага `awaitingCustomerConfirm{step:'delivery_failed', failReason, escalateAt}` ва `deliveryFailedEscalateAt` ёзилади | `restaurant_orders.js:1750-1775` | CONFIRMED |
| Мижоз «тасдиқлайман» деса — якун: 2 % комиссия ресторанга қайтади, `customer_absent` ёки `customer_refused` сабабида мижозга strike ёзилади | `restaurant_orders.js:1937-1950`, `:1846-1865` | CONFIRMED |
| Мижоз «Олмоқчиман» (rad) деса — етказиш давом этади | `restaurant_orders.js:1963-1973`, `continueInTx` `:1981-1994` | CONFIRMED |
| Ҳар дақиқада ишлайдиган scheduler: бир майдон бўйича оралиқ сўрови (`deliveryFailedEscalateAt <= now`), композит индекс керак эмас | `restaurant_orders.js:2120-2171` | CONFIRMED |
| Қарор callable'и `failed` ёки `continue`. Ким чақиради: ресторан аъзоси ёки admin (admin_audit билан). Муддат тугамагунча `DECISION_NOT_YET` қайтаради | `restaurant_orders.js:2044-2113` | CONFIRMED |
| `failedTimeoutMin`: 1–240, стандарт 15, админ созлайди | `customer_confirm.js:76-79, 125-132, 505-508` | CONFIRMED |
| «Етказилмади» фақат ресторанда бор ва модуль ёқилганми-йўқми, ҳамма мижоз учун мажбурий | `customer_confirm.js:68-74` | CONFIRMED |
| Курьер «етказилмади» учун ҳақ олмайди: етказиш ҳақи ечилмайди, ҳамёнга ҳеч нарса ёзилмайди | `restaurant_orders.js:1795-1800` (фақат `delivered` да), `:1846-1865` | CONFIRMED |
| Жонли веб иловада мижоз учун «Олмоқчиман» тугмаси (`canReject`) йўқ | hosting `lib` бўйича grep: `canReject` ва `'reject'` customer_confirm'да топилмади | INFERRED (ресторан намунасининг UI'си ҳам жонлида йўқ) |

`customer_confirm.js` ҳозир тўртта модулни билади: `restaurant`, `carpet`, `agro`, `collection` (`:57-66`). Нон ва бозор (`orders`, type `bread` ёки `platform`) учун модуль **йўқ** (CONFIRMED).

---

## 1. Нон ва бозор буюртмалари (`orders`, `type: bread | platform`)

### 1.1 Ҳозирги оқим (CONFIRMED)

- **Яратиш:** `placeOrderPostPaid` (`index.js:3146-3486`). Нарх серверда ҳисобланади (`:3234-3258`). Омбордаги `soldToday` камаяди (`:3334-3344`).
  Мижоз хоҳласа, ҳамёндан қисман ёки тўлиқ тўлайди: `balanceApplied`, `walletUserDocId`, ledger `order_wallet` (`:3321-3375`).
  Шунда `cashDue = total − walletDebit`; `paymentStatus` эса `paid` (ҳаммаси ҳамёндан тўланган бўлса) ёки `unpaid` бўлади (`:3386`).
  `platform` турида `deliveryFee` = товарнинг `platformDeliveryFeePercent`% и (стандарт 5) ва у `total` ичида (`:3248-3255`).
- **Сотувчи:** буюртмада `sellerId` майдони **йўқ** (`:3388-3410`). Ҳолатни админ ўзгартиради: `new → accepted → ready` (`adminSetOrderStatus`, `:8839-8845`).
  Staff роли `seller` бор (`sellerPlaceSale`, `sellerMarkPickupReady`, `:3764-4188`), лекин етказиладиган буюртма бўйича ҳеч қандай callable'и йўқ.
  Демак «сотувчи» — AVA'нинг ўзи (`seller` ёки admin ходими). Бу INFERRED.
- **Курьер:**
  1. `courierCreateRoute` — маршрутга олганда буюртма дарҳол `in_delivery/courier_picked` бўлади (`:4566-4576`).
  2. `courierMarkPicked` (`:4427-4483`).
  3. `courierMarkArrived` → `fulfillmentStatus: arrived` (`:4767-4823`).
  4. `courierSubmitPayment` → `paid/completed/delivered` (`:4891-5292`). Нақд пул `courier_cash_pending` ва `courier_field_cash` ga, кейин `admin_clearing` ga ёзилади (`:5246-5266`, `:5349-5397`).
  5. Кейинги буюртмага ўтиш **клиентда**: `confirmAndAdvance` (`courier_controller.dart:377-419`). У `isOrderFinalized`'ни текширади, яъни `paid`, `completed` ёки `delivered` (`:93-98`).
- **Курьер ҳақи:** нон ва бозор буюртмалари учун серверда курьер тўлови **йўқ**. `courierPayout`, `courierFee` ва шунга ўхшаш номлар бўйича grep ҳеч нарса топмади. `platform` даги `deliveryFee` бутун сумма билан бирга `admin_clearing` ga тушади.
  Курьерга қандай тўланади: UNKNOWN (тизимдан ташқарида бўлса керак — INFERRED).
- **Бекор қилиш йўллари:**
  - `customerCancelOrder` — фақат `new`, `accepted` ёки `ready` ҳолатида. `courier_picked`, `arrived` ва `in_delivery` да рад этилади (`:3712-3727`).
  - Ядро `prepareOrderCancelInTx` ва `commitOrderCancelInTx`: ҳамёнга `balanceApplied` қайтади (`order_cancel_refund_{id}`) ва `soldToday` тикланади (`:3536-3643`).
  - Админ `rejected` ни курьер қўлидаги (`courier_picked`, `arrived`) буюртмага қўя олмайди (`:8848-8858`).
- **Мижоз тасдиғи:** бу тур учун йўқ.

**Муҳим топилма (CONFIRMED):** мижоз уйда бўлмаса, нон ёки бозор буюртмасидан **чиқиш йўли умуман йўқ**:
- курьер «етказилмади» дея олмайди;
- мижоз бекор қила олмайди (`:3713-3719`);
- админ рад эта олмайди (`ORDER_HELD_BY_COURIER`, `:8856-8858`);
- `→ delivered` учун `paid` шарт (`:8859-8861`);
- курьери бор буюртмани `→ ready` га қайтариб бўлмайди (`:8863-8866`).

Натижада буюртма `in_delivery` да қотиб қолади. Курьер эса маршрутни клиентда суриб ўтиб кетади (аудит R-1 ва R-2).

### 1.2 Жисмонан нимани англатади

Курьер нон ёки товарни олиб келди, мижоз эшикда йўқ ёки олмади. Товар курьер қўлида қолади ва сотувчи нуқтасига (AVA новвойхонаси ёки омбори) қайтиши керак.
Нақд пул олинмаган. Ҳамёндан олдиндан ечилган қисм (`balanceApplied`) бор бўлиши мумкин.

**Ким ҳал қилади:** буюртмада эгаси ёзилган майдон йўқ. Шунинг учун AVA ходими — `seller`, `admin` ёки `superadmin` ролидаги одам (INFERRED; 1-савол).

### 1.3 Таклиф (PROPOSED)

- **Курьер:** янги умумий callable `courierReportDeliveryFailed({module:'order', id, reason})`. Шартлар: `fulfillmentStatus ∈ {courier_picked, arrived}` ва буюртма шу курьернинг фаол маршрутида (`assertOrderOnActiveRoute`).
  Натижа: фақат белги ёзилади (`awaitingCustomerConfirm.step = 'delivery_failed'` + `deliveryFailedEscalateAt`). Ҳолат ва пул ўзгармайди.
- **Мижоз:** 2 та жавоб:
  - «тасдиқлайман» — буюртма якунланади;
  - «Олмоқчиман» — белги ўчади, етказиш давом этади (ресторандаги `continueInTx` каби).
- **15 дақиқа ўтса:** қарор `seller` ёки admin га ўтади (`failed` ёки `continue`).
- **Якуний ҳолат:** `status: 'cancelled'`, `fulfillmentStatus: 'delivery_failed'`, `cancelReason: 'delivery_failed:<reason>'`, `deliveryFailedResolution{by, decision, at}`.
  Эски иловалар `cancelled` ни танийди. Янги `status` қиймати қўшилмайди: эски admin доскаси ва мижоз экрани бузилмайди.
- **Пул:** мавжуд ядро қайта ишлатилади (`prepareOrderCancelInTx` + `commitOrderCancelInTx`):
  - ҳамёнга `balanceApplied` тўлиқ қайтади;
  - `soldToday` тикланади.

  Нақд пул олинмагани учун `courier_cash` га ҳеч нарса ёзилмайди. `platform` да `deliveryFee` ҳам қайтади, чунки у `balanceApplied` ичида. Бу 3-саволда сўралган.
- **Маршрут:** сервер якунда буюртмани маршрутдан чиқаради ёки `currentIndex`ни суради. Клиентнинг `confirmAndAdvance` ига ишонилмайди (R-1, R-2).
- **Товар:** «сотувчига қайтарилди» деган тасдиқ (custody, 15-банд) 1-босқичда фақат event сифатида ёзилади. Сотувчининг «қабул қилдим» тугмаси — 2-босқич.
- **Курьерга ҳақ:** ҳозир тизимда ҳақ йўқ, шунинг учун ўзгармайди.
- **Мижозга strike:** 1-босқичда фақат event ёзилади. Ресторандаги `restaurant_customer_stats` ga **қўшилмайди** (4-савол).

---

## 2. Гилам ювиш (`carpet_wash_orders`) — олиб кетиш ва қайтариш

### 2.1 Ҳозирги оқим (CONFIRMED)

- **Ҳолатлар:** `new → accepted → pickup_ready → pickup_in_delivery → picked_up → washing → drying → ready → return_ready → return_in_delivery → completed` (`index.js:19609-19623, 19765-19777`).
- **Курьер:**
  - `courierClaimCarpetPickup` (`:19881-19926`);
  - `courierMarkCarpetArrived` — олиб кетишда ҳам, қайтаришда ҳам (`:19929-20001`);
  - `courierMarkCarpetPickedUp` (`:20083-20122`);
  - `courierClaimCarpetReturn` (`:20125-20170`);
  - `courierMarkCarpetDelivered` (`:20173-20212`).
- **Мижоз тасдиғи:** иккита қадам бор, `handover_pickup` ва `handover_return` (`:20055-20080`). Модуль босқичига боғлиқ: `isGated` (`:20104`, `:20194`).
- **Пул:** `finalPrice` ни админ қўяди (`:19830-19835`). Мижоздан пул олиш коди **топилмади**: `finalPrice` фақат курьер ҳақи учун база (UNKNOWN: мижоз қандай тўлайди).
  Курьер ҳақи `floor(finalPrice × bps / 10000)` фақат `completed` да, қайтарган курьерга ҳисобланади. Олиб кетган курьернинг ҳақи — очиқ савол (`:20039-20053`).
  Бу ҳақ фақат `courier_task_payouts` ҳужжатига ёзилади, ҳамёнга пул ўтмайди (`courier_task_payout.js:33-34`).
- **Бекор қилиш ва бўшатиш:**
  - админ: `pickup_in_delivery → cancelled | pickup_ready`;
  - админ: `return_in_delivery → return_ready` (курьер майдонлари тозаланади, `admin_audit`, `:19765-19790, 19836-19852`).

  Мижоз бекор қилиш callable'и йўқ (grep).
- **Сотувчи ёки эгаси:** ҳужжатда `washId`, `ownerUid` йўқ (`:19728-19742`, grep). Гиламни AVA ювади ва ҳамма нарсани админ бошқаради (INFERRED).

### 2.2 Жисмонан

- **Олиб кетиш муваффақиятсиз:** мижоз уйда йўқ. Ҳеч нарса олинмаган, пул йўқ, курьер бўш қайтади.
- **Қайтариш муваффақиятсиз:** тоза гилам курьер қўлида қолади ва **ювиш цехига қайтади**. Бекор қилиб бўлмайди, гилам мижозники. Кейин қайта етказиш керак.
- **Ким ҳал қилади:** admin (эгаси майдони йўқ; 1-савол).

### 2.3 Таклиф (PROPOSED)

- **Курьер:** `courierReportDeliveryFailed({module:'carpet', id, leg:'pickup'|'return', reason})`. Шартлар: `assertCarpetPickupReady` ёки `assertCarpetReturnReady` (`:20005-20027`; «етиб келдим» шарт).
- **`failed` якуни:**
  - олиб кетиш → `pickup_ready` (навбатга қайтади) ёки `cancelled`. Танловни қарор қилувчи қилади (5-савол).
  - қайтариш → `return_ready`. Бу мавжуд бўшатиш қирраси, курьер майдонлари ўша код билан тозаланади. `returnFailedCount` ва event ёзилади.
- **`continue`:** ҳолат ўзгармайди, белги ўчади.
- **Пул:** ўзгармайди. Курьер ҳақи ҳисобланмайди (`completed` бўлмайди).
- Мавжуд `handover_*` тасдиқ қадамлари ўзгармайди.

---

## 3. Агро / сут қабули (`agro_pickup_orders`)

### 3.1 Ҳозирги оқим (CONFIRMED)

- **Ҳолатлар:** `new → accepted → pickup_in_delivery → picked_up → completed | cancelled` (`index.js:20320-20327, 20432-20439`).
- **Тескари иқтисод:** мижоз сут **сотади**, AVA сотиб олади. `finalPrice` ни админ қўяди (`:20405-20406, 20478-20483`).
  Мижозга қандай тўланиши кодда йўқ (UNKNOWN).
- **Курьер:**
  - `courierClaimAgroPickup` (`:20546-20591`);
  - `courierMarkAgroPickupArrived` (`:20594-20649`);
  - `courierMarkAgroPickedUp` (`:20700-20739`).
- **Мижоз тасдиғи:** `handover_pickup` (`:20681-20697`).
- **Курьер ҳақи:** `picked_up` да `finalPrice` дан фоиз сифатида ҳисобланади. Админ `completed` қилганда қайта ҳисобланади (`:20664-20679, 20505-20531`). Пул ўтмайди.
- **Бекор қилиш ва бўшатиш:** админ `pickup_in_delivery → cancelled | accepted` (`:20437, 20485-20498`).

### 3.2 Жисмонан

Мижоз уйда йўқ ёки сут тайёр эмас. Ҳеч нарса олинмаган, пул ҳам йўқ.
**Ким ҳал қилади:** admin (харидор AVA; 1-савол).

### 3.3 Таклиф (PROPOSED)

- **`failed`:** `pickup_in_delivery → accepted` (навбатга қайтади) ёки `cancelled` (5-савол). Иккаласи ҳам мавжуд қирралар.
- **Пул:** йўқ. Курьер ҳақи ҳисобланмайди.

---

## 4. Йиғиб олиш вазифалари (`collection_tasks`)

### 4.1 Ҳозирги оқим (CONFIRMED)

- **Яратиш:** `adminCreateCollectionTask` → `status:'assigned'`, `courierId`, `createdBy: adminUid`. `sell_submissions` да `inCollection: true` бўлади (`index.js:8993-9108`).
- **Курьер:**
  - `courierMarkCollectionArrived` → `collecting` (`:9146-9206`). Транзакциясиз, `get`дан кейин `update`.
  - `courierFinalizeCollection` (`:9608-9674`): мижоз ҳамёнига `totalValue − cashGiven`, омборга `+qty`, `completed` (`:9333-9449`). AVA мижозга **тўлайди**.
- **Мижоз тасдиғи:** `finalize` (`:9548-9602`).
- **Курьер ҳақи:** `finalValue` дан фоиз, `courier_task_payouts` га (`:9359-9361, 9433-9434`).
- **Бекор қилиш ёки бўшатиш йўли умуман йўқ.** `collection_tasks` га ёзадиган код фақат шу учта функцияда (grep).
  Мижоз йўқ бўлса, вазифа `assigned` ёки `collecting` да абадий қолади. `sell_submissions.inCollection` ҳам `true` бўлиб қолади.

### 4.2 Жисмонан

Мижоз уйда йўқ ёки товарни бермади. Ҳеч нарса олинмаган, пул йўқ.
**Ким ҳал қилади:** admin (вазифани admin яратган, `createdBy`).

### 4.3 Таклиф (PROPOSED)

- **Янги якуний ҳолат:** `failed`, `failReason`, `deliveryFailedResolution`.
- **`sell_submissions/{id}`:** `inCollection: false`, `collectionTaskId` сақланади, `collectionFailedAt` қўшилади. Шунда админ янги вазифа яратади.
  `adminCreateCollectionTask` `collectionTaskId` бор бўлса рад этади (`:9014-9019`), шунинг учун бу шартни «вазифа `failed` бўлса — рухсат» деб юмшатиш керак.
- **Пул:** йўқ. Ҳамёнга ва омборга ҳеч нарса ёзилмайди.
- Йўл-йўлакай: `courierMarkCollectionArrived` ни транзакцияга ўтказиш (22-банд), чунки янги `failed` билан пойга бўлади.

---

## 5. Улгуржи (`wholesale_orders`) — relay LEG

### 5.1 Ҳозирги оқим (CONFIRMED)

- **Сотувчи бор:** `sellerId` (`wholesale_orders.js:462`). Етказиш relay LEG'лари орқали (`:23-29`). Ҳолатлар жадвали `functions_demand/core/wholesale_orders.js:61-93`.
- **«Етказилмади»нинг ўхшаши мавжуд:** `in_delivery → refused`. Чақиради — фақат курьер (охирги LEG ижрочиси, посилка унинг қўлида), **фақат карта** буюртмасида ва `cardPayment: awaiting` бўлганда (`functions_demand/api/wholesale_card.js:662-717`).
  Мижоз тасдиғи **йўқ**: курьер ўзи якунлайди.
  Ундан кейин:
  - `buyer_stats.cardRefusals += 1` (`:647-650`);
  - қайтариш жўнатмасининг пули сотувчи ҳамёнидан (`wholesale_orders.js:56-61`);
  - AVA улуши сотувчига қайтади, етказиш ҳақи курьерларда қолади (`:54-55`).
- **Ҳамёндан тўланган буюртмада** `refused` йўли йўқ: курьер учун фақат `CARD` (`wholesale_card.js:690`). Чиқиш йўллари: админ `in_delivery → cancelled` (кодда изоҳ бор: «курьер ҳали олмаган бўлса») ёки `lost`.

### 5.2 Жисмонан

Харидор (бизнес) эшикда йўқ ёки олмади. Посилка курьерда. Қайтиш алоҳида жўнатма бўлиб, сотувчига қайтади (карта йўлида шундай).
**Ким ҳал қилади:** сотувчи (`sellerId`) — бу CONFIRMED майдон.

### 5.3 Таклиф (PROPOSED)

- Улгуржи relay, escrow ва иккита codebase'га (demand + default) боғлиқ. `customer_confirm` эса фақат default codebase'да.
- Шунинг учун **алоҳида босқич** таклиф қилинади (6-савол):
  - `markWholesaleBuyerRefused` олдидан харидор тасдиғи (15 дақиқа) қўшилади, кейин қарор сотувчига ўтади;
  - ҳамёндан тўланган буюртма учун ҳам `refused → returning → returned` очилади. Бунда қайтиш ҳақини ким тўлаши ҳали ҳал қилинмаган (UNKNOWN).

---

## 6. Умумий архитектура (PROPOSED, энг кам ўзгариш)

Мавжуд кодни кўчириш эмас, бир марта умумлаштириш таклиф қилинади (4, 7-бандлар).

1. **`customer_confirm.js`:**
   - `MODULES += 'order'`;
   - `STEPS`: `carpet`, `agro`, `collection` ва `order` га `delivery_failed` қўшилади;
   - `MANDATORY_STEPS` ва `REJECTABLE_STEPS` шу модулларга кенгаяди.

   `order` handler'и `orders` коллекциясини `userPhone` бўйича ишлатади. Ресторан handler'и ҳам худди шундай ишлайди, шунинг учун `describe` фақат `type ∈ {bread, platform}` да жавоб қайтариши керак.
2. **Янги модуль `delivery_failed.js`** (ресторан кодидан умумлаштирилади):
   - `requestInTx(module, ...)` — белги ва `deliveryFailedEscalateAt`;
   - `continueInTx`;
   - битта scheduler `escalateDeliveryFailed` — ҳар дақиқада `orders` (ресторан бўлмаганлари), `carpet_wash_orders`, `agro_pickup_orders` ва `collection_tasks` бўйича бир майдонли оралиқ сўрови;
   - битта callable `resolveDeliveryFailed({module, id, decision})`.

   Модуль бўйича ваколат:

   | Модуль | Ким ҳал қилади |
   |---|---|
   | `order` | `seller`, `admin` ёки `superadmin` |
   | `carpet`, `agro`, `collection` | `admin` ёки `superadmin` |

   Admin қарори `admin_audit` га ёзилади.

   Ресторан йўли (`escalateRestaurantDeliveryFailed`, `restaurantResolveDeliveryFailed`) **ўзгармайди**. Кейинчалик уни ҳам шу модулга кўчириш мумкин, лекин бу алоҳида қарор (49-банд).
3. **Битта курьер callable'и:** `courierReportDeliveryFailed({module, id, leg?, reason})`. Мавжуд callable'лар ўзгармайди, шунинг учун эски APK'га таъсир йўқ.
   Сабаблар ресторандаги `FAIL_REASONS` (`restaurant_orders.js:161`) билан бир хил бўлади.
4. **Модуль бўйича якуний ядро (`failInTx`):**
   - нон ва бозор — бекор қилиш ядроси (1.3);
   - гилам ва агро — мавжуд бўшатиш ёки бекор қилиш қирралари;
   - йиғиш — янги `failed`.
5. **Хабарлар:** `notif_i18n` калитлари 3 тилда.

   | Кимга | Нима ҳақида |
   |---|---|
   | Мижоз | тасдиқлаш сўрови |
   | Қарор қилувчи | энди сиз ҳал қиласиз |
   | Курьер | якун ёки давом |
6. **Idempotency:** `wallet_idempotency/delivery_failed_{module}_{id}`. Нон ва бозорда пул қайтариш калити мавжуд `order_cancel_refund_{id}` бўлиб қолади.

**Server функциялари (энг кам тўплам):**
- янги: `courierReportDeliveryFailed`, `resolveDeliveryFailed`, `escalateDeliveryFailed`;
- ўзгаради: `customer_confirm.js` (`getCustomerPendingConfirmations` ва `customerConfirmHandover` номи ўзгармайди) ва `adminCreateCollectionTask` (`failed` дан кейин қайта яратиш);
- тавсия: `courierMarkCollectionArrived` — транзакцияга ўтказиш.

**UI экранлари (жонли lineage номлари):**

| Ким | Экран | Нима қўшилади |
|---|---|---|
| Курьер | `courier_order_tile.dart` (нон) | «Етказилмади» тугмаси |
| Курьер | `carpet_wash_courier_screen.dart` | «Етказилмади» тугмаси |
| Курьер | `agro_pickup_courier_screen.dart` | «Етказилмади» тугмаси |
| Курьер | `courier_collection_detail_screen.dart` | «Етказилмади» тугмаси |
| Курьер | `courier_controller.dart` | `isOrderFinalized`'га `fulfillmentStatus == 'delivery_failed'` |
| Мижоз | `customer_confirm` (мавжуд) | «Олмоқчиман» тугмаси (`canReject`, `decision:'reject'`). Жонлида йўқ — INFERRED |
| Админ | `admin_orders_screen.dart`, `carpet_wash_admin_screen.dart`, `agro_pickup_admin_screen.dart` ва йиғиш вазифалари экрани | «Ҳал қилинг» рўйхати ва 2 та тугма |
| Сотувчи | `seller_pos_screen.dart` ёки алоҳида рўйхат (нон) | «Ҳал қилинг» рўйхати ва 2 та тугма. Сотувчи иловаси қаерда кўрсатиши — UNKNOWN |

---

## 7. Хавфлар

**Эски APK:**
- Эски курьер иловасида «Етказилмади» тугмаси йўқ. Сервер ўзгаришидан зарар йўқ, лекин янги имконият APK чиқмагунча ишламайди. Ресторандан бошқа турларнинг ҳаммаси APK'га боғлиқ.
- Эски курьер иловасининг `isOrderFinalized` функцияси `delivery_failed` ни билмайди. Нон буюртмасида `status:'cancelled'` ҳам у ерда йўқ (`courier_controller.dart:93-98`).
  Шунинг учун маршрут **сервер томонида** сурилиши керак. Акс ҳолда эски иловада буюртма «жорий» бўлиб, тўлов тугмаси билан қолади. Тўлов эса `courierSubmitPayment` да рад этилади: `assertOrderActionable` ва `arrived first`, буни тест билан исботлаш керак.
- Эски мижоз иловаси янги `order` модулини умумий ёрлиқ билан кўрсатади (`customer_confirm.dart:95-106`, `generic`). «Олмоқчиман» тугмаси бўлмайди: эски мижоз фақат тасдиқлай олади ёки жавоб бермайди, ва 15 дақиқадан кейин сотувчи ёки админ ҳал қилади.
  Бу эга қарорига мос, лекин мижоз «рад»ни фақат янги иловада бера олади.
- Эски мижоз иловаси `customerConfirmHandover` ни `decision`сиз юборади, сервер буни `confirm` деб қабул қилади (`customer_confirm.js:323-325`). Бу хавфсиз.

**Firestore rules (~129 байт қолган):**
- Барча ёзувлар сервер callable'лари орқали бўлади, шунинг учун rules ўзгариши **керак эмас**. Изоҳ бўйича `orders` ва `carpet/agro/collection` клиент учун create/update ёпиқ (`customer_confirm.js:40-41`).
  Жонли rules бўйича текширилмади — INFERRED. Деплойдан олдин rules тести керак.
- Йиғишдаги янги `failed` ни мижоз ўқийди: мавжуд read қоидаси бор, майдон қўшилади, rules ўзгармайди.

**Индекслар:**
- Scheduler ҳар коллекцияда бир майдон бўйича оралиқ сўрови ишлатади (ресторандаги каби), автоматик индекс етади.
- Репода бу майдонлар учун `fieldOverrides` йўқ (`firestore.indexes.json:2662-2711`). Жонлида exemption борми — UNKNOWN.
- `--force` ишлатилмайди (prod'да қўлда яратилган индекслар бор).

**Нарх:** битта scheduler ҳар дақиқада 4 та бўш сўров юборади ≈ 5 760 ўқиш/кун. Бу арзон.

**Concurrency:** «етказилмади» сўрови, мижоз тасдиғи, сотувчи қарори ва админ `adminSet*Status` бир буюртмада бир вақтда келиши мумкин. Ҳаммаси битта транзакцияда ва «биринчи қарор ютади» тамойилида бўлиши керак (ресторандаги `withContention` намунаси).
`adminSetCarpetWashStatus` ва `adminSetAgroPickupStatus` белгини аллақачон тозалайди (`:19854`, `:20500`). Улар ресторандаги `failedPendingClear` каби муддат майдонини ҳам тозалаши керак.

**Деплой:**
- `customer_confirm.js` ва курьер функциялари `deploy-biz-fns` пинида йўқ. Деплойни фақат шу lineage'дан қилиш керак (feedback: pin ≠ live).
- Функциялар номи бўйича деплой қилинади, rules алоҳида.

---

## 8. Эгага саволлар (ҳар бирида тавсия этилган жавоб)

1. **Нон ва бозорда ким ҳал қилади?** Буюртмада сотувчи майдони йўқ. Тавсия: `seller` роли ёки admin (AVA новвойхонаси ва омбори ходими).
2. **Гилам, сут ва йиғишда ким ҳал қилади?** Тавсия: admin, чунки бу турларда сотувчи AVA'нинг ўзи ва эгаси майдони йўқ.
3. **Нон ёки бозор етказилмаса, мижозга нима қайтади?** Тавсия: ҳамёндан ечилгани тўлиқ, `platform` даги `deliveryFee` ҳам. Мижоз ҳеч нарса олмаган.
4. **Мижозга жарима (strike) борми?** Тавсия: 1-босқичда фақат ҳисоблагич ёзилади. «Фақат олдиндан тўлов» чеклови ресторандагидек (2 марта ёки 30 кун) кейин, алоҳида қарор билан.
5. **Гилам ёки сутни олиб кетиш бўлмаса, қарор қилувчининг «етказилмади»си нимага олиб келади?** Тавсия: навбатга қайтиш (`pickup_ready` / `accepted`), бекор қилиш — алоҳида тугма.
   Гилам қайтарилмаса, у цехга қайтади ва `return_ready` бўлади (бекор қилинмайди).
6. **Улгуржи шу ишга киритиладими?** Тавсия: йўқ, алоҳида босқич. У ерда курьернинг карта бўйича «рад этди» йўли аллақачон бор, ҳамёндаги буюртма учун қайтиш ҳақи масаласи эса очиқ.
7. **Курьерга «бориб келдим» учун ҳақ тўланадими?** Тавсия: 1-босқичда йўқ, ресторан билан бир хил. Нон ва бозорда курьер ҳақи тизимда умуман йўқ (UNKNOWN).
8. **Нон эгасига қайтганини ким тасдиқлайди?** Тавсия: 1-босқичда фақат event ёзилади. Сотувчининг «қабул қилдим» тугмаси 2-босқичда.
9. **15 дақиқа барча турлар учун битта созламами?** Тавсия: ҳа, мавжуд `failedTimeoutMin`.
10. **Нон буюртмаси бекор бўлганда омбор (`soldToday`) тикланадими?** Тавсия: ҳа, мавжуд бекор қилиш ядроси билан бир хил.

---

## 9. Эга қарорлари (2026-10-31)

**Манба:** эга, 2026-10-31 — «тавсияларга розиман» (8-бўлимдаги ҳамма тавсия этилган жавоблар қабул қилинди).
**Ҳолат:** CONFIRMED (эга). Амалга ошириш: `functions/delivery_failed.js` (сервер) ва курьер/мижоз/сотувчи/админ UI.

| № | Нима (what) | Нега (why) | Таъсир (impact) |
|---|---|---|---|
| 1 | Нон ва бозор (`orders`, bread/platform): мижоз 15 дақиқада жавоб бермаса **`seller` роли** ҳал қилади, захира — admin/superadmin | Буюртмада сотувчи майдони йўқ; нон ва бозор сотувчиси — AVA ходими | `resolveDeliveryFailed` рухсати: seller, admin, superadmin; қарор `admin_audit`га |
| 2 | Гилам, сут (агро), йиғиш: **admin** ҳал қилади | Бу турларда сотувчи AVA'нинг ўзи, эгаси майдони йўқ | Рухсат: admin, superadmin; сотувчига кўринмайди |
| 3 | Нон/бозор етказилмаса ҳамёндан ечилган қисм **тўлиқ** қайтади, `deliveryFee` ҳам | Мижоз ҳеч нарса олмаган | Мавжуд бекор қилиш ядроси (`balanceApplied`, калит `order_cancel_refund_{id}`) |
| 4 | Мижозга strike: **фақат ҳисоблагич**, «фақат олдиндан тўлов» чеклови йўқ | 1-босқичда жазо эмас, кузатиш | `customer_delivery_stats/{uid}` (customer_absent / customer_refused); ресторан `restaurant_customer_stats` ўзгармайди |
| 5 | Гилам/сут олиб кетиш бўлмаса — **навбатга қайтиш** (`pickup_ready` / `accepted`); гилам қайтарилмаса — **цехга** (`return_ready`). Бекор қилиш — алоҳида admin амали | Мижоз буюртмаси сақланади, гилам мижозники | Мавжуд release қирралари (`CARPET_RELEASE_EDGES`, B1) ишлатилади |
| 6 | Улгуржи (`wholesale_orders`) — **ҳозир эмас** | Relay, escrow, икки codebase; алоҳида босқич | Ўзгармайди |
| 7 | «Бориб келдим» учун курьерга **ҳақ йўқ** (1-босқич) | Ресторан билан бир хил | `courier_task_payouts` ёзилмайди |
| 8 | Товар сотувчига қайтгани — **фақат ҳодиса** (сотувчининг «қабул қилдим» тугмаси йўқ) | 1-босқичда минимал | `delivery_failed_events` (`goods_return_to_seller`, гиламда `goods_return_to_workshop`) |
| 9 | Ҳамма тур учун **битта муддат** — мавжуд `server_config/customer_confirm.failedTimeoutMin` (стандарт 15) | Битта созлама (7-қоида) | Админ ўзгартиради (1–240) |
| 10 | Нон бекор бўлганда омбор (`soldToday`) **тикланади** | Мавжуд бекор қилиш ядроси билан бир хил | `prepareOrderCancelInTx` / `commitOrderCancelInTx` |

Қўшимча (топшириқ, 2026-10-31): нон буюртмаси мижоз йўқлигида `in_delivery`да қотиб қолмайди (шу хусусият чиқиш йўли); йиғиш вазифаси учун `failed` якуни ва `sell_submissions.inCollection` бўшатилади (`adminCreateCollectionTask` боғлиқ вазифа `failed` бўлса янгисини очади).

**Амалга ошириш тафсилоти (PROPOSED, кичик):** курьер «етказилмади» деганда нон буюртмаси маршрут охирига сурилади (курьер кейинги манзилга ўтади); якунда сервер уни маршрутдан чиқаради (`currentIndex` тузатилади, бекат қолмаса маршрут ёпилади). Эски APK `isOrderFinalized`га боғлиқ эмас.