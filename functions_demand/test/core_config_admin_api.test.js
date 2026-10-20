/**
 * «Талаб ядроси» админ callable'лари: `adminSetCoreConfig`, `adminGetCoreOverview`.
 *
 *   node functions_demand/test/core_config_admin_api.test.js
 *
 * Эга қарорлари (2026-10-20): вариант А (ҳудуд бўйича, таклифчи >= 5),
 * вариант 3 (push чегараси ўлчаб қўйилмагунча push ёқилмайди), ҳар амал
 * аудитга тушади (41-банд). Фирестор — fake (ёзишдан кейин ўқиш хато).
 */
const assert = require('assert');
const { FakeFirestore } = require('./fake_firestore');
const api = require('../api/core_config_admin');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const ADMIN = '998909990000';
const SUPER = '998909990001';
const DISP = '998909990002';
const USER = '998909990003';
const NOW = new Date('2026-10-20T10:00:00.000Z');
const ctx = (phone) => ({ auth: { token: { phone_number: `+${phone}` } } });

function makeDb(seed = {}) {
  const db = new FakeFirestore({
    [`users/${ADMIN}`]: { role: 'admin' },
    [`users/${SUPER}`]: { role: 'superadmin' },
    [`users/${DISP}`]: { role: 'dispatcher' },
    [`users/${USER}`]: { role: 'user' },
    'geo_regions/xorazm': { name: 'Xorazm', nameUz: 'Хоразм', order: 14 },
    'geo_regions/toshkent_shahri': { name: 'Toshkent shahri', nameUz: 'Тошкент шаҳри', order: 12 },
    'geo_regions/andijon': { name: 'Andijon', nameUz: 'Андижон', order: 1 },
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
      delete: (ref) => { tx._ops.push(() => ref.delete()); },
      _ops: [],
    };
    const out = await fn(tx);
    for (const op of tx._ops) await op();
    return out;
  };
  return db;
}

/** n та ишлай оладиган хизмат таклифчиси шу ҳудудда. */
function providers(n, regionId = 'xorazm', prefix = 'acc') {
  const out = {};
  for (let i = 0; i < n; i += 1) {
    out[`provider_capabilities/${prefix}${regionId}${i}`] = {
      status: { service: 'enabled' },
      service: { active: true, regionIds: [regionId], categoryIds: ['elektrik'] },
    };
  }
  return out;
}

const set = (db, data, who = ADMIN) =>
  api.makeAdminSetCoreConfig({ db, now: () => NOW })(data, ctx(who));
const get = (db, data = {}, who = ADMIN) =>
  api.makeAdminGetCoreOverview({ db, now: () => NOW })(data, ctx(who));
const auditDocs = (db) => Object.values(db.dump('admin_audit'))
  .filter((d) => d.kind === 'core_config_changed');
const cfgOf = (db, key) => db.dump('module_config')[key];
const rejects = (p, code, reason) => assert.rejects(p, (e) => {
  if (e.code !== code) return false;
  return !reason || (e.details && e.details.reason === reason);
});

// ─── ruxsat ───────────────────────────────────────────────────────────
ok('ruxsat: dispatcher, oddiy foydalanuvchi va kirmagan YOZA OLMAYDI', async () => {
  const db = makeDb(providers(5));
  const body = { module: 'service', regionId: 'xorazm', state: 'shadow' };
  await rejects(set(db, body, DISP), 'permission-denied');
  await rejects(set(db, body, USER), 'permission-denied');
  await assert.rejects(
    api.makeAdminSetCoreConfig({ db })(body, { auth: null }),
    (e) => e.code === 'unauthenticated');
  assert.strictEqual(cfgOf(db, 'service_xorazm'), undefined);
  assert.strictEqual(auditDocs(db).length, 0);
});
ok('ruxsat: admin va superadmin yoza oladi', async () => {
  const db = makeDb(providers(5));
  await set(db, { module: 'service', regionId: 'xorazm', state: 'shadow' }, ADMIN);
  await set(db, { module: 'service', regionId: 'xorazm', state: 'off' }, SUPER);
  assert.strictEqual(auditDocs(db).length, 2);
});

