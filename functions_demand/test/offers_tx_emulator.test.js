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
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-offers-tx';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const offersApi = require('../api/offers');
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
