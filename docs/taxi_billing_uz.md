# AVA TAXI — БИЗНЕС-ҚОИДАЛАР РЕЕСТРИ ВА ЖОРИЙ ЭТИШ РЕЖАСИ

> **Манба:** лойиҳа эгаси, 2026-10-06. Барча қарорлар `AVA_DECIDED`.
> **Ҳолат:** 3-бўлимдаги режа бажарилган ва деплой қилинган (2026-10-06
> кечки). Эга тузатишлари N-1…N-3 (1.6-quater) коди ёзилди ва тестланди
> (2026-10-06 кечқурун, 3.2-бўлим) — **деплой кутилмоқда**. N-4 (бошқа
> хизматлар келишув матни) — эга таҳрири кутилмоқда (2-bis).
>
> Capability модели (`provider_capabilities`, `provider_presence`,
> `provider_stats`) — [relay_delivery_architecture_uz.md](relay_delivery_architecture_uz.md)
> §9-ter. Такси billing ўша моделнинг устига қурилади, **алоҳида
> policy** сифатида.

---

## 0. ЎЗГАРТИРИЛМАЙДИГАН ФОРМУЛА

```text
AVA fee = farePerSeat × 4 × 2%
```

**AVA орқали ҳақиқатда нечта йўловчи топилгани комиссия миқдорига
ТАЪСИР ҚИЛМАЙДИ.**

```text
actual AVA passengers  !=  commission basis
```

Бу формула соддалаштирилмайди, `actual passenger count` асосига
ўзгартирилмайди ва код ёзишда айнан шу шаклда қолади.

---

## 1. ҚАРОРЛАР РЕЕСТРИ

### 1.1 Такси lifecycle

| # | Қарор | Белги |
|---|---|---|
| **D-TAXI-1** | Янги такси ҳайдовчиси админ тасдиғини КУТМАЙДИ. Сервер `taxi.status = starter` беради. `starter` — ариза эмас, **реал ишлаш ҳуқуқи**: рейс эълон қилиш, йўналиш танлаш, йўлкира белгилаш, йўловчи қабул қилиш, рейсни бажариш. Фақат `taxi` capability учун | AVA_DECIDED |
| **D-TAXI-2** | Taxi'га биринчи кирган пайтдан **4 ойлик starter даври**. Серверда `startedAt` ва `verificationDueAt = startedAt + 4 ой`. Муддат **аккаунт/UID** билан боғлиқ. Қуйидагилар муддатни ҚАЙТА БОШЛАМАЙДИ: телефон алмаштириш · logout/login · иловани қайта ўрнатиш · бошқа телефондан кириш · capability'ни ўчириб-қайта ёқиш · профилни таҳрирлаш. Бир UID учун starter даври **бир марта** | AVA_DECIDED |
| **D-TAXI-3** | Биринчи 4 ойда taxi БЕПУЛ: `taxi billing = 0`. Лекин `provider_stats` биринчи кунданоқ ишлайди: рейслар сони · бажарилган · бекор қилинган · йўловчи баҳоси · рейтинг · шикоятлар · кечикишлар | AVA_DECIDED |
| **D-TAXI-4** | 4 ой тугагач `starter → verification_required`. Кейин админ текширувидан ўтиб `verified` олинади. Модел: `starter → verification_required → verified`. `verified` АВТОМАТИК берилмайди — фақат trusted server/admin. Фойдаланувчи ўзига `verified` ёки `approved` ёзолмайди | AVA_DECIDED |
| **D-TAXI-5** | `verification_required` ҳолатида янги **пуллик** рейс эълон қилишдан олдин админ текшируви шарт. Аккаунт БЛОКЛАНМАЙДИ, бошқа capability'лар ҳам блокланмайди: `taxi = verification_required` бўлса ҳам `courier` ва `seller` ишлашда давом этади | AVA_DECIDED |

### 1.2 Пуллик модел

| # | Қарор | Белги |
|---|---|---|
| **D-TAXI-6** | Taxi billing фақат `starter` тугаган **ВА** `taxi.status = verified` бўлганда ишлайди. Модел: **ҳар бир рейс эълони учун 2%**. Ойлик subscription бу қарорга КИРМАЙДИ | AVA_DECIDED |
| **D-TAXI-7** | Ҳисоб базаси: ҳайдовчи белгилаган бир киши учун йўлкира × **4 ўрин**. `AVA fee = farePerSeat × 4 × 2%` | AVA_DECIDED |
| **D-TAXI-8** | Мисол: `350 000/киши` → база `1 400 000` → фи `28 000`. Ҳайдовчи AVA орқали 1, 2, 3 ёки 4 киши олса ҳам комиссия **28 000** | AVA_DECIDED |
| **D-TAXI-9** | `farePerSeat × 1 × 2%` каби ҳисоб **ТАҚИҚЛАНАДИ**. Қолган ўринлар бўш кетса, кўчадан олинса, Telegram орқали топилса, таниши билан кетса ҳам комиссия ЎЗГАРМАЙДИ | AVA_DECIDED |
| **D-TAXI-10** | AVA ўзидан тариф ўйлаб топмайди. Асос — ҳайдовчи эълонда кўрсатган `farePerSeat`. `250 000 → 20 000`, `400 000 → 32 000` | AVA_DECIDED |

### 1.3 Нарх манипуляциясига қарши

| # | Қарор | Белги |
|---|---|---|
| **D-TAXI-11** | Арзон нарх билан комиссия тўлаб, кейин нархни ошириб эски комиссия билан давом этиш МУМКИН ЭМАС. Тизим янги нарх бўйича қайта ҳисоблайди ва **фарқни** талаб қилади: `200 000` да `16 000` тўланган, `350 000` га кўтарилса янгиси `28 000`, қўшимча `12 000`. Тўламаса эълон янги нарх билан актив БЎЛМАЙДИ | AVA_DECIDED |
| **D-TAXI-12** | Нарх пасайтирилганда комиссия камайиши мумкин, лекин бу abuse'га айланмасин. Ҳар бир нарх ўзгариши audit log'да: `oldFare` `newFare` `changedAt` `tripId` `uid`. Refund policy server-side. Кўтариб-тушириш орқали комиссиядан қочиш мумкин бўлмасин | AVA_DECIDED |
| **D-TAXI-13** | Комиссия рейс ЯКУНЛАНГАНДА эмас, **publish'дан ОЛДИН**. Оқим: йўналиш → йўлкира → AVA 2% ҳисоблайди → ҳайдовчи кўради → тўлов → кейин publish. Тўловсиз рейс `published` БЎЛМАЙДИ | AVA_DECIDED |

### 1.4 Location ва anti-fraud

