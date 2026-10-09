# Улгуржи бозор — «Мижозларга» хизмат бўлими (BTS намунаси): таклиф ва архитектура

> Сана: 2026-10-09. Манба: bts.uz «Mijozlarga» менюси (6 банд) ва FAQ (2026-10-09 ўқилди),
> `docs/ulgurji_bozor_savdo_taklifi_uz.md` (У0–У8 режаси, D-ULG-1…9), relay архитектураси
> (`docs/relay_delivery_architecture_uz.md`), ресторан занжири. Код ёзилмаган.
> Белгилар: **BTS_CONFIRMED** — BTS саҳифасида бор; **CONFIRMED** — AVA кодида бор;
> **PROPOSED** — таклиф; **ЭГА ҚАРОРИ** — тасдиқ керак.

---

## 1. BTS «Мижозларга» бўлими нимадан иборат — BTS_CONFIRMED

| № | BTS банди | Нима қилади | FAQ'дан қўшимча қоида |
|---|---|---|---|
| 1 | **Xizmat narxini hisoblash** (`/calculate`) | Қаердан/қаерга (вилоят+туман), олиш/топшириш усули (курьер, туман маркази, қўлдан), ўлчам ×3 + вазн, ҳужжат қайтариш, қути → нарх | нарх жадвали — тариф картаси (`/dokumenty`) |
| 2 | **Shartnoma tuzish** (`/contract`) | Юридик шахс/ҳажмли жўнатувчи аризаси: исм, компания, лавозим, шаҳар, манзил, хизмат тури (экспресс, курьер, e-commerce, омбор, юк), кутилаётган вазн/ҳажм → сотув менежери боғланади | шартнома = COD (4 %), кабинет, шахсий тариф |
| 3 | **Ofislarimiz** (`/nashi-ofisi`) | Филиаллар рўйхати: код, ном, манзил+мўлжал, иш вақти, телефон 1230, «Xaritadan ko'rish», видео-йўриқ; ҳудуд фильтри | бепул сақлаш 10 кун, пуллик 1 ой, кейин утилизация |
| 4 | **Murojaat** (`new.bts.uz/complaint`) | Шикоят/мурожаат формаси (логин талаб қилади); зарар/йўқолиш — «takliflar va shikoyatlar bo'limi», далил билан | SMS код билан учинчи шахсга бериш; маълумот фақат рўйхатдаги рақамга |
| 5 | **Ko'p beriladigan savollar** (`/faq`) | 17 савол: кузатув (илова, сайт, @btsrobot, 1230), ID рақам, муддат (1 иш куни, Тошкент 3–5 соат), ким тўлайди (жўнатувчи, Click/Payme/Uzum Bank), суғурта 1 %, тақиқланган буюмлар, зарар, сақлаш, курьер чақириш муддати (16:00 / шанба 13:00), халқаро, франшиза | — |
| 6 | **Shartnomalar va umumiy shartlar** (`/dokumenty`) | Умумий шартлар, тариф картаси (эски/янги, кучга кириш санаси), оферта, экспресс шартнома, эътироз далолатномаси | версияланган, санали |

Хулоса: BTS мижозга **олдиндан** (нарх, офис, қоида), **жараёнда** (кузатув, SMS код) ва **кейин** (мурожаат, сақлаш, суғурта) хизмат кўрсатади; ҳаммаси 6 кириш нуқтасига жамланган.

---

## 2. AVA'да ҳозир нима бор — CONFIRMED

