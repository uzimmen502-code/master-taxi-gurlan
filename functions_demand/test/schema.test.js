/**
 * 13.2.1 — JSON Schema validatsiyasi.
 *
 *   npm --prefix functions_demand run test:schema
 *
 * Qabul mezoni: «Noto'g'ri `attributes` -> `invalid-argument`».
 * Lekin bu testning asosiy vazifasi boshqa: KLIENT YUBORA OLMAYDIGAN
 * maydonlar haqiqatan rad etilishini qulflash. Agar `ownerId` yoki
 * `regionId` sxemadan o'tib ketsa, foydalanuvchi boshqa odam nomidan
 * talab yarata olardi — eng xavfli xato ayni shu yerda bo'lardi.
 */
const assert = require('assert');
const schema = require('../core/schema');

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

/** Minimal to'g'ri yuklama. */
function base(extra = {}) {
  return {
    module: 'service',
    clientRequestId: 'req-abc12345',
    input: { type: 'form' },
    ...extra,
  };
}

console.log('validateDemandInput — minimal');
ok('minimal yuklama o`tadi', () => {
  const r = schema.validateDemandInput(base());
  assert.ok(r.valid, r.errors.join('; '));
});
ok('standart qiymatlar qo`shiladi (useDefaults)', () => {
  const r = schema.validateDemandInput(base());
  assert.strictEqual(r.value.schemaVersion, 1);
  assert.strictEqual(r.value.source, 'module');
});
ok('asl yuklama O`ZGARMAYDI (nusxa olinadi)', () => {
  const payload = base();
  schema.validateDemandInput(payload);
  assert.strictEqual(payload.schemaVersion, undefined);
});

console.log('validateDemandInput — majburiy maydonlar');
ok('module yo`q -> xato', () => {
  const r = schema.validateDemandInput({ clientRequestId: 'req-abc12345', input: { type: 'form' } });
  assert.ok(!r.valid);
  assert.ok(r.errors.some((e) => /module/.test(e)), r.errors.join('; '));
});
ok('clientRequestId yo`q -> xato (Т-12 idempotentlik)', () => {
  const r = schema.validateDemandInput({ module: 'service', input: { type: 'form' } });
  assert.ok(!r.valid);
  assert.ok(r.errors.some((e) => /clientRequestId/.test(e)));
});
ok('input yo`q -> xato', () => {
  const r = schema.validateDemandInput({ module: 'service', clientRequestId: 'req-abc12345' });
  assert.ok(!r.valid);
});

console.log('XAVFSIZLIK: klient yubora olmaydigan maydonlar');
for (const field of [
  'ownerId', 'status', 'matching', 'assignment', 'createdAt', 'updatedAt',
  'liabilityCap', 'trustScore', 'mode',
]) {
  ok(`«${field}» rad etiladi`, () => {
    const r = schema.validateDemandInput(base({ [field]: 'nimadir' }));
    assert.ok(!r.valid, `«${field}» o'tib ketdi — bu XAVFLI`);
    assert.ok(
      r.errors.some((e) => e.includes(field)),
      `xato xabari maydonni nomlashi kerak: ${r.errors.join('; ')}`,
    );
  });
}
ok('location ichida geohash/regionId rad etiladi', () => {
  // Eng muhim holat: `regionId` klientdan olinsa, foydalanuvchi o'z talabini
  // istalgan hududga «joylashtirib» qo'ya olardi.
  const r = schema.validateDemandInput(base({
    location: { lat: 41.55, lng: 60.63, regionId: 'toshkent' },
  }));
  assert.ok(!r.valid);
  assert.ok(r.errors.some((e) => /regionId/.test(e)));
});
ok('location faqat lat/lng/addressText qabul qiladi', () => {
  const r = schema.validateDemandInput(base({
    location: { lat: 41.55, lng: 60.63, addressText: 'Al-Xorazmiy ko`chasi' },
  }));
  assert.ok(r.valid, r.errors.join('; '));
});

