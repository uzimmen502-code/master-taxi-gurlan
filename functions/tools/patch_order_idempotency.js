/** Add idempotency to placeCarpetWashOrder and placeAgroPickupOrder. */
const fs = require('fs');
const path = require('path');

const p = path.join(__dirname, '..', 'index.js');
let s = fs.readFileSync(p, 'utf8');

function patchPlace(fnName, prefix) {
  const needle = `exports.${fnName} = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
    }

    const`;
  const idemBlock = `exports.${fnName} = functions.https.onCall(async (data, context) => {
  try {
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
    }

    const idempotencyKey = String(data.idempotencyKey || '').trim();
    if (idempotencyKey) {
      const idemRef = db.collection('wallet_idempotency').doc('${prefix}_' + idempotencyKey);
      const idemSnap = await idemRef.get();
      if (idemSnap.exists) {
        const prev = idemSnap.data() || {};
        return { ok: true, orderId: String(prev.orderId || ''), idempotent: true };
      }
    }

    const`;
  if (!s.includes(needle)) {
    console.error('needle not found for', fnName);
    process.exit(1);
  }
  s = s.replace(needle, idemBlock);

  const retNeedle = `    await orderRef.set(payload);
    return { ok: true, orderId: orderRef.id };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error('${fnName}:'`;
  const retBlock = `    await orderRef.set(payload);
    if (idempotencyKey) {
      await db.collection('wallet_idempotency').doc('${prefix}_' + idempotencyKey).set({
        orderId: orderRef.id,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    return { ok: true, orderId: orderRef.id };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error('${fnName}:'`;
  if (!s.includes(retNeedle)) {
    console.error('return needle not found for', fnName);
    process.exit(1);
  }
  s = s.replace(retNeedle, retBlock);
}

patchPlace('placeCarpetWashOrder', 'carpet');
patchPlace('placeAgroPickupOrder', 'agro');
fs.writeFileSync(p, s);
console.log('idempotency patched');
