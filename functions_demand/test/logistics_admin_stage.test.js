/**
 * AVA Logistics - admin: ishga tushirish bosqichi va sinovchilar (D8, ega qarori 2026-10-16).
 *
 *   node functions_demand/test/logistics_admin_stage.test.js
 *
 * `adminSetLogisticsStage` - `tools/set_logistics_stage.js` ning callable shakli:
 * faqat admin/superadmin (dispatcher EMAS), `module_config/logistics_all.logistics.
 * {stage,testerIds}` ni yangilaydi (boshqa kalitlar tegilmaydi), `logistics_audit`ga
 * yozadi, telefonlarni javobga/jurnalga CHIQARMAYDI. Takror chaqiruv - audit yo'q.
 *
 * Qulflanadi:
 *   - huquq: user / dispatcher / token yo'q -> rad
 *   - tekshiruv: noma'lum stage, noto'g'ri telefon, testerIds + add/remove aralashmasi, chegara
 *   - yozuv: kanonik telefon, takrorsiz, boshqa maydonlar saqlanadi, audit (from/to/added/removed/by/reason)
 *   - idempotent: o'zgarish yo'q -> unchanged, audit yo'q
 *   - OFF/PILOT/INTERNAL/PUBLIC xatti-harakati (getLogisticsAccess orqali)
 */
const assert = require('assert');
const api = require('../api/logistics');
const config = require('../core/config');
const tariffCore = require('../core/tariff');
const {
  OWNER, K1, ADMIN, ctx, makeDb, seed,
} = require('./helpers/logistics_harness');

const DISPATCHER = '998908880008';
const STRANGER = '998907770007';

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

function fresh(logistics = { stage: 'internal', testerIds: [] }, extra = {}) {
  config.clearCache(); tariffCore.clearCache();
  return makeDb(seed({
    'module_config/logistics_all': { enabled: true, matchingEnabled: true, pushEnabled: false, logistics },
    [`users/${DISPATCHER}`]: { role: 'dispatcher' },
    [`users/${STRANGER}`]: { role: 'user' },
    ...extra,
  }));
}
const call = (db, data, who = ADMIN) => api.makeAdminSetLogisticsStage({ db })(data, who ? ctx(who) : {});
const cfgOf = (db) => db.dump('module_config')['logistics_all'];
const audits = (db) => Object.values(db.dump('logistics_audit')).filter((a) => a.kind === 'stage_update');
const rejects = (p, code, reason) => assert.rejects(p, (e) => {
  assert.strictEqual(e.code, code, `kod ${e.code}: ${e.message}`);
  if (reason) assert.strictEqual(e.details && e.details.reason, reason, `sabab ${JSON.stringify(e.details)}`);
  return true;
});

ok('huquq: token yo\'q / oddiy foydalanuvchi / dispatcher - rad (stage butun xizmatni ochadi)', async () => {
  const db = fresh();
  await rejects(call(db, { stage: 'public' }, null), 'unauthenticated');
  await rejects(call(db, { stage: 'public' }, STRANGER), 'permission-denied');
  await rejects(call(db, { stage: 'public' }, DISPATCHER), 'permission-denied');
  assert.strictEqual(cfgOf(db).logistics.stage, 'internal', 'rad etilganlar yozmadi');
  assert.strictEqual(audits(db).length, 0);
});

ok('tekshiruv: noma\'lum stage, hech narsa berilmagan, noto\'g\'ri telefon, aralash argumentlar, chegara', async () => {
  const db = fresh();
  await rejects(call(db, { stage: 'beta' }), 'invalid-argument', 'stage_invalid');
  await rejects(call(db, { stage: 'PUBLIC' }), 'invalid-argument', 'stage_invalid');
  await rejects(call(db, { reason: 'bo\'sh' }), 'invalid-argument', 'nothing_to_change');
  await rejects(call(db, { addTesterIds: ['123'] }), 'invalid-argument', 'tester_invalid');
  await rejects(call(db, { addTesterIds: 'x' }), 'invalid-argument', 'tester_invalid');
  await rejects(call(db, { testerIds: [OWNER], addTesterIds: [K1] }), 'invalid-argument', 'tester_args_conflict');
  const many = Array.from({ length: 501 }, (_, i) => `99890${String(1000000 + i)}`);
  await rejects(call(db, { testerIds: many }), 'invalid-argument', 'testers_limit');
  assert.deepStrictEqual(cfgOf(db).logistics, { stage: 'internal', testerIds: [] });
  assert.strictEqual(audits(db).length, 0);
});

