# Иловада ҳисобни автоматик ўчириш (дизайн, 2026-10-24)

> Манба: эганинг қарорлари (чат, 2026-10-24). Статус: **дизайн; код ёзилмаган**.
> Белгилар: CONFIRMED = коддан тасдиқланган · INFERRED = кучли хулоса · PROPOSED = таклиф · UNKNOWN = аниқланмаган.
> Сабаб (why): Google Play иловада ҳам, веб-ҳаволада ҳам ўчириш йўлини талаб қилади
> (support.google.com/googleplay/android-developer/answer/13327111, 2026-10-24 да ўқилган).
> Ҳозир фақат `web/delete-account.html` + email бор (CONFIRMED: иловада ва серверда ўчириш коди йўқ).

## 1. Эга қарорлари (AVA_DECIDED)

| # | Қарор |
|---|---|
| 1 | Тўлиқ автоматик ўчириш; сўровдан кейин **10 кун** кутилади, шу даврда бекор қилиш мумкин |
| 2 | Ҳамёнда пул бўлса ҳам ўчирилади, ечиб олиш шарт эмас (қолдиқ сўндирилади) |
| 3 | Фаол буюртма / сафар / курьер қарзи бўлса ўчириш **блокланади** (+ кутилаётган payout/ечиш/тўлдириш ва админ/молия роллари) |
| 4 | `users` ҳужжати ўчирилмайди — «ўчирилган» **қобиққа** айлантирилади |
| 5 | Сўров тасдиғи: **ҳозирги кодий қоида** (тасдиқланган қурилмадаги кириш сессияси; SMS йўқ — CONFIRMED) |
| 6 | Пулли хизматлар (кўчмас мулк Pro, ёрдамчи пакети) ҳамён каби сўндирилади — **огоҳлантириш билан** |
| 7 | Эълон/видео ва бошқа очиқ контент сўровдан **дарҳол яширилади** |
| 8 | Танишув: **чат ўчмайди** (эга, 2026-10-24: «чат ўчмасин»). Ўчириш ўз профилини, суратларини, юборган қизиқишларини ва блокларини олиб ташлайди; `dating_matches` ва уларнинг хабарлари иккинчи томонда қолади. Мавжуд `deleteDatingProfile` (у иккинчи томон чатини ҳам ўчиради, index.js:16896) ўзгармайди ва бу ерда **чақирилмайди** — алоҳида «ўз томонини ўчириш» қадами ёзилади |
| 9 | Давралар ва шажара: **кейинга қолдирилди** (қўлланилмайди) |
| 10 | Бонус ҳеши: ҳисоб ўчирилгандан **30 кун** сақланади |
| 11 | Бонус ёзуви **телефон ҳеши (HMAC) ва қурилма ҳеши** бўйича юритилади; иккаласидан бири такрорланса бонус берилмайди. Сабаб (CONFIRMED): кодда телефонни SMS билан тасдиқлаш йўқ, рақамни фойдаланувчи ўзи ёзади, қурилма бармоқ изи шу рақамга боғланади (`checkDeviceBinding`, `createPhoneSession`) |

## 2. Ҳолатлар

`account_deletions/{uid12}`: `PENDING` (scheduledFor = +10 кун) → `EXECUTING` → `DONE` | `CANCELLED` | `POSTPONED` (ижро пайтида блок чиқса). Ҳар ўтиш воқеалар журналига ёзилади (16-банд). PROPOSED.

## 3. Шахсни аниқлаш (identity set) — CONFIRMED хавфлар
- `users` ҳужжат ID икки шаклда (12 хонали ва эски 9 хонали); `canonicalUid` index.js:759.
- `changeDevicePhone` фақат `users.phone`, `device_bindings.phone`, `device_aliases` ни янгилайди — эски телефон калити остидаги маълумот қолади.
- Ўчириш ўқиши керак: `users` ID (иккала шакл), `users.phone`, `device_bindings.phone`, `users.accountId`, `users.realtyOwnerKey`.

