# Такрорланишлар аудити — 17-банд (ишлатилмайдиган функциялар) — 2026-11-28

> Топшириқ (эга, 2026-11-28): «17-бандни тузат» — ишлатилмайдиган Cloud Functions, такрор тил калитлари,
> эски расм/калитлар. Бу ҳужжат — **сервер қисми** ва эга ишга туширадиган **ўчириш буйруқлари**.
> Deploy қилинмади, production'да ҳеч нарса ўчирилмади ва ёзилмади.

## 1. Текширув усули

- Манба: `origin/feat/ev-trip-planner` d6ac6e18 (`functions/` 564 + `functions_demand/` 77 экспорт; `index.js` юклаб,
  ҳар бирининг тури — callable / http / trigger / schedule).
- Жонли рўйхат: 626 функция (2026-11-28 01:31Z deploy'дан кейин).
- Клиент: `origin/feat/factories-jobs` a9527153 (`lib/`, `web/`) — номи `'…'`/`"…"` ичида учрамаган callable/http — 50 та номзод.
- Ҳар номзод учун: 92 та клиент линияси (`deploy/apk-117…126`, `deploy/apk-*`, `release/play-1.0.36/1.0.37/127/128`,
  `deploy/hosting-*`) да `git grep`; бутун тарихда `git log --all -G` (`lib/`); сервер/тоол/rules/бот ҳаволалари;
  Cloud Logging — охирги 30 кунда «Function execution started» сони (фақат сон, маълумот чиқарилмади).

## 2. Натижа — 50 номзод

| Синф | Сон | Функциялар |
|---|---|---|
| **SAFE_TO_DELETE** (манбадан олиб ташланди) | 12 | debitForOrder, requestPayout, checkWithdrawalLimit, placeOrderWithWallet, floatTopUp, floatReturn, driverFloatStatus, adminWebSignInWithCode, promoteToAdminWithPin, appendAdminSystemChat, migrateCheapProductTitleLower, migratePhoneFormats |
| KEEP — эски APK/веб чақирган | 5 | linkRealtyVideo, unlinkRealtyVideo (APK 10-18…10-20 линиялари), leaveDriverRole (≤10-17), autoApproveDriverApplication (≤10-06), verifyPendingCodeAndRegister (≤08-07; хавфсизлик учун ENDPOINT_RETIRED гуруҳи) |
| KEEP — ташқи кириш | 3 | clipPage (`/clip/**` hosting rewrite), shopPage (`/s/<id>` ҳаволалар), telegramWalletBotWebhook (Telegram) |
| KEEP — эга қарори | 1 | creditSupplier (W-2: courier_payout қўлда тўлов йўли) |
| KEEP — ҳали deploy қилинмаган (жонли эмас) | 11 | account deletion 10 та, adminSetRealtyCounts |
| UNKNOWN — эга қарори керак | 18 | қуйида |

UNKNOWN (ўчирилмади): adminSetRestaurantCuisineHidden, adminSetRestaurantSections, adminSetRestaurantSeasons,
adminSetRestaurantRamadan, adminRefundBookingFee, adminRestoreRestaurantBookings, adminSetRestaurantBookings,
adminSetMarketTaxonomy (админ UI йўқ, rules/тоол «ягона ёзиш йўли» дейди), adminUpsertRelativesBonusProgram
(админ экрани «ягона ёзиш йўли» дейди, лекин чақирув 11-27 да олиб ташланган — текшириш керак),
mergeAnonymousSession, backfillEngagementIndex (anon-session 1-босқич, клиент уланиши кейин),
migrateOldBindings (админ экрани «керак» деб ёзади), adminSeedSearchIndex (тоол нусхаси эскирган бўлиши мумкин),
resetSoldStockNow (тиклаш воситаси), bootstrapAdminUser (секрет билан авария кириши), adminMigrateTaxiDrivers,
runDemandAnalytics, demandCoreStatus (demand диагностика).

SAFE мезони: ҳозирги клиентда йўқ; 92 клиент линиясининг бирортасида йўқ; охирги клиент чақируви ≤ 2026-06-14
ёки ҳеч қачон; 30 кунда 0 чақирув; trigger/schedule эмас; бот/тоол/админ веб чақирмайди; ўрнини бошқа жонли
йўл босади (placeOrderPostPaid, requestWalletWithdraw/walletToCash/cashExchange, confirmPayout/rejectPayout,
sendSupportChatReply, adminWebSignIn). 8 таси аллақачон фақат хато қайтарадиган стуб эди; 2 таси бир марталик
migration; driverFloatStatus — клиент ҳеч қачон чақирмаган; appendAdminSystemChat — sendSupportChatReply нусхаси.

Эслатма: эски APK стубни чақирса аввал «эскирган, иловани янгиланг» хатосини оларди, ўчирилгач `NOT_FOUND`
олади — натижа бир хил (амал бажарилмайди). 2026-06-14 дан кейинги ҳеч бир клиент уларни чақирмайди.

## 3. Ўчириш буйруғи (эга ишга туширади — Claude ИШГА ТУШИРМАДИ)

Тартиб: аввал шу бранч mainline'га мерж (ёки мерждан кейин) — акс ҳолда кейинги тўлиқ `--only functions`
deploy «манбада йўқ функцияларни ўчирайми?» деб сўрайди. Ном бўйича deploy'ларга таъсир йўқ.

```powershell
firebase functions:delete debitForOrder requestPayout checkWithdrawalLimit placeOrderWithWallet floatTopUp floatReturn driverFloatStatus adminWebSignInWithCode promoteToAdminWithPin appendAdminSystemChat migrateCheapProductTitleLower migratePhoneFormats --region us-central1 --project master-taxi-gurlan --config D:\projects\ava_gurlan\firebase.json
```

(12 тасининг ҳаммаси `us-central1`, 1-авлод — `gcloud functions list` билан текширилди.)

Текшириш: `gcloud functions list --project master-taxi-gurlan --format="value(name)"` — 626 → 614.

Rollback: ҳар бир функциянинг коди git тарихида (d6ac6e18). Қайтариш — шу коммитдан ном бўйича
`firebase deploy --only functions:<name> --config <abs>\firebase.json`.

## 4. Тестлар

`functions/test/legacy_money_retired_cf.test.js` — 12 та ном export қилинмаслиги, ўрнини босувчи 9 йўл борлиги,
creditSupplier қолгани; `payout_controls_cf.test.js` — олиб ташланди (фақат ўчирилган 2 стубни текширарди);
`device_security_cf` K13 ва `admin_panel_audit_cf` W1 — «export йўқ» текширувига ўтказилди.
