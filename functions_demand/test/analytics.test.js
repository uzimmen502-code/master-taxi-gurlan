/**
 * 13.5.2 — SHADOW MODE АНАЛИТИКАСИ.
 *
 *   npm --prefix functions_demand run test:analytics
 *
 * Тест эга рўйхатидаги ТЎҚҚИЗ кўрсаткични ва унинг ТЎРТТА саволига
 * жавоб берадиган нисбатларни қулфлайди.
 *
 * Энг муҳим қисм — `pushEligible` shadow mode'да ҲАМ ҳисобланиши
 * (13.5.3): акс ҳолда «push спам бўляптими?» саволига жавоб бериб
 * бўлмасди, ҳамма нол бўлиб кўринарди.
 */
const assert = require('assert');
const { FakeFirestore } = require('./fake_firestore');
const m = require('../analytics/metrics');
const { aggregateDay, recordPushSummary } = require('../analytics/aggregate');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const DAY = '2026-10-03';

/** Toshkent 2026-10-03 12:00 = UTC 07:00. */
function at(hhmm) {
  const [h, mi] = hhmm.split(':').map(Number);
  // Маҳаллий вақтдан UTC'га: -5 соат.
  return new Date(Date.UTC(2026, 9, 3, h - 5, mi, 0));
}

function demand(over = {}) {
  return {
    ownerId: '998901110001',
    module: 'service',
    mode: 'quote',
    status: 'active',
    location: { regionId: 'xorazm', districtId: 'urganch_sh' },
    matching: { state: 'done', matchedBucket: '3-5' },
    assignment: { providerId: null, offerId: null, acceptedAt: null },
    offerCount: 0,
    createdAt: at('12:00'),
    ...over,
  };
}

// ── metrics: sof hisob ────────────────────────────────────────────────

ok('ЭГА РЎЙХАТИДАГИ ТЎҚҚИЗ КЎРСАТКИЧ НОМИ ЎЗГАРМАГАН', () => {
  // Эга рўйхатни аниқ берган — номлар ўзгарса, у ҳисоботда
  // кутганини кўрмайди.
  assert.deepStrictEqual(m.METRIC_NAMES, [
    'demandsCreated',
    'providersMatched',
    'pushEligible',
    'offersReceived',
    'timeToFirstOffer',
    'acceptedOffer',
    'expiredWithoutOffer',
    'completedDemand',
    'cancelledDemand',
  ]);
});

ok('бўш кун — ҳамма нол, нисбатлар null', () => {
  const b = m.emptyBucket();
  const r = m.finalize(b, { date: DAY, module: 'service', regionId: 'xorazm' });
  assert.strictEqual(r.demandsCreated, 0);
  assert.strictEqual(r.precision, null, 'нол бўлувчида null, 0 эмас');
  assert.strictEqual(r.fillRate, null);
  assert.strictEqual(r.timeToFirstOffer.medianSec, null);
});

ok('demandsCreated ва providersMatched', () => {
  const b = m.emptyBucket();
  m.addDemand(b, demand(), { matchedCount: 5 });
  m.addDemand(b, demand(), { matchedCount: 3 });
  const r = m.finalize(b, {});
  assert.strictEqual(r.demandsCreated, 2);
  assert.strictEqual(r.providersMatched, 8);
  assert.strictEqual(r.avgProvidersPerDemand, 4);
});

ok('offersReceived ва fillRate', () => {
  const b = m.emptyBucket();
  m.addDemand(b, demand({ offerCount: 3 }), { matchedCount: 5 });
  m.addDemand(b, demand({ offerCount: 0 }), { matchedCount: 5 });
  const r = m.finalize(b, {});
  assert.strictEqual(r.offersReceived, 3);
  assert.strictEqual(r.fillRate, 0.5, 'иккитадан биттаси таклиф олди');
  assert.strictEqual(r.precision, 0.3, '3 таклиф / 10 мос');
});

ok('timeToFirstOffer — МЕДИАНА, ўртача эмас', () => {
  // Битта узоқ таклиф натижани бузмаслиги керак.
  const b = m.emptyBucket();
  m.addDemand(b, demand({ createdAt: at('12:00'), firstOfferAt: at('12:01'), offerCount: 1 }), {});
  m.addDemand(b, demand({ createdAt: at('12:00'), firstOfferAt: at('12:02'), offerCount: 1 }), {});
  m.addDemand(b, demand({ createdAt: at('12:00'), firstOfferAt: at('20:00'), offerCount: 1 }), {});
  const r = m.finalize(b, {});
  assert.strictEqual(r.timeToFirstOffer.medianSec, 120, 'медиана 2 дақиқа');
  assert.strictEqual(r.timeToFirstOffer.sampleCount, 3);
  assert.ok(r.timeToFirstOffer.p90Sec > 1000, 'p90 узоқ ҳолатни кўрсатади');
});

