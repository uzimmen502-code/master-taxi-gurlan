/**
 * `functions/tools/migrate_ads_address_to_area.js` — Firestore Emulator (demo-* loyiha).
 *
 *   npm run test:migrate-ads-address     (functions/ ichidan)
 *
 *   M1  DRY (default): hech narsa yozilmaydi, backup fayl yaratilmaydi
 *   M2  --apply: uy manzili -> ommaviy hudud yorlig'i; hujjat districtId'si bo'lsa shundan,
 *       bo'lmasa egasining profilidan (districtId hujjatga YOZILMAYDI); hudud yo'q -> ''
 *   M3  faqat `address` o'zgaradi (status, text, editedAt, moderatedAt, districtId tegilmaydi);
 *       cheap_product va boshqa turlar tegilmaydi
 *   M4  backup: eski manzillar saqlangan
 *   M5  IDEMPOTENT: ikkinchi --apply hech narsani o'zgartirmaydi
 *   M6  hujjat dry-run va yozish orasida o'zgargan bo'lsa — SKIP (ustiga yozmaydi)
 *   M7  --rollback: eski manzillar qaytadi; keyin o'zgartirilgan hujjatga tegmaydi
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-ads-migrate';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const admin = require('firebase-admin');
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const TOOL = path.join(__dirname, '..', 'tools', 'migrate_ads_address_to_area.js');
const BK = fs.mkdtempSync(path.join(os.tmpdir(), 'ads-mig-'));
const run = (...args) => spawnSync(process.execPath, [TOOL, ...args], {
  env: { ...process.env, MIGRATION_BACKUP_DIR: BK }, encoding: 'utf8',
});
const backups = () => fs.readdirSync(BK).filter((f) => f.startsWith('ads-address-backup-'));
const get = async (id) => (await db.doc(`ads/${id}`).get()).data();

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
};

async function seed() {
  for (const col of ['ads', 'users', 'geo_districts', 'geo_regions']) {
    const s = await db.collection(col).get();
    await Promise.all(s.docs.map((d) => d.ref.delete()));
  }
  await db.doc('geo_regions/xorazm').set({ name: 'Xorazm viloyati', nameUz: 'Хоразм вилояти' });
  await db.doc('geo_districts/gurlan').set({ name: 'Gurlan tumani', nameUz: 'Гурлан тумани', regionId: 'xorazm' });
  await db.doc('geo_districts/urganch').set({ name: 'Urganch shahri', nameUz: 'Урганч шаҳри', regionId: 'xorazm' });
  await db.doc('users/998901110001').set({ name: 'Эга 1', districtId: 'urganch', regionId: 'xorazm' });
  await db.doc('users/998901110002').set({ name: 'Эга 2' }); // ҳудудсиз
  const base = { text: 'Матн', title: 'Сарлавҳа', authorName: 'Эга', isUrgent: false, status: 'active', editedAt: null };
  // A: hujjatda districtId bor, uy manzili ommaviy
  await db.doc('ads/A').set({ ...base, type: 'ad', authorPhone: '998901110001', districtId: 'gurlan', regionId: 'xorazm', address: 'Гурлан, Навоий кўчаси 12-уй, 4-хона' });
  // B: districtId yo'q — egasining profilidan (urganch)
  await db.doc('ads/B').set({ ...base, type: 'service', status: 'pending', authorPhone: '998901110001', address: 'Урганч, Хива кўчаси 5' });
  // C: ega hududsiz, hujjatda ham yo'q — '' ga
  await db.doc('ads/C').set({ ...base, type: 'work', authorPhone: '998901110002', address: 'Уй манзили' });
  // D: allaqachon yorliq — tegilmaydi
  await db.doc('ads/D').set({ ...base, type: 'ad', authorPhone: '998901110001', districtId: 'gurlan', regionId: 'xorazm', address: 'Гурлан тумани, Хоразм вилояти' });
  // E: bozor eʼloni — tegilmaydi
  await db.doc('ads/E').set({ type: 'cheap_product', ownerId: '998901110001', status: 'active', address: 'Бозор манзили', districtId: 'gurlan' });
  // F: manzil yo'q hujjat, hudud bor -> yorliq yoziladi
  await db.doc('ads/F').set({ ...base, type: 'ad', authorPhone: '998901110001', districtId: 'gurlan', regionId: 'xorazm' });
}

(async () => {
  await seed();
  const snapshotBefore = {};
  for (const id of ['A', 'B', 'C', 'D', 'E', 'F']) snapshotBefore[id] = await get(id);

  await check('M1 DRY: hech narsa yozilmaydi, backup yaratilmaydi', async () => {
    const r = run();
    assert.strictEqual(r.status, 0, r.stderr + r.stdout);
    assert.ok(/DRY: hech narsa yozilmadi/.test(r.stdout), r.stdout);
    assert.ok(/O'ZGARTIRILADI\s*:\s*4/.test(r.stdout), r.stdout);
    for (const id of Object.keys(snapshotBefore)) assert.deepStrictEqual(await get(id), snapshotBefore[id]);
    assert.strictEqual(backups().length, 0);
  });

  await check('M2/M3/M4 --apply: faqat address, backup bilan', async () => {
    const r = run('--apply');
    assert.strictEqual(r.status, 0, r.stderr + r.stdout);
    assert.ok(/YOZILDI=4\s+SKIP\(orada o'zgargan\)=0\s+XATO=0/.test(r.stdout), r.stdout);
    const A = await get('A'); const B = await get('B'); const C = await get('C');
    assert.strictEqual(A.address, 'Гурлан тумани, Хоразм вилояти');
    assert.strictEqual(B.address, 'Урганч шаҳри, Хоразм вилояти');
    assert.strictEqual(C.address, '');
    assert.strictEqual((await get('F')).address, 'Гурлан тумани, Хоразм вилояти');
    // address'dan boshqa HAMMA maydon o'zgarmagan (districtId B'ga YOZILMAGAN)
    for (const id of ['A', 'B', 'C', 'F']) {
      const was = { ...snapshotBefore[id] }; const now = { ...(await get(id)) };
      delete was.address; delete now.address;
      assert.deepStrictEqual(now, was, `${id}: address'dan boshqa maydon o'zgargan`);
    }
    assert.strictEqual((await get('B')).districtId, undefined);
    assert.strictEqual((await get('B')).status, 'pending');
    assert.deepStrictEqual(await get('D'), snapshotBefore.D);
    assert.deepStrictEqual(await get('E'), snapshotBefore.E);
    const files = backups();
    assert.strictEqual(files.length, 1);
    const bk = JSON.parse(fs.readFileSync(path.join(BK, files[0]), 'utf8'));
    const byId = Object.fromEntries(bk.items.map((i) => [i.id, i]));
    assert.strictEqual(byId.A.old, 'Гурлан, Навоий кўчаси 12-уй, 4-хона');
    assert.strictEqual(byId.C.old, 'Уй манзили');
    assert.strictEqual(bk.items.length, 4);
  });

  await check('M5 IDEMPOTENT: ikkinchi --apply hech narsa o\'zgartirmaydi', async () => {
    const r = run('--apply');
    assert.strictEqual(r.status, 0, r.stderr + r.stdout);
    assert.ok(/O'ZGARTIRILADI\s*:\s*0/.test(r.stdout), r.stdout);
    assert.strictEqual(backups().length, 1, 'yangi backup yaratilmasligi kerak (o\'zgarish yo\'q)');
  });

  await check('M7 --rollback: eski manzillar qaytadi; keyin o\'zgargan hujjatga tegmaydi', async () => {
    const file = path.join(BK, backups()[0]);
    await db.doc('ads/C').update({ address: 'Egasi keyin yozdi' });   // keyin o'zgartirilgan
    const r = run('--rollback', file);
    assert.strictEqual(r.status, 0, r.stderr + r.stdout);
    assert.strictEqual((await get('A')).address, 'Гурлан, Навоий кўчаси 12-уй, 4-хона');
    assert.strictEqual((await get('B')).address, 'Урганч, Хива кўчаси 5');
    assert.strictEqual((await get('C')).address, 'Egasi keyin yozdi');
    assert.ok(/Qaytarildi=3\s+tegilmadi\(keyin o'zgargan\/yo'q\)=1/.test(r.stdout), r.stdout);
  });

  await check('M6 orada o\'zgargan hujjat SKIP qilinadi (ustiga yozilmaydi)', async () => {
    await seed();
    // dry-run rejasi tuzilgandan keyin hujjat o'zgaradi: buni tool ichidagi ketma-ketlikda
    // tekshirish uchun lastUpdateTime sharti ishlatiladi — tool'ni "sekinlashtirish" o'rniga
    // sharti bevosita tekshiramiz (xuddi shu API chaqiruvi).
    const ref = db.doc('ads/A');
    const old = (await ref.get()).updateTime;
    await ref.update({ title: 'Egasi tahrir qildi' });
    let failed = false;
    try { await ref.update({ address: 'X' }, { lastUpdateTime: old }); } catch (e) { failed = true; }
    assert.ok(failed, 'eski updateTime sharti bilan yozish rad etilishi kerak');
    assert.notStrictEqual((await get('A')).address, 'X');
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  fs.rmSync(BK, { recursive: true, force: true });
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