// ─── holatni o'zgartirish ─────────────────────────────────────────────
ok('shadow: 5 ta taklifchi bor -> hujjat va audit yoziladi', async () => {
  const db = makeDb(providers(5));
  const r = await set(db, { module: 'service', regionId: 'xorazm', state: 'shadow' });
  assert.strictEqual(r.changed, true);
  assert.strictEqual(r.from.state, 'off');
  assert.strictEqual(r.to.state, 'shadow');
  const c = cfgOf(db, 'service_xorazm');
  assert.strictEqual(c.enabled, true);
  assert.strictEqual(c.matchingEnabled, true);
  assert.strictEqual(c.pushEnabled, false);
  assert.strictEqual(c.updatedBy, ADMIN);
  const [a] = auditDocs(db);
  assert.strictEqual(a.actor, ADMIN);
  assert.strictEqual(a.regionId, 'xorazm');
  assert.strictEqual(a.from.state, 'off');
  assert.strictEqual(a.to.state, 'shadow');
  assert.strictEqual(a.configKey, 'service_xorazm');
});
ok('`_` li hudud: kalit service__toshkent_shahri (yadro o`qiydigan kalit)', async () => {
  const db = makeDb(providers(5, 'toshkent_shahri'));
  await set(db, { module: 'service', regionId: 'toshkent_shahri', state: 'shadow' });
  assert.ok(cfgOf(db, 'service__toshkent_shahri'));
  assert.strictEqual(cfgOf(db, 'service_toshkent_shahri'), undefined);
});
ok('4 ta taklifchi — RAD (not_enough_providers), hech narsa yozilmaydi', async () => {
  const db = makeDb(providers(4));
  await rejects(
    set(db, { module: 'service', regionId: 'xorazm', state: 'shadow' }),
    'failed-precondition', 'not_enough_providers');
  assert.strictEqual(cfgOf(db, 'service_xorazm'), undefined);
  assert.strictEqual(auditDocs(db).length, 0);
});
ok('faqat ISHLAY OLADIGAN taklifchi sanaladi (active:false, status, boshqa hudud emas)', async () => {
  const db = makeDb({
    ...providers(3),
    ...providers(5, 'andijon'), // boshqa hudud
    'provider_capabilities/offA': {
      status: { service: 'enabled' }, service: { active: false, regionIds: ['xorazm'] },
    },
    'provider_capabilities/susA': {
      status: { service: 'suspended' }, service: { active: true, regionIds: ['xorazm'] },
    },
  });
  await rejects(
    set(db, { module: 'service', regionId: 'xorazm', state: 'shadow' }),
    'failed-precondition', 'not_enough_providers');
  // andijonda 5 ta — ruxsat.
  await set(db, { module: 'service', regionId: 'andijon', state: 'shadow' });
  assert.ok(cfgOf(db, 'service_andijon'));
});
ok('push: chegara null -> RAD (min_score_not_calibrated); chegara qo`yilgach ruxsat', async () => {
  const db = makeDb(providers(5));
  await rejects(
    set(db, { module: 'service', regionId: 'xorazm', state: 'push' }),
    'failed-precondition', 'min_score_not_calibrated');
  await set(db, { module: 'service', regionId: 'all', minScore: 0.75 });
  const r = await set(db, { module: 'service', regionId: 'xorazm', state: 'push' });
  assert.strictEqual(r.to.state, 'push');
  assert.strictEqual(cfgOf(db, 'service_xorazm').pushEnabled, true);
});
ok('push: avval taklifchi soni tekshiriladi', async () => {
  const db = makeDb(providers(1));
  await rejects(
    set(db, { module: 'service', regionId: 'xorazm', state: 'push' }),
    'failed-precondition', 'not_enough_providers');
});
ok('off: taklifchi 0 bo`lsa ham mumkin; modul hujjati yopiladi', async () => {
  const db = makeDb({
    ...providers(5),
    'module_config/service_xorazm': { enabled: true, matchingEnabled: true, pushEnabled: false },
  });
  const r = await set(db, { module: 'service', regionId: 'xorazm', state: 'off' });
  assert.strictEqual(r.from.state, 'shadow');
  assert.strictEqual(r.to.state, 'off');
  assert.strictEqual(cfgOf(db, 'service_xorazm').enabled, false);
});
ok('idempotent: bir xil holat qayta -> changed:false, ikkinchi audit YO`Q', async () => {
  const db = makeDb(providers(5));
  await set(db, { module: 'service', regionId: 'xorazm', state: 'shadow' });
  const r = await set(db, { module: 'service', regionId: 'xorazm', state: 'shadow' });
  assert.strictEqual(r.changed, false);
  assert.strictEqual(auditDocs(db).length, 1);
});
ok('matching_off -> shadow: matching qaytadan yoqiladi', async () => {
  const db = makeDb({
    ...providers(5),
    'module_config/service_xorazm': { enabled: true, matchingEnabled: false, pushEnabled: false },
  });
  const r = await set(db, { module: 'service', regionId: 'xorazm', state: 'shadow' });
  assert.strictEqual(r.from.state, 'matching_off');
  assert.strictEqual(cfgOf(db, 'service_xorazm').matchingEnabled, true);
});
ok('merge: hududdagi boshqa maydonlar saqlanadi (masalan minScore override)', async () => {
  const db = makeDb({
    ...providers(5),
    'module_config/service_xorazm': { minScore: 0.5, push: { quote: { perDay: 7 } } },
  });
  await set(db, { module: 'service', regionId: 'xorazm', state: 'shadow' });
  const c = cfgOf(db, 'service_xorazm');
  assert.strictEqual(c.minScore, 0.5);
  assert.strictEqual(c.push.quote.perDay, 7);
});
ok('global kill faol bo`lsa ham yoziladi, lekin globalKill:true haqida ogohlantiriladi', async () => {
  const db = makeDb({
    ...providers(5),
    'module_config/global': { enabled: false, reason: 'incident' },
  });
  const r = await set(db, { module: 'service', regionId: 'xorazm', state: 'shadow' });
  assert.strictEqual(r.globalKill, true);
  assert.strictEqual(r.to.state, 'off', 'global kill modul holatini o`chiq qiladi — yakuniy holat');
});