console.log('validateDemandInput — chegaralar');
ok('noto`g`ri modul rad etiladi', () => {
  const r = schema.validateDemandInput(base({ module: 'kosmik_taksi' }));
  assert.ok(!r.valid);
});
ok('lat chegaradan chiqsa rad etiladi', () => {
  const r = schema.validateDemandInput(base({ location: { lat: 95, lng: 60.63 } }));
  assert.ok(!r.valid);
});
ok('categoryId faqat kichik harf va pastki chiziq', () => {
  assert.ok(schema.validateDemandInput(base({ categoryId: 'santexnik' })).valid);
  assert.ok(!schema.validateDemandInput(base({ categoryId: 'Santexnik' })).valid);
  assert.ok(!schema.validateDemandInput(base({ categoryId: 'sant exnik' })).valid);
});
ok('clientRequestId juda qisqa bo`lsa rad etiladi', () => {
  assert.ok(!schema.validateDemandInput(base({ clientRequestId: 'req' })).valid);
});
ok('ttlMinutes 14 kundan oshsa rad etiladi', () => {
  assert.ok(schema.validateDemandInput(base({ timeWindow: { ttlMinutes: 20160 } })).valid);
  assert.ok(!schema.validateDemandInput(base({ timeWindow: { ttlMinutes: 20161 } })).valid);
});
ok('ttlMinutes 15 daqiqadan kam bo`lsa rad etiladi', () => {
  assert.ok(!schema.validateDemandInput(base({ timeWindow: { ttlMinutes: 5 } })).valid);
});
ok('6 tadan ko`p rasm rad etiladi', () => {
  const images = Array.from({ length: 7 }, (_, i) => `gs://bucket/img${i}.jpg`);
  assert.ok(!schema.validateDemandInput(base({ media: { images } })).valid);
});
ok('qabul qiluvchi telefoni 9 yoki 12 xonali', () => {
  const okPhones = ['901234567', '998901234567', '+998901234567'];
  for (const p of okPhones) {
    const r = schema.validateDemandInput(base({ contact: { recipientName: 'Ali', recipientPhone: p } }));
    assert.ok(r.valid, `${p}: ${r.errors.join('; ')}`);
  }
  const badPhones = ['123', '9012345671234', 'abcdefghi'];
  for (const p of badPhones) {
    assert.ok(
      !schema.validateDemandInput(base({ contact: { recipientName: 'Ali', recipientPhone: p } })).valid,
      `${p} o'tib ketdi`,
    );
  }
});
ok('bo`sh title rad etiladi, lekin title ixtiyoriy', () => {
  assert.ok(schema.validateDemandInput(base()).valid, 'title ixtiyoriy');
  assert.ok(!schema.validateDemandInput(base({ title: 'ab' })).valid, 'juda qisqa');
});

console.log('validateAttributes — service (P0 piloti)');
ok('bo`sh attributes o`tadi', () => {
  assert.ok(schema.validateAttributes('service', {}).valid);
  assert.ok(schema.validateAttributes('service', undefined).valid);
});
ok('to`g`ri attributes o`tadi', () => {
  const r = schema.validateAttributes('service', {
    visitType: 'at_my_place',
    objectType: 'apartment',
    areaM2: 12.5,
    hasMaterials: false,
    accessNotes: 'Ikkinchi qavat, lift yo`q',
  });
  assert.ok(r.valid, r.errors.join('; '));
});
ok('noma`lum attribut rad etiladi (QABUL MEZONI)', () => {
  const r = schema.validateAttributes('service', { xayoliy_maydon: 1 });
  assert.ok(!r.valid);
  assert.ok(r.errors.some((e) => /xayoliy_maydon/.test(e)), r.errors.join('; '));
});
ok('noto`g`ri enum rad etiladi', () => {
  assert.ok(!schema.validateAttributes('service', { visitType: 'oyda' }).valid);
});
ok('areaM2 chegaralari', () => {
  assert.ok(!schema.validateAttributes('service', { areaM2: 0.1 }).valid);
  assert.ok(!schema.validateAttributes('service', { areaM2: 99999 }).valid);
});
ok('null ruxsat etilgan joyda ishlaydi', () => {
  assert.ok(schema.validateAttributes('service', { areaM2: null, workersNeeded: null }).valid);
});