| BTS вазифаси | AVA'да мавжуд компонент | Улгуржи бозорга уланганми |
|---|---|---|
| Нарх ҳисоблаш | relay `quoteLogisticsOrder` (зона × пулли вазн, версияли тариф), ресторан `quoteRestaurantDelivery`; У1 дан товарда вазн/ўлчам, сотувчида туман бор | **йўқ** (У2 режада) |
| Шартнома / сотувчи аризаси | `wholesale_sellers` рўйхатдан ўтиш (компания, тур, У1: манзил), админ тасдиғи, авто-тасдиқ; оферта/шартлар матни — йўқ | қисман |
| Офислар / пунктлар | **йўқ** — AVA'да ПВЗ/офис тушунчаси йўқ (эшикдан эшикка модели); relay'да `agent` роли режада | йўқ |
| Мурожаат | `support_chats` (чат + `awaitingAdmin` badge), админ «Chat support»; relay `disputed` ҳолати; ресторан `adminCancelRestaurantOrder` | улгуржига боғланмаган |
| FAQ / қоидалар | `admin_news`/ticker, модул «Тез кунда» матнлари; алоҳида FAQ экрани йўқ | йўқ |
| Ҳужжатлар (оферта, тариф версиялари) | relay `module_tariffs/logistics_v{N}` (draft/active/retired), `restaurant_delivery_tariffs/v{n}`, админ тарих экрани; мижозга кўринадиган оферта — йўқ | йўқ |
| Кузатув | relay custody тасмаси (`lib/features/logistics/` буюртма экрани), ресторан статус тасмаси | улгуржи буюртмаси йўқ (У3) |
| SMS/код билан топшириш | relay `confirmDelivery` 6 хонали код, ресторан pickup код — **кодда бор** | У5 да уланади |
| Суғурта / эълон қилинган қиймат | relay `riskReserve` ички компонент; мижозга «қиймат эълон қилиш» — йўқ | йўқ |
| Сақлаш муддати / утилизация | йўқ (ПВЗ йўқлиги учун керак эмас) | — |
| Тўлов: ким тўлайди | relay эскроу `payerSide: 'sender'`; улгуржида D-ULG-4 очиқ | қарор кутилмоқда |

---

## 3. Таклиф — AVA Улгуржи бозорида «Мижозларга» бўлими (PROPOSED)

Принцип: BTS'ни кўчирмаймиз — унинг **офис/ПВЗ** модели AVA'га мос эмас (AVA эшикдан эшикка, туман даражасида). Олинадигани: 6 кириш нуқтасининг **вазифаси**, ҳар бири мавжуд AVA компонентига уланади, янги «орол» қурилмайди (CLAUDE.md 43).

Иловада жойлашуви: Улгуржи бозор экранида учинчи таб ёки «⋯» меню → **«Ёрдам ва хизмат»** (сотувчи ва харидор учун бир хил кириш, ичида рол бўйича фарқ). Админда: «Улгуржи бозор» бўлимига «Хизмат маркази» таби.

