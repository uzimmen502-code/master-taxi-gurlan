# AVA — админ «ўчириш» сиёсати (хабар қайтариб олинади, чат архивга олинади)

**Қарор:** эга, 2026-10-20 («ҳа»). **Ўрнига келди:** 2026-10-19 даги `adminDeleteRecord` — админ risk event, хабар, алоҳида чат хабари ва бутун чатни ҳақиқий ўчира оларди (a3fbacd0, production'да ишлаб турибди).

## 1. Нима ўзгаради (§46: what / why / date / impact)

| Объект | Аввал | Энди |
|---|---|---|
| `admin_news` (умумий хабар) | админ ҳақиқий ўчиради | **Қайтариб олинади** (`adminRetractNews`): ҳужжат сақланади, фойдаланувчиларда йўқолади, **90 кун** тарихда туради, кейин `purgeRetractedAdminNews` ўчиради |
| Шахсий / буюртма / wallet хабари | (admin_news орқали ўчирилиши мумкин эди) | **Ҳеч қачон қайтарилмайди/тозаланмайди** (молиявий ёзув): `PERSONAL_NEWS_NOT_RETRACTABLE` |
| Алоҳида support хабари | ўчирилади | **Ўчириш йўқ** (kind `support_message` → `KIND_INVALID`, тугма олиб ташланди) |
| Support чат | админ ўчиради | **Архивга олинади** (`adminArchiveSupportChat`); мижоз тарихи сақланади; янги хабар келса чат ўзи қайта очилади |
| Support чатни ҲАҚИҚИЙ ўчириш | admin | Фақат **superadmin**, фақат шахсий маълумотни ўчириш талаби бўйича: сабаб ≥ 10 белги (`REASON_REQUIRED`) + чат аввал архивда (`CHAT_NOT_ARCHIVED`) |
| `risk_event` | админ ўчиради | UI тугмаси йўқ (ёпиш = «Resolved»). Серверда фақат **superadmin** ва фақат `status=='resolved'` + `resolvedAt` > 365 кун (`RISK_EVENT_RETENTION`) |

**Нега:** мижоз ёзишмаси ва хабар тарихи — далил/низо материали; тасодифий ёки суиистеъмол қилинган ўчириш қайтариб бўлмайди (§16, §41). Қайтариладиган амал (қайтариб олиш / архив) хавфни олиб ташлайди, ҳуқуқий талаб (шахсий маълумотни ўчириш) эса алоҳида, назоратли йўл билан сақланади.

## 2. Техник тузилиш

**Сервер** (`functions/`, default codebase; Firestore rules **ўзгармайди** — ҳамма ёзув Admin SDK орқали):
- `admin_retract_archive.js` (янги): `adminRetractNews`, `adminArchiveSupportChat`, `purgeRetractedAdminNews` (кунига 03:30 Тошкент), `isSupportChatArchived`, `isProtectedNews`.
- `admin_delete_record.js`: фақат `support_chat` ва `risk_event`, иккаласи ҳам superadmin.
- `index.js`: `attachAdminRetractArchive(exports, …)` — 2 қатор.

**Қайтариб олиш майдонлари** (`admin_news/{id}`): `retractedAt` (server ts), `retractedBy` (actor uid), `retractedFromAudience` (аввалги аудитория), `audience: 'retracted'`. Эски APK `retractedAt`ни билмайди, лекин `audience`ни текширади (`'retracted'` уларнинг гуруҳларида йўқ) — **эски версиялар ҳам умумий хабарни яширади**. Янги APK қўшимча `retractedAt != null` бўйича филтрлайди (`NewsItem.retractedAt`, `NewsRepository._filterForUser`, ўқилмаганлар ҳисоби).

**Архив майдонлари** (`support_chats/{chatId}`): `adminArchivedAt`, `adminArchivedBy`. `awaitingAdmin`, `awaitingAdminMsgAt`, `lastFromAdmin`, `updatedAt` **тегилмайди**. Қоида: *архивда ⇔ `adminArchivedAt != null` ва `updatedAt` ундан кейин эмас*. Янги хабар `updatedAt`ни оширади → чат серверда ҳеч нарса қилмасдан қайта очилади. Админ рўйхатида архивдаги чат яширилади, «Архивланган» филтрида кўринади; сайдбар badge'ига ҳам кирмайди.

**Audit** (`admin_audit`, §41): `admin_news_retracted`, `admin_news_purged` (count, cutoff, ids), `support_chat_archived` / `support_chat_unarchived`, `admin_record_deleted` (support_chat / risk_event). Матн (хабар/чат) auditга ёзилмайди (§40).

**Идемпотентлик:** қайтарилган хабарни яна қайтариш → `{ok:true, changed:false}`, янги audit йўқ; архив/архивдан чиқариш ҳам шундай; purge қайта ишга тушса ўчирадиган нарса йўқ → audit йўқ.

## 3. Тасдиқланган: `onAdminNewsUpdate` қайтаришга реакция қилмайди (CONFIRMED)

`functions/index.js` даги `onAdminNewsUpdate` (`admin_news/{newsId}` `onUpdate`) **фақат** `pushResendAt` ўзгарганда push юборади (`afterMs && afterMs !== beforeMs`). Қайтариш update'и `pushResendAt`га тегмайди (`retractedAt/By/FromAudience` ва `audience`ни ёзади) → триггер `null` қайтаради, push йўқ. `onAdminNewsCreate` — фақат `onCreate`. `admin_news` га бошқа триггер репозиторийда йўқ (`document('admin_news/…')` қидируви: фақат шу иккиси). Тест `N6` (`admin_retract_archive_cf.test.js`): триггер қайтаришдаги before/after билан `ref`га ҳам тегмайди; `pushResendAt` ўзгарса — тегади (мусбат назорат).

## 4. Deploy тартиби (ҲАЛИ БАЖАРИЛМАГАН — production'да йўқ)

1. **Functions — ном бўйича** (пинланган worktree, `--config <abs>\firebase.json`):
   `adminRetractNews`, `adminArchiveSupportChat`, `purgeRetractedAdminNews`, `adminDeleteRecord`.
   (`purgeRetractedAdminNews` — янги scheduled функция: биринчи deployда Cloud Scheduler job яратилади.)
2. **Hosting** (admin web): жонли SHA устига; параллел сессиялар навбати билан.
3. Rules — **деплой йўқ** (ўзгармаган). Индекс — **керак эмас** (`retractedAt` ягона майдон сўрови).
4. Деплойдан кейин жонлида текшириш: бир тест умумий хабарни қайтариб олиш (audit ёзилганини кўриш), чатни архивга олиш/чиқариш.

Тартиб муҳим: **функциялар hosting'дан олдин** — акс ҳолда янги admin web мавжуд бўлмаган callable'ни чақиради. Эски admin web (ўчириш тугмали) `adminDeleteRecord` янгиланганидан кейин `KIND_INVALID` олади (хабар/хабар-чат ўчириш ишламайди) — шунинг учун hosting функциялардан кейин дарҳол чиқарилсин.

## 5. Мослик ва таъсир

- **Эски APK** (Play'даги): умумий қайтарилган хабар `audience=='retracted'` орқали яширилади. Шахсий хабар қайтарилмайди, шунинг учун APK +103 нинг `retractedAt` филтри **фақат шахсий ҳужжатлар учун** (улар қайтарилмайди) — амалда қўшимча кафолат; янги APK мажбурий эмас.
- **Эски ҳужжатлар:** `retractedAt` / `adminArchivedAt` йўқ → оддий (қайтарилмаган/архивда эмас). Миграция керак эмас.
- **Бош саҳифа badge** (`config/home_news_badge.broadcastSeq`) хабар яратилганда ошади; қайтарилганда **камаймайди** — фойдаланувчи «Хабарлар»ни очгач ўзи тенглашади (UNKNOWN: эффект кичик, ҳисобланмаган).
- Қайтарилган хабарлар `limit(50)` ичида фойдаланувчи сўровида қатнашади (клиент филтрлайди) — кўп қайтаришда кўринадиган хабарлар сони камайиши мумкин.
- Админ рўйхатининг чат сўрови `limit(100)` (updatedAt бўйича): жуда эски архивланган чатлар «Архивланган»да чиқмаслиги мумкин.

## 6. Очиқ масалалар / хатарлар

- `firestore.rules`да `admin_news` update = `isAdmin()`: админ клиентдан бевосита `retractedAt`/`audience` ёза олади (audit'сиз) — callable'ни айланиб ўтиш. Rules'га тегиш бу топшириққа кирмайди; алоҳида қарор керак (UNKNOWN).
- Супер-админ чатни ўчирганда архивдаги тарих ва шу вақтда келаётган янги хабар ўртасида бир лаҳзали ораликда пойга (race) бор: текширув ва ўчириш битта транзакцияда эмас. Сўров шахсий маълумотни ўчиришга бўлгани учун қабул қилинган.
- `purgeRetractedAdminNews` ҳар 400 ҳужжатга битта audit ёзади (батч ичида); битта ишга тушишда 4000 тагача.