| # | Қарор | Белги |
|---|---|---|
| **D-TAXI-14** | Рейс яратишда ҳайдовчи location'и server-side қайд этилсин: `originDeclared` `originResolved` `driverLat` `driverLng` `locationAccuracy` `locationCapturedAt`. Мақсад — сохта origin, арзонроқ йўналиш кўрсатиш, бошқа шаҳардан рейс қилиб кўрсатиш. ЛЕКИН текширув ақлли бўлсин: эртанги рейсни олдиндан эълон қилиш нормал. `location mismatch` автоматик fraud ЭМАС — масофа, рейс вақти, жорий вақт, йўналиш ва аввалги ҳаракатлар бўйича текширилсин, шубҳали ҳолат audit event бўлсин | AVA_DECIDED |
| **D-TAXI-15** | Рейс ҳақиқатан бекор қилинса (`trip.status = cancelled`) тўланган комиссия **driver AVA wallet**'га қайтарилади. Банк картага автоматик қайтариш шарт эмас — wallet'да `refund` сифатида кўринади | AVA_DECIDED |
| **D-TAXI-16** | Ёлғон отмена хавфи: рейс эълон қилиб, AVA'дан йўловчи олиб, комиссия тўлаб, йўлга чиқиб, кейин атайлаб `cancelled` қилиб комиссияни қайтариб олиш. Бунга anti-fraud механизми бўлсин | AVA_DECIDED |
| **D-TAXI-17** | Аниқлаш сигналлари: cancel location · кейинги location · вақт · масофа · йўналиш · кейинги рейс origin/destination · GPS ҳаракат · AVA booking мавжудлиги. Мисол: `Урганч → Тошкент` cancel қилинди, бир неча соатдан кейин `Тошкент → Урганч` эълон қилинди ва GPS Тошкентни кўрсатяпти | AVA_DECIDED |
| **D-TAXI-18** | Fraud қоидаси етарлича ишонч билан рейс бажарилганини аниқласа, refund қилинган комиссия `driver wallet → AVA` қайта ўтказилади ва ҳайдовчига АНИҚ хабар берилади | AVA_DECIDED |
| **D-TAXI-19** | Fraud текшируви ЭҲТИЁТКОР: битта GPS нуқтасига қараб жазоланмайди. False positive сабаблари: бошқа машинада кетган · GPS хато қилган · рейс ҳақиқатан бекор бўлган · кейин бошқа иш билан борган. Configurable threshold, ҳолатлар: `normal` `suspicious` `confirmed` `manual_review`. Пулни қайтариб олиш учун **sufficient evidence** шарт | AVA_DECIDED |

### 1.5 Billing техник қоидалари

| # | Қарор | Белги |
|---|---|---|
| **D-TAXI-20** | Бир рейс учун комиссия БИР МАРТА. Billing идемпотент: `billingKey = tripId + billingVersion` ёки тенг server-controlled механизм. Retry `double charge` қилмасин | AVA_DECIDED |
| **D-TAXI-21** | Publish'да billing snapshot сақлансин: `tripId` `driverUid` `farePerSeat` `seatBasis = 4` `rate = 0.02` `grossBasis` `feeAmount` `chargedAt` `billingVersion` | AVA_DECIDED |
| **D-TAXI-22** | Ҳайдовчи тасдиқлашдан олдин комиссияни КЎРСИН: «AVA хизмат ҳақи: 28 000 сўм», тугма «28 000 сўм тўлаб рейсни эълон қилиш» | AVA_DECIDED |
| **D-TAXI-23** | Wallet'да маблағ етмаса рейс `draft` ёки `payment_required` ҳолатида қолади. Комиссия тўланмагунча `published` қилинмайди | AVA_DECIDED |
| **D-TAXI-24** | Taxi'ни биринчи марта ёққанда **Taxi Service Agreement** қабул қилиш шарт. Ичида очиқ ёзилсин: 4 ой starter · бу даврда billing йўқ · кейин admin verification · кейин ҳар рейс учун 2% · 2% `fare × 4` дан · AVA орқали нечта йўловчи топилгани таъсир қилмаслиги · publish'дан олдин тўлов · нарх ошса қўшимча комиссия · cancellation refund · fraud бўлса refund қайтариб олиниши · location anti-fraud. Серверда: `serviceType = taxi` `agreementVersion` `acceptedAt` `acceptedByUid` | AVA_DECIDED |

### 1.6 Бошқа хизматлар

| # | Қарор | Белги |
|---|---|---|
| **D-SERVICE-0** | Taxi учун белгиланган 4 ой starter · admin verification · 2% billing · 4 ўринлик база · taxi anti-fraud billing қоидалари `courier` `seller` `freight` ва бошқа хизматларга **АВТОМАТИК ТАТБИҚ ЭТИЛМАЙДИ** | AVA_DECIDED |
| **D-SERVICE-1** | Бошқа provider хизматларида: хизматни ўзи ёқади → agreement'ни қабул қилади → ишни бошлайди. Admin approval кутиш шарт эмас, агар ўша хизмат учун алоҳида бизнес-қоида қабул қилинмаган бўлса | AVA_DECIDED |
| **D-SERVICE-2** | Ҳар бир хизмат учун АЛОҲИДА agreement: Taxi · Courier · Seller · Freight. Қабул қилиш серверда: `serviceType` `agreementVersion` `acceptedAt` `acceptedByUid` | AVA_DECIDED |
| **D-SERVICE-3** | Бир user'да бир нечта capability мустақил: `taxi = verification_required`, `courier = active`, `seller = active` бўлса taxi чекланиши courier ёки seller'ни БЛОКЛАМАЙДИ | AVA_DECIDED |
| **D-SERVICE-4** | `taxi` `courier` `seller` `freight` ҳеч қачон `users.role` сифатида ишлатилмайди — улар `provider_capabilities` ичида. `users.role` фақат platform-level: `user` `admin` `superadmin` `staff` | AVA_DECIDED |

### 1.6-bis Бекор қилиш, кейинга суриш ва сохта отмена (2026-10-06, кечки)

| # | Қарор | Белги |
|---|---|---|
| **D-TAXI-CANCEL-1** | Рейсни ҲАҚИҚИЙ бекор қилиш мумкин (режа ўзгарди, эртага кетади, кечиктиради, машина, шахсий сабаб, йўл). Ҳар қандай `cancel` fraud ЭМАС. Бекор → `cancelled`, комиссия wallet'га refund, сумма ҳамёнда қолади ва кейинги рейс учун ишлатилади | AVA_DECIDED |
| **D-TAXI-CANCEL-2** | Бекордан кейин эртасига, 2 кун, 5 кун ёки бошқа санада, худди шу ёки бошқа йўналишда янги рейс эълон қилиш — ЎЗ-ЎЗИДАН сохта отмена далили ЭМАС. Автоматик fraud белгиланмасин | AVA_DECIDED |
| **D-TAXI-CANCEL-3** | **Reschedule — алоҳида функция.** `tripId` сақланади, комиссия refund қилинмайди ва қайта олинмайди, фақат departure date/time ўзгаради. Нарх ўзгармаса billing ўзгармайди; ошса фақат фарқ (350k→400k: 28 000→32 000, +4 000) | AVA_DECIDED |
| **D-TAXI-CANCEL-4** | Сохта отмена фақат ЕТАРЛИ ДАЛИЛ билан `fraudStatus = confirmed`: GPS ҳаракат · cancel вақтидаги location · кейинги location · йўналиш ҳаракати · AVA booking · кейинги рейс origin/destination · вақт/масофа · бошқа мустақил сигналлар. Бир дона GPS нуқтаси ёки кейин янги рейс эълон қилингани ЎЗИ fraud эмас | AVA_DECIDED |
| **D-TAXI-CANCEL-5** | Fraud `confirmed` → аввал refund қилинган комиссия қайта AVA ҳисобига. Ҳайдовчига аниқ хабар («…тизим текшируви рейс амалга оширилганини тасдиқлади…») | AVA_DECIDED |
| **D-TAXI-CANCEL-6** | Reclaim'да wallet етмаса комиссия ЙЎҚОЛМАСИН: `outstandingTaxiFee` / мавжуд ledger'га мос қарз ёзуви. Кейинги top-up, тушум ёки комиссия учун киритилган маблағдан АВВАЛ шу қарз ёпилади. Иккинчи ledger ЙЎҚ | AVA_DECIDED |
| **D-TAXI-CANCEL-7** | Anti-fraud эҳтиёткор: `normal` `suspicious` `manual_review` `confirmed`. Фақат `confirmed`да пул ечилади; `suspicious`/`manual_review`да автоматик ечилмайди | AVA_DECIDED |
| **D-TAXI-CANCEL-8** | Учта ҳолат қатъий ажратилади: RESCHEDULE (рейс+комиссия сақланади, сана ўзгаради) · CANCEL (бекор, refund) · FALSE CANCEL CONFIRMED (refund қайта ечилади). **Кейин яна рейс эълон қилиш ёки сафарни кечиктириш ўз-ўзидан fraud эмас** | AVA_DECIDED |

