#!/bin/bash
# Cloud Shell: patch-deleteRelativePerson.js ni index.js ga qo'shadi.
set -e
cd ~/master-taxi-gurlan
IDX=functions/index.js
PATCH=~/patch-deleteRelativePerson.js

if grep -q 'exports.deleteRelativePerson' "$IDX"; then
  echo "OK: deleteRelativePerson allaqachon bor"
else
  MARKER='exports.saveTreeNode = functions.https.onCall'
  if ! grep -q "$MARKER" "$IDX"; then
    echo "XATO: saveTreeNode topilmadi — to'liq index.js yuklang"
    exit 1
  fi
  python3 << 'PY'
from pathlib import Path
idx = Path("functions/index.js")
patch = Path.home() / "patch-deleteRelativePerson.js"
text = idx.read_text(encoding="utf-8")
snippet = patch.read_text(encoding="utf-8")
marker = "exports.saveTreeNode = functions.https.onCall"
if "exports.deleteRelativePerson" in text:
    print("already patched")
else:
    text = text.replace(marker, snippet + "\n" + marker, 1)
    idx.write_text(text, encoding="utf-8")
    print("PATCH OK")
PY
fi

node -e "const m=require('./functions/index.js'); console.log('deleteRelativePerson =', typeof m.deleteRelativePerson);"
