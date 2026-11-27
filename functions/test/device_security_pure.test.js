/**
 * Qurilma xavfsizligi — sof yordamchilar (ega 2026-11-28). Emulatorsiz.
 *   node test/device_security_pure.test.js
 */
'use strict';
const assert = require('assert');
const ds = require('../device_security');

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};

const ANDROID = {
  platform: 'android', androidId: 'a1b2c3d4e5f6', firebaseInstallationId: 'fid_0123456789abc',
  hardwareId: 'SER123', model: 'SM-A515F', brand: 'samsung', device: 'a51', product: 'a51nsxx',
  fingerprint: 'samsung/a51/2026-10',
};

check('P1 avto-tasdiq: favqulodda bayroq OFF — sozlama true bo\'lsa ham false', () => {
  assert.strictEqual(ds.DEVICE_SEC.EMERGENCY_HONOR_AUTO_APPROVE, false);
  assert.strictEqual(ds.shouldHonorAutoApprove({ settingEnabled: true, privileged: false }), false);
});

check('P2 avto-tasdiq: favqulodda ON — faqat sozlama true + imtiyozsiz', () => {
  assert.strictEqual(ds.shouldHonorAutoApprove({ settingEnabled: true, privileged: false, emergency: true }), true);
  assert.strictEqual(ds.shouldHonorAutoApprove({ settingEnabled: true, privileged: true, emergency: true }), false);
  assert.strictEqual(ds.shouldHonorAutoApprove({ settingEnabled: false, privileged: false, emergency: true }), false);
  assert.strictEqual(ds.shouldHonorAutoApprove({ settingEnabled: 'true', privileged: false, emergency: true }), false);
});

check('P3 imtiyozli rollar = panel rollari (admin/superadmin/dispatcher/finance/auditor)', () => {
  for (const r of ['admin', 'superadmin', 'dispatcher', 'finance', 'auditor', ' Admin ']) {
    assert.strictEqual(ds.isPrivilegedRole(r), true, r);
  }
  for (const r of ['user', 'driver', 'courier', '', null]) assert.strictEqual(ds.isPrivilegedRole(r), false, String(r));
});

check('P4 sameInstall: OS yangilanishi (Build.fingerprint) — bir xil o\'rnatma', () => {
  assert.strictEqual(ds.sameInstall(ANDROID, { ...ANDROID, fingerprint: 'samsung/a51/2026-11' }), true);
});

check('P5 sameInstall: boshqa FID / androidId / model / web — mos emas', () => {
  assert.strictEqual(ds.sameInstall(ANDROID, { ...ANDROID, firebaseInstallationId: 'fid_other_000000' }), false);
  assert.strictEqual(ds.sameInstall(ANDROID, { ...ANDROID, androidId: 'ffffffffffff' }), false);
  assert.strictEqual(ds.sameInstall(ANDROID, { ...ANDROID, model: 'SM-A525F' }), false);
  const web = { platform: 'web', androidId: '', firebaseInstallationId: 'fid_web_000000000', model: 'UA' };
  assert.strictEqual(ds.sameInstall(web, { ...web, fingerprint: 'en' }), false);
  // bo'sh / qisqa identifikatorlar — hech qachon mos emas
  assert.strictEqual(ds.sameInstall({ ...ANDROID, firebaseInstallationId: '' }, { ...ANDROID, firebaseInstallationId: '' }), false);
  assert.strictEqual(ds.sameInstall({}, ANDROID), false);
});

check('P6 rateStep: 5 ruxsat, 6-chi rad, oyna tugagach qayta', () => {
  let doc = null;
  const now = 1_000_000;
  for (let i = 1; i <= 5; i += 1) {
    const r = ds.rateStep(doc, now + i, 3600000, 5);
    assert.strictEqual(r.allowed, true, `#${i}`);
    doc = r.next;
  }
  const sixth = ds.rateStep(doc, now + 10, 3600000, 5);
  assert.strictEqual(sixth.allowed, false);
  assert.ok(sixth.retryAfterMs > 0 && sixth.retryAfterMs <= 3600000);
  const later = ds.rateStep(doc, now + 1 + 3600000, 3600000, 5);
  assert.strictEqual(later.allowed, true);
  assert.strictEqual(later.next.count, 1);
});

