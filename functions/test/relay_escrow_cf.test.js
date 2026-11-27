/**
 * AVA Logistics eskrou — HAQIQIY ledger bilan (Firestore Emulator, Admin SDK).
 *
 *   firebase emulators:exec --only firestore --project demo-relay-escrow \
 *     "node functions/test/relay_escrow_cf.test.js"
 *
 * Qulflanadi (D-11, relay 7.6):
 *   - FUND: hamyon → eskrou, ATOMAR (holat + ledger bir tranzaksiyada); yetmasa rad
 *   - EARNED eskrouni KAMAYTIRMAYDI; ijrochiga `supplier_payable`
 *   - RELEASE: eskrou → payable pool + AVA ulushi; `settled`; frozen → yo'q
 *   - REFUND: eskrou → hamyon; `refunded`
 *   - hammasi idempotent; Σdr == Σcr
 *   - YO'QOLGAN POSILKA (D1, 2026-10-16): G kuryer hamyonidan mijozga (hamyon yetganicha,
 *     manfiy BO'LMAYDI), qolgani kuryer QARZI (provider_capabilities.debt.logistics + incident);
 *     eskrou odatdagidek yopiladi, ishlanmagan LEG ulushi AVA daromadiga; admin to'lovni yozadi
 *     (admin_cash -> mijoz hamyoni), idempotent, qarzdan oshmaydi; reconcile qotib qolganni tiklaydi
 */
'use strict';
const assert = require('assert');
const admin = require('firebase-admin');
const functions = require('firebase-functions');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-relay-escrow';
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const settlementLedger = require('../settlement_ledger');
const relay = require('../relay_escrow');

