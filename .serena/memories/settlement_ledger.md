# Settlement Ledger (double-entry money engine)
Design doc: `docs/settlement_ledger_v1_uz.md`. Code: `functions/settlement_ledger.js` + `functions/index.js` (CF section from `reconcileLedger` onward). Strangler pattern over legacy bonusBalance wallet.

## Data model (all CF-only writes)
- `journal_entries/{id}` append-only; Σdebit==Σcredit. Fields: ts(serverTs), kind, idempotencyKey, refType, refId, postedBy, postedRole, amount, legs[{account,dr,cr}], meta, status. id forms: `settle:{opId}`, `floatTopUp:{opId}`, `floatReturn:{opId}`, `bonus:{idempotencyKey}`, `courierCash:{orderId}`, `courierInkassa:{opId}`.
- `ledger_accounts/{accountId}` materialized balance. accountId = type or `type:uid`. Types: `admin_cash`, `admin_clearing`, **`courier_cash:{phone12}`** (assets); `driver_float:{uid}`, `passenger_credit:{uid}`, `supplier_payable:{uid}` (liabilities).
- `settlements/{id}`, `period_closings/{YYYY-MM-DD}`, `ledger_exceptions/{id}` (fields: type, driverUid, balance, detectedAt, resolved).
- INVARIANT: `passenger_credit:{uid}.balance == users/{uid}.bonusBalance`.
- Only identified users (phone-verified Auth + `users/{uid}` doc) participate.

## Courier field cash (2026-07)
- `courierSubmitPayment` cash+card → post `kind:courier_field_cash` Dr `courier_cash:{canonicalUid}` / Cr `admin_clearing` (after order batch).
- `receiveCourierCash` (finance/superadmin) → `kind:courier_inkassa` Dr `admin_cash` / Cr `courier_cash` (assert balance >= amount).
- `getMoneyControlSnapshot` — Finance Center «Назорат» KPI + queues + today-by-kind.
- `reconcile` also returns adminCash, courierCashSum, driverFloatSum, passengerCreditSum, courierCashAccounts.

## Core helpers (settlement_ledger.js)
- `postEntry`, `courierCashAccount(phone)`, `moneyControlSnapshot(db)`.
- Bonus mirror: prepareBonusInTx / commitBonusInTx / commitBonusInBatch.
- `reconcile(db)` + position breakdowns. `getConfig`, `floatZone`, `settlementEnabled`, `deferredFloor`.

## Bonus flows wired to ledger (Qadam 5 — DONE)
creditChange, debitForOrder, confirmPayout (funding admin_cash), placeOrderWithWallet, grantBirthdayBonus, courierFinalizeCollection, courierSubmitPayment (batch + field cash). creditSupplier V2: funding `supplier_payable:{uid}`.

## Driver float / trip settlement / deferred
- CFs: floatTopUp, floatReturn, driverFloatStatus; openSettlement, confirmSettlement, cancelSettlement; submitDeferredSettlement; settlementDeferredWatch.
- Dart: settlement_service, trip_change_settlement, deferred_settlement_queue.

## Finance Center (Qadam 6 + Money Control)
- RBAC: `isFinanceReader()` = superadmin/finance/auditor. UI: `finance_center_screen.dart` tabs: **Назорат** (`money_control_tab.dart`), Float, Settlements, Journal, Closing, Exceptions. Phone-first &lt;700px.
- CFs: reconcileLedger, closePeriod, getMoneyControlSnapshot, receiveCourierCash.

## Payout KYC (V2 partial)
- requestPayout / confirmPayout / rejectPayout. Nazorat tab can confirm/reject pending.

## CI E2E
- `functions/tools/settlement_e2e_test.js`; workflow settlement-ci.yml.

## Remaining / future
full supplier_payable spend routing, PDF export, historical backfill of courier_cash for past orders.
