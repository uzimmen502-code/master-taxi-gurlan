'use strict';
/**
 * tools/migrate_geo_latin_alphabet.js — тоза тестлар + (FIRESTORE_EMULATOR_HOST бўлса) Admin SDK қатлами эмуляторда.
 *   node test/migrate_geo_latin_alphabet.test.js
 *   firebase emulators:exec --only firestore --project demo-geo-latin "node test/migrate_geo_latin_alphabet.test.js"
 */
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const M = require('../tools/migrate_geo_latin_alphabet');

const results = [];
async function check(name, fn) {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`);
  }
}

/** Хотирадаги store (SDK/REST билан бир хил интерфейс; updateTime шарти текширилади). */
function memStore(seed) {
  const db = new Map(); // key -> {name, other, v}
  for (const [k, v] of Object.entries(seed)) db.set(k, { ...v, v: 1 });
  return {
    label: 'memory',
    db,
    async* listAll(col) {
      for (const [k, d] of [...db].sort()) if (k.startsWith(`${col}/`)) yield { collection: col, id: k.split('/')[1], updateTime: d.v, name: d.name };
    },
    async getMany(col, ids) {
      return ids.map((id) => {
        const d = db.get(`${col}/${id}`);
        return d ? { collection: col, id, exists: true, updateTime: d.v, name: d.name } : { collection: col, id, exists: false, updateTime: null, name: undefined };
      });
    },
    async commit(writes) {
      for (const w of writes) if (!db.has(`${w.collection}/${w.id}`) || db.get(`${w.collection}/${w.id}`).v !== w.updateTime) throw new Error('FAILED_PRECONDITION');
      for (const w of writes) { const d = db.get(`${w.collection}/${w.id}`); d.name = w.after; d.v += 1; }
    },
  };
}
const SEED = {
  'geo_regions/xorazm': { name: 'Xorazm viloyati', nameUz: 'Хоразм вилояти' },
  'geo_regions/fargona': { name: "Farg'ona viloyati", nameUz: 'Фарғона вилояти' },
  'geo_regions/toshkent_sh': { name: 'Toshkent shahri', nameUz: 'Тошкент шаҳри' },
  'geo_districts/gurlan': { name: 'Gurlan tumani', nameUz: 'Гурлан тумани' },
  'geo_districts/shovot': { name: 'Shovot tumani', nameUz: 'Шовот тумани' },
  'geo_districts/qoshkopir': { name: 'Qo‘shko‘pir tumani', nameUz: 'Қўшкўпир тумани' },
  'geo_districts/empty': { nameUz: 'Номсиз' },
};
const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'geo-latin-'));
const quiet = async (fn) => { const l = console.log; console.log = () => {}; try { return await fn(); } finally { console.log = l; } };

(async () => {
  await check('parseArgs: --project majburiy main da; --rollback faylsiz → xato', async () => {
    assert.deepStrictEqual(M.parseArgs(['--project', 'p', '--apply']), { apply: true, project: 'p', rollback: undefined });
    await assert.rejects(M.main([]), /--project/);
    await assert.rejects(M.main(['--project', 'p', '--rollback']), /--rollback/);
  });
  await check('planDoc: faqat name; o\'zgarmasa/bo\'sh — null; idempotent', () => {
    assert.deepStrictEqual(M.planDoc({ collection: 'geo_districts', id: 's', name: 'Shovot tumani', updateTime: 1 }),
      { collection: 'geo_districts', id: 's', updateTime: 1, before: 'Shovot tumani', after: 'Şovot tumani' });
    assert.strictEqual(M.planDoc({ collection: 'geo_districts', id: 'g', name: 'Gurlan tumani' }), null);
    assert.strictEqual(M.planDoc({ collection: 'geo_districts', id: 'e', name: undefined }), null);
    assert.strictEqual(M.planDoc({ collection: 'geo_districts', id: 's', name: 'Şovot tumani' }), null);
    assert.strictEqual(M.planDoc({ collection: 'geo_regions', id: 'f', name: "Farg'ona viloyati" }).after, 'Farğona viloyati');
    assert.strictEqual(M.planDoc({ collection: 'geo_districts', id: 'q', name: 'Qo‘shko‘pir tumani' }).after, 'Qöşköpir tumani');
  });
  await check('DRY RUN: hech narsa yozilmaydi, backup yo\'q', async () => {
    const s = memStore(SEED);
    const dir = tmp();
    const r = await quiet(() => M.migrate(s, { project: 'demo', apply: false }, { backupDir: dir }));
    assert.strictEqual(r.planned, 4);
    assert.strictEqual(s.db.get('geo_districts/shovot').name, 'Shovot tumani');
    assert.deepStrictEqual(fs.readdirSync(dir), []);
  });
  await check('APPLY: backup avval, faqat name o\'zgaradi, tekshiruv; qayta ishga tushirish — 0 yozuv', async () => {
    const s = memStore(SEED);
    const dir = tmp();
    const r = await quiet(() => M.migrate(s, { project: 'demo', apply: true }, { backupDir: dir, now: 0 }));
    assert.deepStrictEqual([r.planned, r.done, r.verified], [4, 4, 4]);
    assert.strictEqual(s.db.get('geo_regions/toshkent_sh').name, 'Toşkent şahri');
    assert.strictEqual(s.db.get('geo_regions/toshkent_sh').nameUz, 'Тошкент шаҳри');
    assert.strictEqual(s.db.get('geo_districts/gurlan').name, 'Gurlan tumani');
    const bk = JSON.parse(fs.readFileSync(r.backup, 'utf8'));
    assert.strictEqual(bk.kind, 'geo_latin_alphabet_migration');
    assert.strictEqual(bk.docs.length, 4);
    assert.ok(bk.docs.some((d) => d.id === 'shovot' && d.before === 'Shovot tumani' && d.after === 'Şovot tumani'));
    const again = await quiet(() => M.migrate(s, { project: 'demo', apply: true }, { backupDir: dir }));
    assert.strictEqual(again.planned, 0);
  });
  await check('ROLLBACK: faqat skript yozgan qiymatda; qo\'lda tuzatilgan — tegilmaydi; boshqa loyiha backup — rad', async () => {
    const s = memStore(SEED);
    const dir = tmp();
    const r = await quiet(() => M.migrate(s, { project: 'demo', apply: true }, { backupDir: dir }));
    s.db.get('geo_districts/shovot').name = 'Shovot (qo\'lda)';
    s.db.get('geo_districts/shovot').v += 1;
    const dry = await quiet(() => M.rollback(s, { project: 'demo', rollback: r.backup, apply: false }));
    assert.deepStrictEqual([dry.planned, dry.skipped], [3, 1]);
    assert.strictEqual(s.db.get('geo_regions/fargona').name, 'Farğona viloyati');
    const rb = await quiet(() => M.rollback(s, { project: 'demo', rollback: r.backup, apply: true }));
    assert.deepStrictEqual([rb.done, rb.verified, rb.skipped], [3, 3, 1]);
    assert.strictEqual(s.db.get('geo_regions/fargona').name, "Farg'ona viloyati");
    assert.strictEqual(s.db.get('geo_districts/shovot').name, 'Shovot (qo\'lda)');
    await assert.rejects(quiet(() => M.rollback(s, { project: 'other', rollback: r.backup, apply: false })), /boshqa loyiha/);
  });
  await check('updateTime sharti: orada o\'zgargan hujjat yozilmaydi (chunk xato, exitCode 1)', async () => {
    const s = memStore(SEED);
    const orig = s.commit;
    s.commit = async (w) => { s.db.get('geo_districts/shovot').v += 1; s.commit = orig; return orig(w); };
    const r = await quiet(() => M.migrate(s, { project: 'demo', apply: true }, { backupDir: tmp() }));
    assert.strictEqual(r.done, 0);
    assert.strictEqual(s.db.get('geo_districts/shovot').name, 'Shovot tumani');
    process.exitCode = 0;
  });

  if (process.env.FIRESTORE_EMULATOR_HOST) {
    await check('EMULATOR: Admin SDK qatlami — apply + rollback', async () => {
      const project = process.env.GCLOUD_PROJECT || 'demo-geo-latin';
      const store = M.sdkStore(project);
      const admin = require('firebase-admin');
      const db = admin.firestore();
      for (const [k, v] of Object.entries(SEED)) await db.doc(k).set(v);
      const r = await quiet(() => M.migrate(store, { project, apply: true }, { backupDir: tmp() }));
      assert.deepStrictEqual([r.planned, r.done, r.verified], [4, 4, 4]);
      assert.strictEqual((await db.doc('geo_districts/qoshkopir').get()).data().name, 'Qöşköpir tumani');
      assert.strictEqual((await db.doc('geo_districts/qoshkopir').get()).data().nameUz, 'Қўшкўпир тумани');
      const rb = await quiet(() => M.rollback(store, { project, rollback: r.backup, apply: true }));
      assert.strictEqual(rb.done, 4);
      assert.strictEqual((await db.doc('geo_districts/qoshkopir').get()).data().name, 'Qo‘shko‘pir tumani');
    });
  } else {
    console.log('SKIP - EMULATOR (FIRESTORE_EMULATOR_HOST yo\'q)');
  }

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
})();
