/**
 * Манзил миграцияси (`tools/realty_move_address.js`) — Emulator.
 *
 *   firebase emulators:exec --only firestore "node functions/test/realty_move_address.test.js"
 *
 * Қулфланади: dry-run ҳеч нарса ёзмайди; execute очиқни тозалайди,
 * ёпиққа кўчиради, ёпиқдаги янгироқ манзилга тегмайди; rollback аввалги
 * ҳолатни АЙНАН тиклайди (27-қоида).
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-realty-move';

const admin = require('firebase-admin');
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const { plan, execute, rollback } = require('../tools/realty_move_address');

const silent = () => {};

(async () => {
  const s = await db.collection('realty_listings').get();
  await Promise.all(s.docs.map((d) => db.recursiveDelete(d.ref)));

  // L1 — эски: очиқда манзил, ёпиқда йўқ.
  await db.doc('realty_listings/L1').set({ title: 'a', addressText: 'Эски 1' });
  await db.doc('realty_listings/L1/private/detail').set({ ownerId: '998900000001', lat: 41, lng: 60 });
  // L2 — очиқда эски, ёпиқда ЯНГИРОҚ (таҳрирланган) — ёпиқ тегилмайди.
  await db.doc('realty_listings/L2').set({ title: 'b', addressText: 'Эски 2' });
  await db.doc('realty_listings/L2/private/detail').set({ ownerId: '998900000001', addressText: 'Янги 2' });
  // L3 — аллақачон тўғри.
  await db.doc('realty_listings/L3').set({ title: 'c' });
  await db.doc('realty_listings/L3/private/detail').set({ addressText: 'Тоза 3' });

  const dry = await plan(db);
  assert.deepStrictEqual(dry.map((x) => x.id).sort(), ['L1', 'L2']);
  assert.strictEqual((await db.doc('realty_listings/L1').get()).data().addressText, 'Эски 1', 'dry-run ёзмайди');

  const backupPath = path.join(os.tmpdir(), `realty_move_${Date.now()}.json`);
  const r = await execute(db, backupPath, silent);
  assert.deepStrictEqual(r, { moved: 2, leftPublic: 0, privMissing: 0 });
  assert.ok(!('addressText' in (await db.doc('realty_listings/L1').get()).data()));
  assert.strictEqual((await db.doc('realty_listings/L1/private/detail').get()).data().addressText, 'Эски 1');
  assert.strictEqual((await db.doc('realty_listings/L1/private/detail').get()).data().lat, 41, 'бошқа майдон сақланади');
  assert.strictEqual((await db.doc('realty_listings/L2/private/detail').get()).data().addressText, 'Янги 2',
    'ёпиқдаги янгироқ манзил тегилмайди');
  console.log('PASS - execute: очиқ тозаланди, ёпиққа кўчди, янгироғига тегилмади');

  // Қайта execute — ҳеч нарса қилмайди (idempotent).
  const again = await execute(db, `${backupPath}.2`, silent);
  assert.strictEqual(again.moved, 0);
  console.log('PASS - қайта ишга тушириш — бўш');

  await rollback(db, backupPath, silent);
  assert.strictEqual((await db.doc('realty_listings/L1').get()).data().addressText, 'Эски 1');
  assert.ok(!('addressText' in (await db.doc('realty_listings/L1/private/detail').get()).data()),
    'ёпиқда аввал манзил йўқ эди — олиб ташланди');
  assert.strictEqual((await db.doc('realty_listings/L2/private/detail').get()).data().addressText, 'Янги 2');
  assert.strictEqual((await db.doc('realty_listings/L2').get()).data().addressText, 'Эски 2');
  console.log('PASS - rollback аввалги ҳолатни айнан тиклади');

  fs.rmSync(backupPath, { force: true });
  fs.rmSync(`${backupPath}.2`, { force: true });
  console.log('\n3/3 realty move-address checks passed.');
  process.exit(0);
})().catch((e) => { console.log(`FAIL - ${e.stack || e.message}`); process.exit(1); });
