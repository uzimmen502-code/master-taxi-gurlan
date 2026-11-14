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
