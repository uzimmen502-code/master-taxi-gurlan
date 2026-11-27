/**
 * Ulgurji buyurtma zanjiri, 5-bosqich (admin) — darvoza va sinovchilar (2026-10-31).
 *
 *   node functions_demand/test/wholesale_orders_admin.test.js
 *
 * `adminSetWholesaleOrdersStage` / `adminGetWholesaleOrdersStage` —
 * `module_config/wholesale_orders_all` {enabled, stage, testerIds}.
 *
 * Qulflanadi:
 *   - huquq: token yo'q / oddiy foydalanuvchi / dispatcher — rad (pul oqimini ochadi)
 *   - tekshiruv: sabab majburiy, enabled turi, noma'lum stage, noto'g'ri telefon,
 *     bir raqam ham add ham remove, hech narsa yo'q, 500 chegara
 *   - yozuv: hujjat yo'q bo'lsa yaratiladi (standart yopiq), kanonik telefon, takrorsiz,
 *     boshqa maydonlar saqlanadi; audit (admin_audit, telefonsiz)
 *   - idempotent: takror chaqiruv — yozuv ham, audit ham yo'q
 *   - kvota darvozasi (`requireOrdersGate`) yozilgan hujjatni AYNAN shunday o'qiydi
 */
const assert = require('assert');
const { FakeFirestore } = require('./fake_firestore');
const config = require('../core/config');
const api = require('../api/wholesale_orders_admin');
const orders = require('../api/wholesale_orders');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const ADMIN = '998909990000';
const SUPER = '998906660000';
const DISP = '998908880000';
const USER = '998901110001';
const T1 = '998901110011';
const T2 = '998902220022';
const NOW = new Date('2026-10-31T12:00:00.000Z');
const ctx = (phone) => ({ auth: { token: { phone_number: `+${phone}` } } });

function makeDb(seed = {}) {
  config.clearCache();
  const db = new FakeFirestore({
    [`users/${ADMIN}`]: { role: 'admin' },
    [`users/${SUPER}`]: { role: 'superadmin' },
    [`users/${DISP}`]: { role: 'dispatcher' },
    [`users/${USER}`]: { role: 'user' },
    ...seed,
  });
  db.runTransaction = async (fn) => {
    const tx = {
      get: (ref) => {
        if (tx._ops.length) throw new Error('Firestore transactions require all reads to be executed before all writes.');
        return ref.get();
      },
      set: (ref, data, opts) => { tx._ops.push(() => ref.set(data, opts)); },
      update: (ref, data) => { tx._ops.push(() => ref.update(data)); },
      _ops: [],
    };
    const out = await fn(tx);
    for (const op of tx._ops) await op();
    return out;
  };
  return db;
}

const set = (db, data, who = ADMIN) => api.makeAdminSetWholesaleOrdersStage({ db, now: () => NOW })(data, who ? ctx(who) : {});
const get = (db, who = ADMIN) => api.makeAdminGetWholesaleOrdersStage({ db })({}, who ? ctx(who) : {});
const gate = (db) => db.dump('module_config').wholesale_orders_all;
const audits = (db) => Object.values(db.dump('admin_audit') || {}).filter((a) => a.kind === api.AUDIT_KIND);

async function rejects(promise, code, reason) {
  try {
    await promise;
  } catch (e) {
    assert.strictEqual(e.code, code, `kutilgan «${code}», keldi «${e.code}»: ${e.message}`);
    if (reason) assert.strictEqual((e.details || {}).reason, reason, `reason: ${JSON.stringify(e.details)}`);
    return e;
  }
  throw new Error(`«${code}/${reason || ''}» xatosi kutilgan edi`);
}

const origLog = console.log;
const origErr = console.error;
const quiet = () => { console.log = () => {}; console.error = () => {}; };
const loud = () => { console.log = origLog; console.error = origErr; };

ok('huquq: token yo\'q / user / dispatcher — rad, hech narsa yozilmaydi; admin va superadmin — mumkin', async () => {
  const db = makeDb();
  await rejects(set(db, { enabled: true, reason: 'ochamiz' }, null), 'unauthenticated');
  await rejects(set(db, { enabled: true, reason: 'ochamiz' }, USER), 'permission-denied');
  await rejects(set(db, { enabled: true, reason: 'ochamiz' }, DISP), 'permission-denied');
  await rejects(get(db, null), 'unauthenticated');
  await rejects(get(db, USER), 'permission-denied');
  await rejects(get(db, DISP), 'permission-denied');
  assert.strictEqual(gate(db), undefined);
  assert.strictEqual(audits(db).length, 0);
  const r = await set(db, { addTesterIds: [T1], reason: 'sinov' }, SUPER);
  assert.strictEqual(r.ok, true);
  assert.strictEqual((await get(db, SUPER)).testerCount, 1);
});

