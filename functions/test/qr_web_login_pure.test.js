/**
 * QR web kirish — sof yordamchilar (ega 2026-11-28).
 *   node test/qr_web_login_pure.test.js
 */
'use strict';
const assert = require('assert');
const q = require('../qr_web_login');

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e && e.message}`);
  }
};
const ts = (ms) => ({ toMillis: () => ms });

check('P1 holat mashinasi: ruxsat etilgan o\'tishlar', () => {
  assert.ok(q.canTransitionQr('pending', 'scanned'));
  assert.ok(q.canTransitionQr('scanned', 'approved'));
  assert.ok(q.canTransitionQr('approved', 'consumed'));
  assert.ok(q.canTransitionQr('scanned', 'rejected'));
  assert.ok(q.canTransitionQr('pending', 'expired'));
});

check('P2 holat mashinasi: taqiqlangan o\'tishlar (replay, orqaga, terminaldan)', () => {
  assert.ok(!q.canTransitionQr('pending', 'consumed'), 'tasdiqsiz consume yo\'q');
  assert.ok(!q.canTransitionQr('scanned', 'consumed'));
  assert.ok(!q.canTransitionQr('consumed', 'consumed'), 'replay yo\'q');
  assert.ok(!q.canTransitionQr('consumed', 'approved'));
  assert.ok(!q.canTransitionQr('rejected', 'approved'));
  assert.ok(!q.canTransitionQr('expired', 'approved'));
  assert.ok(!q.canTransitionQr('approved', 'approved'));
  assert.ok(!q.canTransitionQr('', 'approved'));
  assert.ok(!q.canTransitionQr('bogus', 'scanned'));
});

check('P3 effectiveStatus: muddat chegarasi (== now → expired), terminal holat o\'zgarmaydi', () => {
  const now = 1_000_000;
  assert.strictEqual(q.effectiveStatus({ status: 'pending', expiresAt: ts(now + 1) }, now), 'pending');
  assert.strictEqual(q.effectiveStatus({ status: 'pending', expiresAt: ts(now) }, now), 'expired');
  assert.strictEqual(q.effectiveStatus({ status: 'approved', expiresAt: ts(now - 1) }, now), 'expired');
  assert.strictEqual(q.effectiveStatus({ status: 'consumed', expiresAt: ts(now - 1) }, now), 'consumed');
  assert.strictEqual(q.effectiveStatus({ status: 'scanned' }, now), 'scanned');
});

check('P4 bosqich: hujjat yo\'q/noma\'lum = off; internal faqat testerIds; public hammaga', () => {
  assert.strictEqual(q.normalizeStage(null), 'off');
  assert.strictEqual(q.normalizeStage({ stage: 'PILOT' }), 'off');
  assert.ok(!q.stageAllows({}, '998901234567'));
  assert.ok(!q.stageAllows({ stage: 'internal', testerIds: ['998900000000'] }, '998901234567'));
  assert.ok(q.stageAllows({ stage: 'internal', testerIds: ['998901234567'] }, '998901234567'));
  assert.ok(q.stageAllows({ stage: ' Public ' }, '998901234567'));
});

check('P5 QR matni: AVAQR1:<32 hex>; boshqa narsa rad', () => {
  const sid = 'a'.repeat(32);
  assert.strictEqual(q.parseQrPayload(q.qrPayloadFor(sid)), sid);
  assert.strictEqual(q.parseQrPayload(`AVAQR1:${'A'.repeat(32)}`), sid);
  assert.strictEqual(q.parseQrPayload(`AVAQR1:${'a'.repeat(31)}`), '');
  assert.strictEqual(q.parseQrPayload(`https://evil/?${sid}`), '');
  assert.strictEqual(q.parseQrPayload(''), '');
  assert.strictEqual(q.parseQrPayload(`AVAQR1:${'g'.repeat(32)}`), '');
});

check('P6 sir: to\'g\'ri mos, noto\'g\'ri/bo\'sh/buzilgan hash — yo\'q', () => {
  const secret = 'b'.repeat(64);
  const h = q.sha256Hex(secret);
  assert.ok(q.secretMatches(secret, h));
  assert.ok(!q.secretMatches('c'.repeat(64), h));
  assert.ok(!q.secretMatches(secret, ''));
  assert.ok(!q.secretMatches(secret, 'zz'));
  assert.notStrictEqual(h, secret);
});

check('P7 User-Agent → yorliq (to\'liq UA saqlanmaydi)', () => {
  assert.strictEqual(q.browserLabelFromUA('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36'), 'Chrome · Windows');
  assert.strictEqual(q.browserLabelFromUA('Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 Chrome/120 Safari/537.36 Edg/120.0'), 'Edge · Windows');
  assert.strictEqual(q.browserLabelFromUA('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17 Safari/605.1.15'), 'Safari · macOS');
  assert.strictEqual(q.browserLabelFromUA('Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0'), 'Firefox · Linux');
  assert.strictEqual(q.browserLabelFromUA(''), '');
});

check('P8 sessionItem: telefon/IP/sir hash chiqmaydi; muddati o\'tgan active → expired', () => {
  const now = 5000;
  const it = q.sessionItem('w1', { phone: '998901234567', ipKey: 'x', renewSecretHash: 'h', status: 'active', expiresAt: ts(now - 1), browserLabel: 'Chrome · Windows' }, now);
  assert.strictEqual(it.status, 'expired');
  assert.strictEqual(it.phone, undefined);
  assert.strictEqual(it.ipKey, undefined);
  assert.strictEqual(it.renewSecretHash, undefined);
  assert.strictEqual(q.sessionItem('w2', { status: 'active', expiresAt: ts(now + 1) }, now).status, 'active');
});

check('P9 xabar va xato matnlari 3 tilda', () => {
  const t = q.texts('web_login', { label: 'Chrome · Windows', at: '10:00' });
  for (const l of ['uz_Cyrl', 'uz_Latn', 'ru']) {
    assert.ok(t.i18n[l].title && t.i18n[l].body.includes('Chrome'));
  }
  for (const code of Object.keys(q.MESSAGES)) {
    for (const l of ['uz_Cyrl', 'uz_Latn', 'ru']) assert.ok(q.qrMessagesFor(code)[l], `${code}.${l}`);
  }
});

const passed = results.filter(Boolean).length;
console.log(`\n${passed}/${results.length} passed`);
process.exit(passed === results.length ? 0 : 1);