## 4. Блокловчи ҳолатлар (сўровда ВА ижрода қайта текширилади)
Манба: инвентаризация (2026-10-24). Аниқ «фаол» қийматлар PROPOSED, `UNKNOWN` — таҳлилда аниқланади.
| Соҳа | Коллекция.майдон | Фаол қийматлар |
|---|---|---|
| Нон/платформа буюртма | orders.status / fulfillmentStatus | new, accepted, ready, in_delivery, courier / pending, confirmed, ready, courier_picked, arrived; тўланмаган нақд (paymentStatus≠paid, cashDue>0) |
| Ресторан буюртма | orders.restaurantStatus | placed, accepted, ready, picked, arrived |
| Гилам / агро | carpet_wash_orders.status, agro_pickup_orders.status | юқоридаги рўйхатлар (delivered — UNKNOWN) |
| Йиғиш топшириқлари | collection_tasks | UNKNOWN |
| Такси | trips.status (local/alone; marshrut) | searching, accepted; pending, accepted |
| Шаҳарлараро / стол / мой | intercity_bookings, restaurant_bookings, oil_change_bookings | pending, confirmed; requested, confirmed; new |
| Юк (relay) | shipments.status / paymentStatus; demands.status | awaiting_payment, ready, in_transit, disputed, lost / pending, escrow_funded, release_approved, escrow_frozen, refund_pending; active, accepted, in_progress, disputed |
| Хитой сўровлари | china_inquiries.status | new, sent, quoted |
| Ҳисоб-китоб | settlements.state | pending |
| Курьер | delivery_routes.status; ledger_accounts/courier_cash:{phone12}.balance; ресторан buyout | ready, active; >0 |
| Қарзлар | provider_capabilities/{accountId}.debt.taxi; driver_float; supplier_payable (маъноси UNKNOWN); escrow:{shipmentId} | >0 / ≠0 |
| Пул ҳаракатда | payout_requests, wallet_withdraw_requests, wallet_topup_requests | pending; pending, approved; awaiting_transfer, awaiting_review |
| Ходим роллари | users.role | admin, superadmin, dispatcher, finance, auditor (аввал рол олиб ташланади) |

## 5. Ижро қадамлари (идемпотент, ҳар қадам белгиланади, қайта юритса давом этади) — PROPOSED
1. Блокларни қайта текшириш → бор бўлса `POSTPONED` + фойдаланувчига хабар.
2. Ҳамён қолдиғи ва бонус лотлари сўндирилади: ҳисоб дафтарига алоҳида ёзув (`account_deletion_forfeit`), `passenger_credit == bonusBalance` муносабати сақланади.
3. Очиқ контент ва медиа ўчирилади (мавжуд функциялардан: `deleteRealtyListing`, `onTvClipDeleted`/`deleteTvClipMedia`, `deleteMyBusiness`, ёрдамчи ва қариндош ўчиришлар). Танишув: **алоҳида «ўз томонини ўчириш»** (профил, суратлар, юборилган қизиқишлар, блоклар); матчлар ва чат хабарлари қолади (қарор 8).
4. Буюртма/сафар/бронлардан исм, манзил, GPS олиб ташланади; молиявий ёзув сақланади.
5. Қурилма боғланиши, `device_aliases`, Telegram боғланиши, FCM токенлар, `anon_sessions`, ёрдамчи маълумоти ўчирилади.
6. `users/{id}` → қобиқ: `deleted:true`, `deletedAt`, `bonusBalance:0`, шахсий майдонлар йўқ (**ID да телефон қолади**).
7. Firebase Auth фойдаланувчиси ўчирилади (охирида).
8. Бонус ҳеши: `expireAt = deletedAt + 30 кун`.
Қобиқ нега: 6 та ҳисоб-китоб йўли `set(merge)` билан ўчирилган `users` ҳужжатини бўш «арвоҳ» сифатида қайта яратади (CONFIRMED, settlement_ledger.js:263-276, 367, 418; index.js:2418, 16365-16386); `reconcile()` ва тўлов функциялари ҳужжат бор деб ҳисоблайди.

