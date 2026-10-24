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
| 8 | Танишув: мавжуд `deleteDatingProfile` **ўзгармайди** (иккинчи томон чати ҳам ўчади — эга шу ҳолатни қабул қилди) |
| 9 | Давралар ва шажара: **кейинга қолдирилди** (қўлланилмайди) |
| 10 | Бонус ҳеши: ҳисоб ўчирилгандан **30 кун** сақланади |

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
3. Очиқ контент ва медиа ўчирилади (мавжуд функциялардан: `deleteRealtyListing`, `onTvClipDeleted`/`deleteTvClipMedia`, `deleteMyBusiness`, ёрдамчи ва қариндош ўчиришлар; танишув — ўзгармаган `deleteDatingProfile`).
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
- Танишувда иккинчи томон чати ўчади (мавжуд хатти-ҳаракат, ўзгармаган).

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
- Қобиқ ва қайта рўйхатдан ўтиш: ўша телефон билан қайта кирилса қобиқ янги ҳисобга айлантирилади (`createdAt` янгиланиши) — таҳлилда ёзилади.
