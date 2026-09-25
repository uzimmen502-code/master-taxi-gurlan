# AVA — очиқ вазифалар рўйхати

Ҳар вазифа: мақсад → қадамлар → қабул мезони → ким. Бажарилгач — сана ва commit билан «Бажарилди» бўлимига кўчирилади.

---

## В-1. «AVA ёрдамчиси» — илова ичидаги AI чат (CF + OpenAI API)

**Ҳолат (2026-09-21):** сервер production'да — `assistantChat/GetStatus/BuyPackage/ClearHistory` (us-central1) + firestore.rules деплой қилинди, `OPENAI_API_KEY` функцияда бор (эга калит яратди; `.env`да префикс иккиланиб қолган эди — тузатилди). Реал синов: AVA саволи, баланс (ўйлаб топмайди), об-ҳаво/доллар курси (web search) — ўтди. Default модель `gpt-5-mini` (reasoning low). **Қолди:** илова релизи (Home тугмаси янги чатни очади) ва OpenAI Billing → Limits'да ойлик чегара. Йўриқнома: [ava-yordamchisi-yorqnoma.md](ava-yordamchisi-yorqnoma.md).

**Нега режа ўзгарди:** Custom GPT пилоти бекор — OpenAI 2026-09 да шахсий аккаунтларда (Free/Go/Plus/Pro) GPT яратишни ўчирди, 2026-12-11 дан мавжуд GPT'лар ҳам ишламайди (эга Plus'га уланиб «Create» тугмасини топа олмагани шу сабабдан). Пастдаги «Custom GPT» қадамлари тарих учун қолдирилди — бажарилмайди.

**Қилинди:**
- `functions/assistant_chat.js` — `assistantGetStatus`, `assistantChat` (OpenAI Responses API, `gpt-4.1-mini`, Pro'да `web_search` кунига 10), `assistantBuyPackage` (ҳамёндан, идемпотент, settlement ledger), `assistantClearHistory`. Кунлик лимит транзакцияда (параллел сўровлар ошиб кетмайди), OpenAI хатосида хабар ҳисоби қайтарилади.
- `functions/assistant_prompt.js` — Instructions + AVA билими + FAQ (аввалги GPT йўриқномасидан кўчирилди); `settings/assistant.systemPrompt`/`extraKnowledge` билан релизсиз алмаштирилади.
- `firestore.rules` — `assistant_messages/usage/packages` фақат ўқиш; `assistantPaidUntil` клиентдан ёзилмайди (`walletFieldsUntouched`).
- `lib/features/assistant/` — чат экрани (тарих stream, starter саволлар, тариф чизиғи), Pro варақаси (7/15/30 кун, баланс, «Тўлдириш» → Ҳамён). Home тугмаси «AVA ёрдамчиси» (3 тил). `chatgpt_launcher.dart` ва `settings/app.assistantUrl` олиб ташланди.

**Қолди (эга):** API калити → `.env` → `firebase deploy --only functions,firestore:rules` → релиз → OpenAI Billing'да ойлик лимит.

**Тарифлар (эга қарори):** бепул 10 хабар/кун; Pro 7 кун — 15 000, 15 кун — 25 000, 30 кун — 30 000 сўм (акция); тўлов AVA ҳамёнидан; web search фақат Pro, 10/кун.

---

### (Тарих) Custom GPT пилот режаси — бекор қилинган

**Ҳолат:** аниқлаштирилди, ҳали бошланмаган (2026-09-18, эга билан суҳбат асосида тузатилди).
**Мақсад:** бу **чекланган/тор мавзули бот эмас** — фойдаланувчи учун **ҳақиқий, тўлиқ ишлайдиган ChatGPT** (Web browsing ёқиқ, исталган мавзудаги саволга жавоб бера олади), фақат унинг устига AVA хизматлари ва имкониятлари ҳақида ҳужжатга асосланган қўшимча билим қатлами қўшилган. Яъни: **оддий ChatGPT + AVA бўйича мутахассислик**, "фақат AVA ҳақида" деб чекланган алоҳида чат эмас. Илова ичидаги «ChatGPT» тугмаси оддий chatgpt.com ўрнига шу GPT'ни очади.
**Нега Custom GPT:** бир кунда синаб кўриладиган пилот — код деярли йўқ, OpenAI инфраструктураси. Талаб тасдиқланса, кейин илова ичидаги ўз ёрдамчимизга (CF + LLM API) ўтилади; Instructions ва FAQ файли у ерга тўғридан-тўғри кўчади.

### Қадамлар

**A. Контент (dev тайёрлайди, эга тасдиқлайди)**
1. `Instructions` матни — роли: "сен — оддий ChatGPT'сан, шу билан бирга AVA иловаси ҳақида қуйидаги ҳужжатга таянган аниқ билимга эгасан". Чегара **фақат бир жойда**: AVA'даги шахсий/реал вақт маълумотлари (баланс, буюртма ҳолати, шахсий маълумот) ҳақида ўйлаб топма — "буни илова ичида кўрасиз" деб йўналтир. Бошқа ҳеч қандай мавзу чекланмайди. Тил қоидаси (фойдаланувчи тилида; кирилл ўзбекчани сақла), модул номлари иловадагидек (ТУМАН ИЧИДА ЮК / ШАҲАРЛАРАРО ЮК, АҲОЛИ БОЗОРИ, AVAGram …).
2. `Knowledge` файллари:
   - `docs/modules-imkoniyatlari.md` → PDF (ҳар релизда қайта юкланади — қаранг D).
   - FAQ файли: 30–50 та «қандай қилинади» саволи қадам-қадам жавоби билан (такси буюртма, юк эълони, ҳамён, AVAGram видео, дўкон очиш, ҳайдовчи бўлиш).
3. 4 та conversation starter.

**B. OpenAI томонида (илова эгаси — ChatGPT Plus/Team аккаунт керак)**
4. ChatGPT → Explore GPTs → Create: Name «AVA ёрдамчиси», Description, Instructions (A1), Knowledge (A2), starters (A3).
5. Capabilities: **Web browsing — ёқиқ қолдирилади** (энг муҳим қарор — GPT ҳақиқий ChatGPT каби интернетдан қидира олсин); Image generation / Code interpreter — эҳтиёжга қараб эга қарор қилади.
6. Publish → «Anyone with the link». Ссылка: `https://chatgpt.com/g/g-…`.
7. 20–30 та реал савол билан синов — фақат AVA мавзусида эмас, аралаш (умумий саволлар + AVA саволлари, уч тилда); нотўғри жавобларга қараб Instructions/FAQ тузатилади.

**C. Иловада (dev)**
8. `lib/core/utils/chatgpt_launcher.dart` — `kChatGptUrl` ўрнига GPT ссылкаси. Тавсия: URL'ни Firestore `settings/app.assistantUrl`га қўйиб, релизсиз алмаштириладиган қилиш (бўш бўлса — эски chatgpt.com).
9. Home тугмаси: `home_module_chatgpt` матни → «AVA ёрдамчиси» (3 тил), иконка ўзгармаслиги мумкин.
10. Analytics: тугма босилиши event (ҳозир борми — текшириш).

**D. Эксплуатация**
11. Ҳар релизда (модул/ном ўзгарса) Knowledge PDF қайта юкланади — релиз checklist'ига қўшилади.
12. 2–4 ҳафтадан кейин баҳолаш: тугма босилиш сони, эга томонидан 10 та тасодифий савол синови.

### Эгадан талаб қилинадигани (қисқача)
- ChatGPT Plus/Team аккаунт (Custom GPT яратиш фақат пуллик режада мавжуд) — ким номига очилиши ҳал қилиниши керак.
- GPT Builder'да созлаш (Instructions/Knowledge/starters'ни dev тайёрлаган ҳолда тасдиқлаш, Capabilities'да Web browsing'ни ёқиқ қолдириш).
- Publish қилиб, ссылкани dev'га бериш.
- Уч тилда синов ўтказиш ва жавоб сифатини баҳолаш.

