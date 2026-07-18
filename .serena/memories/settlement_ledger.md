# Settlement Ledger (double-entry money engine)
Design: `docs/settlement_ledger_v1_uz.md`. Code: `functions/settlement_ledger.js` + `functions/index.js`.

## Accounts
- Assets: `admin_cash`, `admin_clearing`, `courier_cash:{phone12}`
- Liabilities: `passenger_credit:{uid}` (= `bonusBalance`), `supplier_payable` (V2)
- **`driver_float` DEPRECATED** — migrate via `migrateFloatToWallet`; new money via Cash Exchange only.
- No negative wallet (assert next >= 0 on spends/settlements).

## Cash Exchange (2026-07)
- `cashExchange` (finance): `cash_in` then `cash_to_wallet` (clearing staging). UI: Finance Center → Cash Exchange.
- `walletToCash`: Dr passenger_credit / Cr admin_cash.
- `floatTopUp` / `floatReturn` throw failed-precondition → use cashExchange / walletToCash.
- Trip settlement: Dr `passenger_credit:driver` / Cr `passenger_credit:passenger` (openSettlement checks driver bonusBalance).
- Deferred: same wallet path; negative deferred forbidden.

## P2P
- `wallet_transfer_requests` CF-only write; rules: parties + finance read.
- `requestWalletTransfer` / `respondWalletTransfer`; daily ceiling 100_000 fromUid; 24h TTL; pull-request model.
- kinds: `wallet_p2p`.

## Other
- `getMoneyControlSnapshot`, `receiveCourierCash`, `courier_field_cash` on courierSubmitPayment.
- `reconcile` returns position breakdowns.
- Finance Center tabs: Назорат, Cash Exchange, Settlements, Journal, Closing, Exceptions.
