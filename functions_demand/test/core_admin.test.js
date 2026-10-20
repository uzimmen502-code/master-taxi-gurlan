/**
 * «Талаб ядроси» админ қоидалари — тоза функциялар (Фирестор йўқ).
 *
 *   node functions_demand/test/core_admin.test.js
 *
 * Эга қарорлари: вариант А (ҳудуд таклифчи >= N=5 бўлганда ёқилади),
 * вариант 3 (push чегараси ўлчаб қўйилмагунча push ёқилмайди).
 */
const assert = require('assert');
const ca = require('../core/core_admin');
const { DEFAULTS } = require('../core/config');

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

const REGIONS = ['xorazm', 'toshkent_shahri', 'andijon'];
const bad = (data, code, re) => {
  assert.throws(
    () => ca.parseSetRequest(data, REGIONS),
    (e) => e.code === code && (!re || re.test(e.message)),
    JSON.stringify(data),
  );
};

console.log('presetFor / stateOf');
ok('off: hamma yopiq', () => {
  assert.deepStrictEqual(ca.presetFor('off'), {
    enabled: false, matchingEnabled: false, pushEnabled: false,
  });
});
ok('shadow: matching bor, push YO\'Q', () => {
  assert.deepStrictEqual(ca.presetFor('shadow'), {
    enabled: true, matchingEnabled: true, pushEnabled: false,
  });
});
ok('push: hammasi yoqiq', () => {
  assert.deepStrictEqual(ca.presetFor('push'), {
    enabled: true, matchingEnabled: true, pushEnabled: true,
  });
});
ok('noma`lum holat -> xato', () => {
  assert.throws(() => ca.presetFor('boshqa'), /holat/);
});
ok('stateOf: konfig hujjatsiz -> off (DEFAULTS.enabled=false)', () => {
  assert.strictEqual(ca.stateOf({}, DEFAULTS), 'off');
});
ok('stateOf: preset -> holat (aylanma)', () => {
  for (const s of ca.STATES) {
    const cfg = { ...DEFAULTS, ...ca.presetFor(s) };
    assert.strictEqual(ca.stateOf({}, cfg), s, s);
  }
});
ok('stateOf: global kill (enabled:false) modul yoqiq bo`lsa ham -> off', () => {
  const cfg = { ...DEFAULTS, ...ca.presetFor('push') };
  assert.strictEqual(ca.stateOf({ enabled: false }, cfg), 'off');
});
ok('stateOf: global pushEnabled:false -> push emas, shadow', () => {
  const cfg = { ...DEFAULTS, ...ca.presetFor('push') };
  assert.strictEqual(ca.stateOf({ pushEnabled: false }, cfg), 'shadow');
});
ok('stateOf: yoqiq lekin matching o`chiq -> matching_off (noaniq holat yashirilmaydi)', () => {
  const cfg = { ...DEFAULTS, enabled: true, matchingEnabled: false, pushEnabled: true };
  assert.strictEqual(ca.stateOf({}, cfg), 'matching_off');
});

console.log('parseSetRequest');
ok('holat: to`g`ri so`rov', () => {
  assert.deepStrictEqual(
    ca.parseSetRequest({ module: 'service', regionId: 'xorazm', state: 'shadow' }, REGIONS),
    { module: 'service', regionId: 'xorazm', state: 'shadow', minScore: { set: false, value: null } },
  );
});
ok('`_` li hudud ID (toshkent_shahri) qabul qilinadi', () => {
  const r = ca.parseSetRequest({ module: 'service', regionId: 'toshkent_shahri', state: 'off' }, REGIONS);
  assert.strictEqual(r.regionId, 'toshkent_shahri');
});
ok('holat uchun `all` RAD (variant A: hudud bo`yicha)', () => {
  bad({ module: 'service', regionId: 'all', state: 'shadow' }, 'invalid-argument', /hudud/i);
});
ok('noma`lum hudud RAD (geo_regions da yo`q)', () => {
  bad({ module: 'service', regionId: 'atlantida', state: 'shadow' }, 'invalid-argument');
});
ok('noma`lum modul va boshqaruvga berilmagan modul RAD', () => {
  bad({ module: 'nonsense', regionId: 'xorazm', state: 'off' }, 'invalid-argument');
  bad({ module: 'logistics', regionId: 'xorazm', state: 'off' }, 'invalid-argument');
});
ok('noma`lum holat RAD', () => {
  bad({ module: 'service', regionId: 'xorazm', state: 'turbo' }, 'invalid-argument');
});
ok('na holat, na minScore -> RAD (bo`sh so`rov)', () => {
  bad({ module: 'service', regionId: 'xorazm' }, 'invalid-argument');
});
ok('minScore: `all` va hudud uchun ruxsat; qiymat 0.01..1 yoki null', () => {
  const a = ca.parseSetRequest({ module: 'service', regionId: 'all', minScore: 0.75 }, REGIONS);
  assert.deepStrictEqual(a.minScore, { set: true, value: 0.75 });
  assert.strictEqual(a.state, null);
  const b = ca.parseSetRequest({ module: 'service', regionId: 'xorazm', minScore: null }, REGIONS);
  assert.deepStrictEqual(b.minScore, { set: true, value: null });
});
ok('minScore noto`g`ri qiymatlar RAD: 0, 90 (foiz), manfiy, matn, NaN', () => {
  for (const v of [0, 90, 1.01, -0.2, 'yuqori', NaN, Infinity]) {
    bad({ module: 'service', regionId: 'all', minScore: v }, 'invalid-argument', /minScore/);
  }
});
ok('minScore uchun hudud majburiy', () => {
  bad({ module: 'service', minScore: 0.7 }, 'invalid-argument');
});
ok('maydonlar tip tekshiruvi: regionId/module matn bo`lishi shart', () => {
  bad({ module: 5, regionId: 'xorazm', state: 'off' }, 'invalid-argument');
  bad({ module: 'service', regionId: ['xorazm'], state: 'off' }, 'invalid-argument');
  bad(null, 'invalid-argument');
});
ok('ortiqcha (noma`lum) maydonlar RAD — klient o`zboshimcha maydon yubormasin', () => {
  bad({ module: 'service', regionId: 'xorazm', state: 'off', enabled: true }, 'invalid-argument', /enabled/);
});