console.log('validateAttributes — sxemasi yo`q modul');
ok('sxemasi yo`q modulda bo`sh attributes o`tadi', () => {
  assert.ok(schema.validateAttributes('courier', {}).valid);
});
ok('sxemasi yo`q modulda to`la attributes RAD ETILADI', () => {
  // Bu eng muhim himoya: yangi modul qo'shilganda sxemasini yozishni
  // esdan chiqarsa, tekshirilmagan ma'lumot bazaga tushmaydi.
  const r = schema.validateAttributes('courier', { weightKg: 4 });
  assert.ok(!r.valid);
  assert.ok(r.errors.some((e) => /sxemasi yo'q/.test(e)), r.errors.join('; '));
});

console.log('validateCreateDemand — birga');
ok('yuklama + attributlar birga tekshiriladi', () => {
  const r = schema.validateCreateDemand(base({
    categoryId: 'santexnik',
    attributes: { visitType: 'at_my_place' },
  }));
  assert.ok(r.valid, r.errors.join('; '));
  assert.strictEqual(r.value.attributes.visitType, 'at_my_place');
});
ok('noto`g`ri attribut butun chaqiruvni rad etadi', () => {
  const r = schema.validateCreateDemand(base({ attributes: { yolgon: true } }));
  assert.ok(!r.valid);
  assert.ok(r.errors.some((e) => /attributes/.test(e)), r.errors.join('; '));
});
ok('attributes standart qiymatlari to`ldiriladi', () => {
  const r = schema.validateCreateDemand(base({ attributes: {} }));
  assert.ok(r.valid, r.errors.join('; '));
  assert.strictEqual(r.value.attributes.visitType, 'at_my_place');
  assert.strictEqual(r.value.attributes.preferredTimeOfDay, 'any');
});

console.log('validateOfferInput');
ok('minimal taklif o`tadi', () => {
  const r = schema.validateOfferInput({ demandId: 'dem123', clientRequestId: 'req-abc12345' });
  assert.ok(r.valid, r.errors.join('; '));
});
ok('to`liq taklif o`tadi', () => {
  const r = schema.validateOfferInput({
    demandId: 'dem123',
    clientRequestId: 'req-abc12345',
    price: 150000,
    priceType: 'fixed',
    message: '18:00 gacha boraman',
    etaMinutes: 40,
    delivery: true,
  });
  assert.ok(r.valid, r.errors.join('; '));
});
ok('demandId da pastki chiziq rad etiladi (composite kalit)', () => {
  const r = schema.validateOfferInput({ demandId: 'dem_123', clientRequestId: 'req-abc12345' });
  assert.ok(!r.valid);
});
ok('providerId va status klientdan OLINMAYDI', () => {
  for (const f of ['providerId', 'status', 'createdAt', 'ownerId', 'revision']) {
    const r = schema.validateOfferInput({
      demandId: 'dem123', clientRequestId: 'req-abc12345', [f]: 'x',
    });
    assert.ok(!r.valid, `«${f}» o'tib ketdi`);
  }
});
ok('manfiy narx rad etiladi', () => {
  const r = schema.validateOfferInput({
    demandId: 'dem123', clientRequestId: 'req-abc12345', price: -100,
  });
  assert.ok(!r.valid);
});

console.log('modulesWithAttributeSchema');
ok('P0 da faqat service', () => {
  assert.deepStrictEqual(schema.modulesWithAttributeSchema(), ['service']);
});

console.log(`\n${passed} test o'tdi.`);
