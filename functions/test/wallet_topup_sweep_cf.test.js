/**
 * Тўлдириш сўровлари sweeper'и — ҲАҚИҚИЙ Firestore (эмулятор).
 *
 *   npm run test:wallet-topup-sweep   (functions/ ичидан)
 *
 *   S1  24 соатдан ошган `awaiting_transfer` → `expired` (expiredAt ёзилади)
 *   S2  муддати ўтмаган сўровга тегилмайди
 *   S3  чек келган (`awaiting_review`), тасдиқланган (`credited`), бекор қилинган
 *       сўровларга ТЕГИЛМАЙДИ — ҳатто эски бўлса ҳам
 *   S4  идемпотент: иккинчи ўтишда ҳеч нарса ўзгармайди
 *   S5  РЕЙС: sweeper топгандан кейин чек келиб `awaiting_review` бўлса —
 *       транзакция уни `expired` қилмайди
 *   S6  `expiresAt` йўқ эски ҳужжат: createdAt + TTL бўйича
 *   S7  ҳажм: batchSize'дан кўп сўров бир ўтишда (бир нечта раунд) ёпилади
 *   S8  пул ўзгармайди: users.bonusBalance ва журнал ёзуви йўқ
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-wallet-topup-sweep';

const admin = require('firebase-admin');
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const { sweepExpiredTopUps } = require('../wallet_topup_support');

const COL = 'wallet_topup_requests';
const TTL = 24 * 60 * 60 * 1000;
const NOW = Date.UTC(2026, 9, 18, 12, 0, 0);
const ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);
const H = 60 * 60 * 1000;

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function wipe(col) {
  const s = await db.collection(col).get();
  await Promise.all(s.docs.map((d) => d.ref.delete()));
}
async function put(id, status, ageHours, extra = {}) {
  const created = NOW - ageHours * H;
  await db.collection(COL).doc(id).set({
    uid: '998901000001', amount: 50000, status,
    createdAt: ts(created), expiresAt: ts(created + TTL), ...extra,
  });
}
const st = async (id) => (await db.collection(COL).doc(id).get()).data().status;
const sweep = (o = {}) => sweepExpiredTopUps({ db, admin, nowMs: NOW, ttlMs: TTL, ...o });

(async () => {
  await check('S1 24 соатдан ошган awaiting_transfer → expired', async () => {
    await wipe(COL);
    await put('old', 'awaiting_transfer', 30);
    const r = await sweep();
    assert.strictEqual(r.expired, 1);
    assert.strictEqual(await st('old'), 'expired');
    const d = (await db.collection(COL).doc('old').get()).data();
    assert.ok(d.expiredAt, 'expiredAt ёзилиши керак');
  });

  await check('S2 муддати ўтмаган сўровга тегилмайди', async () => {
    await wipe(COL);
    await put('fresh', 'awaiting_transfer', 2);
    await put('edge', 'awaiting_transfer', 23);
    const r = await sweep();
    assert.strictEqual(r.expired, 0);
    assert.strictEqual(await st('fresh'), 'awaiting_transfer');
    assert.strictEqual(await st('edge'), 'awaiting_transfer');
  });

  await check('S3 бошқа ҳолатдаги эски сўровларга тегилмайди', async () => {
    await wipe(COL);
    await put('rev', 'awaiting_review', 100);
    await put('cred', 'credited', 100);
    await put('canc', 'cancelled', 100);
    await put('rej', 'rejected', 100);
    const r = await sweep();
    assert.strictEqual(r.expired, 0);
    assert.strictEqual(await st('rev'), 'awaiting_review');
    assert.strictEqual(await st('cred'), 'credited');
    assert.strictEqual(await st('canc'), 'cancelled');
    assert.strictEqual(await st('rej'), 'rejected');
  });

  await check('S4 идемпотент: иккинчи ўтишда ҳеч нарса', async () => {
    await wipe(COL);
    await put('a', 'awaiting_transfer', 30);
    await put('b', 'awaiting_transfer', 40);
    const first = await sweep();
    const second = await sweep();
    assert.strictEqual(first.expired, 2);
    assert.strictEqual(second.expired, 0);
    assert.strictEqual(await st('a'), 'expired');
  });

  await check('S5 РЕЙС: чек келиб улгурган сўров expired қилинмайди', async () => {
    await wipe(COL);
    await put('race', 'awaiting_transfer', 30);
    // Sweeper рўйхатни олади, лекин транзакциядан олдин чек келади.
    const origRun = db.runTransaction.bind(db);
    let flipped = false;
    db.runTransaction = async (fn, opts) => {
      if (!flipped) {
        flipped = true;
        await db.collection(COL).doc('race').update({ status: 'awaiting_review' });
      }
      return origRun(fn, opts);
    };
    try {
      const r = await sweep();
      assert.strictEqual(r.expired, 0);
      assert.strictEqual(r.skipped, 1);
    } finally {
      db.runTransaction = origRun;
    }
    assert.strictEqual(await st('race'), 'awaiting_review');
  });

  await check('S6 expiresAt йўқ эски ҳужжат — createdAt + TTL бўйича', async () => {
    await wipe(COL);
    await db.collection(COL).doc('legacy').set({
      uid: 'u', amount: 1, status: 'awaiting_transfer', createdAt: ts(NOW - 30 * H),
    });
    await db.collection(COL).doc('legacyNew').set({
      uid: 'u', amount: 1, status: 'awaiting_transfer', createdAt: ts(NOW - 1 * H),
    });
    const r = await sweep();
    assert.strictEqual(r.expired, 1);
    assert.strictEqual(await st('legacy'), 'expired');
    assert.strictEqual(await st('legacyNew'), 'awaiting_transfer');
  });

  await check('S7 batchSize\'дан кўп сўров бир ўтишда ёпилади', async () => {
    await wipe(COL);
    for (let i = 0; i < 7; i += 1) await put(`m${i}`, 'awaiting_transfer', 30 + i);
    await put('keep', 'awaiting_transfer', 1);
    const r = await sweep({ batchSize: 3 });
    assert.strictEqual(r.expired, 7);
    assert.strictEqual(await st('keep'), 'awaiting_transfer');
  });

  await check('S8 пул ўзгармайди', async () => {
    await wipe(COL);
    await wipe('users');
    await db.collection('users').doc('998901000001').set({ bonusBalance: 12345 });
    await put('x', 'awaiting_transfer', 30, { uid: '998901000001' });
    await sweep();
    const u = (await db.collection('users').doc('998901000001').get()).data();
    assert.strictEqual(u.bonusBalance, 12345);
    const journal = await db.collection('settlement_journal').limit(1).get();
    assert.ok(journal.empty, 'журналга ёзув тушмаслиги керак');
  });

  await wipe(COL);
  await wipe('users');
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
