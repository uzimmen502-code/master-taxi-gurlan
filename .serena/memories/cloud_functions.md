# Cloud Functions Catalog (`functions/index.js`, ~119 exports)

Grep exact name with `^exports\.NAME` to jump to a function (no line numbers — they drift).
Types: onCall = `functions.https.onCall`; trigger = `functions.firestore`; sched = `functions.pubsub.schedule`; http = `onRequest`; storage = `onObjectFinalized`.
Region `us-central1`, Node 20 1st Gen. Helpers from `settlement_ledger.js` imported as `settlementLedger`.
Central RBAC: `requireCallerRoles(context,[roles],msg)`. Idempotency: `wallet_idempotency/{key}` + client `opId`.
Geo report denormalizatsiya: helper `geoReportStamp(userData)` → {regionId,districtId,serviceAreaId} (faqat boʻsh emas) user hujjatidan olib order payload'ga bosiladi. Ishlatilgan: placeOrderPostPaid, placeCarpetWashOrder, placeAgroPickupOrder (placeOrderWithWallet deprecated). (Client-side trips/courier/intercity Flutter `ServiceConfigHolder.reportStamp()` bilan bosadi.)

## Wallet / Finance (onCall)
- creditChange — wallet credit/refund (change, bonuses); idemKey e.g. `change_trip_{id}`.
- creditSupplier — credit a supplier account.
- debitForOrder — legacy wallet debit for order.
- placeOrderWithWallet — **deprecated** (throws failed-precondition); use placeOrderPostPaid only.
- placeOrderPostPaid — bread/food/platform; **food←food_catalog**, **bread←bread_products+extra_products+settings/prices**, **platform←platform_products** (kind platform → soldToday on product doc); wallet debit; cashDue=total-balanceApplied. Bread items require `firestoreId`.
- customerCancelOrder — owner cancel early order; restore soldToday + wallet refund.
- sellerPlaceSale / sellerGetCustomerWalletBalance / sellerGetShiftSummary — seller POS (role seller|admin|superadmin); cash/wallet/mixed; `fulfillmentMode:pos`; shift = today Tashkent `paidBySellerId`+`paidAt`.
- sellerMarkPickupReady / sellerSubmitPickupPayment — pickup order ready + in-store pay.
- requestPayout / confirmPayout / rejectPayout — cash-out lifecycle (`payout_requests`).
- checkWithdrawalLimit — payout limit guard.
- grantBirthdayBonus — yearly birthday bonus (`users/{uid}/birthday_bonus_claims/{year}`).
- claimCarProfileBonus — one-time bonus when profile car complete; `users/{uid}/car_profile_bonus_claims/v1`; amount `settings/oil_change.carProfileBonusAmount` (default 5000).
- adminUpsertOilCatalogItem / adminDeleteOilCatalogItem / adminSeedOilCatalog — oil catalog CRUD (admin|finance); Storage images client-side.

## Settlement Ledger / Finance Center (onCall + sched)
- reconcileLedger — recompute/verify ledger balances (+ position breakdowns).
- getMoneyControlSnapshot — Nazorat KPI + queues + today journal-by-kind.
- receiveCourierCash — inkassa: Dr admin_cash / Cr courier_cash (finance).
- cashExchange / walletToCash — Cash In→Wallet / Wallet→Cash (finance); floatTopUp/floatReturn deprecated.
- migrateFloatToWallet — one-shot driver_float → passenger_credit.
- Telegram Wallet Bot (`functions/telegram_wallet_bot.js`): `telegramWalletBotWebhook` (http); `createTelegramLinkCode`; `requestWalletWithdraw` (app own-wallet cash-out); `adminGetWalletBotSettings` / `adminSetWalletBotSettings`; `adminReviewWalletTopUp` (→cashExchange); `adminReviewWalletWithdraw` (→walletToCash); `getWalletTopUpReceiptUrl`. Config `telegram.wallet_token|username|secret`. Doc: `docs/telegram_wallet_bot_architecture.md`.
- closePeriod — daily closing lock+snapshot (`period_closings/{YYYY-MM-DD}`).
- driverFloatStatus — legacy read (float accounts).
- openSettlement / confirmSettlement / cancelSettlement — trip change via driver wallet → passenger wallet.
- submitDeferredSettlement — wallet-based; no negative.
- settlementDeferredWatch (sched) — legacy negative float timeouts.
- courierSubmitPayment — also posts `courier_field_cash` for cash+card lines.

## Orders / Food / Stock
- onOrderCreate (trigger) / onOrderUpdate (trigger) — order side effects; pickup → FCM sellers (`seller_pickup` / `seller_pos`).
- adminSetOrderStatus / adminSetOrderStatusBatch (onCall) — admin order status.
- resetDailySoldStock (sched) / resetSoldStockNow (onCall) — reset daily sold counters.
- seedFoodCatalog (http) — seed food menu.

