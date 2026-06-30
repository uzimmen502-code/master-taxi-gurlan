# Task Completion Checks
- Dart changes: `flutter analyze <changed files>` — no NEW issues. Pre-existing geolocator `desiredAccuracy`/`timeLimit` deprecations are acceptable.
- CF JS changes: `node --check` on edited files (no eslint in project).
- Ledger/money changes: run relevant `functions/tools/*_test.js` (self-cleaning, net-zero) AND verify `reconcile` is green: `balanced && identityOk && projectionOk && mismatches==0`.
- Deploy only the specific changed functions: `firebase deploy --only "functions:NAME"` with `$env:NODE_OPTIONS="--use-system-ca"`.
- Commit/push ONLY when the user asks; PowerShell — commit message via temp file + `git commit -F`.