check('P7 cleanFingerprint: ≤16 kalit, uzun qiymat tashlanadi, massiv rad', () => {
  const big = {};
  for (let i = 0; i < 30; i += 1) big[`k${i}`] = 'v';
  assert.strictEqual(Object.keys(ds.cleanFingerprint(big)).length, 16);
  assert.deepStrictEqual(ds.cleanFingerprint({ a: 'x'.repeat(300), b: 'ok' }), { b: 'ok' });
  assert.deepStrictEqual(ds.cleanFingerprint(['a']), {});
  assert.deepStrictEqual(ds.cleanFingerprint(null), {});
});

check('P8 deviceLabelOf / platformOf', () => {
  assert.strictEqual(ds.deviceLabelOf(ANDROID), 'samsung SM-A515F');
  assert.strictEqual(ds.platformOf(ANDROID), 'android');
  assert.strictEqual(ds.deviceLabelOf({ platform: 'web', device: 'chrome', product: 'Win32', model: 'Mozilla/5.0 …' }),
    'Web · chrome · Win32');
});

check('P9 ipKeyOf: xom IP saqlanmaydi, barqaror xesh; city sarlavhasi ixtiyoriy', () => {
  const ctx = { rawRequest: { headers: { 'x-forwarded-for': '10.1.2.3, 1.1.1.1', 'x-appengine-city': 'tashkent' }, ip: '9.9.9.9' } };
  const k = ds.ipKeyOf(ctx);
  assert.strictEqual(k.length, 24);
  assert.ok(!k.includes('10.1.2.3'));
  assert.strictEqual(k, ds.ipKeyOf(ctx));
  assert.strictEqual(ds.ipKeyOf({}), '');
  assert.strictEqual(ds.approxCityOf(ctx), 'Tashkent');
  assert.strictEqual(ds.approxCityOf({ rawRequest: { headers: { 'x-appengine-city': '?' } } }), '');
});

check('P10 xabar matnlari va xato matnlari — 3 tilda', () => {
  for (const kind of ['attempt', 'prompt', 'admin_review_requested', 'approved']) {
    const t = ds.texts(kind, { label: 'samsung SM-A515F', city: 'Tashkent', at: '28.11 14:05' });
    for (const l of ['uz_Cyrl', 'uz_Latn', 'ru']) {
      assert.ok(t.i18n[l].title && t.i18n[l].body.includes('samsung SM-A515F'), `${kind}/${l}`);
    }
    assert.strictEqual(t.title, t.i18n.uz_Cyrl.title);
  }
  assert.ok(ds.texts('prompt').body.includes(ds.DEVICE_SEC.PLAY_URL), 'eski APK uchun yangilash havolasi');
  for (const code of Object.keys(ds.MESSAGES)) {
    for (const l of ['uz_Cyrl', 'uz_Latn', 'ru']) assert.ok(ds.MESSAGES[code][l], `${code}/${l}`);
  }
});

check('P11 secError: ichki kod + 3 til details', () => {
  const functions = require('firebase-functions');
  const e = ds.secError(functions, 'resource-exhausted', 'DEVICE_BINDING_RATE_LIMITED', { retryAfterMs: 5 });
  assert.strictEqual(e.code, 'resource-exhausted');
  assert.strictEqual(e.details.code, 'DEVICE_BINDING_RATE_LIMITED');
  assert.strictEqual(e.details.retryAfterMs, 5);
  assert.ok(e.details.messages.ru);
});

check('P12 adminDecidable: 72 soat ichida pending/expired/cancelled — ha; hal qilingan yoki eski — yo\'q', () => {
  const now = 10 * 24 * 3600 * 1000;
  const ts = (ms) => ({ toMillis: () => ms });
  assert.strictEqual(ds.adminDecidable({ status: 'pending', createdAt: ts(now - 1000) }, now), true);
  assert.strictEqual(ds.adminDecidable({ status: 'expired', createdAt: ts(now - 71 * 3600 * 1000) }, now), true);
  assert.strictEqual(ds.adminDecidable({ status: 'cancelled', createdAt: ts(now - 1000) }, now), true);
  assert.strictEqual(ds.adminDecidable({ status: 'expired', createdAt: ts(now - 73 * 3600 * 1000) }, now), false);
  for (const st of ['approved', 'rejected', 'approving']) {
    assert.strictEqual(ds.adminDecidable({ status: st, createdAt: ts(now - 1000) }, now), false, st);
  }
  assert.strictEqual(ds.adminDecidable({ status: 'pending' }, now), false, 'createdAt yo\'q');
});

const passed = results.filter(Boolean).length;
console.log(`\n${passed}/${results.length} passed`);
process.exit(passed === results.length ? 0 : 1);