const OWNER = '998901110001';
const K1 = '998902220002';
const F1 = '998904440004';
const NOW = new Date('2026-10-07T06:00:00Z');
const notified = [];
const digits = (v) => String(v || '').replace(/\D/g, '');
const api = relay.attachRelayEscrow({}, {
  functions, db, admin,
  callerPhone: (ctx) => digits(ctx.auth.token.phone_number),
  canonicalUid: (v) => { const d = digits(v); return d.length === 9 ? `998${d}` : d; },
  settlementLedger,
  notifyUserInApp: async (m) => { notified.push(m); },
  // `functions/index.js requireCallerRoles` bilan bir xil qoida (token telefoni -> users.role).
  requireCallerRoles: async (context, roles, msg) => {
    if (!context || !context.auth) throw new functions.https.HttpsError('unauthenticated', 'Authentication required');
    const d = digits(context.auth.token.phone_number);
    const uid = d.length === 9 ? `998${d}` : d;
    const role = ((await db.collection('users').doc(uid).get()).data() || {}).role || 'user';
    if (!roles.includes(role)) throw new functions.https.HttpsError('permission-denied', msg || 'Insufficient role');
    return uid;
  },
  now: () => NOW,
});
const ctx = { auth: { token: { phone_number: `+${OWNER}` } } };

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push({ name, pass: true }); console.log(`PASS - ${name}`); } catch (e) {
    results.push({ name, pass: false }); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function wipe(col) {
  const s = await db.collection(col).get();
  await Promise.all(s.docs.map((d) => d.ref.delete()));
}
const bal = async (acc) => (await db.collection(settlementLedger.COL_ACCOUNTS).doc(acc).get()).data()?.balance || 0;
const wallet = () => bal(settlementLedger.passengerCreditAccount(OWNER));
const ship = async (id) => (await db.collection('shipments').doc(id).get()).data();

async function seedShipment(id, { price = 240000, platformShare = 48000, pool = 192000, wallet: w = 300000 } = {}) {
  notified.length = 0;
  await Promise.all(['shipments', 'users', 'custody_events', settlementLedger.COL_JOURNAL, settlementLedger.COL_ACCOUNTS].map(wipe));
  await db.collection('users').doc(OWNER).set({ bonusBalance: 0 });
  await db.collection('shipments').doc(id).set({
    ownerId: OWNER, trackingNumber: 'AVA-26-1007-000001', status: 'awaiting_payment', paymentStatus: 'pending',
    priceSnapshot: { customerPrice: price, tariffVersion: 7 }, legIds: ['leg0', 'leg1'],
  });
  await db.collection('shipments').doc(id).collection('private').doc('internal').set({
    platformShare, providerPool: pool, legPayouts: [{ index: 0, amount: 96000 }, { index: 1, amount: 96000 }],
  });
  if (w > 0) {
    await settlementLedger.postEntry(db, {
      idempotencyKey: `topup:${OWNER}:${id}`, kind: 'test_topup',
      legs: [{ account: 'admin_clearing', dr: w }, { account: settlementLedger.passengerCreditAccount(OWNER), cr: w }],
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════
// YO'QOLGAN POSILKA (D1). Demand codebase `adminMarkShipmentLost` yozadigan holat qo'lda
// seed qilinadi (shipment lost/loss_pending + logistics_incidents); pulni default codebase hisoblaydi.
// ═══════════════════════════════════════════════════════════════════════
const ADMIN_U = '998909990000';
const SUPER_U = '998906660000';
const DISP_U = '998908880000';
const FIN_U = '998907770000';
const ACC_F1 = 'accF1';
const G = 150000;
const pcOf = (uid) => settlementLedger.passengerCreditAccount(uid);
const INC = (id) => db.collection('logistics_incidents').doc(id);
const CAPDOC = () => db.collection('provider_capabilities').doc(ACC_F1);
const incOf = async (id) => (await INC(id).get()).data();
const debtOf = async () => ((((await CAPDOC().get()).data() || {}).debt) || {}).logistics || 0;
const bonusOf = async (uid) => ((await db.collection('users').doc(uid).get()).data() || {}).bonusBalance || 0;
const journal = async (key) => (await db.collection(settlementLedger.COL_JOURNAL).doc(key).get());
const asAdmin = (uid) => ({ auth: { token: { phone_number: `+${uid}` } } });
let topupSeq = 0;
const topup = (uid, amount) => settlementLedger.postEntry(db, {
  idempotencyKey: `topupX:${uid}:${topupSeq += 1}`, kind: 'test_topup',
  legs: [{ account: 'admin_clearing', dr: amount }, { account: pcOf(uid), cr: amount }],
});
async function resetAll() {
  const url = `http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`;
  const res = await fetch(url, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator tozalanmadi: ${res.status}`);
}
/** Yo'qolishni demand codebase e'lon qilgan holat. atLeg=1: 2-LEG'da yo'qoldi (1-LEG ijrochisi K1 ishlab topgan). */
async function seedLoss(id, {
  courierWallet = 200000, atLeg = 1, earnedPosted = true, priorDebt = 0, declared = G, pool = 192000,
} = {}) {
  await resetAll();
  await seedShipment(id, { pool });
  await api.fund({ shipmentId: id }, ctx); // mijoz: 300 000 -> 60 000, eskrou 240 000
  for (const [uid, role] of [[ADMIN_U, 'admin'], [SUPER_U, 'superadmin'], [DISP_U, 'dispatcher'], [FIN_U, 'finance']]) {
    await db.collection('users').doc(uid).set({ role });
  }
  await db.collection('users').doc(F1).set({ bonusBalance: 0, accountId: ACC_F1 });
  await CAPDOC().set({ identity: { accountId: ACC_F1, primaryUid: F1 }, ...(priorDebt ? { debt: { logistics: priorDebt } } : {}) });
  if (courierWallet > 0) await topup(F1, courierWallet);
  if (atLeg === 1) {
    const ev = {
      shipmentId: id, legId: 'leg1', kind: 'pickup', completesLegId: 'leg0', completedLegProviderId: K1,
      completedLegPayout: 96000, legIndex: 1, deliversShipment: false,
    };
    await db.collection('custody_events').doc(`pickup_${id}`).set(ev);
    if (earnedPosted) await api.onCustodyEvent(ev); // prod'da custody triggeri shuni qiladi
  }
  await db.collection('shipments').doc(id).update({
    status: 'lost', paymentStatus: 'loss_pending',
    currentCustodian: { kind: 'provider', id: F1 }, currentLegId: atLeg === 1 ? 'leg1' : 'leg0', lostLegId: atLeg === 1 ? 'leg1' : 'leg0',
  });
  await INC(id).set({
    type: 'lost', status: 'declared', shipmentId: id, legId: atLeg === 1 ? 'leg1' : 'leg0', legIndex: atLeg,
    courier: { uid: F1, accountId: ACC_F1 }, customer: { uid: OWNER }, goodsValue: declared,
    refundedNow: null, outstanding: null, paidTotal: 0, declaredBy: ADMIN_U, reason: 'sinov', note: '', opId: 'lost-op-0001',
  });
  notified.length = 0;
}
/** Trigger: shipments onUpdate (`pre -> loss_pending`). */
const settle = (id) => api.onShipmentUpdate({ paymentStatus: 'escrow_funded' }, { paymentStatus: 'loss_pending' }, id);
async function assertLedgerSound() {
  const rec = await settlementLedger.reconcile(db);
  assert.strictEqual(rec.balanced, true, `Σdr==Σcr buzildi: ${rec.totalDr} != ${rec.totalCr}`);
  assert.strictEqual(rec.identityOk, true, `aktiv/passiv tengligi: ${rec.assets} != ${rec.liabilities}`);
  assert.strictEqual(rec.projectionOk, true, `bonusBalance ko'zgusi: ${JSON.stringify(rec.mismatches)}`);
}

async function lossTests() {
  const L1 = 'shpLOSS0001';
  await check('LOSS to\'liq: kuryer hamyoni >= G — G mijozga, eskrou yopildi, ishlanmagan ulush AVA\'ga, qarz yo\'q', async () => {
    await seedLoss(L1);
    assert.strictEqual(await wallet(), 60000);
    const r = await settle(L1);
    assert.strictEqual(r.settled, true);
    assert.strictEqual(r.taken, G);
    assert.strictEqual(r.outstanding, 0);
    assert.strictEqual(await wallet(), 60000 + G, 'mijoz: aynan G (yetkazish haqi QAYTMAYDI)');
    assert.strictEqual(await bal(pcOf(F1)), 200000 - G);
    assert.strictEqual(await bonusOf(OWNER), 60000 + G);
    assert.strictEqual(await bonusOf(F1), 200000 - G);
    assert.strictEqual(await bal(relay.escrowAccount(L1)), 0, 'eskrou yopildi');
    assert.strictEqual(await bal(relay.ACCRUAL_ACCOUNT), 0, 'platform_accrual = 0');
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(K1)), 96000, 'oldingi LEG ijrochisi haqi saqlandi');
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(F1)), 0, 'yo\'qotgan kuryer yo\'qolgan LEG uchun haq OLMAYDI');
    assert.strictEqual(await bal(relay.PLATFORM_FEE_ACCOUNT), 48000 + 96000, 'AVA ulushi + ishlanmagan LEG ulushi');
    const rel = (await journal(`relayRelease:${L1}`)).data();
    assert.deepStrictEqual(rel.legs, [
      { account: relay.escrowAccount(L1), dr: 240000, cr: 0 },
      { account: relay.ACCRUAL_ACCOUNT, dr: 0, cr: 192000 },
      { account: relay.PLATFORM_FEE_ACCOUNT, dr: 0, cr: 48000 },
    ]);
    const un = (await journal(`relayLostUnearned:${L1}`)).data();
    assert.deepStrictEqual(un.legs, [
      { account: relay.ACCRUAL_ACCOUNT, dr: 96000, cr: 0 },
      { account: relay.PLATFORM_FEE_ACCOUNT, dr: 0, cr: 96000 },
    ]);
    const rf = (await journal(`relayLostRefund:${L1}`)).data();
    assert.deepStrictEqual(rf.legs, [
      { account: pcOf(F1), dr: G, cr: 0 },
      { account: pcOf(OWNER), dr: 0, cr: G },
    ]);
    const s = await ship(L1);
    assert.strictEqual(s.paymentStatus, 'loss_settled');
    const inc = await incOf(L1);
    assert.strictEqual(inc.status, 'repaid');
    assert.strictEqual(inc.refundedNow, G);
    assert.strictEqual(inc.outstanding, 0);
    assert.strictEqual(inc.unearnedToAva, 96000);
    assert.strictEqual(await debtOf(), 0, 'qarz yozilmaydi');
    const ev = await INC(L1).collection('events').get();
    assert.deepStrictEqual(ev.docs.map((d) => d.id), ['settled']);
    assert.deepStrictEqual(notified.map((n) => n.userId).sort(), [F1, OWNER].sort(), 'mijoz va kuryerga xabar');
    assert.ok(notified.find((n) => n.userId === OWNER).body.includes('150 000'));
    await assertLedgerSound();
  });

  await check('LOSS idempotent: trigger/reconcile takrori pulni ikkilamaydi, xabar takrorlanmaydi', async () => {
    const before = { w: await wallet(), c: await bal(pcOf(F1)), fee: await bal(relay.PLATFORM_FEE_ACCOUNT) };
    notified.length = 0;
    const again = await settle(L1);
    assert.strictEqual(again.skipped, 'already_settled');
    const rec = await api.reconcile();
    assert.strictEqual(rec.lossSettled, 0);
    assert.strictEqual(await wallet(), before.w);
    assert.strictEqual(await bal(pcOf(F1)), before.c);
    assert.strictEqual(await bal(relay.PLATFORM_FEE_ACCOUNT), before.fee);
    assert.strictEqual(notified.length, 0);
  });

  const L2 = 'shpLOSS0002';
  await check('LOSS qisman: kuryer hamyoni < G — bor qismi olinadi (manfiy BO\'LMAYDI), qolgani QARZ (cap + incident)', async () => {
    await seedLoss(L2, { courierWallet: 40000, priorDebt: 50000 });
    const r = await settle(L2);
    assert.strictEqual(r.taken, 40000);
    assert.strictEqual(r.outstanding, 110000);
    assert.strictEqual(await bal(pcOf(F1)), 0, 'manfiy emas');
    assert.strictEqual(await bonusOf(F1), 0);
    assert.strictEqual(await wallet(), 60000 + 40000, 'mijoz aynan olingan summani oladi');
    assert.strictEqual(await debtOf(), 50000 + 110000, 'debt.logistics += 110 000 (oldingi qarzga qo\'shiladi)');
    const inc = await incOf(L2);
    assert.strictEqual(inc.status, 'settled');
    assert.strictEqual(inc.refundedNow, 40000);
    assert.strictEqual(inc.outstanding, 110000);
    assert.strictEqual((await ship(L2)).paymentStatus, 'loss_settled');
    assert.strictEqual(await bal(relay.ACCRUAL_ACCOUNT), 0);
    assert.strictEqual(await bal(relay.escrowAccount(L2)), 0);
    const nOwner = notified.find((n) => n.userId === OWNER);
    assert.ok(nOwner.body.includes('40 000') && nOwner.body.includes('110 000'), 'mijozga: qisman + qolgan');
    assert.ok(notified.find((n) => n.userId === F1).body.includes('110 000'), 'kuryerga: qolgan qarz');
    await assertLedgerSound();
  });

  const L3 = 'shpLOSS0003';
  await check('LOSS nol hamyon: kuryer hamyonida pul yo\'q — refund yozuvi YO\'Q, butun G qarz; shunda ham holat yopiladi', async () => {
    await seedLoss(L3, { courierWallet: 0 });
    const w0 = await wallet();
    const r = await settle(L3);
    assert.strictEqual(r.taken, 0);
    assert.strictEqual(r.outstanding, G);
    assert.strictEqual((await journal(`relayLostRefund:${L3}`)).exists, false);
    assert.strictEqual(await wallet(), w0, 'mijoz hamyoni o\'zgarmaydi');
    assert.strictEqual(await bal(pcOf(F1)), 0);
    assert.strictEqual(await debtOf(), G);
    assert.strictEqual((await incOf(L3)).status, 'settled');
    assert.strictEqual((await ship(L3)).paymentStatus, 'loss_settled');
    assert.ok(notified.find((n) => n.userId === OWNER).body.includes('150 000'));
    await assertLedgerSound();
  });

  const L4 = 'shpLOSS0004';
  await check('LOSS poyga: balans o\'qilgach kuryer pul sarflasa — manfiyga tushmaydi, yangi balans bo\'yicha olinadi', async () => {
    await seedLoss(L4, { courierWallet: 200000 });
    let fired = false;
    const hooked = new Proxy(db, {
      get(t, p) {
        if (p !== 'collection') { const v = t[p]; return typeof v === 'function' ? v.bind(t) : v; }
        return (name) => {
          const c = t.collection(name);
          if (name !== settlementLedger.COL_ACCOUNTS) return c;
          return new Proxy(c, {
            get(ct, cp) {
              if (cp !== 'doc') { const v = ct[cp]; return typeof v === 'function' ? v.bind(ct) : v; }
              return (id) => {
                const r = ct.doc(id);
                if (id !== pcOf(F1)) return r;
                return new Proxy(r, {
                  get(rr, rp) {
                    if (rp === 'get') {
                      return async () => {
                        const s = await rr.get();
                        if (!fired) { fired = true; await settlementLedger.postEntry(db, { idempotencyKey: 'spendX:1', kind: 'test_spend', legs: [{ account: pcOf(F1), dr: 170000 }, { account: 'admin_clearing', cr: 170000 }] }); }
                        return s;
                      };
                    }
                    const v = rr[rp]; return typeof v === 'function' ? v.bind(rr) : v;
                  },
                });
              };
            },
          });
        };
      },
    });
    const racy = relay.attachRelayEscrow({}, {
      functions, db: hooked, admin, callerPhone: () => '', canonicalUid: (v) => { const d = digits(v); return d.length === 9 ? `998${d}` : d; },
      settlementLedger, notifyUserInApp: async (m) => { notified.push(m); }, now: () => NOW,
    });
    const r = await racy.onShipmentUpdate({ paymentStatus: 'escrow_funded' }, { paymentStatus: 'loss_pending' }, L4);
    assert.strictEqual(fired, true);
    assert.strictEqual(r.taken, 30000, 'yangi balans (30 000) bo\'yicha');
    assert.strictEqual(await bal(pcOf(F1)), 0);
    assert.strictEqual(await debtOf(), G - 30000);
    assert.strictEqual(await wallet(), 60000 + 30000);
    await assertLedgerSound();
  });

  const L5 = 'shpLOSS0005';
  await check('LOSS 1-LEG da yo\'qoldi (EARNED yo\'q): butun providerPool AVA\'ga, platform_accrual 0', async () => {
    await seedLoss(L5, { atLeg: 0 });
    const r = await settle(L5);
    assert.strictEqual(r.unearned, 192000);
    assert.strictEqual(await bal(relay.PLATFORM_FEE_ACCOUNT), 48000 + 192000);
    assert.strictEqual(await bal(relay.ACCRUAL_ACCOUNT), 0);
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(K1)), 0);
    assert.strictEqual(await bal(relay.escrowAccount(L5)), 0);
    await assertLedgerSound();
  });

  const L6 = 'shpLOSS0006';
  await check('LOSS: oldingi LEG EARNED triggeri yiqilgan bo\'lsa ham settle uni yozadi (K1 haqi yo\'qolmaydi, accrual 0)', async () => {
    await seedLoss(L6, { earnedPosted: false });
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(K1)), 0);
    await settle(L6);
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(K1)), 96000);
    assert.strictEqual(await bal(relay.ACCRUAL_ACCOUNT), 0);
    assert.strictEqual(await bal(relay.PLATFORM_FEE_ACCOUNT), 48000 + 96000);
    await assertLedgerSound();
  });

  const L7 = 'shpLOSS0007';
  await check('LOSS RECONCILE: loss_pending qotib qolgan (trigger yiqilgan) — reconcile tiklaydi, takrori pulni ikkilamaydi', async () => {
    await seedLoss(L7, { courierWallet: 40000 });
    const r = await api.reconcile();
    assert.strictEqual(r.lossSettled, 1);
    assert.strictEqual((await ship(L7)).paymentStatus, 'loss_settled');
    assert.strictEqual(await debtOf(), 110000);
    const w = await wallet();
    const r2 = await api.reconcile();
    assert.strictEqual(r2.lossSettled, 0);
    assert.strictEqual(await wallet(), w);
    assert.strictEqual(await debtOf(), 110000, 'qarz ikkilanmaydi');
    await assertLedgerSound();
  });

  const L8 = 'shpLOSS0008';
  await check('LOSS davom ettirish: eskrou RELEASE allaqachon yozilgan, status hali loss_pending — qolgan qadamlar tugaydi, takror yo\'q', async () => {
    await seedLoss(L8);
    const rel = await api.releaseEscrow(L8, { forLoss: true });
    assert.strictEqual(rel.released, 240000);
    assert.strictEqual((await ship(L8)).paymentStatus, 'loss_pending', 'RELEASE holatni o\'zgartirmaydi');
    const fee0 = await bal(relay.PLATFORM_FEE_ACCOUNT);
    assert.strictEqual(fee0, 48000);
    const r = await settle(L8);
    assert.strictEqual(r.settled, true);
    assert.strictEqual(await bal(relay.PLATFORM_FEE_ACCOUNT), 48000 + 96000, 'RELEASE ikkilanmadi');
    assert.strictEqual(await bal(relay.ACCRUAL_ACCOUNT), 0);
    await assertLedgerSound();
  });

  const L9 = 'shpLOSS0009';
  await check('LOSS: refund yozuvi bor, lekin holat hali loss_pending (sun\'iy) — journal summasi bilan yopiladi, G qayta olinmaydi', async () => {
    await seedLoss(L9);
    await settle(L9);
    // Holatni sun'iy qaytaramiz (atomiklik buzilgan taqdirda ham xavfsiz tiklash).
    await db.collection('shipments').doc(L9).update({ paymentStatus: 'loss_pending' });
    await INC(L9).update({ status: 'declared', refundedNow: null, outstanding: null });
    const w = await wallet();
    const c = await bal(pcOf(F1));
    const r = await settle(L9);
    assert.strictEqual(r.settled, true);
    assert.strictEqual(await wallet(), w, 'mijoz ikkinchi marta olmaydi');
    assert.strictEqual(await bal(pcOf(F1)), c);
    assert.strictEqual((await incOf(L9)).refundedNow, G);
  });

  await check('LOSS: noto\'g\'ri holatlar tegilmaydi — escrow_funded/refunded/pending va incident yo\'q', async () => {
    const L10 = 'shpLOSS0010';
    await seedLoss(L10);
    await db.collection('shipments').doc(L10).update({ paymentStatus: 'escrow_funded' });
    assert.strictEqual((await settle(L10)).skipped, 'payment_escrow_funded');
    assert.strictEqual(await bal(relay.escrowAccount(L10)), 240000, 'eskrou tegilmadi');
    await db.collection('shipments').doc(L10).update({ paymentStatus: 'loss_pending' });
    await INC(L10).delete();
    assert.strictEqual((await settle(L10)).skipped, 'incident_missing');
    assert.strictEqual(await bal(relay.escrowAccount(L10)), 240000, 'incident\'siz pul harakatlanmaydi');
    assert.strictEqual((await ship(L10)).paymentStatus, 'loss_pending');
  });

  await check('LOSS: ichki summa mos emas (providerPool + platformShare != narx) — hech narsa o\'zgarmaydi, loss_pending turadi', async () => {
    const L11 = 'shpLOSS0011';
    await seedLoss(L11, { pool: 100000 });
    const r = await settle(L11);
    assert.strictEqual(r.skipped, 'amount_mismatch');
    assert.strictEqual(await bal(relay.escrowAccount(L11)), 240000);
    assert.strictEqual((await journal(`relayLostRefund:${L11}`)).exists, false);
    assert.strictEqual((await ship(L11)).paymentStatus, 'loss_pending');
  });

  // ── admin to'lovni yozadi ────────────────────────────────────────────
  const P1 = 'shpLOSS0020';
  const pay = (id, amount, opId, who = ADMIN_U, extra = {}) => api.recordLostPayment({ shipmentId: id, amount, opId, ...extra }, asAdmin(who));
  await check('TO\'LOV authz: oddiy foydalanuvchi, kuryer, dispatcher, finance — rad; admin va superadmin — ruxsat', async () => {
    await seedLoss(P1, { courierWallet: 40000 });
    await settle(P1);
    for (const who of [OWNER, F1, DISP_U, FIN_U]) {
      await assert.rejects(() => pay(P1, 1000, 'pay-op-aaaa', who), (e) => e.code === 'permission-denied', who);
    }
    await assert.rejects(() => api.recordLostPayment({ shipmentId: P1, amount: 1000, opId: 'pay-op-aaaa' }, {}), (e) => e.code === 'unauthenticated');
    assert.strictEqual(await debtOf(), 110000, 'rad etilganda hech narsa o\'zgarmadi');
    const r1 = await pay(P1, 10000, 'pay-op-sup1', SUPER_U);
    assert.strictEqual(r1.ok, true);
  });

  await check('TO\'LOV argumentlari: kasr/satr/0/manfiy summa, qisqa opId, noma\'lum jo\'natma', async () => {
    for (const bad of [1.5, '1000', 0, -5, null, undefined, NaN, 2 ** 60]) {
      await assert.rejects(() => pay(P1, bad, 'pay-op-bbbb'), (e) => e.code === 'invalid-argument', String(bad));
    }
    await assert.rejects(() => pay(P1, 1000, 'ab'), (e) => e.code === 'invalid-argument');
    await assert.rejects(() => pay('yoq', 1000, 'pay-op-cccc'), (e) => e.code === 'not-found');
  });

  await check('TO\'LOV: AVA nakd oladi (admin_cash), mijoz hamyoniga o\'tadi; qarz va incident BIR YO\'LA kamayadi; hodisa + audit', async () => {
    // P1: 40 000 olingan, 110 000 qarz; yuqorida 10 000 to'langan (SUPER_U) -> 100 000 qoldi.
    assert.strictEqual(await debtOf(), 100000);
    const cust0 = await wallet();
    const cash0 = await bal('admin_cash');
    const r = await pay(P1, 60000, 'pay-op-0001', ADMIN_U, { note: 'naqd olindi' });
    assert.deepStrictEqual({ ok: r.ok, idempotent: r.idempotent, outstanding: r.outstanding, amount: r.amount }, { ok: true, idempotent: false, outstanding: 40000, amount: 60000 });
    assert.strictEqual(await wallet(), cust0 + 60000);
    assert.strictEqual(await bonusOf(OWNER), cust0 + 60000);
    assert.strictEqual(await bal('admin_cash'), cash0 + 60000);
    assert.strictEqual(await debtOf(), 40000);
    const inc = await incOf(P1);
    assert.strictEqual(inc.outstanding, 40000);
    assert.strictEqual(inc.paidTotal, 70000);
    assert.strictEqual(inc.status, 'settled');
    const j = (await journal(`relayLostPayment:${P1}:pay-op-0001`)).data();
    assert.strictEqual(j.kind, 'logistics_lost_payment');
    assert.strictEqual(j.postedBy, ADMIN_U);
    const dr = j.legs.reduce((s, l) => s + l.dr, 0); const cr = j.legs.reduce((s, l) => s + l.cr, 0);
    assert.strictEqual(dr, cr);
    assert.strictEqual(j.legs.find((l) => l.account === 'admin_cash').dr, 60000);
    assert.strictEqual(j.legs.find((l) => l.account === pcOf(OWNER)).cr, 60000);
    const ev = (await INC(P1).collection('events').doc('payment_pay-op-0001').get()).data();
    assert.strictEqual(ev.amount, 60000); assert.strictEqual(ev.by, ADMIN_U); assert.strictEqual(ev.outstandingAfter, 40000);
    const audit = (await db.collection('logistics_audit').doc(`lost_payment_${P1}_pay-op-0001`).get()).data();
    assert.strictEqual(audit.kind, 'lost_payment'); assert.strictEqual(audit.by, ADMIN_U); assert.strictEqual(audit.amount, 60000);
    assert.ok(notified.some((n) => n.userId === OWNER && n.body.includes('60 000')));
    await assertLedgerSound();
  });

  await check('TO\'LOV idempotent: shu opId qayta — ikkinchi marta o\'tmaydi; shu opId boshqa summa bilan — rad', async () => {
    const w = await wallet(); const d = await debtOf();
    notified.length = 0;
    const again = await pay(P1, 60000, 'pay-op-0001');
    assert.strictEqual(again.idempotent, true);
    assert.strictEqual(again.outstanding, 40000);
    assert.strictEqual(await wallet(), w);
    assert.strictEqual(await debtOf(), d);
    assert.strictEqual(notified.length, 0, 'xabar takrorlanmaydi');
    await assert.rejects(() => pay(P1, 61000, 'pay-op-0001'), (e) => e.code === 'failed-precondition' && e.details.reason === 'op_id_reused');
    assert.strictEqual(await wallet(), w);
  });

  await check('TO\'LOV qarzdan oshmaydi: qolgan 40 000 dan ko\'p — rad, hech narsa o\'zgarmaydi', async () => {
    const w = await wallet(); const d = await debtOf();
    await assert.rejects(() => pay(P1, 40001, 'pay-op-0002'), (e) => e.code === 'failed-precondition' && e.details.reason === 'exceeds_outstanding' && e.details.outstanding === 40000);
    assert.strictEqual(await wallet(), w);
    assert.strictEqual(await debtOf(), d);
    assert.strictEqual((await journal(`relayLostPayment:${P1}:pay-op-0002`)).exists, false);
  });

  await check('TO\'LOV oxirgisi: qarz 0, incident repaid; keyingi to\'lov — nothing_outstanding; takror (shu opId) idempotent', async () => {
    const r = await pay(P1, 40000, 'pay-op-0003');
    assert.strictEqual(r.outstanding, 0);
    assert.strictEqual(await debtOf(), 0);
    const inc = await incOf(P1);
    assert.strictEqual(inc.status, 'repaid');
    assert.strictEqual(inc.paidTotal, 110000);
    assert.strictEqual(inc.refundedNow + inc.paidTotal, G, 'jami mijozga G');
    assert.ok(notified.some((n) => n.userId === OWNER && n.body.includes('150 000')), 'to\'liq qaytarildi xabari');
    await assert.rejects(() => pay(P1, 1000, 'pay-op-0004'), (e) => e.code === 'failed-precondition' && e.details.reason === 'nothing_outstanding');
    const again = await pay(P1, 40000, 'pay-op-0003');
    assert.strictEqual(again.idempotent, true, 'to\'liq to\'langandan keyin ham shu opId idempotent');
    assert.strictEqual(await wallet(), 60000 + G, 'mijoz jami G oldi: 40 000 (kuryer hamyoni) + 110 000 (admin)');
    await assertLedgerSound();
  });

  await check('TO\'LOV holat tekshiruvi: e\'lon qilingan-lekin-hisoblanmagan (loss_not_settled) va incident yo\'q', async () => {
    const P2 = 'shpLOSS0021';
    await seedLoss(P2, { courierWallet: 0 });
    await assert.rejects(() => pay(P2, 1000, 'pay-op-0005'), (e) => e.code === 'failed-precondition' && e.details.reason === 'loss_not_settled');
    await INC(P2).delete();
    await assert.rejects(() => pay(P2, 1000, 'pay-op-0005'), (e) => e.code === 'not-found');
  });

  await check('TO\'LOV parallel: ikki admin 100 000 dan (qarz 150 000) — summa qarzdan OSHMAYDI, faqat bittasi o\'tadi', async () => {
    const P3 = 'shpLOSS0022';
    await seedLoss(P3, { courierWallet: 0 }); // qarz 150 000
    await settle(P3);
    const args = [[100000, 'pay-par-0001', ADMIN_U], [100000, 'pay-par-0002', SUPER_U]];
    const first = await Promise.allSettled(args.map((a) => pay(P3, ...a)));
    // Emulator pessimistik qulflaydi: yutqazgan tranzaksiya ba'zan xom «Transaction is invalid or closed»
    // bilan tugaydi (ishlab chiqarishda SDK o'zi qayta uradi). Mijoz qayta urinadi — natija aniq bo'lishi shart.
    const res = [];
    for (let i = 0; i < first.length; i += 1) {
      const r = first[i];
      if (r.status === 'rejected' && !(r.reason && r.reason.details && r.reason.details.reason)) {
        res.push(await pay(P3, ...args[i]).then((v) => ({ status: 'fulfilled', value: v }), (e) => ({ status: 'rejected', reason: e })));
      } else res.push(r);
    }    const okN = res.filter((r) => r.status === 'fulfilled').length;
    assert.strictEqual(okN, 1, 'ikkalasi 200 000 bo\'lardi > 150 000: faqat bittasi o\'tadi');
    const bad = res.find((r) => r.status === 'rejected');
    assert.ok(bad.reason.details && ['exceeds_outstanding'].includes(bad.reason.details.reason),`yutqazgan xato: code=${bad.reason.code} msg=${bad.reason.message} details=${JSON.stringify(bad.reason.details)}`);
    assert.strictEqual(await debtOf(), 50000);
    assert.strictEqual((await incOf(P3)).outstanding, 50000);
    assert.strictEqual(await wallet(), 60000 + 100000);
    await assertLedgerSound();
  });
}

