/**
 * `tools/create_splash_house_ad.js` — соф қисмлар (эга 2026-11-28). Production'га уланмайди.
 *
 *   node test/create_splash_house_ad.test.js
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');
const tool = require('../tools/create_splash_house_ad');
const { validateAd, adminAdFields } = require('../splash_ads');

const TS = admin.firestore.Timestamp;
const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`); }
};
const B = 'master-taxi-gurlan.firebasestorage.app';
const urlsOf = (bufs) => Object.fromEntries(Object.entries(bufs).map(([l, b]) => {
  const p = tool.objectPathOf(l, b, 'webp');
  return [l, tool.downloadUrlOf(B, p, tool.tokenOf(p, b))];
}));
const BUFS = { uz_Cyrl: Buffer.from('cyr'), uz_Latn: Buffer.from('lat'), ru: Buffer.from('ru') };
const NOW = Date.UTC(2026, 10, 28, 10, 0, 0); // 15:00 Тошкент

check('T1 buildAd → validateAd ўтади: house, БИТТА лотин расм, бутун республика, 365 кун, оғирлик 1', () => {
  const v = validateAd(tool.buildAd({ imageUrl: urlsOf(BUFS).uz_Latn, nowMs: NOW }));
  assert.ok(v.ok, JSON.stringify(v.errors));
  const f = adminAdFields(v.clean, TS);
  assert.deepStrictEqual([f.house, f.source, f.weight, f.areaKeys, f.visible, f.active], [true, 'admin', 1, ['all'], true, true]);
  assert.strictEqual(f.imageUrl, urlsOf(BUFS).uz_Latn); // эга: «фақат Лотин тили етарли»
  assert.deepStrictEqual(f.imageUrls, {});
  assert.deepStrictEqual(f.text, tool.TEXT);
  assert.strictEqual(f.startAt.toMillis(), Date.UTC(2026, 10, 27, 19, 0, 0)); // 28-ноябрь 00:00 Тошкент
  assert.strictEqual(f.endAt.toMillis() - f.startAt.toMillis(), 365 * 86400000);
});

check('T2 --off → active/visible false (ҳужжат ўчмайди)', () => {
  const v = validateAd(tool.buildAd({ imageUrl: urlsOf(BUFS).uz_Latn, nowMs: NOW, active: false }));
  const f = adminAdFields(v.clean, TS);
  assert.deepStrictEqual([f.active, f.visible, f.house], [false, false, true]);
});

check('T3 идемпотент: бир хил файл → бир хил йўл/токен/ҳавола; бошқа файл → бошқа йўл (мижоз кеши янгиланади)', () => {
  const a = urlsOf(BUFS);
  assert.deepStrictEqual(urlsOf(BUFS), a);
  const b = urlsOf({ ...BUFS, ru: Buffer.from('ru2') });
  assert.notStrictEqual(b.ru, a.ru);
  assert.strictEqual(b.uz_Cyrl, a.uz_Cyrl);
  assert.ok(/^platform_images\/splash_ads\/house_ru_[0-9a-f]{8}\.webp$/.test(tool.objectPathOf('ru', BUFS.ru, 'webp')));
  assert.ok(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-a[0-9a-f]{3}-[0-9a-f]{12}$/.test(tool.tokenOf('x', BUFS.ru)));
  assert.ok(a.ru.startsWith('https://firebasestorage.googleapis.com/v0/b/master-taxi-gurlan.firebasestorage.app/o/platform_images%2Fsplash_ads%2Fhouse_ru_'));
});

check('T4 comparable: вақт белгиси/версия фарқи ўзгариш эмас; матн фарқи — ўзгариш', () => {
  const f = adminAdFields(validateAd(tool.buildAd({ imageUrl: urlsOf(BUFS).uz_Latn, nowMs: NOW })).clean, TS);
  const stored = { ...f, version: 3, updatedAt: TS.fromMillis(1), createdAt: TS.fromMillis(1) };
  assert.strictEqual(tool.comparable(stored), tool.comparable(f));
  assert.notStrictEqual(tool.comparable({ ...stored, text: { uz_Cyrl: 'x' } }), tool.comparable(f));
  assert.strictEqual(tool.comparable(null), null);
});

check('T5 backup ↔ restore: Timestamp сақланади (rollback)', () => {
  const f = adminAdFields(validateAd(tool.buildAd({ imageUrl: urlsOf(BUFS).uz_Latn, nowMs: NOW })).clean, TS);
  const back = tool.fromBackup(JSON.parse(JSON.stringify(tool.toBackup({ ...f, version: 2 }))), TS);
  assert.strictEqual(back.startAt.toMillis(), f.startAt.toMillis());
  assert.strictEqual(back.imageUrl, f.imageUrl);
  assert.strictEqual(back.version, 2);
  assert.strictEqual(tool.toBackup(null), null);
});

check('T6 тайёр креатив: фақат лотин, ≤ 500 КБ, 1080×1920; бошқа тил файллари йўқ', () => {
  const dir = path.join(__dirname, '..', 'tools', 'splash_house_ad', 'out');
  for (const l of ['uz_Cyrl', 'ru']) assert.ok(!fs.existsSync(path.join(dir, `house_${l}.png`)), l);
  for (const l of ['uz_Latn']) {
    for (const ext of ['webp', 'png']) {
      const f = path.join(dir, `house_${l}.${ext}`);
      assert.ok(fs.existsSync(f), f);
      const n = fs.statSync(f).size;
      assert.ok(n > 10 * 1024 && n <= 500 * 1024, `${f}: ${n}`);
    }
    const png = fs.readFileSync(path.join(dir, `house_${l}.png`));
    assert.deepStrictEqual([png.readUInt32BE(16), png.readUInt32BE(20)], [1080, 1920]); // IHDR
  }
});

const failed = results.filter((x) => !x).length;
console.log(`\n${results.length - failed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