### Қабул мезони
- Тугма босилганда ChatGPT иловаси/сайти тўғридан-тўғри «AVA ёрдамчиси» GPT'да очилади (Android: илова бўлса — иловада).
- «Шаҳарлараро таксига қандай буюртма бераман?» (3 тилда) — ҳужжатга мос, иловадаги ном/қадамлар билан жавоб.
- «Менинг балансим қанча?» — «буни илова ичида Ҳамён бўлимида кўрасиз, менда бу маълумот йўқ» тарзида жавоб (ўйлаб топмайди).
- Web browsing ёқиқ: AVA'га алоқаси йўқ исталган умумий савол (об-ҳаво, таржима, дастурлаш ва ҳ.к.) ҳам оддий ChatGPT каби, интернет қидируви орқали жавобланади — мавзу бўйича чекланмайди.

### Чекловлар / хавфлар (қарор қабул қилинган ҳолда)
- Фойдаланувчида ChatGPT аккаунти керак (login тўсиғи) — пилотнинг асосий номаълуми.
- Бепул аккаунтда кунлик лимит (OpenAI ўзгартириб туради); Web browsing ёқиқ бўлгани баъзи режаларда квотани тезроқ сарфлаши мумкин.
- Реал маълумот (рейслар, баланс, буюртма ҳолати) йўқ — статик ҳужжат. Actions (ochiq API) — кейинги босқич, керак бўлса.
- Web browsing ёқиқ бўлгани учун AVA'га алоқасиз жавоблар устидан назорат йўқ (OpenAI'нинг умумий веб-қидируви — биз таъминламаймиз).
- Савол матнлари логи йўқ — фақат умумий сон.
- Кириллча ўзбекчада модель заифроқ — Instructions'да мажбурлаш.

