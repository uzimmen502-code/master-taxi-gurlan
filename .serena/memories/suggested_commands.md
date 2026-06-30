# Suggested Commands (Windows / PowerShell)

Shell is PowerShell: chain with `;` NOT `&&`. Heredoc `$(cat <<EOF)` is NOT supported — for multi-line git commit messages write a temp file then `git commit -F <file>`.

## Flutter (project root)
- `flutter analyze <paths>` — analyze specific changed files (always pass changed paths, not whole repo, to cut output/tokens)
- `flutter build apk --release`
- `powershell -ExecutionPolicy Bypass -File scripts/build_combined_web.ps1` — build user+admin web into `build/hosting`

## Firebase deploy (set CA first or cert verify fails)
- `$env:NODE_OPTIONS="--use-system-ca"; firebase deploy --only "functions:NAME1,functions:NAME2,firestore:rules"`
- `firebase deploy --only hosting`

## Cloud Functions (run inside `functions/`)
- `node --check index.js` / `node --check settlement_ledger.js` — syntax (no eslint)
- `$env:NODE_OPTIONS="--use-system-ca"; node tools/<name>.js` — self-cleaning E2E tests (need `service-account.json`)

## Reconcile ledger (inside `functions/`)
- `$env:NODE_OPTIONS="--use-system-ca"; node -e "const admin=require('firebase-admin');const sa=require('./service-account.json');admin.initializeApp({credential:admin.credential.cert(sa)});const db=admin.firestore();require('./settlement_ledger').reconcile(db).then(r=>{console.log(JSON.stringify(r,null,2));process.exit(0)})"`

## Terminals metadata
- Quick state of IDE terminals: `head -n 10 *.txt` in the terminals folder (use Read tool for full output).