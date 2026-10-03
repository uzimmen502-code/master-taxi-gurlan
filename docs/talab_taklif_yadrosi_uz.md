# AVA: ТАЛАБ → ТАКЛИФ ядроси — аудит, баҳо ва жорий этиш вазифалари

Ҳужжат санаси: 2026-10-02 · Манба концепция: «AVA: ТАЛАБ → ТАКЛИФ ядроси архитектураси» (Oct 2, 2026)
Ушбу ҳужжат концепцияни **алмаштирмайди**, унинг устига ўтиради: аудит натижаси, тузатишлар ва вазифалар.

---

## 1. Умумий баҳо

**Архитектура йўналиши тўғри.** Битта ядро + модул adapter'лари, серверда matching, matching'ни push'дан ажратиш,
проекция орқали махфийлик, trust'нинг фақат серверда бўлиши — буларнинг ҳаммаси тўғри қарорлар ва улар
кейинроқ қайта ёзишни талаб қилмайди. Концепциянинг энг кучли жойлари:

- `demand_matches` проекцияси (таклифчи `demands` ҳужжатини ҳеч қачон кўрмайди) — махфийлик ва Firestore
  чекловининг ҳар иккисини бир йўла ҳал қилади;
- «кўриниш» ва «push»ни ажратиш — концепциянинг энг муҳим ғояси;
- strangler pattern + feature flag + shadow mode — мавжуд production'ни сақлайди;
- lifecycle'дан `matching.state`ни ажратиш.

**Лекин концепция репонинг ҳақиқий ҳолатини текширмаган** (ўзи ҳам «0-қадам: аудит» деб ёзган). Аудит
қилинди — натижада концепциянинг **8 та асосий техник тахмини нотўғри** чиқди, **4 та коллекция номи
production билан тўқнашади** (булардан биттаси — `trips` — жорий қилинса таксини бузади), ва **3 та
янги инфратузилма** (Cloud Tasks, Realtime Database, OSRM) ҳақиқатда керакмас ёки кейинга қолдирилиши мумкин.