ok('firstOfferAt йўқ бўлса намунага кирмайди', () => {
  const b = m.emptyBucket();
  m.addDemand(b, demand({ offerCount: 0 }), {});
  const r = m.finalize(b, {});
  assert.strictEqual(r.timeToFirstOffer.sampleCount, 0);
  assert.strictEqual(r.timeToFirstOffer.medianSec, null);
});

ok('acceptedOffer — ТАЙИНЛОВДАН, статусдан ЭМАС', () => {
  // Талаб `accepted` → `in_progress` → `completed` ўтади. Статус
  // бўйича санаш «қабул қилинган» сонини йўқотиб юборарди.
  const b = m.emptyBucket();
  m.addDemand(b, demand({
    status: 'completed',
    assignment: { providerId: '998902220002', offerId: '998902220002', acceptedAt: at('13:00') },
  }), {});
  m.addDemand(b, demand({
    status: 'in_progress',
    assignment: { providerId: '998903330003', offerId: '998903330003', acceptedAt: at('14:00') },
  }), {});
  const r = m.finalize(b, {});
  assert.strictEqual(r.acceptedOffer, 2);
  assert.strictEqual(r.completedDemand, 1);
});

ok('expiredWithoutOffer — ФАҚАТ таклиф келмаганлар', () => {
  const b = m.emptyBucket();
  m.addDemand(b, demand({ status: 'expired', offerCount: 0 }), {});
  m.addDemand(b, demand({ status: 'expired', offerCount: 2 }), {});
  const r = m.finalize(b, {});
  assert.strictEqual(r.expiredWithoutOffer, 1, 'таклиф олгани ҳисобга кирмайди');
});

ok('cancelledDemand', () => {
  const b = m.emptyBucket();
  m.addDemand(b, demand({ status: 'cancelled' }), {});
  assert.strictEqual(m.finalize(b, {}).cancelledDemand, 1);
});

ok('ЭГА 3-САВОЛИ: provider сони кам/кўпми', () => {
  const b = m.emptyBucket();
  m.addDemand(b, demand({ matching: { state: 'no_providers' } }), { matchedCount: 0 });
  m.addDemand(b, demand(), { matchedCount: 4 });
  m.addDemand(b, demand(), { matchedCount: 6 });
  const r = m.finalize(b, {});
  assert.strictEqual(r.noProviders, 1);
  assert.ok(Math.abs(r.noProvidersRate - 0.3333) < 0.001);
  assert.ok(Math.abs(r.avgProvidersPerDemand - 3.3333) < 0.001);
});

ok('ЭГА 2-САВОЛИ: номос provider чиқяптими', () => {
  const b = m.emptyBucket();
  // 10 та мос топилди, фақат 1 таси таклиф берди.
  m.addDemand(b, demand({ offerCount: 1 }), {
    matchedCount: 10,
    rejectReasons: { trust_too_low: 2, out_of_area: 3 },
  });
  const r = m.finalize(b, {});
  assert.strictEqual(r.matchedWithoutOffer, 9);
  assert.strictEqual(r.precision, 0.1, 'precision паст — номос provider белгиси');
  assert.deepStrictEqual(r.rejectReasons, { trust_too_low: 2, out_of_area: 3 });
});

ok('rejectReasons бир нечта талабдан йиғилади', () => {
  const b = m.emptyBucket();
  m.addDemand(b, demand(), { rejectReasons: { self: 1, debt: 2 } });
  m.addDemand(b, demand(), { rejectReasons: { self: 3 } });
  const r = m.finalize(b, {});
  assert.deepStrictEqual(r.rejectReasons, { self: 4, debt: 2 });
});

ok('ЭГА 4-САВОЛИ: push спам бўляптими', () => {
  const b = m.emptyBucket();
  m.addDemand(b, demand(), {
    push: { eligible: 10, sent: 7, digest: 2, noConsent: 1 },
  });
  const r = m.finalize(b, {});
  assert.strictEqual(r.pushEligible, 10);
  assert.strictEqual(r.pushSent, 7);
  assert.strictEqual(r.pushDigest, 2);
  assert.strictEqual(r.pushNoConsent, 1);
  assert.strictEqual(r.pushSentRate, 0.7);
  assert.strictEqual(r.pushPerDemand, 7);
});