ok('modul hujjati yo\'q (set_logistics_stage.js kabi) - failed-precondition, hujjat YARATILMAYDI', async () => {
  config.clearCache();
  const db = makeDb(seed());
  db.docs.delete('module_config/logistics_all');
  await rejects(call(db, { stage: 'pilot' }), 'failed-precondition', 'module_config_missing');
  assert.strictEqual(db.dump('module_config')['logistics_all'], undefined);
});

ok('yozuv: stage + sinovchilar (kanonik, takrorsiz); boshqa maydonlar saqlanadi; audit; javobda telefon YO\'Q', async () => {
  const db = fresh({ stage: 'internal', testerIds: [], legTtlMinutes: 4320 });
  const r = await call(db, {
    stage: 'pilot', addTesterIds: ['+998 90 111 00 01', '902220002', OWNER, ' '], reason: 'pilot boshlandi',
  });
  const logistics = cfgOf(db).logistics;
  assert.strictEqual(logistics.stage, 'pilot');
  assert.deepStrictEqual(logistics.testerIds, [OWNER, K1], 'kanonik 12 xonali, takrorsiz');
  assert.strictEqual(logistics.legTtlMinutes, 4320, 'boshqa logistics kalitlari tegilmadi');
  assert.strictEqual(cfgOf(db).enabled, true, 'enabled tegilmadi');
  assert.strictEqual(cfgOf(db).updatedBy, ADMIN);
  assert.deepStrictEqual({ ok: r.ok, stage: r.stage, n: r.testerCount, u: r.unchanged, a: r.added, rm: r.removed },
    { ok: true, stage: 'pilot', n: 2, u: false, a: 2, rm: 0 });
  assert.ok(!JSON.stringify(r).includes(OWNER) && !JSON.stringify(r).includes(K1), 'javobda telefon yo\'q');
  const a = audits(db);
  assert.strictEqual(a.length, 1);
  assert.deepStrictEqual({ f: a[0].from, t: a[0].to, ad: a[0].added, rm: a[0].removed, by: a[0].by, r: a[0].reason },
    { f: { stage: 'internal', testerCount: 0 }, t: { stage: 'pilot', testerCount: 2 }, ad: 2, rm: 0, by: ADMIN, r: 'pilot boshlandi' });
  assert.ok(!JSON.stringify(a[0]).includes(OWNER), 'auditda telefon yo\'q (40-band)');
});

ok('idempotent: o\'zgarish yo\'q -> unchanged, audit qo\'shilmaydi', async () => {
  const db = fresh({ stage: 'pilot', testerIds: [OWNER, K1] });
  const r = await call(db, { stage: 'pilot', addTesterIds: [K1], removeTesterIds: [STRANGER] });
  assert.deepStrictEqual({ u: r.unchanged, n: r.testerCount }, { u: true, n: 2 });
  assert.strictEqual(audits(db).length, 0);
});

ok('remove va to\'liq almashtirish (testerIds); bo\'sh ro\'yxat ham mumkin', async () => {
  const db = fresh({ stage: 'internal', testerIds: [OWNER, K1] });
  let r = await call(db, { removeTesterIds: [`+${OWNER}`] });
  assert.deepStrictEqual(cfgOf(db).logistics.testerIds, [K1]);
  assert.strictEqual(r.removed, 1);
  r = await call(db, { testerIds: [OWNER, STRANGER] });
  assert.deepStrictEqual(cfgOf(db).logistics.testerIds, [OWNER, STRANGER]);
  assert.deepStrictEqual({ a: r.added, rm: r.removed }, { a: 2, rm: 1 });
  await call(db, { testerIds: [] });
  assert.deepStrictEqual(cfgOf(db).logistics.testerIds, []);
  assert.strictEqual(audits(db).length, 3);
});

ok('bosqich amalda: OFF/INTERNAL/PILOT/PUBLIC getLogisticsAccess orqali (sinovchi OWNER, begona STRANGER)', async () => {
  const db = fresh({ stage: 'internal', testerIds: [OWNER] });
  const acc = async (who) => api.makeGetLogisticsAccess({ db })({}, ctx(who));
  const expect = {
    off: [false, false], internal: [true, false], pilot: [true, false], public: [true, true],
  };
  for (const [stage, [tester, other]] of Object.entries(expect)) {
    config.clearCache();
    await call(db, { stage });
    assert.deepStrictEqual(await acc(OWNER), { allowed: tester, stage }, `${stage}: sinovchi`);
    assert.deepStrictEqual(await acc(STRANGER), { allowed: other, stage }, `${stage}: begona`);
  }
});

(async () => {
  for (const t of tests) {
    try { await t.fn(); passed += 1; console.log(`  OK  ${t.name}`); } catch (e) {
      console.error(`  XATO ${t.name}\n       ${e.stack || e.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`\n${passed} test o'tdi.`);
})();
