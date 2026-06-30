# Conventions
- UI strings: Uzbek Cyrillic, hardcoded (no i18n framework). Code comments often Uzbek (Latin/Cyrillic); explain intent only, never narrate code.
- Encoding: all source MUST be UTF-8. Watch for double-mojibake (UTF-8 mis-read as cp1251): Cyrillic shows as `Р`/`С`-pairs (e.g. `РђРґРјРёРЅ`=Админ), emoji as `рџ...`, em-dash as `вЂ"`. Reverse safely with `text.encode('cp1251').decode('utf-8')` per non-ASCII run, accepting only sane results (Cyrillic/emoji/punct) — correct Cyrillic fails the cp1251→utf-8 round-trip so it's left untouched. (Fixed 55 files once; onboarding_screen.dart was fully corrupted.)
- Brand: app display name "AVA Gurlan"; primary green `#36A63A`.
- Money formatting: `lib/core/utils/formatters.dart` (`formatPrice`, `canonicalPhoneId`). Wallet entry labels: `lib/core/utils/wallet_ledger_labels.dart`.
- Phone/uid: CFs use `canonicalUid` (12-digit `998...`) and `userUid()`; Dart uses `canonicalPhoneId`. Keep ledger account uid consistent with the `users/{uid}` doc id used by the same flow.
- CFs: callable via `functions.https.onCall`; auth from `context`; RBAC via `requireCallerRoles(context, [roles], msg)`; idempotency via `wallet_idempotency/{key}` docs and/or client `opId`.
- Ledger collections (journal_entries, ledger_accounts, settlements, period_closings, ledger_exceptions): CF-only writes (rules `allow write: if false`); finance read via `isFinanceReader()`.
- Dart edits: prefer existing patterns; run `flutter analyze` on changed files.
- Git commits only when user explicitly asks.