Бундан ташқари бизнес томонида иккита очиқ тешик бор: **чекланмаган жавобгарлик** (`declaredValue`ни
юборувчи ўзи ёзади, курьер эса чекланмаган пул тўлайди) ва **Google Play талаблари** (паспорт нусхаси +
фон жойлашуви — иккаласи ҳам Data Safety ва Permissions декларациясини янгилашни талаб қилади, акс ҳолда
илова Play'дан олиб ташланади).

**Хулоса:** концепцияни қайта ёзиш керак эмас. Қуйидаги 22 та тузатиш киритилса, жорий этишга тайёр.
Тузатишларнинг аксарияти ишни **камайтиради**, кўпайтирмайди.

---

## 2. 0-қадам: аудит натижаси (код бўйича текширилган)

### 2.1 Репонинг ҳақиқий ҳолати

| Нима | Концепция тахмини | Ҳақиқат (текширилди) |
|---|---|---|
| Cloud Functions тили | TypeScript, `functions/src/demand/**` | Оддий JavaScript (CommonJS). `functions/index.js` — **690 КБ, 16 624 қатор**, build қадами йўқ |
| Функциялар сони | — | 180+ exported функция, ҳаммаси `default` codebase'да; `firebase.json`да иккинчи codebase (`y`) аллақачон бор |
| SDK | — | `firebase-functions@4.9.0` (gen1 + gen2 аралаш), `firebase-admin@11.11.1`, Node 20 |
| Шахсни аниқлаш | `request.auth.uid` | **`request.auth.token.phone_number` → рақамлар**. `users/{998901234567}`. Rules'да `isOwner()`, `phoneDocIdsMatch()` ёрдамчилари. **9 ва 12 хонали иккита шакл бир вақтда ишлайди** |
| Веб фойдаланувчи | — | Anonymous Auth + `users/{998...}` — **`token.phone_number` йўқ** |
| Cloud Tasks | `dispatchWave`, `expireDemand`, `runMatching` учун асос | **Лойиҳада умуман ишлатилмайди.** Фақат `pubsub.schedule` (3 жойда). Cloud Tasks API ёқилмаган |
| Region | — | Ҳеч қайси функцияда `region()` йўқ → ҳаммаси `us-central1` |
| Realtime Database | Жонли кузатув учун асосий база | **`firebase.json`да `database` блоки йўқ, `pubspec.yaml`да `firebase_database` йўқ.** Яъни: янги инстанс + янги SDK + янги rules файли |
| Remote Config | Intent Router луғати учун | **`firebase_remote_config` dependency йўқ.** Лекин `settings/{app,courier,prices,...}` ҳужжатлари аллақачон конфиг сифатида ишлатилади |
| Routing | OSRM ўз серверида + Google | **`getDirections` callable аллақачон бор** — Google Directions + Secret Manager (`DIRECTIONS_API_KEY`) |
| Geohash | `geofire-common` керак | **Аллақачон бор:** `functions/geo_hash.js` + `lib/utils/geo_hash.dart` (бит-бабит бир хил, тестланган) |
| Қидирув | Typesense/Meilisearch керак | **`search_index` коллекцияси ишлаб турибди** (токен индекс, кирилл+лотин, `onSearchIndex*Write` триггерлари, `home_global_search.dart`) |
| Push | Data message, collapseKey, action тугма, кўп қурилма | `notifications` ҳужжати → `onNotificationCreate` → **телефон бўйича БИТТА токен** (`users.fcmToken` — массив эмас, стринг). `notification`+`data` аралаш (OS ўзи кўрсатади), collapseKey йўқ |
| Пул / жарима | Янги `penalties` + «баланс» | **Аллақачон бор:** `wallet_ledger`, `wallet_idempotency`, `settlement_ledger.js`, манфий float = қарз, `blockedReason: 'deferred_debt'`, `settlementDeferredWatch` |
| LLM | Gemini Flash ёки Claude Haiku — янги вендор | **Аллақачон бор:** `assistant_chat.js` + `assistant_prompt.js` (OpenAI, Secret Manager'да калит) |
| Аналитика | Firestore → BigQuery экспорти | BigQuery экспорти йўқ. `analytics_pipeline.js` + `user_engagement_index` + `analytics_backfill_jobs` — ўз қувури |
| Dart codegen | JSON Schema'дан генерация | **`build_runner`/`json_serializable`/`freezed` — pubspec'да йўқ.** Моделлар қўлда ёзилган |
| Харита SDK | «аудитда аниқланади» | **`google_maps_flutter` 2.10** (+ Android/iOS имплементациялари) |
| Локализация | — | `assets/lang/{uz_Cyrl,ru,uz_Latn}.json` — ҳар бири ~213 КБ. **Матн қўшилса учаласига** |
| Firestore индекслар | — | 119 та композит индекс аллақачон бор |
| iOS | — | App Store'да ҳали нашр қилинмаган (В-6) |

### 2.2 КРИТИК: коллекция номлари production билан тўқнашади

| Концепциядаги ном | Муаммо | Ечим |
|---|---|---|
| **`trips/{tripId}`** | `trips` — **маҳаллий такси сафарлари**, ишлаб турган коллекция (`trips where status=='pending'/'searching'`, `expirePendingTrips`, `onTripUpdate`, `completeLocalTrip`). Устига ёзилса такси бузилади | **`provider_trips`** |
| **`reports/{reportId}`** | `reports` — **касса/ҳисобот даврлари** (`openSettlement`, `closePeriod`, `getMoneyControlSnapshot`) + EV шикоятлари | Мавжуд **`complaints`** коллекциясидан фойдаланиш (аллақачон шикоят учун) |
| `couriers/{uid}` (назарда тутилган) | `couriers` — **платформа етказиб бериш курьери**: `isOnline`, `fcmToken`, `delivery_routes`, `collection_tasks`, пул йиғиш. Посилка курьери бу эмас | `couriers`га тегмаслик. Посилка имконияти → `provider_capabilities/{uid}_courier` |
| camelCase номлар | Репо конвенцияси — snake_case (`intercity_bookings`, `yuk_listings`, `search_index`, `wallet_ledger`) | Ҳаммасини snake_case'га ўтказиш (2.3-жадвал) |

### 2.3 Якуний коллекция номлари (тасдиқланган)

| Концепция | Жорий этиладиган ном |
|---|---|
| `demands` | `demands` ✔ |
| `demands/{id}/offers` | `demands/{id}/offers` ✔ |
| `demandMatches` | `demand_matches` |
| `providerCapabilities` | `provider_capabilities` |
| `providerStats` | `provider_stats` |
| `providerPresence` | `provider_presence` |
| `trips` | **`provider_trips`** |
| `trustEvents` | `trust_events` |
| `ratings` | `demand_ratings` |
| `notificationLog` | `demand_push_log` |
| `taxonomy` | `taxonomy` ✔ |
| `moduleConfig` | `module_config` |
| `reports` | **`complaints`** (мавжуд) |
| `penalties` | `demand_penalties` (**пул эса `wallet_ledger`да**) |
| `courierDocuments` | `courier_documents` |
| `trackingHistory` | `demand_tracking_history` |
| `tracking` (RTDB) | `demand_tracking` (**Firestore**, 2.4-Т-6 га қаранг) |
| `tariffs` | `module_tariffs` |

**Ҳужжат калити:** барча `ownerId`, `providerId`, `driverId` майдонлари **12 хонали канон шакл** (`998XXXXXXXXX`).
Сервер ёзишдан олдин нормаллаштиради. 9 хонали шакл базага ёзилмайди.

---

## 3. Тузатишлар (концепцияга киритилади)

### Т-1. Янги ядро — алоҳида functions codebase'да, JavaScript'да

Концепция `functions/src/demand/**.ts` деб ёзган. Репода TypeScript йўқ, `index.js` эса 690 КБ.
Янги кодни шу монолитга қўшиш — ҳар деплойда 180+ функцияга таъсир қилиш демак.

**Ечим:** `firebase.json`га учинчи codebase қўшилади:

```
functions_demand/        ← codebase: "demand", оддий JS (CommonJS), Node 20
├── core/        lifecycle.js, state_machine.js, schemas/*.json (JSON Schema)
├── matching/    orchestrator.js, scoring.js, fairness.js, dedupe.js
├── sources/     active_listings.js, past_activity.js, capabilities.js,
│                presence_geo.js, provider_trips.js
├── adapters/    service.js, carpet_wash.js, courier.js, intercity_taxi.js, ...
├── notify/      policy.js, fcm.js, waves.js
├── trust/       events.js, compute.js
├── geo/         (мавжуд `functions/geo_hash.js` reuse қилинади)
├── api/         create_demand.js, submit_offer.js, accept.js, cancel.js ...
└── index.js
```

- Деплой: `firebase deploy --only functions:demand` — **мавжуд функцияларга тегмайди**. Бу codebase даражасидаги kill switch.
- Тил: JS + JSDoc `@typedef`. TypeScript қўшиш — алоҳида қарор, ядро учун шарт эмас.
- Валидация: JSON Schema (`ajv`) — схема файллари ҳам сервер, ҳам Dart тести учун ягона манба.
- `functions/geo_hash.js` янги codebase'га нусхаланмайди, `require`+symlink эмас — **файл кўчирилади ва иккала жойда
  бир хил қолиши тест билан текширилади** (`test/geo_hash_parity.test.js`).

### Т-2. Security rules'ни репонинг шахс моделига мослаштириш

Концепциядаги барча rules нотўғри: `request.auth.uid` бу лойиҳада фойдаланувчи ID эмас.

```javascript
// НОТЎҒРИ (концепцияда):
allow read: if request.auth.uid == resource.data.ownerId;

// ТЎҒРИ (репо ёрдамчилари билан):
allow read: if isOwner(resource.data.ownerId);
```

Қўшимча тузатишлар:

1. **`demand_matches` калити.** `{demandId}_{providerId}` калити rules'да парчалаб текширишга тўғри келмайди
   (9/12 хонали иккилик сабабли). Шунинг учун `providerId` **майдон сифатида** ҳам сақланади ва
   қоида майдон бўйича текширади:
   ```javascript
   match /demand_matches/{key} {
     allow read: if isOwner(resource.data.providerId);
     allow write: if false;
   }
   ```
   Клиент ҳар доим `where('providerId','==', myCanonicalId)` билан сўров беради (акс ҳолда rules сўровни рад этади).

2. **`offers` учун `get()` олиб ташланади.** Концепцияда ҳар бир offer ўқилганда ота `demands` ҳужжати
   `get()` қилинади. Буни `ownerId`ни offer ҳужжатига денормаллаштириш билан алмаштирамиз:
   ```javascript
   match /demands/{id}/offers/{providerId} {
     allow read: if isOwner(resource.data.providerId) || isOwner(resource.data.ownerId);
     allow write: if false;
   }
   ```

3. **`provider_presence` ўқиш.** Концепция `allow read: if false` деган — лекин курьернинг ўзи ва админ
   панели ўз ҳолатини кўриши керак. `allow read: if isOwner(uid) || isAdmin();`

4. **Веб (Anonymous Auth) фойдаланувчилари** `token.phone_number`га эга эмас → **провайдер томони P0'да
   фақат мобил илова**. Веб админ панели `isAdmin()` орқали ишлайди.

5. Қоидалар **алоҳида деплой** қилинади (`firebase deploy --only firestore:rules`) — функциялар билан
   бирга эмас (2026-09-27 ҳодисаси: ~5 соат бронь узилиши).

### Т-3. Realtime Database **жорий этилмайди** — жонли кузатув Firestore'да

Концепция «Firestore ҳар ёзиш ва тинглаш учун пул олади, RTDB арзонроқ» деган. Ҳақиқий ҳисоб:

- Битта буюртма: 30 дақиқа × ҳар 8 сонияда = ~225 ёзиш; 2 тинглаш (юборувчи + қабул қилувчи) = ~450 ўқиш.
- Кунда 200 буюртма: 45 000 ёзиш + 90 000 ўқиш ≈ **$0,13/кун** (Firestore нархи: ёзиш $0,18/100к, ўқиш $0,06/100к).
- RTDB қўшиш нархи: янги инстанс + `firebase_database` SDK (илова ҳажми) + янги rules файли + iOS/Android pod
  янгилаш + эмулятор ва тестларни қайта созлаш + иккинчи база учун мониторинг.

**Қарор:** `demand_tracking/{demandId}` — Firestore'да, битта ҳужжат, 8–10 сонияда update (шаҳарлараро: 30–60 с).
Мавжуд rules ва SDK ишлатилади, янги инфратузилма йўқ. **Кунлик фаол кузатилаётган буюртма 2000'дан ошса**
RTDB'га кўчириш алоҳида вазифа сифатида очилади (интерфейс шу тарзда ёзилади: `TrackingSink` абстракцияси).

### Т-4. OSRM **жорий этилмайди** — тўлқин ETA'си гео-ҳисоб билан, мижоз ETA'си мавжуд `getDirections` билан

OSRM ўз серверида: Cloud Run/VM + OSM маълумотини янгилаб туриш + мониторинг + ишдан чиқса dispatch тўхтайди.
Урганч ҳажмида бу керак эмас.

**Ечим (уч поғона):**
1. **Тўлқин фильтри:** geohash префикс (мавжуд `geo_hash.js`) → haversine масофа × йўл коэффициенти (1,35)
   → транспорт тури тезлиги бўйича ETA. Ташқи сўров **нол**.
2. **Мижозга кўринадиган ETA ва маршрут чизиғи:** мавжуд **`getDirections`** callable (Google Directions,
   Secret Manager'да калит) — фақат **қабул қилингандан кейин**, битта буюртмага 1–3 сўров.
3. OSRM фақат shadow mode ўлчови «тўлқин сифати ёмон» деб кўрсатса қўшилади (алоҳида вазифа, P2+).

### Т-5. Cloud Tasks фақат **тўлқинлар** учун. Муддат — мавжуд sweeper намунаси билан

Концепция 4 жойда Cloud Tasks ишлатади. Лойиҳада Cloud Tasks умуман йўқ (API ёқилмаган).

- `expireDemand` → **`pubsub.schedule('every 5 minutes')` sweeper**, худди мавжуд `expirePendingTrips` ва
  `releaseStaleReservations` каби. Илова рўйхатларда `expiresAt > now` фильтрини ҳам ишлатади → кечикиш кўринмайди.
- `runMatching` → `createDemand` ичида **синхрон** (P0'да номзодлар сони кичик: <500). 200 мс қўшимча
  кечикиш — фойдаланувчи учун сезилмайди, битта функция камаяди.
- `dispatchWave` (20 сониялик аниқлик) → **фақат бу** Cloud Tasks'ни талаб қилади, у ҳам **P2**'да.
  `firebase-functions@4.9.0`да `firebase-functions/v2/tasks` (`onTaskDispatched`) ва
  `firebase-admin@11`да `getFunctions().taskQueue().enqueue()` бор — SDK янгилаш керак эмас.
  P2 бошида: Cloud Tasks API ёқиш + `demand-waves` навбати + IAM (`cloudtasks.enqueuer`).
- **Region:** янги codebase Firestore билан бир регионда бўлиши шарт (мавжуд функциялар `us-central1`).
  Деплойдан олдин Firestore локацияси текширилади; тўлқинлар учун `minInstances: 1` (совуқ старт 20 сониялик
  тўлқинни бузади).

### Т-6. Push қувури: кўп қурилма + collapse + платформа ҳақиқати

Мавжуд: `users.fcmToken` — **битта стринг**. Иккинчи қурилмага кирган фойдаланувчи push олмайди.

1. **`users/{id}/fcm_tokens/{token}`** субколлекцияси: `platform`, `appVersion`, `updatedAt`.
   `messaging/registration-token-not-registered` хатосида токен ўчирилади. Эски `fcmToken` майдони
   мослик учун ёзилишда давом этади (мавжуд 180+ функция уни ишлатади) — миграция **ядро учун** қилинади,
   бутун илова учун эмас.
2. **Collapse:** Android `android.collapseKey = demandId`, iOS `apns.headers['apns-collapse-id'] = demandId`.
3. **iOS ҳақиқати:** фақат `data` хабар илова ўлдирилганда **кўринмайди**. Шунинг учун dispatch push:
   `notification` + `data` + `apns.payload.aps.category = 'DEMAND_DISPATCH'`.
   Action тугма: Android'да `flutter_local_notifications` (17.2.2 — аллақачон бор) `AndroidNotificationAction`,
   iOS'да `UNNotificationCategory`. **iOS'да илова нашр қилинмагани учун (В-6) action тугмалар Android-only P2.**
   P0'да фақат тап → deep link (`ava://demand/{id}`).
4. **Янги `notifications` ҳужжати ёзилмайди.** Ядронинг inbox'и — `demand_matches`. Иккита inbox бўлмасин.
   Push фақат `admin.messaging().sendEach()` орқали, `demand_push_log/{demandId}_{providerId}` idempotency билан.
5. **Тинч соатлар Asia/Tashkent бўйича** (функциялар UTC'да ишлайди — `timezone` пакети Dart'да бор,
   серверда қўлда offset +05:00).

### Т-7. Push лимити: концепциядаги «кунлик лимит йўқ» хавфли

Концепция: quote режимида «ҳар бир янги мос талаб учун битта push, кунлик лимит йўқ». Урганч ҳажмида кенг
имкониятли сотувчи кунда 20–40 push олиши мумкин → push ўчириш ёки иловани ўчириш. Концепциянинг ўзи буни
хавф сифатида тан олади, лекин ҳимоя қўймайди.

**Ечим (кўринишга тегмайди):**

| Режим | Push қоидаси |
|---|---|
| dispatch | Лимитсиз, юқори приоритет (битта курьер керак — ҳар сония муҳим) |
| quote | **Соатда 5 та, кунда 20 та** push. Лимитдан ошганлар **битта дайжестга** йиғилади: «Сизга мос 7 та янги талаб» (3 соатда бир) |
| alert | Кунда 10 та |
| Тинч соатлар | 23:00–07:00 (Asia/Tashkent) — dispatch'дан ташқари ҳаммаси тўхтайди, эрталаб дайжест |

Қийматлар `module_config/{module}_{regionId}`да. **Inbox (`demand_matches`) лимитсиз** — «кутиш йўқ»
қоидаси бузилмайди: барча мос таклифчи талабни дарҳол кўради.

### Т-8. `matchedCount` зиддияти

Концепция: харидор `matchedCount: 37`ни кўради, лекин UI'да «30+» кўрсатилади — «рақобатчи сотувчилар
сонини йиғмасин» деб. Аммо `demands` ҳужжатини **харидорнинг ўзи ўқийди** → аниқ рақам унда бор.

**Ечим:** `demands.matching` ичида фақат `matchedBucket: "30+"` (0, 1-2, 3-5, 6-10, 10+, 30+, 100+).
Аниқ рақам `demands/{id}/private/stats` ҳужжатида — `allow read: if false`, фақат сервер ва аналитика.

### Т-9. Контакт очилиши икки поғонага бўлинади

Концепция: қабул қилингач иккала томоннинг телефони ва аниқ манзил очилади. Бу «манзил йиғиш» ҳужумига
очиқ: курьер қабул қилади, манзил ва телефонларни ўқийди, келмайди.

| Босқич | Нима очилади |
|---|---|
| `accepted` | Юборувчининг телефони + **олиш** манзили |
| `in_progress` (посилка олинди, расм тушди) | Қабул қилувчининг телефони + **етказиш** манзили |

Қўшимча: бир вақтда қабул қилиш лимити (янги курьер: 2), no-show → энг кучли trust таъсири.

### Т-10. Жавобгарлик чекланади (`declaredValue` ҳужуми)

Концепция: «зарар миқдори формадаги Посилка қийматидан аниқланади». Қиймат — **юборувчи ёзган рақам**,
текширилмайди. Ёмон ниятли юборувчи 50 млн деб ёзиб, курьердан талаб қилиши мумкин.

**Ечим — жавобгарлик шифти (`liabilityCap`):**

| Курьер ҳолати | Максимал `declaredValue` |
|---|---|
| Паспорт тасдиқланмаган ёки trust < 40 | 300 000 сўм |
| Паспорт тасдиқланган | 1 000 000 сўм |
| Паспорт + ўзини ўзи банд қилиш + ≥20 бажарилган буюртма | 3 000 000 сўм |

- Форма юборилганда юборувчи шифтни **кўради ва тасдиқлайди**; қиймат шифтдан юқори бўлса — талаб
  фақат юқори поғонали курьерларга кетади ёки юборувчи қийматни пасайтиради.
- Шифтдан юқори посилка (қимматбаҳо) — 1-версияда **қабул қилинмайди**.
- Жарима ва зарар **ҳуқуқий асос** талаб қилади: илова ичида «Курьер шартлари» оферта матни + бир марталик
  тасдиқ (checkbox) + `courier_terms_accepted_at`. Бусиз пул ундириш мумкин эмас (13.P2 вазифаси).

### Т-11. Жарима пули — мавжуд wallet'да, янги «баланс» ясалмайди

Репода аллақачон: `wallet_ledger`, `wallet_idempotency`, манфий баланс = қарз, `blockedReason: 'deferred_debt'`,
`settlementDeferredWatch` (муддати ўтган қарзларни белгилайди).

**Ечим:** `demand_penalties/{penaltyId}` — фақат **ҳолат ҳужжати** (сабаб, босқич, миқдор, ҳолат, далиллар).
Пул ҳаракати — **`wallet_ledger`** ёзуви, мавжуд idempotency калити билан. Блоклаш — мавжуд `blockedReason`
механизми. Иккита пул ҳақиқати бўлмайди.

### Т-12. `createDemand` idempotency

Икки марта тап ёки тармоқ қайта уриниши икки талаб яратади. Репода намуна бор (`wallet_idempotency`).

`createDemand(clientRequestId, ...)` — `uuid` пакети pubspec'да бор. Сервер 10 дақиқа ичидаги бир хил
`clientRequestId`ни рад этмайди, аввалги `demandId`ни қайтаради.

### Т-13. Intent Router луғати — Remote Config эмас, мавжуд конфиг намунаси

`firebase_remote_config` dependency йўқ. Фақат калит сўзлар рўйхати учун янги SDK қўшиш оқланмайди.

**Ечим:** `module_config/intent_keywords` Firestore ҳужжати + иловада bundled fallback
(`assets/data/intent_keywords.json`) + `SharedPreferences` кеши (илова аллақачон `settings/app`ни шу тарзда ўқийди).
Оффлайн ва биринчи ишга туширишда bundled нусхa ишлайди.

**Диққат:** калит сўзлар — UI матни эмас, учта локал файлга тегмайди. Лекин хизмат карточкасининг матни
(«Курьер хизмати — Давом этиш») — UI матни → `assets/lang/{uz_Cyrl,uz_Latn,ru}.json` **учаласига** қўшилади.

### Т-14. Қидирув: Typesense/Meilisearch P0'да керак эмас

`search_index` коллекцияси ишлаб турибди (токен индекс, кирилл+лотин нормализацияси, `onSearchIndex*Write`
триггерлари, `home_global_search.dart`). Intent Router'нинг иши — матнни **хизмат сўровимi** деб ажратиш,
тўлиқ матнли қидирув эмас.

**Ечим:** P0–P1'да мавжуд `search_index` ишлатилади. Typesense/Meilisearch — P3, «эълон матни бўйича
семантик мослик» талаб қилинганда, алоҳида қарор билан.

### Т-15. LLM: янги вендор эмас, мавжуд assistant қувури

`assistant_chat.js` + `assistant_prompt.js` аллақачон OpenAI'ни Secret Manager калити билан чақиради
(В-1 бўйича). Gemini/Claude қўшиш = янги ҳисоб, янги калит, янги мониторинг.

**Ечим:** `parseIntent` — `functions_demand/api/parse_intent.js`, мавжуд assistant клиенти ва секрети
қайта ишлатилади, промпт эса алоҳида (қисқа, структурали JSON чиқариш). Провайдер интерфейс ортида қолади.
Модел солиштириш (200 реал сўров) — P1'нинг **ўлчов** вазифаси, инфратузилма вазифаси эмас.

### Т-16. Dart codegen жорий этилмайди

`build_runner`, `json_serializable`, `freezed` — pubspec'да йўқ. 1.0.32 версиядаги production иловага
codegen қувурини киритиш — алоҳида катта иш.

**Ечим:** моделлар қўлда ёзилади (репо услуби), **паритет тести** билан ҳимояланади:
`functions_demand/core/schemas/*.json` + `test/fixtures/demand_attributes/*.json` →
(а) серверда `ajv` билан валид, (б) Dart тестида моделга parse бўлади ва қайта serialize қилинганда бир хил.
Схема ўзгарса, иккала тест синади.

### Т-17. Пилот модулни ўзгартириш

Концепция P0 пилоти: **Гилам ювиш** + **Эълон ва хизмат**. Аудит: гилам ювишнинг тўлиқ оқими аллақачон
ишлайди (`placeCarpetWashOrder`, `courierClaimCarpetPickup`, `courierMarkCarpetDelivered`,
`adminSetCarpetWashStatus`). Уни ядрога кўчириш = dual-write + фойдаланувчига **нол янги фойда** + регрессия хавфи.

**Ечим:** P0 пилоти — **«Хизмат сўрови» (уста, сантехник, электрик, мой алмаштириш устаси)**: бугун бу оқим
**умуман йўқ** (фойдаланувчилар `ads`га эълон беради ва кутади). Яъни:

- dual-write йўқ, миграция йўқ, бузиладиган production йўқ;
- режим — энг оддийси (`quote`), географик фильтр + capabilities, тўлқин йўқ, trips йўқ, тўлов йўқ;
- фойдаланувчи учун аниқ янги қиймат: «Уста чақириш» → 10 дақиқада 3 та таклиф.

Гилам ювиш ва мой алмаштириш ядрога **P1'да**, ўз оқими ишлаб тургани ҳолда, adapter орқали уланади.

### Т-18. Trust ва score — аниқ бошланғич рақамлар

Концепцияда формула тасвирланган, рақам йўқ → жорий этиб бўлмайди. Бошланғич қийматлар (`module_config`да,
shadow mode'дан кейин созланади):

```
trustScore: 0..100, янги таклифчи = 50
  dispatch 1-тўлқинга кириш:        trust >= 40
  matching'дан вақтинча чиқариш:    trust < 20  (+ модераторга хабар)
  trust_events вазнлари: completed +2, кеч бекор қилиш -5, no-show -15,
                         тасдиқланган шикоят -20, баҳо 5★ +1, баҳо ≤2★ -3
  сўниш: 90 кундан кейин воқеа вазни ×0,5; 180 кундан кейин ×0,25

score (0..1):
  base = 0.40·categoryMatch + 0.40·proximity + 0.20·sourceStrength
    proximity: dispatch → 1 - min(etaMin,30)/30 ; quote → 1 - min(detourKm,20)/20
    sourceStrength: манбалар сони (1→0.4, 2→0.7, 3+→1.0)
  equalizer (фақат base фарқи ≤ 0.05 ёки ETA фарқи ≤ 2 дақиқа бўлганда, ±0.05 оралиғида):
    0.50·(1 - todayOrders/dailyTarget) + 0.30·(trust/100) + 0.20·(rating/5)
  янги таклифчи (<5 бажарилган): +0.03, лекин бир вақтда ≤2 буюртма
  minScore (мос ҳисобланиш чегараси): 0.35
```

### Т-19. Lifecycle'даги етишмаган ўтишлар

Концепцияда аниқланмаган ҳолатлар:

1. **`accepted` → ҳеч нарса бўлмади.** `assignmentDeadline` (dispatch: 15 дақиқа, quote: модул бўйича).
   Муддат ўтса → `active`га қайтади, trust воқеаси ёзилади, қайта matching (аввал push олганларга
   такрор push кетмайди).
2. **Ижрочи бекор қилганда рад этилган таклифлар.** `rejected` таклифлар `active`га **қайтмайди**
   (эскирган нарх). Талаб `active`га қайтади ва фақат **янги** таклифлар кутилади; эски таклифчиларга
   «талаб яна очиқ» дайжест хабари (push лимити ичида).
3. **`disputed` эгаси ва SLA.** Низо админ панелида навбат, SLA 48 соат, ечим `completed` ёки `cancelled` +
   `demand_penalties` ҳужжати. Панелсиз `disputed` статуси жорий этилмайди.
4. **Таклифни ўзгартириш лимити:** битта талабга максимум 3 марта (спам ва нарх ўйинига қарши).

### Т-20. Проекция: «~500 м тахминий нуқта»нинг аниқ таърифи

«Тахминий нуқта» деб кесиб ташлаш (truncate) мумкин эмас — у тўр (grid) ҳосил қилади ва бир нечта
талабдан аниқ жойни тиклаш мумкин.

**Ечим:** `demandId` hash'идан детерминистик оғиш (seeded offset) — 300–600 м радиусда тасодифий, лекин
ҳар доим бир хил нуқта. Қўшимча: `geohash` проекцияда **5 белги** (≈4,9 км), тўлиқ 7–8 белги эмас.
Масофа ва ETA серверда аниқ координата бўйича ҳисобланади, клиентга фақат натижа («Сиздан 1,4 км») берилади.

### Т-21. Google Play ва ҳуқуқий талаблар (концепцияда умуман йўқ)

Илова Play'да нашр қилинган («AVA Zona», `uz.ava.gurlan`). P2 функциялари Play сиёсатига тегади:

1. **Паспорт нусхаси** = шахсни тасдиқловчи ҳужжат → Data Safety формасида «Personal identifiers / Government ID»
   декларацияси, сақлаш муддати ва мақсади; махфийлик сиёсати матнига қўшиш (`privacy-site/`).
2. **Фон/фаол жойлашув** → Android 14+: `foregroundServiceType="location"` + `FOREGROUND_SERVICE_LOCATION`
   рухсати + Play Console'да «Foreground service permissions» декларацияси + илова ичида **prominent disclosure**
   экрани («Жойлашувингиз фақат фаол буюртма пайтида мижозга кўрсатилади»).
3. **Тақиқланган товарлар** — фойдаланувчи шартлари ва модерация сиёсати матни.
4. **Жарима/қарз** — оферта матни ва тасдиқ (Т-10).

Бу тўртталаси **коддан олдин** эмас, лекин **релиздан олдин** бажарилиши шарт. Акс ҳолда илова олиб ташланади.

### Т-22. Аналитика: BigQuery мажбурий эмас

BigQuery экспорти лойиҳада йўқ; `analytics_pipeline.js` ўз қувури (pubsub schedule + агрегат ҳужжатлар).

**Ечим:** ядро кўрсаткичлари мавжуд қувурга қўшилади: `analytics_demand_daily/{date}_{module}_{regionId}`
агрегат ҳужжати (кунлик schedule). BigQuery — кейинги босқич, харажат ва эга қарори билан.

---

## 4. Эга қарорлари — ҲАММАСИ ҚАБУЛ ҚИЛИНДИ (2026-10-03)

| № | Савол | Қарор |
|---|---|---|
| Қ-1 | P0 пилоти «Хизмат сўрови» бўлсинми (гилам ювиш эмас)? | ✅ **Ҳа** — Т-17 |
| Қ-2 | Жавобгарлик шифти (300к / 1 млн / 3 млн) қабул қилинадими? | ✅ **Ҳа**, оферта матни билан — Т-10 |
| Қ-3 | quote режимида push лимити (5/соат, 20/кун + дайжест)? | ✅ **Ҳа** — Т-7 |
| Қ-4 | Жонли кузатув P2'да Firestore'да бошланадими (RTDB эмас)? | ✅ **Ҳа** — Т-3 |
| Қ-5 | Янги ядро алоҳида codebase'да (`functions_demand`) деплой қилинадими? | ✅ **Ҳа** — Т-1 |
| Қ-6 | Таксономия пилот учун нечта категория билан бошланади? | ✅ **≤40 категория**, фақат хизматлар |

Эга тасдиғи: «таклифларни қўллаб-қувватлайман, барчасини кетма-кет бажаришга кириш» (2026-10-03).
Жорий этиш 13.0'дан бошланди. **Деплой қилинмайди** — код тайёр бўлгач эга қарори билан.

---

## 4-А. ЖОРИЙ ҲОЛАТ (2026-10-03)

**P0 сервер томони тугади.** 13.0 (4/4), 13.1 (5/5), 13.2 (13/13), 13.3 (4/4).
**Тестлар:** `npm --prefix functions_demand test` → **405 тест, 0 хато.**
**Деплой:** `firebase deploy --only functions:demand --dry-run` → ✅ тоза (128,6 КБ пакет).
**Қоидалар:** `firebase deploy --only firestore:rules --dry-run` → ✅ компиляция тоза, янги бўлимда огоҳлантириш йўқ.

### ⚠️ ДОИРАДАН ТАШҚАРИ, ЛЕКИН МУДДАТЛИ ТОПИЛМА

Деплой текширувида Firebase огоҳлантириши чиқди:

> `Runtime Node.js 20 was deprecated on 2026-04-30 and will be decommissioned on 2026-10-30`

| Codebase | Node | Ҳолат |
|---|---|---|
| `functions` (**226 функция — бутун production**) | **20** | ⚠️ 2026-10-30 дан кейин ДЕПЛОЙ ҚИЛИНМАЙДИ |
| `y` | **20** | ⚠️ худди шундай |
| `functions_demand` (янги) | **22** | ✅ ўтказилди ва dry-run билан тасдиқланди |

**2026-10-30 — 27 кун қолди.** Шу санадан кейин мавжуд функцияларга битта кичик тузатиш ҳам деплой
қилинмайди (ишлаб турганлари тўхтамайди, лекин янгилаш имконсиз). Бу ушбу иш доирасига кирмайди, лекин
алоҳида вазифа сифатида очилиши керак: `functions/package.json`да `"node": "22"` + регрессия текшируви.

### P0 сервер — бажарилган файллар

| Файл | Вазифа | Тест |
|---|---|---|
| `firebase.json`, `functions_demand/package.json` | 13.1.1 codebase `demand`, **europe-west1**, Node 22 | dry-run ✅ |
| `geo/geo_hash.js`, `geo/geo.js` | 13.1.2, Т-4 (OSRM'сиз) | 36 |
| `functions/test/geo_hash_parity.test.js` | нусха ажралиб кетмаслиги қулфи | 14 |
| `core/ids.js` | 13.1.3 канон телефон ID | 26 |
| `core/config.js` | 13.1.4+13.1.5, Т-7/Т-18 рақамлари, 3 поғонали kill switch | 28 |
| `core/schemas/*`, `core/schema.js` | 13.2.1 | 43 |
| `core/state_machine.js` | Lifecycle, Т-19 | 54 |
| `core/text.js`, `core/keywords.js` | Intent Router ва эълон манбаси учун **битта** мослаштиргич | 57 |
| `core/moderation.js` | 13.2.13 (расм авто-фильтри ваъда қилинмайди) | — |
| `core/registry.js` | адаптер реестри | — |
| `core/seed/taxonomy_services.json` | 13.0.4 — **40** категория, 655 синоним | ✅ |
| `matching/scoring.js` | Т-18 score + fairness | 35 |
| `matching/orchestrator.js` | 13.2.3 — dedupe, фильтр, score, проекция | 33 |
| `sources/capabilities.js`, `sources/active_listings.js` | номзод манбалари + **cold start** | ✅ |
| `adapters/service.js` | P0 пилоти (Т-17, Қ-1) | ✅ |
| `notify/policy.js`, `notify/fcm.js`, `notify/dispatch.js` | 13.2.4+13.2.5, Т-6/Т-7 | 41 |
| `trust/compute.js`, `trust/events.js` | 13.2.11, Т-18+Т-10 | 26 |
| `api/create_demand.js` | 13.2.2 | 33 |
| `api/offers.js` | 13.2.6, 13.2.7, 13.2.8 | 26 |
| `api/maintenance.js` | 13.2.9, 13.2.10, 13.2.12, Т-19.1 | ✅ |
| `index.js` | 7 callable + 2 scheduled + 2 trigger | dry-run ✅ |
| `firestore.rules` | 13.3.1+13.3.2 — 18 коллекция қоидаси | компиляция ✅ |
| `firestore.indexes.json` | 13.3.3 — **23** янги индекс (жами 142) | валид ✅ |

### Иш давомида топилган ва тузатилган нарсалар

1. **Пилотнинг cold start муаммоси** — концепцияда кўрилмаган. Биринчи кунда `provider_capabilities`
   бўш бўлади, яъни ҳар талаб `no_providers` қайтарарди. Аудитда топилди: `ads`да аллақачон
   `type: 'service'` бўлган 21 эълон бор (75 эълон Хоразмда). `sources/active_listings.js` уларни
   ўқийди, лекин **push юбормайди** (`consentGiven: false`) — рози бўлмаган одамга спам кетмайди.
2. **Intent Router ва эълон манбаси битта мослаштиргични ишлатади** (`core/keywords.js`). Иккисининг
   иши айни бир хил: эркин матндан категория чиқариш. Луғат бир жойда таҳрирланади.
3. **Таксономияда иккита кўп маъноли калит сўз** топилди (`котёл` → газ устаси ёки иситиш тизими;
   `ямоқ` → шина ёки тикувчи). Улар ўчирилмади — Intent Router «сўраб олади», ўзи танламайди.
4. **`тозалаш` синоними жуда умумий эди** — «уй тозалаш» сўровини кондиционерга тортиб кетарди.
   Кўп сўзли ибора вазни ×3 га оширилди ва синоним аниқлаштирилди.
5. **Транслитерация айланаси симметрик эмас** (`электрик → elektrik → електрик`). Бу мавжуд
   `functions/index.js:7210` жадвалининг хусусияти ва `search_index` шу билан тўлдирилган, шунинг учун
   тузатилмади — ядро канон шакл сифатида доим **лотинни** ишлатади.
6. **Тест fake'и ноҳақиқий Firestore ID ясаган** (`auto_xxx`) ва `_` сабабли мавжуд бўлмаган
   нуқсонни кўрсатди. Ҳақиқий Firestore `_` ишлатмайди — fake тузатилди.
7. **`capabilities` манбаси `consentGiven`ни қўймаган** эди — имконият белгилаган одам розилик берган
   ҳисобланиши керак. Тест топди, тузатилди.

### P0 Flutter — бажарилган файллар (13.4)

| № | Файл | Тест |
|---|---|---|
| 13.4.1 | `lib/features/demand_offer/` тузилмаси (domain / data / ui_adapters / presentation) | `flutter analyze` ✅ |
| 13.4.2 | `domain/demand_enums.dart`, `demand.dart`, `offer.dart`, `demand_match.dart`, `canonical_id.dart` | 26 |
| 13.4.2 | **Паритет қулфи:** `functions_demand/test/fixtures/demand_parity.json` — сервер (16 тест) ва Dart (26 тест) АЙНИ БИР файлни ўқийди | 42 |
| 13.4.3 | `data/demand_repository.dart`, `data/match_repository.dart` — ёзиш callable, ўқиш жонли stream | ✅ |
| 13.4.4 | `ui_adapters/demand_ui_adapter.dart` — интерфейс + `DemandDraft`, `IntentResult` | ✅ |
| 13.4.4 | `ui_adapters/service_ui_adapter.dart` — P0 пилоти | 24 |
| 13.4.5 | `presentation/demand_composer/demand_composer_screen.dart` | ✅ |
| 13.4.6 | `presentation/demand_confirm/demand_confirm_sheet.dart` — «Шундай тушундик» | ✅ |
| 13.4.7 | `presentation/activity/activity_screen.dart` — икки бўлим + badge | ✅ |
| 13.4.8 | `presentation/demand_detail/demand_detail_screen.dart` (харидор), `demand_match_detail_screen.dart` (таклифчи), `offer_create/offer_create_sheet.dart` | ✅ |
| 13.4.10 | `lib/services/push_navigation.dart`га `demand_match` / `demand_taken` тармоғи — **мавжуд занжирга интеграция** | ✅ |
| 13.4.11 | `presentation/capabilities/provider_capabilities_screen.dart` — имконият + розилик оқими | ✅ |
| 13.4.12 | `assets/lang/{uz_Cyrl,uz_Latn,ru}.json` — **91 калит, учаласи синхрон** (2485 → 2576) | 4 |
| — | `test/core/locale_sync_test.dart` — уч тил қоидасининг автоматик қулфи | 4 |

**Жами тест: 936** (515 Flutter + 421 сервер), ҳаммаси яшил. `flutter analyze` — `lib/`да 0 муаммо.

### ✅ ЭГА ҚАРОРЛАРИ (2026-10-03) — БАЖАРИЛДИ

| Савол | Эга қарори | Жорий этилди |
|---|---|---|
| «Фаолият» таби қаерда? | **Bottom nav'га ЯНГИ ТАБ ҚЎШИЛМАЙДИ.** Профиль ичида «Талаб ва таклифлар» бўлими | `profile_screen.dart`да `_rolePanelButton` + `demand_activity_entry.dart` |
| «Уста чақириш» тугмаси? | **Алоҳида катта тугма ЭМАС.** Асосий кириш нуқтаси — **AVA'дан қидириш** | `home_global_search.dart` + `intent_router.dart` |

Шунинг учун **13.4.9 ўзгарди**: «Уста чақириш» тугмаси ўрнига Intent Router қурилди ва у
**P1'дан P0'га кўчди** — бошқа кириш нуқтаси йўқ, яъни у ишламаса пилот умуман ишламайди.

### ✅ P0.3 — UNIVERSAL SEARCH ИНТЕГРАЦИЯСИ (эга спецификацияси)

Эга талаб қилган оқим:
```
қидирув → intent аниқлаш → МАВЖУД натижаларни кўрсатиш
        → моси топилмаса: «Таклиф олиш» → сўров яратиш
```

Бешта сўров турининг ҳаммаси ишлайди (тестда қулфланган):

| Сўров | Натижа | Ажратилган маълумот |
|---|---|---|
| «Курьер керак» | `courier` | — |
| «Сантехник керак» | `service` + `santexnik` | — |
| «3 хонали квартира керак» | `realty` | хона = **3** |
| «Тошкентга такси керак» | `intercity_taxi` | манзил = **Тошкент** |
| «500 дона футболка керак» | `market` | миқдор = **500** (улгуржи) |

**Ядрога уланмаган модуллар учун** карточка «тез орада» демайди — иловада аллақачон
ишлайдиган экранга олиб боради (`existingScreen: courier / realty / intercity_taxi / …`).
Модул ядрога уланганда (P1–P2) фақат `coreReady: true` белгиси ўзгаради.

**Карточка форма эмас** (концепция қатъий қоидаси): натижаларни яширмайди, ўтказиб кетиш мумкин.
Натижа бор бўлса — рўйхат охирида камтарона «Моси топилмадими?»; натижа йўқ бўлса — асосий таклиф.

| Файл | Вазифа | Тест |
|---|---|---|
| `functions_demand/core/seed/intent_modules.json` | 5 модул + ажратиш намуналари + иш қидириш тўсғичи | — |
| `functions_demand/tools/build_intent_keywords.js` | луғат генератори (таксономиядан, қўлда ёзилмайди) | — |
| `assets/data/intent_keywords.json` | **397 калит, 40 категория, 6 модул, 26 манзил** (35 КБ) | — |
| `lib/features/demand_offer/intent/intent_router.dart` | қурилмада ишлайди, тармоқсиз | 68 |
| `presentation/service_intent_card/service_intent_card.dart` | карточка (иккита жойлашув) | — |
| `home_global_search.dart` | интеграция (`onIntent` ихтиёрий — ядро ўчса эски ҳолида ишлайди) | — |
| `test/features/demand_offer/canon_parity_test.dart` | канон шакл паритети | 5 |

**Иш қидириш ажратилади** (концепция талаби): «курьер иш», «ҳайдовчи бўлиб ишлаш» → карточка
**умуман чиқмайди**. Сабаб: бу одам «курьер керак» демаяпти, у ўзи курьер бўлиб ишлашни хоҳлаяпти.

### Иш давомида топилган ва тузатилган нарсалар (Flutter)

8. **Иккита ҳақиқий overflow нуқсони** — виджет тести топди: таклифчи карточкасидаги чип
   36 пиксел, таклиф карточкасидаги нарх қатори 70 пиксел ошиб кетарди. Бу фақат тестда
   эмас, production'да ҳам бўлади: русча таржима узунроқ ва фойдаланувчи шрифтни 130% гача
   катталаштириши мумкин. Иккиси ҳам `Flexible` + `ellipsis` + `maxWidth` билан тузатилди.
9. **Локализация делегати виджет тестида ишламайди** — `shouldReload => true` + асинхрон
   `rootBundle` сабабли `Localizations` ҳеч қачон «тайёр» бўлмайди ва бола дарахт қурилмайди
   (`LateError`). Тестлар калитлар бўйича ишлашга ўтказилди, сабаб ҳужжатлаштирилди.
10. **Локал файлларни алифбо бўйича қайта тартиблаш — 2532 қаторлик бекорга дифф берди.**
    Файллар тўлиқ алифбо тартибида эмас (`add` → `ad_district_choose`). Мавжуд тартиб
    сақланиб, янги калитлар охирига қўшилди: дифф 93 қаторга тушди.
12. **PRODUCTION'ДАГИ НОЗИК КАМЧИЛИК — `marketToLatin`да `ъ` ва `ь` олиб ташланмайди.**

    `functions/index.js:7210`да транслитерация `map[c] || c` тарзида ёзилган. Жадвалда
    `ъ: ''` ва `ь: ''` бор, лекин **бўш сатр JS'да falsy** — шунинг учун `|| c` ишга тушади
    ва белги ўзгармаган ҳолда ўтиб кетади:

    ```
    marketToLatin('курьер')  →  'kurьer'   (кутилган: 'kurer')
    marketToLatin('подъезд') →  'подъезд' дан 'podъezd'
    ```

    Dart томондаги `AdSearchText.toLatin` эса белгини тўғри олиб ташлайди (`kurer`). Яъни
    **илова ва сервер аллақачон ажралиб кетган**. Бу `search_index` ва `searchTokens`
    токенларига таъсир қилади: кирилл «курьер» деб ёзилган эълон лотин «kuryer» сўрови билан
    топилмайди.

    Тест буни топди (`canon_parity_test.dart`): «Курьер керак» сўрови луғат калити билан
    **ҳеч қачон учрашмасди** ва бу жимгина содир бўларди — хато чиқмайди, шунчаки «AVA тушунмади».

    **Қилингани:** ядро нусхаси (`functions_demand/core/text.js`) `hasOwnProperty` билан
    текширадиган қилиб тузатилди — икки томон энди бир хил.

    **Қилинмагани:** production'даги `marketToLatin` ТЕГИЛМАДИ.

    **Алоҳида реja:** [translit_migration_uz.md](translit_migration_uz.md) — ўлчов билан.
    Қисқаси: таъсир доираси бугун **битта ҳужжат**, reseed механизми (`adminSeedSearchIndex`)
    аллақачон мавжуд, тузатиш **битта қатор**. Шошилинч эмас, лекин `ъ` ўзбекча ҳақиқий ҳарф
    (эълон, таъми, истеъмол) — контент ўсган сари зарар ҳам ўсади.

13. **Мавжуд иккита локализация камчилиги топилди** (менинг ўзгаришимдан эмас):
    - `sum` / `currency_sum` = «сўм» — **учала** файлда, русчасида ҳам. Лотин ва рус
      интерфейсидаги фойдаланувчи нарх ёнида кирилл кўради. Тўғриси: `uz_Latn` → «so'm»,
      `ru` → «сум». **Ўзим тузатмадим:** бу матн бутун иловада, ҳар нарх ёнида ишлатилади.
    - `oil_section_*` калитлари бўш — текширувда улар «атайин бўш» деб белгиланди.

**Жами тест: 1015** (591 Flutter + 424 сервер), ҳаммаси яшил.

**Деплой қилинмади.** Ҳеч қандай `firebase deploy` (dry-run'дан бошқа) ишга туширилмаган.

**Кейинги навбат (эга тартиби бўйича):** 13.P1 — shadow mode + аналитика (9 кўрсаткич), сўнг курьер.

**Эга қарорини кутадиган очиқ савол:** `marketToLatin`даги `ъ`/`ь` камчилиги (12-банд) —
`search_index`ни қайта қуриб тузатамизми?

---

## 5. Вазифалар рўйхати

Белгилар: `[infra]` инфратузилма · `[srv]` Cloud Functions · `[app]` Flutter · `[rules]` Firestore rules ·
`[ops]` деплой/мониторинг · `[doc]` ҳужжат/ҳуқуқ · `[test]` тест

### 13.0 — Тайёргарлик (код ўзгармайди) — ✅ БАЖАРИЛДИ 2026-10-03

| № | Вазифа | Ҳолат |
|---|---|---|
| 13.0.1 | `[ops]` Firestore локацияси ва codebase регионини аниқлаш | ✅ қуйида |
| 13.0.2 | `[doc]` Қ-1…Қ-6 бўйича эга қарори | ✅ 4-бўлим |
| 13.0.3 | `[ops]` 17 коллекция номининг бандмаслигини production'да текшириш | ✅ қуйида |
| 13.0.4 | `[doc]` Таксономия пилот рўйхати (≤40 хизмат категорияси, 3 тилда) | ✅ `functions_demand/core/seed/taxonomy_services.json` |

#### 13.0.1 натижаси — РЕГИОН АНИҚЛАНДИ

```
Firestore:  projects/master-taxi-gurlan/databases/(default)
            locationId = eur3   (Европа мульти-регион: europe-west1/west4/north1)
            FIRESTORE_NATIVE, PESSIMISTIC
Функциялар: 226 та → us-central1
             17 та → europe-west1
```

**Хулоса:** мавжуд 226 функция Firestore билан бошқа қитъада — ҳар ўқиш/ёзишда ~100–150 мс қўшимча
(бу эски муаммо, ушбу ишнинг доирасида эмас, лекин ёзиб қўйилди).

**Янги `demand` codebase → `europe-west1`.** Репода намуна аллақачон бор, янгидан ўйлаб топилмайди:

| Нима | Мавжуд намуна |
|---|---|
| gen1 callable регион | `functions/index.js:5355` → `const authFunctions = functions.region('europe-west1')` |
| gen2 триггер регион | `functions/index.js:15402` → `onDocumentWritten({ document: ..., region: 'europe-west1' })` |
| Flutter клиент | `lib/core/firebase_functions_client.dart` → `AvaFunctions.auth` (`instanceFor(region: 'europe-west1')`) |
| Канон телефон ID | `functions/index.js:633` → `canonicalUid()` (998 + 9 рақам) — **13.1.3 шуни қайта ишлатади** |

Фойдаси: Firestore латенцияси ~150 мс → ~5 мс, Ўзбекистондан тармоқ RTT ~180 мс → ~80 мс.
Иккаласи ҳам 20 сониялик dispatch тўлқинлари учун ҳал қилувчи.

#### 13.0.3 натижаси — 17 НОМ БЎШ, ТЎҚНАШУВ ТАСДИҚЛАНДИ

Production Firestore'да 79 та root коллекция. Янги 17 номдан **0 таси банд** ✅

Тўқнашув текшируви (Т-2.1 тасдиқланди):

| Ном | Ҳолат | Намуна майдонлари |
|---|---|---|
| `trips` | **БАНД — маҳаллий такси** | `taxiType`, `userPhone`, `fromLat`, `fromLng`, `toAddr`, `driverId`, `price`, `radiusKm`, `expiresAt`, `cancelCount` |
| `couriers` | **БАНД — платформа курьери** | `phone`, `name`, `fcmToken`, `lat`, `lng`, `isOnline` |
| `complaints` | БОР — шикоят учун ишлатилади | `reason`, `adId`, `createdAt` |
| `reports` | root'да йўқ (субколлекция) | — |

→ `provider_trips` ва `provider_capabilities` номлари тасдиқланди. Шикоятлар мавжуд `complaints`га ёзилади.

### 13.P0 — Ядро + «Хизмат сўрови» пилоти (Урганч)

**Инфратузилма**

| № | Вазифа | Қабул мезони |
|---|---|---|
| 13.1.1 | `[infra]` `functions_demand/` codebase (`firebase.json`га учинчи codebase), Node 20, `ajv`, `eslint` | `firebase deploy --only functions:demand` мавжуд функцияларга тегмайди (деплой логида тасдиқ) |
| 13.1.2 | `[infra]` `geo_hash.js` кўчирилиши + паритет тести | `npm run test:geo-parity` — Dart ва JS бир хил натижа |
| 13.1.3 | `[srv]` Канон телефон ID ёрдамчиси (`toCanonicalId`: 9/12 → `998XXXXXXXXX`) + 100% қамров тести | Барча ёзишларда фақат 12 хонали шакл |
| 13.1.4 | `[srv]` `module_config/{module}_{regionId}` ўқиш + кеш + бошланғич қийматлар (Т-7, Т-18) | Қиймат ўзгарса, 60 сонияда функция уни кўради |
| 13.1.5 | `[srv]` Feature flag ва kill switch: `module_config.enabled`, `.pushEnabled`, `.matchingEnabled` | Битта майдон `false` → push ва matching тўхтайди, талаб яратиш ишлайди |

**Схема ва ядро функциялари**

| № | Вазифа | Қабул мезони |
|---|---|---|
| 13.2.1 | `[srv]` JSON Schema: `demand` (v1), `offer`, `attributes/service.json` | Нотўғри `attributes` → `invalid-argument` |
| 13.2.2 | `[srv]` `createDemand` callable: валидация, `clientRequestId` idempotency (Т-12), модерация, кунлик лимит, ёзиш, `runMatching` чақириш | Икки марта тап → битта `demands` ҳужжати |
| 13.2.3 | `[srv]` `runMatching`: манбалар (`active_listings`, `capabilities`, гео) → dedupe → қаттиқ фильтр → score (Т-18) → `demand_matches` ёзиш + `matchedBucket` (Т-8) | 500 номзодда < 3 сония; эга ўзи номзод бўлмайди |
| 13.2.4 | `[srv]` `notify/policy.js`: лимитлар, тинч соатлар (Asia/Tashkent), `demand_push_log` idempotency, дайжест (Т-7) | Бир талаб бўйича бир таклифчига ҳеч қачон иккинчи push кетмайди (тест) |
| 13.2.5 | `[srv]` `notify/fcm.js`: `users/{id}/fcm_tokens` субколлекцияси, `sendEach`, collapseKey/apns-collapse-id, ўлик токенни ўчириш (Т-6) | Икки қурилмада иккита push; ўчирилган иловадан кейин токен базадан кетади |
| 13.2.6 | `[srv]` `submitOffer` / `withdrawOffer`: битта таклифчи = битта таклиф, ≤3 таҳрир (Т-19.4), `ownerId` денормализацияси (Т-2.2) | Иккинчи таклиф янги ҳужжат ясамайди |
| 13.2.7 | `[srv]` `acceptOffer`: транзакция, қолганлар `rejected`, контакт 1-поғона очилиши (Т-9), collapse push янгиланиши | Икки параллел accept → битта ғолиб |
| 13.2.8 | `[srv]` `cancelDemand` / `cancelAssignment`: босқичга қараб `trust_events` (P0'да пул жарима йўқ) | Статус ўтишлари state machine'дан ташқарига чиқмайди |
| 13.2.9 | `[srv]` `expireDemandsSweeper` — `every 5 minutes` (Т-5) | `expiresAt` ўтган талаб 5 дақиқада `expired` |
| 13.2.10 | `[srv]` `submitRating` + `demand_ratings`: фақат `completed`, бир талабга битта баҳо | Бажарилмаган талабга баҳо → `failed-precondition` |
| 13.2.11 | `[srv]` `recomputeTrust` (`trust_events` триггери) → `provider_stats` | Воқеа ёзилгач 10 сонияда `trustScore` янгиланади |
| 13.2.12 | `[srv]` `onProviderAvailable` (тескари matching): `provider_capabilities` ўзгарганда мос актив талаблар | Янги имконият ёққан таклифчи 1 дақиқада мос талабларни кўради |
| 13.2.13 | `[srv]` `moderateDemand`: админ таҳрирлайдиган тақиқланган сўзлар рўйхати (`module_config/moderation`), шубҳали → `complaints` навбати. **Расм авто-фильтри йўқ** (қўлда) | Тақиқланган сўз → талаб `active` бўлмайди, модератор кўради |

**Қоидалар ва индекслар**

| № | Вазифа | Қабул мезони |
|---|---|---|
| 13.3.1 | `[rules]` 9 та янги коллекция қоидаси, репо ёрдамчилари билан (Т-2) | `@firebase/rules-unit-testing` тестлари: 25+ кейс, ҳаммаси яшил |
| 13.3.2 | `[rules]` Таклифчи `demands`ни ҳеч қачон ўқий олмаслиги; `demand_matches`ни фақат `providerId` фильтри билан | Фильтрсиз сўров `permission-denied` |
| 13.3.3 | `[infra]` Композит индекслар: `demand_matches(providerId, score desc)`, `demand_matches(providerId, createdAt desc)`, `demands(ownerId, status, createdAt desc)`, `demands(module, regionId, status, expiresAt)` | Илова рўйхатлари индекс хатосиз |
| 13.3.4 | `[ops]` Қоидалар **алоҳида** деплой (функциялардан кейин, алоҳида буйруқ) | Деплой логида фақат `firestore:rules` |

**Илова (Flutter)**

| № | Вазифа | Қабул мезони |
|---|---|---|
| 13.4.1 | `[app]` `lib/features/demand_offer/` тузилмаси; мавжуд Clean Architecture ва `provider` state management'га мослаш | `flutter analyze` — 0 хато |
| 13.4.2 | `[app]` `domain/`: `demand.dart`, `offer.dart`, `demand_match.dart`, `demand_status.dart`, `demand_mode.dart` — **қўлда** (Т-16) | Fixture паритет тести яшил |
| 13.4.3 | `[app]` `data/`: `demand_repository.dart` (callable'лар), `match_repository.dart` (жонли Firestore сўрови) | Ёзиш — фақат callable; ўқиш — Firestore stream |
| 13.4.4 | `[app]` `DemandUiAdapter` интерфейси + `service_ui_adapter.dart` (пилот) | Янги модул учун фақат adapter ёзилади |
| 13.4.5 | `[app]` `demand_composer/` — умумий форма хости (хизмат формаси: нима керак, қачон, қаерда, бюджет, расм, изоҳ) | Форма 3 тилда, валидация сервер схемаси билан мос |
| 13.4.6 | `[app]` `demand_confirm/` — «AVA шундай тушунди» тасдиқлаш экрани | Юборишдан олдин доимо кўрсатилади |
| 13.4.7 | `[app]` «Фаолият» таби: «Менинг сўровларим» + «Менга келган сўровлар» (`ava_bottom_nav.dart`га уланиш) | Икки бўлим, янги таклифлар сони badge'да |
| 13.4.8 | `[app]` `demand_detail/`, `offer_create/`, `offer_list/` (тартиблаш: нарх, рейтинг, масофа) | Таклифчи бошқа таклифнинг нархини кўрмайди |
| 13.4.9 | `[app]` Модул экранида «Уста чақириш» тугмаси + эълон рўйхати охирида «Таклиф олинг» | `ads` экранидан ядрога кириш нуқтаси |
| 13.4.10 | `[app]` Push: deep link `ava://demand/{id}` → «Фаолият» → талаб тафсилоти. **Action тугма P2** (Т-6.3) | Илова ўлдирилган ҳолатдан ҳам тўғри экран очилади |
| 13.4.11 | `[app]` `provider_capabilities` таҳрирлаш экрани (йўналиш, ҳудуд, модул, push созламаси) | Фойдаланувчи `trust`/`rating` майдонига ёза олмайди (rules тести) |
| 13.4.12 | `[app]` Барча янги матнлар → `assets/lang/uz_Cyrl.json`, `uz_Latn.json`, `ru.json` (**учаласи битта commit'да**) | Учта файлда калитлар сони бир хил (тест скрипти) |

**Shadow mode ва мониторинг**

| № | Вазифа | Қабул мезони |
|---|---|---|
| 13.5.1 | `[srv]` Shadow mode: matching ишлайди, `demand_matches` ёзилади, **push юборилмайди** (`pushEnabled: false`) | 1–2 ҳафта, Урганч, хизмат модули |
| 13.5.2 | `[srv]` `analytics_demand_daily` агрегати (Т-22): precision, fill rate, `no_providers`, push ўчириш улуши, intent карточка CTR | Кунлик ҳужжат, модул × ҳудуд кесимида |
| 13.5.3 | `[ops]` Қўлда текширув: 50 тасодифий match — «нега мос?» изоҳи билан | ≥90% эга «мантиқан мос» деб баҳолайди |
| 13.5.4 | `[ops]` Дарвоза: push ёқилиши учун 6-бўлимдаги рақамлар бажарилиши | Ёзма қарор, кейин `pushEnabled: true` |

---

## 5-А. ФАЗАЛАР — ЭГА ЙЎЛ ХАРИТАСИ (2026-10-03)

**ДИҚҚАТ:** эга юборган тартиб менинг дастлабки режамдан ФАРҚ ҚИЛАДИ ва **ўша тартиб
ҳақиқат манбаи**. Асосий ўзгариш: **Курьер P2'дан P1'га** кўчди, **товар модуллари
P1'дан P2'га**. Қуйидаги жадваллар эга хабарига кўра қайта тартибланган.

### 13.P1 — SHADOW MODE + ANALYTICS

Эга: «Аввал production'га тўлиқ тарқатмасдан shadow mode ишлатилсин.»

**Ўлчанадиган 9 кўрсаткич (эга рўйхати, айнан):**

| Кўрсаткич | Нима учун |
|---|---|
| `demandsCreated` | ҳажм |
| `providersMatched` | provider сони кам/кўпми |
| `pushEligible` | push спам бўляптими |
| `offersReceived` | matching тўғрими |
| `timeToFirstOffer` | жавоб тезлиги |
| `acceptedOffer` | сифат |
| `expiredWithoutOffer` | таклифчи етишмаслиги |
| `completedDemand` | якуний натижа |
| `cancelledDemand` | муаммо белгиси |

**Эга қўйган тўртта савол** — аналитика шу тўрттасига жавоб бериши керак:
matching тўғрими · номос provider чиқяптими · provider сони кам/кўпми · push спам бўляптими.

| № | Вазифа |
|---|---|
| 13.5.1 | `[srv]` Shadow mode: `matchingEnabled: true` + `pushEnabled: false` (кодда тайёр) — Урганч, хизмат модули, 1–2 ҳафта |
| 13.5.2 | `[srv]` `analytics_demand_daily` — **юқоридаги 9 кўрсаткич**, модул × ҳудуд кесимида |
| 13.5.3 | `[srv]` `pushEligible` алоҳида ҳисобланади: policy «юборилади» деган, лекин shadow'да юборилмаган ҳолатлар (Т-7 лимитлари кўринсин) |
| 13.5.4 | `[ops]` 50 тасодифий match — «нега мос?» изоҳи билан қўлда текширув (номос provider саволига жавоб) |
| 13.5.5 | `[ops]` Дарвоза: 6-бўлимдаги рақамлар бажарилса `pushEnabled: true` |

### 13.P1 — КУРЬЕР

Эга рўйхати бўйича. **Қатъий қоида (эга):** посилка «оддий / муҳим / қимматбаҳо» деб
**тоифаланмайди**.

> **Аниқлик:** Т-10 жавобгарлик шифти бу қоидага ЗИД ЭМАС. Шифт **курьернинг**
> тасдиқланганлик даражасига боғланади, посилкага эмас. Посилка қиймати концепция
> айтганидек «тоифа эмас, оддий рақам» бўлиб қолади. Яъни посилка турлари ЙЎҚ — фақат
> курьернинг қанча жавобгарликни кўтара олиши бор.

| № | Вазифа |
|---|---|
| 13.6.1 | `[doc]` **Релиз блокери:** оферта матни, Data Safety (паспорт), фон жойлашуви декларацияси, prominent disclosure (Т-21) |
| 13.6.2 | `[infra]` Cloud Tasks API + `demand-waves` навбати + IAM + `minInstances: 1` (Т-5) |
| 13.6.3 | `[srv]` **Шаҳар ичи курьер** — `provider_presence`, ETA тўлқинлари, `dispatchWave`, `acceptDispatch` + `assignmentDeadline` (Т-19.1) |
| 13.6.4 | `[srv]` **Шаҳарлараро курьер** — `provider_trips` (Т-2.1 ном!), «Йўлим тушади» matching, маршрутдан четлашиш (haversine × 1,35, Т-4) |
| 13.6.5 | `[app]`+`[srv]` **«Посилка оламан»** белгиси — `provider_trips.acceptsParcels` + `parcelCapacity` |
| 13.6.6 | `[app]` **Истаган одам courier mode'ни ёқа олиши** — `provider_capabilities` экрани (P0'да тайёр, курьер майдонлари қўшилади) |
| 13.6.7 | `[srv]` **Бир курьерга бир нечта посилка** — `parcelCapacity` тўлса қолганлар кўрсатилмайди; ҳар мижоз фақат ўз нуқтасигача ETA'ни кўради |
| 13.6.8 | `[app]` **Вазн / ҳажм / вақт** формаси + улов → максимал вазн жадвали (сервер белгилайди) |
| 13.6.9 | `[srv]` `expiresAt` — P0'да тайёр (sweeper), курьер учун қисқа муддатлар созланади |
| 13.6.10 | `[srv]` **Fairness** — P0'да тайёр (`scoring.js`), курьер учун `dailyOrderTarget` созланади |
| 13.6.11 | `[srv]` **Internal trust** — P0'да тайёр (`trust/compute.js`) |
| 13.6.12 | `[srv]` **Public rating АЛОҲИДА** — P0'да тайёр (`demand_ratings`, AVA уни ўзгартирмайди) |
| 13.6.13 | `[srv]` `confirmPickup` (расм) / `confirmDelivery` (4 хонали код) + контакт 2-поғона (Т-9) |
| 13.6.14 | `[srv]`+`[app]` Жонли кузатув: `demand_tracking` **Firestore** (Т-3), `getTracking(token)`, Android foreground service |
| 13.6.15 | `[srv]` `courier_documents` + `verifyCourierDocuments` + `checkCourierDocuments` (7 кун) |
| 13.6.16 | `[srv]` Жарима: `demand_penalties` (ҳолат) + **`wallet_ledger`** (пул) + `blockedReason` (Т-11) |
| 13.6.17 | `[srv]` `module_tariffs` — версия ва тарих билан |
| 13.6.18 | `[app]` Android action тугма + notification channel + AVA овози (Т-6.3) |

### 13.P1 — ШАҲАРЛАРАРО ТАКСИ

| № | Вазифа |
|---|---|
| 13.7.1 | `[srv]` Йўловчи талаби — `quote` режими, `provider_trips` манбаси |
| 13.7.2 | `[srv]` Ҳайдовчи таклифи — `submitOffer` (P0'да тайёр) |
| 13.7.3 | `[srv]` «Посилка оламан» — курьер билан БИР МЕХАНИЗМ (`provider_trips`) |
| 13.7.4 | `[srv]` Route matching — йўналиш, вақт, бўш жой, четлашиш |
| 13.7.5 | `[srv]` Мавжуд `intercity_drivers` / `intercity_bookings` билан боғлаш (**бузилмайди**) |

### 13.P1 — ЮК (иккала модул)

| № | Вазифа |
|---|---|
| 13.8.1 | `[srv]` **Туман ичида Юк** adapter'и |
| 13.8.2 | `[srv]` **Шаҳарлараро Юк** adapter'и (**мавжуд биржа бузилмайди**) |
| 13.8.3 | `[srv]` Мослаш: маршрут · вазн · машина тури · вақт · масофа |

### 13.P2 — ТОВАР МОДУЛЛАРИ

Уланади: **Сотинг · Аҳоли Бозори · AVA Дўкони**

Қўллаб-қувватланадиган сўровлар (эга): «Шу товар керак» · «500 дона керак» · «Шунга ўхшаш керак»

| № | Вазифа |
|---|---|
| 13.9.1 | `[srv]` `taxonomy` коллекцияси + товар категориялари (P0'да хизмат seed'и тайёр) |
| 13.9.2 | `[srv]` Matching манбалари: **active listings** (P0'да тайёр) · **old listings** · **provider profile** · **seller history** |
| 13.9.3 | `[srv]` `sources/past_activity.js` + **розилик оқими** (P0'да UI тайёр) |
| 13.9.4 | `[srv]` Улгуржи: `quantity >= 5` (P0'да тайёр) → `wholesale`/`minOrderQty` устунлиги |
| 13.9.5 | `[app]` «Шунга ўхшаш керак» — AVAGram ва эълон карточкасидан |

### 13.P2 — ХИЗМАТЛАР

Уланади: **Эълон ва Хизмат · Гилам ювиш · Мой алмаштириш · Таомлар · Нон · Сут қабул**

**Эга қоидаси:** ноаниқ сўзларда (`котёл`, `ямоқ`) Intent Router **ўзи тахмин қилмасин** —
clarification сўралиши мумкин. ✅ **P0'да жорий этилган ва тестда қулфланган.**

| № | Вазифа |
|---|---|
| 13.10.1 | `[srv]` Гилам ювиш adapter'и (**мавжуд оқим ишлаб туради**, dual-write фақат зарур жойда) |
| 13.10.2 | `[srv]` Мой алмаштириш adapter'и |
| 13.10.3 | `[srv]` Таомлар adapter'и («20 кишига ош» — катта буюртма) |
| 13.10.4 | `[srv]` Нон ва Сут қабул — `recurring` режими, юпқа adapter |
| 13.10.5 | `[srv]` Таксономияни кенгайтириш + админ панелда таҳрирлаш |

### 13.P2 — КЎЧМАС МУЛК

Эга мисоли: **«Урганчда 3 хонали квартира керак»** ✅ (Intent Router P0'да уни таниди)

**Эга позицияси:** AVA ўзи риэлтор ЭМАС, платформа сифатида matching қилади.

| № | Вазифа |
|---|---|
| 13.11.1 | `[srv]` `alert` + `quote` режими (мавжуд `realty.js` ва «Кластер» билан) |
| 13.11.2 | `[srv]` Таклифчи турлари: **мулк эгалари · агентлар · ҳамкор риэлторлик компаниялари** |
| 13.11.3 | `[srv]` Агентлар ва компаниялар учун алоҳида тасдиқлаш |

### 13.P3 — ҚЎШИМЧА ИМКОНИЯТЛАР

| № | Вазифа |
|---|---|
| 13.12.1 | `[app]`+`[srv]` **image demand** (`imageEmbedding` майдони P0'дан бери бўш туради) |
| 13.12.2 | `[srv]` **semantic image matching** |
| 13.12.3 | `[app]`+`[srv]` **voice demand** — Aisha ва Google STT'ни Хоразмдан 100 реал овозда солиштириш |
| 13.12.4 | `[app]` **AVAGram → «Шуни хоҳлайман»** |
| 13.12.5 | `[srv]` **advanced ranking** |
| 13.12.6 | `[ops]` **deeper analytics** (BigQuery — харажат ҳисоби билан, Т-22) |
| 13.12.7 | `[srv]` `parseIntent` LLM — мавжуд assistant OpenAI қувури устида (Т-15) |
| 13.12.8 | `[srv]` Юпқа adapter'лар: Маҳаллий такси (**ўз диспетчери қолади**), Маршрут такси |

### 🚫 DEMAND ENGINE'ГА УЛАНМАЙДИ (эга қарори)

| Модул | Сабаб |
|---|---|
| **EV Зарядлаш** | Ўзининг Trip Planner архитектурасида қолади |
| **Менинг Яқинларим** | Талаб → таклиф модели эмас |
| **Танишув** | Талаб → таклиф модели эмас |

Шунинг учун `demand_input.schema.json`даги модул рўйхатига улар **киритилмайди**.

---

## 6. Shadow mode дарвозалари (рақамли — булардан ўтмаса push ёқилмайди)

| Кўрсаткич | Минимал талаб |
|---|---|
| Precision: push → таклиф (quote) | ≥ 12% |
| Dispatch: push → қабул | ≥ 25% |
| Fill rate (камида 1 таклиф олган талаб) | ≥ 60% |
| `no_providers` улуши | ≤ 25% |
| Push ўчириш улуши (2 ҳафта) | ≤ 5% |
| Intent карточка → «Давом этиш» | ≥ 40% |
| Қўлда текширув (50 match) | ≥ 90% «мантиқан мос» |
| Функция хатолари | ≤ 0,5% |
| `runMatching` p95 | ≤ 3 сония |

Ҳар бир фаза учун мажбурий: feature flag (модул × ҳудуд), shadow mode (1–2 ҳафта), kill switch
(`module_config`да битта майдон), мониторинг (push сони, хатолар, функция вақти ва нархи).

---

## 7. Деплой тартиби (бузилмайдиган қоида)

1. `firebase deploy --only functions:demand` — **фақат янги codebase**.
2. Текшириш: логлар, хатолар, kill switch ишлаши.
3. `firebase deploy --only firestore:indexes`.
4. **Алоҳида буйруқ:** `firebase deploy --only firestore:rules` — ҳеч қачон функциялар билан бирга эмас
   (2026-09-27: бронь ~5 соат узилган).
5. Илова релизи — эга қарори билан, қоидалар деплой қилингандан кейин.

Git: бу тармоқ (worktree) бошқа сессия билан улашилган → фақат аниқ йўллар `git add` қилинади, `git add -A` йўқ.

---

## 8. Ҳозирча жорий этилмайди (ёзиб қўйилди, қайтиб келинади)

| Нима | Сабаб | Қачон |
|---|---|---|
| Realtime Database | Firestore нархи Урганч ҳажмида арзон (Т-3) | Кунда >2000 фаол кузатув |
| OSRM ўз серверида | Geohash + коэффициент етарли (Т-4) | Shadow mode «тўлқин сифати ёмон» дейса |
| Typesense / Meilisearch | `search_index` ишлаб турибди (Т-14) | Семантик мослик талаб қилинганда |
| BigQuery экспорти | Ўз аналитика қувури бор (Т-22) | Харажат тасдиқлангач |
| Dart codegen (build_runner) | Паритет тести етарли (Т-16) | Модуллар 8+ бўлганда |
| iOS action тугмалар, iOS фон жойлашуви | App Store'да нашр йўқ (В-6) | iOS релизидан кейин |
| Тўлов ва комиссия | `payment` майдони бўш қолдирилади | Эга қарори билан |
| Расм авто-модерацияси | Вендор йўқ, ваъда берилмайди | P3 |
