/**
 * 13.1.3 — kanon foydalanuvchi ID.
 *
 *   npm --prefix functions_demand run test:ids
 *
 * Nega bu test muhim: bu loyihada ID = telefon raqami va production'da
 * 9/12 xonali IKKI shakl yonma-yon yashaydi. Yadro faqat 12 xonali shaklni
 * yozadi — aks holda bir odam ikki provayder bo'lib ko'rinadi va
 * `demand_matches` dublikat yozadi.
 */
const assert = require('assert');
const ids = require('../core/ids');

let passed = 0;
function ok(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`  OK  ${name}`);
  } catch (e) {
    console.error(`  XATO ${name}\n       ${e.message}`);
    process.exitCode = 1;
  }
}

console.log('toCanonicalId');
ok('9 xonali -> 998 qoshiladi', () => {
  assert.strictEqual(ids.toCanonicalId('901234567'), '998901234567');
});
ok('12 xonali ozgarmaydi', () => {
  assert.strictEqual(ids.toCanonicalId('998901234567'), '998901234567');
});
ok('+998 va ajratgichlar tozalanadi', () => {
  assert.strictEqual(ids.toCanonicalId('+998 90 123-45-67'), '998901234567');
  assert.strictEqual(ids.toCanonicalId('+998(90)1234567'), '998901234567');
});
ok('eski codebase canonicalUid bilan bir xil natija', () => {
  // `functions/index.js:633` bilan zid bo'lmasligi SHART.
  const samples = ['901234567', '998901234567', '+998901234567', '90 123 45 67'];
  for (const s of samples) {
    const d = String(s).replace(/\D/g, '');
    const legacy = d.length === 9 ? `998${d}` : d;
    assert.strictEqual(ids.toCanonicalId(s), legacy, `farq: ${s}`);
  }
});
ok('notogri uzunlik -> bosh satr (jimgina tuzatilmaydi)', () => {
  assert.strictEqual(ids.toCanonicalId('123'), '');
  assert.strictEqual(ids.toCanonicalId('9012345678901234'), '');
  assert.strictEqual(ids.toCanonicalId(''), '');
  assert.strictEqual(ids.toCanonicalId(null), '');
  assert.strictEqual(ids.toCanonicalId(undefined), '');
});
ok('998 bilan boshlanmagan 12 xonali rad etiladi', () => {
  assert.strictEqual(ids.toCanonicalId('777901234567'), '');
});

console.log('isCanonicalId');
ok('faqat 998 + 9 raqam', () => {
  assert.strictEqual(ids.isCanonicalId('998901234567'), true);
  assert.strictEqual(ids.isCanonicalId('901234567'), false);
  assert.strictEqual(ids.isCanonicalId('+998901234567'), false);
  assert.strictEqual(ids.isCanonicalId(''), false);
});

console.log('requireCanonicalId');
ok('togri qiymat qaytariladi', () => {
  assert.strictEqual(ids.requireCanonicalId('901234567', 'ownerId'), '998901234567');
});
ok('notogri qiymat -> invalid-argument xatosi', () => {
  assert.throws(
    () => ids.requireCanonicalId('123', 'ownerId'),
    (e) => e.code === 'invalid-argument' && /ownerId/.test(e.message),
  );
});

console.log('candidateIdsFor');
ok('ikkala shakl, kanon birinchi', () => {
  assert.deepStrictEqual(
    ids.candidateIdsFor('901234567'),
    ['998901234567', '901234567'],
  );
});
ok('notogri -> bosh royxat', () => {
  assert.deepStrictEqual(ids.candidateIdsFor('abc'), []);
});

console.log('sameUser');
ok('9 va 12 xonali bir odam', () => {
  assert.strictEqual(ids.sameUser('901234567', '998901234567'), true);
});
ok('turli odamlar', () => {
  assert.strictEqual(ids.sameUser('901234567', '901234568'), false);
});
ok('bosh qiymatlar teng DEB HISOBLANMAYDI', () => {
  // Bu eng xavfli xato bo'lardi: ikkita bo'sh ID «bir odam» bo'lib qolsa,
  // autentifikatsiyasiz foydalanuvchi boshqaning talabini ko'rardi.
  assert.strictEqual(ids.sameUser('', ''), false);
  assert.strictEqual(ids.sameUser(null, undefined), false);
  assert.strictEqual(ids.sameUser('abc', 'xyz'), false);
});

console.log('isSafeForCompositeKey');
ok('pastki chiziq va slash rad etiladi', () => {
  assert.strictEqual(ids.isSafeForCompositeKey('abc_def'), false);
  assert.strictEqual(ids.isSafeForCompositeKey('abc/def'), false);
});
ok('oddiy Firestore auto-id xavfsiz', () => {
  assert.strictEqual(ids.isSafeForCompositeKey('aBc123XyZ456'), true);
});
ok('bosh qiymat xavfsiz emas', () => {
  assert.strictEqual(ids.isSafeForCompositeKey(''), false);
});

console.log('matchKey');
ok('demandId_providerId', () => {
  assert.strictEqual(
    ids.matchKey('dem123', '901234567'),
    'dem123_998901234567',
  );
});
ok('providerId doim kanonlashtiriladi', () => {
  assert.strictEqual(
    ids.matchKey('dem123', '901234567'),
    ids.matchKey('dem123', '+998 90 123 45 67'),
  );
});
ok('xavfsiz bolmagan demandId rad etiladi', () => {
  assert.throws(() => ids.matchKey('dem_123', '901234567'), (e) => e.code === 'invalid-argument');
});
ok('pushLogKey matchKey bilan bir xil', () => {
  assert.strictEqual(ids.pushLogKey('dem1', '901234567'), ids.matchKey('dem1', '901234567'));
});

console.log('moduleRegionKey');
ok('`capabilityKey` OLIB TASHLANDI (D-12…D-16)', () => {
  // `provider_capabilities` kaliti endi `{uid}_{module}` emas, balki
  // shunchaki kanon uid. Funksiya qayta qo'shilsa, eski shaklda
  // yozilgan hujjat yangi qoida tomonidan rad etiladi.
  assert.strictEqual(ids.capabilityKey, undefined);
});
ok('moduleRegionKey module_region', () => {
  assert.strictEqual(ids.moduleRegionKey('service', 'xorazm'), 'service_xorazm');
});
ok('module nomida pastki chiziq rad etiladi', () => {
  assert.throws(
    () => ids.moduleRegionKey('my_service', 'xorazm'),
    (e) => e.code === 'invalid-argument',
  );
});

console.log('callerIdFrom');
ok('phone_number claim dan oladi', () => {
  const ctx = { auth: { token: { phone_number: '+998901234567' } } };
  assert.strictEqual(ids.callerIdFrom(ctx), '998901234567');
});
ok('claim yoq (Anonymous Auth / veb) -> bosh satr', () => {
  // Т-2.4: veb foydalanuvchilari yadroga yozolmaydi va bu ataylab shunday.
  assert.strictEqual(ids.callerIdFrom({ auth: { token: {} } }), '');
  assert.strictEqual(ids.callerIdFrom({ auth: null }), '');
  assert.strictEqual(ids.callerIdFrom({}), '');
  assert.strictEqual(ids.callerIdFrom(undefined), '');
});

console.log(`\n${passed} test o'tdi.`);