// ─── push chegarasi ───────────────────────────────────────────────────
ok('minScore `all` ga yoziladi va auditga tushadi', async () => {
  const db = makeDb({});
  const r = await set(db, { module: 'service', regionId: 'all', minScore: 0.75 });
  assert.strictEqual(r.changed, true);
  assert.strictEqual(cfgOf(db, 'service_all').push.minScore, 0.75);
  const [a] = auditDocs(db);
  assert.strictEqual(a.from.minScore, null);
  assert.strictEqual(a.to.minScore, 0.75);
});
ok('minScore: bir xil qiymat qayta -> changed:false', async () => {
  const db = makeDb({});
  await set(db, { module: 'service', regionId: 'all', minScore: 0.75 });
  const r = await set(db, { module: 'service', regionId: 'all', minScore: 0.75 });
  assert.strictEqual(r.changed, false);
  assert.strictEqual(auditDocs(db).length, 1);
});
ok('minScore null chegarani o`chiradi (kalibrovka yo`q holati)', async () => {
  const db = makeDb({});
  await set(db, { module: 'service', regionId: 'all', minScore: 0.75 });
  const r = await set(db, { module: 'service', regionId: 'all', minScore: null });
  assert.strictEqual(r.to.minScore, null);
});
ok('minScore noto`g`ri qiymat RAD: 90 (foiz), 0, matn — hech narsa yozilmaydi', async () => {
  const db = makeDb({});
  for (const v of [90, 0, 'yuqori']) {
    await rejects(set(db, { module: 'service', regionId: 'all', minScore: v }), 'invalid-argument');
  }
  assert.strictEqual(cfgOf(db, 'service_all'), undefined);
  assert.strictEqual(auditDocs(db).length, 0);
});
ok('chegara yo`q bo`lgan holda push yoqilgan hududda chegara o`chirilsa — push o`chmaydi, lekin `core` push yubormaydi', async () => {
  // Konfig o`zgarishi o`zi to`sib qo`ymaydi: policy score_not_calibrated bilan to`xtatadi.
  const db = makeDb({
    ...providers(5),
    'module_config/service_all': { push: { minScore: 0.75 } },
    'module_config/service_xorazm': { enabled: true, matchingEnabled: true, pushEnabled: true },
  });
  const r = await set(db, { module: 'service', regionId: 'all', minScore: null });
  assert.strictEqual(r.changed, true);
});

// ─── validatsiya ──────────────────────────────────────────────────────
ok('noma`lum hudud va `all` + holat RAD (variant A)', async () => {
  const db = makeDb(providers(5));
  await rejects(set(db, { module: 'service', regionId: 'atlantida', state: 'shadow' }), 'invalid-argument');
  await rejects(set(db, { module: 'service', regionId: 'all', state: 'shadow' }), 'invalid-argument');
});
ok('ortiqcha maydon (enabled/pushEnabled) RAD — klient qoidani chetlab o`tmaydi', async () => {
  const db = makeDb(providers(5));
  await rejects(
    set(db, { module: 'service', regionId: 'xorazm', state: 'shadow', pushEnabled: true }),
    'invalid-argument');
});
ok('boshqaruvga berilmagan modul RAD', async () => {
  const db = makeDb(providers(5));
  await rejects(set(db, { module: 'logistics', regionId: 'xorazm', state: 'shadow' }), 'invalid-argument');
});