## Courier / Delivery / Collection
- courierCreateRoute / courierRecoverOrphanRoute — build/recover delivery route.
- courierMarkPicked / courierMarkArrived — bread/food `orders` delivery; arrived → `notifyCourierArrivedToCustomer` (ring push `courier_arrived`).
- courierMarkCollectionArrived — collection_tasks arrived + ring; finalize requires `arrivedAt`.
- courierGetCustomerWalletBalance — courier reads customer wallet (for payment).
- courierSubmitPayment — order payment (cash/card/wallet/product lines) + ledger `courier_field_cash`.
- onDeliveryRouteCreate / onDeliveryRouteAssign (triggers) — route side effects.
- adminCreateCollectionTask / courierFinalizeCollection / adminGetWarehouseStock — sell-collection + `warehouse_stock`.

## Carpet wash
- placeCarpetWashOrder — customer creates `carpet_wash_orders` doc (carpetCount, pickupAddress, note); **idempotencyKey** → `wallet_idempotency/carpet_{key}`.
- adminSetCarpetWashStatus — admin status + optional finalPrice.
- courierClaimCarpetPickup / courierMarkCarpetArrived (leg pickup|return) / courierMarkCarpetPickedUp — pickup flow; picked_up requires `pickupArrivedAt`.
- courierClaimCarpetReturn / courierMarkCarpetDelivered — return flow; completed requires `returnArrivedAt`.

## Taxi (local + marshrut)
- completeLocalTrip (onCall) — driver completes local/alone trip: debit passenger wallet per `passengerWalletIntent` (idem `local_trip_complete_{tripId}`), set `completed`+`walletPaid`; returns `{fare,cashPaid,walletPaid,cashDue,change}`.
- onMarshrutTripCreate (trigger) / onTripUpdate (trigger) — trip dispatch/side effects.
- expirePendingTrips (sched) / releaseStaleReservations (sched) — cleanup stale trips/holds; closes expired `yuk_listings` (active→closed) + FCM via `notifications` (`yuk_listing_closed`); T−6h warn (`yuk_listing_expire_soon`, flag `expireSoonNotified`); jobs `ads` active|pending → `completed`; cheap_product expired → `inactive`.
- submitJobAd / submitJobComplaint (onCall) — Иш топ CF-only create (auth+canonical phone; ad daily 10; complaint daily 20).
- submitMarketAd / submitMarketComplaint (onCall) — Onlayn BOZOR CF-only create + reports type market_ad (ads daily/pending/active <=5000; complaints daily 20; phone=token; images under ads/{uid}/; submit/adminUpdate write `searchTokens`).
- migrateCheapProductTitleLower (onCall admin) — backfill `titleLower` + empty `searchTokens` on cheap_product.
- cleanupStaleDrivers (sched) — offline stale drivers.
- marshrutDriverAutoOffline (sched) — auto-offline marshrut drivers.
- marshrutPassengerCancelAfterAccept — passenger cancel after accept (block logic).
- seedMarshrutRoutePrice — first driver sets flat route price (`marshrut_route_prices/{from|to}`, then locked).
- adminSetMarshrutRoutePrice — admin edits route price (roles incl finance).
- updateDriverRating / updateIntercityDriverRating — driver ratings.

## Intercity
- onIntercityDriverUpdate / onIntercityBookingCreated / onIntercityBookingUpdated / onIntercityBookingCancelled / onIntercityPickupUpdated (triggers) — intercity booking side effects.
- autoUpdateDepartureTime — roll intercity departure to next slot.

## Auth / Device Binding / Phone
- checkDeviceBinding / registerDeviceBinding — device fingerprint binding (`device_bindings`).
- requestPendingCode / getPendingCodeStatus / verifyPendingCodeAndRegister — admin-code phone verify flow (`pending_codes`).
- autoApprovePendingCode / autoApprovePendingCodeOnUpdate (triggers) — auto-approve codes.
- changeDevicePhone — change phone bound to device.
- migrateOldBindings / migrateCheapProductTitleLower / migratePhoneFormats — one-off migrations (onCall).
- adminSetDeviceBindingAutoApprove / adminAutoApproveDeviceBinding / adminManualApproveDeviceBinding / adminUnblockDeviceBinding / adminRejectDeviceBinding — admin device binding mgmt.

## Admin / Roles / Driver apps
- adminWebSignIn / adminWebSignInWithCode — admin web login (custom token; trusted phone `998912778777` / PIN code).
- setUserRoleByAdmin — assign role (allowed: user/admin/finance/auditor).
- promoteToAdminWithPin / bootstrapAdminUser — bootstrap admin.
- autoApproveDriverApplication / approveDriverRequest / rejectDriverRequest / revokeDriverApproval — driver application lifecycle (`driver_requests`,`drivers`).
- leaveDriverRole / adminResetTaxiDriversRegistry — driver role exit / registry reset.