### 1.6-ter Тоза старт (2026-10-06, кечки)

| # | Қарор | Белги |
|---|---|---|
| **D-CLEAN-1** | Эски илова версиялари ва мавжуд ҳайдовчилар — ТЕСТ маълумотлари. Backward compatibility ва migration ТАЛАБ ҚИЛИНМАЙДИ. Зарур бўлса эски test driver/user/provider маълумотларини тозалаш мумкин. Янги taxi/provider архитектураси тоза ҳолатдан ишга тушади; янги ҳайдовчилар фақат янги lifecycle, agreement, verification ва billing билан. Legacy `couriers`, `users.role == courier/taxi`, эски client-side publish flow ва шунга ўхшаш fallback'лар сақланмайди | AVA_DECIDED |

### 1.6-quater Эга тузатишлари (2026-10-06, кечқурун) — ✅ КОД ЁЗИЛДИ (деплой кутилмоқда, 3.2)

| # | Қарор | Кодда нима ўзгаради | Белги |
|---|---|---|---|
| **D-TAXI-24.1** | Taxi Service Agreement ҳайдовчи ишга тушганда ЭМАС — **4 ой ўтгач тизим автоматик тақдим қилади** (starter тугаб `verification_required`га ўтганда). Starter учун келишув шарт эмас | `AGREEMENT_GATED.taxi = false` (requestCapability'да дарвоза йўқ); `capabilitySweeper` starter→verification_required қилганда `agreementPending: taxi` белгиси + ҳайдовчига хабар/варақ; `quoteTaxiFee`/`publishTaxiTrip` ва админ `verified` қилишдан олдин келишув текширилади (ҳозирги publish-даги текширув қолади). `ensureTaxiCapability` UI оқимидан келишув варағи олиб ташланади; у `verification_required` ҳолатида кўрсатилади | AVA_DECIDED |
| **D-TAXI-6.1** | Billing **глобал флаг билан эмас**, ҳар бир ҳайдовчи учун 4 ой ўтиши билан (verified бўлгач) **автоматик очилади** | `module_config/global.taxiBillingEnabled` флаги ОЛИБ ТАШЛАНАДИ (ёки доим `true`); `billable = isTaxiBillable(cap, now)` ягона мезон (verified + grace). `billingMode: 'shadow'` йўқолади — fee'сиз starter бекорлари fraud shadow маълумотини беришда давом этади | AVA_DECIDED |
| **D-TAXI-CANCEL-9** | «Жўнашдан 2 соат кейин бекор = тугаган, refund йўқ» қоидаси **БЕКОР**. Жўнашдан кейин ҳам бекор қилиш мумкин ва refund берилади — йўловчи ўз вақтида топилмай қолиши мумкин. Сохта отмена фақат fraud далиллари билан (CANCEL-4…7) | `cancelTaxiTrip`да `CANCEL_AFTER_DEPARTURE_GRACE_H` блоки ва `late_cancel` сигналининг оғирлиги қайта кўрилади (late_cancel — тасдиқловчи сигнал сифатида қолиши мумкин, лекин бекорни тақиқламайди); CF тести «jo'nashdan 2 soat keyin → completed» ТЕСКАРИСИГА ёзилади | AVA_DECIDED |
| **D-SERVICE-2.1** | Бошқа хизматлар учун келишув матнлари — таклиф киритилсин (2-bis бўлим) | Матн тасдиқлангач `AGREEMENT_GATED[service]` ва локал калитлар | PROPOSED |

**Бажарилгани (2026-10-06 кечқурун, кейинги сессия):**

| Қарор | Код |
|---|---|
| D-TAXI-24.1 | `core/capabilities.js`: `AGREEMENT_GATED.taxi = false`; янги `AGREEMENT_DUE_STATUSES.taxi = [verification_required, verified]` + `agreementDue(service, status)`. `requestCapability`: starter келишувсиз; ишлаётган ҳолатда `agreementDue` бўлса ва келишув йўқ бўлса жавобда `agreementRequired: true, agreementVersion` (информацион, ҳуқуқ ўзгармайди). `capabilitySweeper`: starter→verification_required'да келишув йўқ бўлса `window.taxi.agreementRequestedAt` (сервер калити, қоида ўзгармади) + `admin_news` inbox хабари (детерминистик ID `taxiVerificationDue_{accountId}` — дубликат йўқ) + FCM push (`users/{id}/fcm_tokens`, fallback `fcmToken`). `adminSetCapabilityStatus`: `verified` (пуллик ҳуқуқ) фақат келишув қабул қилингандан кейин, акс ҳолда `agreement_required`; `suspended`/`verification_required` келишувсиз ҳам. `quoteTaxiFee`/`publishTaxiTrip`: starter — келишув текширилмайди; `verification_required` жавобида `agreementRequired` ҳам келади (илова варақни тақдим қилади, кейин админ кутилади); `verified` — келишувсиз пуллик эълон йўқ (аввалги текширув қолди). Flutter: `ensureTaxiCapability` дарвозасиз, сервер `agreementRequired` деса варақни тақдим қилади (рад этилса ҳам ишлайди); `intercity_taxi_screen` approved йўлда `verification_required` бўлса варақ (`DriverRepository.taxiAccess`, қўшимча ўқишсиз); quick start quote'да `agreementRequired` бўйича. `admin_news` матни — PROPOSED, uz_Latn (сервер матнлари шундай) |
| D-TAXI-6.1 | `taxi_billing.js`: `billingEnabled()`/`module_config/global.taxiBillingEnabled` ва `billingMode` ОЛИБ ТАШЛАНДИ; `billable = caps.isTaxiBillable(cap, now)` ягона мезон. Starter/grace'да fee 0, snapshot (`quotedFee`) ва fraud баҳолаш ишлайди. Dart `TaxiFeeQuote.billingMode` → йўқ, `agreementRequired` қўшилди. `module_config/global.taxiBillingEnabled` ҳужжати продакшнда қолса ҳам ЎҚИЛМАЙДИ |
| D-TAXI-CANCEL-9 | `cancelTaxiTrip`: `CANCEL_AFTER_DEPARTURE_GRACE_H` блоки ўчирилди — жўнашдан кейин ҳам `cancelled` + refund (idempotent). CF тести тескарисига: «3 соат кейин бекор → cancelled + refund» + «далилсиз → keyingi e'londa normal». `taxi_fraud.js`: `late_cancel` сигнал сифатида ҚОЛАДИ, лекин `confirmed` (автоматик пул ечиш) учун САНАЛМАЙДИ — фақат `manual_review`га олиб келади (**INFERRED** — CANCEL-9 «late_cancel оғирлиги қайта кўрилади»дан; эга бошқача хоҳласа `strong` ҳисобидан `late_cancel` истисноси олиб ташланади) |

### 1.7 Якуний архитектура принципи

```text
users                  → бу ким?
provider_capabilities  → қандай хизматларни қилади?
provider_presence      → ҳозир онлайнми ва қаерда?
provider_stats         → қандай ишлаяпти?
service_agreements     → қайси хизмат шартларини қабул қилган?
taxi_billing           → taxi'нинг алоҳида 2% ҳисоб-китоби
wallet                 → комиссия ва refund ҳаракатлари
```

Taxi billing бошқа capability'лардан **алоҳида policy**.

---

## 2. МАВЖУД КОД БИЛАН ЗИДДИЯТЛАР ВА ОЧИҚ САВОЛЛАР

> Булар код ёзишдан ОЛДИН ҳал қилиниши керак (CLAUDE.md 1, 3, 50-банд).
> Ҳар бири учун ўлчов ёки код ҳаволаси келтирилган — тахмин эмас.

### ✅ ЭГА ҚАРОРЛАРИ — 2026-10-06

| # | Қарор | Белги |
|---|---|---|
| **T-1** | **T-1a** — барқарор `accountId` ҲОЗИР киритилади (0 ҳужжат пайтида). `users/{phoneId}.accountId` — сервер беради, ўзгармас; `provider_capabilities` шу калит билан. Starter даври `accountId`га боғланади | AVA_DECIDED |
| **T-2** | Ҳар бир хизматнинг lifecycle'и АЛОҲИДА (`LIFECYCLES[service]`) | AVA_DECIDED |
| **T-3** | `active` = фойдаланувчининг ХОҲИШИ; `status` = ҲУҚУҚИЙ ҳолат. Иккиси аралашмайди | AVA_DECIDED |
| **T-4** | Комиссияни **сервер**, **бутун сўмда** ҳисоблайди. Яқинлаштириш: юқорига бутун сўмгача (`ceil`), чунки AVA ўзига зарар қилмайди ва фарқ ≤ 1 сўм | AVA_DECIDED |
| **T-5** | Биринчи версияда 2% **фақат шаҳарлараро** (`intercity`) такси. `marshrut` ва `local` — алоҳида қарор | AVA_DECIDED |
| **T-6** | Мавжуд тасдиқланган ҳайдовчилар `starter`га ТУШИРИЛМАЙДИ: улар `verified` бўлиб қолади, лекин **4 ойлик billing grace** олади (`billingGraceUntil = миграция + 4 ой`). Billing фақат `verified` **ва** grace тугагандан кейин | AVA_DECIDED |

**T-1a чегараси (INFERRED, эга тасдиғи керак эмас — бажарилишидан
келиб чиқади):** `accountId` ҳозир `provider_capabilities` калити
бўлади (starter, verification, billing grace шу ерда). `provider_presence`
(вақтинчалик онлайн ҳолат), `demand_matches`, `provider_stats` ва trust
ядро ичида канон телефон билан қолади — capability ҳужжати ичида
сервер ёзадиган `identity.primaryUid` орқали боғланади. Сабаб: ядронинг
бутун кимлик қатламини (matchKey, offers, trust) бир йўла алмаштириш
деплой қилинган ядрони беқарор қилади; starter даврини сақлаш учун эса
capability калитининг ўзи етарли. Телефон алмашганда клиент
қоидасидаги `isOwner` муаммоси (`changeDevicePhone` ҳужжат калитини
кўчирмайди) — АЛОҲИДА, аввалдан мавжуд масала, шу ерда ҳал қилинмайди.

### T-1 — UID барқарорлиги. ЭНГ МУҲИМ ЗИДДИЯТ

D-TAXI-2: «муддат аккаунт/UID билан боғлиқ бўлсин, телефон
алмаштириш уни қайта бошламасин».

**Муаммо:** AVA'да фойдаланувчи ID = **телефон рақами**
(`users/{998XXXXXXXXX}`), ва `provider_capabilities` ҳам шу калит
билан. Телефон алмашса — калит ҳам алмашади.

Бундан ҳам ёмони: `changeDevicePhone` ([functions/index.js:6286](../functions/index.js))
ҳужжат ичидаги `phone` МАЙДОНИНИ янгилайди, лекин **ҳужжат
калитини кўчирмайди**:

```javascript
// users/{998OLD} ҳужжати қолади, ичида phone: 998NEW
t.update(userQuery.docs[0].ref, { phone: newPhone, ... });
```

Қоида эса `isOwner(uid)` ни **калит** бўйича текширади
(`userDocIdFromPhoneToken()`). Яъни телефон алмашгандан кейин:

- токенда `998NEW`, ҳужжат калити `998OLD` → одам ўз ҳужжатига
  кира олмайди;
- `provider_capabilities/{998NEW}` **янги, бўш** ҳужжат бўлади →
  starter даври **қайта бошланади**, бу D-TAXI-2 га тўғридан-тўғри зид.

**Иккита йўл — эга ҳал қилади:**

- **T-1a. Барқарор ички `providerId`.** `users` ҳужжатига ўзгармас
  `providerId` (масалан `prv_<random>`) берилади,
  `provider_capabilities` калити шу бўлади. Устуни: телефон, қурилма
  ва ҳатто ҳужжат калити ўзгарса ҳам starter даври сақланади — D-TAXI-2
  тўлиқ бажарилади. Хавфи: `isOwner(uid)` телефонга таянади, яъни
  қоида `providerId → телефон` мосligini текшириш учун қўшимча
  `get()` қилади (ҳар ёзувда 1 ўқиш), ва мавжуд барча
  `provider_*` калитлари миграция қилинади (ҳозир presence 0,
  capabilities 0 — яъни ҳозир АРЗОН, кейин қиммат).
- **T-1b. Телефон алмашганда миграция.** `changeDevicePhone` ичида
  `provider_capabilities`, `provider_presence`, `provider_stats`
  ҳужжатлари янги калитга кўчирилади ва `provider_aliases/{old}` →
  `{new}` занжири сақланади. Устуни: мавжуд архитектура сақланади,
  diff кичик. Хавфи: кўчириш атомар бўлиши керак, ва занжир узилса
  starter даври йўқолади.

**Тавсиям: T-1a**, фақат ҳозир — чунки иккала коллекцияда ҳам 0 ҳужжат
(2026-10-06 ўлчови), яъни миграция бугун текин. Кейинроқ бу иш
минглаб ҳужжатни кўчиришни талаб қилади.

### T-2 — Lifecycle хизматга қараб ФАРҚ ҚИЛАДИ

`core/capabilities.js` да ҳозир БИТТА status enum ва БИТТА transition
жадвали бор (курьер учун: `trial → trial_expired → … → approved`).
Такси эса бошқа: `starter → verification_required → verified`.

Яъни модел **хизмат бўйича lifecycle**га ажратилиши керак:

```text
STATUS_BY_SERVICE = {
  taxi:    starter → verification_required → verified (+ suspended)
  courier: trial → trial_expired → document_submitted → under_review
           → approved (+ document_rejected, suspended)
  seller/freight: D-SERVICE-1 бўйича оддий (enabled → active)
}
```

`WORKING_STATUSES` ҳам хизмат бўйича бўлади: такси учун `starter` ва
`verified` ишлайди, `verification_required` эса **фақат пуллик янги
рейсни** тўхтатади (D-TAXI-5) — яъни «ишлаш» тушунчасининг ўзи
такси учун иккига бўлинади:

```text
canPublishPaidTrip()   — verification_required да YO'Q
canOperate()           — мавжуд рейсни бажариш, ҳамон ҲА
```

### T-3 — `status = active` номи

D-TAXI-5 ва D-SERVICE-3 да `courier.status = active` деб ёзилган.
Ҳозирги моделда `active` — **status эмас**, балки хоҳиш белгиси
(`courier.active: true` = «ҳозир сўров олмоқчиман»), ҳуқуқ эса
`status: approved`.

**Савол:** `active` статус сифатида қўшилсинми, ёки D-SERVICE-1
хизматлари учун `status = active` ва курьер учун `approved` деб
аталсинми? **Тавсиям:** `status` қийматлари хизмат lifecycle'идан
олинсин (T-2), ва `active` фақат хоҳиш белгиси бўлиб қолсин — акс
ҳолда битта сўз иккита маънони ташийди (17-қоида).

### T-4 — Яқинлаштириш (rounding) қоидаси ЙЎҚ

`farePerSeat × 4 × 0.02` ҳар доим бутун сон бермайди:

| farePerSeat | база | 2% |
|---|---|---|
| 350 000 | 1 400 000 | 28 000 ✅ |
| 333 333 | 1 333 332 | 26 666.64 ❌ |
| 275 000 | 1 100 000 | 22 000 ✅ |

8-қоида: пул ҳеч қачон float бўлмайди. Шунинг учун яқинлаштириш
қоидаси КЕРАК. Вариантлар: юқорига 100 сўмгача · юқорига 1000 сўмгача ·
`round half up` бутун сўмгача · ёки `farePerSeat` ни 1000 сўмга
каррали қилиб чеклаш.

**Тавсиям:** `feeAmount = ceil(farePerSeat × 4 × 2 / 100)` — бутун
сўмгача юқорига. Сабаб: AVA ҳеч қачон ўзига зарар қилмайди, ва фарқ
энг кўпи 1 сўм. Эга бошқа вариантни танласа — шу жойда қайд этилади.

### T-5 — Такси туридан қайси бири? (4 ўрин базаси)

`farePerSeat × 4` — бу **енгил автомобиль** (седан) мантиғи. Репода
учта такси тури бор: `intercity` · `marshrut` (микроавтобус, 7+ ўрин) ·
`local`/`alone` (шаҳар ичи, ўрин тушунчаси йўқ).

**Савол:** D-TAXI қоидалари қайси турларга тегишли? Фақат
`intercity`ми, ёки `marshrut` ҳам (унда база 4 эмас)? Шаҳар ичи
таксида «рейс эълони» умуман йўқ.

**Тавсиям:** биринчи версияда ФАҚАТ `intercity`. `marshrut` ва
`local` учун алоҳида қарор.

### T-6 — Мавжуд тасдиқланган ҳайдовчилар нима бўлади?

Репода такси учун АЛЛАҚАЧОН админ тасдиғи бор:
`drivers.approved` + `taxiTypes` ([firestore.rules:353](../firestore.rules)
→ `approvedDriverForTaxi`), ариза оқими `driver_requests`, тасдиқлаш
CF'да ([functions/index.js:8431](../functions/index.js)).

**Савол:** ҳозир тасдиқланган ҳайдовчилар миграцияда:

- **(а)** тўғридан-тўғри `verified` бўладими — унда улар ЭРТАГАДАН
  2% тўлай бошлайди;
- **(б)** ёки уларга ҳам 4 ойлик starter бериладими (муддат
  миграция кунидан бошланади);
- **(в)** ёки `verified` + billing бошланиш санаси алоҳида
  белгиланадими.

Бу — пул масаласи, шунинг учун эга қарори. **Тавсиям: (б)** — мавжуд
ҳайдовчилар ҳам 4 ой бепул ишлайди ва шу вақт ичида AVA billing
оқимини ҳақиқий трафикда синаб кўради.

### T-7 — Пул қатлами: мавжудини ишлатиш

43-қоида: янги пул тизими қурилмайди. Репода бор: `wallet_ledger` ·
`wallet_idempotency` · `functions/settlement_ledger.js` (икки ёзувли,
`journal_entries` append-only, Σdebit == Σcredit).

Шунинг учун `taxi_billing` **иккинчи ledger ЭМАС**, балки
D-TAXI-21 даги snapshot ва audit ёзуви бўлади; ҳақиқий пул ҳаракати
мавжуд ledger орқали кетади. `billingKey = tripId + billingVersion`
эса мавжуд `wallet_idempotency` механизмига мос келади (D-TAXI-20).

**Текширилди (CONFIRMED):** `settlement_ledger.js` умумий икки ёзувли
`postEntry(db, {idempotencyKey, legs: [{account, dr|cr}]})` беради,
ҳисоб турлари ичида `driver_float:{uid}` (ҳайдовчи баланси, liability)
ва `earnings` (AVA даромади) бор, миқдорлар `isPositiveInt` билан
**фақат бутун сон**. Яъни 2% ечиш = `driver_float:{uid}` debit +
`earnings:taxi` credit, `idempotencyKey = tripId + billingVersion`.
Янги пул тизими КЕРАК ЭМАС — T-7 ёпилди.

### T-8 — Рейс «publish» объекти қайси?

D-TAXI-13: тўловсиз рейс `published` бўлмасин. `intercity_trips`
қоидаси аллақачон `allow create, update, delete: if false` — яъни
рейсни фақат CF яратади. Бу тўғри томон.

**Текширилди (CONFIRMED):** интершаҳар «рейс эълони» — бу
`intercity_drivers/{phone}` ҳужжатида `isOnPanel: true` + `price`
(бир киши учун йўлкира). Иккала майдонни ҳозир **КЛИЕНТ ЁЗАДИ**
(`intercity_driver_panel_controller.dart:162`), бронь CF'и эса
`driver.price`ни `pricePerSeat` сифатида ўқийди
(`functions/index.js:9974`) ва кўрсатилган нарх билан солиштиради
(`:9981`). `intercity_trips`ни CF ҳам яратмайди — у бронь объекти.

**Оқибати (D-TAXI-13):** «панелга чиқиш» = publish, яъни
`isOnPanel: true` ва `price` ёзуви **клиентдан олиб ташланиб**
`publishTaxiTrip` callable'ига ўтади (фи → wallet → ечиш → панелга
чиқариш). Нарх ўзгариши ҳам шу йўлдан (D-TAXI-11). `intercity_drivers`
қоидасида `isOnPanel`/`price` клиент учун ёпилади. Бу — иловадаги
мавжуд ҳайдовчи панелини ўзгартиради, яъни янги илова версияси керак
ва эски версия ўтиш даврида панелга чиқа олмай қолади — буни
босқичма-босқич (feature flag, 42-қоида) қилиш керак.

