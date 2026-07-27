# Settlement Ledger (double-entry money engine)
Design: `docs/settlement_ledger_v1_uz.md`. Code: `functions/settlement_ledger.js` + `functions/index.js`.

## Accounts
- Assets: `admin_cash`, `admin_clearing`, `courier_cash:{phone12}`
- Liabilities: `passenger_credit:{uid}` (= `bonusBalance`), `supplier_payable` (V2)
- **`driver_float` DEPRECATED** — migrate via `migrateFloatToWallet`; new money via Cash Exchange only.
- No negative wallet (assert next >= 0 on spends/settlements).

## Cash Exchange (2026-07)
- `cashExchange` (finance): `cash_in` then `cash_to_wallet` (clearing staging). UI: Finance Center → Cash Exchange. Also used by Telegram bot admin approve (`adminReviewWalletTopUp`, opId `topup_{id}`).
- `walletToCash`: Dr passenger_credit / Cr admin_cash.
- `floatTopUp` / `floatReturn` throw failed-precondition → use cashExchange / walletToCash.
- Trip settlement: Dr `passenger_credit:driver` / Cr `passenger_credit:passenger` (openSettlement checks driver bonusBalance).
- Deferred: same wallet path; negative deferred forbidden.

## Withdraw (app)
- `requestWalletWithdraw` (app) + Telegram `/withdraw` → `wallet_withdraw_requests`; admin `adminReviewWalletWithdraw` → `walletToCash`.
- Withdraw auto: `settings/wallet_bot.withdrawApproveMode` (manual|auto) + `withdrawAutoLimit` ∈ {20000,50000,100000}; ≤limit → auto `walletToCash` (balance−); card payout still manual.
- Wallet P2P deleted; historical `wallet_p2p_*` ledger labels kept.

## Order wallet opt-in (2026-07)
- `placeOrderPostPaid`: wallet debit **only** if `orderBase.useWallet === true`; `balanceApplied` defaults to **0** (not max). Silent max debit removed.
- Client: bread/food/platform `useWallet=false` + `OrderCheckoutWalletBanner` switch; new commerce modules must reuse this banner + CF gate.
- Courier/Seller POS still use explicit `walletPaid` (operator-entered).

## Exact accounting (majburiy, 2026-07)
- Pul/summa haqida **faqat aniq** raqam: taxminan/approximate/~ YO‘Q.
- UI aggregatlar: status bo‘yicha aniq filter (masalan top-up `awaiting_review` vs `credited`); `awaiting_transfer` (pul o‘tmagan) jami/pending ga **qo‘shilmaydi**.
- Balans manbai: ledger/`bonusBalance` — taxminiy yig‘indi bilan aralashtirilmasin.
- Javoblarda summa aytilsa Firestore/ledger dan verify qilingan aniq qiymat bo‘lsin.

## Other
- `getMoneyControlSnapshot`, `receiveCourierCash`, `courier_field_cash` on courierSubmitPayment.
- `reconcile` returns position breakdowns.
- Finance Center tabs: Назорат, Cash Exchange, Settlements, Journal, Closing, Exceptions.