// ═══════════════════════════════════════════════════════════════════
// ADMIN: yo'qolish hodisalari ro'yxati (`adminListLossIncidents`) - faqat o'qish, PII maskalanadi
// ═══════════════════════════════════════════════════════════════════
async function listTests() {
  const ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);
  const seedInc = (id, ms, over = {}) => INC(id).set({
    type: 'lost', status: 'declared', shipmentId: id, trackingNumber: `AVA-${id}`, legId: 'leg1', legIndex: 1,
    courier: { uid: F1, accountId: ACC_F1 }, customer: { uid: OWNER }, goodsValue: 150000,
    customerPrice: 240000, tariffVersion: 7, refundedNow: null, outstanding: null, paidTotal: 0,
    declaredBy: ADMIN_U, reason: 'yo\'lda yo\'qoldi', note: 'MIJOZ-IZOHI-MAXFIY Gurlan, 5-uy', opId: `lost-op-${id}`,
    declaredAt: ts(ms), updatedAt: ts(ms), ...over,
  });
  const list = (data, who = ADMIN_U) => api.listLossIncidents(data, asAdmin(who));

  await check('RO\'YXAT authz: oddiy foydalanuvchi, kuryer, dispatcher, finance, kirmagan - rad; admin va superadmin - ruxsat', async () => {
    await resetAll();
    for (const [uid, role] of [[ADMIN_U, 'admin'], [SUPER_U, 'superadmin'], [DISP_U, 'dispatcher'], [FIN_U, 'finance']]) {
      await db.collection('users').doc(uid).set({ role });
    }
    await db.collection('users').doc(OWNER).set({ role: 'user' });
    await db.collection('users').doc(F1).set({ role: 'user' });
    await seedInc('incA', 1000);
    for (const who of [OWNER, F1, DISP_U, FIN_U]) {
      await assert.rejects(() => list({}, who), (e) => e.code === 'permission-denied', who);
    }
    await assert.rejects(() => api.listLossIncidents({}, {}), (e) => e.code === 'unauthenticated');
    assert.strictEqual((await list({}, ADMIN_U)).ok, true);
    assert.strictEqual((await list({}, SUPER_U)).ok, true);
  });

  await check('RO\'YXAT shakli: id/shipmentId, status, goodsValue, refundedNow, outstanding, paidTotal, declaredAtMs, kuryer (maskalangan), sabab, tracking; mijoz/izoh YO\'Q', async () => {
    await resetAll();
    await db.collection('users').doc(ADMIN_U).set({ role: 'admin' });
    await seedInc('incS', 5000, {
      status: 'settled', refundedNow: 100000, outstanding: 50000, paidTotal: 20000,
    });
    const r = await list({});
    assert.strictEqual(r.ok, true);
    assert.strictEqual(r.items.length, 1);
    const it = r.items[0];
    assert.deepStrictEqual(it, {
      id: 'incS', shipmentId: 'incS', trackingNumber: 'AVA-incS', status: 'settled', goodsValue: 150000,
      refundedNow: 100000, outstanding: 50000, paidTotal: 20000, declaredAtMs: 5000,
      courierPhoneMasked: '***0004', courierAccountId: ACC_F1, reason: 'yo\'lda yo\'qoldi', legId: 'leg1',
    });
    const dump = JSON.stringify(r);
    assert.ok(!dump.includes(F1), 'kuryer telefoni to\'liq chiqmaydi');
    assert.ok(!dump.includes(OWNER), 'mijoz telefoni chiqmaydi');
    assert.ok(!dump.includes('MAXFIY'), 'izoh (note) chiqmaydi');
    assert.ok(!/customerPrice|tariffVersion|declaredBy|opId|note|customer/.test(dump), 'ichki/mijoz maydonlari yo\'q');
  });

  await check('RO\'YXAT hisoblanmagan (declared): refundedNow/outstanding null qaytadi; status declared', async () => {
    const r = await list({});
    await seedInc('incD', 9000);
    const r2 = await list({});
    const it = r2.items.find((x) => x.id === 'incD');
    assert.strictEqual(it.status, 'declared');
    assert.strictEqual(it.refundedNow, null);
    assert.strictEqual(it.outstanding, null);
    assert.strictEqual(r.items.length, 1);
  });

  await check('RO\'YXAT tartibi: eng yangisi birinchi (declaredAt kamayish); limit=2 faqat 2 ta', async () => {
    await resetAll();
    await db.collection('users').doc(ADMIN_U).set({ role: 'admin' });
    await seedInc('o1', 1000); await seedInc('o3', 3000); await seedInc('o2', 2000); await seedInc('o4', 4000);
    const all = await list({});
    assert.deepStrictEqual(all.items.map((x) => x.id), ['o4', 'o3', 'o2', 'o1']);
    const two = await list({ limit: 2 });
    assert.deepStrictEqual(two.items.map((x) => x.id), ['o4', 'o3']);
  });

  await check('RO\'YXAT limit: standart 50, eng ko\'pi 100 (katta qiymat qisqartiriladi); noto\'g\'ri limit - invalid-argument', async () => {
    await resetAll();
    await db.collection('users').doc(ADMIN_U).set({ role: 'admin' });
    for (let start = 0; start < 120; start += 40) {
      const b = db.batch();
      for (let i = start; i < start + 40; i += 1) {
        b.set(INC(`bulk${String(i).padStart(3, '0')}`), {
          type: 'lost', status: 'declared', shipmentId: `bulk${i}`, goodsValue: 1000, courier: { uid: F1 },
          declaredAt: ts(10000 + i),
        });
      }
      await b.commit();
    }
    assert.strictEqual((await list({})).items.length, 50, 'standart 50');
    assert.strictEqual((await list(undefined)).items.length, 50, 'data yo\'q - standart');
    assert.strictEqual((await list({ limit: 100 })).items.length, 100);
    assert.strictEqual((await list({ limit: 5000 })).items.length, 100, 'eng ko\'pi 100');
    assert.strictEqual((await list({ limit: 1 })).items.length, 1);
    for (const bad of [0, -3, 1.5, '10', NaN, null, true]) {
      await assert.rejects(() => list({ limit: bad }), (e) => e.code === 'invalid-argument', String(bad));
    }
    const top = (await list({ limit: 3 })).items.map((x) => x.id);
    assert.deepStrictEqual(top, ['bulk119', 'bulk118', 'bulk117']);
  });

  await check('RO\'YXAT faqat o\'qish: hech narsa yozilmaydi (incident o\'zgarmaydi, journal/audit yo\'q)', async () => {
    await resetAll();
    await db.collection('users').doc(ADMIN_U).set({ role: 'admin' });
    await seedInc('ro1', 1000);
    const before = JSON.stringify(await incOf('ro1'));
    await list({});
    assert.strictEqual(JSON.stringify(await incOf('ro1')), before);
    assert.strictEqual((await db.collection(settlementLedger.COL_JOURNAL).get()).size, 0);
    assert.strictEqual((await db.collection('logistics_audit').get()).size, 0);
  });
}