---

## 2-bis. БОШҚА ХИЗМАТЛАР КЕЛИШУВИ — ТАКЛИФ (D-SERVICE-2.1)

> **PROPOSED.** Фақат репода аллақачон ҚАРОР бўлган қоидалардан тузилган
> (D-15, D-15.1, D-14, presence/GPS, trust events, admin suspension) —
> янги бизнес қоида ўйлаб топилмаган. Ҳуқуқий матн эмас, бандлар
> рўйхати: эга таҳрирлайди, кейин `AGREEMENT_GATED[service] = true`
> ва локал калитлар (`<service>_agreement_p1…`, 3 тил).

**Умумий (ҳамма provider хизматлари учун, 1-банд сифатида):**
1. Мен мустақил ижрочиман; AVA — буюртмачи билан мени боғловчи платформа.
2. Хизматни ўзим ёқаман/ўчираман (`active`); ҳуқуқий ҳолатни (`status`) фақат AVA бошқаради.
3. Онлайн пайтимда жойлашувим (GPS) AVA'га юборилади ва буюртмачига масофа/вақт сифатида кўрсатилади; офлайн бўлганда юборилмайди.
4. Бажарган ишларим, баҳолар, шикоятлар ва бекор қилишлар ҳисобга олинади (`provider_stats`, trust); такроран шикоят ёки қоидабузарликда AVA хизматни тўхтатиши мумкин (`suspended`), аккаунтим эса очиқ қолади.
5. Буюртмачи маълумотлари (телефон, манзил) фақат шу иш учун; уни бошқа мақсадда сақламайман ва тарқатмайман.

