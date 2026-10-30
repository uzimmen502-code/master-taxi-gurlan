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
 *   SHIP_FUND (3-bosqich) Dr escrow:wholesale:{id}  Cr escrow:{shipmentId}   deliveryFee
 *           → shipment `escrow_funded`/`ready` (relay FUND maydonlari) + buyurtma
 *             placed → in_delivery; relay `onShipmentFunded` LEG'ni ochadi, yetkazilganda
 *             relay RELEASE escrow:{shipmentId} ni kuryer/AVA ga odatdagidek yopadi.
 *   RELEASE (3-bosqich, custody `deliversShipment`) Dr escrow:wholesale:{id}  goodsTotal
 *           Cr passenger_credit:{sotuvchi} sellerPayout · Cr earnings:ava_wholesale_fee avaFee
 *           → escrow:wholesale:{id} AYNAN 0; buyurtma in_delivery → delivered.
 *
 * Jurnal kalitlari: `journal_entries/bonus:{kalit}` (`prepareBonusInTx` naqshi) —
 *   wholesaleHold:{orderId}, wholesaleRefund:{orderId}; `journal_entries/{kalit}`
 *   (`postEntry`, 3+ oyoq) — wholesaleShipFund:{orderId}, wholesaleRelease:{orderId}.
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
// 3-bosqich: `in_delivery`, `delivered` — faqat SYSTEM o'tishlari (shu fayl yozadi).
const STATUS = Object.freeze({
  PLACED: 'placed', CANCELLED: 'cancelled', IN_DELIVERY: 'in_delivery', DELIVERED: 'delivered',
});
const REFUND_STATUSES = Object.freeze([STATUS.CANCELLED]);
const REFUND_STATUS = Object.freeze({ PENDING: 'pending', DONE: 'done' });

/** Reconcile: shundan eski `pending` qaytarishlar qayta ishlanadi (topshiriq: 10 daqiqa). */
const RECONCILE_MIN_AGE_MS = 10 * 60 * 1000;
const RECONCILE_LIMIT = 100;

/** relay `escrow:{shipmentId}` — `functions/relay_escrow.js` bilan BIR XIL nom. */
const SHIPMENTS = 'shipments';
const AVA_FEE_ACCOUNT = 'earnings:ava_wholesale_fee';
const shipmentEscrowAccount = (shipmentId) => `escrow:${shipmentId}`;

const escrowAccount = (orderId) => `escrow:wholesale:${orderId}`;
const holdKey = (orderId) => `wholesaleHold:${orderId}`;
const refundKey = (orderId) => `wholesaleRefund:${orderId}`;
/** 3-bosqich jurnal kalitlari (`journal_entries/{kalit}`, `postEntry` — `bonus:` prefiksisiz). */
const shipFundKey = (orderId) => `wholesaleShipFund:${orderId}`;
const releaseKey = (orderId) => `wholesaleRelease:${orderId}`;
/**
 * Relay jo'natmasi qabul qiluvchiga HAQIQATAN topshirilganmi (tovar puli shundan keyin).
 * `closed` yolg'iz yetmaydi: yo'qolgan posilka ham `lost → closed` bo'ladi — shuning uchun
 * `deliveredAt` (faqat `confirmDelivery` yozadi) SHART, yo'qolish/nizo to'lov holatlari — YO'Q.
 */
