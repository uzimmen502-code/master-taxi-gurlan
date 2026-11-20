/**
 * «AVA Супермаркет»: мижоз буюртмани ФАҚАТ `new` ҳолатида бекор қилади (эга 2026-11-20). customerCancelOrder, Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-sm-cancel "node test/sm_customer_cancel_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-sm-cancel';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');

const db = admin.firestore();
const U = '998917000001';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const cancel = (orderId) => fns.customerCancelOrder.run({ orderId }, ctxOf(U));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const get = async (p) => (await db.doc(p).get()).data();
const smOrder = (extra) => ({
  type: 'platform', subtype: 'supermarket', userPhone: U, phone: U, items: [], inventoryDecrements: [],
  total: 50000, balanceApplied: 50000, walletUserDocId: U, cashDue: 0, paymentStatus: 'paid',
  fulfillmentStatus: 'pending', status: 'new', ...extra,
});

async function main() {
  await clearEmulator();
  await db.doc(`users/${U}`).set({ role: 'user', bonusBalance: 0 });
  await db.doc('orders/sm_new').set(smOrder({}));
  await db.doc('orders/sm_acc').set(smOrder({ status: 'accepted', fulfillmentStatus: 'confirmed' }));
  await db.doc('orders/sm_ready').set(smOrder({ status: 'ready', fulfillmentStatus: 'ready' }));
  const { subtype, ...legacy } = smOrder({ status: 'accepted', fulfillmentStatus: 'confirmed', balanceApplied: 0, total: 1000 });
  await db.doc('orders/legacy_acc').set(legacy);

  await check('K1 супермаркет `new` — мижоз бекор қилади, ҳамён қайтади', async () => {
    await cancel('sm_new');
    const o = await get('orders/sm_new');
    assert.ok(['cancelled', 'rejected'].includes(o.status) || o.fulfillmentStatus === 'cancelled', JSON.stringify([o.status, o.fulfillmentStatus]));
    assert.strictEqual((await get(`users/${U}`)).bonusBalance, 50000);
  });

  await check('K2 супермаркет `accepted` / `ready` — рад SUPERMARKET_CANCEL_ONLY_NEW (3 тил), ҳеч нарса ўзгармайди', async () => {
    for (const id of ['sm_acc', 'sm_ready']) {
      await assert.rejects(cancel(id), (e) => {
        assert.strictEqual(e.code, 'failed-precondition');
        assert.strictEqual(e.details.code, 'SUPERMARKET_CANCEL_ONLY_NEW');
        for (const l of ['uz_Cyrl', 'uz_Latn', 'ru']) assert.ok(e.details.messages[l], l);
        return true;
      });
      const o = await get(`orders/${id}`);
      assert.ok(['accepted', 'ready'].includes(o.status));
    }
    assert.strictEqual((await get(`users/${U}`)).bonusBalance, 50000);
    // қайта уриниш ҳам рад (idempotency ёзуви қолмаган)
    await assert.rejects(cancel('sm_acc'), (e) => e.details.code === 'SUPERMARKET_CANCEL_ONLY_NEW');
  });

  await check('K3 эски platform буюртма `accepted` — аввалгидек мижоз бекор қила олади (regression)', async () => {
    await cancel('legacy_acc');
    const o = await get('orders/legacy_acc');
    assert.ok(['cancelled', 'rejected'].includes(o.status) || o.fulfillmentStatus === 'cancelled');
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}
main().catch((e) => { console.error(e); process.exit(1); });