ok('Toshkent кун кесими — UTC'.replace("'", ''), () => {
  // Маҳаллий 00:30 (03-окт) → UTC 19:30 (02-окт).
  assert.strictEqual(m.tashkentDateStr(new Date('2026-10-02T19:30:00Z')), '2026-10-03');
  // Маҳаллий 23:30 (03-окт) → UTC 18:30 (03-окт).
  assert.strictEqual(m.tashkentDateStr(new Date('2026-10-03T18:30:00Z')), '2026-10-03');
  // Маҳаллий 00:30 (04-окт) → UTC 19:30 (03-окт).
  assert.strictEqual(m.tashkentDateStr(new Date('2026-10-03T19:30:00Z')), '2026-10-04');
});

ok('кун оралиғи 24 соат ва маҳаллий 00:00 дан бошланади', () => {
  const r = m.tashkentDayRange('2026-10-03');
  assert.strictEqual(r.end.getTime() - r.start.getTime(), 24 * 3600 * 1000);
  assert.strictEqual(m.tashkentDateStr(r.start), '2026-10-03');
  // Оралиқнинг охирги сонияси ҳам ўша кун.
  assert.strictEqual(
    m.tashkentDateStr(new Date(r.end.getTime() - 1000)), '2026-10-03',
  );
});

ok('ҳужжат калити: sana_modul_hudud', () => {
  assert.strictEqual(m.docKey('2026-10-03', 'service', 'xorazm'), '2026-10-03_service_xorazm');
  assert.strictEqual(m.docKey('2026-10-03', 'service', null), '2026-10-03_service_unknown');
});

ok('median ва percentile чегара ҳолатлари', () => {
  assert.strictEqual(m.median([]), null);
  assert.strictEqual(m.median([5]), 5);
  // Жуфт сонда ўртача олинади ва яхлитланади: (2+3)/2 = 2.5 → 3.
  assert.strictEqual(m.median([1, 2, 3, 4]), 3);
  assert.strictEqual(m.median([1, 2, 3, 5]), 3, '(2+3)/2 = 2.5 → 3');
  assert.strictEqual(m.median([10, 20, 30, 40]), 25, '(20+30)/2 = 25');
  assert.strictEqual(m.percentile([], 90), null);
  assert.strictEqual(m.percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 90), 10);
});

// ── aggregateDay: Firestore bilan ─────────────────────────────────────

function dbWith(demands) {
  const seed = {};
  for (const [id, d] of Object.entries(demands)) {
    seed[`demands/${id}`] = d.doc;
    if (d.stats) seed[`demands/${id}/private/stats`] = d.stats;
  }
  return new FakeFirestore(seed);
}

ok('aggregateDay — модул × ҳудуд кесимига бўлади', async () => {
  const db = dbWith({
    d1: { doc: demand({ offerCount: 2 }), stats: { matchedCount: 5 } },
    d2: { doc: demand({ offerCount: 1 }), stats: { matchedCount: 3 } },
    d3: {
      doc: demand({
        module: 'service',
        location: { regionId: 'toshkent_shahri' },
        offerCount: 0,
      }),
      stats: { matchedCount: 1 },
    },
  });

  const r = await aggregateDay({ db, dateStr: DAY });
  assert.strictEqual(r.scanned, 3);
  assert.strictEqual(r.buckets.length, 2, 'иккита ҳудуд = иккита кесим');

  const xorazm = r.buckets.find((b) => b.regionId === 'xorazm');
  assert.strictEqual(xorazm.demandsCreated, 2);
  assert.strictEqual(xorazm.providersMatched, 8);
  assert.strictEqual(xorazm.offersReceived, 3);

  // Ҳужжат ёзилганини текширамиз.
  const written = db.docs.get(`analytics_demand_daily/${DAY}_service_xorazm`);
  assert.ok(written, 'ҳужжат ёзилмади');
  assert.strictEqual(written.date, DAY);
  assert.strictEqual(written.demandsCreated, 2);
});

