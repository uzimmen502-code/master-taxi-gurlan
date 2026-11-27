/**
 * 13.1.4 + 13.1.5 — konfig, kesh, feature flag va kill switch.
 *
 *   npm --prefix functions_demand run test:config
 *
 * Firestore o'rniga qo'lda yozilgan fake ishlatiladi — emulator kerak emas.
 */
const assert = require('assert');
const cfg = require('../core/config');

let passed = 0;
function ok(name, fn) {
  try {
    const r = fn();
    if (r && typeof r.then === 'function') {
      throw new Error('async test `okAsync` orqali chaqirilishi kerak');
    }
    passed += 1;
    console.log(`  OK  ${name}`);
  } catch (e) {
    console.error(`  XATO ${name}\n       ${e.message}`);
    process.exitCode = 1;
  }
}

const asyncTests = [];
function okAsync(name, fn) {
  asyncTests.push({ name, fn });
}

/** Minimal Firestore fake: `collection(x).doc(y).get()`. */
function fakeDb(docs, opts = {}) {
  let reads = 0;
  return {
    get reads() { return reads; },
    collection(name) {
      return {
        doc(id) {
          return {
            async get() {
              reads += 1;
              if (opts.throwOn && opts.throwOn === id) {
                throw new Error('simulyatsiya: Firestore o\'qilmadi');
              }
              const key = `${name}/${id}`;
              const data = docs[key];
              return { exists: data !== undefined, data: () => data };
            },
          };
        },
      };
    },
  };
}

console.log('deepMerge');
ok('chuqur birlashtirish — tegilmagan maydon standart qoladi', () => {
  const out = cfg.deepMerge(
    { a: 1, nested: { x: 1, y: 2 } },
    { nested: { y: 99 } },
  );
  assert.strictEqual(out.a, 1);
  assert.strictEqual(out.nested.x, 1);
  assert.strictEqual(out.nested.y, 99);
});
ok('massiv butunlay almashtiriladi (to`lqinlar yarim qolmasin)', () => {
  const out = cfg.deepMerge({ waves: [1, 2, 3] }, { waves: [9] });
  assert.deepStrictEqual(out.waves, [9]);
});
ok('null va undefined e`tiborsiz qoldiriladi', () => {
  const out = cfg.deepMerge({ a: 1 }, { a: null, b: undefined });
  assert.strictEqual(out.a, 1);
});

console.log('DEFAULTS sogligi');
ok('koddagi standart qiymatlar o`zi validatsiyadan o`tadi', () => {
  // Agar standart qiymatlarning o'zi nosog'lom bo'lsa, hamma modul buzuq
  // konfig bilan ishga tushardi.
  assert.deepStrictEqual(cfg.validateConfig(cfg.DEFAULTS), []);
});
ok('standart holatda modul O`CHIQ (enabled: false)', () => {
  // Deploy qilingan zahoti hech qanday modul o'zidan ishga tushmasligi SHART.
  assert.strictEqual(cfg.DEFAULTS.enabled, false);
});
ok('standart holatda push O`CHIQ — shadow mode birinchi', () => {
  assert.strictEqual(cfg.DEFAULTS.pushEnabled, false);
  assert.strictEqual(cfg.DEFAULTS.matchingEnabled, true);
});
ok('score vaznlari yig`indisi 1.0', () => {
  const w = cfg.DEFAULTS.weights;
  assert.ok(Math.abs((w.categoryMatch + w.proximity + w.sourceStrength) - 1) < 1e-9);
});
ok('dispatch push limiti yo`q, quote da bor (Т-7)', () => {
  assert.strictEqual(cfg.DEFAULTS.push.dispatch.perDay, 0);
  assert.strictEqual(cfg.DEFAULTS.push.quote.perDay, 20);
  assert.strictEqual(cfg.DEFAULTS.push.quote.perHour, 5);
});
ok('javobgarlik shifti Қ-2 qarori bilan mos', () => {
  const c = cfg.DEFAULTS.liabilityCaps;
  assert.strictEqual(c.unverified, 300000);
  assert.strictEqual(c.passportVerified, 1000000);
  assert.strictEqual(c.fullyVerified, 3000000);
});

