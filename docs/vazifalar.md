# AVA — очиқ вазифалар рўйхати

Ҳар вазифа: мақсад → қадамлар → қабул мезони → ким. Бажарилгач — сана ва commit билан «Бажарилди» бўлимига кўчирилади.

---

## В-1. «AVA ёрдамчиси» — ChatGPT Custom GPT (пилот)

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
- [ ] `third_party/video_player_android` — плагин янгиланганда `AvaLoadControl` патчини қайта қўллаш.

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

## Бажарилди

### В-2. Юк биржаси split — қолган ишлар (2026-09-18, production ops)
- [x] `firebase deploy --only functions` — жорий commit (d473113) production'га чиқарилди. Деплой муваффақиятли ("Deploy complete!"); бир нечта функцияда (`submitSellSubmission`, `adminUpdateSellSubmission`, `adminDeleteMarketAd`, `adminGetWarehouseStock`) вақтинчалик "Quota Exceeded" бўлиб, автоматик қайта уринишдан кейин барчаси муваффақиятли янгиланди.
- [x] Search index тузатилди: `node functions/tools/seed_search_index.js` орқали `yuk_local`/`yuk_intercity` хизмат ёзувлари қўшилди; эски `search_index/service_yuk_birja` ёзуви қўлда (Admin SDK, бир марталик скрипт орқали) ўчирилди — стандарт скрипт бу ёзувни ўчирмайди, шунинг учун алоҳида қадам сифатида бажарилди.
- [x] Admin config: `config/module_defaults` ҳужжатида `yuk_local` ва `yuk_intercity` учун `status: enabled` аниқ ёзилди (аввалги `yuk_birja` статусига мос) — энди alias'дан мустақил, admin панелдан алоҳида бошқарилади.
- [x] Эски `yuk_birja` бутунлай олиб ташланди: `kKnownModuleIds`/`kModuleIdAliases` ([service_module_config.dart](lib/models/service_module_config.dart)), alias fallback логикаси ([service_config_holder.dart](lib/core/service_config_holder.dart)), admin панель ёрлиғи ([service_config_admin_screen.dart](lib/features/admin_web/screens/service_config_admin_screen.dart)) кодидан, ва орфан `modules.yuk_birja` майдони production `config/module_defaults`дан. **Эслатма:** тарихий маълумот билан мослик учун сақланган жойлар (`global_search.dart`, `push_navigation.dart`, `home_screen.dart` даги эски `yuk_birja` индекс/push фолбэклари, `functions/index.js`даги idempotent `deleteSearchIndexEntry`) — қасддан тегилмади.
- [ ] **Ҳали қолган:** бу code ўзгаришлари admin панелида кўриниши учун `scripts/build_combined_web.ps1` + `firebase deploy --only hosting` керак (жонли админ панели ҳали эски build'да — `yuk_local`/`yuk_intercity` алоҳида қатор сифатида кўринмайди, "Yuk birjasi" ҳам ҳали ўчмаган). Бу асосий фойдаланувчи веб-иловасини ҳам биргаликда деплой қилади.