**Courier (D-15, D-15.1):**
6. Биринчи 3 кун — синов; шу муддатда ягона дарча орқали ўзини ўзи банд қилган шахс сифатида рўйхатдан ўтиб, тасдиқловчи ҳужжат нусхасини юклайман.
7. Улгурмасам — бир марта 5 кун қўшимча муддат; у ҳам ўтса янги буюртма олиш тўхтайди, ҳужжат тасдиқлангач қайта очилади.
8. Қабул қилган жўнатмам учун топширгунимча жавобгарман; ҳар қабул/топшириш қайд этилади (custody).

**Seller (ulgurji/do'kon):**
6. Эълонларим ҳақиқий товар ва нархни кўрсатади; ёлғон эълон модерацияда олиб ташланади.
7. Буюртмачи шикоятида AVA эълонни/хизматни тўхтатиши мумкин.

**Freight (yuk):**
6. Транспорт сиғими ва турини тўғри кўрсатаман; юкни топширгунимча жавобгарман.
7. (Шаҳарлараро юк учун) билдирилган маршрут ва вақтга амал қиламан; бекор қилишлар ҳисобга олинади.

**Service (usta):**
6. Малакам ва йўналишларимни тўғри кўрсатаман; таклиф берган нархим буюртмачи учун мажбурий таклиф ҳисобланади (`offer`).
7. Қабул қилинган ишни бекор қилсам, талаб қайта очилади ва бу trust'га таъсир қилади.

**Эгадан керак:** бандлар матни, қайси хизматда қайси бандлар, 3 тилда расмий ифода. Шундан кейин код: `AGREEMENT_GATED` + локал калитлар + умумий `ServiceAgreementSheet` (ҳозирги `TaxiAgreementSheet` xizmat параметрли бўлади).

## 3. ЖОРИЙ ЭТИШ РЕЖАСИ — ТАКЛИФ

Босқичлар T-1…T-8 жавобларига боғлиқ. Ҳар бири тест билан ва
алоҳида деплой билан.

| # | Босқич | Боғлиқлик |
|---|---|---|
| **1** | ✅ **БАЖАРИЛДИ (2026-10-06, деплой қилинди)** — `core/capabilities.js` → `LIFECYCLES[service]`: такси `starter → verification_required → verified` (4 ой, `addMonths` ой охирига қисқартириб), курьер (3к + 5к grace), оддийлар `enabled`. `isWorking()` ≠ `canPublishPaid()` (D-TAXI-5), `isTaxiBillable()` (D-TAXI-6 + T-6 grace). Модел 26, API 15 тест | — |
| **2** | ✅ **БАЖАРИЛДИ (2026-10-06, деплой қилинди)** — `users/{phone}.accountId` (сервер, `ensureAccountId` транзакцияда, 9/12 хонали калитлар), `provider_capabilities/{accountId}`, `identity.primaryUid`. Қоида: клиент `accountId`ни ёза/ўзгартира олмайди, capability ҳужжатини яратолмайди (фақат сервер), эгалик `isCapabilityOwner` орқали. 27 қоида текшируви | — |
| **3** | ✅ `service_agreements/{accountId}` + `acceptServiceAgreement` (demand codebase). Фақат жорий версия (`AGREEMENT_VERSIONS`, иккала codebase'да бир хил — нусха паритети), идемпотент | — |
| **4** | ✅ `requestCapability` taxi учун `starter` + `window.taxi.startedAt/verificationDueAt` (4 ой, бир марта); `capabilitySweeper` → `verification_required`, grace йўқ | — |
| **5** | ✅ `adminSetCapabilityStatus` (`canTransition(..., 'admin')`, `capability_audit` append-only) + `adminMigrateTaxiDrivers` (T-6, `dryRun` стандарт true). **Продакшнда ҳали ИШГА ТУШИРИЛМАГАН** — эга буйруғи билан аввал dryRun | эга |
| **6** | ✅ `functions/taxi_billing.js` → `calculateTaxiFee`: `ceil(farePerSeat × 4 × 200 / 10000)`, фақат `number`, snapshot (D-TAXI-21), `taxiFee:{tripId}:v{n}` идемпотентлик, пул `settlement_ledger.postEntry` орқали (`passenger_credit:{uid}` → `earnings:ava_taxi_fee`) | — |
| **7** | ✅ `quoteTaxiFee` + `publishTaxiTrip`: ҳуқуқ (`canPublishPaid`) → келишув (фақат `agreementDue` ҳолатларда, D-TAXI-24.1) → фи → wallet `assert` → `published`; етмаса `payment_required`. ~~`module_config/global.taxiBillingEnabled` флаги~~ — **ОЛИБ ТАШЛАНДИ (D-TAXI-6.1)**: billing ҳар ҳайдовчи учун `isTaxiBillable` билан автоматик | — |
| **8** | ✅ `repriceTaxiTrip`: ошса фарқ, тўламаса `repriceStatus: payment_required`; пасайса **бир марта** refund (`MAX_DOWNWARD_REFUNDS = 1`), ҳар ўзгариш `taxi_price_changes`да | — |
| **9** | ✅ Location snapshot'да; `evaluateOriginMismatch` — узоқ **ва** жўнаш яқин бўлсагина `taxi_fraud_cases` (signal, hukm emas) | — |
| **10** | ✅ `cancelTaxiTrip`: refund `taxiRefund:{tripId}:v{n}`; ~~жўнашдан 2 соатдан кейин «бекор» = `completed`, refund йўқ~~ — **БЕКОР (D-TAXI-CANCEL-9)**: жўнашдан кейин ҳам `cancelled` + refund | — |
| **11** | ✅ `taxi_fraud.js` — 5 сигнал, конфиг чегаралар (`module_config/taxi_fraud`), `confirmed` учун ≥3 мустақил сигнал **ва** joylashuv; faqat `confirmed`да reclaim (`taxiReclaim:{tripId}`) + `notifyUserInApp` xabari; `suspicious`/`manual_review` — фақат ёзув | — |
| **12** | ✅ `intercity_quick_start_sheet`: quote → келишув варағи (`TaxiAgreementSheet`) → «N сўм тўлаб рейсни эълон қилиш» → publish → шундан кейин `registerDriverSchedule(billingTripId)`. `endTripListing` → `cancelTaxiTrip`. 19 калит × 3 тил | — |

### 3.0 D-TAXI-CANCEL-1…8 ва D-CLEAN-1 — бажарилгани (2026-10-06, кечки)

| Қоида | Код |
|---|---|
| CANCEL-1/2 | `taxi_fraud.js` қайта ёзилди: **баҳолаш қатламлари**, ball эмас. Жойлашув далили йўқ → доим `normal`; AVA bron йўқ → доим `normal` (олинадиган фойда йўқ, CANCEL-7). «Бекор → эртасига/2 кун/5 кун кейин тескари рейс» — `normal`, ёзув ҳам йўқ |
| CANCEL-3 | `rescheduleTaxiTrip`: `tripId` сақланади, refund/qayta charge йўқ, `taxi_reschedules` audit; нарх ўзгарса `reprice` қоидаси (350k→400k = +4 000). Dart: `TaxiBillingRepository.reschedule` |
| CANCEL-4/5/7 | `confirmed` = жойлашув + AVA bron + ≥2 мустақил тасдиқловчи; `manual_review` = +1; `suspicious` = фақат жойлашув+bron. Пул фақат `confirmed`да + сиз ёзган хабар |
| CANCEL-6 | `reclaimWithDebt`: wallet'даги қисми ledger орқали, қолгани `provider_capabilities.debt.taxi` (сервер калити, клиент тегмайди); `publishTaxiTrip` АВВАЛ қарзни ёпади (`settleOutstanding`), етмаса `outstanding_debt` билан янги рейс йўқ. Иккинчи ledger йўқ |
| D-CLEAN-1 | `resolveAuthorizedCourierUid` → **фақат capability** (`couriers` мавжудлиги ва `users.role == 'courier'` олиб ташланди, 14 callable қайта деплой); `isStaff()`дан `courier`/`seller` чиқарилди; `usersCourierRolePromotion/Demotion` ўчирилди; `courier_push` фақат `provider_presence` + `users.fcmToken`; **R-1 hard gate ЖОНЛИ**: `intercity_drivers.isActive: true` фақат `billingTripId` билан |

Тестлар: taxi CF (ҳақиқий ledger) **20/20** · fraud/формула соф **21** · rules **309** (intercity 28, caps 28, courier_push 20) · demand **557** · Flutter **620**. Деплой: қоида → 22 та default функция → demand.

### 3.0-bis Тоза старт кетма-кетлиги — бажарилгани (2026-10-06, кечқурун)

Тартиб (эга рухсати билан мен белгиладим): A Agreement→Starter + fraud shadow ·
B R-7 · C ҳайдовчи кириш оқими · D admin verification UI · E reschedule UI ·
F админ couriers→presence · G test data cleanup · H деплой.

| Босқич | Ҳолат |
|---|---|
| **A** | ✅ ~~`requestCapability` taxi учун келишувни ТАЛАБ қилади (`AGREEMENT_GATED.taxi = true`)~~ — **D-TAXI-24.1 билан ўзгарди**: `AGREEMENT_GATED.taxi = false`, келишув 4 ой ўтгач тақдим қилинади (1.6-quater). Fraud review fee'сиз бекорларни ҳам баҳолайди (verdict ёзилади, пул фақат refund бўлганда) — starter даврида pipeline маълумот беради |
| **B R-7** | ✅ `approvedDriverForTaxi()` → capability (`starter`/`verification_required`/`verified` + `taxi.taxiTypes` декларатсияси); `taxiCanPublish()` (`starter`/`verified`) — `schedules` ва `queue` create. Эгалик текшируви қўшилди (аввал тасдиқланган ҳайдовчи бошқа номидан жадвал яратарди). `drivers.approved` энди ҳеч нарса бермайди. Тест: `taxi_capability_rules.test.js` 13/13 — бу йўллар аввал ҳеч қаерда ижобий ҳолат билан синалмаган экан |
| **C** | ✅ `DriverRepository.submitDriverApplication` → `requestCapability(taxi)` + ўз профили (`drivers/{uid}`, тасдиқ майдонларисиз) + `provider_capabilities.taxi.taxiTypes`; `isApprovedForTaxi` → capability; 3 экран (`intercity`, `local`, `marshrut`) `ensureTaxiCapability` орқали: келишув варағи → `starter`. `driver_requests`/`autoApproveDriverApplication`/`driverApprovalMode` — legacy, ишлатилмайди |
| **D** | ✅ `TaxiVerificationScreen` (admin web, «Такси верификацияси»): фильтр `verification_required`/`starter`/`verified`/`suspended`, амаллар `adminSetCapabilityStatus` орқали (сабаб → audit) |
| **E** | ✅ Ҳайдовчи панелида «Рейсни кейинга суриш»: sana/vaqt → `rescheduleTaxiTrip` (комиссия сақланади) + `intercity_drivers.scheduleDate/hour` |
| **F** | ✅ `courier_admin_screen`: онлайн рўйхат ва харита `provider_presence`дан, исм `users/{id}`дан |
| **G** | ⛔ **СИЗ ИШГА ТУШИРАСИЗ.** Dry-run ўтди, backup ёзилди (177 ҳужжат: drivers 16 · couriers 3 · intercity_drivers 6 · schedules 139 · queue 6 · driver_requests 7; `users.role=='courier'` 1 та → `user`). Mass delete автоматик классификатор томонидан тўхтатилди — скрипт: `node <scratchpad>/cleanup_test_data.js --execute`. `users`, `orders`, `trips`, `intercity_bookings`, `delivery_routes`, wallet/ledger ТЕГИЛМАЙДИ |
| **H** | ✅ индекс (`taxi_trips` driverUid+status+fraudReviewed+cancelledAt) → қоида → 6 taxi callable → demand |

### 3.1 Қолган ишлар

| # | Нима | Нега ҳали |
|---|---|---|
| ~~N-1~~ | ✅ D-TAXI-24.1 — келишув дарвозаси starter'дан олинди, 4 ой ўтганда (verification_required) тизим тақдим қилади (1.6-quater «Бажарилгани») | деплой кутилмоқда |
| ~~N-2~~ | ✅ D-TAXI-6.1 — `taxiBillingEnabled` глобал флаги олиб ташланди; billing ҳар ҳайдовчи учун `isTaxiBillable` билан автоматик | деплой кутилмоқда |
| ~~N-3~~ | ✅ D-TAXI-CANCEL-9 — «2 соат» қоидаси `cancelTaxiTrip`дан олинди, CF тести тескарисига ёзилди; `late_cancel` фақат `manual_review` учун | деплой кутилмоқда |
| **N-4** | Бошқа хизматлар келишув матнлари — таклиф 2-bis бўлимда, эга таҳрири кутилмоқда | PROPOSED |
| ~~R-1~~ | ✅ hard gate жонли | — |
| ~~R-2~~ | ❌ КЕРАК ЭМАС — D-CLEAN-1: мавжуд ҳайдовчилар тест маълумоти, миграция йўқ. `adminMigrateTaxiDrivers` коди қолади, ишлатилмайди | — |
| ~~R-3~~ | ❌ БЕКОР — D-TAXI-6.1: глобал флаг эмас, ҳар ҳайдовчи учун автоматик (N-2) | — |
| ~~R-4~~ | ✅ `TaxiVerificationScreen` | — |
| ~~R-5~~ | ❌ БЕКОР — D-TAXI-CANCEL-9: 2 соат қоидаси игнор қилинади (N-3) | — |
| ~~R-6~~ | ✅ панелда «Рейсни кейинга суриш» | — |
| R-7 | Такси operational қоидалари (`approvedDriverForTaxi` → `drivers.approved`) capability `starter/verified`га кўчирилиши — `queue`, `schedules`, `driver_requests` оқими. Ҳозир янги ҳайдовчи `starter` олса ҳам, `schedules`/`queue` қоидаси ҳамон `drivers.approved` талаб қилади | Алоҳида катта иш: 6+ қоида блоки + `driver_requests` CF |
| R-8 | Админ `couriers` экранлари → `provider_presence`; `courier_controller`даги `couriers` dual-write олиб ташлаш | Экранлар кўчгач |
| R-9 | Эски test driver/user/provider маълумотларини тозалаш | Эга «мумкин» деди, «қил» демади — буйруқ билан, dry-run рўйхатидан кейин |

### 3.2 Деплой ҳолати — 2026-10-06 кечки

| | |
|---|---|
| `firestore.indexes.json` | ✅ `taxi_trips(driverUid,status,refunded,fraudReviewed,cancelledAt)`; **`trips(status,reservedAt)` ҚАЙТА ҚЎШИЛДИ** (қуйига қаранг) |
| `firestore.rules` | ✅ `service_agreements` `capability_audit` `taxi_trips` `taxi_price_changes` `taxi_fraud_cases` — ҳаммаси `write: false` |
| `functions` (default) | ✅ `quoteTaxiFee` `publishTaxiTrip` `repriceTaxiTrip` `cancelTaxiTrip` `completeTaxiTrip` — us-central1, фақат шу бештаси деплой қилинди |
| `functions:demand` | ✅ `acceptServiceAgreement` `adminSetCapabilityStatus` `adminMigrateTaxiDrivers` |
| Тестлар | demand 557 · rules 309 (19 to'plam) · taxi CF (haqiqiy ledger) 15/15 · taxi pure 17 · paritet 1 · Flutter 620 |

### 3.3 N-1…N-3 ҳолати — 2026-10-06 кечқурун (кейинги сессия)

| | |
|---|---|
| Git | 83 файл (аввалги сессия иши) `b06325f` да commit қилинди; N-1…N-3 алоҳида commit |
| `firestore.rules` / `firestore.indexes.json` | **ЎЗГАРМАДИ** — деплой керак эмас (`agreementRequestedAt` мавжуд `window` сервер калити ичида) |
| `functions` (default) | ⏳ **ДЕПЛОЙ КУТИЛМОҚДА**: `quoteTaxiFee` `publishTaxiTrip` `repriceTaxiTrip` `rescheduleTaxiTrip` `cancelTaxiTrip` `completeTaxiTrip` (`taxi_billing.js`, `taxi_fraud.js`, `capabilities_model.js` нусхаси) |
| `functions:demand` | ⏳ **ДЕПЛОЙ КУТИЛМОҚДА**: `requestCapability` `capabilitySweeper` `adminSetCapabilityStatus` (ва `acceptServiceAgreement` — фақат изоҳ) |
| Flutter | янги илова версияси керак: `TaxiFeeQuote.billingMode` йўқ, `agreementRequired`; эски илова `billingMode` йўқлигини `''` деб ўқийди — бузилмайди |
| Тестлар | demand **565** (20 тўплам, +8) · taxi CF (haqiqiy ledger) **26/26** (+6) · taxi pure **23** (+2) · паритет 1 · Flutter analyze/test — 3.3-жадвал остига қаранг |
| Продакшн маълумот | `module_config/global.taxiBillingEnabled` ҳужжати қолади, энди ўқилмайди — ўчириш шарт эмас |

**Инцидент (менинг эмас, лекин мен топдим ва тузатдим):**
`releaseStaleReservations` (ҳар дақиқа, `trips` коллекцияси) 2026-10-06
07:00–07:16 UTC дан бошлаб `The query requires an index` (`trips:
status + reservedAt`) билан йиқилиб турган. Бу индекс репо файлида
**умуман йўқ эди** — яъни продакшнда қўлда яратилган ва бугун эрталаб
йўқолган (менинг биринчи индекс деплойим 08:45+ UTC, яъни кейин; ким
ўчиргани аниқланмади). Индекс файлга қўшилди ва деплой қилинди
(`CREATING`). Оқибати: ~5 соат давомида эскирган ўрин бронлари
автоматик бўшатилмаган — маълумот йўқолмаган, фақат ўринлар кечроқ
бўшаган. Индекс `READY` бўлгач функция ўзи тикланади.

**Биринчи қадам 1 ва 2 — улар қолган ҳаммасининг асоси.** 2-босқич
(барқарор `providerId`) эса **вақтга боғлиқ**: ҳозир 0 ҳужжат, кейин
қиммат.

---

## 4. ЎЗГАРМАСЛИГИ КЕРАК

Код ёзишда қуйидагилар соддалаштирилмайди:

1. `AVA fee = farePerSeat × 4 × 2%` — ҳамма жойда.
2. AVA орқали топилган йўловчи сони комиссияга таъсир қилмайди.
3. Комиссия publish'дан ОЛДИН олинади.
4. `verified` ни фақат сервер/админ беради.
5. Такси чеклови бошқа capability'ларни блокламайди.
6. 4 ойлик starter бир UID учун бир марта бошланади.
