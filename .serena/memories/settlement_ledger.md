# Settlement Ledger (double-entry money engine)
Design doc: `docs/settlement_ledger_v1_uz.md`. Code: `functions/settlement_ledger.js` + `functions/index.js` (CF section from `reconcileLedger` onward). Strangler pattern over legacy bonusBalance wallet.

## Data model (all CF-only writes)
- `journal_entries/{id}` append-only; Σdebit==Σcredit. Fields: ts(serverTs), kind, idempotencyKey, refType, refId, postedBy, postedRole, amount, legs[{account,dr,cr}], meta, status. id forms: `settle:{opId}`, `floatTopUp:{opId}`, `floatReturn:{opId}`, `bonus:{idempotencyKey}`.
- `ledger_accounts/{accountId}` materialized balance. accountId = type or `type:uid`. Types: `admin_cash`, `admin_clearing` (assets); `driver_float:{uid}`, `passenger_credit:{uid}`, `supplier_payable:{uid}` (liabilities).
- `settlements/{id}`, `period_closings/{YYYY-MM-DD}`, `ledger_exceptions/{id}` (fields: type, driverUid, balance, detectedAt, resolved).
- INVARIANT: `passenger_credit:{uid}.balance == users/{uid}.bonusBalance`.
- Only identified users (phone-verified Auth + `users/{uid}` doc) participate.

## Core helpers (settlement_ledger.js)
- `postEntry(db, entry, opts)` atomic idempotent post; opts: `assert / precheck / onCommit / accountExtras / mirrorBonus / walletLedgerType / meta`.
- Bonus mirror, two-phase (reads-before-writes): `prepareBonusInTx(tx,db,uid,{idempotencyKey,fundingAccount})` + `commitBonusInTx(tx,ctx,{delta,kind,...})`. `supplierPayableAccount(uid)` for V2 supplier credits.
- `commitBonusInBatch(batch,db,{...})` for `db.batch()` flows.
- `reconcile(db)` returns {balanced,totalDr,totalCr,identityOk,assets,liabilities,projectionOk,mismatches,accountCount,entryCount}. `getConfig`, `floatZone`, `settlementEnabled`, `deferredFloor`.

## Bonus flows wired to ledger (Qadam 5 — DONE)
creditChange, debitForOrder, confirmPayout (funding admin_cash), placeOrderWithWallet, grantBirthdayBonus, courierFinalizeCollection, courierSubmitPayment (batch). creditSupplier V2: funding `supplier_payable:{uid}`. spend => Dr passenger_credit / Cr funding; cashout/payout => funding admin_cash.

## Driver float / trip settlement / deferred
- CFs: floatTopUp, floatReturn, driverFloatStatus; openSettlement, confirmSettlement, cancelSettlement; submitDeferredSettlement (offline-lite: float may go negative within `deferredFloor`, sets `blocked`+`deferredTimeoutAt`); settlementDeferredWatch (scheduled, flags timeouts to `ledger_exceptions`).
- Settlement host doc: `trips/{id}` OR `intercity_bookings/{id}` (same tripId/opId).
- Dart: `lib/services/settlement_service.dart`, `lib/services/trip_change_settlement.dart` (retry + reason, no creditChange fallback), `lib/services/deferred_settlement_queue.dart`. Wired: local taxi `driver_home_controller`, marshrut driver, intercity driver (`settle_ic_{bookingId}`). Passenger confirm: local/marshrut trip doc; intercity `IntercitySettlementWatcher` on booking doc.

## Qadam 6 (Finance Center) — DONE + SoD
- RBAC: rules `isFinanceReader()` = **superadmin/finance/auditor only** (plain admin excluded). CF reconcileLedger/closePeriod same. Admin UI hides Finance Center unless `AdminAuthService.isFinanceReader`.
- Daily Closing: `closePeriod` CF (finance role, idempotent) writes `period_closings/{YYYY-MM-DD}`.
- UI `finance_center_screen.dart` 5 tabs + **CSV export** (journal, settlements). Nav filtered in `admin_shell.dart`.

## Payout KYC (V2 partial)
- `requestPayout` / `confirmPayout`: require `payoutKycVerified==true` OR (name + birthDate). Enforces anomaly withdrawal limits on request.

## CI E2E
- `functions/tools/settlement_e2e_test.js` runs spend + trip + deferred tests. `.github/workflows/settlement-ci.yml` (needs `FIREBASE_SERVICE_ACCOUNT_JSON` secret). npm: `test:settlement:e2e`.

## Remaining / future
finance/auditor role-grant UI (`setUserRoleByAdmin`), full supplier_payable spend routing, PDF export.