async function main() {
  const S = 'shpTEST0001';
  await seedShipment(S);

  await check('FUND: hamyon → eskrou, holat escrow_funded/ready AYNI tranzaksiyada', async () => {
    const r = await api.fund({ shipmentId: S }, ctx);
    assert.strictEqual(r.paymentStatus, 'escrow_funded'); assert.strictEqual(r.amount, 240000);
    assert.strictEqual(await wallet(), 60000);
    assert.strictEqual(await bal(relay.escrowAccount(S)), 240000);
    const s = await ship(S);
    assert.strictEqual(s.status, 'ready'); assert.strictEqual(s.paymentStatus, 'escrow_funded');
    assert.strictEqual(s.escrowAmount, 240000);
    assert.strictEqual((await db.collection('users').doc(OWNER).get()).data().bonusBalance, 60000, 'bonusBalance ko\'zgusi');
  });
  await check('FUND idempotent: ikkinchi chaqiruv pul olmaydi', async () => {
    const r = await api.fund({ shipmentId: S }, ctx);
    assert.strictEqual(r.idempotent, true);
    assert.strictEqual(await wallet(), 60000);
  });
  await check('FUND: egasi bo\'lmagan — permission-denied', async () => {
    await assert.rejects(() => api.fund({ shipmentId: S }, { auth: { token: { phone_number: `+${K1}` } } }), (e) => e.code === 'permission-denied');
  });

  await check('EARNED (LEG-1 tugadi): payable K1 +96 000, eskrou O\'ZGARMAYDI', async () => {
    const r = await api.onCustodyEvent({
      shipmentId: S, legId: 'leg1', kind: 'pickup', completesLegId: 'leg0', completedLegProviderId: K1,
      completedLegPayout: 96000, legIndex: 1, deliversShipment: false,
    });
    assert.strictEqual(r.earned.earned, 96000);
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(K1)), 96000);
    assert.strictEqual(await bal(relay.escrowAccount(S)), 240000, 'eskrou to\'liq turadi (7.6)');
    assert.strictEqual(await bal(relay.ACCRUAL_ACCOUNT), -96000);
    const again = await api.onCustodyEvent({ shipmentId: S, completesLegId: 'leg0', completedLegProviderId: K1, completedLegPayout: 96000 });
    assert.strictEqual(again.earned.idempotent, true);
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(K1)), 96000, 'takror trigger — takror pul yo\'q');
  });

  await check('DELIVERED: EARNED F1 + RELEASE: eskrou 0, AVA ulushi 48 000, payable pool yopildi, settled, xabar', async () => {
    const r = await api.onCustodyEvent({
      shipmentId: S, legId: 'leg1', kind: 'delivery', completesLegId: 'leg1', completedLegProviderId: F1,
      completedLegPayout: 96000, legIndex: 1, deliversShipment: true, trackingNumber: 'AVA-26-1007-000001',
    });
    assert.strictEqual(r.release.released, 240000);
    assert.strictEqual(await bal(relay.escrowAccount(S)), 0);
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(F1)), 96000);
    assert.strictEqual(await bal(relay.PLATFORM_FEE_ACCOUNT), 48000);
    assert.strictEqual(await bal(relay.ACCRUAL_ACCOUNT), 0, 'EARNED (−192 000) + RELEASE (+192 000) = 0');
    assert.strictEqual((await ship(S)).paymentStatus, 'settled');
    assert.strictEqual(notified.length, 1);
    const j = await db.collection(settlementLedger.COL_JOURNAL).doc(`relayRelease:${S}`).get();
    const dr = j.data().legs.reduce((s, l) => s + l.dr, 0); const cr = j.data().legs.reduce((s, l) => s + l.cr, 0);
    assert.strictEqual(dr, cr);
  });
  await check('RELEASE idempotent', async () => {
    const r = await api.releaseEscrow(S);
    assert.strictEqual(r.skipped, 'already_settled');
    assert.strictEqual(await bal(relay.PLATFORM_FEE_ACCOUNT), 48000);
  });

  const S2 = 'shpTEST0002';
  await seedShipment(S2, { wallet: 100000 });
  await check('FUND: hamyon yetmasa — rad, holat o\'zgarmaydi, pul olinmaydi', async () => {
    await assert.rejects(() => api.fund({ shipmentId: S2 }, ctx), (e) => e.code === 'failed-precondition' && e.details.reason === 'insufficient' && e.details.shortfall === 140000);
    assert.strictEqual(await wallet(), 100000);
    assert.strictEqual((await ship(S2)).paymentStatus, 'pending');
  });

  const S3 = 'shpTEST0003';
  await seedShipment(S3);
  await check('REFUND: bekor (refund_pending) → eskrou hamyonga, refunded; idempotent', async () => {
    await api.fund({ shipmentId: S3 }, ctx);
    assert.strictEqual(await wallet(), 60000);
    // demand codebase bekor qildi:
    const before = await ship(S3);
    await db.collection('shipments').doc(S3).update({ status: 'cancelled', paymentStatus: 'refund_pending' });
    const r = await api.onShipmentUpdate(before, await ship(S3), S3);
    assert.strictEqual(r.refunded, 240000);
    assert.strictEqual(await wallet(), 300000);
    assert.strictEqual(await bal(relay.escrowAccount(S3)), 0);
    assert.strictEqual((await ship(S3)).paymentStatus, 'refunded');
    const again = await api.onShipmentUpdate({ paymentStatus: 'pending' }, await ship(S3), S3);
    assert.strictEqual(again.skipped, 'payment_refunded');
    assert.strictEqual(await wallet(), 300000);
  });

  const S4 = 'shpTEST0004';
  await seedShipment(S4);
  await check('FROZEN (nizo): yetkazilsa ham RELEASE qilinmaydi', async () => {
    await api.fund({ shipmentId: S4 }, ctx);
    await db.collection('shipments').doc(S4).update({ paymentStatus: 'escrow_frozen' });
    const r = await api.onCustodyEvent({ shipmentId: S4, completesLegId: 'leg1', completedLegProviderId: F1, completedLegPayout: 96000, deliversShipment: true });
    assert.strictEqual(r.release.skipped, 'frozen');
    assert.strictEqual(await bal(relay.escrowAccount(S4)), 240000);
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(F1)), 96000, 'EARNED baribir yoziladi — mehnat yo\'qolmaydi');
  });

  const S5 = 'shpTEST0005';
  await seedShipment(S5, { platformShare: 48000, pool: 100000 });
  await check('RELEASE: ichki summa mos kelmasa — yozilmaydi (xato logga)', async () => {
    await api.fund({ shipmentId: S5 }, ctx);
    const r = await api.releaseEscrow(S5);
    assert.strictEqual(r.skipped, 'amount_mismatch');
    assert.strictEqual(await bal(relay.escrowAccount(S5)), 240000);
  });

  // R2/R3 (L2, L1-natija): trigger yiqilsa ham pul qotib qolmasin — reconcile tiklaydi.
  const S6 = 'shpTEST0006';
  await seedShipment(S6);
  await check('RECONCILE: refund_pending qotib qolgan (trigger yiqilgan) → refunded', async () => {
    await api.fund({ shipmentId: S6 }, ctx);
    await db.collection('shipments').doc(S6).update({ status: 'cancelled', paymentStatus: 'refund_pending' });
    const r = await api.reconcile();
    assert.strictEqual(r.refunded, 1);
    assert.strictEqual(await wallet(), 300000);
    assert.strictEqual((await ship(S6)).paymentStatus, 'refunded');
  });
  const S7 = 'shpTEST0007';
  await seedShipment(S7);
  await check('RECONCILE: bekor qilingan, lekin escrow_funded qolgan (cancel/fund poygasi) → refund', async () => {
    await api.fund({ shipmentId: S7 }, ctx);
    await db.collection('shipments').doc(S7).update({ status: 'cancelled' });
    const r = await api.reconcile();
    assert.strictEqual(r.refunded, 1);
    assert.strictEqual(await wallet(), 300000);
    assert.strictEqual(await bal(relay.escrowAccount(S7)), 0);
    assert.strictEqual((await ship(S7)).paymentStatus, 'refunded');
    const again = await api.reconcile();
    assert.strictEqual(again.refunded, 0, 'takror reconcile pul qaytarmaydi');
    assert.strictEqual(await wallet(), 300000);
  });
  const S8 = 'shpTEST0008';
  await seedShipment(S8);
  await check('RECONCILE: delivered, lekin RELEASE/EARNED yozilmagan → settled, ijrochilarga payable, takror ikkilamaydi', async () => {
    await api.fund({ shipmentId: S8 }, ctx);
    await db.collection('shipments').doc(S8).update({ status: 'delivered' });
    await db.collection('custody_events').doc('e1').set({
      shipmentId: S8, legId: 'leg1', completesLegId: 'leg0', completedLegProviderId: K1,
      completedLegPayout: 96000, deliversShipment: false,
    });
    await db.collection('custody_events').doc('e2').set({
      shipmentId: S8, legId: 'leg1', completesLegId: 'leg1', completedLegProviderId: F1,
      completedLegPayout: 96000, deliversShipment: true,
    });
    const r = await api.reconcile();
    assert.strictEqual(r.released, 1);
    assert.strictEqual((await ship(S8)).paymentStatus, 'settled');
    assert.strictEqual(await bal(relay.escrowAccount(S8)), 0);
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(K1)), 96000);
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(F1)), 96000);
    assert.strictEqual(await bal(relay.PLATFORM_FEE_ACCOUNT), 48000);
    await api.reconcile();
    assert.strictEqual(await bal(relay.PLATFORM_FEE_ACCOUNT), 48000);
    assert.strictEqual(await bal(settlementLedger.supplierPayableAccount(K1)), 96000);
  });
  await check('RECONCILE: escrow_frozen (nizo) ga tegilmaydi', async () => {
    const S9 = 'shpTEST0009';
    await seedShipment(S9);
    await api.fund({ shipmentId: S9 }, ctx);
    await db.collection('shipments').doc(S9).update({ status: 'delivered', paymentStatus: 'escrow_frozen' });
    await api.reconcile();
    assert.strictEqual(await bal(relay.escrowAccount(S9)), 240000);
    assert.strictEqual((await ship(S9)).paymentStatus, 'escrow_frozen');
  });

  await lossTests();
  await listTests();

  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} relay escrow CF checks passed.`);
  if (failed.length) process.exitCode = 1;
}
main().catch((e) => { console.error('FATAL', e); process.exitCode = 1; });
