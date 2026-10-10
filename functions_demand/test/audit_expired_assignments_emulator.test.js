/**
 * READ-ONLY аудит воситаси (`tools/audit_expired_assignments.js`) — эмуляторда.
 *
 *   npm --prefix functions_demand run test:audit-tx
 *
 * Атайлаб зиддиятли + тоза маълумот ёзилади, кейин:
 *   - C1–C4 ҳар бири ўз зиддиятини ТОПАДИ, тоза ҳужжатни БЕЛГИЛАМАЙДИ
 *   - телефонлар ниқобланган (ҳисоботда тўлиқ рақам йўқ)
 *   - `lockWrites`дан кейин ҳар қандай ёзиш хато беради, маълумот ўзгармайди
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-audit-tx';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const { runAudit, lockWrites } = require('../tools/audit_expired_assignments');
const { resetEmulator } = require('./helpers/emulator_hooks');

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};

const OWNER = '998901110001';
const P1 = '998902220002';
const P2 = '998903330003';
const T0 = new Date('2026-10-01T10:00:00Z');
const T1 = new Date('2026-10-01T11:00:00Z');
const svc = (status, extra = {}) => ({
  ownerId: OWNER, module: 'service', mode: 'quote', status,
  timeWindow: { expiresAt: T1 },
  assignment: { providerId: null, offerId: null, acceptedAt: null },
  ...extra,
});

const SEED = {
  // C1: sweeper poygasi — qabul muddatdan OLDIN, keyin expired bilan bosilgan.
  'demands/bad1': svc('expired', { assignment: { providerId: P1, offerId: P1, acceptedAt: T0 }, expiredAt: T1 }),
  'demands/bad1/offers/998902220002': { status: 'accepted' },
  'demand_matches/bad1_998902220002': { demandId: 'bad1', providerId: P1, status: 'accepted', contactUnlocked: { stage: 1 } },
  // C1: qabul muddatdan KEYIN (acceptOffer tekshirmagan).
  'demands/bad2': svc('expired', { assignment: { providerId: P2, offerId: P2, acceptedAt: new Date('2026-10-01T12:00:00Z') } }),
  // TOZA: expired, tayinlanmagan.
  'demands/ok1': svc('expired'),
  'demand_matches/ok1_998902220002': { demandId: 'ok1', providerId: P1, status: 'expired' },
  // TOZA: ishdagi talab, accepted match.
  'demands/ok2': svc('accepted', { assignment: { providerId: P1, offerId: P1, acceptedAt: T0 } }),
  'demand_matches/ok2_998902220002': { demandId: 'ok2', providerId: P1, status: 'accepted' },
  // C3: bekor qilingan talabda ochiq match.
  'demands/bad3': svc('cancelled'),
  'demand_matches/bad3_998903330003': { demandId: 'bad3', providerId: P2, status: 'new' },
  // TOZA: active talabda ochiq match.
  'demands/ok3': svc('active'),
  'demand_matches/ok3_998903330003': { demandId: 'ok3', providerId: P2, status: 'new' },
  // C4: Relay — eskirgan assignedProviderIds + etim active LEG.
  'shipments/shipBad': {
    status: 'ready', legIds: ['legA'], legAssignments: {}, assignedProviderIds: [P1],
  },
  'demands/legA': { module: 'logistics', status: 'active', attributes: { shipmentId: 'shipBad' }, assignment: { providerId: null } },
  'demands/legOrphan': { module: 'logistics', status: 'active', attributes: { shipmentId: 'shipBad' }, assignment: { providerId: null } },
  // TOZA: Relay — izchil.
  'shipments/shipOk': {
    status: 'in_transit', legIds: ['legB'], legAssignments: { legB: P2 }, assignedProviderIds: [P2], currentLegId: 'legB',
  },
  'demands/legB': { module: 'logistics', status: 'in_progress', attributes: { shipmentId: 'shipOk' }, assignment: { providerId: P2 } },
};

(async () => {
  await resetEmulator(db, SEED);
  lockWrites(admin.firestore);
  const report = await runAudit(db, { maxReads: 5000 });

  await check('C1: expired + ijrochi — bad1 va bad2 topiladi, ok1 yo\'q', async () => {
    const ids = report.C1.rows.map((r) => r.demandId).sort();
    assert.deepStrictEqual(ids, ['bad1', 'bad2']);
    const b1 = report.C1.rows.find((r) => r.demandId === 'bad1');
    assert.strictEqual(b1.acceptedAfterExpiry, false, 'sweeper poygasi');
    assert.strictEqual(b1.offerStatus, 'accepted');
    assert.strictEqual(b1.matches[0].contactUnlocked, true);
    assert.strictEqual(report.C1.rows.find((r) => r.demandId === 'bad2').acceptedAfterExpiry, true);
  });

  await check('C2: accepted match ishda bo\'lmagan talabda — faqat bad1', async () => {
    assert.deepStrictEqual(report.C2.rows.map((r) => r.demandId), ['bad1']);
    assert.strictEqual(report.C2.rows[0].demandStatus, 'expired');
  });

  await check('C3: yopiq talabda ochiq match — bad3, ok3 emas', async () => {
    assert.deepStrictEqual(report.C3.rows.map((r) => r.demandId), ['bad3']);
  });

  await check('C4: Relay — eskirgan assignedProviderIds + etim LEG; shipOk toza', async () => {
    const kinds = report.C4.rows.map((r) => `${r.shipmentId}:${r.kind}`).sort();
    assert.deepStrictEqual(kinds, ['shipBad:orphan_open_leg', 'shipBad:stale_assignedProviderIds']);
    assert.strictEqual(report.C4.rows.find((r) => r.kind === 'orphan_open_leg').legId, 'legOrphan');
  });

  await check('PII: hisobotda to\'liq telefon raqami YO\'Q', async () => {
    const text = JSON.stringify(report);
    for (const p of [OWNER, P1, P2]) {
      // matchId / doc ID'lar emas — ijrochi/egasi maydonlari ниқобланган.
      const plain = text.replace(/"(demandId|matchId|legId|shipmentId)":"[^"]*"/g, '');
      assert.ok(!plain.includes(p), `ochiq raqam: ${p.slice(0, 5)}…`);
    }
  });

  await check('lockWrites: set/update/delete/batch/transaction — hammasi XATO, ma\'lumot o\'zgarmaydi', async () => {
    const ref = db.doc('demands/ok3');
    assert.throws(() => ref.set({ x: 1 }), /READ-ONLY/);
    assert.throws(() => ref.update({ x: 1 }), /READ-ONLY/);
    assert.throws(() => ref.delete(), /READ-ONLY/);
    assert.throws(() => db.collection('demands').add({ x: 1 }), /READ-ONLY/);
    assert.throws(() => db.batch(), /READ-ONLY/);
    assert.throws(() => db.runTransaction(async () => {}), /READ-ONLY/);
    assert.strictEqual((await ref.get()).data().status, 'active');
    assert.strictEqual((await db.doc('demands/bad1').get()).data().status, 'expired', 'avtomatik tiklanmaydi');
  });

  await check('audit faqat o\'qidi: hisobot readOnly, o\'qish soni chegarada', async () => {
    assert.strictEqual(report.readOnly, true);
    assert.ok(report.reads > 0 && report.reads < 5000);
    assert.strictEqual(report.budgetExhausted, false);
  });

  const failed = results.filter((r) => !r.pass).length;
  console.log(`\n${results.length - failed}/${results.length} o'tdi.`);
  process.exit(failed ? 1 : 0);
})();