console.log('validateConfig');
ok('vazn yig`indisi 1.0 bo`lmasa xato', () => {
  const bad = cfg.deepMerge(cfg.DEFAULTS, { weights: { proximity: 0.9 } });
  const errors = cfg.validateConfig(bad);
  assert.ok(errors.some((e) => /weights/.test(e)), errors.join('; '));
});
ok('minScore 0..1 dan chiqsa xato', () => {
  const bad = cfg.deepMerge(cfg.DEFAULTS, { minScore: 1.5 });
  assert.ok(cfg.validateConfig(bad).some((e) => /minScore/.test(e)));
});
ok('trust chegaralari teskari bo`lsa xato', () => {
  const bad = cfg.deepMerge(cfg.DEFAULTS, { trust: { excludeBelow: 50, firstWaveMin: 40 } });
  assert.ok(cfg.validateConfig(bad).some((e) => /excludeBelow/.test(e)));
});
ok('to`lqinlar tartibsiz bo`lsa xato', () => {
  const bad = cfg.deepMerge(cfg.DEFAULTS, {
    waves: [{ etaMaxMinutes: 12, waitSeconds: 20 }, { etaMaxMinutes: 5, waitSeconds: 20 }],
  });
  assert.ok(cfg.validateConfig(bad).some((e) => /waves\[1\]/.test(e)));
});
ok('bo`sh to`lqin ro`yxati xato', () => {
  const bad = cfg.deepMerge(cfg.DEFAULTS, { waves: [] });
  assert.ok(cfg.validateConfig(bad).some((e) => /waves/.test(e)));
});
ok('tinch soatlar 24/7 bo`lib qolsa xato', () => {
  const bad = cfg.deepMerge(cfg.DEFAULTS, { push: { quietHours: { from: 7, to: 7 } } });
  assert.ok(cfg.validateConfig(bad).some((e) => /quietHours/.test(e)));
});
ok('fairness juda kuchli bo`lsa xato', () => {
  const bad = cfg.deepMerge(cfg.DEFAULTS, { equalizer: { maxShift: 0.5 } });
  assert.ok(cfg.validateConfig(bad).some((e) => /maxShift/.test(e)));
});

console.log('getModuleConfig');
okAsync('hujjat yo`q -> standart qiymatlar', async () => {
  cfg.clearCache();
  const db = fakeDb({});
  const c = await cfg.getModuleConfig(db, 'service', 'xorazm');
  assert.strictEqual(c.minScore, cfg.DEFAULTS.minScore);
  assert.strictEqual(c.enabled, false);
  assert.strictEqual(c.configKey, 'service_xorazm');
});
okAsync('bitta maydon ustiga yozilsa qolgani standart qoladi', async () => {
  cfg.clearCache();
  const db = fakeDb({ 'module_config/service_xorazm': { enabled: true, minScore: 0.5 } });
  const c = await cfg.getModuleConfig(db, 'service', 'xorazm');
  assert.strictEqual(c.enabled, true);
  assert.strictEqual(c.minScore, 0.5);
  assert.strictEqual(c.push.quote.perDay, 20, 'tegilmagan maydon standart qolishi kerak');
  assert.strictEqual(c.trust.initial, 50);
});
okAsync('kesh ishlaydi — ikkinchi chaqiruv Firestore`ga bormaydi', async () => {
  cfg.clearCache();
  const db = fakeDb({ 'module_config/service_xorazm': { enabled: true } });
  await cfg.getModuleConfig(db, 'service', 'xorazm');
  const after1 = db.reads;
  await cfg.getModuleConfig(db, 'service', 'xorazm');
  assert.strictEqual(db.reads, after1, 'ikkinchi chaqiruv keshdan kelishi kerak');
});
okAsync('skipCache keshni chetlab o`tadi', async () => {
  cfg.clearCache();
  const db = fakeDb({ 'module_config/service_xorazm': { enabled: true } });
  await cfg.getModuleConfig(db, 'service', 'xorazm');
  const after1 = db.reads;
  await cfg.getModuleConfig(db, 'service', 'xorazm', { skipCache: true });
  assert.strictEqual(db.reads, after1 + 1);
});
okAsync('kesh muddati 60 soniya (13.1.4 qabul mezoni)', async () => {
  assert.strictEqual(cfg.CACHE_TTL_MS, 60000);
});
okAsync('Firestore o`qilmasa push MAJBURAN o`chadi', async () => {
  cfg.clearCache();
  const db = fakeDb({}, { throwOn: 'service_xorazm' });
  const c = await cfg.getModuleConfig(db, 'service', 'xorazm');
  assert.strictEqual(c.pushEnabled, false, 'noma`lum holatda push yuborilmasligi kerak');
  assert.strictEqual(c.minScore, cfg.DEFAULTS.minScore, 'qolgani standart bilan davom etadi');
});
okAsync('nosoglom konfig xatolari hujjatga yoziladi, yadro to`xtamaydi', async () => {
  cfg.clearCache();
  const db = fakeDb({
    'module_config/service_xorazm': { enabled: true, weights: { proximity: 0.9 } },
  });
  const c = await cfg.getModuleConfig(db, 'service', 'xorazm');
  assert.ok(Array.isArray(c.configErrors) && c.configErrors.length > 0);
  assert.strictEqual(c.enabled, true, 'xato bo`lsa ham ishlashda davom etadi');
});