ok('tekshiruv: sabab, enabled turi, stage, telefon, add∩remove, bo\'sh so\'rov, 500 chegara', async () => {
  const db = makeDb();
  await rejects(set(db, { enabled: true }), 'invalid-argument', 'reason_required');
  await rejects(set(db, { enabled: true, reason: '  a ' }), 'invalid-argument', 'reason_required');
  await rejects(set(db, { enabled: 'true', reason: 'xato tur' }), 'invalid-argument', 'enabled_invalid');
  await rejects(set(db, { enabled: 1, reason: 'xato tur' }), 'invalid-argument', 'enabled_invalid');
  await rejects(set(db, { stage: 'beta', reason: 'xato bosqich' }), 'invalid-argument', 'stage_invalid');
  await rejects(set(db, { stage: 'PUBLIC', reason: 'xato bosqich' }), 'invalid-argument', 'stage_invalid');
  await rejects(set(db, { addTesterIds: ['123'], reason: 'telefon' }), 'invalid-argument', 'tester_invalid');
  await rejects(set(db, { addTesterIds: T1, reason: 'telefon' }), 'invalid-argument', 'tester_invalid');
  await rejects(set(db, { addTesterIds: [T1], removeTesterIds: [`+${T1}`], reason: 'ziddiyat' }),
    'invalid-argument', 'tester_args_conflict');
  await rejects(set(db, { reason: 'hech narsa' }), 'invalid-argument', 'nothing_to_change');
  const many = Array.from({ length: 501 }, (_, i) => `99890${String(1000000 + i)}`);
  await rejects(set(db, { addTesterIds: many, reason: 'chegara' }), 'invalid-argument', 'testers_limit');
  assert.strictEqual(gate(db), undefined, 'rad etilganlar hujjat yaratmadi');
  assert.strictEqual(audits(db).length, 0);
  // Chegara: aynan 500 — mumkin.
  const r = await set(db, { addTesterIds: many.slice(0, 500), reason: 'chegara 500' });
  assert.strictEqual(r.testerCount, 500);
});

ok('hujjat yo\'q: sinovchi qo\'shish hujjatni YOPIQ holda yaratadi (enabled false, internal); audit telefonsiz', async () => {
  const db = makeDb();
  const before = await get(db);
  assert.deepStrictEqual(
    { e: before.exists, en: before.enabled, s: before.stage, n: before.testerCount, open: before.effectiveOpen },
    { e: false, en: false, s: 'internal', n: 0, open: false },
  );
  const r = await set(db, { addTesterIds: ['+998 90 111 00 11', '902220022', T1, ' '], reason: 'ichki sinov' });
  assert.deepStrictEqual(
    { ok: r.ok, u: r.unchanged, c: r.created, en: r.enabled, s: r.stage, n: r.testerCount, a: r.added, rm: r.removed },
    { ok: true, u: false, c: true, en: false, s: 'internal', n: 2, a: 2, rm: 0 },
  );
  assert.ok(!JSON.stringify(r).includes(T1) && !JSON.stringify(r).includes(T2), 'setter javobida telefon yo\'q');
  const g = gate(db);
  assert.deepStrictEqual({ en: g.enabled, s: g.stage, t: g.testerIds, by: g.updatedBy, cb: g.createdBy },
    { en: false, s: 'internal', t: [T1, T2], by: ADMIN, cb: ADMIN });
  const a = audits(db);
  assert.strictEqual(a.length, 1);
  assert.deepStrictEqual(
    { act: a[0].actor, tg: a[0].target, f: a[0].from, t: a[0].to, ad: a[0].added, rm: a[0].removed, r: a[0].reason },
    {
      act: ADMIN,
      tg: 'module_config/wholesale_orders_all',
      f: { exists: false, enabled: false, stage: 'internal', testerCount: 0 },
      t: { enabled: false, stage: 'internal', testerCount: 2 },
      ad: 2,
      rm: 0,
      r: 'ichki sinov',
    },
  );
  assert.ok(!JSON.stringify(a[0]).includes(T1), 'auditda telefon yo\'q (40-band)');
  const after = await get(db);
  assert.deepStrictEqual(after.testerIds, [T1, T2], 'getter admin uchun ro\'yxatni beradi');
  assert.strictEqual(after.effectiveOpen, false, 'enabled false — yopiq');
});

ok('hujjat yo\'q va so\'rov standartga teng (enabled:false) — unchanged, hujjat YARATILMAYDI', async () => {
  const db = makeDb();
  const r = await set(db, { enabled: false, stage: 'internal', reason: 'yopiq qoladi' });
  assert.strictEqual(r.unchanged, true);
  assert.strictEqual(gate(db), undefined);
  assert.strictEqual(audits(db).length, 0);
});

