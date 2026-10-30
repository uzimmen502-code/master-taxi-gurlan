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
 *
 * ── YO'QOLGAN POSILKA (D1, ega qarori 2026-10-16) ──────────────────────
 * Demand codebase `adminMarkShipmentLost` jo'natmani `lost` + `paymentStatus: loss_pending`
 * qiladi va `logistics_incidents/{shipmentId}` yozadi (G = priceSnapshot.declaredValue,
 * kuryer, mijoz). Bu yerda `settleLoss` (trigger + reconcile; har qadam idempotent):
 *   a) EARNED  — oldingi (tugagan) LEG'lar ijrochilariga haq SAQLANADI (kutilmagan trigger yiqilishi ham tiklanadi);
 *   b) RELEASE — odatdagi `relayRelease:{id}` (eskrou -> accrual + AVA ulushi), holat `loss_pending` qoladi;
 *   c) UNEARNED— Dr platform_accrual U / Cr earnings:ava_logistics_fee U, U = providerPool − Σ EARNED
 *                (tugallanmagan LEG'lar ulushi AVA daromadiga): `relayLostUnearned:{id}`;
 *   d) REFUND  — Dr passenger_credit:{kuryer} take / Cr passenger_credit:{mijoz} take, take = min(G, kuryer
 *                hamyoni) (manfiy BO'LMAYDI): `relayLostRefund:{id}`; shu tranzaksiyada holat `loss_settled`,
 *                incident (`settled|repaid`), qarz `provider_capabilities.debt.logistics += G − take`.
 * AVA o'z cho'ntagidan to'lamaydi va qarzni o'zi undirmaydi: kuryer to'laydi, ADMIN
 * `adminRecordLostParcelPayment` bilan yozadi (Dr admin_cash / Cr passenger_credit:{mijoz}, admin_clearing
 * orqali — `cashExchange` naqshi), qarz va incident AYNI tranzaksiyada kamayadi.
 */

const i18n = require('./notif_i18n');

const SHIPMENTS = 'shipments';
const CUSTODY = 'custody_events';
const INCIDENTS = 'logistics_incidents';
const LOGISTICS_AUDIT = 'logistics_audit';
const CAPS = 'provider_capabilities';
const PLATFORM_FEE_ACCOUNT = 'earnings:ava_logistics_fee';
const ACCRUAL_ACCOUNT = 'platform_accrual';
const LOSS_PENDING = 'loss_pending';
const LOSS_SETTLED = 'loss_settled';

const escrowAccount = (shipmentId) => `escrow:${shipmentId}`;

function attachRelayEscrow(exports, deps) {
  const {
    functions, db, admin, callerPhone, canonicalUid, settlementLedger, notifyUserInApp, requireCallerRoles,
    now: nowFn,
    /** Ixtiyoriy (3-bosqich): `attachWholesaleOrders` natijasi — `onShipmentDelivered(shipmentId)`. */
    wholesaleOrders = null,
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
    // Ulgurji buyurtmasi jo'natmasi (egasi = sotuvchi): yetkazish haqini xaridor kvotada
    // to'lagan, eskrouni `wholesale_orders.js` (wholesaleShipFund) o'tkazadi. Sotuvchi
    // o'z hamyonidan to'lab, buyurtma zanjirini buzmasin.
    if (ship0.source === 'wholesale') {
      throw err('permission-denied', 'Bu jo\'natma to\'langan', { reason: 'wholesale_managed' });
    }
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
          if (d.source === 'wholesale') throw Object.assign(new Error('wholesale_managed'), { reason: 'wholesale_managed' });
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
  /**
   * `forLoss` (D1): yo'qolgan posilkada ham eskrou AYNAN SHU yozuv (`relayRelease:{id}`) bilan
   * yopiladi, lekin boshlang'ich holat `loss_pending` va u `settled`ga O'TKAZILMAYDI (holatni
   * `settleLoss` oxirida `loss_settled` qiladi).
   */
  async function releaseEscrow(shipmentId, { forLoss = false } = {}) {
    const shipRef = db.collection(SHIPMENTS).doc(shipmentId);
    const [shipSnap, internalSnap] = await Promise.all([
      shipRef.get(), shipRef.collection('private').doc('internal').get(),
    ]);
    if (!shipSnap.exists) return { skipped: 'shipment_missing' };
    const ship = shipSnap.data() || {};
    const internal = internalSnap.exists ? (internalSnap.data() || {}) : {};
    const fromStatus = forLoss ? LOSS_PENDING : 'escrow_funded';
    if (!forLoss && ship.paymentStatus === 'settled') return { skipped: 'already_settled' };
    if (!forLoss && ship.paymentStatus === 'escrow_frozen') return { skipped: 'frozen' };
    if (ship.paymentStatus !== fromStatus) return { skipped: `payment_${ship.paymentStatus}` };
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
        if (d.paymentStatus !== fromStatus) throw Object.assign(new Error('not_funded'), { reason: 'not_funded' });
        return d;
      },
      onCommit: (tx) => {
        tx.update(shipRef, forLoss
          ? { releaseEntryId: `relayRelease:${shipmentId}`, updatedAt: when }
          : { paymentStatus: 'settled', settledAt: when, releaseEntryId: `relayRelease:${shipmentId}`, updatedAt: when });
      },
    });
    return { released: amount, platformShare, providerPool, idempotent: res.idempotent };
  }

  /**
   * Mijoz hamyoni (`users` hujjat ID'si, 9 yoki 12 xonali bo'lishi mumkin) — eskrou qaysi
   * hisobdan to'ldirilgan bo'lsa, o'sha (journal'dan). Qaytarish (bekor) ham, yo'qolish
   * puli ham AYNAN shu hamyonga tushadi.
   */
  async function customerWalletId(ship) {
    let usersDocId = canonicalUid(ship.ownerId);
    if (ship.escrowEntryId) {
      const j = await db.collection(settlementLedger.COL_JOURNAL).doc(ship.escrowEntryId).get();
      const drLeg = j.exists ? ((j.data() || {}).legs || []).find((l) => l.dr > 0) : null;
      if (drLeg && drLeg.account.startsWith('passenger_credit:')) usersDocId = drLeg.account.slice('passenger_credit:'.length);
    }
    return usersDocId;
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
    // Ulgurji buyurtmasi jo'natmasi: eskrou xaridorning `escrow:wholesale:{order}` idan
    // to'ldirilgan (egasi = sotuvchi EMAS to'lagan) — qaytarish O'SHA eskrouga (keyin
    // buyurtma bekor oqimi xaridorga qaytaradi, 5-bosqich). Sotuvchi hamyoniga tushmaydi.
    const wholesaleOrderId = ship.source === 'wholesale' && typeof ship.wholesaleOrderId === 'string'
      ? ship.wholesaleOrderId : '';
    const creditAccount = wholesaleOrderId
      ? `escrow:wholesale:${wholesaleOrderId}`
      : settlementLedger.passengerCreditAccount(await customerWalletId(ship));
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
        { account: creditAccount, cr: amount },
      ],
    }, {
      mirrorBonus: !wholesaleOrderId,
      walletLedgerType: wholesaleOrderId ? null : 'logistics_refund',
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

  // ── 5. YO'QOLGAN POSILKA (D1, ega qarori 2026-10-16) ─────────────────
  const fmt = (n) => String(Number(n) || 0).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  // Log: telefon raqamlari YO'Q (24-band) — faqat jo'natma/LEG/hisob identifikatorlari.
  const lossFail = (action, shipmentId, errorCode, extra) => console.error(JSON.stringify({
    action, shipmentId, result: 'failed', errorCode, ...(extra || {}),
  }));
  const notReason = (reason, extra) => Object.assign(new Error(reason), { reason, ...(extra || {}) });

  /** Hamyon `users` hujjati: 12 xonali, bo'lmasa 9 xonali (fund() bilan bir xil tartib). */
  async function usersDocIdOf(uid) {
    const canon = canonicalUid(uid);
    for (const id of [canon, canon.slice(3)]) {
      if (id && (await db.collection('users').doc(id).get()).exists) return id;
    }
    return canon;
  }

  async function walletBalance(usersDocId) {
    const s = await db.collection(settlementLedger.COL_ACCOUNTS)
      .doc(settlementLedger.passengerCreditAccount(usersDocId)).get();
    return s.exists ? Number(s.data().balance || 0) : 0;
  }

  /** `loss_pending`dan boshqa holatda hech qanday pul yozuvi bo'lmasin (tranzaksiya ichida). */
  const lossPrecheck = (shipRef, incRef) => async (tx) => {
    const [s, i] = await Promise.all([tx.get(shipRef), tx.get(incRef)]);
    if (!s.exists || (s.data() || {}).paymentStatus !== LOSS_PENDING || !i.exists) throw notReason('not_pending');
    return { ship: s.data(), inc: i.data() };
  };

  /**
   * Yakuniy yozuv (WRITE fazasi, o'qishsiz): holat `loss_settled`, incident, qarz (server kaliti
   * `debt` — `increment`, o'qish kerak emas). Refund yozuvi bilan AYNI tranzaksiyada (take > 0),
   * yoki alohida tranzaksiyada (take = 0 / journal allaqachon bor).
   */
  function writeLossFinalize(tx, o) {
    const outstanding = o.goods - o.taken;
    tx.update(o.shipRef, {
      paymentStatus: LOSS_SETTLED, lossSettledAt: o.when,
      lossRefundEntryId: o.taken > 0 ? o.refundKey : null, updatedAt: o.when,
    });
    tx.update(o.incRef, {
      status: outstanding > 0 ? 'settled' : 'repaid',
      refundedNow: o.taken, outstanding, unearnedToAva: o.unearned,
      refundEntryId: o.taken > 0 ? o.refundKey : null, settledAt: o.when, updatedAt: o.when,
    });
    tx.set(o.incRef.collection('events').doc('settled'), {
      type: 'settled', refunded: o.taken, outstanding, unearnedToAva: o.unearned, at: o.when,
    });
    if (outstanding > 0) {
      tx.set(db.collection(CAPS).doc(o.accountId), {
        debt: { logistics: admin.firestore.FieldValue.increment(outstanding) }, updatedAt: o.when,
      }, { merge: true });
    }
  }

  async function finalizeLossPlain(o) {
    return db.runTransaction(async (tx) => {
      const s = await tx.get(o.shipRef);
      if (!s.exists || (s.data() || {}).paymentStatus !== LOSS_PENDING) return { flipped: false };
      writeLossFinalize(tx, o);
      return { flipped: true };
    });
  }

  async function notifyLoss(uid, key, params, category) {
    if (!notifyUserInApp) return;
    try {
      const m = i18n.render(key, await i18n.langOfPhone(db, uid), params);
      await notifyUserInApp({
        userId: uid, title: m.title, body: m.body, category, source: 'logistics', dataType: 'logistics_lost',
      });
    } catch (e) {
      console.error(JSON.stringify({
        action: 'relayLossNotify', result: 'failed', errorCode: 'RELAY_LOSS_NOTIFY_FAILED',
        message: String((e && e.message) || e).slice(0, 200),
      }));
    }
  }

  /**
   * `loss_pending` -> pulni hisoblash -> `loss_settled`. Har qadam idempotent (journal kaliti +
   * holat tekshiruvi); trigger va reconcile bir vaqtda ishlasa ham pul ikkilanmaydi.
   */
  async function settleLoss(shipmentId) {
    const started = Date.now();
    const shipRef = db.collection(SHIPMENTS).doc(shipmentId);
    const incRef = db.collection(INCIDENTS).doc(shipmentId);
    const [shipSnap, internalSnap, incSnap] = await Promise.all([
      shipRef.get(), shipRef.collection('private').doc('internal').get(), incRef.get(),
    ]);
    if (!shipSnap.exists) return { skipped: 'shipment_missing' };
    const ship = shipSnap.data() || {};
    if (ship.paymentStatus === LOSS_SETTLED) return { skipped: 'already_settled' };
    if (ship.paymentStatus !== LOSS_PENDING) return { skipped: `payment_${ship.paymentStatus}` };
    if (!incSnap.exists) {
      lossFail('relayLossSettle', shipmentId, 'LOSS_INCIDENT_MISSING');
      return { skipped: 'incident_missing' };
    }
    const inc = incSnap.data() || {};
    const goods = Number(inc.goodsValue);
    const legId = String(inc.legId || '');
    const courier = inc.courier || {};
    const accountId = String(courier.accountId || '');
    if (!Number.isSafeInteger(goods) || goods <= 0 || !accountId) {
      lossFail('relayLossSettle', shipmentId, 'LOSS_INCIDENT_INVALID', { legId });
      return { skipped: 'incident_invalid' };
    }
    const providerPool = Number((internalSnap.exists ? internalSnap.data() : {}).providerPool) || 0;

    try {
      // a) Oldingi (tugagan) LEG'lar ijrochilariga haq SAQLANADI: custody triggeri yiqilgan bo'lsa
      //    ham shu yerda yoziladi (kalit `relayEarned:{id}:{leg}` — takror ikkilamaydi).
      const evs = await db.collection(CUSTODY).where('shipmentId', '==', shipmentId).get();
      const earnedByLeg = new Map();
      for (const ev of evs.docs) {
        const e = ev.data() || {};
        if (!e.completesLegId) continue;
        await postEarned({ ...e, shipmentId });
        earnedByLeg.set(String(e.completesLegId), Number(e.completedLegPayout) || 0);
      }
      const earnedSum = [...earnedByLeg.values()].reduce((s, v) => s + v, 0);
      const unearned = providerPool - earnedSum;
      if (unearned < 0) {
        lossFail('relayLossSettle', shipmentId, 'LOSS_UNEARNED_NEGATIVE', { legId, providerPool, earnedSum });
        return { skipped: 'unearned_negative' };
      }

      // b) Eskrou odatdagi `relayRelease:{id}` bilan yopiladi (holat loss_pending qoladi).
      const rel = await releaseEscrow(shipmentId, { forLoss: true });
      if (rel.skipped) {
        lossFail('relayLossSettle', shipmentId, 'LOSS_RELEASE_SKIPPED', { legId, skipped: rel.skipped });
        return { skipped: rel.skipped };
      }

      // c) Tugallanmagan LEG'lar ulushi (U) AVA daromadiga: platform_accrual 0 ga tushadi.
      if (unearned > 0) {
        await settlementLedger.postEntry(db, {
          idempotencyKey: `relayLostUnearned:${shipmentId}`,
          kind: 'logistics_lost_unearned',
          refType: 'shipment',
          refId: shipmentId,
          postedBy: 'system',
          postedRole: 'system',
          legs: [
            { account: ACCRUAL_ACCOUNT, dr: unearned },
            { account: PLATFORM_FEE_ACCOUNT, cr: unearned },
          ],
        }, {
          mirrorBonus: false,
          meta: { shipmentId, legId, unearned, earnedSum },
          precheck: lossPrecheck(shipRef, incRef),
        });
      }

      // d) G: kuryer hamyonidan mijozga (hamyon yetganicha), qolgani — qarz.
      const courierWalletId = await usersDocIdOf(courier.uid);
      const customerWallet = await customerWalletId(ship);
      const pcCourier = settlementLedger.passengerCreditAccount(courierWalletId);
      const pcCustomer = settlementLedger.passengerCreditAccount(customerWallet);
      if (pcCourier === pcCustomer) {
        lossFail('relayLossSettle', shipmentId, 'LOSS_SAME_ACCOUNT', { legId });
        return { skipped: 'same_account' };
      }
      const refundKey = `relayLostRefund:${shipmentId}`;
      const when = now();
      const fin = {
        shipRef, incRef, accountId, goods, unearned, when, refundKey, taken: 0,
      };
      let taken = 0;
      let flipped = false;
      const existing = await db.collection(settlementLedger.COL_JOURNAL).doc(refundKey).get();
      if (existing.exists) {
        // Yozuv bor, lekin holat hali yopilmagan (atomiklik buzilsa ham tiklanadi): journal summasi bilan yopiladi.
        taken = Number((existing.data() || {}).amount) || 0;
        flipped = (await finalizeLossPlain({ ...fin, taken })).flipped;
      } else {
        let done = false;
        for (let attempt = 0; attempt < 3 && !done; attempt += 1) {
          const take = Math.min(goods, Math.max(0, await walletBalance(courierWalletId)));
          if (take === 0) break;
          try {
            const res = await settlementLedger.postEntry(db, {
              idempotencyKey: refundKey,
              kind: 'logistics_lost_refund',
              refType: 'shipment',
              refId: shipmentId,
              postedBy: 'system',
              postedRole: 'system',
              legs: [
                { account: pcCourier, dr: take },
                { account: pcCustomer, cr: take },
              ],
            }, {
              mirrorBonus: true,
              walletLedgerType: 'logistics_lost_refund',
              meta: { shipmentId, legId, courierAccountId: accountId, goodsValue: goods },
              precheck: lossPrecheck(shipRef, incRef),
              // Balans tashqarida o'qilgan: orada kamaygan bo'lsa kuryer hamyoni manfiyga TUSHMAYDI
              // (taxi `reclaimWithDebt` bilan bir xil) — qayta o'qib kichikroq summa olinadi.
              assert: ({ accounts }) => {
                const st = accounts.get(pcCourier);
                if (st && st.next < 0) throw notReason('insufficient');
              },
              onCommit: (tx) => writeLossFinalize(tx, { ...fin, taken: take }),
            });
            if (res.idempotent) {
              const j = await db.collection(settlementLedger.COL_JOURNAL).doc(refundKey).get();
              taken = Number((j.data() || {}).amount) || 0;
              flipped = (await finalizeLossPlain({ ...fin, taken })).flipped;
            } else {
              taken = take;
              flipped = true;
            }
            done = true;
          } catch (e) {
            if (!(e && e.reason === 'insufficient')) throw e;
          }
        }
        if (!done) {
          taken = 0;
          flipped = (await finalizeLossPlain({ ...fin, taken: 0 })).flipped;
        }
      }

      const outstanding = goods - taken;
      console.log(JSON.stringify({
        action: 'relayLossSettle', result: flipped ? 'ok' : 'already', shipmentId, legId, accountId,
        goodsValue: goods, taken, outstanding, unearned, durationMs: Date.now() - started,
      }));
      if (flipped) {
        const tracking = inc.trackingNumber || ship.trackingNumber || '';
        const owner = canonicalUid((inc.customer || {}).uid || ship.ownerId);
        if (owner) {
          const key = taken >= goods ? 'lost_customer_full' : (taken > 0 ? 'lost_customer_partial' : 'lost_customer_none');
          await notifyLoss(owner, key, { tracking, amount: fmt(taken > 0 ? taken : goods), left: fmt(outstanding) }, 'info');
        }
        await notifyLoss(canonicalUid(courier.uid), 'lost_courier', { tracking, taken: fmt(taken), left: fmt(outstanding) }, 'warning');
      }
      return { settled: true, flipped, taken, outstanding, unearned, goodsValue: goods };
    } catch (e) {
      if (e && e.reason === 'not_pending') return { skipped: 'not_pending' }; // boshqa ishga tushish allaqachon yopdi
      if (e && e.reason === 'not_funded') return { skipped: 'not_pending' };
      throw e;
    }
  }

  // ── 6. ADMIN: kuryer to'lovini yozish (nakd -> mijoz hamyoni) ────────
  /**
   * `adminRecordLostParcelPayment({ shipmentId, amount, opId, note? })` — faqat admin/superadmin.
   * Kuryer qarzni O'ZI to'laydi (AVA undirmaydi); admin olingan summani yozadi. Har to'lov:
   *   Dr admin_cash / Cr admin_clearing  +  Dr admin_clearing / Cr passenger_credit:{mijoz}
   * (`cashExchange` naqshi; bitta ATOMAR yozuvda — yarim holat qolmasin), qarz (`debt.logistics`) va
   * incident (`outstanding`) AYNI tranzaksiyada kamayadi. Idempotent (opId), qarzdan oshmaydi.
   */
  async function recordLostPayment(data, context) {
    const adminUid = await requireCallerRoles(context, ['admin', 'superadmin'], 'Faqat admin yoki superadmin');
    const d = data || {};
    const shipmentId = String(d.shipmentId || '').trim();
    const amount = d.amount;
    const opId = String(d.opId || '').trim();
    const note = String(d.note || '').trim().slice(0, 300);
    if (!shipmentId) throw err('invalid-argument', 'shipmentId majburiy');
    if (typeof amount !== 'number' || !Number.isSafeInteger(amount) || amount <= 0) {
      throw err('invalid-argument', 'amount musbat butun so\'m bo\'lishi kerak', { reason: 'bad_amount' });
    }
    if (!/^[A-Za-z0-9_-]{6,64}$/.test(opId)) {
      throw err('invalid-argument', 'opId (6-64 belgi: harf, raqam, _ -)', { reason: 'bad_op_id' });
    }
    const key = `relayLostPayment:${shipmentId}:${opId}`;
    const shipRef = db.collection(SHIPMENTS).doc(shipmentId);
    const incRef = db.collection(INCIDENTS).doc(shipmentId);

    // Idempotent qayta chaqiruv HOLAT tekshiruvidan OLDIN (to'liq to'langandan keyin ham shu opId rad etilmasin).
    const prior = await db.collection(settlementLedger.COL_JOURNAL).doc(key).get();
    if (prior.exists) {
      // Jurnal mount = Σdr (4 oyoqli yozuvda 2×); asl summa meta.amountda.
      if (Number(((prior.data() || {}).meta || {}).amount) !== amount) {
        throw err('failed-precondition', 'Bu opId boshqa summa bilan ishlatilgan', { reason: 'op_id_reused' });
      }
      const i0 = (await incRef.get()).data() || {};
      return { ok: true, idempotent: true, shipmentId, amount, outstanding: i0.outstanding, paidTotal: i0.paidTotal };
    }

    const [shipSnap, incSnap] = await Promise.all([shipRef.get(), incRef.get()]);
    if (!shipSnap.exists || !incSnap.exists) throw err('not-found', 'Yo\'qolish hodisasi topilmadi', { reason: 'incident_missing' });
    const inc0 = incSnap.data() || {};
    if (inc0.status === 'declared') {
      throw err('failed-precondition', 'Yo\'qolish puli hali hisoblanmagan', { reason: 'loss_not_settled' });
    }
    const out0 = Number(inc0.outstanding) || 0;
    if (out0 <= 0) throw err('failed-precondition', 'To\'lanadigan qarz qolmagan', { reason: 'nothing_outstanding' });
    if (amount > out0) {
      throw err('failed-precondition', 'Summa qarzdan oshib ketdi', { reason: 'exceeds_outstanding', outstanding: out0 });
    }
    const accountId = String((inc0.courier || {}).accountId || '');
    if (!accountId) throw err('failed-precondition', 'Kuryer hisobi yozilmagan', { reason: 'incident_invalid' });
    const customerWallet = await customerWalletId(shipSnap.data() || {});
    const pcCustomer = settlementLedger.passengerCreditAccount(customerWallet);
    const capRef = db.collection(CAPS).doc(accountId);
    const when = now();

    try {
      const res = await settlementLedger.postEntry(db, {
        idempotencyKey: key,
        kind: 'logistics_lost_payment',
        refType: 'shipment',
        refId: shipmentId,
        postedBy: adminUid,
        postedRole: 'admin',
        legs: [
          { account: 'admin_cash', dr: amount },
          { account: 'admin_clearing', cr: amount },
          { account: 'admin_clearing', dr: amount },
          { account: pcCustomer, cr: amount },
        ],
      }, {
        mirrorBonus: true,
        walletLedgerType: 'logistics_lost_payment',
        meta: { shipmentId, opId, amount, courierAccountId: accountId },
        // READ fazasi — holat tranzaksiya ichida QAYTA tekshiriladi (parallel to'lovlar).
        precheck: async (tx) => {
          const [i, c] = await Promise.all([tx.get(incRef), tx.get(capRef)]);
          const inc = i.exists ? (i.data() || {}) : {};
          const outstanding = Number(inc.outstanding) || 0;
          if (inc.status === 'declared' || !i.exists) throw notReason('loss_not_settled');
          if (outstanding <= 0) throw notReason('nothing_outstanding');
          if (amount > outstanding) throw notReason('exceeds_outstanding', { outstanding });
          const debt = Number((((c.data() || {}).debt) || {}).logistics) || 0;
          if (debt < amount) throw notReason('debt_mismatch', { debt });
          return { outstanding, paidTotal: Number(inc.paidTotal) || 0, debt };
        },
        onCommit: (tx, { pre }) => {
          const left = pre.outstanding - amount;
          tx.update(incRef, {
            outstanding: left, paidTotal: pre.paidTotal + amount, status: left === 0 ? 'repaid' : 'settled',
            lastPaymentAt: when, updatedAt: when,
          });
          tx.set(incRef.collection('events').doc(`payment_${opId}`), {
            type: 'payment', amount, opId, by: adminUid, note, entryId: key, outstandingAfter: left, at: when,
          });
          tx.set(capRef, { debt: { logistics: pre.debt - amount }, updatedAt: when }, { merge: true });
          tx.set(db.collection(LOGISTICS_AUDIT).doc(`lost_payment_${shipmentId}_${opId}`), {
            kind: 'lost_payment', shipmentId, amount, opId, by: adminUid, note, at: when,
          });
        },
      });
      if (res.idempotent) {
        const i1 = (await incRef.get()).data() || {};
        return { ok: true, idempotent: true, shipmentId, amount, outstanding: i1.outstanding, paidTotal: i1.paidTotal };
      }
      const left = res.pre.outstanding - amount;
      console.log(JSON.stringify({
        action: 'adminRecordLostParcelPayment', result: 'ok', shipmentId, accountId, amount, outstanding: left,
      }));
      const tracking = inc0.trackingNumber || (shipSnap.data() || {}).trackingNumber || '';
      const owner = canonicalUid((inc0.customer || {}).uid || (shipSnap.data() || {}).ownerId);
      if (owner) {
        if (left === 0) {
          await notifyLoss(owner, 'lost_customer_done', { tracking, total: fmt(inc0.goodsValue) }, 'info');
        } else {
          await notifyLoss(owner, 'lost_customer_payment', { tracking, amount: fmt(amount), left: fmt(left) }, 'info');
        }
      }
      return {
        ok: true, idempotent: false, shipmentId, amount, outstanding: left, paidTotal: res.pre.paidTotal + amount,
      };
    } catch (e) {
      if (e && e.reason) {
        console.error(JSON.stringify({
          action: 'adminRecordLostParcelPayment', result: 'denied', shipmentId, errorCode: e.reason,
        }));
        throw err('failed-precondition', 'To\'lovni yozib bo\'lmadi', { reason: e.reason, outstanding: e.outstanding, debt: e.debt });
      }
      throw e;
    }
  }

  // ── 7. ADMIN: yo'qolish hodisalari ro'yxati (faqat o'qish) ───────────
  const LIST_LIMIT_DEFAULT = 50;
  const LIST_LIMIT_MAX = 100;
  /** Telefon -> faqat oxirgi 4 raqam (40-band: admin ro'yxatida to'liq raqam kerak emas). */
  const maskPhone = (v) => {
    const d = String(v || '').replace(/\D/g, '');
    return d.length >= 4 ? `***${d.slice(-4)}` : '';
  };
  const msOf = (v) => {
    if (v && typeof v.toMillis === 'function') return v.toMillis();
    if (v instanceof Date) return v.getTime();
    return null;
  };
  const numOrNull = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);

  /**
   * `adminListLossIncidents({ limit? })` — faqat admin/superadmin (`adminRecordLostParcelPayment`
   * bilan bir xil tekshiruv). Eng yangi `logistics_incidents` (declaredAt kamayish, bitta maydon
   * bo'yicha - qo'shimcha indeks YO'Q). limit: standart 50, eng ko'pi 100. Mijoz telefoni/ismi/
   * manzili va izoh (note) QAYTARILMAYDI; kuryer telefoni oxirgi 4 raqamgacha maskalanadi.
   */
  async function listLossIncidents(data, context) {
    const adminUid = await requireCallerRoles(context, ['admin', 'superadmin'], 'Faqat admin yoki superadmin');
    const raw = (data || {}).limit;
    let limit = LIST_LIMIT_DEFAULT;
    if (raw !== undefined) {
      if (typeof raw !== 'number' || !Number.isInteger(raw) || raw < 1) {
        throw err('invalid-argument', 'limit musbat butun son bo\'lishi kerak', { reason: 'bad_limit' });
      }
      limit = Math.min(raw, LIST_LIMIT_MAX);
    }
    const snap = await db.collection(INCIDENTS).orderBy('declaredAt', 'desc').limit(limit).get();
    const items = snap.docs.map((doc) => {
      const i = doc.data() || {};
      return {
        id: doc.id,
        shipmentId: String(i.shipmentId || doc.id),
        trackingNumber: String(i.trackingNumber || ''),
        status: String(i.status || ''),
        goodsValue: numOrNull(i.goodsValue),
        refundedNow: numOrNull(i.refundedNow),
        outstanding: numOrNull(i.outstanding),
        paidTotal: numOrNull(i.paidTotal),
        declaredAtMs: msOf(i.declaredAt),
        courierPhoneMasked: maskPhone((i.courier || {}).uid),
        courierAccountId: String((i.courier || {}).accountId || ''),
        reason: String(i.reason || '').slice(0, 300),
        legId: String(i.legId || ''),
      };
    });
    console.log(JSON.stringify({
      action: 'adminListLossIncidents', result: 'ok', userId: adminUid, limit, count: items.length,
    }));
    return { ok: true, items };
  }

  // ── Triggerlar ───────────────────────────────────────────────────────
  /** custody_events onCreate: LEG tugadi → EARNED; yetkazildi → RELEASE. */
  async function onCustodyEvent(event) {
    const out = {};
    try {
      out.earned = await postEarned(event);
    } catch (e) {
      console.error(JSON.stringify({
        action: 'relayEarned', shipmentId: event.shipmentId, legId: event.completesLegId,
        result: 'failed', errorCode: 'RELAY_EARNED_FAILED', message: String(e.message).slice(0, 200),
      }));
    }
    if (event.deliversShipment === true) {
      try {
        out.release = await releaseEscrow(String(event.shipmentId));
      } catch (e) {
        if (!(e && e.reason === 'not_funded')) console.error(`relay RELEASE xato (${event.shipmentId}): ${e.message}`);
      }
      // Ulgurji buyurtmasi (3-bosqich): tovar puli sotuvchiga — alohida eskrou
      // (`escrow:wholesale:{order}`), relay RELEASE'dan mustaqil; oddiy jo'natmada no-op.
      // Yiqilsa — `wholesaleOrdersReconcile` qayta urinadi (idempotent).
      if (wholesaleOrders && typeof wholesaleOrders.onShipmentDelivered === 'function') {
        try {
          out.wholesale = await wholesaleOrders.onShipmentDelivered(String(event.shipmentId));
        } catch (e) {
          console.error(JSON.stringify({
            action: 'wholesaleRelease', shipmentId: event.shipmentId, result: 'failed',
            errorCode: 'WHOLESALE_RELEASE_FAILED', message: String((e && e.message) || e).slice(0, 200),
          }));
        }
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

  /** shipments onUpdate: `refund_pending` → REFUND; `loss_pending` → yo'qolish puli (D1). */
  async function onShipmentUpdate(before, after, shipmentId) {
    const ap = (after || {}).paymentStatus;
    const bp = (before || {}).paymentStatus;
    if (ap === 'refund_pending' && bp !== 'refund_pending') {
      try { return await refundEscrow(shipmentId); } catch (e) {
        if (!(e && e.reason === 'not_pending')) console.error(`relay REFUND xato (${shipmentId}): ${e.message}`);
      }
    }
    if (ap === LOSS_PENDING && bp !== LOSS_PENDING) {
      try { return await settleLoss(shipmentId); } catch (e) {
        // Reconcile (har 10 daqiqa) qayta urinadi; har qadam idempotent.
        lossFail('relayLossSettle', shipmentId, 'RELAY_LOSS_SETTLE_FAILED', { message: String((e && e.message) || e).slice(0, 200) });
        return { skipped: 'failed' };
      }
    }
    // Takror trigger (retry) yoki boshqa o'tish — pul harakati yo'q; sabab
    // holat bo'yicha, logda ajratish oson bo'lsin.
    return { skipped: ap === 'refund_pending' ? 'no_change' : `payment_${ap || 'none'}` };
  }

  // ── RECONCILE — trigger yiqilsa ham pul qotib qolmasin (audit R2/R3) ──
  // Triggerlar xatoni yutadi va qayta urinmaydi; poyga (bekor ↔ to'lov)
  // `cancelled + escrow_funded` qoldirishi mumkin. Har yozuv idempotent
  // (`relayRefund/relayRelease/relayEarned` kalitlari + precheck), shuning
  // uchun trigger bilan bir vaqtda ishlash xavfsiz. `escrow_frozen` (nizo) ga
  // tegilmaydi.
  const logFail = (action, shipmentId, e) => console.error(JSON.stringify({
    action, shipmentId, result: 'failed', errorCode: 'RELAY_ESCROW_RECONCILE_FAILED',
    message: String((e && e.message) || e).slice(0, 200),
  }));

  async function reconcile({ limit = 50 } = {}) {
    const out = {
      refunded: 0, released: 0, flagged: 0, failed: 0, lossSettled: 0,
    };
    // A) refund_pending qolib ketgan.
    const pend = await db.collection(SHIPMENTS).where('paymentStatus', '==', 'refund_pending').limit(limit).get();
    for (const d of pend.docs) {
      try {
        const r = await refundEscrow(d.id);
        if (r && r.refunded) out.refunded += 1;
      } catch (e) {
        if (!(e && e.reason === 'not_pending')) { out.failed += 1; logFail('relayReconcileRefund', d.id, e); }
      }
    }
    // B) bekor qilingan, lekin eskrou yechilmagan (cancel/fund poygasi) → refund_pending → refund.
    const canc = await db.collection(SHIPMENTS)
      .where('paymentStatus', '==', 'escrow_funded').where('status', '==', 'cancelled').limit(limit).get();
    for (const d of canc.docs) {
      try {
        const flagged = await db.runTransaction(async (tx) => {
          const s = await tx.get(d.ref);
          const cur = s.exists ? (s.data() || {}) : {};
          if (cur.status !== 'cancelled' || cur.paymentStatus !== 'escrow_funded') return false;
          tx.update(d.ref, { paymentStatus: 'refund_pending', updatedAt: now() });
          return true;
        });
        if (flagged) {
          out.flagged += 1;
          const r = await refundEscrow(d.id);
          if (r && r.refunded) out.refunded += 1;
        }
      } catch (e) {
        if (!(e && e.reason === 'not_pending')) { out.failed += 1; logFail('relayReconcileCancelled', d.id, e); }
      }
    }
    // C) yetkazilgan, lekin EARNED/RELEASE yozilmagan.
    const del = await db.collection(SHIPMENTS)
      .where('paymentStatus', '==', 'escrow_funded').where('status', '==', 'delivered').limit(limit).get();
    for (const d of del.docs) {
      try {
        const evs = await db.collection(CUSTODY).where('shipmentId', '==', d.id).get();
        for (const ev of evs.docs) {
          const e = ev.data() || {};
          if (e.completesLegId) await postEarned({ ...e, shipmentId: d.id });
        }
        const r = await releaseEscrow(d.id);
        if (r && r.released) out.released += 1;
      } catch (e) {
        if (!(e && e.reason === 'not_funded')) { out.failed += 1; logFail('relayReconcileDelivered', d.id, e); }
      }
    }
    // D) yo'qolgan posilka: `loss_pending` qotib qolgan (trigger yiqilgan / oraliq qadam yiqilgan).
    const lost = await db.collection(SHIPMENTS).where('paymentStatus', '==', LOSS_PENDING).limit(limit).get();
    for (const d of lost.docs) {
      try {
        const r = await settleLoss(d.id);
        if (r && r.settled && r.flipped) out.lossSettled += 1;
      } catch (e) {
        out.failed += 1;
        logFail('relayReconcileLoss', d.id, e);
      }
    }
    console.log(JSON.stringify({ action: 'relayEscrowReconcile', ...out }));
    return out;
  }

  exports.relayEscrowReconcile = functions.pubsub
    .schedule('every 10 minutes')
    .onRun(async () => { await reconcile(); return null; });

  exports.fundShipmentEscrow = functions.https.onCall(fund);
  /** ADMIN — kuryer to'lagan qarzni yozish (yo'qolgan posilka, D1). Faqat admin/superadmin. */
  exports.adminRecordLostParcelPayment = functions.https.onCall(recordLostPayment);
  /** ADMIN — yo'qolish hodisalari ro'yxati (D1, faqat o'qish). Faqat admin/superadmin. */
  exports.adminListLossIncidents = functions.https.onCall(listLossIncidents);
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
    fund, postEarned, releaseEscrow, refundEscrow, onCustodyEvent, onShipmentUpdate, resolveCaller, reconcile,
    settleLoss, recordLostPayment, listLossIncidents,
  };
}

module.exports = {
  SHIPMENTS, CUSTODY, INCIDENTS, PLATFORM_FEE_ACCOUNT, ACCRUAL_ACCOUNT, escrowAccount, attachRelayEscrow,
};
