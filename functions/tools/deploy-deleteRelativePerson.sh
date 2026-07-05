#!/bin/bash
# Cloud Shell: bitta skript — patch + tekshiruv + deploy.
# Upload: faqat shu fayl (LF/Unix formatida)
set -e
cd ~/master-taxi-gurlan
IDX=functions/index.js
MARKER='exports.saveTreeNode = functions.https.onCall'

echo "=== 1) Patch qo'shish ==="
if grep -q 'exports.deleteRelativePerson = functions.https.onCall' "$IDX"; then
  echo "Funksiya allaqachon index.js da bor"
else
  if ! grep -q "$MARKER" "$IDX"; then
    echo "XATO: saveTreeNode topilmadi. index.js juda eski."
    echo "Yechim: Desktop/functions-index.js (398948 bayt) ni yuklab cp qiling."
    exit 1
  fi
  python3 << 'PY'
from pathlib import Path
idx = Path("functions/index.js")
text = idx.read_text(encoding="utf-8")
marker = "exports.saveTreeNode = functions.https.onCall"
snippet = r'''
/// Shaxsiy qarindoshni o'chirish — server (Admin SDK), subcollection + tree tozalash.
exports.deleteRelativePerson = functions.https.onCall(async (data, context) => {
  const uid = datingCallerUid(context);
  const personId = String(data.personId || '');
  if (!personId) {
    throw new functions.https.HttpsError('invalid-argument', 'personId required');
  }

  const ref = db.collection('relatives').doc(uid).collection('people').doc(personId);
  const snap = await ref.get();
  if (!snap.exists) return { ok: true, alreadyDeleted: true };

  const row = snap.data() || {};
  if (row.isSelf === true) {
    throw new functions.https.HttpsError(
      'failed-precondition', 'men yozuvini ochirish mumkin emas');
  }

  const photosSnap = await ref.collection('photos').get();
  let batch = db.batch();
  let ops = 0;
  const flush = async () => {
    if (ops > 0) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  };
  for (const p of photosSnap.docs) {
    batch.delete(p.ref);
    ops++;
    if (ops >= 400) await flush();
  }
  batch.delete(ref);
  ops++;
  await flush();

  const redir = await db.collection('tree_redirects').doc(personId).get();
  if (!redir.exists) {
    const nodeSnap = await db.collection('tree_persons').doc(personId).get();
    if (nodeSnap.exists) {
      const node = nodeSnap.data() || {};
      const owner = node.ownerUid || '';
      const claimed = node.claimedBy || null;
      if (owner === uid && !claimed) {
        await db.collection('tree_persons').doc(personId).delete();
      } else if (owner === uid && claimed && claimed !== uid) {
        await db.collection('tree_persons').doc(personId).set({
          ownerUid: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
    }
  }

  const peopleSnap = await db.collection('relatives').doc(uid)
    .collection('people').get();
  batch = db.batch();
  ops = 0;
  for (const doc of peopleSnap.docs) {
    const d = doc.data() || {};
    const upd = {};
    if (d.fatherId === personId) upd.fatherId = null;
    if (d.motherId === personId) upd.motherId = null;
    if (d.spouseId === personId) upd.spouseId = null;
    if (Object.keys(upd).length) {
      upd.updatedAt = admin.firestore.FieldValue.serverTimestamp();
      batch.set(doc.ref, upd, { merge: true });
      ops++;
      if (ops >= 400) await flush();
    }
  }
  if (ops > 0) await batch.commit();

  return { ok: true };
});

'''
if marker not in text:
    raise SystemExit("marker yoq")
text = text.replace(marker, snippet + "\n" + marker, 1)
idx.write_text(text, encoding="utf-8")
print("PATCH OK")
PY
fi

echo "=== 2) Tekshiruv ==="
grep -n 'exports.deleteRelativePerson' "$IDX" | head -1
T=$(node -e "const m=require('./functions/index.js'); console.log(typeof m.deleteRelativePerson)")
echo "deleteRelativePerson = $T"
if [ "$T" != "function" ]; then
  echo "XATO: patch ishlamadi — deploy qilinmaydi"
  exit 1
fi

echo "=== 3) Deploy (default codebase, ~10 daqiqa) ==="
cd functions && npm install && cd ..
firebase deploy --only functions:default

echo "=== TAYYOR ==="
firebase functions:list 2>/dev/null | grep -i deleteRelative || true