## 6. «Дарҳол яшириш» (қарор 7)
Ҳар коллекцияда яширишнинг мавжуд механизми бор-йўқлиги **UNKNOWN**. PROPOSED: мавжуд статус/кўриниш майдонидан фойдаланиш; бўлмаган жойда `hiddenByAccountDeletion` + сўровларга фильтр. Бекор қилинса — қайтарилади. Таҳлил қадами A1.

## 7. Ўчирилмайдиган жойлар (очиқ эълон қилинади)
- Молиявий журнал ва ҳисоб-китоб ёзувлари (ID ичида телефон/uid), 3 йилгача.
- Хавфсизлик/фирибгарлик логлари, 12 ойгача.
- Учинчи томонлар: OpenAI (ёрдамчи чат матни), Crashlytics (телефон ID), Telegram бот, AVA нинг ижтимоий саҳифаларидаги постлар, CDN кэши.
- Танишувда матчлар ва чат хабарлари иккинчи томонда қолади (қарор 8); ўчирилган томоннинг хабар матни чатда қолиши ва профили йўқлиги UI да қандай кўриниши — таҳлилда (A1) текширилади.

## 8. Клиент ва админ — PROPOSED
- Кабинетда «Ҳисобни ўчириш» қатори (хавфли): нима ўчади / нима қолади, ҳамён ва бонус суммаси «қайтарилмайди», пулли хизматлар огоҳлантириши, блок сабаблари оддий тилда (техник атамасиз, 45-банд).
- Сўровдан кейин: «N кун қолди — Бекор қилиш» баннери; сўров вақтида ва 7-кунда push.
- Ижродан кейин: сессия ва prefs тозаланади, Crashlytics ID тозаланади, FCM токен ёзуви тўхтайди (CONFIRMED: `FCMService._saveToken` `users` ҳужжатини қайта ёзади — fcm_service.dart:143-161).
- Админ: «Ўчириш сўровлари» экрани (кўриш, бекор қилиш, аудит). Иловасиз фойдаланувчилар учун веб-саҳифа шу жараёнга боғланади.
- Матнлар: `web/delete-account.html`, махфийлик сиёсати, Play Data Safety — янги йўл, 10 кун, ҳамён сўндирилиши, сақланадиганлар, ҳеш 30 кун.

## 9. Тестлар (режа)
Мусбат/манфий/чегара: ҳар блок ҳолати; икки марта ижро; ижро ярмида узилиш ва давом; 9/12 хонали ID; арвоҳ ҳужжат йўқлиги; қолдиқ сўндирилиши (`passenger_credit == bonusBalance`); бекор қилиш; бир вақтдаги иккита сўров; Firestore rules (клиент ёзмайди); мавжуд ҳамён/ҳисоб-китоб сюитлари.

## 10. Очиқ масалалар
- Давралар ва шажара (қарор 9, кейинга).
- Ҳамён сўндирилиши ҳуқуқий/солиқ жиҳати: **UNKNOWN**, текширув эганинг «Админ ва бошқалар» ўзи.
- Ҳар коллекция учун яшириш механизми (A1), `collection_tasks` / `supplier_payable` / карпет `delivered` маъноси.
- Қобиқ ва қайта рўйхатдан ўтиш: **ҳал қилинди** — киришнинг марказий функциясига тегилмайди; алоҳида триггер `onUserShellRevived`: қобиқ (`deleted:true`) ҳужжатга клиент `phone` ёзганда белгилар олинади ва `createdAt` янгиланади (янги ҳисоб). Ҳамён тарихи ўчиришда `account_deletion_archive/{uid}/wallet_ledger` га кўчади (рақам қайта берилса янги эга эски тарихни кўрмасин).

## 11. Ҳолат (2026-10-24 кечаси) — сервер ва клиент КОД ТАЙЁР, production'да ҲАЛИ ЙЎҚ