### Очиқ саволлар
- ChatGPT Plus/Team аккаунт кимники бўлади (компания аккаунти тавсия).
- Тугма ҳамма туманларда кўринсинми ёки `chatgpt` модул gating'и сақланадими.

---

## В-2. Юк биржаси split — Local dispatch (алоҳида лойиҳа, ТЗ керак)
- [ ] Local dispatch (буюртма/таклиф) — алоҳида лойиҳа сифатида қолади, ушбу вазифа доирасидан чиқарилди.

## В-3. AVAGram видео — кузатув (2026-09-18, commit b40bb65)
- [ ] Релиздан 1–2 ҳафта кейин `tv_clips.playbackStats` (bufferMs/view, bufferEvents/view) ни аввалги 436 мс / 0.08 билан солиштириш.
- [ ] Қарор: мобил тармоқда 720p'ни чеклаш (трафик яна ~40% камаяди, сифат пасаяди).
- [ ] `third_party/video_player_android` — плагин янгиланганда иккала патчни қайта қўллаш: `AvaLoadControl` (LoadControl 20с) ва `AvaMediaCache` (Media3 SimpleCache 150MB + HLS сегмент prefetch; `HttpVideoAsset.unstableWrapWithCache`, илова томонида `MainActivity.kt` `tv_media_cache` канали). Ўлчов (TECNO LH7n, 2026-09-21): свайп→play 2.9 с → ~20 мс (prefetch улгурганда), PSS ўзгармади (508 MB).

## В-5. AVAGram — сегмент кеши кетма-кетлиги (2026-09-21, эга қарори)

Асос: `AvaMediaCache` (Media3 SimpleCache + HLS prefetch) қурилмада ўлчанди — свайп→play 2.9 с → ~20 мс (prefetch улгурганда); cold-path (кеш бўлса ҳам instance яратиш) ~1.7 с.

1. **Б — БАЖАРИЛДИ (2026-09-21):** ўлчов "deferred dispose" гипотезасини рад этди (`_evictIfNeeded` = 0 мс — dispose critical path'да эмас). Ҳақиқий сабаблар ва тузатишлар: (а) player prefetch'дан бошқа variant'ни (480/720p) танлаётган эди → `AvaBandwidthMeter` (патч #3, бошланғич баҳо 100 kbps → биринчи сегмент доим master'даги энг паст variant, кейин ўлчовга қараб кўтарилади); (б) writer + player бир сегментни параллел тортарди → `FLAG_BLOCK_ON_CACHE`; (в) `cancelAll` ўйналаётган клипнинг prefetch'ини бекор қиларди → `markWanted` (pool андозаси); (г) NEXT — 1 сегмент (4 с production), NEXT+1 фақат playlist; retain prefetch'га ≤1 с кутади. Натижа (TECNO, совуқ кеш, 2.2 с темп): свайп→play медиана ~35 мс (10 тадан 6 таси 20–40 мс), ёмони 2.4 с (тармоқ); олдин ҳар свайп 2.9 с. PSS 467 MB (олдин 516). Релиздан кейин `playbackStats` p50 firstFrame кузатилади.
2. **А — БАЖАРИЛДИ (2026-09-21, эга қарори билан муддатидан олдин):** `firebase deploy --only functions` — 144 функция янгиланди, хатосиз (`onTvClipCreatedV2` жумладан: HLS сегмент 3 с + fastTrack360p энди production'да). Эслатма: биринчи уриниш commit'ли ҳолатдан (stash) қилинди ва CLI **тўхтатди** — production'да 5 та `ev_charging` функцияси мавжуд экан (working tree'дан аввал деплой қилинган); шунинг учун тўлиқ working tree'дан деплой қилинди, ҳеч нарса ўчирилмади. Rollback: `d473113`/`f63e8e8` функциялари. **Кузатув:** фақат ЯНГИ transcode қилинган клиплар 3 с; 1–2 ҳафтада `playbackStats` rebuffer/firstFrame солиштирилади.
3. **В — А барқарор бўлгач:** Home'да 3-клип prefetch (NEXT+1 фақат playlist) — `HomeVideoStage._load()`.

## В-4. Видео қотиши, айниқса биринчи юкланган видео — Instagram/TikTok/Facebook тадқиқоти асосида тўлиқ таклиф

**Ҳолат:** режалаштирилган (2026-09-18, тадқиқот + код таҳлили асосида).
**Муаммо (эга ташвиши):** видеоролик қотиши, **айниқса биринчи марта юкланган видеонинг қаттиқ қотиши**.

