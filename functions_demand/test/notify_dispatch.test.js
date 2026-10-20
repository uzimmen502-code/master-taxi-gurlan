/**
 * dispatchNotifications — «кимнинг телефони жиринглайди» + ҳар мослик учун
 * push чегараси (push.minScore, ега 2026-10-20, вариант 3) + shadow mode ҳисоби.
 *
 *   node functions_demand/test/notify_dispatch.test.js
 *
 * Firestore ва FCM ўрнига fake: ҳақиқий push юборилмайди.
 */
const assert = require('assert');
const { FakeFirestore } = require('./fake_firestore');
const { makeDispatchNotifications } = require('../notify/dispatch');
const { DEFAULTS, deepMerge } = require('../core/config');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const calibrated = deepMerge(DEFAULTS, { push: { minScore: 0.7 } });

const P_HIGH = '998901111111'; // score 0.79 — чегарадан юқори
const P_LOW = '998902222222'; // score 0.62 — чегарадан паст

function mkDb() {
  return new FakeFirestore({
    [`users/${P_HIGH}/fcm_tokens/tokH`]: { token: 'tokH' },
    [`users/${P_LOW}/fcm_tokens/tokL`]: { token: 'tokL' },
  });
}

function mkMessaging() {
  const calls = [];
  return {
    calls,
    async sendEach(msgs) {
      calls.push(msgs.map((m) => m.token));
      return { responses: msgs.map(() => ({ success: true })) };
    },
  };
}

function mkDemand(over = {}) {
  return {
    id: 'Dem1AAAAAAAAAAAAAAAA0001',
    mode: 'quote',
    module: 'service',
    categoryId: null,
    location: { districtId: 'urganch_shahri' },
    media: {},
    ...over,
  };
}

function ranked(over = {}) {
  return [
    {
      providerId: P_HIGH, finalScore: 0.79, metrics: {}, candidate: { consentGiven: true, ...over.high },
    },
    {
      providerId: P_LOW, finalScore: 0.62, metrics: {}, candidate: { consentGiven: true, ...over.low },
    },
  ];
}

function run({ db, messaging, demand, list, flags, config }) {
  const dispatch = makeDispatchNotifications({
    db, messaging, keywordIndex: { categoryById: new Map() },
  });
  return dispatch(db, demand, { ranked: list }, { flags, config });
}

ok('чегарадан юқори мослик push олади, паст — олмайди', async () => {
  const db = mkDb(); const messaging = mkMessaging();
  const s = await run({
    db, messaging, demand: mkDemand(), list: ranked(),
    flags: { pushEnabled: true }, config: calibrated,
  });
  assert.strictEqual(s.sent, 1);
  assert.deepStrictEqual(messaging.calls, [['tokH']]);
  assert.strictEqual(s.reasons.below_min_score, 1);
  assert.strictEqual(s.reasons.send, 1);
});

ok('паст мослик дайжестга ҳам тушмайди (рўйхатда кўринади, push йўқ)', async () => {
  const db = mkDb();
  await run({
    db, messaging: mkMessaging(), demand: mkDemand(), list: ranked(),
    flags: { pushEnabled: true }, config: calibrated,
  });
  assert.strictEqual(db.docs.has(`demand_digest_queue/${P_LOW}`), false);
});

ok('калибровкасиз (minScore: null) ҳеч кимга push кетмайди', async () => {
  const db = mkDb(); const messaging = mkMessaging();
  const s = await run({
    db, messaging, demand: mkDemand(), list: ranked(),
    flags: { pushEnabled: true }, config: DEFAULTS,
  });
  assert.strictEqual(s.sent, 0);
  assert.strictEqual(messaging.calls.length, 0);
  assert.strictEqual(s.reasons.score_not_calibrated, 2);
});