console.log('checkEnable');
const base = {
  mode: 'quote', providers: 5, minProviders: 5, effectiveMinScore: 0.75,
};
ok('off har doim mumkin (taklifchi 0 bo`lsa ham)', () => {
  assert.strictEqual(ca.checkEnable({ ...base, state: 'off', providers: 0, effectiveMinScore: null }).ok, true);
});
ok('shadow: taklifchi N dan kam -> RAD (not_enough_providers)', () => {
  const r = ca.checkEnable({ ...base, state: 'shadow', providers: 4 });
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.reason, 'not_enough_providers');
  assert.ok(/4/.test(r.message) && /5/.test(r.message), r.message);
});
ok('shadow: aynan N (5) -> mumkin; kalibrovka shart emas', () => {
  assert.strictEqual(ca.checkEnable({ ...base, state: 'shadow', effectiveMinScore: null }).ok, true);
});
ok('push: quote rejimida chegara null -> RAD (min_score_not_calibrated)', () => {
  const r = ca.checkEnable({ ...base, state: 'push', effectiveMinScore: null });
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.reason, 'min_score_not_calibrated');
});
ok('push: chegara bor va taklifchi yetarli -> mumkin', () => {
  assert.strictEqual(ca.checkEnable({ ...base, state: 'push' }).ok, true);
});
ok('push: dispatch (kuryer) rejimida kalibrovka kerak emas', () => {
  assert.strictEqual(
    ca.checkEnable({ ...base, state: 'push', mode: 'dispatch', effectiveMinScore: null }).ok,
    true,
  );
});
ok('push: avval taklifchi sonini tekshiradi (sabab tartibi)', () => {
  const r = ca.checkEnable({ ...base, state: 'push', providers: 1, effectiveMinScore: null });
  assert.strictEqual(r.reason, 'not_enough_providers');
});
ok('minProviders noto`g`ri bo`lsa xato (0, kasr, NaN)', () => {
  for (const v of [0, 1.5, NaN, undefined]) {
    assert.throws(() => ca.checkEnable({ ...base, state: 'shadow', minProviders: v }), /minProviders/);
  }
});

console.log('effectiveMinScore (core/config.deepMerge bilan bir xil qoida)');
ok('hudud hujjatidagi son `_all` dagidan ustun', () => {
  assert.strictEqual(ca.effectiveMinScore({ push: { minScore: 0.8 } }, { push: { minScore: 0.7 } }), 0.8);
});
ok('hududda yo`q -> `_all` dagi son', () => {
  assert.strictEqual(ca.effectiveMinScore({}, { push: { minScore: 0.7 } }), 0.7);
  assert.strictEqual(ca.effectiveMinScore(null, { push: { minScore: 0.7 } }), 0.7);
});
ok('hududdagi null `_all` dagi sonni BEKOR QILMAYDI (core qoidasi)', () => {
  assert.strictEqual(ca.effectiveMinScore({ push: { minScore: null } }, { push: { minScore: 0.7 } }), 0.7);
});
ok('ikkalasida yo`q -> null', () => {
  assert.strictEqual(ca.effectiveMinScore({}, {}), null);
  assert.strictEqual(ca.effectiveMinScore(undefined, undefined), null);
});
ok('yaroqsiz qiymat (matn) e`tiborga olinmaydi', () => {
  assert.strictEqual(ca.effectiveMinScore({ push: { minScore: 'x' } }, {}), null);
});

console.log('maskActor');
ok('telefon niqoblanadi (40-band)', () => {
  assert.strictEqual(ca.maskActor('998901234567'), '9989012****67');
  assert.strictEqual(ca.maskActor(''), '');
  assert.strictEqual(ca.maskActor('abc'), '***');
});

console.log('DEFAULTS.enableMinProviders');
ok('standart N = 5 (ega 2026-10-20)', () => {
  assert.strictEqual(DEFAULTS.enableMinProviders, 5);
});

console.log(`\n${passed} test o'tdi.`);