### Асосий топилма — кодда тасдиқланган race condition
Видео юкланганда (`tv_publish_screen.dart`) хом файл дарҳол Storage'га тушади ва Firestore'да `tv_clips` ҳужжати шу заҳоти яратилади — клип **дарҳол лентада кўринади ва ўйнатилади**. Шу пайтда фонда [onTvClipCreatedV2](functions/index.js:11555) trigger'и асинхрон равишда HLS + кўп-сифатли вариантларни ясайди (4GiB/2CPU, то 540s). Муаммо: [tv_clip.dart:191](lib/features/tv_market/models/tv_clip.dart:191) даги `isPlayable => processingStatus != 'error'` — `processing` ҳолатини `ready` билан бир хил деб ҳисоблайди. Демак трансkodlash тугамагунча ўтган ҳар бир томошабин (жумладан юкловчининг ўзи — энг фаол "биринчи томошабин") хом, HLS'сиз файлга тушади.

### Тадқиқот хулосаси (Instagram, Facebook, TikTok, WeChat)
- **Instagram:** Reels узун битта файл эмас, 2–3 сонияли қисқа HLS/TS сегментлар сифатида узатилади; глобал CDN edge серверлар орқали ("энг яқин edge node жавоб беради").
- **TikTok ва бошқа қисқа-видео платформалар:** блинд/фиксланган ҳажмда олдиндан юклаш эмас, балки тармоқ ҳолати ва scroll тезлигига мослашувchi (adaptive/predictive) prefetch — тадқиқотлар rebuffer'ни 13–15% гача камайтиришини кўрсатади.
- **Умумий қоида:** ҳеч бир платформа фойдаланувчига видеонинг ХОМ шаклини кўрсатмайди — камида битта тезкор, паст сифатли rendition тайёр бўлмагунча видео "ўйнашга тайёр" деб белгиланмайди.

### Қадамлар — устуворлик тартибида

