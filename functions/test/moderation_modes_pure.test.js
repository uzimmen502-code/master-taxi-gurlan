/**
 * Moderatsiya rejimlari — sof qoidalar + rules ro'yxati paritet (ega 2026-11-28, audit C-1). Emulatorsiz.
 *   node test/moderation_modes_pure.test.js
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const mm = require('../moderation_modes');
const mmod = require('../market_moderation');

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};

check('P1 registr: 10 faol rejim, maydon nomlari eski (backward compat), faqat realty defaultOn', () => {
  const fields = Object.fromEntries(Object.entries(mm.MODERATION_MODES).map(([k, v]) => [k, v.field]));
  assert.deepStrictEqual(fields, {
    dating: 'datingAutoApprove', market: 'marketAutoApprove', jobs: 'jobsAutoApprove', tv: 'tvAutoApprove',
    shopItem: 'shopItemAutoApprove', wholesaleProduct: 'wholesaleProductAutoApprove',
    wholesaleSeller: 'wholesaleSellerAutoApprove', realty: 'realtyAutoApprove',
    producerVerify: 'producerVerifyAutoApprove', supermarketPartner: 'supermarketPartnerAutoApprove',
  });
  const on = Object.entries(mm.MODERATION_MODES).filter(([, v]) => v.defaultOn).map(([k]) => k);
  assert.deepStrictEqual(on, ['realty']);
});

check('P2 iste\'fodagi: deviceBinding va restaurant — faol registrda YO\'Q (yozib/yoqib bo\'lmaydi)', () => {
  assert.deepStrictEqual(Object.keys(mm.RETIRED_MODES).sort(), ['deviceBinding', 'restaurant']);
  assert.strictEqual(mm.MODERATION_MODES.deviceBinding, undefined);
  assert.strictEqual(mm.isModeAuto({ deviceBindingAutoApprove: true }, 'deviceBinding'), false);
  assert.strictEqual(mm.isModeAuto({ restaurantAutoApprove: true }, 'restaurant'), false);
});

check('P3 defaultOn=false: faqat aniq true; yo\'q/null/"true"/1/boshqa kalit — false (eski === true)', () => {
  for (const mode of Object.keys(mm.MODERATION_MODES).filter((m) => m !== 'realty')) {
    const f = mm.MODERATION_MODES[mode].field;
    assert.strictEqual(mm.isModeAuto({ [f]: true }, mode), true, mode);
    for (const s of [undefined, null, {}, { [f]: false }, { [f]: 'true' }, { [f]: 1 }, { [f]: null }]) {
      assert.strictEqual(mm.isModeAuto(s, mode), false, `${mode} ${JSON.stringify(s)}`);
    }
  }
});

check('P4 realty: faqat aniq false o\'chiradi; yo\'q/null/"false" — AVTO (eski appSetting(...,true) !== false)', () => {
  const legacy = (app) => {
    const v = (app || {}).realtyAutoApprove;
    return (v === undefined || v === null ? true : v) !== false;
  };
  for (const s of [undefined, null, {}, { realtyAutoApprove: true }, { realtyAutoApprove: false },
    { realtyAutoApprove: null }, { realtyAutoApprove: 'false' }, { realtyAutoApprove: 0 }]) {
    assert.strictEqual(mm.isModeAuto(s, 'realty'), legacy(s), JSON.stringify(s));
  }
});

check('P5 market_moderation.shopItemAutoApproveOf — yagona qoida orqali, natija o\'zgarmagan', () => {
  assert.strictEqual(mmod.shopItemAutoApproveOf({ shopItemAutoApprove: true }), true);
  for (const s of [undefined, null, {}, { shopItemAutoApprove: 'true' }, { marketAutoApprove: true }]) {
    assert.strictEqual(mmod.shopItemAutoApproveOf(s), false, JSON.stringify(s));
  }
});

check('P6 describeModes: samarali qiymat + saqlangan bool (yo\'q — null)', () => {
  const d = mm.describeModes({ tvAutoApprove: true, realtyAutoApprove: 'x' });
  const by = Object.fromEntries(d.map((x) => [x.mode, x]));
  assert.deepStrictEqual([by.tv.enabled, by.tv.stored], [true, true]);
  assert.deepStrictEqual([by.realty.enabled, by.realty.stored, by.realty.defaultOn], [true, null, true]);
  assert.deepStrictEqual([by.jobs.enabled, by.jobs.stored], [false, null]);
  assert.strictEqual(d.length, 10);
});

check('P7 noma\'lum rejim — false (xavfsiz: qo\'lda)', () => {
  assert.strictEqual(mm.isModeAuto({ x: true }, 'nope'), false);
  assert.strictEqual(mm.isModeAuto({ toString: true }, 'toString'), false);
});

check('P8 firestore.rules moderationModeSettingKeys() = ALL_MODE_FIELDS (+ shopItem UpdatedAt/By)', () => {
  const rules = fs.readFileSync(path.join(__dirname, '..', '..', 'firestore.rules'), 'utf8');
  const m = rules.match(/function moderationModeSettingKeys\(\) \{\s*return \[([\s\S]*?)\];/);
  assert.ok(m, 'rules funksiyasi topilmadi');
  const keys = [...m[1].matchAll(/'([A-Za-z]+)'/g)].map((x) => x[1]).sort();
  const want = [...mm.ALL_MODE_FIELDS, 'shopItemAutoApproveUpdatedAt', 'shopItemAutoApproveUpdatedBy'].sort();
  assert.deepStrictEqual(keys, want);
});

const passed = results.filter(Boolean).length;
console.log(`\n${passed}/${results.length} passed`);
process.exit(passed === results.length ? 0 : 1);
