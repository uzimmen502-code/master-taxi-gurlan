# Қурилмага боғлаш ва «QR орқали кириш» — таҳлил ва таклиф

> Сана: 2026-11-28 · Тури: фақат ўқиш (код, deploy, prod ўзгармади)
> Манбалар: server = `.claude/worktrees/dup-audit` (55596a4f, `functions/index.js`,
> `firestore.rules`); client = `.claude/worktrees/fjobs` (HEAD d25aff1b);
> prod — фақат ўқиш (Firestore REST GET/count, `gcloud functions describe`).
> Белгилар: **CONFIRMED** (код/prod билан текширилди) · **INFERRED** (кучли хулоса) ·
> **PROPOSED** (таклиф) · **UNKNOWN**.

---

## 0. Энг муҳими (эгага қисқа)

1. **ХАВФСИЗЛИК — ШОШИЛИНЧ.** Prod'да `settings/app.deviceBindingAutoApprove = true`
   (CONFIRMED, 2026-11-28 ўқилди). Бу ҳолатда `checkDeviceBinding` (auth талаб
   қилмайди) **ҳар қандай** телефон рақами + **ҳар қандай** қурилма учун дарҳол
   `customToken` беради. SMS/OTP йўқ, App Check йўқ (CONFIRMED: client'да
   `verifyPhoneNumber`/`PhoneAuthProvider` йўқ, server'да `enforceAppCheck` йўқ).
   Яъни **бировнинг рақамини билган одам унинг ҳисобига кира олади** (ҳамён,
   буюртмалар, чатлар, дўкон). Эски қурилмага хабар ҳам бормайди.
   `checkDeviceBinding` блоки 2026-10-06 deploy'дан бери ўзгармаган → жонли код
   = репо (INFERRED: git тарихи; gcf zip солиштирилмади).
2. **Бугун компьютерда кириш мумкинми?** Амалда **ҳа** — айнан шу тешик туфайли:
   браузерда рақам киритилади → автоматик тасдиқ → кирилди. Телефон ҳам чиқиб
   кетмайди, иккаласи бирга ишлайди. Лекин бу «хусусият» эмас, хавфсизлик тешиги.
3. Сессияларни бошқариш йўқ: битта ҳисобга нечта қурилма кирганини кўриш,
   биттасини «Чиқариш» мумкин эмас; `revokeRefreshTokens` фақат ҳисобни ўчиришда
   (CONFIRMED).
4. **Таклиф:** аввал 0-босқич (тешикни ёпиш — эганинг қарори керак), кейин
   «QR орқали кириш» (WhatsApp Web каби). Баҳо: ~8–11 иш куни, APK керак.

---

## 1. Бугун кириш қандай ишлайди (ҳозирги ҳолат)

### 1.1. Onboarding телефон қадами — CONFIRMED

`onboarding_controller.dart` `checkPhoneDeviceLock()`:
1. `DeviceFingerprintService().collect()` → 64 белгили SHA-256 `hash`.
2. `checkDeviceBinding({phone, deviceFingerprintHash, fingerprint})` чақирилади
   (europe-west1, **auth йўқ**).
3. Жавоб `trusted_device` бўлса — жавобдаги `customToken` билан
   `signInWithCustomToken`; бўлмаса `createPhoneSession` (`establishPhoneSession`).
4. Бошқа жавоблар (`phone_bound_other_device`, `device_bound_other_phone`,
   `blocked`) → `device_binding_conflict_sheet.dart`.

**SMS код йўқ.** Рақам эгалиги ҳеч қаерда исботланмайди.

### 1.2. `DeviceFingerprintService` — ичида нима бор — CONFIRMED (код)

Hash 8 та калитдан: `androidId | firebaseInstallationId | hardwareId | model |
brand | device | product | fingerprint` (`platform` hash'га кирмайди).

| Калит | Android | WEB (компьютер браузери) |
|---|---|---|
| androidId | `ANDROID_ID` (SSAID) | бўш |
| firebaseInstallationId (FID) | FID | FID (браузер IndexedDB'да) |
| hardwareId | serial, бўлмаса androidId | бўш |
| model | `model` | **userAgent** тўлиқ |
| brand | `brand` | `vendor` (масалан «Google Inc.») |
| device | `device` | браузер номи (chrome/edge…) |
| product | `product` | `platform` (Win32…) |
| fingerprint | **Build.fingerprint** (OS версияси ичида) | браузер тили |

**Барқарорлик (INFERRED — Firebase/Android/браузер умумий хатти-ҳаракатидан):**
- Android: илова қайта ўрнатилса ёки «маълумотни тозалаш» — FID янгиланади →
  hash ўзгаради. OS янгиланса — `Build.fingerprint` ўзгаради → hash ўзгаради.
  Factory reset — androidId ҳам ўзгаради. Шунинг учун prod'да
  `device_bindings` = 587, `users` = 217, `device_aliases` = 212 (CONFIRMED сонлар).
- **WEB:** бир браузер профилида, сайт маълумоти тозаланмаса — барқарор. Лекин:
  - браузер ҳар катта янгиланганда userAgent ўзгаради (Chrome ~ҳар 4 ҳафтада) →
    **янги «қурилма»**;
  - бошқа браузер, бошқа профиль, инкогнито (ҳар сафар янги FID) → янги қурилма;
  - сайт маълумоти/кэш тозаланса → янги FID → янги қурилма;
  - FID олинмаса (`catch` → `''`), hash фақат userAgent+тилдан иборат бўлиб
    қолади → **бир хил браузер версиясидаги ҳамма учун бир хил hash** (тўқнашув
    хавфи). Бу ҳолат қанчалик тез-тез бўлиши — UNKNOWN.
  - Хулоса: **web fingerprint сессиялар/браузерлар орасида барқарор эмас.**

### 1.3. Коллекциялар — CONFIRMED

| Коллекция | Калит | Маъно | Rules |
|---|---|---|---|
| `device_bindings/{hash}` | hash | бу қурилма қайси рақамга боғланган (`phone`, `fingerprint`, `failedAttempts`, `isBlocked`, `verifiedMethod`) | `get: true` (auth'дан олдин), `list: admin`, write: false |
| `device_aliases/{phone}` | рақам | бу рақам қайси **битта** hash'га боғланган | read: admin, write: false |
| `device_transfer_requests/{id}` | авто | эски қурилмадан тасдиқ сўрови (TTL 30 дақ) | read: эгаси/admin, write: false |
| `pending_codes/{phone}` | рақам | эски «админ коди» оқими | read: эгаси/admin, write: false |
| `device_change_requests/{id}` | авто | эски қўлда сўров | create: ҳар қандай auth |

«Битта рақам = битта қурилма» фақат **боғлаш** даражасида: `device_aliases/{phone}`
да битта hash сақланади. **Сессия** даражасида чеклов йўқ.

### 1.4. `checkDeviceBinding` қарор дарахти — CONFIRMED (`index.js:6687`)

1. Hash бўйича binding бор:
   - блокланган → `blocked`;
   - шу рақамга боғланган → `trusted_device` + `customToken`;
   - бошқа рақамга боғланган → **autoApprove ON бўлса: қайта боғлаб token беради**;
     OFF бўлса `failedAttempts+1`, 5 та → 30 дақ блок.
2. Binding йўқ, лекин рақамнинг alias'и бошқа hash'да →
   **autoApprove ON бўлса: қайта боғлаб token**; OFF бўлса `phone_bound_other_device`
   (+ эски қурилма номи).
3. Иккаласи ҳам йўқ (биринчи кириш) → `forceDeviceBindingLink(fingerprint_first_bind)`
   + token. (autoApprove OFF бўлса ҳам — ҳеч ким кирмаган рақамни ҳар ким эгаллайди.)

`forceDeviceBindingLink`: эски hash'да `phone: ''`, `unboundAt` қўяди; alias'ни
янги hash'га кўчиради. **Тарих сақланмайди** (binding устидан ёзилади), эски
қурилмага хабар юборилмайди, `admin_audit`'га ёзилмайди.

### 1.5. `createPhoneSession` / token — CONFIRMED (`index.js:727, 6840`)

- `device_bindings/{hash}.phone == phone` ва блок йўқ бўлса →
  `createPhoneCustomToken(phone)`.
- `getUserByPhoneNumber(+998…)` ёки `createUser({phoneNumber})` → **ҳар доим бир
  хил Firebase uid** (рақамга битта).
- `setCustomUserClaims({phone_number})` (доимий claim) + `createCustomToken(uid,
  {phone_number})`. Rules `isOwner/isAdmin` айнан `token.phone_number` га таянади.
- Демак hash + рақам = калит. Hash тўлиқ сир эмас: уни билган одам
  `device_bindings/{hash}` ни `get` қила олади, admin экранида рўйхат бор. (autoApprove ON ҳолатида эса
  hash ҳам керак эмас.)

### 1.6. Эски қурилмадан тасдиқлаш (peer transfer) — CONFIRMED

1. Янги қурилма: conflict sheet → «Эски қурилмадан тасдиқлаш» →
   `requestDeviceTransfer` (auth йўқ; кунига 5 та; TTL 30 дақ; битта фаол pending).
2. Эски қурилмага in-app/push хабар (`notifyDeviceTransferRequest`,
   `screen: device_transfer`).
3. Янги қурилмада `device_transfer_pending_screen.dart` ҳар 3 сонияда
   `getDeviceTransferStatus` сўрайди.
4. Эски қурилма: `DeviceTransferInboxService.checkOnce()` (илова очилганда,
   **web'да ишламайди**: `if (kIsWeb) return`) ёки push босилганда
   `DeviceTransferApproveScreen` → `respondDeviceTransfer(approve)`:
   auth + `token.phone_number == req.phone` + `deviceFingerprintHash == req.fromHash`.
5. Approve → `forceDeviceBindingLink(peer_device_transfer)` +
   `users/{phone}.security = {deviceTrustMode:'limited', deviceTrustUntil: +24 соат}`.
6. Янги қурилма `createPhoneSession` → кирди.

Prod'да `device_transfer_requests` = **0 та** (CONFIRMED) — autoApprove ON бўлгани
учун бу оқим ҳеч қачон ишлатилмаган (INFERRED).

### 1.7. «deviceTrustMode == limited» 24 соат — CONFIRMED

- Фақат peer transfer'да қўйилади.
- Текширилади: `requestPayout` (`index.js:5966`) ва Telegram ҳамён ботидан пул
  ечиш (`telegram_wallet_bot.js:546`). Client: `wallet_withdraw_panel.dart`
  `device_trust_limited` кодини кўрсатади.
- **Текширилмайди** (INFERRED, grep натижаси): `walletToCash`, ҳамён билан буюртма,
  бошқа пул йўллари. autoApprove ва admin йўлларида limited умуман қўйилмайди.

### 1.8. `phone_reverify_screen` ва `auth_restore_screen` — CONFIRMED

- `AuthRestoreScreen`: `FirebaseAuth.currentUser != null` бўлса **дарҳол уйга** —
  binding текширилмайди. Бўлмаса сақланган `user_phone` + fingerprint →
  `checkDeviceBinding` → token; муваффақиятсиз → `PhoneReverifyScreen`.
- `PhoneReverifyScreen`: рақам киритилади → `checkDeviceBinding` → conflict sheet
  ёки `createPhoneSession`.

### 1.9. Admin йўллари — CONFIRMED

`adminSetDeviceBindingAutoApprove` (глобал тугма, аудитсиз),
`adminAutoApproveDeviceBinding`, `adminManualApproveDeviceBinding`,
`adminUnblockDeviceBinding`, `adminRejectDeviceBinding` (binding + alias ўчади),
`migrateOldBindings`. Эски `pending_codes` оқими (`requestPendingCode` →
`autoApprovePendingCode` триггери кодни **ўзи** тасдиқлайди →
`getPendingCodeStatus` кодни auth'сиз қайтаради → `verifyPendingCodeAndRegister`
token беради) — client'дан олиб ташланган, лекин 6 та функция ҳали **жонли**
(CONFIRMED `gcloud describe`: ACTIVE, 2026-10-06). `registerDeviceBinding`
`admin_code` йўли `settings/app.deviceAdminCode` га таянади — prod'да бу майдон
**йўқ** (CONFIRMED), демак ҳозир бу йўл ёпиқ.
Admin web панель (`adminWebSignIn`) — алоҳида: телефон + шахсий PIN, device
binding'га тегмайди.

### 1.10. Янги қурилма тасдиқланганда ЭСКИ қурилма нима бўлади — CONFIRMED

- Эски қурилманинг binding'и `phone: ''` бўлади, alias янгисига ўтади.
- **Эски қурилма чиқиб кетмайди.** Firebase Auth refresh token бекор қилинмайди
  (`revokeRefreshTokens` фақат `account_deletion*`), rules қурилмани
  текширмайди, `AuthRestoreScreen` `currentUser` бор бўлса текширмайди.
  Logout тугмаси ҳам олиб ташланган (хотирада: 2026-10-24).
- Демак **икки (ва ундан кўп) қурилма бир вақтда фаол бўла олади**, лекин бу
  режалаштирилган эмас — ким кирганини кўриш/чиқариш имкони йўқ.
- Эски қурилма сессиясини йўқотса (қайта ўрнатиш, маълумот тозалаш) — қайта
  кириши керак → autoApprove ON: жим қайта кўчади; OFF: яна тасдиқ керак.

### 1.11. WEB (компьютер браузери) хусусан — CONFIRMED + INFERRED

- Web ҳам худди шу onboarding'дан ўтади (alohida web кириш йўқ; admin панел
  `main_admin.dart` алоҳида).
- `main.dart`: `if (kIsWeb) return;` — web'да `NotificationDelivery`, FCM,
  `DeviceTransferInboxService` ишга тушмайди → **web push олмайди ва эски қурилма
  сифатида трансфер тасдиқлай олмайди** (in-app хабарни босиб очса бўлиши мумкин —
  текширилмади, UNKNOWN).
- Web hash барқарор эмас (1.2) → вақт-вақти билан «янги қурилма».

### 1.12. Ҳимоя чоралари (бор / йўқ)

| Чора | Ҳолат |
|---|---|
| Hash формати текшируви (64 hex) | бор |
| `failedAttempts` 5 → 30 дақ блок | бор, лекин autoApprove ON да ишламайди |
| Transfer: кунига 5, TTL 30 дақ, битта pending | бор |
| 24 соат пул ечиш чеклови | фақат peer transfer'дан кейин, 2 та йўлда |
| SMS/OTP | **йўқ** |
| App Check | **йўқ** |
| Сессиялар рўйхати / битта сессияни чиқариш | **йўқ** |
| Эски қурилмага «янги кириш» хабари | **йўқ** (autoApprove/admin йўлларида) |
| Binding ўзгариш тарихи (audit) | **йўқ** (устидан ёзилади) |
| `checkDeviceBinding` IP/рақам бўйича rate limit | **йўқ** |

---

## 2. Эганинг амалий саволлари

### 2.1. Шерик-сотувчи компьютерда кириб, телефонда ҳам қолиши мумкинми?

**Бугун — ҳа (CONFIRMED код + prod sozlama), лекин хавфсизлик тешиги ҳисобига.**

Қадамлар (ҳозир):
1. Компьютерда AVA веб-иловасини очади, тил танлайди.
2. Телефон рақамини (ва исмини) киритади.
3. Server autoApprove туфайли дарҳол киритади — тасдиқ, SMS, телефондан рухсат йўқ.
4. Телефондаги илова ишлашда давом этади (сессия бекор қилинмайди).

Ён таъсирлар (INFERRED):
- `device_aliases` энди браузерга қарайди; телефоннинг binding'и `phone:''`.
  Телефон сессиясини йўқотса — қайта кирганда яна жим кўчади (ва браузер ҳам
  ичкарида қолади).
- Web'да push йўқ — янги буюртма/хабар овози компьютерга келмайди.
- Браузер янгиланса/кэш тозаланса — «янги қурилма» (ҳозир сезилмайди, чунки
  автотасдиқ).

Агар autoApprove **ўчирилса** (тешик ёпилса), бугунги қадамлар:
1. Web'да рақам → «Бу рақам бошқа қурилмага боғлиқ» → «Эски қурилмадан тасдиқлаш».
2. Телефонда хабар → «Тасдиқлаш».
3. Компьютер кирди; **ҳисоб 24 соат пул еча олмайди**; телефон ичкарида қолади,
   лекин энди «боғланган қурилма» — браузер.
4. Телефон қайта кириши керак бўлса — тасдиқни **браузердан** бериш керак, web'да
   inbox хизмати йўқ → ноқулай/тиқилиб қолиши мумкин; браузер янгиланганда яна
   тасдиқ. Яъни бугунги дизайн «битта асосий қурилма»га мўлжалланган, компьютер +
   телефон учун ярамайди.

### 2.2. Хавфлар

1. **Ҳисобни эгаллаш** (autoApprove ON): рақамни билиш кифоя → ҳамён
   (`bonusBalance`), буюртма, дўкон, чат. Эгаси билмайди.
2. Ҳеч ким кирмаган рақамни ҳар ким «эгаллайди» (autoApprove OFF да ҳам) —
   SMS йўқлиги сабабли.
3. Чиқариб бўлмайдиган сессиялар: компьютер ёки йўқолган телефон абадий ичкарида.
4. Audit йўқ: ким, қачон, қайси қурилмадан кирди — тарихда қолмайди.
5. Web hash'нинг FID'сиз ҳолатида тўқнашув.

### 2.3. 0-босқич — тешикни ёпиш (PROPOSED, эганинг қарори керак — §49/§50)

- `deviceBindingAutoApprove` ни OFF қилиш. Trade-off: телефонини алмаштирганлар
  энди эски телефондан тасдиқлайди ёки admin'га мурожаат қилади (admin
  `adminManualApproveDeviceBinding`). Эски телефони йўқларга — admin йўли ёки
  кейинчалик SMS.
- `forceDeviceBindingLink` ҳар чақирувини `device_binding_events` (append-only)
  га ёзиш + эски рақамга «Янги қурилма кирди» хабари.
- `checkDeviceBinding`'га рақам/IP бўйича rate limit; кейинчалик App Check.
- Жонли, лекин ишлатилмаётган `requestPendingCode`/`getPendingCodeStatus`/
  `verifyPendingCodeAndRegister`/`autoApprovePendingCode*` ни ўчириш ёки
  ёпиш (рад жавоби) — алоҳида қарор.
- Узоқ муддат: биринчи боғлаш ва қурилма алмаштиришда SMS OTP (провайдер/нарх —
  UNKNOWN).

QR кириш 0-босқичсиз маъносиз: рақамни билган ҳар ким барибир киради.

---

## 3. Таклиф: «QR орқали кириш» (WhatsApp Web каби) — PROPOSED

### 3.1. Фойдаланувчи учун

**Компьютерда:** сайтни очади → «QR орқали кириш» экрани: катта QR, «Телефонда AVA →
Профиль → Компьютерлар → QR сканерлаш», 2 дақиқалик таймер, муддати ўтса QR ўзи
янгиланади.

**Телефонда:** «Компьютерлар» → «QR сканерлаш» → камера → тасдиқ ойнаси:
«Windows · Chrome · Тошкент (тахминий) · ҳозиргина. Бу СИЗНИНГ компьютерингизми?
Бегона берган QR'ни сканерламанг!» → «Ҳа, кириш» / «Йўқ».

**Компьютер** 1–2 сонияда ичкарига киради. **Телефон ишлашда давом этади.**
«Компьютерлар» рўйхатида ҳар бир сессия: браузер, охирги фаоллик, «Чиқиш»;
пастда «Ҳамма компьютерлардан чиқиш».

### 3.2. Асосий архитектура қарорлари

1. **Web сессия device_bindings'га тегмайди.** Телефон боғланган қурилма бўлиб
   қолади; web fingerprint ишлатилмайди; 24 соат limited қўйилмайди (web
   сессиянинг ўз чекловлари бор, 3.6).
2. **Ҳар бир web сессия — алоҳида Firebase Auth user** (`uid = web_<sid>`),
   `setCustomUserClaims({phone_number: '+998…', ws: '<sid>'})`. Сабаб: Firebase'да
   битта сессияни бекор қилиб бўлмайди — `revokeRefreshTokens(uid)` uid'нинг
   ҳамма сессиясини (телефонни ҳам) чиқаради. Алоҳида uid → «Чиқиш» фақат шу
   компьютерни чиқаради. Rules `phone_number` claim'га таянгани учун эгалик
   сақланади.
   - Хавф: rules'да 19 жойда `request.auth.uid`, functions'да 3 жойда
     `context.auth.uid` бор; client'да `currentUser.uid` ишлатилган жойлар — ҳаммаси
     аудит қилиниши керак (1 кун). (Муқобил: телефон uid'и + developer claim —
     битта сессияни бекор қилиб бўлмайди; кодда «developer claims refresh'да
     йўқолади» деган изоҳ бор, `index.js:732` — ҳақиқатлиги UNKNOWN, эмуляторда
     текшириш керак.)
3. **Икки сир:** QR ичида `nonceId + scanSecret`; компьютер хотирасида (QR'да йўқ)
   `claimSecret`. Телефон `scanSecret` билан тасдиқлайди; token'ни фақат
   `claimSecret` эгаси олади → QR'нинг расмини олган одам token ола олмайди.
4. Token Firestore'га **ҳеч қачон ёзилмайди** — фақат `claimWebLogin` жавобида бир
   марта қайтади.

### 3.3. Коллекциялар ва rules (PROPOSED)

`web_login_nonces/{nonceId}` (nonceId — 128 бит тасодифий):
`scanSecretHash`, `claimSecretHash` (SHA-256), `status`
(`pending → scanned → approved → consumed` | `rejected` | `expired`),
`createdAt`, `expiresAt` (+120 с), `webAnonUid`, `webInfo{browser, os, approxCity}`,
`approvedBy` (рақам), `approverDeviceHash`, `sessionId`.
Rules: `get` — фақат `request.auth.uid == resource.data.webAnonUid` (компьютер
anonymous auth билан listener қилади — polling йўқ; `AnonSessionService` бор);
`list`, write: false. Firestore TTL policy `expiresAt` бўйича.

`web_sessions/{sid}`: `userId` (рақам), `webUid`, `status`
(`active`/`revoked`/`expired`), `createdAt`, `lastSeenAt`, `expiresAt`
(масалан 30 кун, 7 кун фаолсиз → тугайди), `browser`, `os`, `approvedFromDeviceHash`,
`revokedAt`, `revokedBy`, `revokeReason`.
Rules: `read` — `isOwner(resource.data.userId) || isAdmin()`, write: false.

`web_session_events/{autoId}` (append-only, §16): `created/scanned/approved/
rejected/claimed/revoked/expired/denied`, `sid`, `nonceId`, `userId`, `actor`, `at`,
`errorCode`. Rules: read admin, write false.

`settings/app.webQrLogin`: `OFF | INTERNAL | PILOT | PUBLIC` (§42),
`webQrMaxSessions` (масалан 3), `webQrNonceTtlSec` (120), `webSessionMaxDays` (30).

### 3.4. Cloud Functions (europe-west1, `authFunctions` каби) — PROPOSED

| Функция | Ким | Нима қилади |
|---|---|---|
| `createWebLoginNonce` | web, anonymous auth | flag текшируви; rate limit (anon uid/IP: 10 та/10 дақ); nonce + 2 сир; `{nonceId, scanSecret, claimSecret, expiresAtMs}` |
| `previewWebLogin` | телефон (phone token) | `scanSecret` текшириш; `pending→scanned`; браузер/шаҳар/ёшини қайтариш (тасдиқ ойнаси учун) |
| `approveWebLogin` | телефон | transaction: `scanned→approved`; шартлар: phone token (`ws` claim **йўқ** — web web'ни тасдиқлай олмайди), чақирувчи hash = `device_aliases[phone]` (фақат боғланган телефон), блок йўқ, фаол сессиялар < max, nonce муддати ўтмаган; `approve:false` → `rejected` |
| `claimWebLogin` | web | transaction: `approved→consumed` (битта ғолиб, §22); `claimSecret` + `webAnonUid` мос; `createUser(web_<sid>)` + claims + `createCustomToken`; `web_sessions` ёзиш; эски рақамга «Янги компьютер кирди» хабари |
| `revokeWebSession` | эгаси ёки admin | `status:revoked` + `revokeRefreshTokens(webUid)` + `updateUser(disabled)`; admin бўлса `admin_audit` |
| `revokeAllWebSessions` | эгаси/admin | ҳаммасига юқоридагини |
| `touchWebSession` | web | `lastSeenAt` — кўпи билан 15 дақиқада 1 марта (cost §37) |
| `expireWebSessions` | schedule (кунига) | муддати ўтганларни бекор қилиш |

Ҳар бирида structured log: `requestId, action, sid, nonceId, userId, result,
errorCode, duration` (§24); фойдаланувчига 3 тилдаги матн, ички код
(`WEB_QR_EXPIRED`, `WEB_QR_MAX_SESSIONS`, `WEB_QR_NOT_BOUND_DEVICE`…) (§25).

Web томон: `web_sessions/{sid}` га listener → `revoked` бўлса дарҳол `signOut`.
ID token 1 соатда эскиради, refresh бекор қилингани учун энг кўпи 1 соат ичида
барибир чиқади (rules revocation'ни текширмайди — шу сабабли listener ва 3.6 керак).

### 3.5. Client экранлари — PROPOSED

- **Web:** `WebQrLoginScreen` (kIsWeb'да onboarding телефон қадами ўрнига ёки
  ёнида): `qr_flutter` (бор) билан QR, таймер, авто-янгилаш, «QR'ни қандай
  сканерлаш» йўриқномаси; nonce'га listener; `approved` → `claimWebLogin` →
  `signInWithCustomToken`.
- **Телефон:** Профиль → «Компьютерлар» (`WebSessionsScreen`): рўйхат + «Чиқиш» +
  «Ҳаммасидан чиқиш» + «QR сканерлаш»; `WebQrScanScreen` — **янги пакет керак**
  (`mobile_scanner` ёки шунга ўхшаш; ҳозир pubspec'да сканер йўқ — CONFIRMED),
  камера рухсати, фақат ўз схемамиздаги QR'ни қабул қилади; `WebQrConfirmSheet`.
- Муқобил (камерасиз, B вариант): компьютер 8 белгили код кўрсатади, телефонда
  киритилади — backend бир хил. Иккаласини ҳам қилиш мумкин.
- 3 тил (uz_Cyrl, uz_Latn, ru) бирга.

### 3.6. Web сессия чекловлари (PROPOSED — эга танлайди)

- Энг кўпи 3 та фаол web сессия (4-сида «Аввал биттасидан чиқинг»).
- `ws` claim'ли сессия қила олмайди: пул ечиш (`requestPayout`, Telegram ечиш,
  `walletToCash`), ҳамён ўтказмалари, рақам алмаштириш (`changeDevicePhone`),
  қурилма трансферини тасдиқлаш, бошқа web'ни тасдиқлаш. Бунинг учун умумий
  `assertNotWebSession(context)` helper (функциялар бўйича).
- Admin/panel роли бор рақамлар учун QR кириш ёпиқ (улар PIN билан admin панелга
  киради) — чунки `isAdmin()` рақамга қараб ишлайди ва web сессия ҳам admin бўлиб
  қолади.

### 3.7. Хавфлар ва ҳимоя

| Таҳдид | Ҳимоя |
|---|---|
| **QR фишинг** (ёлғон сайт ўз QR'ини «бонус учун сканерланг» деб кўрсатади) | тасдиқ ойнасида катта огоҳлантириш + компьютер браузери/шаҳари/вақти; QR 120 с; телефондан кейин push «Янги компьютер кирди — сиз эмасмисиз? Чиқариш»; web сессия пул еча олмайди; сканер фақат бизнинг схема/домен |
| **Replay** (QR ёки сўровни қайта юбориш) | бир марталик nonce, transaction ҳолат ўтишлари, `consumed` дан кейин рад; `claimSecret` QR'да йўқ |
| **Session theft** (браузердаги token ўғирланиши, XSS) | hosting CSP; сессия 30 кун/7 кун фаолсиз; «Чиқиш» ва «Ҳаммасидан чиқиш»; пул амаллари ёпиқ; admin ҳам бекор қила олади |
| **Brute force / энумерация** | 128 битли ID ва сирлар; anon uid/IP rate limit; хато уринишлар логи |
| **Икки марта босиш / retry** (§21) | ҳамма ўтишлар transaction'да, idempotent; `claimWebLogin` иккинчи чақирувда token бермайди |
| **Телефон ўғирланса** | admin `revokeAllWebSessions` (audit билан); 0-босқичдаги қурилма қоидалари |
| **Cost** (§37) | listener anonymous auth билан (polling эмас), `touch` 15 дақиқада 1, TTL тозалаш |

### 3.8. Тестлар (PROPOSED)

- Rules (эмулятор): `web_login_nonces` — фақат ўз anon uid'и `get`; `list`/write
  рад; `web_sessions` — эгаси/admin ўқийди, бошқа рақам рад, write рад;
  `web_session_events` — фақат admin.
- Functions: nonce rate limit (+/-/чегара); муддати ўтган nonce; нотўғри
  `scanSecret`/`claimSecret`; боғланмаган қурилмадан approve рад; `ws` claim'дан
  approve рад; бир вақтда 2 та claim → битта ғолиб; иккинчи claim token
  бермайди; 3 та сессия → 4-си рад; revoke → `revokeRefreshTokens` чақирилди;
  `ws` сессия `requestPayout` ни чақира олмайди; flag OFF → рад.
- 19 та `request.auth.uid` жойи учун web uid регрессия тестлари.
- Client: widget тестлари (QR экрани таймер/янгилаш, тасдиқ ойнаси, рўйхат) +
  release web build'да кўз билан текшириш + телефонда (adb) охиригача.

### 3.9. Баҳо (PROPOSED)

| Иш | Кун |
|---|---|
| 0-босқич (autoApprove қарори, audit, хабар, rate limit) | 0.5–1 |
| uid аудити (rules 19 жой, functions, client `currentUser.uid`) | 1 |
| Functions + rules + тестлар | 3–4 |
| Web QR экрани | 1–1.5 |
| Телефон: сканер (янги пакет), тасдиқ, «Компьютерлар» | 2 |
| Эмулятор e2e, deploy (rules алоҳида), жонли текшириш | 1–2 |
| **Жами** | **~8–11 иш куни** + APK (эга розилиги билан) |

Web қисми ва server APK'сиз deploy бўлади, лекин сканер ва «Компьютерлар» —
фақат янги APK'да; B вариант (код киритиш) ҳам APK талаб қилади.

---

## 4. Очиқ саволлар (эга учун)

1. `deviceBindingAutoApprove` ни ўчирамизми? Ким ва нима учун ёқган — UNKNOWN
   (`adminSetDeviceBindingAutoApprove` аудит ёзмайди).
2. Жонли, лекин client ишлатмайдиган pending-code функцияларини ёпамизми?
3. SMS OTP провайдери ва нархи — UNKNOWN.
4. Web сессия чекловлари (3.6): max 3? пул амаллари ёпиқми? admin'лар учун ёпиқми?
5. QR (камера) ёки код киритиш (B) ёки иккаласи?
6. Web'да push йўқ — сотувчига буюртма овози компьютерда керакми (алоҳида иш)?
