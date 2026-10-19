/**
 * `functions/tools/set_restaurant_sections.js` — Firestore Emulator, haqiqiy skript (child process).
 *   firebase emulators:exec --only firestore --project demo-set-sections "node functions/test/set_restaurant_sections_tool.test.js"
 * Qulflanadi: dry-run hech narsa yozmaydi; --apply versiya + tarix + audit; boshqa qiymatlar saqlanadi; takroriy — o'zgarishsiz;
 * hujjat yo'q bo'lsa to'xtaydi; noto'g'ri argumentlar rad.
 */
'use strict';
const assert = require('assert');
const path = require('path');
const { spawnSync } = require('child_process');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-set-sections';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const admin = require('firebase-admin');
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const TOOL = path.join(__dirname, '..', 'tools', 'set_restaurant_sections.js');
const run = (...args) => spawnSync(process.execPath, [TOOL, ...args], { encoding: 'utf8', env: process.env });
const cfg = async () => (await db.collection('settings').doc('restaurant_sections').get());

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.message}`); }
};

async function main() {
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });

  await check('hujjat yo\'q — to\'xtaydi (hech narsa yaratmaydi)', async () => {
    const r = run('--sections=office', '--stage=public', '--apply');
    assert.notStrictEqual(r.status, 0);
    assert.strictEqual((await cfg()).exists, false);
  });

  await db.collection('settings').doc('restaurant_sections').set({
    version: 1, sections: { cheap: 'public', national: 'public' }, testerIds: ['998912000001'], cheapRatingThreshold: 4.5,
    newMaxRatings: 5, newMaxDays: 30, newPerRestaurantPerSection: 3,
  });

  await check('dry-run: hech narsa yozilmaydi', async () => {
    const r = run('--sections=office,dastarxon,seasonal', '--stage=public');
    assert.strictEqual(r.status, 0, r.stderr);
    assert.match(r.stdout, /DRY RUN/);
    assert.strictEqual((await cfg()).data().version, 1);
    assert.strictEqual((await db.collection('restaurant_sections_history').get()).size, 0);
  });

  await check('--apply: v2, tarix + audit; boshqa bo\'limlar, tester va chegara SAQLANADI', async () => {
    const r = run('--sections=office,dastarxon,seasonal', '--stage=public', '--apply');
    assert.strictEqual(r.status, 0, r.stderr);
    const d = (await cfg()).data();
    assert.strictEqual(d.version, 2);
    assert.strictEqual(d.sections.office, 'public');
    assert.strictEqual(d.sections.seasonal, 'public');
    assert.strictEqual(d.sections.cheap, 'public');
    assert.strictEqual(d.sections.kids, 'off');
    assert.deepStrictEqual(d.testerIds, ['998912000001']);
    assert.strictEqual(d.cheapRatingThreshold, 4.5);
    assert.ok((await db.collection('restaurant_sections_history').doc('v2').get()).exists);
    const audit = await db.collection('admin_audit').where('kind', '==', 'restaurant_sections_set').get();
    assert.strictEqual(audit.size, 1);
    assert.strictEqual(audit.docs[0].data().actor, 'script:set_restaurant_sections');
  });

  await check('takroriy --apply: o\'zgarish yo\'q, versiya oshmaydi', async () => {
    const r = run('--sections=office,dastarxon,seasonal', '--stage=public', '--apply');
    assert.strictEqual(r.status, 0, r.stderr);
    assert.match(r.stdout, /O'zgarish yo'q/);
    assert.strictEqual((await cfg()).data().version, 2);
  });

  await check('noto\'g\'ri bo\'lim / bosqich — rad', async () => {
    assert.notStrictEqual(run('--sections=bunday', '--stage=public', '--apply').status, 0);
    assert.notStrictEqual(run('--sections=office', '--stage=pilot', '--apply').status, 0);
    assert.notStrictEqual(run('--stage=public', '--apply').status, 0);
    assert.strictEqual((await cfg()).data().version, 2);
  });

  const ok = results.filter(Boolean).length;
  console.log(`\n${ok} passed, ${results.length - ok} failed`);
  process.exit(results.every(Boolean) ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
