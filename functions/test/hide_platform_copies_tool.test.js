/**
 * `tools/hide_platform_copies_in_wholesale.js` (ega 2026-11-28, audit F-1 / 16-band) — sof qismlar + Firestore Emulator
 * ichida haqiqiy skript (child process): dry-run hech narsa yozmaydi, apply → inactive + backup + audit, qayta apply —
 * idempotent, rollback → avvalgi holat; egasi orada o'zgartirgan hujjatga rollback tegmaydi.
 *
 *   npm run test:hide-platform-copies   (functions/ ichidan)
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
const PROJECT = 'demo-hide-platform-copies';
process.env.GCLOUD_PROJECT = PROJECT;

const tool = require('../tools/hide_platform_copies_in_wholesale');
const admin = require('firebase-admin');
admin.initializeApp({ projectId: PROJECT });
const db = admin.firestore();

const TOOL = path.join(__dirname, '..', 'tools', 'hide_platform_copies_in_wholesale.js');
const BACKUP_DIR = path.join(__dirname, '..', 'tools', 'backup');
const OWNER = '998900008777';

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};
const run = (...args) => {
  const r = spawnSync(process.execPath, [TOOL, '--project', PROJECT, ...args], { encoding: 'utf8', env: process.env });
  return { code: r.status, out: `${r.stdout || ''}${r.stderr || ''}` };
};
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const get = async (id) => (await db.doc(`wholesale_products/${id}`).get()).data();
const fakeFv = { ts: () => 'TS', del: () => 'DEL' };

async function seed() {
  await clearEmulator();
  const base = { sellerId: OWNER, sellerCompanyName: 'AVA', title: 'Ун 1 кг', market: 'wholesale' };
  await db.doc('wholesale_products/pp_a').set({ ...base, status: 'active' });
  await db.doc('wholesale_products/pp_b').set({ ...base, status: 'pending', adminNote: 'eski' });
  await db.doc('wholesale_products/pp_c').set({ ...base, status: 'active' });
  await db.doc('wholesale_products/pp_x').set({ ...base, sellerCompanyName: 'Бошқа', status: 'active' }); // тегилмайди
  await db.doc('wholesale_products/real1').set({ ...base, status: 'active' }); // pp_ эмас — тегилмайди
  await db.doc('wholesale_orders/o1').set({ productId: 'pp_a', status: 'placed' });
  await db.doc('wholesale_orders/o2').set({ productId: 'pp_c', status: 'delivered' });
}

async function main() {
  await check('P1 sof: nishon, patch, expect, rollback rejasi', async () => {
    assert.strictEqual(tool.isHideTarget('pp_1', { sellerCompanyName: 'AVA' }), true);
    assert.strictEqual(tool.isHideTarget('pp_1', { sellerCompanyName: 'AVA', sampleHidden: true }), false);
    assert.strictEqual(tool.isHideTarget('pp_1', { sellerCompanyName: 'Sunlight' }), false);
    assert.strictEqual(tool.isHideTarget('x_pp_1', { sellerCompanyName: 'AVA' }), false);
    const p = tool.hidePatch({ status: 'active' }, fakeFv);
    assert.deepStrictEqual([p.status, p.sampleHidden, p.samplePrevStatus, p.samplePrevAdminNote, p.adminNote],
      ['inactive', true, 'active', null, tool.HIDE_NOTE]);
    assert.strictEqual(tool.expectOk(59, 59), true);
    assert.strictEqual(tool.expectOk(58, 59), false);
    assert.strictEqual(tool.expectOk(59, NaN), false);
    assert.deepStrictEqual(tool.rollbackPlan({ sampleHidden: true, status: 'pending' }, { status: 'active' }, fakeFv),
      { skip: 'status_changed:pending' });
    assert.deepStrictEqual(tool.rollbackPlan(null, {}, fakeFv), { skip: 'missing' });
    const rb = tool.rollbackPlan({ sampleHidden: true, status: 'inactive' }, { status: 'active' }, fakeFv);
    assert.deepStrictEqual([rb.patch.status, rb.patch.adminNote, rb.patch.sampleHidden], ['active', 'DEL', 'DEL']);
    assert.deepStrictEqual(tool.parseArgs(['--project', 'p', '--expect=3', '--apply']),
      { project: 'p', apply: true, rollback: false, from: '', expect: 3 });
    assert.strictEqual(tool.parseArgs(['--project=p']).expect, 59);
  });

  await seed();
  await check('E1 --project yo\'q — rad (exit 2)', async () => {
    const r = spawnSync(process.execPath, [TOOL], { encoding: 'utf8', env: process.env });
    assert.strictEqual(r.status, 2);
  });

  await check('E2 DRY RUN: hech narsa yozilmaydi; ta\'sir hisoboti (ochiq buyurtma 1)', async () => {
    const r = run();
    assert.strictEqual(r.code, 0, r.out);
    assert.match(r.out, /нишон: 3/);
    assert.match(r.out, /очиқ буюртма 1/);
    assert.match(r.out, /НОМУВОФИҚ \(тегилмайди\) pp_x/);
    assert.strictEqual((await get('pp_a')).status, 'active');
    assert.strictEqual((await db.collection('admin_audit').get()).size, 0);
  });

  await check('E3 apply: kutilgan son mos emas — rad, yozuv yo\'q', async () => {
    const r = run('--apply');
    assert.notStrictEqual(r.code, 0);
    assert.match(r.out, /нишон 3 ≠ кутилган 59/);
    assert.strictEqual((await get('pp_a')).status, 'active');
  });

  let backupFile = '';
  await check('E4 apply --expect=3: inactive + prev qiymatlar + backup + audit; boshqalarga tegilmaydi', async () => {
    const r = run('--apply', '--expect=3');
    assert.strictEqual(r.code, 0, r.out);
    const m = r.out.match(/захира: (.+\.json)/);
    assert.ok(m, r.out);
    backupFile = m[1].trim();
    assert.ok(fs.existsSync(backupFile));
    const a = await get('pp_a');
    const b = await get('pp_b');
    assert.deepStrictEqual([a.status, a.sampleHidden, a.samplePrevStatus, a.adminNote], ['inactive', true, 'active', tool.HIDE_NOTE]);
    assert.deepStrictEqual([b.status, b.samplePrevStatus, b.samplePrevAdminNote], ['inactive', 'pending', 'eski']);
    assert.strictEqual((await get('pp_x')).status, 'active');
    assert.strictEqual((await get('real1')).status, 'active');
    assert.strictEqual((await get('pp_a')).title, 'Ун 1 кг', 'kontent o\'zgarmaydi');
    const au = (await db.collection('admin_audit').get()).docs.map((d) => d.data());
    assert.deepStrictEqual([au.length, au[0].kind, au[0].count], [1, 'wholesale_platform_copies_hide', 3]);
    assert.match(r.out, /ҳали active: 0/);
  });

  await check('E5 qayta apply — idempotent (nishon 0, yozuv yo\'q)', async () => {
    const r = run('--apply', '--expect=0');
    assert.strictEqual(r.code, 0, r.out);
    assert.match(r.out, /нишон: 0/);
    assert.match(r.out, /захира ҳам ёзилмади/);
    assert.strictEqual((await db.collection('admin_audit').get()).size, 1);
  });

  await check('E6 rollback: dry-run yozmaydi; apply avvalgi holat; egasi o\'zgartirgan (pp_c) — tegilmaydi', async () => {
    await db.doc('wholesale_products/pp_c').update({ status: 'pending' }); // egasi qayta yubordi
    const dry = run('--rollback', `--from=${backupFile}`);
    assert.strictEqual(dry.code, 0, dry.out);
    assert.strictEqual((await get('pp_a')).status, 'inactive');
    const r = run('--rollback', `--from=${backupFile}`, '--apply');
    assert.strictEqual(r.code, 0, r.out);
    assert.match(r.out, /skip pp_c: status_changed:pending/);
    const a = await get('pp_a');
    const b = await get('pp_b');
    assert.deepStrictEqual([a.status, a.sampleHidden, a.adminNote, a.samplePrevStatus], ['active', undefined, undefined, undefined]);
    assert.deepStrictEqual([b.status, b.adminNote], ['pending', 'eski']);
    assert.strictEqual((await get('pp_c')).status, 'pending');
    const kinds = (await db.collection('admin_audit').get()).docs.map((d) => d.data().kind).sort();
    assert.deepStrictEqual(kinds, ['wholesale_platform_copies_hide', 'wholesale_platform_copies_unhide']);
  });

  // Test (emulator) zaxiralarini tozalash — faqat shu demo loyihaniki.
  if (fs.existsSync(BACKUP_DIR)) {
    for (const f of fs.readdirSync(BACKUP_DIR).filter((x) => x.startsWith('hide-platform-copies-backup-'))) {
      const p = path.join(BACKUP_DIR, f);
      try { if (JSON.parse(fs.readFileSync(p, 'utf8')).project === PROJECT) fs.unlinkSync(p); } catch (_) { /* boshqa fayl */ }
    }
    try { fs.rmdirSync(BACKUP_DIR); } catch (_) { /* bo'sh emas — qoladi */ }
  }
  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
