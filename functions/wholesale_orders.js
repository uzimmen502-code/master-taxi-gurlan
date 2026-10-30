'use strict';

/**
 * ULGURJI BUYURTMA ZANJIRI — 2-bosqich, default codebase (us-central1).
 * Hujjat: docs/ulgurji_buyurtma_zanjiri_uz.md (ega qarorlari Q-1…Q-8, 2026-10-31).
 *
 * NEGA SHU CODEBASE: pul faqat `settlement_ledger.js` orqali (43-band: ikkinchi
 * ledger yo'q) — u shu yerda. Kvota, rad/bekor va holatlar jadvali
 * `functions_demand` da (`api/wholesale_orders.js`, `core/wholesale_orders.js`).
 * Ikkisi Firestore hujjatlari orqali bog'lanadi (relay `shipments.paymentStatus` naqshi):
 *
 *   demand  → wholesale_quotes/{id} (muhrlangan narx), wholesale_orders.status
 *             (placed → cancelled) + refundStatus: 'pending'
 *   default → wholesale_orders/{id} yaratadi (placed + pul ushlandi),
 *             refundStatus: 'done' (pul qaytdi + qoldiq tiklandi)
 *
 * ── HISOB REJASI (mavjud nomlar, relay_escrow.js bilan bir xil) ─────────
 *   passenger_credit:{uid}          xaridor AVA hamyoni (mavjud)
 *   escrow:wholesale:{orderId}      xaridorning DEPONENTLANGAN puli (liability)
 *
 *   HOLD    Dr passenger_credit:{xaridor}     Cr escrow:wholesale:{id}   total   (placeWholesaleOrder)
 *   REFUND  Dr escrow:wholesale:{id}          Cr passenger_credit:{xaridor} total (cancelled)
 *   (3-bosqich: SHIP_FUND escrow:wholesale → escrow:{shipmentId}; RELEASE — sotuvchiga
 *    goodsTotal − avaFee, AVA ulushi earnings:ava_wholesale_fee. Bu yerda YO'Q.)
 *
 * Jurnal kalitlari (`journal_entries/bonus:{kalit}`, `prepareBonusInTx` naqshi):
 *   wholesaleHold:{orderId}, wholesaleRefund:{orderId}.
 *
 * ── INVARIANTLAR ───────────────────────────────────────────────────────
 *   - Bitta tranzaksiya: kvota (used) + qoldiq −N + ledger HOLD + hamyon ko'zgusi
 *     + buyurtma + history + idempotentlik hujjati (22-band). O'qishlar — yozuvdan oldin.
 *   - `clientRequestId` — `wallet_idempotency/wholesale_place_{xaridor}_{id}`:
 *     takror chaqiruv o'sha buyurtmani qaytaradi, ikkinchi yechim yo'q (21-band).
 *   - REFUND: holat (`refundStatus`) tranzaksiya ichida tekshiriladi — trigger,
 *     takror hodisa va reconcile bir vaqtda ishlasa ham pul ham, qoldiq ham bir marta.
 *   - Butun so'm; total === goodsTotal + deliveryFee (8-band).
 *   - Log — telefon/manzil YO'Q (24, 40-band).
 */

const ORDERS = 'wholesale_orders';
const QUOTES = 'wholesale_quotes';
const STOCK = 'wholesale_stock';
const PRODUCTS = 'wholesale_products';
const HISTORY = 'history';
const PRIVATE = 'private';
const IDEMPOTENCY = 'wallet_idempotency';
const GATE_DOC = ['module_config', 'wholesale_orders_all'];

/**
 * Holat nomlari — manba `functions_demand/core/wholesale_orders.js` (yagona jadval).
 * Bu yerda faqat o'qiladi/boshlang'ich holat yoziladi; paritet testi:
 * functions/test/wholesale_orders.test.js.
 */
// Sotuvchi qabul/rad QILMAYDI (ega, 2026-10-31) — 'rejected' holati yo'q.
const STATUS = Object.freeze({ PLACED: 'placed', CANCELLED: 'cancelled' });
const REFUND_STATUSES = Object.freeze([STATUS.CANCELLED]);
const REFUND_STATUS = Object.freeze({ PENDING: 'pending', DONE: 'done' });

