/**
 * `tools/strip_ticker_soft_hyphens.js` — режа (plan): фақат U+00AD бор майдонлар, қиймат белгисиз (2026-10-26).
 *
 *   node test/strip_ticker_soft_hyphens.test.js
 */
'use strict';
const assert = require('assert');
const { plan } = require('../tools/strip_ticker_soft_hyphens');

const fakeDb = (docs) => ({
  collection: (name) => {
    assert.strictEqual(name, 'home_ticker_ads');
    return { get: async () => ({ docs: Object.entries(docs).map(([id, x]) => ({ id, data: () => x })) }) };
  },
});

(async () => {
  const steps = await plan(fakeDb({
    a: { text: 'То­пи­шин­гиз мумкин', textLatn: 'Topishingiz mumkin' },
    b: { text: 'Белгисиз матн' },
    c: { text: 'Такси?', textRu: 'Так­си?' },
    d: { text: 42 },
  }));
  assert.deepStrictEqual(steps.map((s) => `${s.id}.${s.field}`), ['a.text', 'c.textRu'], 'фақат U+00AD бор майдонлар');
  assert.strictEqual(steps[0].value, 'Топишингиз мумкин');
  assert.strictEqual(steps[0].count, 3);
  assert.strictEqual(steps[0].before, 'То­пи­шин­гиз мумкин', 'заҳира учун аввалги қиймат тўлиқ');
  assert.strictEqual(steps[1].value, 'Такси?');
  assert.deepStrictEqual(await plan(fakeDb({ x: { text: 'Тоза' } })), [], 'такрор ишга туширилса — ўзгариш йўқ');
  console.log('strip_ticker_soft_hyphens: 6/6 OK');
})().catch((e) => { console.error(e); process.exit(1); });