ok('SHADOW (push ўчиқ): ҳеч нарса юборилмайди, лекин «ким олар эди» ҳисобланади', async () => {
  const db = mkDb(); const messaging = mkMessaging();
  const demand = mkDemand();
  const s = await run({
    db, messaging, demand, list: ranked(),
    flags: { pushEnabled: false }, config: calibrated,
  });
  assert.strictEqual(messaging.calls.length, 0, 'shadow режимда ҳақиқий push йўқ');
  assert.strictEqual(s.sent, 0);
  assert.strictEqual(s.reasons.send, 1, 'чегарадан ўтган битта — «юборилиши керак эди»');
  assert.strictEqual(s.reasons.below_min_score, 1);
  const stats = db.docs.get(`demands/${demand.id}/private/stats`);
  assert.strictEqual(stats.push.eligible, 1, 'pushEligible shadow`да ҳам ҳисобланади');
});

ok('SHADOW: журнал sent:false (кейинги ҳақиқий push’ни тўсмайди)', async () => {
  const db = mkDb();
  const demand = mkDemand();
  await run({
    db, messaging: mkMessaging(), demand, list: ranked(),
    flags: { pushEnabled: false }, config: calibrated,
  });
  const log = db.docs.get(`demand_push_log/${demand.id}_${P_HIGH}`);
  assert.strictEqual(log.sent, false);
  assert.strictEqual(log.reason, 'shadow_mode');
  assert.strictEqual(db.docs.has(`demand_push_log/${demand.id}_${P_LOW}`), false);
});

ok('SHADOW: дайжест навбатига ёзилмайди, ҳақиқий режимда ёзилади', async () => {
  const digestOnly = { high: { digestOnly: true } };
  const dbShadow = mkDb();
  await run({
    db: dbShadow, messaging: mkMessaging(), demand: mkDemand(), list: ranked(digestOnly),
    flags: { pushEnabled: false }, config: calibrated,
  });
  assert.strictEqual(dbShadow.docs.has(`demand_digest_queue/${P_HIGH}`), false);

  const dbLive = mkDb();
  await run({
    db: dbLive, messaging: mkMessaging(), demand: mkDemand(), list: ranked(digestOnly),
    flags: { pushEnabled: true }, config: calibrated,
  });
  assert.strictEqual(dbLive.docs.has(`demand_digest_queue/${P_HIGH}`), true);
});

ok('иккинчи чақирув такрорий push юбормайди (идемпотентлик)', async () => {
  const db = mkDb(); const messaging = mkMessaging();
  const args = {
    db, messaging, demand: mkDemand(), list: ranked(),
    flags: { pushEnabled: true }, config: calibrated,
  };
  await run(args);
  const s2 = await run(args);
  assert.strictEqual(messaging.calls.length, 1, 'биринчисидан кейин қайта юборилмайди');
  assert.strictEqual(s2.sent, 0);
});

ok('розилик бермаган номзод push олмайди (чегарадан юқори бўлса ҳам)', async () => {
  const db = mkDb(); const messaging = mkMessaging();
  const s = await run({
    db, messaging, demand: mkDemand(),
    list: ranked({ high: { consentGiven: false } }),
    flags: { pushEnabled: true }, config: calibrated,
  });
  assert.strictEqual(messaging.calls.length, 0);
  assert.strictEqual(s.reasons.no_consent, 1);
});

ok('dispatch (курьер) чегарага ва калибровкага боғлиқ эмас', async () => {
  const db = mkDb(); const messaging = mkMessaging();
  const s = await run({
    db, messaging, demand: mkDemand({ mode: 'dispatch', module: 'courier' }),
    list: [{ providerId: P_LOW, finalScore: 0.1, metrics: {}, candidate: { consentGiven: true } }],
    flags: { pushEnabled: true }, config: DEFAULTS,
  });
  assert.strictEqual(s.sent, 1, 'паст score ва minScore:null — курьерга барибир push');
  assert.deepStrictEqual(messaging.calls, [['tokL']]);
});

ok('push ёқиқ + глобал kill (flags.pushEnabled:false) — юборилмайди', async () => {
  const db = mkDb(); const messaging = mkMessaging();
  await run({
    db, messaging, demand: mkDemand(), list: ranked(),
    flags: { pushEnabled: false }, config: calibrated,
  });
  assert.strictEqual(messaging.calls.length, 0);
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