/** Reconcile: shundan eski `pending` qaytarishlar qayta ishlanadi (topshiriq: 10 daqiqa). */
const RECONCILE_MIN_AGE_MS = 10 * 60 * 1000;
const RECONCILE_LIMIT = 100;

const escrowAccount = (orderId) => `escrow:wholesale:${orderId}`;
const holdKey = (orderId) => `wholesaleHold:${orderId}`;
const refundKey = (orderId) => `wholesaleRefund:${orderId}`;

const isInt = (n) => typeof n === 'number' && Number.isInteger(n);
const isPosInt = (n) => isInt(n) && n > 0;

function msOf(v) {
  if (v == null) return null;
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (v instanceof Date) return v.getTime();
  return null;
}

/** Muhrlangan kvota summalari izchilmi (server yozgan, lekin pul yechishdan oldin qayta tekshiriladi). */
function quoteAmountsOk(q) {
  const d = q || {};
  return isPosInt(d.qty) && isPosInt(d.unitPrice) && isPosInt(d.goodsTotal)
    && isInt(d.deliveryFee) && d.deliveryFee >= 0 && isPosInt(d.total)
    && d.goodsTotal === d.unitPrice * d.qty
    && d.total === d.goodsTotal + d.deliveryFee
    && Number.isSafeInteger(d.total)
    && isInt(d.avaFee) && d.avaFee >= 0 && isInt(d.sellerPayout)
    && d.avaFee + d.sellerPayout === d.goodsTotal
    && isInt(d.avaFeeBps) && isInt(d.feeVersion);
}

