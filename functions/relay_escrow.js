'use strict';

/**
 * AVA LOGISTICS — ESKROU (D-11; relay hujjati 7.6). Default codebase.
 *
 * NEGA SHU CODEBASE: pul faqat `settlement_ledger.js` (ikki yozuvli
 * jurnal) orqali yuradi — u shu yerda (43-band: ikkinchi ledger yo'q).
 * ORDER/SHIPMENT/LEG/custody esa `functions_demand` da. Ikkisi Firestore
 * hujjatlari orqali bog'lanadi:
 *
 *   demand  → shipments.{status, paymentStatus}, custody_events (yozadi)
 *   default → ledger yozuvlari + shipments.paymentStatus (escrow_funded,
 *             settled, refunded)
 *
 * ── HISOB REJASI (mavjud nomlar bilan, 5-band) ─────────────────────────
 *   escrow:{shipmentId}            mijozning deponentlangan puli (liability)
 *   passenger_credit:{uid}         mijoz AVA hamyoni (mavjud)
 *   supplier_payable:{providerId}  ijrochi ISHLAB TOPGAN, hali TO'LANMAGAN (mavjud)
 *   platform_accrual               EARNED ≠ PAID oralig'i (liability)
 *   earnings:ava_logistics_fee     AVA ulushi (taksidagi `earnings:ava_taxi_fee` kabi)
 *
 *   1. FUND     Dr passenger_credit:{uid}   Cr escrow:{shipmentId}        customerPrice
 *   2. EARNED   Dr platform_accrual         Cr supplier_payable:{prov}    legPayout   (LEG tugadi)
 *   3. RELEASE  Dr escrow:{shipmentId}      Cr platform_accrual           providerPool
 *                                           Cr earnings:ava_logistics_fee  platformShare   (DELIVERED)
 *   4. REFUND   Dr escrow:{shipmentId}      Cr passenger_credit:{uid}     customerPrice   (bekor)
 *
 * Hujjat 7.6 `earnings:{providerId}` / `platform_revenue` degan edi —
 * repoda `supplier_payable` (ijrochiga qarz) va `earnings:ava_*` (AVA
 * daromadi) allaqachon shu ma'noda ishlatiladi, shuning uchun o'shalar.
 *
 * PAYOUT (4-qadam, bank) — mavjud `requestPayout`/`payout_requests` oqimi;
 * bu modul unga tegmaydi.
 *
 * ── INVARIANTLAR ───────────────────────────────────────────────────────
 *   - Har yozuv idempotent (`journal_entries/{key}`): trigger qayta
 *     ishlasa ikkinchi yozuv yo'q (21-band).
 *   - Eskrou RELEASE'gacha to'liq: EARNED uni kamaytirmaydi (7.6).
 *   - `escrow_frozen` (nizo) bo'lsa RELEASE qilinmaydi.
 *   - Butun so'm, `assert` bilan hamyon manfiyga tushmaydi.
 */

const SHIPMENTS = 'shipments';
const CUSTODY = 'custody_events';
const PLATFORM_FEE_ACCOUNT = 'earnings:ava_logistics_fee';
const ACCRUAL_ACCOUNT = 'platform_accrual';

const escrowAccount = (shipmentId) => `escrow:${shipmentId}`;