console.log('resolveFlags — KILL SWITCH');
okAsync('global o`chiq bo`lsa modul `enabled: true` bo`lsa ham ishlamaydi', async () => {
  cfg.clearCache();
  const db = fakeDb({
    'module_config/global': { enabled: false, reason: 'incident 2026-10-03' },
    'module_config/service_xorazm': { enabled: true, pushEnabled: true },
  });
  const f = await cfg.resolveFlags(db, 'service', 'xorazm');
  assert.strictEqual(f.enabled, false, 'global kalit kuchliroq bo`lishi SHART');
  assert.strictEqual(f.killReason, 'incident 2026-10-03');
});
okAsync('global pushEnabled: false -> modul push`i o`chadi', async () => {
  cfg.clearCache();
  const db = fakeDb({
    'module_config/global': { pushEnabled: false },
    'module_config/service_xorazm': { enabled: true, pushEnabled: true },
  });
  const f = await cfg.resolveFlags(db, 'service', 'xorazm');
  assert.strictEqual(f.enabled, true);
  assert.strictEqual(f.pushEnabled, false);
});
okAsync('global hujjat yo`q -> ruxsat beruvchi standart', async () => {
  cfg.clearCache();
  const db = fakeDb({ 'module_config/service_xorazm': { enabled: true, pushEnabled: true } });
  const f = await cfg.resolveFlags(db, 'service', 'xorazm');
  assert.strictEqual(f.enabled, true);
  assert.strictEqual(f.pushEnabled, true);
});
okAsync('modul hujjati yo`q -> O`CHIQ (ataylab)', async () => {
  cfg.clearCache();
  const db = fakeDb({ 'module_config/global': { enabled: true } });
  const f = await cfg.resolveFlags(db, 'service', 'xorazm');
  assert.strictEqual(f.enabled, false, 'konfig yozilmagan modul o`zidan ishga tushmasligi kerak');
});
okAsync('SHADOW MODE: matching ishlaydi, push ishlamaydi', async () => {
  cfg.clearCache();
  const db = fakeDb({
    'module_config/service_xorazm': { enabled: true, matchingEnabled: true, pushEnabled: false },
  });
  const f = await cfg.resolveFlags(db, 'service', 'xorazm');
  assert.strictEqual(f.enabled, true);
  assert.strictEqual(f.matchingEnabled, true);
  assert.strictEqual(f.pushEnabled, false);
});

(async () => {
  for (const t of asyncTests) {
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