function attachWholesaleOrders(exportsObj, deps) {
  const {
    functions, db, admin, callerPhone, canonicalUid, settlementLedger, now: nowFn,
  } = deps;
  const now = () => (nowFn ? nowFn() : new Date());
  const HttpsError = functions.https.HttpsError;
  const inc = (n) => admin.firestore.FieldValue.increment(n);
  /** User-facing matn (uz) + ichki `details.reason` (25-band). */
  const fail = (status, message, reason, extra) => new HttpsError(status, message, { reason, ...(extra || {}) });

  function log(action, fields) {
    console.log(JSON.stringify({ module: 'wholesale_orders', action, ...fields }));
  }
  function logError(action, fields) {
    console.error(JSON.stringify({ module: 'wholesale_orders', action, result: 'failed', ...fields }));
  }

  /** `users/{12}` yoki eski `users/{9}` — hamyon egasi hujjati ID'si. */
  async function walletUidOf(uid12) {
    for (const id of [uid12, uid12.slice(3)]) {
      const s = await db.collection('users').doc(id).get();
      if (s.exists) return id;
    }
    return null;
  }

  /** Hamyon ko'zgusi — restoran `commitFeeInTx` / `postEntry(mirrorBonus)` bilan bir xil. */
  function mirrorWallet(t, walletUid, delta, type, orderId, when, meta) {
    const userRef = db.collection('users').doc(walletUid);
    t.set(userRef, { bonusBalance: inc(delta), balanceUpdatedAt: when }, { merge: true });
    t.set(userRef.collection('wallet_ledger').doc(), {
      type, amount: delta, module: 'wholesale', refType: 'wholesale_order', refId: orderId,
      meta: meta || {}, createdAt: when, createdBy: 'server',
    });
  }

  function replay(idem, quoteId) {
    if (String(idem.quoteId || '') !== quoteId) {
      throw fail('failed-precondition', 'Bu so\'rov boshqa buyurtma uchun ishlatilgan', 'idempotency_key_reused');
    }
    return { ok: true, orderId: String(idem.orderId), status: STATUS.PLACED, idempotent: true };
  }

  // ── BUYURTMA: kvota → pul ushlash → qoldiq −N (bitta tranzaksiya) ─────
  async function place(data, context) {
    const started = Date.now();
    if (!context || !context.auth) throw fail('unauthenticated', 'Telefon bilan kiring', 'auth_required');
    const uid = canonicalUid(callerPhone(context));
    if (!/^998\d{9}$/.test(uid)) throw fail('unauthenticated', 'Telefon bilan kiring', 'phone_token_required');
    const d = data || {};
    const quoteId = String(d.quoteId || '').trim();
    if (!/^[A-Za-z0-9_-]{1,128}$/.test(quoteId)) throw fail('invalid-argument', 'Narx so\'rovi topilmadi', 'quote_required');
    const clientRequestId = String(d.clientRequestId || '').trim();
    if (!/^[A-Za-z0-9_-]{8,80}$/.test(clientRequestId)) {
      throw fail('invalid-argument', 'So\'rov identifikatori noto\'g\'ri', 'client_request_id_invalid');
    }
    const idemRef = db.collection(IDEMPOTENCY).doc(`wholesale_place_${uid}_${clientRequestId}`);
    const quoteRef = db.collection(QUOTES).doc(quoteId);

    try {
      // 1) Tez yo'l: takror chaqiruv (tarmoq qayta urinishi) — o'sha buyurtma.
      const idem0 = await idemRef.get();
      if (idem0.exists) {
        const r = replay(idem0.data() || {}, quoteId);
        log('place', { result: 'already', orderId: r.orderId, quoteId, durationMs: Date.now() - started });
        return r;
      }
      // 2) Kill switch (42-band). Bosqich/sinovchi — kvotada tekshirilgan (15 daqiqa ichida).
      const gate = await db.collection(GATE_DOC[0]).doc(GATE_DOC[1]).get();
      if (!gate.exists || (gate.data() || {}).enabled !== true) {
        throw fail('unavailable', 'Ulgurji buyurtma hozir ishlamayapti', 'module_disabled');
      }
      const walletUid = await walletUidOf(uid);
      if (!walletUid) throw fail('failed-precondition', 'Hisob topilmadi', 'user_not_found');

      const orderRef = db.collection(ORDERS).doc();
      const orderId = orderRef.id;
      const when = now();

      const out = await db.runTransaction(async (t) => {
        // ── READ fazasi ──
        const [idemSnap, qSnap] = await Promise.all([t.get(idemRef), t.get(quoteRef)]);
        if (idemSnap.exists) return { replay: idemSnap.data() || {} };
        if (!qSnap.exists) throw fail('not-found', 'Narx so\'rovi topilmadi', 'quote_not_found');
        const q = qSnap.data() || {};
        if (canonicalUid(q.buyerId) !== uid) throw fail('permission-denied', 'Bu narx so\'rovi sizniki emas', 'quote_not_yours');
        if (q.used === true) throw fail('failed-precondition', 'Narx so\'rovi allaqachon ishlatilgan', 'quote_used');
        const exp = msOf(q.expiresAt);
        if (exp == null || exp <= when.getTime()) {
          throw fail('failed-precondition', 'Narx eskirdi. Qaytadan hisoblang', 'quote_expired');
        }
        if (!quoteAmountsOk(q) || !q.productId || !q.packId || !q.sellerId) {
          throw fail('failed-precondition', 'Narx so\'rovi yaroqsiz. Qaytadan hisoblang', 'quote_invalid');
        }
        const productRef = db.collection(PRODUCTS).doc(String(q.productId));
        const stockRef = db.collection(STOCK).doc(String(q.productId));
        const [pSnap, sSnap] = await Promise.all([t.get(productRef), t.get(stockRef)]);
        const ledger = await settlementLedger.prepareBonusInTx(t, db, walletUid, {
          fundingAccount: escrowAccount(orderId), idempotencyKey: holdKey(orderId),
        });

        // ── TEKSHIRUVLAR (kvota eskirgan bo'lishi mumkin) ──
        if (!pSnap.exists || (pSnap.data() || {}).status !== 'active') {
          throw fail('failed-precondition', 'Mahsulot hozir sotuvda emas', 'product_unavailable');
        }
        const st = sSnap.exists ? (sSnap.data() || {}) : {};
        const packs = st.packs && typeof st.packs === 'object' ? st.packs : {};
        const available = packs[q.packId];
        if (!isInt(available) || available < 0) {
          throw fail('failed-precondition', 'Sotuvchi qoldiqni kiritmagan', 'stock_unknown');
        }
        if (available < q.qty) {
          throw fail('failed-precondition', 'Omborda yetarli emas', 'insufficient_stock', { available });
        }
        if (ledger.jExists) throw fail('aborted', 'Qayta urinib ko\'ring', 'hold_conflict');
        if (ledger.pcPrev < q.total) {
          throw fail('failed-precondition', 'Hamyonda mablag\' yetarli emas', 'insufficient_balance', {
            required: q.total, balance: ledger.pcPrev,
          });
        }

        // ── WRITE fazasi ──
        const nextPacks = { ...packs, [q.packId]: available - q.qty };
        const version = (isInt(st.version) ? st.version : 0) + 1;
        t.set(stockRef, {
          productId: String(q.productId),
          sellerId: String(st.sellerId || q.sellerId),
          packs: nextPacks,
          version,
          updatedAt: when,
        });
        t.set(stockRef.collection(HISTORY).doc(`v${version}`), {
          kind: 'order_hold', from: packs, to: nextPacks, packId: q.packId, qty: q.qty,
          orderId, by: 'system', at: when, version,
        });
        t.update(quoteRef, { used: true, usedAt: when, orderId });

        settlementLedger.commitBonusInTx(t, ledger, {
          delta: -q.total,
          kind: 'wholesale_hold',
          refType: 'wholesale_order',
          refId: orderId,
          meta: {
            module: 'wholesale', productId: q.productId, packId: q.packId, qty: q.qty,
            goodsTotal: q.goodsTotal, deliveryFee: q.deliveryFee,
          },
          postedBy: uid,
          postedRole: 'client',
        });
        mirrorWallet(t, walletUid, -q.total, 'wholesale_hold', orderId, when, {
          goodsTotal: q.goodsTotal, deliveryFee: q.deliveryFee,
        });

        t.set(orderRef, {
          buyerId: uid,
          buyerWalletUid: walletUid,
          sellerId: String(q.sellerId),
          productId: String(q.productId),
          productTitle: String(q.productTitle || ''),
          packId: q.packId,
          packLabel: String(q.packLabel || ''),
          qty: q.qty,
          unitPrice: q.unitPrice,
          goodsTotal: q.goodsTotal,
          deliveryFee: q.deliveryFee,
          total: q.total,
          currency: 'UZS',
          delivery: q.delivery || null,
          origin: q.origin || null,
          destination: q.destination || null,
          quoteId,
          clientRequestId,
          status: STATUS.PLACED,
          historySeq: 1,
          payment: {
            status: 'held',
            amount: q.total,
            heldAt: when,
            escrowAccount: escrowAccount(orderId),
            holdEntryId: `bonus:${holdKey(orderId)}`,
          },
          stock: { packId: q.packId, qty: q.qty, decremented: true, restored: false },
          // 3-bosqich (relay) shu yerga `{shipmentId, ...}` yozadi.
          shipment: null,
          refundStatus: null,
          createdAt: when,
          updatedAt: when,
          statusUpdatedAt: when,
        });
        // Ichki qatlam (14-band): AVA ulushi va sotuvchi puli — klientga yopiq,
        // 3-bosqich RELEASE shu muhrdan o'qiydi.
        t.set(orderRef.collection(PRIVATE).doc('settlement'), {
          goodsTotal: q.goodsTotal,
          avaFeeBps: q.avaFeeBps,
          feeVersion: q.feeVersion,
          avaFee: q.avaFee,
          sellerPayout: q.sellerPayout,
          createdAt: when,
        });
        t.set(orderRef.collection(HISTORY).doc('1'), {
          seq: 1, from: null, to: STATUS.PLACED, actor: 'buyer', actorId: uid, reason: '',
          meta: { quoteId, total: q.total }, at: when,
        });
        t.set(idemRef, {
          kind: 'wholesale_place', orderId, quoteId, buyerId: uid, createdAt: when,
        });
        return { orderId, total: q.total, productId: q.productId, packId: q.packId, qty: q.qty };
      });

      if (out.replay) {
        const r = replay(out.replay, quoteId);
        log('place', { result: 'already', orderId: r.orderId, quoteId, durationMs: Date.now() - started });
        return r;
      }
      log('place', {
        result: 'ok', orderId: out.orderId, quoteId, productId: out.productId, packId: out.packId,
        qty: out.qty, amount: out.total, durationMs: Date.now() - started,
      });
      return { ok: true, orderId: out.orderId, status: STATUS.PLACED, total: out.total, idempotent: false };
    } catch (e) {
      log('place', {
        result: 'denied', quoteId,
        errorCode: (e && e.details && e.details.reason) || (e && e.code) || 'UNKNOWN',
        durationMs: Date.now() - started,
      });
      if (e instanceof HttpsError) throw e;
      // Kutilmagan xato (tranzaksiya to'qnashuvi va h.k.): tafsilot foydalanuvchiga berilmaydi.
      logError('place', { quoteId, errorCode: 'PLACE_UNEXPECTED', message: String((e && e.message) || e).slice(0, 200) });
      throw fail('internal', 'Buyurtma berib bo\'lmadi. Qayta urinib ko\'ring', 'internal');
    }
  }

  // ── QAYTARISH: cancelled → hamyonga to'liq + qoldiq +N ────────
  /**
   * Idempotent (holat tranzaksiya ichida): `refundStatus === 'done'` bo'lsa hech narsa
   * yozilmaydi. Jurnal yozuvi allaqachon bo'lsa (`jExists`) — pul qayta yozilmaydi.
   */
  async function refundOrder(orderId) {
    const started = Date.now();
    const orderRef = db.collection(ORDERS).doc(orderId);
    const when = now();
    const out = await db.runTransaction(async (t) => {
      const s = await t.get(orderRef);
      if (!s.exists) return { skipped: 'order_missing' };
      const o = s.data() || {};
      if (o.refundStatus === REFUND_STATUS.DONE) return { skipped: 'already_refunded' };
      if (o.refundStatus !== REFUND_STATUS.PENDING || !REFUND_STATUSES.includes(o.status)) {
        return { skipped: `state_${o.status || 'none'}_${o.refundStatus || 'none'}` };
      }
      const pay = o.payment || {};
      const amount = pay.amount;
      const walletUid = String(o.buyerWalletUid || '');
      if (pay.status !== 'held' || !isPosInt(amount) || !walletUid) {
        return { skipped: 'payment_invalid', anomaly: true };
      }
      const so = o.stock || {};
      const restore = so.decremented === true && so.restored !== true
        && isPosInt(so.qty) && typeof so.packId === 'string' && so.packId !== '';
      const stockRef = db.collection(STOCK).doc(String(o.productId || ''));
      // READ fazasi (hammasi yozuvdan oldin).
      const sSnap = restore ? await t.get(stockRef) : null;
      const ledger = await settlementLedger.prepareBonusInTx(t, db, walletUid, {
        fundingAccount: escrowAccount(orderId), idempotencyKey: refundKey(orderId),
      });
      if (!ledger.jExists && ledger.fundPrev < amount) {
        // Eskrou yetmaydi — pulni o'ylab topmaymiz (anomaliya, admin ko'radi).
        return { skipped: 'escrow_short', anomaly: true, escrow: ledger.fundPrev };
      }

      // WRITE fazasi.
      if (!ledger.jExists) {
        settlementLedger.commitBonusInTx(t, ledger, {
          delta: amount,
          kind: 'wholesale_refund',
          refType: 'wholesale_order',
          refId: orderId,
          meta: { module: 'wholesale', status: o.status },
          postedBy: 'system',
          postedRole: 'system',
        });
        mirrorWallet(t, walletUid, amount, 'wholesale_refund', orderId, when, { status: o.status });
      }
      if (restore) {
        const st = sSnap && sSnap.exists ? (sSnap.data() || {}) : {};
        const packs = st.packs && typeof st.packs === 'object' ? st.packs : {};
        const cur = isInt(packs[so.packId]) && packs[so.packId] >= 0 ? packs[so.packId] : 0;
        const nextPacks = { ...packs, [so.packId]: cur + so.qty };
        const version = (isInt(st.version) ? st.version : 0) + 1;
        t.set(stockRef, {
          productId: String(o.productId),
          sellerId: String(st.sellerId || o.sellerId || ''),
          packs: nextPacks,
          version,
          updatedAt: when,
        });
        t.set(stockRef.collection(HISTORY).doc(`v${version}`), {
          kind: 'order_refund', from: packs, to: nextPacks, packId: so.packId, qty: so.qty,
          orderId, by: 'system', at: when, version,
        });
      }
      const seq = (isInt(o.historySeq) ? o.historySeq : 0) + 1;
      t.update(orderRef, {
        refundStatus: REFUND_STATUS.DONE,
        refundedAt: when,
        'payment.status': 'refunded',
        'payment.refundedAt': when,
        'payment.refundEntryId': `bonus:${refundKey(orderId)}`,
        'stock.restored': restore || so.restored === true,
        'stock.restoredAt': restore ? when : (so.restoredAt || null),
        historySeq: seq,
        updatedAt: when,
      });
      t.set(orderRef.collection(HISTORY).doc(String(seq)), {
        seq, from: o.status, to: o.status, event: 'refund_done', actor: 'system', actorId: null,
        reason: '', meta: { amount, stockRestored: restore }, at: when,
      });
      return { refunded: amount, stockRestored: restore, ledgerExisted: ledger.jExists };
    });
    if (out.anomaly) {
      logError('refund', { orderId, errorCode: out.skipped === 'escrow_short' ? 'WHOLESALE_ESCROW_SHORT' : 'WHOLESALE_PAYMENT_INVALID' });
    } else {
      log('refund', {
        orderId, result: out.refunded ? 'ok' : 'skipped', skipped: out.skipped || null,
        amount: out.refunded || 0, stockRestored: !!out.stockRestored, durationMs: Date.now() - started,
      });
    }
    return out;
  }

  /** wholesale_orders onUpdate: cancelled + refundStatus=pending → qaytarish. */
  async function onStatusChange(before, after, orderId) {
    const a = after || {};
    if (!REFUND_STATUSES.includes(a.status) || a.refundStatus !== REFUND_STATUS.PENDING) {
      return { skipped: 'no_refund_needed' };
    }
    try {
      return await refundOrder(orderId);
    } catch (e) {
      // Reconcile (har 15 daqiqa) qayta urinadi; har qadam idempotent.
      logError('refund', { orderId, errorCode: 'WHOLESALE_REFUND_FAILED', message: String((e && e.message) || e).slice(0, 200) });
      return { skipped: 'failed' };
    }
  }

  /** Qotib qolgan `pending` qaytarishlar (trigger yiqilgan / o'tkazib yuborilgan). */
  async function reconcile({ limit = RECONCILE_LIMIT, minAgeMs = RECONCILE_MIN_AGE_MS } = {}) {
    const nowMs = now().getTime();
    const out = { checked: 0, refunded: 0, skipped: 0, failed: 0 };
    const snap = await db.collection(ORDERS).where('refundStatus', '==', REFUND_STATUS.PENDING).limit(limit).get();
    for (const d of snap.docs) {
      const o = d.data() || {};
      const at = msOf(o.statusUpdatedAt) || msOf(o.updatedAt) || 0;
      if (nowMs - at < minAgeMs) continue; // trigger hali ishlayotgan bo'lishi mumkin
      out.checked += 1;
      try {
        const r = await refundOrder(d.id);
        if (r && r.refunded) out.refunded += 1; else out.skipped += 1;
      } catch (e) {
        out.failed += 1;
        logError('reconcile', { orderId: d.id, errorCode: 'WHOLESALE_RECONCILE_FAILED', message: String((e && e.message) || e).slice(0, 200) });
      }
    }
    log('reconcile', { result: 'ok', ...out });
    return out;
  }

  exportsObj.placeWholesaleOrder = functions.https.onCall(place);
  exportsObj.onWholesaleOrderStatusChange = functions.firestore
    .document(`${ORDERS}/{orderId}`)
    .onUpdate(async (change, context) => {
      await onStatusChange(change.before.data() || {}, change.after.data() || {}, context.params.orderId);
      return null;
    });
  exportsObj.wholesaleOrdersReconcile = functions.pubsub
    .schedule('every 15 minutes')
    .onRun(async () => { await reconcile(); return null; });

  return { place, refundOrder, onStatusChange, reconcile };
}

module.exports = {
  ORDERS,
  QUOTES,
  STATUS,
  REFUND_STATUSES,
  REFUND_STATUS,
  escrowAccount,
  holdKey,
  refundKey,
  quoteAmountsOk,
  attachWholesaleOrders,
};