// ─── ko'rinish ────────────────────────────────────────────────────────
ok('overview: hududlar holati, taklifchilar, tayyorlik', async () => {
  const db = makeDb({
    ...providers(5, 'xorazm'),
    ...providers(2, 'andijon'),
    'module_config/service_xorazm': { enabled: true, matchingEnabled: true, pushEnabled: false },
    'module_config/service_all': { push: { minScore: 0.75 } },
  });
  const r = await get(db);
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.minProviders, 5);
  assert.strictEqual(r.minScoreAll, 0.75);
  const by = Object.fromEntries(r.rows.map((x) => [x.regionId, x]));
  assert.strictEqual(by.xorazm.state, 'shadow');
  assert.strictEqual(by.xorazm.providers, 5);
  assert.strictEqual(by.xorazm.ready, true);
  assert.strictEqual(by.xorazm.minScore, 0.75, 'chegara `_all` dan meros');
  assert.strictEqual(by.andijon.state, 'off');
  assert.strictEqual(by.andijon.providers, 2);
  assert.strictEqual(by.andijon.ready, false);
  assert.strictEqual(by.toshkent_shahri.providers, 0);
  assert.strictEqual(r.rows.length, 3);
});
ok('overview: hududlar `order` bo`yicha, nomlar bor', async () => {
  const r = await get(makeDb({}));
  assert.deepStrictEqual(r.rows.map((x) => x.regionId), ['andijon', 'toshkent_shahri', 'xorazm']);
  assert.ok(r.rows.every((x) => x.name && x.name.length > 0));
});
ok('overview: global kill ko`rsatiladi; holatlar off ko`rinadi', async () => {
  const db = makeDb({
    'module_config/global': { enabled: false, reason: 'incident' },
    'module_config/service_xorazm': { enabled: true, matchingEnabled: true, pushEnabled: true },
  });
  const r = await get(db);
  assert.strictEqual(r.globalKill.active, true);
  assert.strictEqual(r.globalKill.reason, 'incident');
  assert.strictEqual(r.rows.find((x) => x.regionId === 'xorazm').state, 'off');
});
ok('overview: audit — yangisi birinchi, boshqa turdagi yozuv kirmaydi, telefon niqoblangan', async () => {
  const db = makeDb({
    'admin_audit/a1': {
      kind: 'core_config_changed', actor: ADMIN, module: 'service', regionId: 'xorazm',
      from: { state: 'off', minScore: null }, to: { state: 'shadow', minScore: null },
      at: new Date('2026-10-20T09:00:00Z'),
    },
    'admin_audit/a2': {
      kind: 'core_config_changed', actor: SUPER, module: 'service', regionId: 'andijon',
      from: { state: 'off', minScore: null }, to: { state: 'shadow', minScore: null },
      at: new Date('2026-10-20T09:30:00Z'),
    },
    'admin_audit/x': { kind: 'module_config_changed', actor: ADMIN, at: new Date('2026-10-20T09:45:00Z') },
  });
  const r = await get(db);
  assert.deepStrictEqual(r.audit.map((a) => a.id), ['a2', 'a1']);
  assert.strictEqual(r.audit[0].actor, '9989099****01');
  assert.ok(!JSON.stringify(r).includes(SUPER), 'to`liq telefon chiqmasligi kerak');
  assert.ok(!JSON.stringify(r).includes(ADMIN), 'to`liq telefon chiqmasligi kerak');
});
ok('overview: audit 20 tagacha', async () => {
  const seed = {};
  for (let i = 0; i < 30; i += 1) {
    seed[`admin_audit/n${String(i).padStart(2, '0')}`] = {
      kind: 'core_config_changed', actor: ADMIN, module: 'service', regionId: 'xorazm',
      from: { state: 'off', minScore: null }, to: { state: 'shadow', minScore: null },
      at: new Date(Date.UTC(2026, 9, 20, 0, i)),
    };
  }
  const r = await get(makeDb(seed));
  assert.strictEqual(r.audit.length, 20);
  assert.strictEqual(r.audit[0].id, 'n29');
});
ok('overview: dispatcher O`QIY oladi, oddiy foydalanuvchi — yo`q', async () => {
  const db = makeDb({});
  assert.strictEqual((await get(db, {}, DISP)).ok, true);
  await rejects(get(db, {}, USER), 'permission-denied');
});
ok('overview: noma`lum modul RAD', async () => {
  await rejects(get(makeDb({}), { module: 'logistics' }), 'invalid-argument');
});
ok('overview: konfig xatolari ko`rsatiladi (configErrors) va yiqilmaydi', async () => {
  const db = makeDb({
    'module_config/service_xorazm': {
      enabled: true, matchingEnabled: true, pushEnabled: false, weights: { proximity: 0.9 },
    },
  });
  const r = await get(db);
  const row = r.rows.find((x) => x.regionId === 'xorazm');
  assert.ok(Array.isArray(row.configErrors) && row.configErrors.length > 0);
  assert.strictEqual(row.state, 'shadow');
});

(async () => {
  for (const t of tests) {
    try {
      await t.fn();
      passed += 1;
      console.log(`  OK  ${t.name}`);
    } catch (e) {
      console.error(`  XATO ${t.name}\n       ${e.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`\n${passed} test o'tdi.`);
})();