| Қисм | Файл | Тест |
|---|---|---|
| Блок текшируви (ўқиш) | `functions/account_deletion_core.js` | 27 |
| Сўров/бекор/ижро/режали ижро, дарвоза, INTERNAL рўйхат | `functions/account_deletion.js` | 26 |
| Дарҳол яшириш/қайтариш | `functions/account_deletion_hide.js` | 9 |
| Якуний ўчириш ва тозалаш | `functions/account_deletion_content.js` | 7 |
| Callable қатлами (ҳақиқий index.js) | `functions/index.js` (attach) | 8 |
| Firestore rules (клиент `deletion/deleted/…` ёзолмайди; `account_deletions*` ёпиқ) | `firestore.rules` (REPO нусхаси) | 7 |
| Дарвоза воситаси (OFF/INTERNAL/PUBLIC, audit) | `functions/tools/set_account_deletion.js` | 7 |
| Клиент: экран, репозиторий, Кабинет қатори ва банер, 3 тил (37 калит) | `lib/features/profile/…`, `assets/lang/*.json` | 19 |

**Ёқиш босқичлари (42-банд):** OFF (ҳозир: ҳужжат йўқ) → INTERNAL (`--enabled=true --allow=<ички телефонлар>`; биринчи ҳақиқий ўчириш фақат шу ҳисобларда) → PUBLIC (`--allow=` бўш).

**Production'га чиқаришдан олдин (ҳали бажарилмаган):**
1. Функциялар НОМ бўйича (пинланган worktree, жонли функциялар асоси + шу файллар + index.js'даги 3 қатор; бутун `functions:default` ЭМАС): `previewAccountDeletion`, `requestAccountDeletion`, `cancelAccountDeletion`, `executeAccountDeletions`, `onUserShellRevived`. Дарвоза ёпиқ — қўшимча хавф йўқ.
2. Rules — АЛОҲИДА командада, ЖОНЛИ қоида матнига ЯМОҚ (repo `firestore.rules` жонлидан фарқ қилади, бутунини чиқариш МУМКИН ЭМАС): `walletFieldsUntouched()` ва `users` create рўйхатига 4 калит: `deletion, deleted, deletedAt, revivedAt`.
3. Илова (APK) — эганинг ҳар build учун рухсати билан; Google Play иловада йўл талаб қилади (текширув: support.google.com/googleplay/android-developer/answer/13327111).
4. Матнлар (ёқиш пайтида): `web/delete-account.html` — иловадаги йўл, 10 кун, ҳамён қайтарилмаслиги, сақланадиганлар (молиявий ёзувларда телефон 3 йил), учинчи томонлар (OpenAI чат матни, Crashlytics, Telegram бот, ижтимоий саҳифалардаги постлар, CDN кэши); махфийлик сиёсати; Play Data Safety.
5. Биринчи ҳақиқий ижро фақат INTERNAL ҳисобда; кузатиш: `account_deletions/{uid}` (ҳолат, `steps`, `lastError`), `events`, структурали логлар (`module: account_deletion`).

**Ҳали ЙЎҚ / очиқ:**
- Админ экрани («Ўчириш сўровлари»: рўйхат, бекор қилиш, қўлда сўров) ва дарвозани админдан бошқариш — ҳозир `set_account_deletion.js` воситаси.
- Давралар ва шажара (эга: кейинга); comments/likes/ratings, relative_phone_watchers, notifications, admin_news (шахсий хабарлар), topup_receipts, logistics, restaurants — ижро қилинмайди (UNKNOWN), ҳужжатда номма-ном.
- Яширилмайдиганлар: businesses, tv_public_profiles, tv_shops, wholesale_sellers, yuk_local_drivers, comments/likes — якуний ўчиришгача кўринади.
- Ҳамён сўндирилишининг ҳисобчилик/ҳуқуқий жиҳати (`admin_clearing` га ёзув) — UNKNOWN, «Админ ва бошқалар».
- Ижро пайтида Firebase Auth/Storage/R2 ҳақиқий муҳитда синалмаган (эмуляторда Auth/Storage сохта) — INTERNAL босқич шунинг учун шарт.
- Ёқилган APK ва ўчирилгандан кейин қурилма: Auth фойдаланувчиси ўчади, қурилма боғланиши ўчади; иловада сақланган `user_phone` билан «қайта тасдиқлаш» мастери очилиши мумкин — INTERNAL синовда текширилади.
