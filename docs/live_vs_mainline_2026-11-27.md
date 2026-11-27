# Jonli Cloud Functions ↔ server mainline (`feat/ev-trip-planner`) — 2026-11-27

**Vazifa (ega, 2026-11-27):** server mainline `feat/ev-trip-planner` (boshlang'ich tip `863efa03`) jonli
production'dagi BARCHA Cloud Functions kodini o'z ichiga olsin — kelajakda mainline'dan nom bo'yicha deploy
jonli xulqni regress qilmasin. Deploy QILINMADI, prod'ga yozilmadi (faqat o'qish: Cloud Functions API, GCS
manba arxivlari, Rules API).

## Natija (qisqa)

| | 863efa03 (oldin) | reconcile tip (keyin) |
|---|---:|---:|
| Jonli funksiyalar jami | 575 | 575 |
| SAME (effektiv kod bir xil) | 250 | **355** |
| MAINLINE_NEWER (mainline'da jonlidan keyingi o'zgarish) | 99 | **194** |
| MAINLINE_NEWER* (qo'lda tasdiqlangan, pastda izoh) | — | **26** |
| LIVE_NEWER (mainline regress qilardi) | 38 | **0** |
| LIVE_ONLY (mainline'da funksiya yo'q edi) | 120 | **0** |
| DIVERGED (ikki tomonlama) | 66 | **0** |
| aniqlanmagan (indeksator) | 2 | 0 (qo'lda) |

- Jonli: **556 gen1** (us-central1 469 default, europe-west1 10 default + 77 `demand`) + **19 gen2** = 575.
  `y` codebase'da jonli funksiya yo'q.
- Manba arxivlari: **113 noyob arxiv** (md5), **106 xil git commit** (2026-10-06 … 2026-11-26).
  112 tasi commit bilan 0 farqda; 9 tasi «iflos» deploy (commitdan 1–3 fayl farq — jadvalda `±N`).
- `firestore.rules` o'zgarmadi: blob `f4cbda1b` = 863efa03 = jonli ruleset `37146b29`
  (`build:rules` chiqishi jonli ruleset bilan bayt-bir xil — `// built from … sha256:4dc7f65f…`).

## Usul

1. `cloudfunctions v1/v2` API → har funksiya: codebase (label), runtime, versionId, updateTime (env chiqarilmadi).
2. gen1 manbasi: `gs://gcf-sources-67136747215-<region>/<fn>-<uuid>/version-<versionId>/function-source.zip`;
   gen2: `buildConfig.source.storageSource` (generation). md5 bo'yicha guruhlanib, har arxiv bir marta yuklandi.
3. Har fayl CRLF→LF, `git hash-object` → `git log --all --raw` bilan eng yaqin commit (blob mos).
4. **Funksiya darajasida** taqqoslash (acorn AST): `exports.<fn>` (yoki `attachX(exportsObj)` ichidagi) ta'rifi +
   u ishlatgan top-level yordamchilar + `require` qilingan modullarning faqat ishlatilgan a'zolari (tranzitiv),
   izoh/bo'shliqsiz. Uch tomonlama: jonli arxiv vs nomzod vs merge-base(jonli commit, nomzod).
5. `MAINLINE_NEWER` = jonli commit nomzod tarixida va undan keyin shu funksiya kodiga mainline'da o'zgarish
   kiritilgan (deploy qilinmagan, lekin niyat qilingan). Bunday funksiyani mainline'dan deploy qilish — yangi
   xulqni chiqarish, regress emas.

## Nima qilindi (reconcile, toza worktree, push ff)

Asosiy jonli server liniyasi «P» (deploy-biz-fns pin → bozor/biz-order/ava-ai/avagram-news) mainline'dan
2026-10-23 (`f2a77d32`) da ajralgan edi — 110+ commit, 120 ta funksiya mainline'da umuman yo'q edi
(biznes buyurtmalar, customer_confirm, delivery_failed, deal chat, shop link, seller TG, courier payout,
yuk_local, relay naqd/yo'qotish, assistantPriceSearch …). Butun liniyalar merge qilindi:

| Commit | Nima |
|---|---|
| a65fd102 | merge `feat/avagram-news-srv` 9771c4e6 (P: ava-ai, bozor-orders, biz-order, courier, incentives 1–2, deal-chat, shop link, yuk_local, relay payout). Konfliktlar: rules=mainline, incentives.js=mainline (e0985429 muhr + holiday), business_directory.js=P, index.js/notif_i18n/package.json/tv_social_publish = ikkalasi, market_search_tokens=mainline (yangi alifbo), rules testlari=mainline |
| b5ff20db | merge `fix/ulg-requote-1b37de53` ed6c6dab (ulg-s57-srv, relay-cash-loss-srv, ulg-debt-pay-srv, placeWholesaleOrder requote) — konfliktsiz |
| 5746dc68, 4a82183b, bd6df4d0 | merge `fix/sm-label-orders-7418a7a8`, `fix/sm-customer-cancel-b9cfffcc`, `fix/platform-sm-guard-496e080e` — daraxt o'zgarmadi (qo'lda portlar allaqachon bor edi), tarix bog'landi |
| c1d8367e | merge `fix/pickup-cleanup-3feb9d6e` 8d393e86 (deleteMyMainShop) |
| 61277158 | merge `fix/realty-fields-live-c8c5b324` 97c81499 — realty.js = mainline (pastda «Xavflar») |
| 7868986d | merge `fix/restaurant-preorder-dish-ce23f0ed` 73178957 — daraxt o'zgarmadi |
| ee30742d | merge `feat/incentives-srv` e0985429 |
| f6907506 | fix: `isBusinessOrder` ikki marta e'lon (merge natijasi) — jonli shakl qoldi |
| 25f8177d | **demand:** functions_demand = mainline + `feat/relay-cash-loss-demand` 42fc64d7 (ulg-s57 5001f513, ulg-s46 8794aa08, relay zanjiri 69bf7609, adminMarkShipmentLost naqd) + `feat/ulg-admin-srv` 4f7153a0 — FAQAT `functions_demand/` yo'li 3 tomonlama (bu branchlar hosting liniyasida, lib/ olinmadi). P'ning eski functions_demand nusxasi tashlandi (u adminGetCoreOverview/adminSetCoreConfig ni o'chirgan edi). `analytics/access.js`: assertCoreConfigAdmin + assertStrictAdmin birga |
| 8dc18abe, 6e7c5677 | testlar jonli kodga moslandi (wholesale_orders_admin, seller_tg_channel_rules) |

**Mainline'dagi faqat-mainline funksiyalar:** default 15 + demand 7 (jonli emas) — hech biri yo'qolmadi va
merge ularni o'zgartirmadi (fingerprint bir xil). index.js eksportlari: default 513, demand 77 (= jonli 77).

## MAINLINE_NEWER* (qo'lda tasdiqlangan 26 ta)

- **demand 22 ta** (acceptLeg, scanHandover, createLogisticsOrder, legChainSweeper, startWholesaleSelfDelivery …):
  jonli arxivlar bir liniyaning turli nuqtalaridan (5001f513, 8794aa08, 69bf7609) — nomzod = shu liniyaning
  keyingi jonli nuqtasi 42fc64d7 + mainline `core/config.js` (ALL_REGION, enableMinProviders — jonli createDemand'da
  allaqachon ishlaydi), `core/ids.js`, `notify/policy.js`. Production'da demand funksiyalari bir vaqtda 5+ xil
  config.js bilan ishlayapti — mainline ularni bittaga keltiradi.
- **cancelDemand, acceptOffer** (jonli 205c1b1c iflos deploy): repoda yo'q bo'lgan jonli wholesale-LEG himoyasi
  aynan ko'chirilgan (42fc64d7 liniyasida) + muddat o'tgan talabni qabul qilmaslik (yangi).
- **onTripUpdate** (8bee7cdd iflos): appendSystemSupportChatMessage'ga opsiya qo'shilgan. **sellerPlaceSale** (580f9523):
  food kodi olib tashlangan, FOOD_MODULE_REMOVED rad etish saqlangan.
- **adminGetCustomerConfirmation** = SAME (customer_confirm.js bayt-bir xil), **onSearchIndexYukListingWrite** — faqat runExpiry matni.

## Testlar (reconcile tip 6e7c5677, emulator port 18471)

- `functions_demand`: `node test/run_all.js` — **1164 test, 0 xato to'plam**.
- `functions`: package.json'dagi 120 to'plam bitta emulatorda ketma-ket: 108 OK, 12 FAIL. Baseline 863efa03 (97 to'plam)
  ham xuddi shu 8 tasida FAIL — umumiy emulator izolyatsiyasi. Har biri o'z emulatorida alohida:
  courier_orders 33/33, collection_pricing 10/10, market_moderation_cf 31/31, market_search_tokens_cf 12/12,
  carpet_agro_courier_tasks 24/24, account_deletion_admin 14/14, seller_tg_channel_cf 30/30,
  seller_tg_channel_rules 11/11 (fixture tuzatildi), admin_stale_tasks 12/12, intercity_audit 31/31, realty_expiry o'tdi.
  Qolgan yagona: `capabilities_model_parity` — baseline'da ham FAIL (worktree CRLF nusxa, mavjud muammo).

## Xavflar / ochiq masalalar

1. **MAINLINE_NEWER 194+26 = 220 funksiya** — mainline'dan deploy qilinsa jonlida hali yo'q kod chiqadi. Muhimlari:
   - `submitRealtyListing`/`updateRealtyListing` + realty 14 ta: jonli = eski c8c5b324 liniyasi (manzil ixtiyoriy,
     rasm egaligi tekshirilmaydi); mainline = 5465ac6c + 37dd14d9 (manzil MAJBURIY `address_required`,
     rasm faqat o'z Storage'idan `image_invalid`). Deploy = xulq o'zgarishi (eski APK manzilsiz yubora olmaydi).
   - P liniyasi jonli deploylardan keyingi commitlari (masalan upsertSearchIndexEntry, order_index, notif_i18n,
     tv_social_publish) endi mainline'da — ular boshqa jonli funksiyalarda allaqachon ishlaydi.
   - demand: barcha logistics/wholesale funksiyalari bitta (eng yangi) config.js/logistics.js ga o'tadi.
2. Ulgurji/relay demand branchlari hosting liniyasida — ularning `lib/`/`functions/` qismi olinmadi (default
   codebase'ning jonli manbasi ulg-requote liniyasi edi va u merge qilingan).
3. Root'ga P'dan `biz_order_indexes.json`, `biz_order_rules.patch`, `.claude/deploy-kit-courier-audit/`, 3 ta docs fayl keldi
   (liniya bilan birga; zararsiz).
4. Bu inventar 2026-11-27 holati; har yangi deploy'dan keyin jadval eskiradi. Qayta tekshirish skriptlari shu
   sessiya scratchpad'ida edi (repo'ga qo'shilmadi).

## Funksiyalar jadvali

`archive` = manba zip md5 boshi; `commit±N` = eng yaqin commit (N — farq qiluvchi fayllar); `oldin` = 863efa03 ga nisbatan.

| funksiya | codebase | region | gen | runtime | ver | updateTime (UTC) | archive | commit | branch | oldin | holat | izoh |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| acceptDeliveryQuote | default | us-c1 | 1 | nodejs22 | v2 | 2026-11-16 17:23 | N5ESIkER | 03d85441 | feat/bozor-orders-srv | LIVE_ONLY | **MAINLINE_NEWER** |  |
| addRealtyTeamMember | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-06 06:39 | mqmy34rY | d2d45a96 | fix/bozor-live-port-d2d45a96 | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| addRelativePerson | default | us-c1 | 1 | nodejs20 | v16 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| adminAddChinaQuote | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-20 17:30 | OJiiM3GR | f1ff9ca4 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminArchiveSupportChat | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-19 20:14 | IEXEFQtS | f1c45289 |  | SAME | **SAME** |  |
| adminAutoApproveDeviceBinding | default | us-c1 | 1 | nodejs20 | v30 | 2026-10-08 10:16 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminCancelRestaurantOrder | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-09 01:24 | QmQAQ/Ce | dae5406e |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminChangeOwnPin | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-08 11:03 | J0AT+iaf | ed0241af |  | SAME | **SAME** |  |
| adminCloseChinaInquiry | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-20 17:30 | OJiiM3GR | f1ff9ca4 |  | SAME | **SAME** |  |
| adminCreateBusiness | default | us-c1 | 1 | nodejs22 | v4 | 2026-11-01 00:34 | Lag2kwZz | 9f4b7594 | feat/biz-cat30-srv | LIVE_NEWER | **SAME** |  |
| adminCreateCollectionTask | default | us-c1 | 1 | nodejs22 | v24 | 2026-10-31 19:08 | YX0wh3qj | f00a6bbe | feat/courier-failed-other-srv | DIVERGED | **SAME** |  |
| adminDecideCourierScope | default | us-c1 | 1 | nodejs22 | v1 | 2026-10-31 12:24 | Kel/Zoyq | 420ed0b2 | pin/courier-scopes | DIVERGED | **SAME** |  |
| adminDeleteBusiness | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-23 04:30 | /tnUK6zo | eb79f9cd |  | SAME | **SAME** |  |
| adminDeleteBusinessProduct | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-25 07:34 | kqjEOTT2 | a07abc0f |  | DIVERGED | **SAME** |  |
| adminDeleteJobAd | default | us-c1 | 1 | nodejs20 | v18 | 2026-10-08 10:16 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminDeleteMarketAd | default | us-c1 | 1 | nodejs20 | v17 | 2026-10-08 10:16 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminDeleteOilCatalogItem | default | us-c1 | 1 | nodejs20 | v14 | 2026-10-08 10:16 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminDeleteRealtyListing | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-06 06:39 | mqmy34rY | d2d45a96 | fix/bozor-live-port-d2d45a96 | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminDeleteRecord | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-19 20:14 | IEXEFQtS | f1c45289 |  | SAME | **SAME** |  |
| adminGetBusinessOrdersConfig | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-16 17:23 | N5ESIkER | 03d85441 | feat/bozor-orders-srv | LIVE_ONLY | **SAME** |  |
| adminGetCourierServiceFee | default | us-c1 | 1 | nodejs22 | v1 | 2026-10-31 05:07 | n/SPTx8c | 7de7a7e1 |  | LIVE_ONLY | **SAME** |  |
| adminGetCourierTaskPayoutSettings | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-16 08:37 | 0UNP8F7o | 77bfbe13 |  | LIVE_ONLY | **SAME** |  |
| adminGetCustomerConfirmation | default | us-c1 | 1 | nodejs22 | v3 | 2026-11-03 04:44 | jDSk+nf7 | a55d78b3 |  | LIVE_ABSENT_IN_ARCHIVE? | **SAME** | customer_confirm.js jonli arxiv bilan bayt-bir xil (indeksator ichki fabrikani ko'rmaydi - qo'lda tekshirildi) |
| adminGetFamilyBonusPrograms | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| adminGetTvSocialSettings | default | us-c1 | 1 | nodejs20 | v8 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **MAINLINE_NEWER** |  |
| adminGetWalletBotSettings | default | us-c1 | 1 | nodejs20 | v15 | 2026-10-08 16:17 | LkaWH9lb | e7a40724 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminGetWarehouseStock | default | us-c1 | 1 | nodejs20 | v20 | 2026-10-08 10:16 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminListCourierScopeRequests | default | us-c1 | 1 | nodejs22 | v1 | 2026-10-31 12:24 | Kel/Zoyq | 420ed0b2 | pin/courier-scopes | DIVERGED | **SAME** |  |
| adminListLossIncidents | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-16 08:36 | 0UNP8F7o | 77bfbe13 |  | LIVE_ONLY | **SAME** |  |
| adminListMarketAds | default | us-c1 | 1 | nodejs20 | v19 | 2026-10-09 00:56 | qFXQZugK | 2d1d19b4В±1 |  | SAME | **SAME** |  |
| adminListModuleConfigAudit | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-08 16:20 | LkaWH9lb | e7a40724 |  | SAME | **SAME** |  |
| adminListStaleTasks | default | us-c1 | 1 | nodejs22 | v2 | 2026-11-03 04:44 | jDSk+nf7 | a55d78b3 |  | LIVE_ONLY | **SAME** |  |
| adminManualApproveDeviceBinding | default | us-c1 | 1 | nodejs20 | v30 | 2026-10-08 10:16 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminMarkChinaInquirySent | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-20 17:30 | OJiiM3GR | f1ff9ca4 |  | SAME | **SAME** |  |
| adminMarkSupermarketCourierPaid | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| adminModerateDatingProfile | default | us-c1 | 1 | nodejs20 | v17 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| adminModerateListing | default | us-c1 | 1 | nodejs22 | v2 | 2026-11-15 13:33 | ZIsIwEDA | 57f0ceefВ±1 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminModeratePromo | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-19 20:44 | IBhLycaP | fd5db610 | deploy/rel-1120-srv | SAME | **SAME** |  |
| adminPublishTvClipSocial | default | us-c1 | 1 | nodejs20 | v10 | 2026-10-25 19:46 | SGinORMQ | 811a7c28 |  | LIVE_NEWER | **SAME** |  |
| adminRecordLostParcelPayment | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-16 06:07 | a6lIxN2y | 76a9ec3d |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| adminRecordWholesaleLostFeePayment | default | us-c1 | 1 | nodejs22 | v3 | 2026-11-14 16:37 | hXXYEK1Q | badd3ff0 | feat/ulg-s57-srv | LIVE_ONLY | **MAINLINE_NEWER** |  |
| adminRefundBookingFee | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-19 12:01 | IwjU2UoG | 11ab5913В±1 |  | SAME | **SAME** |  |
| adminRejectDeviceBinding | default | us-c1 | 1 | nodejs20 | v30 | 2026-10-08 10:16 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminRemoveSupermarketLine | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| adminReportSupermarketShortage | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| adminResetItemSoldToday | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-08 10:16 | 5QRrk06u | ed0241af |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminResetTaxiDriversRegistry | default | us-c1 | 1 | nodejs20 | v35 | 2026-10-08 10:14 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminResolveDatingReport | default | us-c1 | 1 | nodejs20 | v15 | 2026-10-08 10:16 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminResolveEvReport | default | us-c1 | 1 | nodejs20 | v4 | 2026-10-08 10:18 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminResolveJobComplaint | default | us-c1 | 1 | nodejs20 | v17 | 2026-10-08 10:16 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminRestoreRestaurantBookings | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-19 12:01 | IwjU2UoG | 11ab5913В±1 |  | SAME | **SAME** |  |
| adminResyncIncentiveProfile | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-02 20:45 | jWD2Iilm | e0985429 | feat/incentives-srv | DIVERGED | **MAINLINE_NEWER** |  |
| adminRetractNews | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-19 20:14 | IEXEFQtS | f1c45289 |  | SAME | **SAME** |  |
| adminReviewWalletTopUp | default | us-c1 | 1 | nodejs20 | v14 | 2026-10-08 16:17 | LkaWH9lb | e7a40724 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminReviewWalletWithdraw | default | us-c1 | 1 | nodejs20 | v13 | 2026-10-08 16:17 | LkaWH9lb | e7a40724 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminRevokeIncentiveGrant | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-02 18:43 | RYERmEvb | 41948286 |  | DIVERGED | **MAINLINE_NEWER** |  |
| adminSaveModuleConfig | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-08 11:42 | ng4cmgdA | 1baa3e9fВ±4 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminSeedOilCatalog | default | us-c1 | 1 | nodejs20 | v14 | 2026-10-08 10:16 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminSeedSearchIndex | default | us-c1 | 1 | nodejs20 | v9 | 2026-10-08 10:16 | 5QRrk06u | ed0241af |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminSetAdminPin | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-08 11:02 | J0AT+iaf | ed0241af |  | SAME | **SAME** |  |
| adminSetAgroPickupStatus | default | us-c1 | 1 | nodejs20 | v19 | 2026-10-16 08:37 | 0UNP8F7o | 77bfbe13 |  | LIVE_NEWER | **MAINLINE_NEWER** |  |
| adminSetBusinessOrdersConfig | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-03 04:47 | jDSk+nf7 | a55d78b3 |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| adminSetBusinessStatus | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-25 10:10 | 6IJqILiA | 2cc56591 |  | LIVE_ONLY | **SAME** |  |
| adminSetCarpetWashStatus | default | us-c1 | 1 | nodejs20 | v20 | 2026-10-16 08:37 | 0UNP8F7o | 77bfbe13 |  | LIVE_NEWER | **MAINLINE_NEWER** |  |
| adminSetChinaInquiryConfig | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-20 17:30 | OJiiM3GR | f1ff9ca4 |  | SAME | **SAME** |  |
| adminSetChinaInquiryTextZh | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-20 17:30 | OJiiM3GR | f1ff9ca4 |  | SAME | **SAME** |  |
| adminSetCourierScopeApprovalMode | default | us-c1 | 1 | nodejs22 | v1 | 2026-10-31 12:24 | Kel/Zoyq | 420ed0b2 | pin/courier-scopes | DIVERGED | **SAME** |  |
| adminSetCourierServiceFee | default | us-c1 | 1 | nodejs22 | v1 | 2026-10-31 05:07 | n/SPTx8c | 7de7a7e1 |  | LIVE_ONLY | **SAME** |  |
| adminSetCourierTaskPayoutPct | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-16 08:37 | 0UNP8F7o | 77bfbe13 |  | LIVE_ONLY | **SAME** |  |
| adminSetCustomerConfirmation | default | us-c1 | 1 | nodejs22 | v3 | 2026-11-03 04:44 | jDSk+nf7 | a55d78b3 |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| adminSetDatingAutoApprove | default | us-c1 | 1 | nodejs20 | v18 | 2026-10-08 10:16 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminSetDeviceBindingAutoApprove | default | us-c1 | 1 | nodejs20 | v29 | 2026-10-08 10:16 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminSetEvStationActive | default | us-c1 | 1 | nodejs20 | v4 | 2026-10-08 10:18 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminSetIncentiveStage | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-02 18:43 | RYERmEvb | 41948286 |  | DIVERGED | **MAINLINE_NEWER** |  |
| adminSetJobsAutoApprove | default | us-c1 | 1 | nodejs20 | v7 | 2026-10-08 10:16 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminSetLocalTaxiPrices | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-07 22:40 | YhZD2sCQ | df062163В±3 |  | SAME | **SAME** |  |
| adminSetMarketAutoApprove | default | us-c1 | 1 | nodejs20 | v9 | 2026-10-08 10:16 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminSetMarketTaxonomy | default | us-c1 | 1 | nodejs22 | v3 | 2026-11-16 19:17 | 0QSBrraw | caddd168В±1 |  | SAME | **SAME** |  |
| adminSetMarshrutRoutePrice | default | us-c1 | 1 | nodejs20 | v17 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| adminSetOrderStatus | default | us-c1 | 1 | nodejs22 | v25 | 2026-11-03 04:44 | jDSk+nf7 | a55d78b3 |  | LIVE_NEWER | **SAME** |  |
| adminSetOrderStatusBatch | default | us-c1 | 1 | nodejs22 | v25 | 2026-11-03 04:44 | jDSk+nf7 | a55d78b3 |  | LIVE_NEWER | **SAME** |  |
| adminSetPlatformDeliveryFeePercent | default | us-c1 | 1 | nodejs22 | v9 | 2026-11-02 22:00 | Q+2FYYD4 | 496e080e | fix/courier-3bugs-srv | LIVE_NEWER | **SAME** |  |
| adminSetPlatformFeaturedAuto | default | us-c1 | 1 | nodejs20 | v8 | 2026-10-08 10:18 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminSetProductDiscount | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-19 20:44 | IBhLycaP | fd5db610 | deploy/rel-1120-srv | SAME | **SAME** |  |
| adminSetRealtyStatus | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-06 06:39 | mqmy34rY | d2d45a96 | fix/bozor-live-port-d2d45a96 | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminSetRestaurantAutoApprove | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-09 01:24 | QmQAQ/Ce | dae5406e |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminSetRestaurantBookings | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-19 12:01 | IwjU2UoG | 11ab5913В±1 |  | SAME | **SAME** |  |
| adminSetRestaurantCuisineHidden | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-19 08:39 | rVPLRpc/ | 30af7f73В±1 |  | SAME | **SAME** |  |
| adminSetRestaurantDeliveryPrices | default | us-c1 | 1 | nodejs20 | v3 | 2026-10-16 08:37 | 0UNP8F7o | 77bfbe13 |  | DIVERGED | **MAINLINE_NEWER** |  |
| adminSetRestaurantFeeSettings | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-16 08:37 | 0UNP8F7o | 77bfbe13 |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| adminSetRestaurantRamadan | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-19 12:01 | IwjU2UoG | 11ab5913В±1 |  | SAME | **SAME** |  |
| adminSetRestaurantSeasons | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-19 12:01 | IwjU2UoG | 11ab5913В±1 |  | SAME | **SAME** |  |
| adminSetRestaurantSections | default | us-c1 | 1 | nodejs20 | v3 | 2026-10-19 15:04 | aJNHVipB | 7e370c8bВ±1 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminSetRestaurantsStage | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-09 01:24 | QmQAQ/Ce | dae5406e |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminSetRestaurantStatus | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-09 01:24 | QmQAQ/Ce | dae5406e |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminSetSectionGrant | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-15 04:04 | srfp4s4Y | 0add857eВ±1 |  | SAME | **SAME** |  |
| adminSetShopStatus | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-25 10:10 | 6IJqILiA | 2cc56591 |  | LIVE_ONLY | **SAME** |  |
| adminSetSupermarketSettings | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| adminSetSupermarketTaxonomy | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| adminSettleSupermarketWeights | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| adminSetTvSocialSettings | default | us-c1 | 1 | nodejs20 | v8 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **MAINLINE_NEWER** |  |
| adminSetWalletBotSettings | default | us-c1 | 1 | nodejs20 | v16 | 2026-10-18 07:19 | pbkTiiWk | fd151de0 |  | SAME | **SAME** |  |
| adminSupermarketCourierPayouts | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| adminSupermarketImportConfirm | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminSupermarketImportPreview | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminSupermarketImportTemplate | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminSupermarketProcurementReport | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| adminSupermarketStats | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| adminUnblockDeviceBinding | default | us-c1 | 1 | nodejs20 | v30 | 2026-10-08 10:18 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminUnmarkSupermarketCourierPaid | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| adminUpdateBusiness | default | us-c1 | 1 | nodejs22 | v5 | 2026-11-01 00:34 | Lag2kwZz | 9f4b7594 | feat/biz-cat30-srv | LIVE_NEWER | **SAME** |  |
| adminUpdateBusinessProduct | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-25 07:34 | kqjEOTT2 | a07abc0f |  | DIVERGED | **SAME** |  |
| adminUpdateEvStationStatus | default | us-c1 | 1 | nodejs20 | v4 | 2026-10-08 10:18 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminUpdateJobAd | default | us-c1 | 1 | nodejs20 | v18 | 2026-10-08 10:18 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminUpdateJobAdStatus | default | us-c1 | 1 | nodejs20 | v18 | 2026-10-08 10:18 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminUpdateMarketAd | default | us-c1 | 1 | nodejs22 | v20 | 2026-11-15 11:41 | Yk366IL9 | 35b8dfd1В±1 |  | SAME | **MAINLINE_NEWER** |  |
| adminUpdateMarketAdStatus | default | us-c1 | 1 | nodejs22 | v19 | 2026-11-15 11:41 | Yk366IL9 | 35b8dfd1В±1 |  | SAME | **SAME** |  |
| adminUpdateSellSubmission | default | us-c1 | 1 | nodejs20 | v16 | 2026-10-08 10:18 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminUpsertChinaSupplier | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-20 17:30 | OJiiM3GR | f1ff9ca4 |  | SAME | **SAME** |  |
| adminUpsertFamilyBonusProgram | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| adminUpsertHolidayBasket | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| adminUpsertHolidayOccasion | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| adminUpsertIncentiveProgram | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-02 18:43 | RYERmEvb | 41948286 |  | DIVERGED | **MAINLINE_NEWER** |  |
| adminUpsertOilCatalogItem | default | us-c1 | 1 | nodejs20 | v14 | 2026-10-08 10:18 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| adminUpsertRelativesBonusProgram | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| adminUpsertSupermarketOffer | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| adminWebSignIn | default | us-c1 | 1 | nodejs20 | v30 | 2026-10-08 11:03 | J0AT+iaf | ed0241af |  | SAME | **SAME** |  |
| adminWebSignInWithCode | default | us-c1 | 1 | nodejs20 | v22 | 2026-10-08 11:11 | YONyL/wv | 1631f85e |  | SAME | **SAME** |  |
| adminWithdrawChinaQuote | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-20 17:30 | OJiiM3GR | f1ff9ca4 |  | SAME | **SAME** |  |
| analyticsDailyRollup | default | us-c1 | 1 | nodejs20 | v6 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| analyticsHistoricalBackfill | default | us-c1 | 1 | nodejs20 | v6 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| appendAdminSystemChat | default | us-c1 | 1 | nodejs20 | v45 | 2026-10-08 10:18 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| approveDriverRequest | default | us-c1 | 1 | nodejs20 | v40 | 2026-10-16 19:39 | vqxRt5A9 | 6a124f51 |  | SAME | **SAME** |  |
| assistantBuyPackage | default | us-c1 | 1 | nodejs22 | v7 | 2026-11-17 03:26 | vaeU6qJ8 | 1ea5225f | feat/ava-ai-price-srv | LIVE_NEWER | **SAME** |  |
| assistantChat | default | us-c1 | 1 | nodejs22 | v15 | 2026-11-17 03:25 | vaeU6qJ8 | 1ea5225f | feat/ava-ai-price-srv | LIVE_NEWER | **SAME** |  |
| assistantDeleteConversation | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| assistantDeleteMemory | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| assistantGetStatus | default | us-c1 | 1 | nodejs22 | v8 | 2026-11-17 03:25 | vaeU6qJ8 | 1ea5225f | feat/ava-ai-price-srv | LIVE_NEWER | **SAME** |  |
| assistantPriceSearch | default | us-c1 | 1 | nodejs22 | v2 | 2026-11-17 03:26 | vaeU6qJ8 | 1ea5225f | feat/ava-ai-price-srv | LIVE_ONLY | **MAINLINE_NEWER** |  |
| assistantRenameConversation | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| autoApproveDriverApplication | default | us-c1 | 1 | nodejs20 | v34 | 2026-10-16 19:39 | vqxRt5A9 | 6a124f51 |  | SAME | **SAME** |  |
| autoApprovePendingCode | default | us-c1 | 1 | nodejs20 | v23 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| autoApprovePendingCodeOnUpdate | default | us-c1 | 1 | nodejs20 | v23 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| autoUpdateDepartureTime | default | us-c1 | 1 | nodejs20 | v24 | 2026-10-16 12:28 | sp5QqC+w | aea0d8d8 |  | DIVERGED | **MAINLINE_NEWER** |  |
| backfillEngagementIndex | default | us-c1 | 1 | nodejs20 | v6 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| bootstrapAdminUser | default | us-c1 | 1 | nodejs20 | v34 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| buildHolidayBasket | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| buildTvFeedJson | default | us-c1 | 1 | nodejs22 | v2 | 2026-11-19 20:49 | 20/wuQ+g | 9771c4e6 | feat/avagram-news-srv | SAME | **SAME** |  |
| businessAcceptOrder | default | us-c1 | 1 | nodejs22 | v2 | 2026-11-16 09:56 | m7aluLVc | e0f1d57d |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| businessMarkReady | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-03 04:47 | jDSk+nf7 | a55d78b3 |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| businessProductsCascade | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-25 10:10 | 6IJqILiA | 2cc56591 |  | DIVERGED | **SAME** |  |
| businessRejectOrder | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-03 04:47 | jDSk+nf7 | a55d78b3 |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| calibrateLocalTaxiRoadFactor | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-08 02:18 | QS+FP6Yv | 8bee7cddВ±1 | deploy/hosting-ulgurji | SAME | **SAME** |  |
| cancelChinaInquiry | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-20 17:30 | OJiiM3GR | f1ff9ca4 |  | SAME | **SAME** |  |
| cancelRestaurantBooking | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-19 12:01 | IwjU2UoG | 11ab5913В±1 |  | SAME | **SAME** |  |
| cancelSettlement | default | us-c1 | 1 | nodejs20 | v20 | 2026-10-08 16:17 | LkaWH9lb | e7a40724 |  | SAME | **SAME** |  |
| cancelTaxiTrip | default | us-c1 | 1 | nodejs20 | v6 | 2026-10-16 12:28 | sp5QqC+w | aea0d8d8 |  | LIVE_NEWER | **SAME** |  |
| cashExchange | default | us-c1 | 1 | nodejs20 | v13 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| changeDevicePhone | default | us-c1 | 1 | nodejs20 | v29 | 2026-10-08 10:14 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| checkDeviceBinding | default | eu-w1 | 1 | nodejs20 | v11 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| checkWithdrawalLimit | default | us-c1 | 1 | nodejs20 | v27 | 2026-10-08 16:17 | LkaWH9lb | e7a40724 |  | SAME | **SAME** |  |
| claimCarProfileBonus | default | us-c1 | 1 | nodejs20 | v13 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| claimIncentive | default | us-c1 | 1 | nodejs22 | v2 | 2026-11-02 20:45 | jWD2Iilm | e0985429 | feat/incentives-srv | DIVERGED | **MAINLINE_NEWER** |  |
| claimRelativesBonus | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| cleanupStaleDrivers | default | us-c1 | 1 | nodejs20 | v45 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| clipPage | default | us-c1 | 1 | nodejs20 | v3 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| closePeriod | default | us-c1 | 1 | nodejs20 | v17 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| completeLocalTrip | default | us-c1 | 1 | nodejs20 | v16 | 2026-10-07 18:53 | X91h/XtW | df062163 |  | SAME | **SAME** |  |
| completeTaxiTrip | default | us-c1 | 1 | nodejs20 | v5 | 2026-10-08 16:17 | LkaWH9lb | e7a40724 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| confirmPayout | default | us-c1 | 1 | nodejs20 | v49 | 2026-10-08 10:14 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| confirmSettlement | default | us-c1 | 1 | nodejs20 | v21 | 2026-10-08 16:17 | LkaWH9lb | e7a40724 |  | SAME | **SAME** |  |
| courierAcceptRestaurantHandover | default | us-c1 | 1 | nodejs22 | v1 | 2026-10-31 18:03 | gmPGVCnT | 2b69ff46 | feat/courier-failed-handover-srv | LIVE_ONLY | **MAINLINE_NEWER** |  |
| courierArriveBusinessOrder | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-03 04:47 | jDSk+nf7 | a55d78b3 |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| courierArriveRestaurantOrder | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-09 01:24 | QmQAQ/Ce | dae5406e |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| courierCancelRestaurantHandover | default | us-c1 | 1 | nodejs22 | v1 | 2026-10-31 18:03 | gmPGVCnT | 2b69ff46 | feat/courier-failed-handover-srv | LIVE_ONLY | **MAINLINE_NEWER** |  |
| courierCashPendingSweep | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-16 05:16 | +aYZUqII | 6cdba7c5 |  | LIVE_ONLY | **SAME** |  |
| courierClaimAgroPickup | default | us-c1 | 1 | nodejs22 | v21 | 2026-10-31 12:47 | Kel/Zoyq | 420ed0b2 | pin/courier-scopes | SAME | **SAME** |  |
| courierClaimBusinessOrder | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-03 04:47 | jDSk+nf7 | a55d78b3 |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| courierClaimCarpetPickup | default | us-c1 | 1 | nodejs22 | v22 | 2026-10-31 12:47 | Kel/Zoyq | 420ed0b2 | pin/courier-scopes | SAME | **SAME** |  |
| courierClaimCarpetReturn | default | us-c1 | 1 | nodejs22 | v22 | 2026-10-31 12:47 | Kel/Zoyq | 420ed0b2 | pin/courier-scopes | SAME | **SAME** |  |
| courierClaimRestaurantOrder | default | us-c1 | 1 | nodejs22 | v6 | 2026-10-31 18:03 | gmPGVCnT | 2b69ff46 | feat/courier-failed-handover-srv | DIVERGED | **MAINLINE_NEWER** |  |
| courierCompleteBusinessOrder | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-03 04:47 | jDSk+nf7 | a55d78b3 |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| courierCompleteRestaurantDelivery | default | us-c1 | 1 | nodejs22 | v7 | 2026-10-31 18:03 | gmPGVCnT | 2b69ff46 | feat/courier-failed-handover-srv | DIVERGED | **MAINLINE_NEWER** |  |
| courierCreateRoute | default | us-c1 | 1 | nodejs22 | v28 | 2026-11-03 04:44 | jDSk+nf7 | a55d78b3 |  | DIVERGED | **SAME** |  |
| courierFinalizeCollection | default | us-c1 | 1 | nodejs22 | v29 | 2026-11-02 22:01 | Q+2FYYD4 | 496e080e | fix/courier-3bugs-srv | DIVERGED | **MAINLINE_NEWER** |  |
| courierGetCustomerWalletBalance | default | us-c1 | 1 | nodejs20 | v22 | 2026-10-08 10:26 | Xx+MNcV+ | ed0241af |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| courierListAgroTasks | default | us-c1 | 1 | nodejs22 | v3 | 2026-10-31 19:08 | YX0wh3qj | f00a6bbe | feat/courier-failed-other-srv | DIVERGED | **MAINLINE_NEWER** |  |
| courierListCarpetTasks | default | us-c1 | 1 | nodejs22 | v3 | 2026-10-31 19:08 | YX0wh3qj | f00a6bbe | feat/courier-failed-other-srv | DIVERGED | **MAINLINE_NEWER** |  |
| courierListReadyOrders | default | us-c1 | 1 | nodejs22 | v7 | 2026-11-03 04:44 | jDSk+nf7 | a55d78b3 |  | DIVERGED | **SAME** |  |
| courierMarkAgroPickedUp | default | us-c1 | 1 | nodejs20 | v22 | 2026-10-16 08:37 | 0UNP8F7o | 77bfbe13 |  | DIVERGED | **MAINLINE_NEWER** |  |
| courierMarkAgroPickupArrived | default | us-c1 | 1 | nodejs20 | v21 | 2026-10-16 05:16 | +aYZUqII | 6cdba7c5 |  | DIVERGED | **MAINLINE_NEWER** |  |
| courierMarkArrived | default | us-c1 | 1 | nodejs22 | v37 | 2026-11-03 04:44 | jDSk+nf7 | a55d78b3 |  | DIVERGED | **SAME** |  |
| courierMarkCarpetArrived | default | us-c1 | 1 | nodejs20 | v21 | 2026-10-16 05:16 | +aYZUqII | 6cdba7c5 |  | DIVERGED | **MAINLINE_NEWER** |  |
| courierMarkCarpetDelivered | default | us-c1 | 1 | nodejs20 | v24 | 2026-10-16 08:37 | 0UNP8F7o | 77bfbe13 |  | DIVERGED | **MAINLINE_NEWER** |  |
| courierMarkCarpetPickedUp | default | us-c1 | 1 | nodejs20 | v24 | 2026-10-16 08:37 | 0UNP8F7o | 77bfbe13 |  | DIVERGED | **MAINLINE_NEWER** |  |
| courierMarkCollectionArrived | default | us-c1 | 1 | nodejs22 | v22 | 2026-11-02 22:01 | Q+2FYYD4 | 496e080e | fix/courier-3bugs-srv | DIVERGED | **SAME** |  |
| courierMarkPicked | default | us-c1 | 1 | nodejs22 | v35 | 2026-11-03 04:44 | jDSk+nf7 | a55d78b3 |  | DIVERGED | **SAME** |  |
| courierPayoutReconcile | default | us-c1 | 1 | nodejs22 | v1 | 2026-10-31 05:07 | n/SPTx8c | 7de7a7e1 |  | LIVE_ONLY | **SAME** |  |
| courierPickupBusinessOrder | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-03 04:47 | jDSk+nf7 | a55d78b3 |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| courierPickupRestaurantOrder | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-09 01:24 | QmQAQ/Ce | dae5406e |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| courierRecoverOrphanRoute | default | us-c1 | 1 | nodejs22 | v24 | 2026-11-03 04:44 | jDSk+nf7 | a55d78b3 |  | DIVERGED | **SAME** |  |
| courierReportDeliveryFailed | default | us-c1 | 1 | nodejs22 | v3 | 2026-11-03 04:44 | jDSk+nf7 | a55d78b3 |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| courierRequestScopes | default | us-c1 | 1 | nodejs22 | v1 | 2026-10-31 12:24 | Kel/Zoyq | 420ed0b2 | pin/courier-scopes | DIVERGED | **SAME** |  |
| courierSetBuyoutPrefs | default | us-c1 | 1 | nodejs22 | v3 | 2026-10-31 12:47 | Kel/Zoyq | 420ed0b2 | pin/courier-scopes | DIVERGED | **MAINLINE_NEWER** |  |
| courierStartRestaurantHandover | default | us-c1 | 1 | nodejs22 | v1 | 2026-10-31 18:03 | gmPGVCnT | 2b69ff46 | feat/courier-failed-handover-srv | LIVE_ONLY | **MAINLINE_NEWER** |  |
| courierSubmitPayment | default | us-c1 | 1 | nodejs22 | v50 | 2026-11-03 04:44 | jDSk+nf7 | a55d78b3 |  | DIVERGED | **SAME** |  |
| createChinaInquiry | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-20 17:30 | OJiiM3GR | f1ff9ca4 |  | SAME | **SAME** |  |
| createLocalTaxiTrip | default | us-c1 | 1 | nodejs20 | v3 | 2026-10-08 02:18 | QS+FP6Yv | 8bee7cddВ±1 | deploy/hosting-ulgurji | SAME | **SAME** |  |
| createPhoneSession | default | eu-w1 | 1 | nodejs20 | v8 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| createRealtyAlert | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-15 04:07 | srfp4s4Y | 0add857eВ±1 |  | SAME | **SAME** |  |
| createTelegramLinkCode | default | us-c1 | 1 | nodejs20 | v14 | 2026-10-18 06:31 | Hr6Qy2zC | 1e42ac32 |  | SAME | **SAME** |  |
| creditChange | default | us-c1 | 1 | nodejs20 | v48 | 2026-10-08 04:58 | xc1tV78w | f575181d | fix/wallet-followups | SAME | **SAME** |  |
| creditSupplier | default | us-c1 | 1 | nodejs20 | v48 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| customerCancelBusinessOrder | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-03 04:47 | jDSk+nf7 | a55d78b3 |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| customerCancelOrder | default | us-c1 | 1 | nodejs22 | v20 | 2026-11-26 19:55 | rvhPMpJx | fbaf2621 | fix/sm-customer-cancel-b9cfffcc | DIVERGED | **SAME** |  |
| customerCancelRestaurantOrder | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-09 01:24 | QmQAQ/Ce | dae5406e |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| customerConfirmHandover | default | us-c1 | 1 | nodejs22 | v6 | 2026-11-03 04:44 | jDSk+nf7 | a55d78b3 |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| customerMarkRestaurantOrderPaid | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-09 01:24 | QmQAQ/Ce | dae5406e |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| dailyReport20 | default | us-c1 | 1 | nodejs20 | v44 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| debitForOrder | default | us-c1 | 1 | nodejs20 | v47 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| deleteDatingProfile | default | us-c1 | 1 | nodejs20 | v16 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| deleteHlsSpike | default | us-c1 | 1 | nodejs20 | v6 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| deleteMyBusiness | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-25 07:34 | kqjEOTT2 | a07abc0f |  | LIVE_NEWER | **SAME** |  |
| deleteMyMainShop | default | us-c1 | 1 | nodejs22 | v4 | 2026-11-16 18:08 | p3h2Ayos | 8d393e86 | fix/pickup-cleanup-3feb9d6e | LIVE_ONLY | **SAME** |  |
| deleteRealtyListing | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-06 06:39 | mqmy34rY | d2d45a96 | fix/bozor-live-port-d2d45a96 | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| deleteRelativePerson | default | us-c1 | 1 | nodejs20 | v15 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| detectAnomaly | default | us-c1 | 1 | nodejs20 | v26 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| driverFloatStatus | default | us-c1 | 1 | nodejs20 | v17 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| ensureMyTree | default | us-c1 | 1 | nodejs20 | v18 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| ensureRestaurantSeasons | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-19 12:01 | IwjU2UoG | 11ab5913В±1 |  | SAME | **SAME** |  |
| escalateDeliveryFailed | default | us-c1 | 1 | nodejs22 | v3 | 2026-11-03 04:44 | jDSk+nf7 | a55d78b3 |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| escalateRestaurantDeliveryFailed | default | us-c1 | 1 | nodejs22 | v2 | 2026-10-31 18:03 | gmPGVCnT | 2b69ff46 | feat/courier-failed-handover-srv | LIVE_ONLY | **MAINLINE_NEWER** |  |
| evStaticMap | default | us-c1 | 1 | nodejs20 | v3 | 2026-10-06 06:39 | L/skxMwL | a21e575c | fix/secrets-to-secret-manager | SAME | **SAME** |  |
| expirePendingTrips | default | us-c1 | 1 | nodejs20 | v57 | 2026-10-16 12:28 | sp5QqC+w | aea0d8d8 |  | LIVE_NEWER | **SAME** |  |
| expireRestaurantBookings | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-19 12:01 | IwjU2UoG | 11ab5913В±1 |  | SAME | **SAME** |  |
| expireReturnedRestaurantOrders | default | us-c1 | 1 | nodejs22 | v1 | 2026-10-31 18:03 | gmPGVCnT | 2b69ff46 | feat/courier-failed-handover-srv | LIVE_ONLY | **MAINLINE_NEWER** |  |
| expireTvContent | default | us-c1 | 1 | nodejs22 | v11 | 2026-11-19 20:49 | 20/wuQ+g | 9771c4e6 | feat/avagram-news-srv | DIVERGED | **SAME** |  |
| expireUnacceptedBusinessOrders | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-03 04:47 | jDSk+nf7 | a55d78b3 |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| expireUnacceptedRestaurantOrders | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-09 01:24 | QmQAQ/Ce | dae5406e |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| floatReturn | default | us-c1 | 1 | nodejs20 | v18 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| floatTopUp | default | us-c1 | 1 | nodejs20 | v19 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| fundShipmentEscrow | default | us-c1 | 1 | nodejs22 | v3 | 2026-10-31 04:58 | dWL80BDm | 76a9ec3dВ±2 |  | LIVE_NEWER | **SAME** |  |
| generateDailyReportNow | default | us-c1 | 1 | nodejs20 | v45 | 2026-10-08 10:18 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| getBusinessOrdersAccess | default | us-c1 | 1 | nodejs22 | v2 | 2026-11-16 09:56 | m7aluLVc | e0f1d57d |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| getChinaInquiryAccess | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-20 17:29 | OJiiM3GR | f1ff9ca4 |  | SAME | **SAME** |  |
| getCustomerPendingConfirmations | default | us-c1 | 1 | nodejs22 | v5 | 2026-11-03 04:44 | jDSk+nf7 | a55d78b3 |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| getDeviceTransferStatus | default | eu-w1 | 1 | nodejs20 | v7 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| getDirections | default | us-c1 | 1 | nodejs20 | v28 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| getEvStationTariffs | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| getHolidayCatalog | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| getMoneyControlSnapshot | default | us-c1 | 1 | nodejs20 | v14 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| getMyFamilyLinks | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| getMyIncentiveOffers | default | us-c1 | 1 | nodejs22 | v2 | 2026-11-02 20:45 | jWD2Iilm | e0985429 | feat/incentives-srv | DIVERGED | **MAINLINE_NEWER** |  |
| getMyShopLink | default | us-c1 | 1 | nodejs20 | v3 | 2026-10-25 19:47 | SGinORMQ | 811a7c28 |  | LIVE_ONLY | **SAME** |  |
| getPendingCodeStatus | default | eu-w1 | 1 | nodejs20 | v6 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| getRealtyPackagePricing | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-06 06:39 | mqmy34rY | d2d45a96 | fix/bozor-live-port-d2d45a96 | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| getRealtyPricing | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-06 06:39 | mqmy34rY | d2d45a96 | fix/bozor-live-port-d2d45a96 | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| getRealtyProPlans | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-06 06:39 | mqmy34rY | d2d45a96 | fix/bozor-live-port-d2d45a96 | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| getRealtyQuota | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-06 06:39 | mqmy34rY | d2d45a96 | fix/bozor-live-port-d2d45a96 | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| getRestaurantsAccess | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-09 01:24 | QmQAQ/Ce | dae5406e |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| getSupermarketAccess | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| getWalletTopUpReceiptUrl | default | us-c1 | 1 | nodejs20 | v11 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| getWalletTopUpStatus | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-18 07:54 | pbkTiiWk | fd151de0 |  | SAME | **SAME** |  |
| grantBirthdayBonus | default | us-c1 | 1 | nodejs20 | v32 | 2026-10-08 10:14 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| hlsSpikeTranscode | default | us-c1 | 1 | nodejs20 | v6 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| holidayReminders | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| incentiveExpirySweep | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-02 18:43 | RYERmEvb | 41948286 |  | DIVERGED | **MAINLINE_NEWER** |  |
| intercityCancelBooking | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-16 12:28 | sp5QqC+w | aea0d8d8 |  | LIVE_NEWER | **SAME** |  |
| intercityCompleteBooking | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-16 12:28 | sp5QqC+w | aea0d8d8 |  | LIVE_NEWER | **SAME** |  |
| intercityCreateBooking | default | us-c1 | 1 | nodejs20 | v3 | 2026-10-16 12:28 | sp5QqC+w | aea0d8d8 |  | SAME | **SAME** |  |
| inviteRelative | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| inviteSpouse | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| leaveDriverRole | default | us-c1 | 1 | nodejs20 | v37 | 2026-10-08 10:14 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| leaveDriverType | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-16 19:39 | vqxRt5A9 | 6a124f51 |  | SAME | **SAME** |  |
| linkBusinessRestaurant | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-02 20:53 | vw1a93Cd | 1df1f273 | feat/biz-restaurant-link-srv | LIVE_ONLY | **SAME** |  |
| linkRealtyVideo | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-06 06:39 | mqmy34rY | d2d45a96 | fix/bozor-live-port-d2d45a96 | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| listDeliveryFailedPending | default | us-c1 | 1 | nodejs22 | v3 | 2026-11-16 09:56 | m7aluLVc | e0f1d57d |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| listMyPendingDeviceTransfers | default | eu-w1 | 1 | nodejs20 | v7 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| listNearbyBusinessOrders | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-03 04:47 | jDSk+nf7 | a55d78b3 |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| listNearbyRestaurantOrders | default | us-c1 | 1 | nodejs22 | v4 | 2026-10-31 12:47 | Kel/Zoyq | 420ed0b2 | pin/courier-scopes | DIVERGED | **MAINLINE_NEWER** |  |
| listOpenDeliveryQuotes | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-16 12:53 | 5t8eXCll | f6644f6a |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| lockLocalTripFare | default | us-c1 | 1 | nodejs20 | v3 | 2026-10-08 02:18 | QS+FP6Yv | 8bee7cddВ±1 | deploy/hosting-ulgurji | SAME | **SAME** |  |
| markDealChatRead | default | us-c1 | 1 | nodejs22 | v2 | 2026-11-01 06:11 | U69sKH2c | 8092fef0 | feat/deal-chat-srv | LIVE_ONLY | **SAME** |  |
| marketListingsExpirySweep | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-15 11:41 | Yk366IL9 | 35b8dfd1В±1 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| marketListingsExpiryWarning | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-15 11:41 | Yk366IL9 | 35b8dfd1В±1 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| marshrutDriverAutoOffline | default | us-c1 | 1 | nodejs20 | v30 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| marshrutPassengerCancelAfterAccept | default | us-c1 | 1 | nodejs20 | v25 | 2026-10-15 04:43 | BBDy6rrE | 97ca173fВ±1 |  | SAME | **SAME** |  |
| marshrutPassengerCloseOffer | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-15 04:43 | BBDy6rrE | 97ca173fВ±1 |  | SAME | **SAME** |  |
| mergeAnonymousSession | default | us-c1 | 1 | nodejs20 | v7 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| mergeTreePersons | default | us-c1 | 1 | nodejs20 | v20 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| migrateCheapProductTitleLower | default | us-c1 | 1 | nodejs20 | v26 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **MAINLINE_NEWER** |  |
| migrateFloatToWallet | default | us-c1 | 1 | nodejs20 | v13 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| migrateOldBindings | default | us-c1 | 1 | nodejs20 | v28 | 2026-10-08 10:18 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| migratePhoneFormats | default | us-c1 | 1 | nodejs20 | v23 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| onAdminNewsCreate | default | us-c1 | 1 | nodejs20 | v38 | 2026-10-16 20:09 | db6VMW9Q | dbaf6192 |  | SAME | **SAME** |  |
| onAdminNewsUpdate | default | us-c1 | 1 | nodejs20 | v34 | 2026-10-16 20:09 | db6VMW9Q | dbaf6192 |  | SAME | **SAME** |  |
| onAdUpdate | default | us-c1 | 1 | nodejs22 | v42 | 2026-11-15 12:02 | 1Lp3fBuU | bc82966d | fix/bozor-live-port-b7b52700 | DIVERGED | **SAME** |  |
| onAssistantMessageCreated | default | us-c1 | 1 | nodejs20 | v5 | 2026-10-06 06:39 | L/skxMwL | a21e575c | fix/secrets-to-secret-manager | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| onBirthDateRequestUpdate | default | us-c1 | 1 | nodejs20 | v35 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| onDatingProfileWriteSyncPublic | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-06 06:39 | KbfRIWGA | a78f23ac |  | SAME | **SAME** |  |
| onDeliveryRouteAssign | default | us-c1 | 1 | nodejs22 | v33 | 2026-10-31 12:47 | Kel/Zoyq | 420ed0b2 | pin/courier-scopes | DIVERGED | **SAME** |  |
| onDeliveryRouteCreate | default | us-c1 | 1 | nodejs22 | v49 | 2026-10-31 12:47 | Kel/Zoyq | 420ed0b2 | pin/courier-scopes | DIVERGED | **SAME** |  |
| onDeviceChangeRequestUpdate | default | us-c1 | 1 | nodejs20 | v35 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| onEvConfirmationWrite | default | eu-w1 | 2 | nodejs20 | vonevconfirmationwrite-00003-xer | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| onEvReportCreate | default | eu-w1 | 2 | nodejs20 | vonevreportcreate-00003-xaz | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| onIntercityBookingCancelled | default | us-c1 | 1 | nodejs20 | v22 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| onIntercityBookingCreated | default | us-c1 | 1 | nodejs20 | v21 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| onIntercityBookingUpdated | default | us-c1 | 1 | nodejs20 | v21 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| onIntercityDriverUpdate | default | us-c1 | 1 | nodejs20 | v40 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| onIntercityPickupUpdated | default | us-c1 | 1 | nodejs20 | v21 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| onLogisticsCustodyEvent | default | us-c1 | 1 | nodejs20 | v3 | 2026-10-16 06:07 | a6lIxN2y | 76a9ec3d |  | LIVE_NEWER | **MAINLINE_NEWER** |  |
| onLogisticsShipmentUpdate | default | us-c1 | 1 | nodejs22 | v4 | 2026-11-14 21:10 | XPLwOvcA | d5ef369d | feat/relay-cash-loss-srv | LIVE_NEWER | **MAINLINE_NEWER** |  |
| onMarshrutTripCreate | default | us-c1 | 1 | nodejs20 | v42 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| onNotificationCreate | default | us-c1 | 1 | nodejs20 | v42 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| onOrderCreate | default | us-c1 | 1 | nodejs22 | v49 | 2026-11-26 19:56 | 5IJG+BrY | 54e07faf | fix/sm-label-orders-7418a7a8 | SAME | **SAME** |  |
| onOrderUpdate | default | us-c1 | 1 | nodejs22 | v53 | 2026-11-26 19:56 | 5IJG+BrY | 54e07faf | fix/sm-label-orders-7418a7a8 | SAME | **MAINLINE_NEWER** |  |
| onPlatformProductPromoWrite | default | us-c1 | 1 | nodejs22 | v2 | 2026-11-20 02:35 | BIgX/bzf | 8d1a8602 | fix/promo-cap-1120 | SAME | **SAME** |  |
| onRealtyListingActivated | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-15 04:08 | srfp4s4Y | 0add857eВ±1 |  | SAME | **SAME** |  |
| onRealtyListingDeleted | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-19 19:42 | S67nwOvp | 82f2ecb7 |  | SAME | **SAME** |  |
| onRelativeBirthdayIndex | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| onRelativePersonWrite | default | us-c1 | 1 | nodejs20 | v18 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| onRelayCashShipmentUpdate | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-14 16:37 | hXXYEK1Q | badd3ff0 | feat/ulg-s57-srv | LIVE_ONLY | **SAME** |  |
| onRelayEarnedCourierPayout | default | us-c1 | 1 | nodejs22 | v1 | 2026-10-31 05:07 | n/SPTx8c | 7de7a7e1 |  | LIVE_ONLY | **SAME** |  |
| onRestaurantDishStatsWritten | default | us-c1 | 1 | nodejs20 | v4 | 2026-10-19 18:59 | 7Luc07DK | f4048969 |  | SAME | **SAME** |  |
| onRestaurantIndexSourceWritten | default | us-c1 | 1 | nodejs20 | v4 | 2026-10-19 18:59 | 7Luc07DK | f4048969 |  | SAME | **SAME** |  |
| onRestaurantMenuItemDeleted | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-19 08:39 | rVPLRpc/ | 30af7f73В±1 |  | SAME | **SAME** |  |
| onRestaurantMenuItemWritten | default | us-c1 | 1 | nodejs20 | v4 | 2026-10-19 18:59 | 7Luc07DK | f4048969 |  | SAME | **SAME** |  |
| onSearchIndexAdWrite | default | eu-w1 | 2 | nodejs20 | vonsearchindexadwrite-00006-viq | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **MAINLINE_NEWER** |  |
| onSearchIndexBreadProductWrite | default | eu-w1 | 2 | nodejs20 | vonsearchindexbreadproductwrite-00006-tuh | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **MAINLINE_NEWER** |  |
| onSearchIndexBusinessWrite | default | eu-w1 | 2 | nodejs22 | vonsearchindexbusinesswrite-00002-pen | 2026-11-02 22:14 | Kfx2FcPE | 909b050c | feat/biz-s6-srv | LIVE_ONLY | **SAME** |  |
| onSearchIndexPlatformProductWrite | default | eu-w1 | 2 | nodejs20 | vonsearchindexplatformproductwrite-00007-qew | 2026-10-08 02:35 | 3sjBGdqA | 0b9ef3aaВ±1 |  | SAME | **MAINLINE_NEWER** |  |
| onSearchIndexRestaurantWrite | default | eu-w1 | 2 | nodejs20 | vonsearchindexrestaurantwrite-00001-vaq | 2026-10-25 16:54 | zcLmKSx3 | ffbb4d61 |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| onSearchIndexShopItemWrite | default | eu-w1 | 2 | nodejs22 | vonsearchindexshopitemwrite-00002-med | 2026-11-02 22:14 | Kfx2FcPE | 909b050c | feat/biz-s6-srv | LIVE_ONLY | **SAME** |  |
| onSearchIndexTvShopWrite | default | eu-w1 | 2 | nodejs20 | vonsearchindextvshopwrite-00001-ved | 2026-10-25 11:20 | bTnLA8Iv | 37d75a94 |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| onSearchIndexYukListingWrite | default | eu-w1 | 2 | nodejs20 | vonsearchindexyuklistingwrite-00006-loz | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | LIVE_ABSENT_IN_ARCHIVE? | **MAINLINE_NEWER*** | yuk_intercity.js: faqat runExpiry matni (5 sutka) o'zgargan; trigger kodi bir xil (qo'lda) |
| onSellSubmissionUpdate | default | us-c1 | 1 | nodejs20 | v38 | 2026-10-08 10:14 | 5QRrk06u | ed0241af |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| onShopItemModeration | default | us-c1 | 1 | nodejs22 | v2 | 2026-11-19 20:45 | IBhLycaP | fd5db610 | deploy/rel-1120-srv | SAME | **SAME** |  |
| onShopItemPromoWrite | default | us-c1 | 1 | nodejs22 | v2 | 2026-11-20 02:35 | BIgX/bzf | 8d1a8602 | fix/promo-cap-1120 | SAME | **SAME** |  |
| onShopItemSearchTokens | default | us-c1 | 1 | nodejs22 | v2 | 2026-11-19 20:44 | IBhLycaP | fd5db610 | deploy/rel-1120-srv | SAME | **SAME** |  |
| onSmListWrite | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| onSupermarketOrderCancelStock | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| onSupportChatMessageCreate | default | us-c1 | 1 | nodejs20 | v47 | 2026-10-08 10:14 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| onTripUpdate | default | us-c1 | 1 | nodejs20 | v60 | 2026-10-08 05:37 | B8Rt87L3 | 8bee7cddВ±2 | deploy/hosting-ulgurji | DIVERGED | **MAINLINE_NEWER*** | appendSystemSupportChatMessage ga {systemOrder} opsiyasi qo'shilgan (82f2ecb7/f1c45289 dan); jonli xulq saqlangan |
| onTvClipBackfillRequested | default | us-c1 | 2 | nodejs22 | vontvclipbackfillrequested-00018-yay | 2026-10-30 20:10 | QaFsA/BO | 061d6eca |  | LIVE_NEWER | **SAME** |  |
| onTvClipCreatedV2 | default | us-c1 | 2 | nodejs22 | vontvclipcreatedv2-00021-rad | 2026-10-30 20:10 | QaFsA/BO | 061d6eca |  | LIVE_NEWER | **SAME** |  |
| onTvClipDeleted | default | us-c1 | 1 | nodejs22 | v11 | 2026-10-30 20:08 | QaFsA/BO | 061d6eca |  | LIVE_NEWER | **SAME** |  |
| onTvClipRejected | default | us-c1 | 1 | nodejs20 | v6 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| onTvClipSocialPublish | default | us-c1 | 1 | nodejs22 | v12 | 2026-11-19 20:49 | 20/wuQ+g | 9771c4e6 | feat/avagram-news-srv | DIVERGED | **SAME** |  |
| onTvClipVideoReplacedV2 | default | us-c1 | 2 | nodejs22 | vontvclipvideoreplacedv2-00023-lig | 2026-10-30 20:43 | smef5mzp | b7b52700 |  | LIVE_NEWER | **SAME** |  |
| onUserProfileReady | default | us-c1 | 1 | nodejs20 | v16 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| onWholesaleCustodyEvent | default | us-c1 | 1 | nodejs22 | v7 | 2026-11-14 16:37 | hXXYEK1Q | badd3ff0 | feat/ulg-s57-srv | LIVE_ONLY | **MAINLINE_NEWER** |  |
| onWholesaleOrderStatusChange | default | us-c1 | 1 | nodejs22 | v11 | 2026-11-14 16:37 | hXXYEK1Q | badd3ff0 | feat/ulg-s57-srv | LIVE_ONLY | **MAINLINE_NEWER** |  |
| onWholesaleProductPromoWrite | default | us-c1 | 1 | nodejs22 | v2 | 2026-11-20 02:35 | BIgX/bzf | 8d1a8602 | fix/promo-cap-1120 | SAME | **SAME** |  |
| onWholesaleShipmentLoss | default | us-c1 | 1 | nodejs22 | v6 | 2026-11-14 21:11 | XPLwOvcA | d5ef369d | feat/relay-cash-loss-srv | LIVE_ONLY | **MAINLINE_NEWER** |  |
| onWholesaleStockBadge | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-19 20:45 | IBhLycaP | fd5db610 | deploy/rel-1120-srv | SAME | **SAME** |  |
| onYukLocalDriverWrite | default | us-c1 | 1 | nodejs22 | v3 | 2026-10-31 10:29 | 8yn3VoIj | 478c4ca3 |  | LIVE_ONLY | **SAME** |  |
| openDealChat | default | us-c1 | 1 | nodejs22 | v3 | 2026-11-02 22:09 | /KtJE1BB | a4911c8d | feat/biz-s4-srv | LIVE_ONLY | **SAME** |  |
| openSettlement | default | us-c1 | 1 | nodejs20 | v21 | 2026-10-08 16:17 | LkaWH9lb | e7a40724 |  | SAME | **SAME** |  |
| orderIndexOnCarpet | default | eu-w1 | 2 | nodejs20 | vorderindexoncarpet-00001-ceg | 2026-10-15 04:07 | srfp4s4Y | 0add857eВ±1 |  | SAME | **MAINLINE_NEWER** |  |
| orderIndexOnDemands | default | eu-w1 | 2 | nodejs20 | vorderindexondemands-00001-lip | 2026-10-15 04:07 | srfp4s4Y | 0add857eВ±1 |  | SAME | **MAINLINE_NEWER** |  |
| orderIndexOnMilk | default | eu-w1 | 2 | nodejs20 | vorderindexonmilk-00001-mih | 2026-10-15 04:07 | srfp4s4Y | 0add857eВ±1 |  | SAME | **MAINLINE_NEWER** |  |
| orderIndexOnOrders | default | eu-w1 | 2 | nodejs22 | vorderindexonorders-00002-pud | 2026-11-03 04:44 | jDSk+nf7 | a55d78b3 |  | LIVE_NEWER | **SAME** |  |
| orderIndexOnShipments | default | eu-w1 | 2 | nodejs20 | vorderindexonshipments-00001-hep | 2026-10-15 04:07 | srfp4s4Y | 0add857eВ±1 |  | SAME | **MAINLINE_NEWER** |  |
| payAndCreateEvStation | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| payWholesaleBuyerDebt | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-15 01:43 | yhWp9Ixk | 1b37de53 | feat/ulg-debt-pay-srv | LIVE_ONLY | **MAINLINE_NEWER** |  |
| placeAgroPickupOrder | default | us-c1 | 1 | nodejs20 | v20 | 2026-10-16 05:16 | +aYZUqII | 6cdba7c5 |  | LIVE_NEWER | **SAME** |  |
| placeBusinessOrder | default | us-c1 | 1 | nodejs22 | v4 | 2026-11-16 17:23 | N5ESIkER | 03d85441 | feat/bozor-orders-srv | LIVE_ONLY | **MAINLINE_NEWER** |  |
| placeCarpetWashOrder | default | us-c1 | 1 | nodejs20 | v21 | 2026-10-16 05:16 | +aYZUqII | 6cdba7c5 |  | LIVE_NEWER | **SAME** |  |
| placeOrderPostPaid | default | us-c1 | 1 | nodejs22 | v47 | 2026-11-26 19:53 | jItuM3zT | ac15f486 | fix/platform-sm-guard-496e080e | DIVERGED | **SAME** |  |
| placeOrderWithWallet | default | us-c1 | 1 | nodejs20 | v49 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| placeRestaurantBooking | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-19 12:01 | IwjU2UoG | 11ab5913В±1 |  | SAME | **SAME** |  |
| placeRestaurantOrder | default | us-c1 | 1 | nodejs22 | v9 | 2026-11-26 19:59 | sgh8rxeC | 73178957 | fix/restaurant-preorder-dish-ce23f0ed | DIVERGED | **MAINLINE_NEWER** |  |
| placeSupermarketOrder | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| placeWholesaleOrder | default | us-c1 | 1 | nodejs22 | v9 | 2026-11-19 20:56 | wGIif00v | ed6c6dab | fix/ulg-requote-1b37de53 | LIVE_ONLY | **SAME** |  |
| previewIncentiveForOrder | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-02 19:11 | pYRaqydY | 643be751 |  | DIVERGED | **MAINLINE_NEWER** |  |
| productPromoExpirySweep | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-19 20:44 | IBhLycaP | fd5db610 | deploy/rel-1120-srv | SAME | **SAME** |  |
| promoteToAdminWithPin | default | us-c1 | 1 | nodejs20 | v45 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| publishTaxiTrip | default | us-c1 | 1 | nodejs20 | v7 | 2026-10-16 12:28 | sp5QqC+w | aea0d8d8 |  | LIVE_NEWER | **SAME** |  |
| publishTvAd | default | us-c1 | 1 | nodejs20 | v12 | 2026-10-25 12:33 | dlkmFUhO | 18d45c45 |  | DIVERGED | **SAME** |  |
| purchaseRealtyPackage | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-08 04:59 | xc1tV78w | f575181d | fix/wallet-followups | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| purchaseRealtyProPackage | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-08 04:59 | xc1tV78w | f575181d | fix/wallet-followups | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| purchaseRealtyTier | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-08 04:59 | xc1tV78w | f575181d | fix/wallet-followups | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| purgeRetractedAdminNews | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-19 20:14 | IEXEFQtS | f1c45289 |  | SAME | **SAME** |  |
| quoteBusinessOrder | default | us-c1 | 1 | nodejs22 | v4 | 2026-11-16 17:23 | N5ESIkER | 03d85441 | feat/bozor-orders-srv | LIVE_ONLY | **SAME** |  |
| quoteRestaurantDelivery | default | us-c1 | 1 | nodejs20 | v4 | 2026-10-19 10:14 | cOw7BBv+ | a0abb163В±1 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| quoteTaxiFee | default | us-c1 | 1 | nodejs20 | v6 | 2026-10-15 10:51 | 6h3z5Lr7 | c3e111c0В±1 |  | SAME | **SAME** |  |
| realtyAlertsExpirySweep | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-15 04:07 | srfp4s4Y | 0add857eВ±1 |  | SAME | **SAME** |  |
| realtyExpirySweep | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-06 06:39 | mqmy34rY | d2d45a96 | fix/bozor-live-port-d2d45a96 | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| realtyExpiryWarning | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-06 06:39 | mqmy34rY | d2d45a96 | fix/bozor-live-port-d2d45a96 | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| receiveCourierCash | default | us-c1 | 1 | nodejs20 | v14 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| reconcileLedger | default | us-c1 | 1 | nodejs20 | v17 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| reconcileTvProfileViews | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-06 06:39 | oZitD9rS | 52212546В±1 |  | SAME | **SAME** |  |
| recordShopEvent | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-25 16:54 | zcLmKSx3 | ffbb4d61 |  | LIVE_ONLY | **SAME** |  |
| refreshYukDemoPresence | default | us-c1 | 1 | nodejs22 | v8 | 2026-10-31 07:20 | LrSYMKla | 68a0af2a |  | LIVE_NEWER | **MAINLINE_NEWER** |  |
| registerDeviceBinding | default | eu-w1 | 1 | nodejs20 | v6 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| rejectDriverRequest | default | us-c1 | 1 | nodejs20 | v36 | 2026-10-08 10:18 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| rejectPayout | default | us-c1 | 1 | nodejs20 | v48 | 2026-10-08 10:14 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| relayCashReconcile | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-14 16:37 | hXXYEK1Q | badd3ff0 | feat/ulg-s57-srv | LIVE_ONLY | **SAME** |  |
| relayEscrowReconcile | default | us-c1 | 1 | nodejs22 | v4 | 2026-11-14 21:11 | XPLwOvcA | d5ef369d | feat/relay-cash-loss-srv | LIVE_ONLY | **MAINLINE_NEWER** |  |
| releaseStaleReservations | default | us-c1 | 1 | nodejs20 | v17 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| removeRealtyTeamMember | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-06 06:39 | mqmy34rY | d2d45a96 | fix/bozor-live-port-d2d45a96 | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| renewMarketListing | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-15 11:41 | Yk366IL9 | 35b8dfd1В±1 |  | SAME | **SAME** |  |
| renewTvAd | default | us-c1 | 1 | nodejs20 | v9 | 2026-10-08 10:14 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| renewYukLocalListing | default | us-c1 | 1 | nodejs22 | v2 | 2026-10-31 10:29 | 8yn3VoIj | 478c4ca3 |  | LIVE_ONLY | **SAME** |  |
| repriceTaxiTrip | default | us-c1 | 1 | nodejs20 | v5 | 2026-10-08 16:17 | LkaWH9lb | e7a40724 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| requestDeliveryQuote | default | us-c1 | 1 | nodejs22 | v2 | 2026-11-16 17:23 | N5ESIkER | 03d85441 | feat/bozor-orders-srv | LIVE_ONLY | **MAINLINE_NEWER** |  |
| requestDeviceTransfer | default | eu-w1 | 1 | nodejs20 | v7 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| requestPayout | default | us-c1 | 1 | nodejs20 | v46 | 2026-10-08 16:17 | LkaWH9lb | e7a40724 |  | SAME | **SAME** |  |
| requestPendingCode | default | eu-w1 | 1 | nodejs20 | v6 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| requestWalletWithdraw | default | us-c1 | 1 | nodejs20 | v16 | 2026-10-08 16:17 | LkaWH9lb | e7a40724 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| rescheduleTaxiTrip | default | us-c1 | 1 | nodejs20 | v5 | 2026-10-16 12:28 | sp5QqC+w | aea0d8d8 |  | LIVE_NEWER | **MAINLINE_NEWER** |  |
| resetDailySoldStock | default | us-c1 | 1 | nodejs20 | v46 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| resetSoldStockNow | default | us-c1 | 1 | nodejs20 | v47 | 2026-10-08 10:18 | 5QRrk06u | ed0241af |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| resolveDeliveryFailed | default | us-c1 | 1 | nodejs22 | v3 | 2026-11-03 04:44 | jDSk+nf7 | a55d78b3 |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| resolveShopLink | default | us-c1 | 1 | nodejs20 | v4 | 2026-10-25 19:47 | SGinORMQ | 811a7c28 |  | LIVE_ONLY | **SAME** |  |
| respondDatingInterest | default | us-c1 | 1 | nodejs20 | v17 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| respondDeliveryQuote | default | us-c1 | 1 | nodejs22 | v2 | 2026-11-16 17:23 | N5ESIkER | 03d85441 | feat/bozor-orders-srv | LIVE_ONLY | **MAINLINE_NEWER** |  |
| respondDeviceTransfer | default | eu-w1 | 1 | nodejs20 | v7 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| respondRelativeInvite | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| respondSpouseInvite | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| respondSupermarketShortage | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| respondTreeLinkInvite | default | us-c1 | 1 | nodejs20 | v20 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| restaurantAcceptBooking | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-19 12:01 | IwjU2UoG | 11ab5913В±1 |  | SAME | **SAME** |  |
| restaurantAcceptOrder | default | us-c1 | 1 | nodejs22 | v5 | 2026-10-31 12:47 | Kel/Zoyq | 420ed0b2 | pin/courier-scopes | DIVERGED | **MAINLINE_NEWER** |  |
| restaurantAcceptReturn | default | us-c1 | 1 | nodejs22 | v1 | 2026-10-31 18:03 | gmPGVCnT | 2b69ff46 | feat/courier-failed-handover-srv | LIVE_ONLY | **MAINLINE_NEWER** |  |
| restaurantAddCuisine | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-19 08:39 | rVPLRpc/ | 30af7f73В±1 |  | SAME | **SAME** |  |
| restaurantCancelBooking | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-19 12:01 | IwjU2UoG | 11ab5913В±1 |  | SAME | **SAME** |  |
| restaurantConfirmPayment | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-09 01:24 | QmQAQ/Ce | dae5406e |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| restaurantCourierSharePendingSweep | default | us-c1 | 1 | nodejs22 | v1 | 2026-10-31 18:03 | gmPGVCnT | 2b69ff46 | feat/courier-failed-handover-srv | LIVE_ONLY | **MAINLINE_NEWER** |  |
| restaurantDemoCleanup | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-23 05:16 | EBbrkOvG | ad20823c |  | SAME | **SAME** |  |
| restaurantMarkDelivered | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-09 01:25 | QmQAQ/Ce | dae5406e |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| restaurantMarkReady | default | us-c1 | 1 | nodejs22 | v5 | 2026-10-31 12:47 | Kel/Zoyq | 420ed0b2 | pin/courier-scopes | DIVERGED | **MAINLINE_NEWER** |  |
| restaurantRegister | default | us-c1 | 1 | nodejs22 | v6 | 2026-10-31 06:57 | 6jbBLgYG | ac7f663e |  | DIVERGED | **MAINLINE_NEWER** |  |
| restaurantRejectBooking | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-19 12:01 | IwjU2UoG | 11ab5913В±1 |  | SAME | **SAME** |  |
| restaurantRejectOrder | default | us-c1 | 1 | nodejs20 | v3 | 2026-10-19 10:29 | Xmp2q+tb | 57fa6dc8В±1 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| restaurantResolveDeliveryFailed | default | us-c1 | 1 | nodejs22 | v3 | 2026-10-31 19:40 | +WdqkXKr | 718f2cb4 | feat/ulg-failed-srv | LIVE_ONLY | **MAINLINE_NEWER** |  |
| revokeDriverApproval | default | us-c1 | 1 | nodejs20 | v36 | 2026-10-08 10:18 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| saveDatingProfile | default | us-c1 | 1 | nodejs20 | v19 | 2026-10-08 10:14 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| saveTreeNode | default | us-c1 | 1 | nodejs20 | v19 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| seedMarshrutRoutePrice | default | us-c1 | 1 | nodejs20 | v17 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| sellerGetCustomerWalletBalance | default | us-c1 | 1 | nodejs20 | v13 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| sellerGetShiftSummary | default | us-c1 | 1 | nodejs20 | v13 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| sellerMarkPickupReady | default | us-c1 | 1 | nodejs20 | v13 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| sellerPlaceSale | default | us-c1 | 1 | nodejs20 | v16 | 2026-10-11 17:13 | YYE7C8no | 580f9523 | deploy/food-fns-guard | DIVERGED | **MAINLINE_NEWER*** | food kodi to'liq olib tashlangan; jonli FOOD_MODULE_REMOVED rad etish aynan saqlangan |
| sellerSubmitPickupPayment | default | us-c1 | 1 | nodejs20 | v15 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| sellerTgChannelConnect | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-25 19:47 | SGinORMQ | 811a7c28 |  | LIVE_ONLY | **SAME** |  |
| sellerTgChannelDisconnect | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-25 19:47 | SGinORMQ | 811a7c28 |  | LIVE_ONLY | **SAME** |  |
| sellerTgChannelPrepare | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-25 19:47 | SGinORMQ | 811a7c28 |  | LIVE_ONLY | **SAME** |  |
| sellerTgChannelStatus | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-25 19:46 | SGinORMQ | 811a7c28 |  | LIVE_ONLY | **SAME** |  |
| sendDailyOnboardingPromo | default | us-c1 | 1 | nodejs20 | v47 | 2026-10-16 19:39 | vqxRt5A9 | 6a124f51 |  | SAME | **SAME** |  |
| sendDatingInterest | default | us-c1 | 1 | nodejs20 | v17 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| sendDealMessage | default | us-c1 | 1 | nodejs22 | v3 | 2026-11-01 06:11 | U69sKH2c | 8092fef0 | feat/deal-chat-srv | LIVE_ONLY | **MAINLINE_NEWER** |  |
| sendSupportChatReply | default | us-c1 | 1 | nodejs20 | v45 | 2026-10-08 10:18 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| sendTreeLinkInvite | default | us-c1 | 1 | nodejs20 | v18 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| setDatingActive | default | us-c1 | 1 | nodejs20 | v17 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| setDatingAgePreference | default | us-c1 | 1 | nodejs20 | v16 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| setRealtyAlertStatus | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-15 04:07 | srfp4s4Y | 0add857eВ±1 |  | SAME | **SAME** |  |
| settlementDeferredWatch | default | us-c1 | 1 | nodejs20 | v17 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| setUserRoleByAdmin | default | us-c1 | 1 | nodejs20 | v41 | 2026-10-08 10:18 | 5QRrk06u | ed0241af |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| shopPage | default | us-c1 | 1 | nodejs20 | v5 | 2026-10-25 19:46 | SGinORMQ | 811a7c28 |  | LIVE_ONLY | **SAME** |  |
| shopStatsSeenCleanup | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-25 12:10 | ccWEKO8B | 5065dadd |  | LIVE_ONLY | **SAME** |  |
| smDailyStats | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| smGiftPiiSweep | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| smWeeklyReminder | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| submitContentComplaint | default | us-c1 | 1 | nodejs20 | v3 | 2026-10-25 18:32 | Kt9UXtPt | f32f3881 |  | LIVE_ONLY | **SAME** |  |
| submitDatingReport | default | us-c1 | 1 | nodejs20 | v15 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| submitDeferredSettlement | default | us-c1 | 1 | nodejs20 | v20 | 2026-10-08 16:17 | LkaWH9lb | e7a40724 |  | SAME | **SAME** |  |
| submitDishRatings | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-19 08:39 | rVPLRpc/ | 30af7f73В±1 |  | SAME | **SAME** |  |
| submitJobAd | default | us-c1 | 1 | nodejs22 | v20 | 2026-10-30 22:58 | 6suPcLRc | 00b0e0ae |  | LIVE_NEWER | **SAME** |  |
| submitJobComplaint | default | us-c1 | 1 | nodejs20 | v14 | 2026-10-18 16:25 | RgQj+ttm | e6d6e9c7 |  | SAME | **SAME** |  |
| submitMarketAd | default | us-c1 | 1 | nodejs22 | v21 | 2026-11-15 12:00 | NaTQQCEV | b97b7ab2 | fix/bozor-live-port-00b0e0ae | DIVERGED | **SAME** |  |
| submitMarketComplaint | default | us-c1 | 1 | nodejs20 | v13 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| submitRealtyListing | default | us-c1 | 1 | nodejs22 | v3 | 2026-11-19 20:58 | aesE3hsl | 97c81499 | fix/realty-fields-live-c8c5b324 | DIVERGED | **MAINLINE_NEWER** |  |
| submitSellSubmission | default | us-c1 | 1 | nodejs20 | v15 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| submitShopComplaint | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-25 07:34 | kqjEOTT2 | a07abc0f |  | LIVE_ONLY | **SAME** |  |
| sweepRestaurantCourierLive | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-19 10:29 | Xmp2q+tb | 57fa6dc8В±1 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| telegramWalletBotWebhook | default | us-c1 | 1 | nodejs20 | v21 | 2026-10-18 07:19 | pbkTiiWk | fd151de0 |  | SAME | **SAME** |  |
| transcodeEntertainmentVideo | default | us-c1 | 2 | nodejs20 | vtranscodeentertainmentvideo-00017-dep | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| undoTreeOperation | default | us-c1 | 1 | nodejs20 | v19 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| unlinkRealtyVideo | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-06 06:39 | mqmy34rY | d2d45a96 | fix/bozor-live-port-d2d45a96 | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| unlinkRelative | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| unlinkSpouse | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-26 19:50 | Bng9rMJr | 56eec578 | feat/holiday-basket-srv | SAME | **SAME** |  |
| unlockRealtyListing | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-06 06:39 | mqmy34rY | d2d45a96 | fix/bozor-live-port-d2d45a96 | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| updateDriverRating | default | us-c1 | 1 | nodejs20 | v25 | 2026-10-08 10:14 | 5QRrk06u | ed0241af |  | SAME | **SAME** |  |
| updateIntercityDriverRating | default | us-c1 | 1 | nodejs20 | v23 | 2026-10-16 12:28 | sp5QqC+w | aea0d8d8 |  | LIVE_NEWER | **SAME** |  |
| updateRealtyListing | default | us-c1 | 1 | nodejs22 | v3 | 2026-11-19 20:58 | aesE3hsl | 97c81499 | fix/realty-fields-live-c8c5b324 | DIVERGED | **MAINLINE_NEWER** |  |
| upsertMyBusiness | default | us-c1 | 1 | nodejs22 | v7 | 2026-11-01 00:34 | Lag2kwZz | 9f4b7594 | feat/biz-cat30-srv | LIVE_NEWER | **SAME** |  |
| verifyPendingCodeAndRegister | default | eu-w1 | 1 | nodejs20 | v6 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | SAME | **SAME** |  |
| walletToCash | default | us-c1 | 1 | nodejs20 | v13 | 2026-10-06 06:39 | VYoI7UqE | 1c461cce | feat/tv-clip-deep-link | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| walletTopUpExpirySweep | default | us-c1 | 1 | nodejs20 | v2 | 2026-10-18 05:43 | +gAA5cAc | ae8ba809 |  | SAME | **SAME** |  |
| wholesaleImportConfirm | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-19 20:44 | IBhLycaP | fd5db610 | deploy/rel-1120-srv | SAME | **SAME** |  |
| wholesaleImportPreview | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-19 20:44 | IBhLycaP | fd5db610 | deploy/rel-1120-srv | SAME | **SAME** |  |
| wholesaleImportTemplate | default | us-c1 | 1 | nodejs22 | v1 | 2026-11-19 20:44 | IBhLycaP | fd5db610 | deploy/rel-1120-srv | SAME | **SAME** |  |
| wholesaleLegacyCleanup | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-15 04:07 | srfp4s4Y | 0add857eВ±1 |  | SAME | **SAME** |  |
| wholesaleOrdersReconcile | default | us-c1 | 1 | nodejs22 | v12 | 2026-11-14 21:11 | XPLwOvcA | d5ef369d | feat/relay-cash-loss-srv | LIVE_ONLY | **MAINLINE_NEWER** |  |
| wholesaleProductGeoSync | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-11 09:43 | vSHhkRoA | 7a51b903 |  | SAME | **SAME** |  |
| wholesaleSellerGeoSync | default | us-c1 | 1 | nodejs20 | v1 | 2026-10-11 09:43 | vSHhkRoA | 7a51b903 |  | SAME | **SAME** |  |
| yukLocalDailyMaintenance | default | us-c1 | 1 | nodejs22 | v1 | 2026-10-31 07:20 | LrSYMKla | 68a0af2a |  | LIVE_ONLY | **MAINLINE_NEWER** |  |
| acceptLeg | demand | eu-w1 | 1 | nodejs22 | v10 | 2026-11-14 16:39 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | LIVE_NEWER | **MAINLINE_NEWER*** | jonli liniya vorisi 42fc64d7 (shu liniya keyingi deploylari) + mainline core/config, ids, policy |
| acceptOffer | demand | eu-w1 | 1 | nodejs22 | v11 | 2026-10-31 04:55 | cI7+3dck | 205c1b1cВ±2 |  | DIVERGED | **MAINLINE_NEWER*** | jonli (repoda yo'q edi) wholesale-LEG himoyasi aynan ko'chirilgan + muddat tekshiruvi (yangi) |
| acceptServiceAgreement | demand | eu-w1 | 1 | nodejs22 | v9 | 2026-10-08 10:14 | AOBok4b+ | 81d1cfd9 |  | SAME | **SAME** |  |
| acceptWholesaleOrder | demand | eu-w1 | 1 | nodejs22 | v4 | 2026-11-14 16:41 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | LIVE_ONLY | **SAME** |  |
| adminActivateLogisticsTariff | demand | eu-w1 | 1 | nodejs22 | v8 | 2026-11-07 11:10 | c2ECxMmi | 69bf7609 |  | DIVERGED | **SAME** |  |
| adminGetCoreOverview | demand | eu-w1 | 1 | nodejs22 | v1 | 2026-10-20 16:55 | DCmTD6X9 | 1117b6f9 |  | SAME | **MAINLINE_NEWER** |  |
| adminGetWholesaleFeeStatement | demand | eu-w1 | 1 | nodejs22 | v2 | 2026-11-14 11:15 | 4o5DXdZk | 8794aa08 | feat/ulg-s46-demand | LIVE_ONLY | **SAME** |  |
| adminGetWholesaleOrdersReport | demand | eu-w1 | 1 | nodejs22 | v2 | 2026-11-14 11:15 | 4o5DXdZk | 8794aa08 | feat/ulg-s46-demand | LIVE_ONLY | **SAME** |  |
| adminGetWholesaleOrdersStage | demand | eu-w1 | 1 | nodejs22 | v1 | 2026-10-31 00:12 | rSG+TE4W | 4f7153a0 | feat/ulg-admin-srv | LIVE_ONLY | **SAME** |  |
| adminGrantCapability | demand | eu-w1 | 1 | nodejs22 | v3 | 2026-10-08 10:14 | AOBok4b+ | 81d1cfd9 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminMarkShipmentLost | demand | eu-w1 | 1 | nodejs22 | v5 | 2026-11-14 21:13 | JZMn8vGI | 42fc64d7 | feat/relay-cash-loss-demand | LIVE_ONLY | **SAME** |  |
| adminMarkWholesaleFeeCollected | demand | eu-w1 | 1 | nodejs22 | v2 | 2026-11-14 11:15 | 4o5DXdZk | 8794aa08 | feat/ulg-s46-demand | LIVE_ONLY | **SAME** |  |
| adminMigrateTaxiDrivers | demand | eu-w1 | 1 | nodejs22 | v8 | 2026-10-08 02:52 | XVuTwIDX | 205c1b1cВ±1 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminPlanShipmentRoute | demand | eu-w1 | 1 | nodejs22 | v9 | 2026-11-07 11:10 | c2ECxMmi | 69bf7609 |  | DIVERGED | **MAINLINE_NEWER*** | jonli liniya vorisi 42fc64d7 (shu liniya keyingi deploylari) + mainline core/config, ids, policy |
| adminReactivateLeg | demand | eu-w1 | 1 | nodejs22 | v8 | 2026-11-07 11:10 | c2ECxMmi | 69bf7609 |  | DIVERGED | **MAINLINE_NEWER*** | jonli liniya vorisi 42fc64d7 (shu liniya keyingi deploylari) + mainline core/config, ids, policy |
| adminReopenChainLeg | demand | eu-w1 | 1 | nodejs22 | v2 | 2026-11-14 16:39 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | LIVE_ONLY | **MAINLINE_NEWER*** | jonli liniya vorisi 42fc64d7 (shu liniya keyingi deploylari) + mainline core/config, ids, policy |
| adminResolveWholesaleCardDispute | demand | eu-w1 | 1 | nodejs22 | v2 | 2026-11-14 11:15 | 4o5DXdZk | 8794aa08 | feat/ulg-s46-demand | LIVE_ONLY | **MAINLINE_NEWER*** | jonli liniya vorisi 42fc64d7 (shu liniya keyingi deploylari) + mainline core/config, ids, policy |
| adminSetCapabilityStatus | demand | eu-w1 | 1 | nodejs22 | v10 | 2026-10-08 10:15 | AOBok4b+ | 81d1cfd9 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminSetCoreConfig | demand | eu-w1 | 1 | nodejs22 | v1 | 2026-10-20 16:55 | DCmTD6X9 | 1117b6f9 |  | SAME | **MAINLINE_NEWER** |  |
| adminSetCourierApprovalMode | demand | eu-w1 | 1 | nodejs22 | v4 | 2026-10-08 10:15 | AOBok4b+ | 81d1cfd9 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminSetLogisticsStage | demand | eu-w1 | 1 | nodejs22 | v2 | 2026-11-07 11:10 | c2ECxMmi | 69bf7609 |  | LIVE_ONLY | **SAME** |  |
| adminSetWholesaleOrdersStage | demand | eu-w1 | 1 | nodejs22 | v1 | 2026-10-31 04:52 | rSG+TE4W | 4f7153a0 | feat/ulg-admin-srv | LIVE_ONLY | **SAME** |  |
| adminSetWholesaleProductMarket | demand | eu-w1 | 1 | nodejs22 | v2 | 2026-10-08 02:52 | XVuTwIDX | 205c1b1cВ±1 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| adminUpsertLogisticsTariff | demand | eu-w1 | 1 | nodejs22 | v8 | 2026-11-07 11:10 | c2ECxMmi | 69bf7609 |  | DIVERGED | **SAME** |  |
| aggregateDemandAnalytics | demand | eu-w1 | 1 | nodejs22 | v10 | 2026-10-08 02:52 | XVuTwIDX | 205c1b1cВ±1 |  | SAME | **SAME** |  |
| cancelAssignment | demand | eu-w1 | 1 | nodejs22 | v12 | 2026-11-14 16:39 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | LIVE_NEWER | **MAINLINE_NEWER*** | jonli liniya vorisi 42fc64d7 (shu liniya keyingi deploylari) + mainline core/config, ids, policy |
| cancelDemand | demand | eu-w1 | 1 | nodejs22 | v11 | 2026-10-31 04:55 | cI7+3dck | 205c1b1cВ±2 |  | DIVERGED | **MAINLINE_NEWER*** | jonli (repoda yo'q edi) wholesale-LEG himoyasi aynan ko'chirilgan + muddat tekshiruvi (yangi) |
| cancelLogisticsOrder | demand | eu-w1 | 1 | nodejs22 | v10 | 2026-11-14 16:39 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | LIVE_NEWER | **MAINLINE_NEWER*** | jonli liniya vorisi 42fc64d7 (shu liniya keyingi deploylari) + mainline core/config, ids, policy |
| cancelWholesaleOrder | demand | eu-w1 | 1 | nodejs22 | v7 | 2026-11-14 16:40 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | LIVE_ONLY | **SAME** |  |
| capabilitySweeper | demand | eu-w1 | 1 | nodejs22 | v11 | 2026-10-08 10:14 | AOBok4b+ | 81d1cfd9 |  | SAME | **SAME** |  |
| completeWholesaleSelfDelivery | demand | eu-w1 | 1 | nodejs22 | v1 | 2026-11-14 11:15 | 4o5DXdZk | 8794aa08 | feat/ulg-s46-demand | LIVE_ONLY | **SAME** |  |
| completeWholesaleSelfReturn | demand | eu-w1 | 1 | nodejs22 | v1 | 2026-11-14 11:15 | 4o5DXdZk | 8794aa08 | feat/ulg-s46-demand | LIVE_ONLY | **MAINLINE_NEWER*** | jonli liniya vorisi 42fc64d7 (shu liniya keyingi deploylari) + mainline core/config, ids, policy |
| confirmDelivery | demand | eu-w1 | 1 | nodejs22 | v9 | 2026-11-14 16:39 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | DIVERGED | **MAINLINE_NEWER*** | jonli liniya vorisi 42fc64d7 (shu liniya keyingi deploylari) + mainline core/config, ids, policy |
| confirmWholesaleBankPayment | demand | eu-w1 | 1 | nodejs22 | v3 | 2026-11-14 16:41 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | LIVE_ONLY | **SAME** |  |
| confirmWholesaleCardPayment | demand | eu-w1 | 1 | nodejs22 | v2 | 2026-11-14 11:15 | 4o5DXdZk | 8794aa08 | feat/ulg-s46-demand | LIVE_ONLY | **SAME** |  |
| createDemand | demand | eu-w1 | 1 | nodejs22 | v12 | 2026-10-20 15:58 | tWBKN3xs | 1b5a9dad |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| createLogisticsOrder | demand | eu-w1 | 1 | nodejs22 | v10 | 2026-11-14 16:39 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | DIVERGED | **MAINLINE_NEWER*** | jonli liniya vorisi 42fc64d7 (shu liniya keyingi deploylari) + mainline core/config, ids, policy |
| demandCoreStatus | demand | eu-w1 | 1 | nodejs22 | v10 | 2026-10-08 02:52 | XVuTwIDX | 205c1b1cВ±1 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| expireDemandsSweeper | demand | eu-w1 | 1 | nodejs22 | v11 | 2026-11-07 11:10 | c2ECxMmi | 69bf7609 |  | LIVE_NEWER | **SAME** |  |
| getLogisticsAccess | demand | eu-w1 | 1 | nodejs22 | v3 | 2026-11-07 11:10 | c2ECxMmi | 69bf7609 |  | DIVERGED | **MAINLINE_NEWER*** | jonli liniya vorisi 42fc64d7 (shu liniya keyingi deploylari) + mainline core/config, ids, policy |
| getShipmentSecrets | demand | eu-w1 | 1 | nodejs22 | v8 | 2026-11-14 16:39 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | LIVE_NEWER | **SAME** |  |
| getWholesaleCardPaymentInfo | demand | eu-w1 | 1 | nodejs22 | v3 | 2026-11-14 11:15 | 4o5DXdZk | 8794aa08 | feat/ulg-s46-demand | LIVE_ONLY | **SAME** |  |
| getWholesaleDeliveryCode | demand | eu-w1 | 1 | nodejs22 | v4 | 2026-11-14 16:41 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | LIVE_ONLY | **SAME** |  |
| getWholesaleDeliveryFailedState | demand | eu-w1 | 1 | nodejs22 | v5 | 2026-11-14 16:41 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | LIVE_ONLY | **SAME** |  |
| getWholesaleReturnHandoverCode | demand | eu-w1 | 1 | nodejs22 | v2 | 2026-11-14 11:15 | 4o5DXdZk | 8794aa08 | feat/ulg-s46-demand | LIVE_ONLY | **SAME** |  |
| legChainSweeper | demand | eu-w1 | 1 | nodejs22 | v6 | 2026-11-14 16:39 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | LIVE_ONLY | **MAINLINE_NEWER*** | jonli liniya vorisi 42fc64d7 (shu liniya keyingi deploylari) + mainline core/config, ids, policy |
| listWholesaleDeliveryFailedPending | demand | eu-w1 | 1 | nodejs22 | v3 | 2026-11-14 11:15 | 4o5DXdZk | 8794aa08 | feat/ulg-s46-demand | LIVE_ONLY | **SAME** |  |
| markWholesaleBuyerRefused | demand | eu-w1 | 1 | nodejs22 | v6 | 2026-11-14 16:41 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | LIVE_ONLY | **SAME** |  |
| markWholesaleSelfDeliveryRefused | demand | eu-w1 | 1 | nodejs22 | v1 | 2026-11-14 11:15 | 4o5DXdZk | 8794aa08 | feat/ulg-s46-demand | LIVE_ONLY | **MAINLINE_NEWER*** | jonli liniya vorisi 42fc64d7 (shu liniya keyingi deploylari) + mainline core/config, ids, policy |
| onProviderAvailable | demand | eu-w1 | 1 | nodejs22 | v13 | 2026-10-20 15:57 | tWBKN3xs | 1b5a9dad |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| onShipmentFunded | demand | eu-w1 | 1 | nodejs22 | v8 | 2026-11-14 16:39 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | DIVERGED | **MAINLINE_NEWER*** | jonli liniya vorisi 42fc64d7 (shu liniya keyingi deploylari) + mainline core/config, ids, policy |
| onWholesaleOrderCreated | demand | eu-w1 | 1 | nodejs22 | v5 | 2026-11-14 16:41 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | LIVE_ONLY | **SAME** |  |
| onWholesaleOrderUpdated | demand | eu-w1 | 1 | nodejs22 | v9 | 2026-11-14 16:41 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | LIVE_ONLY | **MAINLINE_NEWER*** | jonli liniya vorisi 42fc64d7 (shu liniya keyingi deploylari) + mainline core/config, ids, policy |
| presenceSweeper | demand | eu-w1 | 1 | nodejs22 | v10 | 2026-10-08 02:52 | XVuTwIDX | 205c1b1cВ±1 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| quoteLogisticsOrder | demand | eu-w1 | 1 | nodejs22 | v8 | 2026-11-07 11:10 | c2ECxMmi | 69bf7609 |  | DIVERGED | **MAINLINE_NEWER*** | jonli liniya vorisi 42fc64d7 (shu liniya keyingi deploylari) + mainline core/config, ids, policy |
| quoteWholesaleOrder | demand | eu-w1 | 1 | nodejs22 | v7 | 2026-11-14 16:42 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | LIVE_ONLY | **SAME** |  |
| recomputeTrust | demand | eu-w1 | 1 | nodejs22 | v11 | 2026-10-20 15:28 | a2O7KUnX | 22347cf5 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| rejectWholesaleOrder | demand | eu-w1 | 1 | nodejs22 | v3 | 2026-11-14 16:41 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | LIVE_ONLY | **SAME** |  |
| reopenStaleAssignments | demand | eu-w1 | 1 | nodejs22 | v10 | 2026-10-08 02:52 | XVuTwIDX | 205c1b1cВ±1 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| requestCapability | demand | eu-w1 | 1 | nodejs22 | v14 | 2026-10-30 22:59 | 7gOwT1Q7 | 00b0e0ae |  | LIVE_NEWER | **MAINLINE_NEWER** |  |
| resolveWholesaleDeliveryFailed | demand | eu-w1 | 1 | nodejs22 | v5 | 2026-11-14 16:41 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | LIVE_ONLY | **SAME** |  |
| respondWholesaleDeliveryFailed | demand | eu-w1 | 1 | nodejs22 | v5 | 2026-11-14 16:41 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | LIVE_ONLY | **SAME** |  |
| runDemandAnalytics | demand | eu-w1 | 1 | nodejs22 | v10 | 2026-10-08 02:52 | XVuTwIDX | 205c1b1cВ±1 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| scanHandover | demand | eu-w1 | 1 | nodejs22 | v10 | 2026-11-14 16:39 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | DIVERGED | **MAINLINE_NEWER*** | jonli liniya vorisi 42fc64d7 (shu liniya keyingi deploylari) + mainline core/config, ids, policy |
| setWholesaleOrderSettings | demand | eu-w1 | 1 | nodejs22 | v1 | 2026-10-30 22:33 | 5BUVPtJm | 0e62343b |  | LIVE_ONLY | **SAME** |  |
| setWholesaleSellerCard | demand | eu-w1 | 1 | nodejs22 | v2 | 2026-10-31 07:22 | dQ8Uvp1E | 2d75eeb2В±3 | feat/ulg-loss | LIVE_ONLY | **SAME** |  |
| setWholesaleStock | demand | eu-w1 | 1 | nodejs22 | v1 | 2026-10-30 21:58 | haoozsxt | 173b6d0d |  | LIVE_ONLY | **SAME** |  |
| startWholesaleSelfDelivery | demand | eu-w1 | 1 | nodejs22 | v1 | 2026-11-14 11:15 | 4o5DXdZk | 8794aa08 | feat/ulg-s46-demand | LIVE_ONLY | **MAINLINE_NEWER*** | jonli liniya vorisi 42fc64d7 (shu liniya keyingi deploylari) + mainline core/config, ids, policy |
| submitOffer | demand | eu-w1 | 1 | nodejs22 | v10 | 2026-10-08 02:52 | XVuTwIDX | 205c1b1cВ±1 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
| submitRating | demand | eu-w1 | 1 | nodejs22 | v10 | 2026-10-08 02:52 | XVuTwIDX | 205c1b1cВ±1 |  | SAME | **SAME** |  |
| submitWholesaleCardReceipt | demand | eu-w1 | 1 | nodejs22 | v2 | 2026-11-14 11:15 | 4o5DXdZk | 8794aa08 | feat/ulg-s46-demand | LIVE_ONLY | **SAME** |  |
| wholesaleBankPaymentSweeper | demand | eu-w1 | 1 | nodejs22 | v3 | 2026-11-14 16:41 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | LIVE_ONLY | **SAME** |  |
| wholesaleCardDisputeSweeper | demand | eu-w1 | 1 | nodejs22 | v2 | 2026-11-14 11:15 | 4o5DXdZk | 8794aa08 | feat/ulg-s46-demand | LIVE_ONLY | **MAINLINE_NEWER*** | jonli liniya vorisi 42fc64d7 (shu liniya keyingi deploylari) + mainline core/config, ids, policy |
| wholesaleDeliveryFailedSweeper | demand | eu-w1 | 1 | nodejs22 | v4 | 2026-11-14 11:15 | 4o5DXdZk | 8794aa08 | feat/ulg-s46-demand | LIVE_ONLY | **MAINLINE_NEWER*** | jonli liniya vorisi 42fc64d7 (shu liniya keyingi deploylari) + mainline core/config, ids, policy |
| wholesaleSellerDecisionSweeper | demand | eu-w1 | 1 | nodejs22 | v3 | 2026-11-14 16:41 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | LIVE_ONLY | **SAME** |  |
| wholesaleShipmentReconcile | demand | eu-w1 | 1 | nodejs22 | v6 | 2026-11-14 16:41 | BQHHDQph | 5001f513 | feat/ulg-s57-demand | LIVE_ONLY | **MAINLINE_NEWER*** | jonli liniya vorisi 42fc64d7 (shu liniya keyingi deploylari) + mainline core/config, ids, policy |
| withdrawOffer | demand | eu-w1 | 1 | nodejs22 | v10 | 2026-10-08 02:52 | XVuTwIDX | 205c1b1cВ±1 |  | MAINLINE_NEWER | **MAINLINE_NEWER** |  |
