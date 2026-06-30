# Cloud Functions Catalog (`functions/index.js`, 111 exports)

Grep exact name with `^exports\.NAME` to jump to a function (no line numbers — they drift).
Types: onCall = `functions.https.onCall`; trigger = `functions.firestore`; sched = `functions.pubsub.schedule`; http = `onRequest`; storage = `onObjectFinalized`.
Region `us-central1`, Node 20 1st Gen. Helpers from `settlement_ledger.js` imported as `settlementLedger`.
Central RBAC: `requireCallerRoles(context,[roles],msg)`. Idempotency: `wallet_idempotency/{key}` + client `opId`.

## Wallet / Finance (onCall)
- creditChange — wallet credit/refund (change, bonuses); idemKey e.g. `change_trip_{id}`.
- creditSupplier — credit a supplier account.
- debitForOrder — legacy wallet debit for order.
- placeOrderWithWallet — legacy pre-paid order (wallet).
- placeOrderPostPaid — CURRENT order placement (bread/food), post-paid; takes orderBase+decrements+idempotencyKey.
- requestPayout / confirmPayout / rejectPayout — cash-out lifecycle (`payout_requests`).
- checkWithdrawalLimit — payout limit guard.
- grantBirthdayBonus — yearly birthday bonus (`users/{uid}/birthday_bonus_claims/{year}`).

## Settlement Ledger / Finance Center (onCall + sched)
- reconcileLedger — recompute/verify ledger balances.
- closePeriod — daily closing lock+snapshot (`period_closings/{YYYY-MM-DD}`).
- floatTopUp / floatReturn / driverFloatStatus — driver float (cash advance) mgmt.
- openSettlement / confirmSettlement / cancelSettlement — trip change-settlement state machine (`settlements`).
- submitDeferredSettlement — offline-lite deferred settlement submit.
- settlementDeferredWatch (sched) — process `ledger_exceptions` (negative float / deferred).

## Orders / Food / Stock
- onOrderCreate (trigger) / onOrderUpdate (trigger) — order side effects (notifications, status).
- adminSetOrderStatus / adminSetOrderStatusBatch (onCall) — admin order status.
- resetDailySoldStock (sched) / resetSoldStockNow (onCall) — reset daily sold counters.
- seedFoodCatalog (http) — seed food menu.

## Courier / Delivery / Collection
- courierCreateRoute / courierRecoverOrphanRoute — build/recover delivery route.
- courierMarkPicked / courierMarkArrived — delivery step transitions.
- courierGetCustomerWalletBalance — courier reads customer wallet (for payment).
- courierSubmitPayment — order payment (cash/card/wallet/product lines).
- courierSubmitCourierOrderPayment — payment for direct `courier_orders`.
- onDeliveryRouteCreate / onDeliveryRouteAssign (triggers) — route side effects.
- adminCreateCollectionTask / courierFinalizeCollection / adminGetWarehouseStock — sell-collection + `warehouse_stock`.

## Taxi (local + marshrut)
- onMarshrutTripCreate (trigger) / onTripUpdate (trigger) — trip dispatch/side effects.
- expirePendingTrips (sched) / releaseStaleReservations (sched) — cleanup stale trips/holds.
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
- onAdUpdate / onSellSubmissionUpdate / onBirthDateRequestUpdate / onDeviceChangeRequestUpdate (triggers) — moderation/request side effects.

## Dating (Tanishuv)
- saveDatingProfile — create/edit profile → status `pending` (sets lastActive). CF-only write to `dating_profiles`.
- setDatingActive — toggle visibility (active) + lastActive.
- adminModerateDatingProfile — approve/reject/block.
- sendDatingInterest — like; mutual → auto-create `dating_matches`.
- respondDatingInterest — accept/decline interest → match on accept.

## Family Tree (Nasab daraxti — global graph)
- ensureMyTree — idempotent: create caller's `treeComponentId`+`treePersonId` (self node).
- onRelativePersonWrite (trigger) — mirror `relatives/{uid}/people/{pid}` → `tree_persons` (redirect-aware).
- sendTreeLinkInvite / respondTreeLinkInvite — two-sided node link → component+node merge, `tree_redirects`, `tree_history` (type=link).
- mergeTreePersons — dedup two nodes in a component (`tree_history` type=merge).
- saveTreeNode — create/edit any component node; mirrors to owner `relatives/people` (no clobber); history type=create/edit.
- undoTreeOperation — reverse link/merge/edit/create from `tree_history`.

## Entertainment
- transcodeEntertainmentVideo (storage, onObjectFinalized) — transcode uploaded mp4 to 720p; NOT called from Flutter.
