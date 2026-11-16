/**
 * `tools/migrate_pickup_private.js` — Firestore Emulator (REST йўли, prod билан бир хил код).
 *
 *   firebase emulators:exec --only firestore --project demo-pickup-migrate "node test/migrate_pickup_private.test.js"
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-pickup-migrate';
const P = process.env.GCLOUD_PROJECT;
if (!/^demo-/.test(P)) throw new Error('demo-* loyiha kerak');

const admin = require('firebase-admin');
admin.initializeApp({ projectId: P });
const db = admin.firestore();
const tool = require('../tools/migrate_pickup_private');

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
const shop = (id) => db.collection('tv_shops').doc(id);
const pick = (id) => shop(id).collection('private').doc('pickup');
const get = async (ref) => (await ref.get()).data();
const backupFile = path.join(os.tmpdir(), `pickup_private_test_${process.pid}.json`);
const quiet = async (fn) => { const o = console.log; console.log = () => {}; try { return await fn(); } finally { console.log = o; } };

async function seed() {
  await shop('s1').set({ ownerPhone: 's1', name: 'Bir', pickupLat: 41.84321, pickupLng: 60.39876, pickupAddress: ' Gurlan, 5-uy ' });
  await shop('s2').set({ ownerPhone: 's2', name: 'Ikki', pickupLat: 41.5, pickupLng: 60.6, pickupAddress: 'aniq', showExactLocation: true });
  await shop('s3').set({ ownerPhone: 's3', name: 'Uch', pickupLat: 41.1, pickupLng: 60.1, pickupAddress: 'eski' });
  await pick('s3').set({ lat: 42, lng: 61, address: 'yangi klient', updatedAt: admin.firestore.Timestamp.now() });
  await shop('s4').set({ ownerPhone: 's4', name: 'Tort', pickupLat: 41.2, pickupLng: 60.2, areaLat: 41.25, areaLng: 60.25 });
  await shop('s5').set({ ownerPhone: 's5', name: 'Besh', areaLat: 41.3, areaLng: 60.3 });
  await shop('s6').set({ ownerPhone: 's6', name: 'Olti', pickupAddress: 'faqat manzil' });
  await shop('s7').set({ ownerPhone: 's7', name: 'Yetti', pickupLat: 41.7, pickupLng: 60.7, pickupAddress: 'parallel' });
}

async function main() {
  await seed();
  const t5 = (await shop('s5').get()).updateTime;

  await check('P1 sof: approxCoord = klient (0.005 to\'r, 3 xona), planDoc yaroqsizni ajratadi', async () => {
    assert.strictEqual(tool.approxCoord(41.84321), 41.845);
    assert.strictEqual(tool.approxCoord(60.39876), 60.4);
    assert.strictEqual(tool.approxCoord(41.8425), 41.845); // yarim — noldan uzoqqa (Dart round)
    assert.strictEqual(tool.approxCoord(-41.8425), -41.845);
    const inv = tool.planDoc({ name: 'x/tv_shops/a', updateTime: 't', fields: { pickupLat: { doubleValue: 95 }, pickupLng: { doubleValue: 1 } } }, false);
    assert.strictEqual(inv.action, 'invalid');
  });

  await check('P2 --project majburiy; CLI dry-run hech narsa yozmaydi', async () => {
    await assert.rejects(tool.main([]), /--project/);
    const r = spawnSync(process.execPath, [path.join(__dirname, '..', 'tools', 'migrate_pickup_private.js'), '--project', P], { env: process.env, encoding: 'utf8' });
    assert.strictEqual(r.status, 0, r.stderr);
    const line = JSON.parse(r.stdout.trim().split('\n').pop());
    assert.deepStrictEqual([line.result, line.candidates, line.migrate, line.createPrivate, line.privateAlreadyExists, line.areaKept, line.invalid],
      ['dry_run', 6, 5, 4, 1, 1, ['s6']]);
    assert.strictEqual((await get(shop('s1'))).pickupLat, 41.84321);
    assert.strictEqual((await pick('s1').get()).exists, false);
  });

  let applied;
  await check('P3 apply: backup oldin, s7 parallel o\'zgardi → faqat s7 failed, qolganlar ko\'chdi', async () => {
    applied = await quiet(() => tool.main(['--project', P, '--apply'], {
      backupFile,
      beforeApply: async () => { await shop('s7').update({ name: 'Yetti (tahrir)' }); },
    }));
    const s = applied.summary;
    assert.deepStrictEqual([s.applied, s.failed], [4, 1], JSON.stringify(s));
    assert.match(s.failedIds[0], /^s7:FAILED_PRECONDITION/);
    const b = JSON.parse(fs.readFileSync(backupFile, 'utf8'));
    assert.strictEqual(b.entries.find((e) => e.id === 's1').old.pickupAddress.stringValue, ' Gurlan, 5-uy ');
    assert.strictEqual(b.entries.find((e) => e.id === 's1').status, 'applied');
    // s1: private yaratildi, ochiq taxminiy, pickup* o'chdi, boshqa maydonlar qoldi
    const p1 = await get(pick('s1'));
    assert.deepStrictEqual([p1.lat, p1.lng, p1.address, p1.updatedAt instanceof admin.firestore.Timestamp], [41.84321, 60.39876, 'Gurlan, 5-uy', true]);
    assert.deepStrictEqual(Object.keys(p1).sort(), ['address', 'lat', 'lng', 'updatedAt']);
    const s1 = await get(shop('s1'));
    assert.deepStrictEqual([s1.areaLat, s1.areaLng, s1.name, 'pickupLat' in s1, 'pickupLng' in s1, 'pickupAddress' in s1],
      [41.845, 60.4, 'Bir', false, false, false]);
    // s2: showExactLocation → aniq
    const s2 = await get(shop('s2'));
    assert.deepStrictEqual([s2.areaLat, s2.areaLng, 'pickupLat' in s2], [41.5, 60.6, false]);
    // s3: private bor edi — tegilmadi; ochiq pickup* o'chdi, area hisoblandi
    assert.strictEqual((await get(pick('s3'))).address, 'yangi klient');
    const s3 = await get(shop('s3'));
    assert.deepStrictEqual([s3.areaLat, s3.areaLng, 'pickupAddress' in s3], [41.1, 60.1, false]);
    // s4: area bor edi — qoldi
    const s4 = await get(shop('s4'));
    assert.deepStrictEqual([s4.areaLat, s4.areaLng, 'pickupLat' in s4], [41.25, 60.25, false]);
    assert.strictEqual((await pick('s4').get()).exists, true);
    // s5 tegilmadi, s6 (yaroqsiz) tegilmadi, s7 (parallel) tegilmadi
    assert.ok((await shop('s5').get()).updateTime.isEqual(t5));
    assert.strictEqual((await get(shop('s6'))).pickupAddress, 'faqat manzil');
    assert.strictEqual((await get(shop('s7'))).pickupLat, 41.7);
    assert.strictEqual((await pick('s7').get()).exists, false);
  });

  await check('P4 qayta apply — idempotent: faqat s7 (+ yaroqsiz s6) qoladi, s7 endi ko\'chadi', async () => {
    const f2 = `${backupFile}.2.json`;
    const r = await quiet(() => tool.main(['--project', P, '--apply'], { backupFile: f2 }));
    assert.deepStrictEqual([r.summary.candidates, r.summary.migrate, r.summary.applied, r.summary.failed], [2, 1, 1, 0]);
    assert.strictEqual((await get(pick('s7'))).address, 'parallel');
    const r3 = await quiet(() => tool.main(['--project', P, '--apply'], { backupFile: `${backupFile}.3.json` }));
    assert.deepStrictEqual([r3.summary.migrate, r3.backupFile], [0, null]);
    fs.unlinkSync(f2);
  });

  await check('P5 rollback dry-run hech narsa o\'zgartirmaydi; ega tahriri (s2 private) → conflict, qolganlari qaytadi', async () => {
    const dry = await quiet(() => tool.main(['--project', P, '--rollback', backupFile]));
    assert.deepStrictEqual([dry.summary.toRestore, dry.summary.privateToDelete, dry.summary.notApplied], [4, 3, 2]);
    assert.strictEqual((await pick('s1').get()).exists, true);
    await pick('s2').update({ address: 'ega tahriri' });
    const r = await quiet(() => tool.main(['--project', P, '--rollback', backupFile, '--apply']));
    assert.strictEqual(r.summary.restored, 3);
    assert.deepStrictEqual(r.summary.conflicts.map((x) => x.split(':')[0]), ['s2']);
    const s1 = await get(shop('s1'));
    assert.deepStrictEqual([s1.pickupLat, s1.pickupLng, s1.pickupAddress, 'areaLat' in s1, 'areaLng' in s1], [41.84321, 60.39876, ' Gurlan, 5-uy ', false, false]);
    assert.strictEqual((await pick('s1').get()).exists, false, 'vosita yaratgan private o\'chdi');
    assert.strictEqual((await get(pick('s3'))).address, 'yangi klient', 'vosita yaratmagan private qoladi');
    assert.strictEqual((await get(shop('s3'))).pickupAddress, 'eski');
    const s4 = await get(shop('s4'));
    assert.deepStrictEqual([s4.areaLat, s4.pickupLat, 'pickupAddress' in s4], [41.25, 41.2, false]);
    assert.strictEqual((await get(pick('s2'))).address, 'ega tahriri', 'conflict — tegilmadi');
    const b = JSON.parse(fs.readFileSync(backupFile, 'utf8'));
    assert.strictEqual(b.entries.find((e) => e.id === 's1').status, 'rolled_back');
    const again = await quiet(() => tool.main(['--project', P, '--rollback', backupFile, '--apply']));
    assert.strictEqual(again.summary.toRestore, 1, 'faqat conflict qolgan s2');
  });

  for (const f of [backupFile, `${backupFile}.3.json`]) { try { fs.unlinkSync(f); } catch (_) { /* yo'q */ } }
  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
