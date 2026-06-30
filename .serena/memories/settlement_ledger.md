# Settlement Ledger (double-entry money engine)
Design doc: `docs/settlement_ledger_v1_uz.md`. Code: `functions/settlement_ledger.js` + `functions/index.js` (CF section from `reconcileLedger` onward). Strangler pattern over legacy bonusBalance wallet.

## Data model (all CF-only writes)
- `journal_entries/{id}` append-only; Σdebit==Σcredit. Fields: ts(serverTs), kind, idempotencyKey, refType, refId, postedBy, postedRole, amount, legs[{account,dr,cr}], meta, status. id forms: `settle:{opId}`, `floatTopUp:{opId}`, `floatReturn:{opId}`, `bonus:{idempotencyKey}`.
- `ledger_accounts/{accountId}` materialized balance. accountId = type or `type:uid`. Types: `admin_cash`, `admin_clearing` (assets); `driver_float:{uid}`, `passenger_credit:{uid}` (liabilities).
- `settlements/{id}`, `period_closings/{YYYY-MM-DD}`, `ledger_exceptions/{id}` (fields: type, driverUid, balance, detectedAt, resolved).
- INVARIANT: `passenger_credit:{uid}.balance == users/{uid}.bonusBalance`.
- Only identified users (phone-verified Auth + `users/{uid}` doc) participate.

## Core helpers (settlement_ledger.js)
- `postEntry(db, entry, opts)` atomic idempotent post; opts: `assert / precheck / onCommit / accountExtras / mirrorBonus / walletLedgerType / meta`.
- Bonus mirror, two-phase (reads-before-writes): `prepareBonusInTx(tx,db,uid,{idempotencyKey,fundingAccount})` + `commitBonusInTx(tx,ctx,{delta,kind,...})`.
- `commitBonusInBatch(batch,db,{...})` for `db.batch()` flows.
- `reconcile(db)` returns {balanced,totalDr,totalCr,identityOk,assets,liabilities,projectionOk,mismatches,accountCount,entryCount}. `getConfig`, `floatZone`, `settlementEnabled`, `deferredFloor`.

## Bonus flows wired to ledger (Qadam 5 — DONE)
creditChange, creditSupplier, debitForOrder, confirmPayout (funding admin_cash), placeOrderWithWallet, grantBirthdayBonus, courierSubmitCourierOrderPayment, courierFinalizeCollection, courierSubmitPayment (batch). credit => Dr admin_clearing / Cr passenger_credit; spend => reverse; cashout/payout => funding admin_cash.

## Driver float / trip settlement / deferred
- CFs: floatTopUp, floatReturn, driverFloatStatus; openSettlement, confirmSettlement, cancelSettlement; submitDeferredSettlement (offline-lite: float may go negative within `deferredFloor`, sets `blocked`+`deferredTimeoutAt`); settlementDeferredWatch (scheduled, flags timeouts to `ledger_exceptions`).
- Dart: `lib/services/settlement_service.dart`, `lib/services/deferred_settlement_queue.dart` (SharedPreferences offline queue; flush on app start + connectivity return in `driver_home_controller.dart`).

## Qadam 6 (Finance Center) — DONE
- RBAC: rules `isFinanceReader()` = admin/superadmin/finance/auditor; ledger collections CF-only; V1 admin sees Finance Center. NOTE: `setUserRoleByAdmin` still only grants user/admin — finance/auditor must be set via direct `users/{uid}.role` edit for now.
- Daily Closing: `closePeriod` CF (finance role, idempotent) writes `period_closings/{YYYY-MM-DD}` = period turnover (periodDr/Cr, kinds, entryCount) + global reconcile snapshot, `locked:true`. Journal stays immutable; lock is audit/report only.
- UI `lib/features/admin_web/screens/finance_center_screen.dart` 5 tabs: Driver Float, Settlements, Audit journal (shows ts/postedBy/postedRole/refType), Davr qulfi (closePeriod + history), Istisnolar (ledger_exceptions). Nav in `admin_shell.dart`.

## Remaining / future (V2)
Strict SoD (hide Finance Center from plain admin), finance/auditor role-grant UI, payout/KYC + limits, supplier_payable, accounting report export (CSV/PDF).