## Chat / News / Notifications
- onSupportChatMessageCreate (trigger) — support chat push.
- sendSupportChatReply / appendAdminSystemChat — admin chat replies.
- onAdminNewsCreate / onAdminNewsUpdate (triggers) — broadcast news fan-out.
- onNotificationCreate (trigger) — FCM send from `notifications` queue.
- sendDailyOnboardingPromo (sched) — onboarding promo push.

## Reports / Misc
- dailyReport20 (sched) / generateDailyReportNow (onCall) — daily report (`daily_reports`).
- detectAnomaly (trigger) — risk/anomaly signals (`risk_events`).
- getDirections (http) — Google Directions proxy.
- onAdUpdate (trigger) — Jobs=`authorPhone`→jobs; cheap_product=`ownerId`→my_ads (`market_ad_*`). onSellSubmissionUpdate / onBirthDateRequestUpdate / onDeviceChangeRequestUpdate — other side effects.
- **adminUpdateSellSubmission** — admin status/forward `sell_submissions` (rules client update false).

## Dating (Tanishuv)
- saveDatingProfile — create/edit profile → `pending` yoki `settings/app.datingAutoApprove` bo'lsa darhol `approved`. CF-only write to `dating_profiles`.
- deleteDatingProfile — owner deletes profile, Storage `dating/{uid}/`, interests, matches(+messages), blocks.
- setDatingAgePreference — user sets prefMinAge/prefMaxAge (18–80) on `dating_profiles`.
- adminSetDatingAutoApprove — admin toggle `datingAutoApprove` in `settings/app`.
- adminSetMarketAutoApprove — toggle `marketAutoApprove` in `settings/app`; submitMarketAd + onAdUpdate(pending) auto→active when on.
- adminSetPlatformFeaturedAuto — toggle `platformFeaturedAuto` in `settings/app` (Тавсия этамиз витрина АВТО/ҚЎЛДА).
- setDatingActive — toggle visibility (active) + lastActive.
- adminModerateDatingProfile — approve/reject/block.
- sendDatingInterest — like; mutual → auto-create `dating_matches`.
- respondDatingInterest — accept/decline interest → match on accept.
- **submitDatingReport** — client shikoyat → `reports` (type=dating_profile); rules client create blok.
- **adminResolveDatingReport** — admin report `resolved`.

## Family Tree (Nasab daraxti — global graph)
- ensureMyTree — idempotent: create caller's `treeComponentId`+`treePersonId` (self node); auto `relatives/people/{treePersonId}` «Мен» from profile (`isSelf:true`); backfills phone watchers + registered-relative notify; tree backfill only fills empty tree fields (no clobber).
- addRelativePerson — server create `relatives/people/{id}` (single id); mirror via `onRelativePersonWrite`; resolves redirect on link fields.
- deleteRelativePerson — owner deletes `relatives/people/{id}` (+ album photos, tree cleanup, unlinks parent/spouse refs); client list delete uses this CF; rules block direct client delete.
- onRelativePersonWrite — mirror relatives→tree_persons (redirect-aware); delete branch clears tree when unclaimed.
- sendTreeLinkInvite / respondTreeLinkInvite — two-sided node link → component+node merge, `tree_redirects`, `tree_history` (type=link); accept rewrites component `relatives` refs, removes inviter placeholder row; stores `relativeRefChanges` + victim snapshot for undo; push via notifyUserInApp (`tree_link_invite`).
- mergeTreePersons — dedup two nodes in a component (`tree_history` type=merge); rewrites component `relatives` refs (returns changes for undo); deletes merged private row; stores `relativeRefChanges` + victim snapshot in history.
- onRelativePersonWrite (trigger) — mirror `relatives/{uid}/people/{pid}` → `tree_persons` (redirect-aware); sync phone watcher index + notify owner if phone already registered.
- onUserProfileReady (trigger `users/{uid}`) — first profile complete (`name`) → notify phone watchers (owner A) + new user B (`relative_waiting`).
- saveTreeNode — **create** writes only `relatives/people` (mirror to tree); **edit** updates `tree_persons` + owner mirror; resolves redirects on link fields; history type=create/edit.
- undoTreeOperation — reverse link/merge/edit/create from `tree_history`; link/merge undo restores `relatives/people` via `restoreRelativePersonDoc` + `undoRelativeRefChanges`.

## Agro pickup (sut qabul)
- placeAgroPickupOrder — customer `agro_pickup_orders` (milk literCount 1..500); **idempotencyKey** → `wallet_idempotency/agro_{key}`.
- adminSetAgroPickupStatus — admin status + optional finalPrice.
- courierClaimAgroPickup / courierMarkAgroPickupArrived / courierMarkAgroPickedUp — courier claim + ring on arrived.

## Entertainment
- transcodeEntertainmentVideo (storage, onObjectFinalized) — transcode uploaded mp4 to 720p; NOT called from Flutter.