function attachRelayEscrow(exports, deps) {
  const {
    functions, db, admin, callerPhone, canonicalUid, settlementLedger, notifyUserInApp, now: nowFn,
  } = deps;
  const now = () => (nowFn ? nowFn() : new Date());
  const err = (code, msg, extra) => new functions.https.HttpsError(code, msg, extra);

  /** Token telefoni → users hujjati (9/12 xonali) */
  async function resolveCaller(context) {
    if (!context || !context.auth) throw err('unauthenticated', 'Login required');
    const phone = canonicalUid(callerPhone(context));
    if (phone.length !== 12) throw err('unauthenticated', 'Telefon claim yo\'q');
    for (const id of [phone, phone.slice(3)]) {
      const s = await db.collection('users').doc(id).get();
      if (s.exists) return { phone, usersDocId: s.ref.id };
    }
    throw err('failed-precondition', 'users hujjati yo\'q', { reason: 'no_user' });
  }

  // ── 1. FUND — mijoz hamyoni → eskrou ─────────────────────────────────
  async function fund(data, context) {
    // Egalik — `users` hujjatidan OLDIN (19-band: kim? → ruxsat bormi?):
    // begona odam `users` hujjati bo'lmasa ham aniq `permission-denied` oladi.
    const phone = canonicalUid(callerPhone(context));
    if (phone.length !== 12) throw err('unauthenticated', 'Telefon claim yo\'q');
    const shipmentId = String((data || {}).shipmentId || '');
    if (!shipmentId) throw err('invalid-argument', 'shipmentId');
    const shipRef = db.collection(SHIPMENTS).doc(shipmentId);
    const pre0 = await shipRef.get();
    if (!pre0.exists) throw err('not-found', 'Jo\'natma topilmadi');
    const ship0 = pre0.data() || {};
    if (ship0.ownerId !== phone) throw err('permission-denied', 'Bu jo\'natma sizniki emas');
    const me = await resolveCaller(context);
    const amount = Number((ship0.priceSnapshot || {}).customerPrice);
    if (!Number.isInteger(amount) || amount <= 0) throw err('failed-precondition', 'Narx yo\'q', { reason: 'no_price' });
    if (ship0.paymentStatus === 'escrow_funded') {
      return { shipmentId, paymentStatus: 'escrow_funded', amount, idempotent: true };
    }

    const key = `relayEscrow:${shipmentId}:v1`;
    const when = now();
    try {
      const res = await settlementLedger.postEntry(db, {
        idempotencyKey: key,
        kind: 'logistics_escrow_fund',
        refType: 'shipment',
        refId: shipmentId,
        postedBy: me.phone,
        postedRole: 'client',
        legs: [
          { account: settlementLedger.passengerCreditAccount(me.usersDocId), dr: amount },
          { account: escrowAccount(shipmentId), cr: amount },
        ],
      }, {
        mirrorBonus: true,
        walletLedgerType: 'logistics_escrow',
        meta: { shipmentId, trackingNumber: ship0.trackingNumber || '' },
        // READ fazasi — holat tranzaksiya ichida qayta tekshiriladi.
        precheck: async (tx) => {
          const s = await tx.get(shipRef);
          const d = s.exists ? (s.data() || {}) : null;
          if (!d) throw Object.assign(new Error('shipment_missing'), { reason: 'shipment_missing' });
          if (d.ownerId !== me.phone) throw Object.assign(new Error('not_owner'), { reason: 'not_owner' });
          if (d.status !== 'awaiting_payment' || d.paymentStatus !== 'pending') {
            throw Object.assign(new Error('not_payable'), { reason: 'not_payable', status: d.status, paymentStatus: d.paymentStatus });
          }
          return d;
        },
        // D-TAXI-23 bilan bir xil: hamyon manfiyga tushmasin.
        assert: ({ accounts }) => {
          const st = accounts.get(settlementLedger.passengerCreditAccount(me.usersDocId));
          if (st && st.next < 0) throw Object.assign(new Error('insufficient'), { reason: 'insufficient', shortfall: -st.next });
        },
        // Yozuv fazasi — holat AYNI tranzaksiyada.
        onCommit: (tx) => {
          tx.update(shipRef, {
            paymentStatus: 'escrow_funded', status: 'ready', fundedAt: when,
            escrowEntryId: key, escrowAmount: amount, updatedAt: when,
          });
        },
      });
      return { shipmentId, paymentStatus: 'escrow_funded', amount, idempotent: res.idempotent === true };
    } catch (e) {
      if (e && e.reason === 'insufficient') {
        throw err('failed-precondition', 'Hamyonda mablag\' yetarli emas', { reason: 'insufficient', shortfall: e.shortfall, amount });
      }
      if (e && e.reason) throw err('failed-precondition', 'To\'lab bo\'lmaydi', { reason: e.reason, status: e.status, paymentStatus: e.paymentStatus });
      throw e;
    }
  }

  // ── 2. EARNED — LEG tugadi → ijrochiga qarz ──────────────────────────
  async function postEarned(event) {
    const legId = String(event.completesLegId || '');
    const providerId = canonicalUid(event.completedLegProviderId || '');
    const amount = Number(event.completedLegPayout) || 0;
    if (!legId || !providerId || amount <= 0) return { skipped: 'no_payout' };
    const res = await settlementLedger.postEntry(db, {
      idempotencyKey: `relayEarned:${event.shipmentId}:${legId}`,
      kind: 'logistics_leg_earned',
      refType: 'shipment',
      refId: String(event.shipmentId),
      postedBy: 'system',
      postedRole: 'system',
      legs: [
        { account: ACCRUAL_ACCOUNT, dr: amount },
        { account: settlementLedger.supplierPayableAccount(providerId), cr: amount },
      ],
    }, {
      mirrorBonus: false,
      // Firestore `undefined`ni rad etadi — hodisada legIndex bo'lmasa null.
      meta: {
        shipmentId: String(event.shipmentId), legId, providerId,
        legIndex: Number.isInteger(event.legIndex) ? event.legIndex : null,
      },
    });
    return { earned: amount, providerId, idempotent: res.idempotent };
  }

  // ── 3. RELEASE — DELIVERED → eskrou yechiladi ────────────────────────
  async function releaseEscrow(shipmentId) {
    const shipRef = db.collection(SHIPMENTS).doc(shipmentId);
    const [shipSnap, internalSnap] = await Promise.all([
      shipRef.get(), shipRef.collection('private').doc('internal').get(),
    ]);
    if (!shipSnap.exists) return { skipped: 'shipment_missing' };
    const ship = shipSnap.data() || {};
    const internal = internalSnap.exists ? (internalSnap.data() || {}) : {};
    if (ship.paymentStatus === 'settled') return { skipped: 'already_settled' };
    if (ship.paymentStatus === 'escrow_frozen') return { skipped: 'frozen' };
    if (ship.paymentStatus !== 'escrow_funded') return { skipped: `payment_${ship.paymentStatus}` };
    const amount = Number((ship.priceSnapshot || {}).customerPrice) || 0;
    const platformShare = Number(internal.platformShare) || 0;
    const providerPool = Number(internal.providerPool) || 0;
    if (amount <= 0 || platformShare + providerPool !== amount) {
      console.error(`relay release: summa mos emas (${shipmentId}): ${amount} != ${platformShare}+${providerPool}`);
      return { skipped: 'amount_mismatch' };
    }
    const legs = [{ account: escrowAccount(shipmentId), dr: amount }];
    if (providerPool > 0) legs.push({ account: ACCRUAL_ACCOUNT, cr: providerPool });
    if (platformShare > 0) legs.push({ account: PLATFORM_FEE_ACCOUNT, cr: platformShare });
    const when = now();
    const res = await settlementLedger.postEntry(db, {
      idempotencyKey: `relayRelease:${shipmentId}`,
      kind: 'logistics_escrow_release',
      refType: 'shipment',
      refId: shipmentId,
      postedBy: 'system',
      postedRole: 'system',
      legs,
    }, {
      mirrorBonus: false,
      meta: { shipmentId, platformShare, providerPool },
      precheck: async (tx) => {
        const s = await tx.get(shipRef);
        const d = s.exists ? (s.data() || {}) : {};
        if (d.paymentStatus !== 'escrow_funded') throw Object.assign(new Error('not_funded'), { reason: 'not_funded' });
        return d;
      },
      onCommit: (tx) => {
        tx.update(shipRef, { paymentStatus: 'settled', settledAt: when, releaseEntryId: `relayRelease:${shipmentId}`, updatedAt: when });
      },
    });
    return { released: amount, platformShare, providerPool, idempotent: res.idempotent };
  }

  // ── 4. REFUND — bekor → eskrou mijozga ───────────────────────────────
  async function refundEscrow(shipmentId) {
    const shipRef = db.collection(SHIPMENTS).doc(shipmentId);
    const snap = await shipRef.get();
    if (!snap.exists) return { skipped: 'shipment_missing' };
    const ship = snap.data() || {};
    if (ship.paymentStatus === 'refunded') return { skipped: 'already_refunded' };
    if (ship.paymentStatus !== 'refund_pending') return { skipped: `payment_${ship.paymentStatus}` };
    const amount = Number(ship.escrowAmount || (ship.priceSnapshot || {}).customerPrice) || 0;
    if (amount <= 0) return { skipped: 'no_amount' };
    const owner = canonicalUid(ship.ownerId);
    // Hamyon hujjati 9 yoki 12 xonali bo'lishi mumkin — eskrou qaysi
    // hisobdan to'ldirilgan bo'lsa, o'shanga qaytadi (journal'dan).
    let usersDocId = owner;
    if (ship.escrowEntryId) {
      const j = await db.collection(settlementLedger.COL_JOURNAL).doc(ship.escrowEntryId).get();
      const drLeg = j.exists ? ((j.data() || {}).legs || []).find((l) => l.dr > 0) : null;
      if (drLeg && drLeg.account.startsWith('passenger_credit:')) usersDocId = drLeg.account.slice('passenger_credit:'.length);
    }
    const when = now();
    const res = await settlementLedger.postEntry(db, {
      idempotencyKey: `relayRefund:${shipmentId}`,
      kind: 'logistics_escrow_refund',
      refType: 'shipment',
      refId: shipmentId,
      postedBy: 'system',
      postedRole: 'system',
      legs: [
        { account: escrowAccount(shipmentId), dr: amount },
        { account: settlementLedger.passengerCreditAccount(usersDocId), cr: amount },
      ],
    }, {
      mirrorBonus: true,
      walletLedgerType: 'logistics_refund',
      meta: { shipmentId, trackingNumber: ship.trackingNumber || '' },
      precheck: async (tx) => {
        const s = await tx.get(shipRef);
        if ((s.data() || {}).paymentStatus !== 'refund_pending') throw Object.assign(new Error('not_pending'), { reason: 'not_pending' });
        return s.data();
      },
      onCommit: (tx) => {
        tx.update(shipRef, { paymentStatus: 'refunded', refundedAt: when, refundEntryId: `relayRefund:${shipmentId}`, updatedAt: when });
      },
    });
    return { refunded: amount, idempotent: res.idempotent };
  }

  // ── Triggerlar ───────────────────────────────────────────────────────
  /** custody_events onCreate: LEG tugadi → EARNED; yetkazildi → RELEASE. */
  async function onCustodyEvent(event) {
    const out = {};
    try {
      out.earned = await postEarned(event);
    } catch (e) {
      console.error(`relay EARNED xato (${event.shipmentId}/${event.completesLegId}): ${e.message}`);
    }
    if (event.deliversShipment === true) {
      try {
        out.release = await releaseEscrow(String(event.shipmentId));
      } catch (e) {
        if (!(e && e.reason === 'not_funded')) console.error(`relay RELEASE xato (${event.shipmentId}): ${e.message}`);
      }
      if (notifyUserInApp && out.release && out.release.released) {
        const s = await db.collection(SHIPMENTS).doc(String(event.shipmentId)).get();
        const owner = s.exists ? (s.data() || {}).ownerId : '';
        if (owner) {
          await notifyUserInApp({
            userId: owner,
            title: 'Jo\'natma yetkazildi',
            body: `${event.trackingNumber || ''} jo'natmangiz qabul qiluvchiga topshirildi.`,
            category: 'info', source: 'logistics', dataType: 'logistics_delivered',
          });
        }
      }
    }
    return out;
  }

  /** shipments onUpdate: `refund_pending` → REFUND. */
  async function onShipmentUpdate(before, after, shipmentId) {
    const ap = (after || {}).paymentStatus;
    const bp = (before || {}).paymentStatus;
    if (ap === 'refund_pending' && bp !== 'refund_pending') {
      try { return await refundEscrow(shipmentId); } catch (e) {
        if (!(e && e.reason === 'not_pending')) console.error(`relay REFUND xato (${shipmentId}): ${e.message}`);
      }
    }
    // Takror trigger (retry) yoki boshqa o'tish — pul harakati yo'q; sabab
    // holat bo'yicha, logda ajratish oson bo'lsin.
    return { skipped: ap === 'refund_pending' ? 'no_change' : `payment_${ap || 'none'}` };
  }

  exports.fundShipmentEscrow = functions.https.onCall(fund);
  exports.onLogisticsCustodyEvent = functions.firestore
    .document(`${CUSTODY}/{eventId}`)
    .onCreate(async (snap) => { await onCustodyEvent(snap.data() || {}); return null; });
  exports.onLogisticsShipmentUpdate = functions.firestore
    .document(`${SHIPMENTS}/{shipmentId}`)
    .onUpdate(async (change, context) => {
      await onShipmentUpdate(change.before.data() || {}, change.after.data() || {}, context.params.shipmentId);
      return null;
    });

  return {
    fund, postEarned, releaseEscrow, refundEscrow, onCustodyEvent, onShipmentUpdate, resolveCaller,
  };
}

module.exports = {
  SHIPMENTS, CUSTODY, PLATFORM_FEE_ACCOUNT, ACCRUAL_ACCOUNT, escrowAccount, attachRelayEscrow,
};