| № | AVA банди | Нима қилади | Қайси компонент (қайта ишлатиш) | Босқич |
|---|---|---|---|---|
| 1 | **Етказиш нархи ҳисоблагичи** | Харидор: товар саҳифасида ва алоҳида экранда — «қаерга?» (туман) → ҳақ ва муддат; сотувчи: «менинг товарим Х туманга қанчага боради» | У2 `quoteWholesaleDelivery` (relay тарифи + last-mile), У1 вазн/ўлчам ва сотувчи тумани | У2 |
| 2 | **Сотувчи шартномаси (оферта)** | Рўйхатдан ўтишда оферта матнини кўриш ва қабул қилиш (версия + сана сақланади); «юқори ҳажм» аризаси: кутилаётган ойлик вазн/буюртма — админга белги (`highVolume`), шахсий шартлар — оффлайн | `wholesale_sellers` + `acceptServiceAgreement` намунаси (capability'да бор, CONFIRMED) → `agreementVersion/agreementAcceptedAt` майдонлари; админ «Сотувчилар» карточкасида кўриниш | У3 олди |
| 3 | **«Офислар» ўрнига — «Хизмат ҳудудлари ва нуқталар»** | Харита/рўйхат: AVA курьерлари ишлайдиган туманлар (`geo_district_modules` да модул ёқилган), relay агент/ПВЗ нуқталари (бўлса), ҳар туман учун кутилаётган муддат; «Сизнинг туманингизда етказиш бор/йўқ» | `ServiceConfigHolder`/`geo_districts` (CONFIRMED), relay `agent` ва ПВЗ — ЭГА ҚАРОРИ (D-ULG-7); ҳозирча фақат «ҳудуд ёқиқми» кўрсатиш | У2 (фақат кўрсатиш), ПВЗ — кейин |
| 4 | **Мурожаат** | Буюртма саҳифасидан «Муаммо» → тоифа (етиб келмади / шикастланган / кам чиқди / сотувчи жавоб бермайди / бошқа) + матн + расм → `support_chats` га буюртма контексти билан; админда буюртма ва custody тарихи ёнма-ён; низо → relay `disputed` ёки `adminCancel…` + эскроу REFUND | `support_chats` + `awaitingAdmin` (CONFIRMED), relay custody (CONFIRMED), ресторан admin cancel намунаси | У3–У5 |
| 5 | **FAQ** | 10–15 савол, 3 тилда, админ таҳрирлайди (матн), версия/сана; буюртма ҳолатига қараб контекстли «кўп сўраладиган 3 савол» | янги кичик коллекция `help_articles/{module}` ёки `admin_news` категорияси — ЭГА ҚАРОРИ; матн тилларни `assets/lang` эмас, базада (админ ўзгартирсин) | У2 |
| 6 | **Ҳужжатлар ва тарифлар** | Мижозга: оферта (жорий + архив), етказиш тарифи версиялари («01.09.2026 дан» каби сана билан), тақиқланган товарлар рўйхати, суғурта/жавобгарлик қоидаси | relay `module_tariffs` тарихи (CONFIRMED), `restaurant_delivery_tariffs` намунаси → улгуржи тарифи ҳам версияли; оферта матни — `help_articles` | У2 |
| 7 | **Кузатув** (BTS'да FAQ'нинг 1-саволи) | Буюртма саҳифасида босқичлар: қабул → сотувчи тайёрлади → курьер олди (код/расм) → йўлда (LEG k/n) → етказилди (код); push ҳар ўтишда; Telegram бот — йўқ (илова бор) | relay custody тасмаси + ресторан статус тасмаси (CONFIRMED) | У5 |
| 8 | **Қиймат эълон қилиш / суғурта** | Буюртмада «эълон қилинган қиймат» = товар суммаси (автомат, улгуржида маълум) → жавобгарлик шу сумма; ҳақ ичида `riskReserve` (BTS 1 %) — мижозга алоҳида қатор сифатида кўрсатиш ёки ҳақ ичида яшириш — ЭГА ҚАРОРИ | relay `riskReserve` (CONFIRMED, ички) | У4 |
| 9 | **Тақиқланган/келишув талаб қиладиган товарлар** | Товар қўшишда категория текшируви (сотувчи тасдиқлайди «тақиқланган эмас»), модерацияда белги; рўйхат — ҳужжатлар бўлимида | модерация экрани (CONFIRMED) + `help_articles` | У3 |

Нима **олинмайди** (асосланган): офис тармоғи ва «пунктда сақлаш 10 кун» (ПВЗ йўқ); франшиза; халқаро; алоҳида Telegram бот (илова + push етарли, 43-банд); «1230» каби қўнғироқ маркази (support chat + сотувчига қўнғироқ бор).

---

## 4. Эга қарорлари — AVA_DECIDED (2026-10-09)

| № | Қарор | Натижа |
|---|---|---|
| D-ULG-10 | Ёрдам/хизмат матнлари **Firebase базасида**, админдан **3 тилда**, **версия тарихи** сақланади | `help_articles` + `help_articles/{id}/versions/{n}` (ўзгармас) |
| D-ULG-11 | «Офислар» → **«Хизмат ҳудудлари»**: ҳозир фақат хизмат кўрсатиладиган туманлар + етказиш муддати; ПВЗ кейин | `service_coverage` кўриниши; модел ПВЗ учун кенгаювчан (`points` бўш) |
| D-ULG-12 | Риск захираси **етказиш нархи ичида**; ҳақиқий суғурта шартномаси бўлмагунча мижозга «суғурта» сўзи **кўрсатилмайди**; зарар учун **жавобгарлик офертада аниқ** | `riskReserve` ички; офертада «жавобгарлик» бўлими мажбурий майдон |
| D-ULG-13 | Мурожаат — **тикет + чат**; ҳар тикет буюртма ва етказиш тарихига боғланади | `support_tickets` (янги) ↔ `support_chats` (мавжуд) ↔ `orders`/custody |
| D-ULG-14 | Катта сотувчиларга **келажакда** алоҳида шартлар; биринчи босқичда **ҳаммага умумий тариф** | `wholesale_sellers.tier` майдони резерв (`standard`), тариф двигатели `tier` параметрини қабул қилади, лекин v1 да фақат `standard` |

Deploy: эга — «ҳозирча production'га deploy қилма». Қуйидагилар фақат код + тест.

---

## 5. Техник режа — янгиланган

### 5.1 Маълумот модели

```
help_articles/{articleId}
  module:        'wholesale' | 'logistics' | 'restaurants' | 'all'
  kind:          'faq' | 'offer' | 'liability' | 'prohibited' | 'terms' | 'notice'
  slug:          string (бир module+kind ичида ноёб, масалан 'offer-wholesale-seller')
  order:         int
  active:        bool
  version:       int            ← ҳар сақлашда +1 (сервер)
  effectiveFrom: timestamp      ← «01.09.2026 дан» кўриниши (BTS каби)
  title:         {uz_Cyrl, uz_Latn, ru}
  body:          {uz_Cyrl, uz_Latn, ru}   ← markdown-lite (сарлавҳа, рўйхат, қалин)
  updatedAt, updatedBy (admin uid)
  versions/{n}   ← ЎЗГАРМАС нусха: ўша title/body/effectiveFrom + changedBy, changedAt, reason

service_coverage/{districtId}            ← D-ULG-11, фақат ўқиш учун проекция (сервер ёзади)
  regionId, districtId, name{3 тил}
  modules: { wholesale: { enabled: bool, etaDaysMin, etaDaysMax, lastMileTier: 'A'|'B'|'C' } }
  points: []                              ← ПВЗ учун резерв (бўш), v1 да ёзилмайди
  updatedAt
  — манба: `geo_district_modules` + relay зона матрицаси; `rebuildServiceCoverage` sweeper/trigger

support_tickets/{ticketId}               ← D-ULG-13
  ticketNo:      int (кетма-кет, ўқилиши осон — «№ 1042»)
  module:        'wholesale'
  kind:          'not_delivered' | 'damaged' | 'short' | 'wrong_item' | 'seller_silent'
                 | 'payment' | 'other'
  status:        'open' | 'in_progress' | 'waiting_customer' | 'resolved' | 'rejected' | 'closed'
  openedBy:      uid (канон телефон), openedRole: 'buyer' | 'seller' | 'courier'
  orderId:       string (мажбурий)        ← буюртма билан боғлиқ
  shipmentId?, legId?                     ← етказиш тарихи (custody) билан боғлиқ
  sellerId, buyerId                       ← проекция (сервер ёзади, рухсат учун)
  chatId:        string (`support_chats` ҳужжати)
  photos:        [storage path]           ← `tickets/{ticketId}/…`
  resolution?:   { kind: 'refund' | 'partial_refund' | 'redeliver' | 'no_action', amount?, note, by, at }
  slaDueAt:      timestamp (очилганда +24 с иш вақти, PROPOSED)
  createdAt, updatedAt
  events/{n}     ← ЎЗГАРМАС: ҳолат ўтишлари (from, to, by, at, note) — 16-банд

wholesale_sellers/{phone}                ← У1 + қўшимча
  agreementVersion:    int, agreementAcceptedAt: timestamp   ← оферта (help_articles offer.version)
  tier:                'standard'        ← D-ULG-14 резерв; v1 да фақат шу
  expectedMonthlyWeightG?: int, highVolume?: bool            ← белги, админ кўради

orders/{id} type:'wholesale'             ← У3 режаси; қўшимча:
  deliveryQuote.internal.riskReserve      ← мижозга кўрсатилмайди (D-ULG-12)
  openTicketIds: []                       ← тез кўриниш учун проекция (сервер)
```

Ўзгармаслик: `help_articles/*/versions`, `support_tickets/*/events`, custody — фақат қўшилади.

### 5.2 Сервер (Cloud Functions, default codebase, номма-ном deploy)

| Callable / trigger | Ким | Нима қилади | Idempotency / audit |
|---|---|---|---|
| `adminUpsertHelpArticle` | admin, superadmin | 3 тил матн, `effectiveFrom`, `active`; транзакцияда `version+1` ва `versions/{n}` нусха; `kind: offer/liability` учун 3 тил ҳам тўлиқ бўлиши шарт (бўш тилда сақланмайди) | `admin_audit kind: help_article` |
| `getHelpArticles` ёки тўғридан-тўғри ўқиш | ҳамма | `module in [x,'all'] && active` — rules орқали ўқиш етарли (CF шарт эмас) | — |
| `acceptWholesaleAgreement` | сотувчи | `offer` ва `liability` мақолаларининг жорий `version`ини қабул қилади; сервер вақти; версия эскирса — қайта қабул талаби (`AGREEMENT_OUTDATED`) | калит `{uid}_{version}`; `agreementAcceptedAt` ўзгармайди |
| `quoteWholesaleDelivery` | харидор/сотувчи | У2: туман→туман зона × пулли вазн + last-mile + `riskReserve` (ички) → мижозга **битта** `deliveryFee` + `etaDays`; `tariffVersion`, `tier:'standard'` | ўқиш; лимит: 60/дақ/uid (PROPOSED) |
| `rebuildServiceCoverage` | trigger (`geo_district_modules` ўзгарганда) + кунлик sweeper | `service_coverage` проекциясини қайта ёзади | — |
| `openSupportTicket` | буюртма эгаси / сотувчиси / фаол LEG ижрочиси | рухсат текшируви серверда; `ticketNo` counter транзакцияда; `support_chats` яратади (`awaitingAdmin: true`); `orders.openTicketIds` янгилайди; админга push | калит `{orderId}_{kind}_{uid}` 10 дақ ичида такрор → мавжуд тикет қайтади |
| `adminUpdateSupportTicket` | admin, superadmin (finance — `refund`) | ҳолат ўтиши (жадвал), `resolution`; `refund` → мавжуд эскроу/ҳамён йўли (relay REFUND ёки ресторан намунаси) — пул фақат ledger орқали | `events/{n}` + `admin_audit`; `refund` idempotent калит `ticket_{id}_refund` |
| `onSupportChatMessage` (мавжуд chat оқими) | — | тикет `waiting_customer` ↔ `in_progress` автомат | — |

Ҳолат жадвали (сервер): `open → in_progress → (waiting_customer ↔ in_progress) → resolved | rejected → closed`; `closed` дан ўтиш йўқ; мижоз фақат `resolved`ни `closed`/қайта `open` (7 кун ичида) қила олади.

### 5.3 Flutter

- `lib/features/wholesale/help/` — «Ёрдам ва хизмат»: Хизмат ҳудудлари (туман рўйхати + муддат, «сизнинг туманингиз» юқорида), Ҳисоблагич (У2), FAQ, Оферта ва жавобгарлик (жорий версия + «архив» рўйхати), Мурожаатларим.
- Тикет экрани: тоифа → матн → расм(лар) → юбориш; кейин чат + ҳолат тасмаси + буюртма карточкаси + custody қадамлари (бор бўлса).
- Сотувчи рўйхатдан ўтишида оферта/жавобгарлик матни экранда, «Қабул қиламан» → `acceptWholesaleAgreement`; версия янгиланса панелда баннер.
- Матн тили: `help_articles` дан илова тили бўйича; бўш бўлса fallback `uz_Cyrl` (ва админга «тил тўлдирилмаган» белгиси).
- Админ: «Улгуржи бозор → Хизмат маркази»: мақолалар (3 тил, версия тарихи, diff), тикетлар (фильтр ҳолат/тоифа/SLA ўтган), буюртма+custody+чат бир экранда, ечим ва қайтариш тугмаси (finance).

### 5.4 Босқичлар

| Босқич | Таркиб | Боғлиқлик |
|---|---|---|
| ХМ-1 | `help_articles` + `versions`, rules, `adminUpsertHelpArticle`, админ муҳаррири (3 тил, версия), иловада FAQ/оферта/жавобгарлик кўриниши; оферта ва жавобгарлик матнининг ўзи — **эга** | — |
| ХМ-2 | `service_coverage` проекцияси + sweeper, «Хизмат ҳудудлари» экрани (муддат = relay зона → кун; туман ичи = 1 кун, PROPOSED) | relay тариф матрицаси |
| ХМ-3 | `acceptWholesaleAgreement` + рўйхатдан ўтишга қўшиш + `tier:'standard'` резерв | ХМ-1 |
| ХМ-4 | `support_tickets` + `events`, `openSupportTicket`, `adminUpdateSupportTicket`, чат боғланиши, илова тикет экрани, админ тикет панели | У3 (буюртма бўлиши керак); ХМ-1 (тоифа матнлари) |
| ХМ-5 | Қайтариш (`refund`) — У4 тўлов модели билан бирга | У4 |

ХМ-1…3 У3 дан олдин, буюртмасиз ҳам фойдали. Ҳар босқич: emulator rules тести + CF тести + Flutter тест, кейин ҳисобот; deploy — эга буйруғи билан.

---

## 6. Хавфсизлик талаблари — янгиланган

| № | Талаб | Қоида/жой |
|---|---|---|
| Х-1 | `help_articles`: ўқиш — `active == true` ҳамма учун (логинсиз ҳам, оферта очиқ ҳужжат); `versions` — фақат admin ўқийди; **ёзиш — ҳеч ким** (фақат CF) | rules + `adminUpsertHelpArticle` |
| Х-2 | Матн XSS/инъекция: markdown-lite фақат рухсат этилган белгилар (сарлавҳа, рўйхат, қалин, ҳавола `https://` фақат); иловада `Text`/оддий рендер, WebView йўқ; узунлик ≤ 20 000 белги | CF валидация + Flutter рендер |
| Х-3 | Оферта қабул қилиш — фақат ўз номидан (`isOwner`), сервер вақти, версия боғланади; эскирган версия билан товар қўшиш/буюртма — `AGREEMENT_OUTDATED` (сервер текширади, клиент эмас) | `acceptWholesaleAgreement`, `placeWholesaleOrder` |
| Х-4 | `service_coverage` — ўқиш очиқ, ёзиш фақат CF; ПВЗ `points` v1 да бўш — клиент уни кўрсатмайди | rules |
| Х-5 | Тикет очиш — фақат буюртма эгаси, сотувчиси ёки шу буюртманинг **фаол** LEG ижрочиси (server-side, `courier_auth`/relay намунаси); бошқа ҳеч ким (`orders.get` рухсати тикетга ўтмайди) | `openSupportTicket` |
| Х-6 | Тикетни ўқиш — очган томон, қарши томон (сотувчи/харидор) ва admin; **проекция**: харидор телефони/манзили сотувчига тикет орқали чиқмайди (40-банд), курьерга фақат ўз LEG маълумоти | rules + сервер проекция |
| Х-7 | Тикет ҳолати, `resolution`, `refund` — фақат CF; `refund` фақат `finance`/`superadmin` роли; пул фақат ledger (`settlement_ledger`), idempotent калит; `events` ўзгармас | `adminUpdateSupportTicket`, rules `write: false` |
| Х-8 | Расмлар `tickets/{ticketId}/…`: ёзиш — тикет очувчи, ≤ 8 МБ, image/*; ўқиш — тикет томонлари + admin (storage rules, `firestore.exists` текшируви — ресторан `restaurant_images` намунаси) | storage.rules |
| Х-9 | Спам/DoS: `openSupportTicket` — бир буюртмага бир тоифадан 10 дақиқада 1 та (idempotent калит), бир uid 20 тикет/кун; `quoteWholesaleDelivery` — 60/дақ/uid | CF лимит + counter |
| Х-10 | «Суғурта» сўзи — илова ва админ матнларида йўқ; `riskReserve` мижозга чиқмайди (`deliveryQuote.internal` проекциядан кесилади) | lint: `test/l10n` да «суғурта/sug'urta/страхов» калити таъқиқи (тест) |
| Х-11 | Жавобгарлик матни (`kind: liability`) — 3 тил тўлиқ ва `active` бўлмаса оферта қабул қилиш ва буюртма **блокланади** (`LIABILITY_TERMS_MISSING`) | CF |
| Х-12 | Observability: `module: wholesale`, `action: help_upsert | agreement_accept | ticket_open | ticket_update | coverage_rebuild`, `ticketId`, `orderId`, `result`, `errorCode`; матн/телефон log'га чиқмайди | 24-банд |
| Х-13 | Admin амаллари (`help_upsert`, тикет ечими, refund) — `admin_audit` (ким, нима, қачон, сабаб) | 41-банд |
| Х-14 | Rules тестлари: ҳар янги коллекция учун emulator тести (ўқиш/ёзиш/бегона/роль); `.get()` default list тузоғи — list қоидаларида фақат тўғридан-тўғри майдон | хотира: rules list trap |

## 7. Хавфлар

- Оферта/жавобгарлик матни ҳуқуқий ҳужжат — юрист текширувисиз `active` қилинмасин (relay §9 «блокланган» билан бир хил эҳтиёт).
- Тикет SLA (24 с) — одам ресурси; админда «SLA ўтган» фильтри бўлмаса ваъда бузилади.
- `service_coverage` муддатлари relay матрицасидан олинади — матрица фаол бўлмагунча «муддат» кўрсатилмайди (бўш эмас, «аниқланмоқда»).
- Чат ва тикет икки жойда ҳолат юритилса айрилади — ҳолатнинг манбаси фақат `support_tickets`, чат унга ҳавола.