**0-босқич — БАЖАРИЛДИ (2026-09-18, ҳали commit қилинмаган — working tree'да):**

Ягона canonical манба — `processingStatus` ('processing'|'ready'|'error') — ўзгармайди, лекин иккита **аниқ номли, ҳисобланадиган (derived)** getter орқали икки хил савол ажратилади (иккиси ҳам бир манбадан, параллел/мустақил байроқ эмас):
- `isPlayable` ([tv_clip.dart:191](lib/features/tv_market/models/tv_clip.dart:191), ЎЗГАРМАЙДИ) — фақат лентада кўриниш учун (`!= 'error'`); `processing` клиплар ҳам poster/thumbnail + "Видео тайёрланмоқда..." белгиси билан лентада кўринаверади.
- `canStartPlayback` (ЯНГИ, derived: `processingStatus == 'ready'`) — реал network playback бошлаш учун қатъий шарт.

**Икки қатламли ҳимоя (defense-in-depth), UI'да эмас, шарт сифатида:**
1. UI қатлами: `canStartPlayback == false` бўлса, плеер ишга туширилмайди, poster кўрсатилади.
2. Плеер қатлами (мажбурий, асосий тўсиқ): [TvPlayerPool.prepare(String url)](lib/features/tv_market/services/tv_player_pool.dart:70) имзоси ўзгаради — энди `canStartPlayback` (ёки status enum) билан бирга чақирилади; `false` бўлса, `_create()` ҳеч қандай controller яратмасдан `null` қайтаради (+ огоҳлантирувчи log/analytics — бу ҳолат юқори қатламда хато борлигини англатади). Шунда келажакда янги экран (масалан profile preview) ёки эскириб қолган fallback URL ноаниq рухсат билан ХОМ MP4'ни тасодифан ўйнатиб юбормайди — гуард URL манбасидан қатъи назар ишлайди.
3. Юкловчининг ўзи учун махсус ҳолат: у ўз видеосини серверда тайёр бўлмасдан туриб ҳам ЛОКАЛ файлдан (тармоққа қайтмасдан) дарҳол кўра олади — фақат бошқаларга "processing" кўринади.

**0-босқич ТЎЛИҚ БАЖАРИЛДИ (2026-09-18, commit [9ebd34c](../../commit/9ebd34c)):**
- [tv_clip.dart](lib/features/tv_market/models/tv_clip.dart) — `canStartPlayback` getter қўшилди, `isPlayable` ўзгармади.
- [tv_player_pool.dart](lib/features/tv_market/services/tv_player_pool.dart) — `prepare(url, {isReady})` ва `retain(urls, {isReady})` гуард билан (рад этилса — `debugPrint` + `CrashReport.nonFatal('tv_player_not_ready_guard')`).
- [tv_market_feed_screen.dart](lib/features/tv_market/screens/tv_market_feed_screen.dart), [home_video_stage.dart](lib/features/tv_market/widgets/home_video_stage.dart) — барча чақирув жойлари `clip.canStartPlayback`ни узатади; `TvClipProcessingBadge` ([tv_clip_poster.dart](lib/features/tv_market/widgets/tv_clip_poster.dart)) postер устида кўрсатилади.
- **3-банд бажарилди:** [tv_publish_screen.dart](lib/features/tv_market/screens/tv_publish_screen.dart) — `_showLocalPreview()`: юкловчи публиш тугагандан кейин (Storage кэши ўчирилишидан ОЛДИН) ўз видеосини локал файлдан модал preview'да дарҳол кўради; лентага/pool'га умуман тегмайди.
- `tv_clip_processing`, `tv_publish_local_preview_hint/close` калитлари уч тилга ҳам қўшилди.
- **Unit test бажарилди:** [tv_player_pool_guard_test.dart](test/features/tv_market/tv_player_pool_guard_test.dart) — `isReady: false` → controller ҳеч қачон яратилмаслигини тасдиқлайди.
- `flutter analyze` — хатосиз. `flutter test` — 192та тестдан 190таси ўтди; **2та xato** (`home_grid_layout_test.dart`) — текширилди, бу ишга **алоқаси йўқ**, аввалдан мавжуд (HEAD'да ҳам, файллар бу сессияда тегилмаган) — алоҳида масала сифатида қолдирилди.
- Йўл-йўлакай тузатилди: `service_runtime_gate_test.dart`даги эскирган "yuk alias даври" тести (kModuleIdAliases ўчирилгандан кейин янгиланмай қолган эди) янги архитектурага мослаб қайта ёзилди.

**Рад этилган альтернатива:** клиентда тўлиқ кўп-сифатли HLS'ни (юклашдан олдин, фонда) тайёрлаб, серверга тайёр ҳолда юбориш — рад қилинди, чунки бу қурилма ресурси (батарея/вақт, айниқса бюджет телефонларда), кўпроқ мобил трафик ва Android'нинг узоқ фон жараёнини ишончсиз тўхтатиши хавфини (Doze/battery optimization) юкловчининг ўзига юклайди — айнан заиф қурилма/тармоқдаги фойдаланувчи учун ёмонроқ савдо.

**1-босқич — БАЖАРИЛДИ (2026-09-18, ҳали commit/deploy қилинмаган):**
1. **Adaptive/predictive prefetch** — [TvNetworkQualityService](lib/features/tv_market/services/tv_network_quality_service.dart)га `recordBufferHealth()`/`adaptivePrefetchTimeout()` қўшилди: сўнгги 5 клипнинг ҳақиқий буферлаш натижасига (соғлом/timeout) қараб [TvMarketFeedScreen](lib/features/tv_market/screens/tv_market_feed_screen.dart)нинг `_waitUntilHealthy()`даги фиксланган 2.5s ўрнига 1.5s–4s оралиғида адаптив таймаут ишлатилади. Scroll тезлиги: `_onPageChanged`даги саҳифалар ораси 700мс'дан қисқа бўлса (тез свайп) — шу цикл учун `_pool.retain(...)` (prefetch) умуман ўтказиб юборилади, бекорга трафик сарфланмайди. Unit test: [tv_network_quality_adaptive_test.dart](test/features/tv_market/tv_network_quality_adaptive_test.dart) (5 та тест, ўтди).
2. **Қисқа HLS сегментлар** — `TV_CLIP_HLS_SEGMENT_SECONDS` ([functions/index.js:11127](functions/index.js:11127)) 4 → 3 сонияга туширилди; мос равишда клиент томонидаги `_prefetchHealthyAhead` ҳам 4s → 3s га мослаштирилди. **Эслатма (ўзгармади):** фақат deploy қилингандан кейин, ЯНГИ transcode қилинадиган клипларга таъсир қилади — мавжудлари эски 4s'да қолади.
- **Ҳали қилинмаган:** `firebase deploy --only functions` (HLS сегмент ўзгариши production'га чиқиши учун) — ва production'да ҳақиқий playbackStats орқали натижани ўлчаш (b40bb65'даги услубда, 1-2 ҳафта кузатув).

**2-босқич — БАЖАРИЛДИ, лекин режадан фарқли усулда (2026-09-18):**

**Муҳим қайта кўриб чиқиш:** дастлабки режа — "энг паст (360p) вариантни биринчи ясаб... алоҳида белги (`lowQualityReady`)" — кодни ўрганганда НОТЎҒРИ асосга қурилган экани маълум бўлди: асосий pipeline барча 3 сифатни (720p+480p+360p) **БИТТА ffmpeg чақируви**да (`filter_complex split`, манба бир марта декодланиб) ишлаб чиқаради — учаласи ҳам БИР ПАЙТДА тугайди. Демак `TV_CLIP_VARIANT_SPECS` тартибини ўзгартириш ёки алоҳида `lowQualityReady` байроғи ҳеч нарсани тезлаштирмас эди (ва иккинчиси 0-босқичда белгиланган "ягона canonical манба" қоидасини бузарди).

**Ҳақиқий ечим:** [fastTrack360pIfPossible](functions/index.js) — асосий, синалган pass'дан ОЛДИН ишлайдиган, АЛОҲИДА, тезкор, фақат-360p preliminary pass:
- Асосий pipeline'га (ҳужжатда кўп марта "синалган қийматлар" деб қайд этилган CRF/maxrate/keyframe созламалари) ҳеч қандай ўзгартириш киритилмади — рискни камайтириш учун.
- Муваффақиятли бўлса, `videoVariants.360p` (dot-notation, mavjud maydonlarga tegmaydi) ва `processingStatus: 'ready'`ни ДАРҲОЛ ёзади — ЯГОНА canonical манба (`processingStatus`) сақланади, янги параллел байроқ йўқ.
- Алоҳида Storage йўли (`360p_fast.mp4`, асосийнинг `360p.mp4`сидан фарқли) — асосий pass тугаганда фаол томоша қилинаётган файлнинг download token'ини бекор қилиб қўймаслик учун.
- Хато бўлса бутунлай e'тиборсиз қолдирилади (best-effort) — асосий pipeline барибир ишлайверади.
- `tv_clip_variants/{clipId}/` prefiksi orqali klip o'chirilganda avtomatik tozalanadi (mavjud mexanizm).

**Мониторинг қилиш керак:** қўшимча pass умумий funktsiya вақтини оширади (540с бюджетга нисбатан — логда `JAMI Xs / 540s budjet` кузатилади); узоқ (600с) клипларда бюджетга яқинлашиш эҳтимоли назорат қилиниши керак.

**3-босқич — КЕЙИНРОҚ (эга қарори, 2026-09-18) — узоқ муддатли (инфратузилма):**
Cache-Control сарлавҳаси аллақачон тўғри ('public, max-age=31536000, immutable', ҳам original ҳам variant файлларда) — лекин Firebase Storage ҳозир ҳақиқий CDN edge тармоғи орқали эмас, тўғридан-тўғри us-central1'дан хизмат қилади. Cloud CDN (HTTPS Load Balancer + GCS backend) орқали видео хизмат қилиш.

**Нега кейинроқ:** бошқа беш бандан фарқли — янги, ойлик доимий харажат келтирувчи GCP ресурси (~$20-50+/ой, трафикка қараб ошади, git revert билан бекор қилинмайди), алоҳида домен (CDN учун subdomain, DNS созлаш — фақат эга ҳал қила оладиган ташқи қарор) ва SSL сертификат тасдиғи (соатлаб чўзилиши мумкин) керак.

**Кутилган натижа (эга билан муҳокама қилинди):** CDN асосан **кўпчилик томошабин** учун фойдали (2-чи, 3-чи, ... N-чи томошабин — яқин edge'дан тезроқ, latency ~300-500мс → ~50-150мс) — **лекин айнан "биринчи марта юкланган видео" муаммосига тўғридан-тўғри ёрдам бермайди** (энг биринчи сўров барибир origin'га боради, cache miss). Бу муаммо аллақачон 0/2-босқичда (processing гуарди + тезкор 360p pass) ҳал қилинган. Демак CDN — комплементар, шошилинч эмас.

**Бошланиш шарти:** (1) домен танланиши, (2) ойлик харажат тасдиғи.

### Қабул мезони
- Янги юкланган видео `processing` ҳолатида ХОМ файл билан қотиб қолмайди — poster + "тайёрланмоқда" ҳолати кўрсатилади.
- `TvPlayerPool.prepare()`га `canStartPlayback: false` билан URL узатилса, controller ҳеч қачон яратилмайди (unit test билан тасдиқланади) — гуард фақат UI'да эмас, шу ерда ҳам ишлайди.
- Заиф ва кучли тармоқда prefetch хатти-ҳаракати аниқ фарқланади (analytics/`playbackStats` орқали тасдиқланади).
- Янги transcode қилинган клиплар 2–3s сегментда; эски 4s билан солиштирилганда firstFrame/rebuffer кўрсаткичи ёмонлашмагани тасдиқланади.

---

## В-6. iOS — App Store'да нашр (улашиш ҳаволасидаги «боши берк кўча»)

**Ҳолат:** очиқ, ҳали бошланмаган (2026-09-24, эга тасдиқлади: «ҳозирча йўқ»).

**Муаммо:** AVAGram видеосини Telegram каналига улашганда постдаги ҳавола **фақат Google Play**'га (`play.google.com/store/apps/details?id=uz.ava.gurlan`, «AVA Zona») олиб боради. Каналда iPhone'дан ўқийдиганлар бўлса, улар учун бу **боши берк кўча** — Android иловасининг веб саҳифаси очилади, ўрната олмайди. Каналнинг обуначилари қанча iOS эканига қараб, бу улашишдан келадиган янги фойдаланувчиларнинг бир қисмини йўқотади.

**Мақсад:** AVA iOS'да ҳам мавжуд бўлсин ва улашиш ҳаволаси қурилмага қараб тўғри дўконга олиб борсин.

### Қадамлар

**A. Нашр (эга)**
1. Apple Developer Program аккаунти (йиллик тўлов, ташкилот ёки шахс номига — ҳал қилиш керак).
2. iOS build созламалари: bundle id, имзо сертификатлари, provisioning.
3. App Store Connect'да илова картаси, скриншотлар, махфийлик сиёсати (Android'дагиси қайта ишлатилади), App Review'дан ўтиш.

**B. Иловада (dev) — нашрдан кейин**
4. `lib/core/app_share.dart` — `kAvaAppStoreUrl` константаси қўшилади (`kAvaPlayStoreUrl` ёнига).
5. Улашиш матнидаги ҳавола **қурилмага қараб** танланадиган бўлади. Икки йўл:
   - **Оддий:** улашаётган қурилма Android бўлса Play, iOS бўлса App Store ҳаволаси. Камчилиги — Android'дан улашилган пост iPhone'да ўқилса, барибир Play кўрсатади.
   - **Тўғри йўл (тавсия):** ҳавола яна `/clip/{id}` саҳифасига қайтарилади, саҳифа эса `User-Agent` бўйича iOS/Android'ни аниқлаб керакли дўконга йўналтиради. Саҳифа ва `clipPage` функцияси **ҳозир ҳам production'да турибди** (2026-09-24 да улашиш оқимидан чиқарилган, лекин ўчирилмаган) — `avaClipShareUrl()` ҳам кодда сақланган, шунинг учун қайтариш арзон.
6. `test/features/tv_market/tv_clip_share_test.dart` янгиланади (ҳозир матнда `/clip/` йўқлигини текширади).

**Қабул мезони:**
- iPhone'да Telegram'даги постдаги ҳавола босилса — App Store'даги AVA саҳифаси очилади, Android'да эса Play.
- Илова ўрнатилган бўлса иккала платформада ҳам дўкон «Очиш» тугмасини кўрсатади.

**Ким:** A — эга (аккаунт, нашр); B — dev (нашрдан кейин, ~1 кун).

**Боғлиқ қарор:** App Links/Universal Links (ҳаволани босганда илова **айнан ўша видеода** очилиши) — 2026-09-24 да эга «ҳозирча керак эмас» деди. iOS иши бошланса, иккаласини бирга кўриб чиқиш арзонроқ.

---

## В-7. «СОТИНГ» модулини ўчириш — 2-босқич (эга қарори кутилмоқда)

**Ҳолат:** 1-босқич бажарилди (2026-09-24), 2-босқич очиқ.

**1-босқичда нима қилинди (код, хавфсиз):**
- Home'даги «СОТИНГ» плиткаси, `HomeModulesCatalog`даги `sell` ёзуви, `kKnownModuleIds`/admin ёрлиғи, `home_module_sell` + `online_market_sell_*` + `home_seller_cta(_subtitle)` l10n калитлари (3 тил), ишлатилмаган `seller_cta_banner.dart` виджети — ўчирилди. Плитка мазмуни («Янги эълон», «Менинг эълонларим», лента) Бозор модулида тўлиқ бор эди, шунинг учун фойдаланувчи ҳеч нима йўқотмайди.
- «Сотув маркази»га (`features/sell/*`) кириш йўллари ёпилди: push `screen: 'sell'` / `type: 'sell_offer'` энди Янгиликлар → «Хабарлар» табига боради; admin панелдаги «Сотиш аризалари» ёрлиғи яширилди. **Код, CF, rules, индекс ва мавжуд `sell_submissions` маълумоти тегилмаган** — ёрлиқ қаторини қайтариш билан панел яна очилади.

**Прод'да қиладиган ишлар (1-босқич учун, ҳали бажарилмаган):**
- [ ] `search_index/sell` ёзувини ўчириш — стандарт `seed_search_index.js` эски ёзувни ўчирмайди, `yuk_birja`дагидек бир марталик Admin SDK скрипти керак. Ўчирилгунча иккита вақтинчалик fallback қасддан қолдирилди: `home_screen._openSearchResult` (`case 'sell'` → Бозор) ва `home_global_search` иконка ёзуви.
- [ ] `config/module_defaults`даги орфан `modules.sell` майдонини ўчириш.
- [ ] `scripts/build_combined_web.ps1` + `firebase deploy --only hosting` — admin панелда «Сотиш аризалари» ёрлиғи ва «Sotish» модул қатори йўқолиши учун.

**2-босқич — қарор керак:** «Платформага сотаман → курьер йиғиб олади → омбор» бизнеси керакми?
- **Керак эмас** → `features/sell/*`, `sell_submissions` CF'лари (`submitSellSubmission`, `adminUpdateSellSubmission`, `onSellSubmissionUpdate`), firestore rules (2294–2330) ва 4 та индекс ўчирилади. **Лекин** биргаликда курьернинг «йиғиб олиш» модули ва омбор кириши ҳам кетади: `adminCreateCollectionTask` `submissionId` талаб қилади, яъни `sell_submissions`сиз `collection_tasks` манбасиз қолади.
- **Керак** → код ҳозирги ҳолида қолади, фақат кириш йўллари ёпиқ туради.

**Олдиндан бажарилиши шарт:** `SellSubmission.pickupFieldsFromAddress()` статик методини нейтрал жойга кўчириш — уни шаҳарлараро такси ишлатади ([intercity_pickup_sheet.dart:212](../lib/features/intercity_taxi/passenger/widgets/intercity_pickup_sheet.dart)), модель ўчса компиляция синади.

**Эслатма:** CF ва hosting ўчириш `firebase deploy` талаб қилади — git revert билан қайтмайди.

---

## В-8. Шаҳарлараро бронь — қоидаларни деплой қилиш (РЕЛИЗДАН КЕЙИН)

**Ҳолат (2026-09-25):** сервер тайёр ва деплой қилинган, **қоидалар атайлаб деплой қилинмаган**.

**Муаммо:** `intercity_drivers.seats` майдонини ҳар қандай чақирувчи (ҳатто тизимга кирмаган) қайта ёза оларди (`intercityDriverSeatBookingPatch`) — рейсни «тўлдириб» қўйиш ёки бўш ўрин «ясаш» мумкин эди. Брон транзакцияси мижозда эди.

**Қилинди:** `createIntercityBooking` / `cancelIntercityBooking` / `completeIntercityBooking` callable'лари (us-central1) — **деплой қилинган**; илова шуларга ўтказилди; `firestore.rules`да тешик ёпилди (репозиторийда, деплойсиз).

**Нега деплой қилинмади:** Play'даги жорий версия броньни ҳали ҳам мижозда яратади ва `seats`ни ўзи ёзади. Қоидалар ҳозир деплой қилинса — **эски иловадаги фойдаланувчилар брон қила олмай қолади**.

**Қадам (эга):** янги версия Play'да чиққач ва фойдаланувчилар янгилангач:

```
firebase deploy --only firestore:rules
```

**Қабул мезони:** янги иловада брон / бекор қилиш / якунлаш ишлайди; Firestore консолидан `intercity_drivers` ҳужжатига қўлда `seats` ёзиб кўрилганда рад этилади.

---

## Бажарилди

### В-2. Юк биржаси split — қолган ишлар (2026-09-18, production ops)
- [x] `firebase deploy --only functions` — жорий commit (d473113) production'га чиқарилди. Деплой муваффақиятли ("Deploy complete!"); бир нечта функцияда (`submitSellSubmission`, `adminUpdateSellSubmission`, `adminDeleteMarketAd`, `adminGetWarehouseStock`) вақтинчалик "Quota Exceeded" бўлиб, автоматик қайта уринишдан кейин барчаси муваффақиятли янгиланди.
- [x] Search index тузатилди: `node functions/tools/seed_search_index.js` орқали `yuk_local`/`yuk_intercity` хизмат ёзувлари қўшилди; эски `search_index/service_yuk_birja` ёзуви қўлда (Admin SDK, бир марталик скрипт орқали) ўчирилди — стандарт скрипт бу ёзувни ўчирмайди, шунинг учун алоҳида қадам сифатида бажарилди.
- [x] Admin config: `config/module_defaults` ҳужжатида `yuk_local` ва `yuk_intercity` учун `status: enabled` аниқ ёзилди (аввалги `yuk_birja` статусига мос) — энди alias'дан мустақил, admin панелдан алоҳида бошқарилади.
- [x] Эски `yuk_birja` бутунлай олиб ташланди: `kKnownModuleIds`/`kModuleIdAliases` ([service_module_config.dart](lib/models/service_module_config.dart)), alias fallback логикаси ([service_config_holder.dart](lib/core/service_config_holder.dart)), admin панель ёрлиғи ([service_config_admin_screen.dart](lib/features/admin_web/screens/service_config_admin_screen.dart)) кодидан, ва орфан `modules.yuk_birja` майдони production `config/module_defaults`дан. **Эслатма:** тарихий маълумот билан мослик учун сақланган жойлар (`global_search.dart`, `push_navigation.dart`, `home_screen.dart` даги эски `yuk_birja` индекс/push фолбэклари, `functions/index.js`даги idempotent `deleteSearchIndexEntry`) — қасддан тегилмади.
- [ ] **Ҳали қолган:** бу code ўзгаришлари admin панелида кўриниши учун `scripts/build_combined_web.ps1` + `firebase deploy --only hosting` керак (жонли админ панели ҳали эски build'да — `yuk_local`/`yuk_intercity` алоҳида қатор сифатида кўринмайди, "Yuk birjasi" ҳам ҳали ўчмаган). Бу асосий фойдаланувчи веб-иловасини ҳам биргаликда деплой қилади.
