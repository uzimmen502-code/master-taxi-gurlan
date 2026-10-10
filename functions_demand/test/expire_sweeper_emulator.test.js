/**
 * `expireDemandsSweeper` — HAQIQIY Firestore bilan (Emulator, Admin SDK).
 *
 *   npm --prefix functions_demand run test:sweeper-tx
 *
 * Qulflanadi (2026-10-10), har bir POYGA hook bilan aniq joyda:
 *   - so'rovdan keyin mijoz taklifni qabul qilsa (umumiy modul): sweeper
 *     qabulni `expired` bilan bosib ketmaydi, ijrochi match'i yopilmaydi
 *   - so'rovdan keyin kuryer LEG'ni olsa: LEG `expired` bo'lmaydi,
 *     jo'natmaga `legProblem` yozilmaydi
 *   - match'larni yopish paytida admin LEG'ni qayta ochsa: yangi match'lar
 *     yopilmaydi
 *   - sweeper yopgan talabda acceptOffer RAD (demand_expired)
 *   - chegara: `expiresAt == now` yopiladi, `now + 1 ms` yopilmaydi
 *   - precondition: so'rovdan keyin o'zgargan hujjat o'tkaziladi va keyingi
 *     aylanishda yopiladi (qotib qolmaydi); takroriy aylanish — no-op
 *   - oddiy holat: muddati o'tgan talab + match'lar yopiladi, legProblem
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-sweeper-tx';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const api = require('../api/logistics');
const offersApi = require('../api/offers');
const maint = require('../api/maintenance');
const config = require('../core/config');
const tariffCore = require('../core/tariff');
const sm = require('../core/state_machine');
const {
  OWNER, K1, ADMIN, NOW, ctx, seed, orderPayload, deps, fund,
} = require('./helpers/logistics_harness');
const { resetEmulator, dbWithQueryHook, dbWithHooks } = require('./helpers/emulator_hooks');

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};

const USTA = '998907770007';
const SVC = 'demSvcExpired1';
const LATER = new Date(NOW.getTime() + (3 * 24 + 1) * 3600 * 1000);

async function reset(extra = {}) {
  config.clearCache(); tariffCore.clearCache();
  await resetEmulator(db, { ...seed(), ...extra });
}
const doc = async (p) => (await db.doc(p).get()).data();
const sweeper = (d) => maint.makeExpireSweeper({ db: d, now: () => LATER })();

/** Umumiy modul talabi: muddati LATER'dan oldin tugagan, USTA taklifi bor. */
const svcDocs = () => ({
  [`demands/${SVC}`]: {
    ownerId: OWNER, module: 'service', mode: 'quote', status: sm.STATUS.ACTIVE,
    location: { lat: 41.55, lng: 60.63, regionId: 'xorazm', addressText: 'Gurlan' },
    timeWindow: { expiresAt: new Date(LATER.getTime() - 60 * 1000) },
    assignment: { providerId: null, offerId: null, acceptedAt: null },
    matching: { state: 'done' },
  },
  [`demands/${SVC}/offers/${USTA}`]: { providerId: USTA, status: 'active', price: 150000, revision: 0 },
  [`demand_matches/${SVC}_${USTA}`]: { demandId: SVC, providerId: USTA, status: 'new' },
});

/** To'langan jo'natma, LEG-1 active (muddati LATER'dan oldin tugaydi). */
async function fundedLeg() {
  const r = await api.makeCreateLogisticsOrder(deps(db))(orderPayload(), ctx(OWNER));
  const shipmentId = r.shipmentIds[0];
  await fund(db, shipmentId);
  const [legId] = (await doc(`shipments/${shipmentId}`)).legIds;
  assert.strictEqual((await doc(`demands/${legId}`)).status, 'active');
  return { shipmentId, legId };
}

