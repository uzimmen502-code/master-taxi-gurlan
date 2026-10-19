# Кўчмас мулк эълонига ихтиёрий видео (≤ 60 сония, АВАГрам)

Ҳолат: **implementation completed, verification pending** (код + тестлар ёзилган ва локал ишга туширилган;
production'га ҲАЛИ чиқарилмаган — деплой алоҳида, қаранг §7). Сана: 2026-10-20.
Белгилар (CLAUDE.md §47): **CONFIRMED** — коддан кўрилди · **INFERRED** — кучли хулоса · **PROPOSED** — менинг таклифим · **UNKNOWN** — эгадан сўралади.

## 1. Эга қарори (сўзма-сўз, 2026-10-19)

> «Кўчмас мулк кластерида, сотиш / ижарада фойдаланувчи ИХТИЁРИЙ, максимум 60 секундлик видео жойлаштириши мумкин,
> видео АВА Грамга жойлаштирилади. Агар эълон ўчирилса видео ҳам ўчирилади.»

## 2. Нима МАВЖУД эди (CONFIRMED, коддан)

| Нарса | Жойи | Хулоса |
|---|---|---|
| Битта коллекция | `realty_listings/{id}`, `deal: 'sale' \| 'rent'` — `functions/realty.js:365` (`parseListingInput`) | сотиш ва ижара БИР ХИЛ ҳужжат, алоҳида коллекция йўқ; видео қоидаси `deal`га боғлиқ эмас |
| Эълон яратиш/таҳрир | CF: `submitRealtyListing` (`realty.js:440`), `updateRealtyListing` (`:587`); клиент ёзмайди (`firestore.rules` `match /realty_listings` — `create, update, delete: if isAdmin()`) | `submit` натижада `listingId` қайтаради (`RealtySubmitResult.listingId`) |
| Эгалик | `ownerKey` (`users/{uid}.realtyOwnerKey`), телефон эмас; жамоа ходимлари битта калитни улашади — `assertOwner` (`realty.js:228`), қоидада `realtyListingIsMine` (`firestore.rules:4122`) | видео ваколати ҳам шу калит бўйича бўлиши керак |
| **Эълон ЎЧИРИЛИШИ** | фақат ҚАТТИҚ ўчириш (soft-delete / архив ЙЎҚ): `deleteRealtyListing` (эга, `realty.js:687`), `adminDeleteRealtyListing` (админ, `:1513`), `realtyExpirySweep` (кунлик cron, `:1543`) — учови ҳам `deleteListingDeep` → `ref.delete()` (`:707`) | **битта Firestore `onDelete` триггери учала йўлни қоплайди** |
| Муддат | бепул ОДДИЙ эълон `PLAIN_EXPIRY_DAYS = 30` кун (`realty.js:59`), тугагач ЎЧИРИЛАДИ; пуллик даража тугаса ҳам ўчади (`:1543`+) | муддат тугаши ҳам «ўчирилди» — видео ҳам кетади (§6, savol 3) |
| Ҳолатлар | `pending` \| `active` \| `blocked` (`adminSetRealtyStatus`, `realty.js:1418`) | булар ўчириш ЭМАС (§3, D-RV-5) |
| ЭСКИ видео йўли | `linkRealtyVideo`/`unlinkRealtyVideo` (`realty.js:1372/1400`): эга ЎЗИНИНГ мавжуд AVAGram клипини танлаб `avagramClipId`/`adClipId` ёзади (клип `active` ва эгасиники бўлиши шарт); UI: `realty_video_sheet.dart`, `my_realty_listings_screen.dart:597`; кўрсатиш: `realty_detail_screen.dart` (`listing.hasVideo`), `realty_card.dart:93` | бу «мавжуд клипни улаш» — ЯНГИ видео яратиш эмас; клипни ўчирмайди (`unlink`да ҳам) |
| AVAGram боғлаш қатлами | `TvClipLink` (`tv_clip_link.dart`): боғлаш КЛИП ҳужжатида (`tv_clips.linkKind/linkId`), `TvPublishScreen(organicOnly, linkKind, linkId)`; турлар: `ad`, `service`, `market_ad`, `wholesale_product`, `restaurant`, `restaurant_item` | қайта ишлатилади, параллел тизим қурилмайди (§3, §4) |
| 60 с чегараси (таом) | сервер `functions/tv_clip_limits.js` (`tvClipMaxSecondsFor`) + `index.js:13968` (транскод `-t`); клиент `tvClipMaxSecondsFor` (`tv_clip.dart`), `tv_publish_screen.dart:274`; тест `tv_clip_duration_limit_test.dart` | сервер КЕСАДИ (рад этмайди), клиент олдиндан огоҳлантиради |
| Таом ўчса видео ўчади | `functions/restaurant_dish_video.js` (`onRestaurantMenuItemDeleted`), тест `restaurant_orders_cf.test.js` DV1/DV2 | айнан шу нақш кўчирилди |
| Ваколат қоидаси (ресторан) | `firestore.rules:3805` `tvClipRestaurantLinkOk` / `tvClipRestaurantLinkUpdateOk`; тест `tv_clip_link_rules.test.js` | нақш кўчирилди |
| Медиани тозалаш | `onTvClipDeleted` (`index.js:14409`) — клип ҳужжати ўчса файллар/CDN/ҳисоб тозаланади | клипни ўчириш = ягона йўл, медиага тегмаймиз |

## 3. Қарорлар

- **D-RV-1 (PROPOSED → амалга оширилди) — янги боғлаш тури `realty_listing`**, `linkId` = `realty_listings` id. Янги коллекция/CF/видео тизими ЙЎҚ: мавжуд `TvPublishScreen` → `tv_clips` → модерация → R2 → АВАГрам лентаси (CLAUDE.md §3/§4/§43).
- **D-RV-2 — бир эълонда БИТТА видео** (CONFIRMED нақш: таом/ресторанда ҳам шундай, `TvClipLink.supersededClips`): янгиси жонли бўлгач эгасининг эскиси клиентда ўчади. Сервер сони чекламайди (қоида ҳужжат санай олмайди); эълон ўчса ҳаммаси (≤ 500) ўчади.
- **D-RV-3 — ваколат серверда (қоида, 18/19/20-қоидалар)**: `tvClipRealtyLinkOk` — `linkKind == 'realty_listing'` бўлса `linkId` ҳужжат-id шаклида (`[A-Za-z0-9_-]{1,64}`, `/` йўқ) ва `realtyListingIsMine(linkId)` (эълон МАВЖУД ва шу фойдаланувчининг `realtyOwnerKey`и). Жамоа ходими ҳам ёза олади. Бегона/сохта эълонга боғлаб бўлмайди. Модерация (`status == pending` шарти) ва пуллик реклама йўли ёпиқлиги (`category != 'ad'`) ўзгармаган.
- **D-RV-4 — 60 сония ЧЕГАРАСИ клип ЯРАТИЛГАНДА `linkKind`дан** (транскод `-t`). Айланиб ўтиш йўли ёпилди: `tvClipRealtyLinkUpdateOk` — мавжуд клипни кейин эълонга «кўчириб» (ёки бошқа эълонга) бўлмайди; боғлаш ўзгармаса (сарлавҳа) ва боғлашни олиб ташлаш мумкин. Ресторан таомидан бу қатъийроқ: у ерда кейин улаш рухсат (`M7`), чунки таом чегараси бошқача тарзда лойиҳаланган — **таомга тегилмади**.
- **D-RV-5 — «эълон ўчирилди» = `realty_listings/{id}` ҳужжати ўчиши**. `blocked`/`pending` ва муддат ЎТМАГАН ҳолатлар клипга тегмайди. Триггер: `onRealtyListingDeleted` (`functions/realty_video.js`), `tv_clips` `linkKind == 'realty_listing' && linkId == id` бўйича ≤ 100×5 партияда ўчиради; идемпотент; лог `action: realty_video_cleanup, listingId, deleted` (клип id/телефон ЙЎҚ).
- **D-RV-6 — ЭСКИ йўл (`avagramClipId`/`adClipId`) билан уланган мустақил клип ЎЧИРИЛМАЙДИ** (у эганинг умумий AVAGram клипи, пуллик реклама ҳам бўлиши мумкин; `unlinkRealtyVideo` ҳам ўчирмайди). Тестда қулфланган (RV4). Эга қарори керак — §6, savol 1.
- **D-RV-7 — кўрсатиш**: эълон тафсилотида `LinkedVideoButton(trustLinkKind: realty_listing)` — битта сўров, эгалик солиштирилмайди (қоида кафолатлайди), фақат `active` ва ўйнатиладиган клип. Эски `hasVideo` тугмаси ўзгармаган.
- **D-RV-8 — UI**: янги эълон — «Видео қўшиш (ихтиёрий, 60 сония гача)» белгиси (`VideoOptionTile`, матн калитлари параметрли — бошқа модуллар ўзгармаган); эълон сақлангач `TvClipLink.publish`. Таҳрир — `RealtyListingVideoCard` (ҳолат, кўриш, алмаштириш, ўчириш; жамоа ходими юклаганини ўчира олмайди). Видео бекор қилинса/йиқилса эълонга таъсир йўқ.

## 4. Хавфлар ва қолдиқ масалалар

| # | Хавф | Ҳолат |
|---|---|---|
| 1 | Эълон ўчириладиган лаҳзада ШУ ПАЙТДА яратилаётган клип етим қолиши (пойга) | қоида клип яратишда эълон МАВЖУДлигини талаб қилади (ўчган эълонга `get()` хато → рад), яъни ойна жуда тор; етим клип ўз ҳолича АВАГрамда қолади — **қолдиқ хавф, қабул қилинган** (INFERRED) |
| 2 | Триггер йиқилса клип етим қолади (эълон аллақачон йўқ) | лог `REALTY_VIDEO_CLEANUP_FAILED`; Cloud Functions retry ЁҚИЛМАГАН (таом нақши билан бир хил). Қайта тозалаш скрипти ЙЎҚ — PROPOSED, талаб бўлса қўшилади |
| 3 | `blocked` эълоннинг клипи АВАГрамда кўриниб туради | UNKNOWN — §6, savol 2 (клип модерацияси алоҳида) |
| 4 | Лентадаги карточкада янги видео белгиси (▶) ЙЎҚ | `hasVideo` эълон майдонидан; янги клип эълонга ёзилмайди (клип томонида боғлаш). Белги учун ё лентада +1 сўров (≤ 200 ўқиш), ё триггер керак — иккиси ҳам қиммат (36/37-қоидалар), шунинг учун ҚИЛИНМАДИ. PROPOSED |
| 5 | `firestore.rules` функцияларида 1000 ибора чегараси: рад этилган `create`да `isAdmin()` тармоғи билан баравар эмулятор «max 1000 expressions» хабарини беради | БАЗА ЧИЗИҒИДА ҲАМ БОР (41 тестда 25 марта), янги қоида муваффақиятли йўлни бузмайди (61/61) |
| 6 | Админ панелда эълон видеоси кўринмайди | ўзгартирилмади (AVAGram модерация бўлими клипни ўзи кўрсатади) |

## 5. Қилинган иш (файллар)

Сервер: `functions/tv_clip_limits.js` (+`realty_listing` 60 с), `functions/realty_video.js` (янги, триггер), `functions/index.js` (3 қатор: рўйхатга олиш).
Қоидалар: `firestore.rules` — `tvClipRealtyLinkOk`, `tvClipRealtyLinkUpdateOk` + `tv_clips` `create`/`update` га 2 шарт.
Клиент: `tv_clip.dart` (`tvClipRealtyMaxUploadSeconds`, `tvClipMaxSecondsFor`), `tv_clip_link.dart` (`kindRealty`), `tv_clips_repository.dart` (`fetchLinkedClips`), `tv_clip_link_widgets.dart` (`VideoOptionTile` матн калитлари; `LinkedVideoButton` Firebase тайёр бўлмаса йиқилмайди), `realty_listing_video_card.dart` (янги), `add_realty_listing_screen.dart`, `realty_detail_screen.dart`, `assets/lang/*.json` (17 калит × 3 тил).
Тестлар: `functions/test/tv_clip_limits.test.js`, `tv_clip_link_rules.test.js` (+20), `realty_video_cleanup.test.js` (янги, 6), `test/features/realty/realty_listing_video_card_test.dart` (янги), `test/features/tv_market/tv_clip_duration_limit_test.dart`.

## 6. Эгадан сўраладиган саволлар (UNKNOWN)

1. **Эски «мавжуд клипни улаш» тугмаси** («Менинг эълонларим» → «Видео боғлаш») қолсинми? Ҳозир қолдирилди (ўзгартирилмади); у билан уланган клип эълон ўчса ЎЧМАЙДИ. Қолдирилса — иккита йўл: янги (60 с, эълон билан бирга ўчади) ва эски (исталган узунликдаги ўз клипи, ўчмайди). Таклиф (PROPOSED): эскисини яшириш, фақат янгисини қолдириш — эга қарори керак.
2. **`blocked` (админ блоклаган) эълоннинг видеоси** — ўчсинми/яширинсинми? Ҳозир тегилмайди.
3. **Муддат тугаши:** бепул ОДДИЙ эълон 30 кундан сўнг ўчади (`realtyExpirySweep`) — видео ҳам шунда ўчади (қарорга мос, лекин эгага билдирилсин: эълон узайтирилмаса видео ҳам кетади).
4. Эски (APK +93 ва аввалги) иловалар янги видео картасини кўрсатмайди, лекин эълонда тугма ишлайди (веб/сервер томонидан).

## 7. Деплой тартиби (бажарилмаган; CLAUDE.md §29/§28)

> **Production ҳолати UNKNOWN**: хотира ёзуви (2026-10-18) бўйича «realty CLIENT live, realty SERVER (`realty.js` ва ҳ.к.) деплой қилинмаган». Эълон яратувчи CF'лар production'да борми — ТЕКШИРИЛМАДИ (production'га тегиш тақиқланган). `realty.js` фақат ўқилди, ўзгартирилмади; триггер ундан мустақил.

1. **Rules алоҳида команда** (functions билан бирга эмас): аввал жонли ruleset'ни олиб `firestore.rules` билан фарқини кўр — файл бошқа сессияларнинг чиқарилмаган ўзгаришларини ҳам ўз ичига олади (`--config <абс>\firebase.json` билан).
2. **Functions ном бўйича** (пинланган worktree): `onRealtyListingDeleted` (янги), `onTvClipCreatedV2`, `onTvClipVideoReplacedV2`, `onTvClipBackfillRequested` (`tv_clip_limits.js` ни ўқийди — 60 с чегараси учун). `realty.js` функциялари ўзгармаган.
3. **Hosting** (жонли SHA устига) ва **APK** — охирида: янги илова эски қоида/сервер билан ишлаганда ваколат ва 60 с тўсиғи йўқ, шунинг учун АЛБАТТА 1–2-қадамлардан КЕЙИН.
4. Тескари қайтариш: rules — олдинги ruleset'ни қайта чиқариш; функция — триггерни ўчириш (`onRealtyListingDeleted`) клипларга зарар қилмайди; клиент — янги тугма/карта фақат кўрсатиш.
5. Деплойдан кейин жонлида исботла: rules релиз вақти, функция версиялари, битта синов эълони (эмулятор/ўз ҳисоб) орқали «клип яратилди → эълон ўчди → клип ўчди».

## 8. Миграция

Керак ЭМАС: янги майдон эълон ҳужжатига ёзилмайди, эски ҳужжатлар ўзгармайди; `tv_clips`да `linkKind/linkId` мавжуд майдонлар.
