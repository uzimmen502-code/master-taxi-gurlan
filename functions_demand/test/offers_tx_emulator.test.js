/**
 * Taklif oqimi (`api/offers.js`) — HAQIQIY Firestore tranzaksiyasi bilan
 * (Emulator, Admin SDK).
 *
 *   npm --prefix functions_demand run test:offers-tx
 *
 * Nega alohida (run_all.js da emas): sof testlardagi fake tranzaksiya
 * 2026-10-07 gacha yozuvlarni oxiriga surardi va «yozuvdan KEYIN o'qish»ni
 * ushlamasdi. Haqiqiy SDK esa `Firestore transactions require all reads to
 * be executed before all writes` deb tashlaydi. `cancelAssignment` aynan
 * shunday edi: talabni `tx.update` qilib, keyin taklifni `tx.get` qilardi —
 * ijrochi tayinlangan buyurtmani HECH QACHON bekor qila olmasdi (ilovadagi
 * «Бекор қилиш» tugmasi ham, Relay LEG'i ham).
 *
 * Qulflanadi:
 *   - submitOffer (yangi + tahrir), withdrawOffer, acceptOffer, cancelDemand
 *   - acceptOffer: ikki parallel qabul → BITTA g'olib
 *   - cancelAssignment: talab qayta ochiladi, taklif `rejected`, kontakt
 *     yopiladi, trust voqeasi yoziladi
 *   - cancelAssignment: taklif hujjati YO'Q (Relay LEG: `offerId: null`)
 *   - acceptOffer/submitOffer muddati (2026-10-11): server vaqti, `<=`
 *     chegarasi, tranzaksiya ichida, `demand_expired` sababi
 *   - Relay LEG bekor (2026-10-10): jo'natmada bekor qilgan ijrochi qolmaydi;
 *     keyingi ijrochi telefoni unga ochilmaydi / undan olinadi; LEG'ni qayta
 *     olgan ijrochi keyingi ijrochi telefonini oladi
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-offers-tx';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const offersApi = require('../api/offers');
const logisticsApi = require('../api/logistics');
const config = require('../core/config');
const sm = require('../core/state_machine');

const OWNER = '998901110001';
const USTA_A = '998902220002';
const USTA_B = '998903330003';
const DEMAND_ID = 'demAbc123XyZ';
const NOW = new Date('2026-10-07T10:00:00.000Z');
const ctx = (phone) => ({ auth: { token: { phone_number: `+${phone}` } } });
const deps = (extra = {}) => ({ db, now: () => NOW, ...extra });

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};

/** Emulatorni butunlay tozalaydi (subkolleksiyalar ham). */
async function reset(extra = {}) {
  const url = `http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/`
    + `${process.env.GCLOUD_PROJECT}/databases/(default)/documents`;
  const res = await fetch(url, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator tozalanmadi: ${res.status}`);
  config.clearCache();
  const docs = {
    'module_config/global': { enabled: true, matchingEnabled: true, pushEnabled: true },
    'module_config/service_xorazm': { enabled: true, pushEnabled: true },
    [`demands/${DEMAND_ID}`]: {
      ownerId: OWNER,
      module: 'service',
      mode: 'quote',
      status: sm.STATUS.ACTIVE,
      categoryId: 'santexnik',
      location: { lat: 41.55, lng: 60.63, regionId: 'xorazm', districtId: 'urganch_sh', addressText: 'Al-Xorazmiy 15' },
      timeWindow: { expiresAt: new Date(NOW.getTime() + 3600 * 1000) },
      assignment: { providerId: null, offerId: null, acceptedAt: null },
      matching: { state: 'done', matchedBucket: '1-2' },
    },
    [`demand_matches/${DEMAND_ID}_${USTA_A}`]: { demandId: DEMAND_ID, providerId: USTA_A, status: 'new' },
    [`demand_matches/${DEMAND_ID}_${USTA_B}`]: { demandId: DEMAND_ID, providerId: USTA_B, status: 'new' },
    ...extra,
  };
  await Promise.all(Object.entries(docs).map(([path, data]) => db.doc(path).set(data)));
}

const demandRef = () => db.collection('demands').doc(DEMAND_ID);
const data = async (ref) => (await ref.get()).data();
const offer = (id, clientRequestId, price = 150000) => offersApi.makeSubmitOffer(deps())(
  { demandId: DEMAND_ID, clientRequestId, price, message: '18:00 gacha' }, ctx(id),
);
const accept = (id) => offersApi.makeAcceptOffer(deps())({ demandId: DEMAND_ID, providerId: id }, ctx(OWNER));

// ── Relay: 2 LEG'li jo'natma (LEG1 → LEG2) ──────────────────────────────
const K1 = '998904440004';
const K2 = '998905550005';
const K3 = '998906660006';
const SHIP = 'shipRelay001';
const relayLeg = (idx, dependsOnLegId, nextLegId) => ({
  ownerId: OWNER,
  module: 'logistics',
  mode: 'dispatch',
  status: sm.STATUS.ACTIVE,
  location: { lat: 41.55, lng: 60.63, addressText: 'Gurlan' },
  timeWindow: { expiresAt: new Date(NOW.getTime() + 3600 * 1000) },
  assignment: { providerId: null, offerId: null, acceptedAt: null },
  attributes: { shipmentId: SHIP, orderId: 'ordRelay001', legIndex: idx, legCount: 2, dependsOnLegId, nextLegId, payout: 10000 },
});
async function resetRelay() {
  const extra = {
    'demands/LEG1': relayLeg(0, null, 'LEG2'),
    'demands/LEG2': relayLeg(1, 'LEG1', null),
    [`shipments/${SHIP}`]: {
      ownerId: OWNER, status: 'ready', paymentStatus: 'escrow_funded',
      legIds: ['LEG1', 'LEG2'], legCount: 2, assignedProviderIds: [], legAssignments: {},
      currentCustodian: { kind: 'sender', id: OWNER, since: NOW },
    },
  };
  for (const k of [K1, K2, K3]) {
    for (const l of ['LEG1', 'LEG2']) extra[`demand_matches/${l}_${k}`] = { demandId: l, providerId: k, status: 'new' };
  }
  await reset(extra);
}
const takeLeg = (legId, id) => logisticsApi.makeAcceptLeg(deps())({ legId }, ctx(id));
const dropLeg = (legId, id) => offersApi.makeCancelAssignment(deps())({ demandId: legId }, ctx(id));
const ship = () => data(db.collection('shipments').doc(SHIP));
const matchOf = (legId, id) => data(db.collection('demand_matches').doc(`${legId}_${id}`));

(async () => {
  await check('submitOffer: yangi taklif + tahrir (revision 1), offerCount 1', async () => {
    await reset();
    await offer(USTA_A, 'req-offer-0001');
    await offer(USTA_A, 'req-offer-0002', 140000);
    const o = await data(demandRef().collection('offers').doc(USTA_A));
    assert.strictEqual(o.status, 'active');
    assert.strictEqual(o.revision, 1);
    assert.strictEqual(o.price, 140000);
    assert.strictEqual((await data(demandRef())).offerCount, 1);
  });

  await check('withdrawOffer: taklif qaytarib olinadi', async () => {
    await reset();
    await offer(USTA_A, 'req-offer-0001');
    await offersApi.makeWithdrawOffer(deps())({ demandId: DEMAND_ID }, ctx(USTA_A));
    assert.strictEqual((await data(demandRef().collection('offers').doc(USTA_A))).status, 'withdrawn');
  });

  await check('acceptOffer: ikki parallel qabul → BITTA g\'olib', async () => {
    await reset();
    await offer(USTA_A, 'req-offer-a001');
    await offer(USTA_B, 'req-offer-b001');
    const out = await Promise.allSettled([accept(USTA_A), accept(USTA_B)]);
    const won = out.filter((o) => o.status === 'fulfilled');
    assert.strictEqual(won.length, 1, out.map((o) => o.reason && o.reason.message).join(' | '));
    const lost = out.find((o) => o.status === 'rejected');
    assert.strictEqual(lost.reason.code, 'failed-precondition', lost.reason.message);
    const d = await data(demandRef());
    assert.strictEqual(d.status, 'accepted');
    assert.strictEqual(d.assignment.providerId, won[0].value.providerId);
  });

  // ── acceptOffer: muddat (ega qarori 2026-10-11) ─────────────────────
  const setExpiry = (at) => demandRef().update({ 'timeWindow.expiresAt': at });
  const expectExpired = async () => {
    await assert.rejects(() => accept(USTA_A), (e) => e.code === 'failed-precondition'
      && e.details && e.details.reason === 'demand_expired');
    const d = await data(demandRef());
    assert.notStrictEqual(d.status, 'accepted');
    assert.strictEqual(d.assignment.providerId, null);
    assert.strictEqual((await data(demandRef().collection('offers').doc(USTA_A))).status, 'active');
    const m = await data(db.collection('demand_matches').doc(`${DEMAND_ID}_${USTA_A}`));
    assert.notStrictEqual(m.status, 'accepted');
    assert.ok(!m.contactUnlocked, 'kontakt ochilmaydi');
  };

  await check('acceptOffer: muddat o\'tgan (sweeper hali yopmagan) — RAD demand_expired, hech narsa o\'zgarmaydi', async () => {
    await reset();
    await offer(USTA_A, 'req-offer-0001');
    await setExpiry(new Date(NOW.getTime() - 60 * 1000));
    await expectExpired();
    assert.strictEqual((await data(demandRef())).status, 'active', 'holatni sweeper o\'zgartiradi, acceptOffer emas');
  });

  await check('acceptOffer: chegara expiresAt == server vaqti — RAD (sweeper bilan bir xil `<=`)', async () => {
    await reset();
    await offer(USTA_A, 'req-offer-0001');
    await setExpiry(NOW);
    await expectExpired();
  });

  await check('acceptOffer: chegara expiresAt == server vaqti + 1 ms — QABUL qilinadi', async () => {
    await reset();
    await offer(USTA_A, 'req-offer-0001');
    await setExpiry(new Date(NOW.getTime() + 1));
    await accept(USTA_A);
    assert.strictEqual((await data(demandRef())).status, 'accepted');
  });

  await check('acceptOffer: talab allaqachon `expired` (sweeper yopgan) — RAD demand_expired', async () => {
    await reset();
    await offer(USTA_A, 'req-offer-0001');
    await demandRef().update({ status: 'expired' });
    await expectExpired();
  });

  await check('submitOffer: chegara expiresAt == server vaqti — RAD demand_expired', async () => {
    await reset();
    await setExpiry(NOW);
    await assert.rejects(() => offer(USTA_A, 'req-offer-0001'),
      (e) => e.details && e.details.reason === 'demand_expired');
  });

  await check('cancelAssignment: talab QAYTA OCHILADI, taklif rejected, kontakt yopiladi, trust', async () => {
    await reset();
    await offer(USTA_A, 'req-offer-0001');
    await accept(USTA_A);
    const r = await offersApi.makeCancelAssignment(deps())({ demandId: DEMAND_ID }, ctx(USTA_A));
    assert.strictEqual(r.reopened, true);
    const d = await data(demandRef());
    assert.strictEqual(d.status, 'active');
    assert.strictEqual(d.assignment.providerId, null);
    assert.strictEqual(d.reopenCount, 1);
    assert.strictEqual((await data(demandRef().collection('offers').doc(USTA_A))).status, 'rejected');
    const m = await data(db.collection('demand_matches').doc(`${DEMAND_ID}_${USTA_A}`));
    assert.strictEqual(m.status, 'cancelled_by_provider');
    assert.strictEqual(m.contactUnlocked, null);
    const trust = await db.collection('trust_events').get();
    assert.strictEqual(trust.size, 1);
    assert.strictEqual(trust.docs[0].data().type, 'quickCancel');
  });

  await check('cancelAssignment: taklif hujjati YO\'Q (Relay LEG, offerId null) → qayta ochiladi', async () => {
    await reset({
      [`demands/${DEMAND_ID}`]: {
        ownerId: OWNER,
        module: 'logistics',
        status: sm.STATUS.ACCEPTED,
        assignment: { providerId: USTA_A, offerId: null, acceptedAt: NOW },
        matching: { state: 'done' },
      },
    });
    await offersApi.makeCancelAssignment(deps())({ demandId: DEMAND_ID }, ctx(USTA_A));
    const d = await data(demandRef());
    assert.strictEqual(d.status, 'active');
    assert.strictEqual(d.assignment.providerId, null);
    const offers = await demandRef().collection('offers').get();
    assert.strictEqual(offers.size, 0, 'yo\'q taklif hujjati yaratilmasligi kerak');
  });

  await check('LEG bekor: jo\'natmada bekor qilgan ijrochi QOLMAYDI (assignedProviderIds, legAssignments)', async () => {
    await resetRelay();
    await takeLeg('LEG1', K1);
    await dropLeg('LEG1', K1);
    const s = await ship();
    assert.deepStrictEqual(s.assignedProviderIds, []);
    assert.deepStrictEqual(s.legAssignments, {});
    assert.strictEqual((await data(db.collection('demands').doc('LEG1'))).status, 'active');
  });

  await check('LEG bekor → keyingi LEG olinsa: telefon BEKOR QILGAN ijrochiga ochilmaydi', async () => {
    await resetRelay();
    await takeLeg('LEG1', K1);
    await dropLeg('LEG1', K1);
    await takeLeg('LEG2', K2);
    const m = await matchOf('LEG1', K1);
    assert.strictEqual(m.status, 'cancelled_by_provider');
    assert.strictEqual(m.contactUnlocked, null, JSON.stringify(m.contactUnlocked));
  });

  await check('LEG1 qayta olinsa (LEG2 band): yangi ijrochiga keyingi ijrochi telefoni ochiladi', async () => {
    await resetRelay();
    await takeLeg('LEG1', K1);
    await takeLeg('LEG2', K2);
    await dropLeg('LEG1', K1);
    await takeLeg('LEG1', K3);
    assert.strictEqual(((await matchOf('LEG1', K3)).contactUnlocked || {}).nextProviderPhone, K2);
    const s = await ship();
    assert.deepStrictEqual([...s.assignedProviderIds].sort(), [K2, K3].sort());
    assert.deepStrictEqual(s.legAssignments, { LEG1: K3, LEG2: K2 });
  });

  await check('LEG2 bekor: oldingi ijrochidan bekor qilganning telefoni OLINADI, o\'z kontakti qoladi', async () => {
    await resetRelay();
    await takeLeg('LEG1', K1);
    await takeLeg('LEG2', K2);
    assert.strictEqual(((await matchOf('LEG1', K1)).contactUnlocked || {}).nextProviderPhone, K2);
    await dropLeg('LEG2', K2);
    const c = (await matchOf('LEG1', K1)).contactUnlocked;
    assert.strictEqual(c.nextProviderPhone, null);
    assert.strictEqual(c.ownerPhone, OWNER, 'olish kontakti (1-pog\'ona) saqlanadi');
    const s = await ship();
    assert.deepStrictEqual(s.assignedProviderIds, [K1]);
    assert.deepStrictEqual(s.legAssignments, { LEG1: K1 });
  });

  await check('LEG bekor: ijrochi boshqa LEG\'ni ham olgan bo\'lsa assignedProviderIds\'da QOLADI', async () => {
    await resetRelay();
    await takeLeg('LEG1', K1);
    await takeLeg('LEG2', K1);
    await dropLeg('LEG2', K1);
    const s = await ship();
    assert.deepStrictEqual(s.assignedProviderIds, [K1]);
    assert.deepStrictEqual(s.legAssignments, { LEG1: K1 });
  });

  await check('cancelDemand: mijoz bekor qiladi, matchlar yopiladi', async () => {
    await reset();
    await offersApi.makeCancelDemand(deps())({ demandId: DEMAND_ID }, ctx(OWNER));
    assert.strictEqual((await data(demandRef())).status, 'cancelled');
    const m = await data(db.collection('demand_matches').doc(`${DEMAND_ID}_${USTA_A}`));
    assert.strictEqual(m.status, 'cancelled');
  });

  const failed = results.filter((r) => !r.pass).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi.`);
  process.exit(failed ? 1 : 0);
})();