(async () => {
  await check('so\'rovdan keyin mijoz taklifni qabul qilsa: qabul SAQLANADI (expired emas)', async () => {
    await reset(svcDocs());
    // Instansiyalar soati farqi: acceptOffer serverida muddat hali tugamagan
    // (expiresAt − 1 ms), sweeper'nikida tugagan — acceptOffer qonuniy g'olib.
    const acceptNow = new Date(LATER.getTime() - 60 * 1000 - 1);
    const hooked = dbWithQueryHook(db, 'demands', async () => {
      await offersApi.makeAcceptOffer({ db, now: () => acceptNow })({ demandId: SVC, providerId: USTA }, ctx(OWNER));
    });
    const r = await sweeper(hooked);
    const d = await doc(`demands/${SVC}`);
    assert.strictEqual(d.status, 'accepted', `qabul bosib ketildi: ${JSON.stringify(r)}`);
    assert.strictEqual(d.assignment.providerId, USTA);
    assert.strictEqual((await doc(`demand_matches/${SVC}_${USTA}`)).status, 'accepted');
    assert.strictEqual(r.expired, 0);
  });

  await check('so\'rovdan keyin kuryer LEG\'ni olsa: LEG accepted qoladi, legProblem YO\'Q', async () => {
    await reset();
    const { shipmentId, legId } = await fundedLeg();
    // Kuryer soati bo'yicha muddat hali tugamagan (NOW), sweeper'niki — tugagan.
    const hooked = dbWithQueryHook(db, 'demands', async () => {
      await api.makeAcceptLeg(deps(db))({ legId }, ctx(K1));
    });
    const r = await sweeper(hooked);
    const l = await doc(`demands/${legId}`);
    assert.strictEqual(l.status, 'accepted', `qabul bosib ketildi: ${JSON.stringify(r)}`);
    assert.strictEqual((await doc(`demand_matches/${legId}_${K1}`)).status, 'accepted');
    assert.ok(!(await doc(`shipments/${shipmentId}`)).legProblem, 'legProblem yozildi');
  });

  await check('match yopish paytida admin LEG\'ni qayta ochsa: yangi match\'lar YOPILMAYDI', async () => {
    await reset();
    const { legId } = await fundedLeg();
    const hooked = dbWithQueryHook(db, 'demand_matches', async () => {
      config.clearCache();
      await api.makeAdminReactivateLeg({ ...deps(db), now: () => LATER })({ legId, reason: 'poyga' }, ctx(ADMIN));
    });
    await sweeper(hooked);
    assert.strictEqual((await doc(`demands/${legId}`)).status, 'active');
    const m = await doc(`demand_matches/${legId}_${K1}`);
    assert.strictEqual(m && m.status, 'new', `K1 match: ${JSON.stringify(m && m.status)}`);
  });

  await check('legProblem yozilishidan oldin admin qayta rejalasa: eski reja LEG\'iga legProblem YOZILMAYDI', async () => {
    await reset();
    const { shipmentId, legId } = await fundedLeg();
    // LEG yopildi, legProblem hali yozilmagan — shu payt admin yangi marshrut beradi.
    const hooked = dbWithHooks(db, { queryOn: 'demand_matches', updateOn: 'shipments' }, async () => {
      await api.makeAdminPlanShipmentRoute({ ...deps(db), now: () => LATER })({
        shipmentId, reason: 'poyga', legs: [
          { to: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' } },
          { from: { regionId: 'xorazm', districtId: 'urganch_shahri', addressText: 'Urganch bekat' } },
        ],
      }, ctx(ADMIN));
    });
    await sweeper(hooked);
    const s = await doc(`shipments/${shipmentId}`);
    assert.ok(!s.legIds.includes(legId));
    assert.ok(!s.legProblem || s.legProblem.legId !== legId, `eskirgan legProblem: ${JSON.stringify(s.legProblem)}`);
  });

  await check('sweeper keyin acceptOffer: muddat o\'tgan talabda qabul RAD (demand_expired)', async () => {
    await reset(svcDocs());
    await sweeper(db);
    await assert.rejects(
      () => offersApi.makeAcceptOffer({ db, now: () => LATER })({ demandId: SVC, providerId: USTA }, ctx(OWNER)),
      (e) => e.details && e.details.reason === 'demand_expired',
    );
    const d = await doc(`demands/${SVC}`);
    assert.strictEqual(d.status, 'expired');
    assert.strictEqual(d.assignment.providerId, null);
  });

  await check('chegara: expiresAt == now — yopiladi; now + 1 ms — yopilmaydi', async () => {
    await reset({
      'demands/edgeEq': { ...svcDocs()[`demands/${SVC}`], timeWindow: { expiresAt: LATER } },
      'demands/edgePlus': { ...svcDocs()[`demands/${SVC}`], timeWindow: { expiresAt: new Date(LATER.getTime() + 1) } },
    });
    const r = await sweeper(db);
    assert.deepStrictEqual(r.ids, ['edgeEq']);
    assert.strictEqual((await doc('demands/edgeEq')).status, 'expired');
    assert.strictEqual((await doc('demands/edgePlus')).status, 'active');
  });

  await check('precondition: so\'rovdan keyin boshqa maydon o\'zgarsa — bu aylanishda o\'tkaziladi, keyingisida yopiladi', async () => {
    await reset(svcDocs());
    const hooked = dbWithQueryHook(db, 'demands', async () => {
      await db.doc(`demands/${SVC}`).update({ 'matching.state': 'done', updatedAt: new Date() });
    });
    const r1 = await sweeper(hooked);
    assert.strictEqual(r1.expired, 0);
    assert.strictEqual(r1.skipped, 1);
    assert.strictEqual((await doc(`demands/${SVC}`)).status, 'active');
    assert.strictEqual((await doc(`demand_matches/${SVC}_${USTA}`)).status, 'new', 'match yopilmaydi');
    const r2 = await sweeper(db);
    assert.strictEqual(r2.expired, 1, 'qotib qolmaydi — keyingi aylanish yopadi');
    assert.strictEqual((await doc(`demand_matches/${SVC}_${USTA}`)).status, 'expired');
  });

  await check('takroriy sweeper: ikkinchi aylanish hech narsa qilmaydi (idempotent)', async () => {
    await reset(svcDocs());
    const r1 = await sweeper(db);
    const r2 = await sweeper(db);
    assert.strictEqual(r1.expired, 1);
    assert.strictEqual(r2.expired, 0);
  });

  await check('oddiy holat: muddati o\'tgan talab va LEG yopiladi, match\'lar expired, legProblem', async () => {
    await reset(svcDocs());
    const { shipmentId, legId } = await fundedLeg();
    const r = await sweeper(db);
    assert.strictEqual(r.expired, 2);
    assert.strictEqual(r.legProblems, 1);
    assert.strictEqual((await doc(`demands/${SVC}`)).status, 'expired');
    assert.strictEqual((await doc(`demands/${legId}`)).status, 'expired');
    assert.strictEqual((await doc(`demand_matches/${SVC}_${USTA}`)).status, 'expired');
    assert.strictEqual((await doc(`demand_matches/${legId}_${K1}`)).status, 'expired');
    assert.strictEqual((await doc(`shipments/${shipmentId}`)).legProblem.legId, legId);
  });

  const failed = results.filter((r) => !r.pass).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi.`);
  process.exit(failed ? 1 : 0);
})();