ok('aggregateDay — dryRun ЁЗМАЙДИ', async () => {
  const db = dbWith({ d1: { doc: demand(), stats: { matchedCount: 2 } } });
  const r = await aggregateDay({ db, dateStr: DAY, dryRun: true });
  assert.strictEqual(r.buckets.length, 1);
  assert.strictEqual(
    Object.keys(db.dump('analytics_demand_daily')).length, 0,
    'dryRun да ҳужжат ёзилмасligi SHART',
  );
});

ok('aggregateDay — кун оралиғидан ташқаридаги талаб олинмайди', async () => {
  const db = dbWith({
    bugun: { doc: demand({ createdAt: at('12:00') }), stats: {} },
    kecha: {
      doc: demand({ createdAt: new Date(Date.UTC(2026, 9, 1, 7, 0)) }),
      stats: {},
    },
  });
  const r = await aggregateDay({ db, dateStr: DAY });
  assert.strictEqual(r.scanned, 1, 'фақат шу кун');
});

ok('aggregateDay — `private/stats` йўқ бўлса йиқилмайди', async () => {
  const db = dbWith({ d1: { doc: demand({ offerCount: 1 }) } });
  const r = await aggregateDay({ db, dateStr: DAY });
  assert.strictEqual(r.scanned, 1);
  assert.strictEqual(r.buckets[0].providersMatched, 0);
  assert.strictEqual(r.buckets[0].offersReceived, 1);
});

ok('aggregateDay — бўш кун ҳеч нарса ёзмайди', async () => {
  const db = dbWith({});
  const r = await aggregateDay({ db, dateStr: DAY });
  assert.strictEqual(r.scanned, 0);
  assert.strictEqual(r.buckets.length, 0);
});

// ── 13.5.3 — pushEligible shadow mode'da ──────────────────────────────

ok('13.5.3 — SHADOW MODE да ҳам pushEligible ҳисобланади', async () => {
  // Policy «юборилади» деди (reason: send), лекин pushEnabled: false
  // сабабли ҳеч нарса юборилмади. Агар `eligible` ҳисобланмаса,
  // «push спам бўляптими?» саволига жавоб бериб бўлмасди.
  const db = dbWith({ d1: { doc: demand(), stats: {} } });
  await recordPushSummary(db, 'd1', {
    total: 10, sent: 0, digest: 0, skipped: 10,
    reasons: { send: 8, no_consent: 2 },
  });
  const stats = db.docs.get('demands/d1/private/stats');
  assert.strictEqual(stats.push.eligible, 8, 'policy «юборилади» дегани 8 та');
  assert.strictEqual(stats.push.sent, 0, 'shadow mode да юборилмади');
  assert.strictEqual(stats.push.noConsent, 2);
});

ok('push хулосаси — ҳақиқий юборишда eligible = sent', async () => {
  const db = dbWith({ d1: { doc: demand(), stats: {} } });
  await recordPushSummary(db, 'd1', {
    total: 10, sent: 7, digest: 2, skipped: 1,
    reasons: { send: 7, hourly_limit: 2, no_consent: 1 },
  });
  const stats = db.docs.get('demands/d1/private/stats');
  assert.strictEqual(stats.push.eligible, 7);
  assert.strictEqual(stats.push.sent, 7);
  assert.strictEqual(stats.push.digest, 2);
});

ok('push хулосаси ёзилмаса асосий оқим бузилмайди', async () => {
  // Хато ютилиши керак — аналитика учун талаб йўқолмайди.
  const broken = {
    collection: () => ({
      doc: () => ({
        collection: () => ({
          doc: () => ({ set: async () => { throw new Error('simulyatsiya'); } }),
        }),
      }),
    }),
  };
  await recordPushSummary(broken, 'd1', { sent: 1, reasons: {} });
  // Хато ташланмади — тест шу ерга етиб келди.
  assert.ok(true);
});

ok('лимит ва тинч соат eligible га КИРМАЙДИ', async () => {
  // Улар policy'нинг атайин қарори, shadow mode таъсири эмас.
  const db = dbWith({ d1: { doc: demand(), stats: {} } });
  await recordPushSummary(db, 'd1', {
    sent: 0, digest: 5, skipped: 5,
    reasons: { hourly_limit: 3, quiet_hours: 2 },
  });
  const stats = db.docs.get('demands/d1/private/stats');
  assert.strictEqual(stats.push.eligible, 0, 'limit sababli to`xtagani eligible emas');
  assert.strictEqual(stats.push.digest, 5);
});

// ─────────────────────────────────────────────────────────────────────
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
