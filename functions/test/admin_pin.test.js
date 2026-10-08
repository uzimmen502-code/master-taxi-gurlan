/**
 * admin_pin.js — toza funksiyalar (emulator kerak emas).
 *   node functions/test/admin_pin.test.js
 */
'use strict';
const assert = require('assert');
const p = require('../admin_pin');

const results = [];
function check(name, fn) {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
}

check('generatePin — 6 raqam, har safar boshqacha (1000 ta ichida takror kam)', () => {
  const seen = new Set();
  for (let i = 0; i < 1000; i += 1) {
    const pin = p.generatePin();
    assert.match(pin, /^\d{6}$/);
    seen.add(pin);
  }
  assert.ok(seen.size > 990, `takrorlar ko'p: ${seen.size}`);
});

check('validateNewPin — format', () => {
  assert.strictEqual(p.validateNewPin('12345'), 'ADMIN_PIN_FORMAT');
  assert.strictEqual(p.validateNewPin('1234567890123'), 'ADMIN_PIN_FORMAT');
  assert.strictEqual(p.validateNewPin('12a456'), 'ADMIN_PIN_FORMAT');
  assert.strictEqual(p.validateNewPin(''), 'ADMIN_PIN_FORMAT');
  assert.strictEqual(p.validateNewPin(null), 'ADMIN_PIN_FORMAT');
});

check('validateNewPin — zaif PIN (bir xil / ketma-ket)', () => {
  for (const w of ['000000', '111111', '123456', '654321', '234567', '0123456789', '987654']) {
    assert.strictEqual(p.validateNewPin(w), 'ADMIN_PIN_WEAK', w);
  }
});

check('validateNewPin — yaxshi PIN', () => {
  for (const ok of ['482915', '73016294', '902817364512']) {
    assert.strictEqual(p.validateNewPin(ok), null, ok);
  }
});

check('hashPin/verifyPinHash — to\'g\'ri PIN mos, noto\'g\'ri mos emas', () => {
  const rec = p.hashPin('482915');
  assert.strictEqual(rec.algo, 'scrypt-n16384-r8-p1');
  assert.ok(!JSON.stringify(rec).includes('482915'), 'PIN ochiq saqlanmaydi');
  assert.strictEqual(p.verifyPinHash('482915', rec), true);
  assert.strictEqual(p.verifyPinHash('482916', rec), false);
  assert.strictEqual(p.verifyPinHash('', rec), false);
});

check('hashPin — har safar yangi salt (bir xil PIN — boshqa xesh)', () => {
  const a = p.hashPin('482915');
  const b = p.hashPin('482915');
  assert.notStrictEqual(a.salt, b.salt);
  assert.notStrictEqual(a.hash, b.hash);
});

check('verifyPinHash — buzilgan/eski yozuv rad', () => {
  const rec = p.hashPin('482915');
  assert.strictEqual(p.verifyPinHash('482915', { ...rec, algo: 'sha256' }), false);
  assert.strictEqual(p.verifyPinHash('482915', null), false);
  assert.strictEqual(p.verifyPinHash('482915', { algo: rec.algo, salt: rec.salt }), false);
});

const failed = results.filter((x) => !x).length;
console.log(`\n${results.length - failed}/${results.length} admin_pin checks passed.`);
process.exit(failed ? 1 : 0);