ok('enabled + stage + remove; boshqa maydonlar saqlanadi; o\'chirish', async () => {
  const db = makeDb({
    'module_config/wholesale_orders_all': { enabled: false, stage: 'internal', testerIds: [T1, `+${T2}`], note: 'qo\'lda' },
  });
  let r = await set(db, { enabled: true, stage: 'pilot', removeTesterIds: [`${T2.slice(3)}`], reason: 'pilot' });
  assert.deepStrictEqual({ en: r.enabled, s: r.stage, n: r.testerCount, rm: r.removed, c: r.created },
    { en: true, s: 'pilot', n: 1, rm: 1, c: false });
  let g = gate(db);
  assert.deepStrictEqual({ en: g.enabled, s: g.stage, t: g.testerIds, note: g.note },
    { en: true, s: 'pilot', t: [T1], note: 'qo\'lda' });
  assert.strictEqual(g.createdBy, undefined, 'mavjud hujjatga createdBy yozilmaydi');
  r = await set(db, { enabled: false, reason: 'yopamiz' });
  g = gate(db);
  assert.deepStrictEqual({ en: g.enabled, s: g.stage, t: g.testerIds }, { en: false, s: 'pilot', t: [T1] });
  assert.strictEqual(audits(db).length, 2);
});

ok('idempotent: takror chaqiruv — unchanged, ikkinchi yozuv va audit yo\'q', async () => {
  const db = makeDb();
  const req = { enabled: true, stage: 'internal', addTesterIds: [T1], reason: 'ochildi' };
  const r1 = await set(db, req);
  const writes = db.writes;
  const r2 = await set(db, req);
  assert.deepStrictEqual([r1.unchanged, r2.unchanged], [false, true]);
  assert.strictEqual(db.writes, writes, 'takrorda yozuv yo\'q');
  assert.strictEqual(audits(db).length, 1);
  // Mavjud bo'lmagan raqamni olish ham — o'zgarish yo'q.
  const r3 = await set(db, { removeTesterIds: [T2], reason: 'yo\'q raqam' });
  assert.strictEqual(r3.unchanged, true);
  assert.strictEqual(audits(db).length, 1);
});

ok('xom bosqich noma\'lum («beta») — internal deb o\'qiladi; yozuvda kanonik qiymat qo\'yiladi', async () => {
  const db = makeDb({ 'module_config/wholesale_orders_all': { enabled: false, stage: 'beta', testerIds: [] } });
  const g0 = await get(db);
  assert.deepStrictEqual({ s: g0.stage, raw: g0.rawStage }, { s: 'internal', raw: 'beta' });
  const r = await set(db, { stage: 'internal', reason: 'tozalash' });
  assert.strictEqual(r.unchanged, false);
  assert.strictEqual(gate(db).stage, 'internal');
  assert.strictEqual((await set(db, { stage: 'internal', reason: 'tozalash' })).unchanged, true);
});

ok('kvota darvozasi yozilgan hujjatni o\'qiydi: yopiq → internal (faqat tester) → public → off', async () => {
  quiet();
  try {
    const db = makeDb();
    await set(db, { addTesterIds: [T1], reason: 'sinov' });
    await rejects(orders.requireOrdersGate(db, T1), 'unavailable', 'module_disabled');
    await set(db, { enabled: true, reason: 'ichki' });
    config.clearCache();
    assert.deepStrictEqual(await orders.requireOrdersGate(db, T1), { stage: 'internal' });
    await rejects(orders.requireOrdersGate(db, USER), 'unavailable', 'module_internal_only');
    await set(db, { stage: 'public', reason: 'hammaga' });
    assert.deepStrictEqual(await orders.requireOrdersGate(db, USER), { stage: 'public' });
    await set(db, { stage: 'off', reason: 'to\'xtat' });
    await rejects(orders.requireOrdersGate(db, T1), 'unavailable', 'module_internal_only');
    const st = await get(db);
    assert.strictEqual(st.effectiveOpen, false, 'off — yopiq');
  } finally { loud(); }
});

ok('getter: global kill switch (module_config/global.enabled=false) — effectiveOpen false', async () => {
  const db = makeDb({
    'module_config/wholesale_orders_all': { enabled: true, stage: 'public', testerIds: [] },
    'module_config/global': { enabled: false },
  });
  const st = await get(db);
  assert.deepStrictEqual({ en: st.enabled, g: st.globalEnabled, open: st.effectiveOpen }, { en: true, g: false, open: false });
  config.clearCache();
  const db2 = makeDb({ 'module_config/wholesale_orders_all': { enabled: true, stage: 'public', testerIds: [] } });
  assert.strictEqual((await get(db2)).effectiveOpen, true);
});

(async () => {
  for (const t of tests) {
    quiet();
    try {
      await t.fn();
      loud();
      passed += 1;
      console.log(`  OK  ${t.name}`);
    } catch (e) {
      loud();
      console.error(`  XATO ${t.name}\n       ${e.stack || e.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`\n${passed} test o'tdi.`);
})();