const SHIPMENT_HOLD_PAYMENT = Object.freeze(['loss_pending', 'loss_settled', 'escrow_frozen']);
function isShipmentDelivered(s) {
  const d = s || {};
  return (d.status === 'delivered' || d.status === 'closed')
    && d.deliveredAt != null
    && !SHIPMENT_HOLD_PAYMENT.includes(d.paymentStatus);
}

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
      // 3-bosqich himoyasi: yetkazish haqi relay eskrouga O'TGAN bo'lsa — bu (to'liq
      // `total`) qaytarish ISHLAMAYDI: pul ikki marta qaytib ketardi. Bunday bekor
      // qilish — admin oqimi (5-bosqich). Belgi ham, jurnal yozuvi ham tekshiriladi.
      const sfSnap = await t.get(db.collection(settlementLedger.COL_JOURNAL).doc(shipFundKey(orderId)));
      if (sfSnap.exists || pay.deliveryFunded === true) {
        return { skipped: 'delivery_funded', anomaly: true };
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
      const codes = { escrow_short: 'WHOLESALE_ESCROW_SHORT', delivery_funded: 'WHOLESALE_REFUND_AFTER_SHIP_FUND' };
      logError('refund', { orderId, errorCode: codes[out.skipped] || 'WHOLESALE_PAYMENT_INVALID' });
    } else {
      log('refund', {
        orderId, result: out.refunded ? 'ok' : 'skipped', skipped: out.skipped || null,
        amount: out.refunded || 0, stockRestored: !!out.stockRestored, durationMs: Date.now() - started,
      });
    }
    return out;
  }

  // ── 3-BOSQICH: yetkazish haqi → relay eskrou; yetkazilganda tovar puli ──
  /** Tranzaksiya ichidagi to'xtash: pul yozilmaydi. `skip` — kutilgan holat, `anomaly` — admin ko'rsin. */
  const skipErr = (reason) => Object.assign(new Error(reason), { reason, wholesaleSkip: true });
  const anomalyErr = (reason, extra) => Object.assign(new Error(reason), { reason, wholesaleAnomaly: true, extra: extra || {} });

  /** Anomaliya belgisi buyurtmada (admin, 5-bosqich) — pul YO'Q, faqat kod va vaqt (PII yo'q). */
  async function markAnomaly(orderId, field, code) {
    try {
      await db.collection(ORDERS).doc(orderId).update({ [field]: { code, at: now() } });
    } catch (e) {
      logError(field, { orderId, errorCode: 'WHOLESALE_ANOMALY_MARK_FAILED' });
    }
  }

  /**
   * SHIP_FUND: Dr escrow:wholesale:{id} / Cr escrow:{shipmentId} = deliveryFee, BITTA
   * tranzaksiyada jo'natma `escrow_funded`+`ready` (relay FUND maydonlari:
   * fundedAt, escrowEntryId, escrowAmount) va buyurtma placed → in_delivery (system,
   * history). Shart: buyurtma `placed`, `payment.held`, jo'natma shu buyurtmaniki
   * (`source: wholesale`), `awaiting_payment/pending`, deliveryFee ===
   * customerPrice (aks holda anomaliya, pul YO'Q). Idempotent: `wholesaleShipFund:{id}`.
   * Xaridor bekor qilish tranzaksiyasi ham buyurtmani o'qiydi — bittasi g'olib.
   */
  async function shipFund(orderId) {
    const started = Date.now();
    const orderRef = db.collection(ORDERS).doc(orderId);
    const s0 = await orderRef.get();
    if (!s0.exists) return { skipped: 'order_missing' };
    const o0 = s0.data() || {};
    const shipmentId = String((o0.shipment || {}).shipmentId || '');
    if (!shipmentId) return { skipped: 'no_shipment' };
    if ((o0.payment || {}).deliveryFunded === true) return { skipped: 'already_funded' };
    if (o0.status !== STATUS.PLACED) return { skipped: `status_${o0.status || 'none'}` };
    const amount = o0.deliveryFee;
    if (!isPosInt(amount)) {
      logError('shipFund', { orderId, shipmentId, errorCode: 'WHOLESALE_SHIP_FUND_FEE_INVALID' });
      await markAnomaly(orderId, 'shipFundAnomaly', 'fee_invalid');
      return { skipped: 'fee_invalid', anomaly: true };
    }
    const key = shipFundKey(orderId);
    const shipRef = db.collection(SHIPMENTS).doc(shipmentId);
    const when = now();
    try {
      const res = await settlementLedger.postEntry(db, {
        idempotencyKey: key,
        kind: 'wholesale_ship_fund',
        refType: 'wholesale_order',
        refId: orderId,
        postedBy: 'system',
        postedRole: 'system',
        legs: [
          { account: escrowAccount(orderId), dr: amount },
          { account: shipmentEscrowAccount(shipmentId), cr: amount },
        ],
      }, {
        mirrorBonus: false,
        meta: { module: 'wholesale', shipmentId, deliveryFee: amount },
        precheck: async (tx) => {
          const [os, ss] = await Promise.all([tx.get(orderRef), tx.get(shipRef)]);
          if (!os.exists) throw skipErr('order_missing');
          const o = os.data() || {};
          if (o.status !== STATUS.PLACED) throw skipErr(`status_${o.status || 'none'}`);
          if (String((o.shipment || {}).shipmentId || '') !== shipmentId) throw anomalyErr('shipment_mismatch');
          if ((o.payment || {}).status !== 'held') throw anomalyErr('payment_invalid');
          if (!ss.exists) throw anomalyErr('shipment_missing');
          const s = ss.data() || {};
          if (s.source !== 'wholesale' || s.wholesaleOrderId !== orderId) throw anomalyErr('shipment_not_wholesale');
          if (s.status !== 'awaiting_payment' || s.paymentStatus !== 'pending') {
            throw anomalyErr('shipment_not_payable', { status: s.status || null, paymentStatus: s.paymentStatus || null });
          }
          const price = (s.priceSnapshot || {}).customerPrice;
          if (o.deliveryFee !== amount || price !== amount) {
            throw anomalyErr('delivery_fee_mismatch', { deliveryFee: o.deliveryFee, customerPrice: price === undefined ? null : price });
          }
          return { o };
        },
        assert: ({ accounts }) => {
          const st = accounts.get(escrowAccount(orderId));
          if (st && st.next < 0) throw anomalyErr('escrow_short', { escrow: st.prev });
        },
        onCommit: (tx, { pre }) => {
          tx.update(shipRef, {
            paymentStatus: 'escrow_funded', status: 'ready', fundedAt: when,
            escrowEntryId: key, escrowAmount: amount, updatedAt: when,
          });
          const seq = (isInt(pre.o.historySeq) ? pre.o.historySeq : 0) + 1;
          tx.update(orderRef, {
            status: STATUS.IN_DELIVERY,
            statusUpdatedAt: when,
            updatedAt: when,
            historySeq: seq,
            'payment.deliveryFunded': true,
            'payment.deliveryFundedAt': when,
            'payment.shipFundEntryId': key,
            shipFundAnomaly: null,
          });
          tx.set(orderRef.collection(HISTORY).doc(String(seq)), {
            seq, from: STATUS.PLACED, to: STATUS.IN_DELIVERY, event: 'ship_funded', actor: 'system', actorId: null,
            reason: '', meta: { shipmentId, amount }, at: when,
          });
        },
      });
      log('shipFund', {
        orderId, shipmentId, result: res.idempotent ? 'already' : 'ok', amount, durationMs: Date.now() - started,
      });
      return { funded: amount, shipmentId, idempotent: res.idempotent === true };
    } catch (e) {
      if (e && e.wholesaleSkip) return { skipped: e.reason };
      if (e && e.wholesaleAnomaly) {
        logError('shipFund', {
          orderId, shipmentId, errorCode: `WHOLESALE_SHIP_FUND_${e.reason.toUpperCase()}`, ...e.extra,
        });
        await markAnomaly(orderId, 'shipFundAnomaly', e.reason);
        return { skipped: e.reason, anomaly: true };
      }
      throw e;
    }
  }

  /**
   * RELEASE (tovar puli): relay jo'natmasi yetkazilgach (custody `deliversShipment`,
   * Q-5) BITTA tranzaksiyada: Dr escrow:wholesale:{id} goodsTotal / Cr
   * passenger_credit:{sotuvchi hamyoni} sellerPayout / Cr earnings:ava_wholesale_fee
   * avaFee (muhr — `private/settlement`) + sotuvchi hamyoni ko'zgusi (`wholesale_payout`)
   * + buyurtma in_delivery → delivered (system) + `payment.status: released`.
   * Eskrou yozuvdan keyin AYNAN 0 bo'lmasa — anomaliya, pul YO'Q. Idempotent:
   * `wholesaleRelease:{id}` (takror custody hodisasi / reconcile — bir marta).
   */
  async function releaseGoods(orderId) {
    const started = Date.now();
    const orderRef = db.collection(ORDERS).doc(orderId);
    const settleRef = orderRef.collection(PRIVATE).doc('settlement');
    const [s0, st0] = await Promise.all([orderRef.get(), settleRef.get()]);
    if (!s0.exists) return { skipped: 'order_missing' };
    const o0 = s0.data() || {};
    if (o0.status === STATUS.DELIVERED) return { skipped: 'already_released' };
    if (o0.status !== STATUS.IN_DELIVERY) return { skipped: `status_${o0.status || 'none'}` };
    const shipmentId = String((o0.shipment || {}).shipmentId || '');
    const fail0 = async (reason) => {
      logError('release', { orderId, shipmentId, errorCode: `WHOLESALE_RELEASE_${reason.toUpperCase()}` });
      await markAnomaly(orderId, 'releaseAnomaly', reason);
      return { skipped: reason, anomaly: true };
    };
    if (!shipmentId) return fail0('no_shipment');
    const st = st0.exists ? (st0.data() || {}) : {};
    const { goodsTotal, avaFee, sellerPayout } = st;
    if (!isPosInt(goodsTotal) || !isInt(avaFee) || avaFee < 0 || !isInt(sellerPayout) || sellerPayout < 0
      || avaFee + sellerPayout !== goodsTotal || goodsTotal !== o0.goodsTotal) {
      return fail0('settlement_invalid');
    }
    const sellerWalletUid = await walletUidOf(canonicalUid(o0.sellerId || ''));
    if (!sellerWalletUid) return fail0('seller_wallet_missing');
    const key = releaseKey(orderId);
    const shipRef = db.collection(SHIPMENTS).doc(shipmentId);
    const legs = [{ account: escrowAccount(orderId), dr: goodsTotal }];
    if (sellerPayout > 0) legs.push({ account: settlementLedger.passengerCreditAccount(sellerWalletUid), cr: sellerPayout });
    if (avaFee > 0) legs.push({ account: AVA_FEE_ACCOUNT, cr: avaFee });
    const when = now();
    try {
      const res = await settlementLedger.postEntry(db, {
        idempotencyKey: key,
        kind: 'wholesale_release',
        refType: 'wholesale_order',
        refId: orderId,
        postedBy: 'system',
        postedRole: 'system',
        legs,
      }, {
        mirrorBonus: false, // ko'zgu — `mirrorWallet` (wholesale wallet_ledger shakli) onCommit'da
        meta: {
          module: 'wholesale', shipmentId, goodsTotal, sellerPayout, avaFee,
          avaFeeBps: isInt(st.avaFeeBps) ? st.avaFeeBps : null, feeVersion: isInt(st.feeVersion) ? st.feeVersion : null,
        },
        precheck: async (tx) => {
          const [os, ss, sts] = await Promise.all([tx.get(orderRef), tx.get(shipRef), tx.get(settleRef)]);
          if (!os.exists) throw skipErr('order_missing');
          const o = os.data() || {};
          if (o.status !== STATUS.IN_DELIVERY) throw skipErr(`status_${o.status || 'none'}`);
          if (String((o.shipment || {}).shipmentId || '') !== shipmentId) throw anomalyErr('shipment_mismatch');
          if ((o.payment || {}).deliveryFunded !== true) throw anomalyErr('delivery_not_funded');
          const s = ss.exists ? (ss.data() || {}) : {};
          if (s.wholesaleOrderId !== orderId) throw anomalyErr('shipment_not_wholesale');
          if (!isShipmentDelivered(s)) throw skipErr(`shipment_${s.status || 'none'}`);
          const cur = sts.exists ? (sts.data() || {}) : {};
          if (cur.goodsTotal !== goodsTotal || cur.avaFee !== avaFee || cur.sellerPayout !== sellerPayout) {
            throw anomalyErr('settlement_changed');
          }
          return { o };
        },
        assert: ({ accounts }) => {
          const e = accounts.get(escrowAccount(orderId));
          // Eskrou AYNAN 0 ga tushishi shart: ortiq/kam pul — anomaliya (o'ylab topilmaydi).
          if (!e || e.next !== 0) throw anomalyErr('escrow_not_zero', { escrowBefore: e ? e.prev : null });
        },
        onCommit: (tx, { pre }) => {
          if (sellerPayout > 0) {
            mirrorWallet(tx, sellerWalletUid, sellerPayout, 'wholesale_payout', orderId, when, {
              goodsTotal, avaFee, shipmentId,
            });
          }
          const seq = (isInt(pre.o.historySeq) ? pre.o.historySeq : 0) + 1;
          tx.update(orderRef, {
            status: STATUS.DELIVERED,
            deliveredAt: when,
            statusUpdatedAt: when,
            updatedAt: when,
            historySeq: seq,
            'payment.status': 'released',
            'payment.releasedAt': when,
            'payment.releaseEntryId': key,
            releaseAnomaly: null,
          });
          tx.set(orderRef.collection(HISTORY).doc(String(seq)), {
            seq, from: STATUS.IN_DELIVERY, to: STATUS.DELIVERED, event: 'goods_released', actor: 'system', actorId: null,
            reason: '', meta: { shipmentId, sellerPayout, avaFee }, at: when,
          });
        },
      });
      log('release', {
        orderId, shipmentId, result: res.idempotent ? 'already' : 'ok', amount: goodsTotal, sellerPayout, avaFee,
        durationMs: Date.now() - started,
      });
      return {
        released: goodsTotal, sellerPayout, avaFee, shipmentId, idempotent: res.idempotent === true,
      };
    } catch (e) {
      if (e && e.wholesaleSkip) return { skipped: e.reason };
      if (e && e.wholesaleAnomaly) {
        logError('release', { orderId, shipmentId, errorCode: `WHOLESALE_RELEASE_${e.reason.toUpperCase()}`, ...e.extra });
        await markAnomaly(orderId, 'releaseAnomaly', e.reason);
        return { skipped: e.reason, anomaly: true };
      }
      throw e;
    }
  }

  /**
   * Relay custody triggeridan (`relay_escrow.onCustodyEvent`, `deliversShipment`):
   * jo'natma Ulgurji buyurtmasiniki bo'lsa — tovar puli. Oddiy jo'natma — tegmaydi.
   */
  async function onShipmentDelivered(shipmentId) {
    const s = await db.collection(SHIPMENTS).doc(String(shipmentId || '')).get();
    if (!s.exists) return { skipped: 'shipment_missing' };
    const ship = s.data() || {};
    const orderId = typeof ship.wholesaleOrderId === 'string' ? ship.wholesaleOrderId : '';
    if (!orderId) return { skipped: 'not_wholesale' };
    if (!isShipmentDelivered(ship)) return { skipped: `shipment_${ship.status || 'none'}` };
    return releaseGoods(orderId);
  }

  /**
   * wholesale_orders onUpdate:
   *   - `placed` + `shipment` bog'langan (demand triggeri yozadi) + haq hali o'tmagan → SHIP_FUND;
   *   - cancelled + refundStatus=pending → qaytarish.
   */
  async function onStatusChange(before, after, orderId) {
    const a = after || {};
    // `shipFundAnomaly` bor bo'lsa trigger QAYTA urinmaydi (belgi yozuvi shu triggerni
    // yana chaqiradi — cheksiz aylanish bo'lmasin); qayta urinish — reconcile.
    if (a.status === STATUS.PLACED && a.shipment && a.shipment.shipmentId
      && (a.payment || {}).deliveryFunded !== true && !a.shipFundAnomaly) {
      try {
        return await shipFund(orderId);
      } catch (e) {
        // Reconcile qayta urinadi; har qadam idempotent.
        logError('shipFund', { orderId, errorCode: 'WHOLESALE_SHIP_FUND_FAILED', message: String((e && e.message) || e).slice(0, 200) });
        return { skipped: 'failed' };
      }
    }
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

  /**
   * Qotib qolganlar (trigger yiqilgan / o'tkazib yuborilgan), har biri 10 daqiqadan eski:
   *   A) `pending` qaytarishlar;
   *   B) jo'natma bog'langan, lekin yetkazish haqi o'tmagan (`placed`) → SHIP_FUND;
   *   C) jo'natma yetkazilgan, buyurtma hali `in_delivery` → RELEASE.
   * Har yozuv idempotent — trigger bilan bir vaqtda ishlash xavfsiz. Tenglik
   * filtrlari bitta maydonda (yangi indeks kerak emas).
   */
  async function reconcile({ limit = RECONCILE_LIMIT, minAgeMs = RECONCILE_MIN_AGE_MS } = {}) {
    const nowMs = now().getTime();
    const out = {
      checked: 0, refunded: 0, skipped: 0, failed: 0, shipFundChecked: 0, shipFunded: 0, releaseChecked: 0, released: 0,
    };
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
    // B) SHIP_FUND qotgan.
    const placed = await db.collection(ORDERS).where('status', '==', STATUS.PLACED).limit(limit).get();
    for (const d of placed.docs) {
      const o = d.data() || {};
      const sh = o.shipment || null;
      if (!sh || !sh.shipmentId || (o.payment || {}).deliveryFunded === true) continue;
      if (nowMs - (msOf(sh.createdAt) || msOf(o.updatedAt) || 0) < minAgeMs) continue;
      out.shipFundChecked += 1;
      try {
        const r = await shipFund(d.id);
        if (r && r.funded && !r.idempotent) out.shipFunded += 1;
      } catch (e) {
        out.failed += 1;
        logError('reconcile', { orderId: d.id, errorCode: 'WHOLESALE_RECONCILE_SHIP_FUND_FAILED', message: String((e && e.message) || e).slice(0, 200) });
      }
    }
    // C) RELEASE qotgan (jo'natma yetkazilgan, buyurtma in_delivery).
    const inDel = await db.collection(ORDERS).where('status', '==', STATUS.IN_DELIVERY).limit(limit).get();
    for (const d of inDel.docs) {
      const o = d.data() || {};
      const shipmentId = String((o.shipment || {}).shipmentId || '');
      if (!shipmentId) continue;
      try {
        const s = await db.collection(SHIPMENTS).doc(shipmentId).get();
        const ship = s.exists ? (s.data() || {}) : {};
        if (!isShipmentDelivered(ship)) continue;
        if (nowMs - (msOf(ship.deliveredAt) || msOf(ship.updatedAt) || 0) < minAgeMs) continue;
        out.releaseChecked += 1;
        const r = await releaseGoods(d.id);
        if (r && r.released && !r.idempotent) out.released += 1;
      } catch (e) {
        out.failed += 1;
        logError('reconcile', { orderId: d.id, errorCode: 'WHOLESALE_RECONCILE_RELEASE_FAILED', message: String((e && e.message) || e).slice(0, 200) });
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

  return {
    place, refundOrder, onStatusChange, reconcile, shipFund, releaseGoods, onShipmentDelivered,
  };
}

module.exports = {
  ORDERS,
  QUOTES,
  STATUS,
  REFUND_STATUSES,
  REFUND_STATUS,
  AVA_FEE_ACCOUNT,
  escrowAccount,
  shipmentEscrowAccount,
  holdKey,
  refundKey,
  shipFundKey,
  releaseKey,
  quoteAmountsOk,
  attachWholesaleOrders,
};
