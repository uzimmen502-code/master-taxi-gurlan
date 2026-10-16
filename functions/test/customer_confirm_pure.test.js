/**
 * Mijoz tasdig'i — SOF qism (emulatorsiz): sozlamani me'yorlash, darvoza qarori,
 * keshlangan o'qigich va uch tilli matnlar.
 *
 *   node functions/test/customer_confirm_pure.test.js
 */
'use strict';
const assert = require('assert');
const cc = require('../customer_confirm');
const i18n = require('../notif_i18n');

const canon = (v) => {
  const d = String(v || '').replace(/[^\d]/g, '');
  return d.length === 9 ? `998${d}` : d;
};
const C1 = '998905550005';
const C2 = '998905550006';

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
const cfgOf = (stage, testers) => cc.normalizeConfig({
  modules: { restaurant: { stage }, carpet: { stage }, agro: { stage }, collection: { stage } }, testerIds: testers || [],
}, canon);

async function main() {
  await check('P1 sozlama yo\'q / bo\'sh / noto\'g\'ri tur -> hamma modul off, testerlar bo\'sh', () => {
    for (const raw of [null, undefined, {}, [], 'x', 5, { modules: null }, { modules: [] }, { modules: 'public' }]) {
      const c = cc.normalizeConfig(raw, canon);
      assert.deepStrictEqual(c, { modules: { restaurant: 'off', carpet: 'off', agro: 'off', collection: 'off' }, testerIds: [] }, JSON.stringify(raw));
    }
  });
  await check('P2 noto\'g\'ri bosqich qiymatlari -> off (PUBLIC, 1, null, obyekt emas, ortiqcha bo\'shliq, matn)', () => {
    for (const bad of ['PUBLIC', 'Public', ' public', 'public ', 1, true, null, {}, [], 'on', 'enabled', '']) {
      const c = cc.normalizeConfig({ modules: { carpet: { stage: bad } } }, canon);
      assert.strictEqual(c.modules.carpet, 'off', `stage=${JSON.stringify(bad)}`);
    }
    assert.strictEqual(cc.normalizeConfig({ modules: { carpet: 'public' } }, canon).modules.carpet, 'off', 'matn o\'rniga obyekt kerak');
    assert.strictEqual(cc.normalizeConfig({ modules: { carpet: { stage: 'public' } } }, canon).modules.carpet, 'public');
    assert.strictEqual(cc.normalizeConfig({ modules: { carpet: { stage: 'internal' } } }, canon).modules.carpet, 'internal');
    assert.strictEqual(cc.normalizeConfig({ modules: { toString: { stage: 'public' }, constructor: { stage: 'public' } } }, canon).modules.carpet, 'off');
  });
  await check('P3 testerlar: kanonik, takrorsiz, tartiblangan; noto\'g\'ri elementlar tashlanadi; ro\'yxat bo\'lmasa bo\'sh', () => {
    const c = cc.normalizeConfig({ testerIds: [`+${C2}`, C1.slice(3), C1, 'abc', '123', null, {}, 998905550007, '997905550007'] }, canon);
    assert.deepStrictEqual(c.testerIds, [C1, C2, '998905550007'].sort());
    assert.deepStrictEqual(cc.normalizeConfig({ testerIds: 'x' }, canon).testerIds, []);
    assert.deepStrictEqual(cc.normalizeConfig({ testerIds: { 0: C1 } }, canon).testerIds, []);
  });
  await check('P4 darvoza: off -> hech kim; public -> hamma; internal -> faqat tester (9/12 xonali shakl farqsiz)', () => {
    assert.strictEqual(cc.isGatedBy(cfgOf('off', [C1]), 'carpet', C1, canon), false);
    assert.strictEqual(cc.isGatedBy(cfgOf('public'), 'carpet', C2, canon), true);
    const internal = cfgOf('internal', [C1]);
    assert.strictEqual(cc.isGatedBy(internal, 'carpet', C1, canon), true);
    assert.strictEqual(cc.isGatedBy(internal, 'carpet', C1.slice(3), canon), true, '9 xonali shakl');
    assert.strictEqual(cc.isGatedBy(internal, 'carpet', `+${C1}`, canon), true);
    assert.strictEqual(cc.isGatedBy(internal, 'carpet', C2, canon), false);
    assert.strictEqual(cc.isGatedBy(internal, 'carpet', '', canon), false);
    assert.strictEqual(cc.isGatedBy(internal, 'carpet', null, canon), false);
    assert.strictEqual(cc.isGatedBy(internal, 'unknown', C1, canon), false, 'noma\'lum modul');
    assert.strictEqual(cc.isGatedBy(null, 'carpet', C1, canon), false);
    const mixed = cc.normalizeConfig({ modules: { carpet: { stage: 'public' }, agro: { stage: 'internal' } }, testerIds: [C1] }, canon);
    assert.deepStrictEqual(
      ['restaurant', 'carpet', 'agro', 'collection'].map((m) => cc.isGatedBy(mixed, m, C2, canon)), [false, true, false, false]);
  });
  await check('P5 ommaviy belgi: biror modul off emas -> true', () => {
    assert.strictEqual(cc.markerEnabled(cfgOf('off')), false);
    assert.strictEqual(cc.markerEnabled(cfgOf('internal')), true);
    assert.strictEqual(cc.markerEnabled(cc.normalizeConfig({ modules: { agro: { stage: 'public' } } }, canon)), true);
    assert.strictEqual(cc.markerEnabled(null), false);
  });
  await check('P6 qadamlar jadvali: har modulning qadamlari', () => {
    assert.deepStrictEqual(cc.STEPS, {
      restaurant: ['received'], carpet: ['handover_pickup', 'handover_return'], agro: ['handover_pickup'], collection: ['finalize'],
    });
  });

  // ── Keshlangan o'qigich ───────────────────────────────────────────────
  const fakeDb = (state) => ({
    gets: 0,
    collection() {
      return {
        doc: () => ({
          get: async () => {
            this.gets += 1;
            if (state.fail) throw new Error('boom');
            return { exists: state.doc !== null, data: () => state.doc };
          },
        }),
      };
    },
  });
  await check('P7 o\'qigich: kesh ichida bitta o\'qish; muddat o\'tgach qayta; invalidate qayta o\'qiydi', async () => {
    const state = { doc: { modules: { carpet: { stage: 'public' } } } };
    const db = fakeDb(state);
    let now = 1000;
    const r = cc.makeConfigReader({ db, canon, ttlMs: 30000, nowFn: () => now });
    assert.strictEqual((await r.get()).modules.carpet, 'public');
    assert.strictEqual((await r.get()).modules.carpet, 'public');
    assert.strictEqual(db.gets, 1);
    state.doc = { modules: { carpet: { stage: 'off' } } };
    now += 29999;
    assert.strictEqual((await r.get()).modules.carpet, 'public', 'muddat ichida eski qiymat');
    now += 2;
    assert.strictEqual((await r.get()).modules.carpet, 'off');
    assert.strictEqual(db.gets, 2);
    state.doc = { modules: { carpet: { stage: 'public' } } };
    r.invalidate();
    assert.strictEqual((await r.get()).modules.carpet, 'public');
    assert.strictEqual(db.gets, 3);
  });
  await check('P8 o\'qigich: ttl=0 keshsiz; hujjat yo\'q -> off; o\'qish xatosi -> oldingi qiymat, u yo\'q bo\'lsa off (fail-closed)', async () => {
    const state = { doc: null };
    const db = fakeDb(state);
    const errors = [];
    const r = cc.makeConfigReader({ db, canon, ttlMs: 0, nowFn: () => 1, onError: (e) => errors.push(e.message) });
    assert.strictEqual((await r.get()).modules.carpet, 'off');
    assert.strictEqual((await r.get()).modules.carpet, 'off');
    assert.strictEqual(db.gets, 2, 'ttl=0: har safar o\'qiydi');
    state.fail = true;
    assert.strictEqual((await r.get()).modules.carpet, 'off', 'xato + oldingi yo\'q -> off');
    assert.deepStrictEqual(errors, ['boom']);
    state.fail = false;
    state.doc = { modules: { carpet: { stage: 'public' } } };
    assert.strictEqual((await r.get()).modules.carpet, 'public');
    state.fail = true;
    assert.strictEqual((await r.get()).modules.carpet, 'public', 'xato -> oxirgi ma\'lum qiymat');
  });

  // ── Matnlar ───────────────────────────────────────────────────────────
  const KEYS = ['confirm_restaurant_received', 'confirm_carpet_pickup', 'confirm_carpet_return', 'confirm_agro_pickup', 'confirm_collection_finalize'];
  await check('P9 matnlar: har kalit uch tilda, bo\'sh emas, ichki atamalarsiz, ўринбосарлар to\'ldirilganda { } qolmaydi', () => {
    for (const key of KEYS) {
      assert.ok(i18n.MESSAGES[key], `kalit yo'q: ${key}`);
      assert.deepStrictEqual(Object.keys(i18n.MESSAGES[key]).sort(), [...i18n.LANGS].sort(), key);
      for (const lang of i18n.LANGS) {
        const m = i18n.render(key, lang, { summary: 'Sut: 10 l', amount: '50 000' });
        assert.ok(m.title.trim().length > 3 && m.body.trim().length > 10, `${key}/${lang} bo'sh`);
        assert.ok(!/\{\w+\}/.test(`${m.title} ${m.body}`), `${key}/${lang}: to'ldirilmagan o'rinbosar`);
        assert.ok(!/\b(LEG|ZONE|settlement|routing|escrow|ledger)\b/i.test(`${m.title} ${m.body}`), `${key}/${lang}: ichki atama`);
      }
      assert.ok(/[а-яё]/i.test(i18n.render(key, 'ru', { summary: 'x' }).title), `${key}: ru kirill`);
      assert.ok(/[ўқғҳ]/i.test(JSON.stringify(i18n.render(key, 'uz_Cyrl', { summary: 'x' }))) || /[а-я]/i.test(i18n.render(key, 'uz_Cyrl', { summary: 'x' }).title), `${key}: uz_Cyrl kirill`);
      assert.ok(/[a-z]/i.test(i18n.render(key, 'uz_Latn', { summary: 'x' }).title) && !/[а-яё]/i.test(i18n.render(key, 'uz_Latn', { summary: 'x' }).title), `${key}: uz_Latn lotin`);
    }
    const col = i18n.render('confirm_collection_finalize', 'uz_Latn', { summary: 'QAYD-77', amount: '12 345' }).body;
    assert.ok(col.includes('QAYD-77') && col.includes('12 345'), 'yig\'ib olish matnida miqdor va summa ko\'rinadi');
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
