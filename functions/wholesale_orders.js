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
 *
 * ── 3b-BOSQICH: «YETKAZILGANDA KARTA ORQALI» (ega, 2026-10-31) ─────────
 * Xaridor eshik oldida hammasini (tovar + yetkazish) SOTUVCHI KARTASIGA to'laydi (AVA
 * orqali emas). Kuryer haqi + AVA ulushi SOTUVCHI hamyonidan ushlanadi:
 *   CARD HOLD   Dr passenger_credit:{sotuvchi}  Cr escrow:wholesale:{id}   deliveryFee+avaFee
 *               (`wholesaleHold:{id}`, placeWholesaleOrder; xaridor hamyoniga TEGILMAYDI)
 *   SHIP_FUND   o'zgarmagan (deliveryFee → escrow:{shipmentId}); eskrouda avaFee qoladi
 *   RELEASE     Dr escrow:wholesale:{id} avaFee / Cr earnings:ava_wholesale_fee (sotuvchiga 0 —
 *               tovar puli unga to'g'ridan-to'g'ri tushgan); `wholesaleRelease:{id}`; eskrou 0
 *   CANCEL      (yetkazish haqi o'tmasdan) to'lovchiga — SOTUVCHIGA — to'liq (`wholesaleRefund:{id}`)
 *   REFUSED     eskrouda qolgan avaFee → sotuvchiga (sotuv yo'q — PROPOSED; `wholesaleRefused:{id}`);
 *               yetkazish haqi escrow:{shipmentId} da kuryerlar uchun qoladi (qaytarilmaydi)
 *   RETURN HOLD Dr passenger_credit:{sotuvchi} Cr escrow:wholesale_return:{id}  qaytish haqi
 *               (`wholesaleReturnHold:{id}`); yetmasa — MANFIYGA TUSHMAYDI: `order.returnDebt`,
 *               `wholesale_seller_stats/{sotuvchi}.cardBlocked = true`, reconcile qayta urinadi
 *   RETURN FUND Dr escrow:wholesale_return:{id} Cr escrow:{qaytishShipmentId} (`wholesaleReturnFund:{id}`)
 *               → qaytish jo'natmasi `escrow_funded`/`ready`, buyurtma refused → returning
 *   RETURNED    qaytish jo'natmasi sotuvchiga yetdi (custody `deliversShipment`) → returned + qoldiq +N
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
  PLACED: 'placed',
  CANCELLED: 'cancelled',
  IN_DELIVERY: 'in_delivery',
  DELIVERED: 'delivered',
  // 3b (karta): refused/returning/returned — shu fayl va demand; payment_dispute — faqat demand.
  REFUSED: 'refused',
  PAYMENT_DISPUTE: 'payment_dispute',
  RETURNING: 'returning',
  RETURNED: 'returned',
});
const REFUND_STATUSES = Object.freeze([STATUS.CANCELLED, STATUS.REFUSED]);
const REFUND_STATUS = Object.freeze({ PENDING: 'pending', DONE: 'done' });
/** Paritet: demand `core/wholesale_orders.js` (yagona jadval) — functions/test/wholesale_orders.test.js. */
const PAYMENT_METHOD = Object.freeze({ WALLET: 'wallet', CARD: 'card_on_delivery' });
const CARD_PAYMENT = Object.freeze({
  AWAITING: 'awaiting', RECEIPT_SUBMITTED: 'receipt_submitted', CONFIRMED: 'confirmed', DISPUTED: 'disputed',
});
const CARD_REFUSAL_LIMIT = 2;
const RETURN_STATUS = Object.freeze({
  PENDING_SHIPMENT: 'pending_shipment', AWAITING_PAYMENT: 'awaiting_payment', IN_TRANSIT: 'in_transit', RETURNED: 'returned',
});
const methodOf = (doc) => ((doc || {}).paymentMethod === PAYMENT_METHOD.CARD ? PAYMENT_METHOD.CARD : PAYMENT_METHOD.WALLET);
/** Ushlanma holati: hamyon — xaridor (`held`), karta — sotuvchi (`held_seller`). */
const HELD_STATUSES = Object.freeze(['held', 'held_seller']);
const SELLERS = 'wholesale_sellers';
const BUYER_STATS = 'wholesale_buyer_stats';
const SELLER_STATS = 'wholesale_seller_stats';
const RETURN_SOURCE = 'wholesale_return';

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
/** 3b kalitlari: `bonus:` prefiksli (prepareBonusInTx) — refused, returnHold; `postEntry` — returnFund. */
const refusedKey = (orderId) => `wholesaleRefused:${orderId}`;
const returnHoldKey = (orderId) => `wholesaleReturnHold:${orderId}`;
const returnFundKey = (orderId) => `wholesaleReturnFund:${orderId}`;
const returnEscrowAccount = (orderId) => `escrow:wholesale_return:${orderId}`;
/**
 * Relay hisob/kalitlari — `functions/relay_escrow.js` bilan AYNAN bir xil (o'sha fayl O'ZGARMAYDI;
 * paritet + «ikki yo'l bir vaqtda» testi: functions/test/wholesale_card_cf.test.js). Rad etilgan karta
 * buyurtmasining CHIQISH jo'natmasi shu kalitlar bilan yopiladi — relay keyinroq o'z EARNED/RELEASE'ini
 * yursa ham ledger idempotentligi ikkinchi to'lovni bermaydi; kuryer to'lovi triggeri
 * `relayEarned:*` yozuvlarini ko'radi.
 */
const RELAY_ACCRUAL_ACCOUNT = 'platform_accrual';
const RELAY_FEE_ACCOUNT = 'earnings:ava_logistics_fee';
const relayEarnedKey = (shipmentId, legId) => `relayEarned:${shipmentId}:${legId}`;
const relayReleaseKey = (shipmentId) => `relayRelease:${shipmentId}`;
const OUTBOUND_SETTLE_STATUSES = Object.freeze([STATUS.REFUSED, STATUS.RETURNING, STATUS.RETURNED]);
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

      // 3b: to'lov usuli kvotada muhrlangan. Karta — ushlanma SOTUVCHI hamyonidan: uning
      // hujjati tranzaksiyadan oldin aniqlanadi (ledger o'qishi uchun), tekshiruv — ichida.
      const q0s = await quoteRef.get();
      const q0 = q0s.exists ? (q0s.data() || {}) : {};
      const method = methodOf(q0);
      const isCard = method === PAYMENT_METHOD.CARD;
      const sellerKey = isCard ? canonicalUid(q0.sellerId || '') : '';
      const sellerWalletUid = isCard && /^998\d{9}$/.test(sellerKey) ? await walletUidOf(sellerKey) : null;

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
        // Muhr tranzaksiyadan oldingi o'qish bilan bir xil bo'lishi shart (usul / sotuvchi).
        if (methodOf(q) !== method || (isCard && canonicalUid(q.sellerId) !== sellerKey)) {
          throw fail('failed-precondition', 'Narx so\'rovi yaroqsiz. Qaytadan hisoblang', 'quote_invalid');
        }
        const cardHold = isCard ? q.deliveryFee + q.avaFee : 0;
        if (isCard && (!isPosInt(cardHold) || (q.cardHold !== undefined && q.cardHold !== cardHold))) {
          throw fail('failed-precondition', 'Narx so\'rovi yaroqsiz. Qaytadan hisoblang', 'quote_invalid');
        }
        if (isCard && !sellerWalletUid) {
          throw fail('failed-precondition', 'Bu buyurtmani karta orqali to\'lab bo\'lmaydi', 'seller_balance_insufficient');
        }
        const productRef = db.collection(PRODUCTS).doc(String(q.productId));
        const stockRef = db.collection(STOCK).doc(String(q.productId));
        const [pSnap, sSnap] = await Promise.all([t.get(productRef), t.get(stockRef)]);
        // Karta: sotuvchi kartasi, qaytish qarzi bloki, xaridor rad hisoblagichi — kvotadan
        // keyin o'zgargan bo'lishi mumkin, shuning uchun tranzaksiyada QAYTA o'qiladi.
        let cardCtx = null;
        if (isCard) {
          const payoutIds = [...new Set([String(q.sellerId), sellerKey, sellerKey.slice(3)])];
          const [payoutSnaps, sStatsSnap, bStatsSnap] = await Promise.all([
            Promise.all(payoutIds.map((id) => t.get(db.collection(SELLERS).doc(id).collection(PRIVATE).doc('payout')))),
            t.get(db.collection(SELLER_STATS).doc(sellerKey)),
            t.get(db.collection(BUYER_STATS).doc(uid)),
          ]);
          cardCtx = {
            hasCard: payoutSnaps.some((p) => p.exists && /^\d{16}$/.test(String((p.data() || {}).cardNumber || ''))),
            blocked: sStatsSnap.exists && (sStatsSnap.data() || {}).cardBlocked === true,
            refusals: bStatsSnap.exists && isInt((bStatsSnap.data() || {}).cardRefusals) ? (bStatsSnap.data() || {}).cardRefusals : 0,
          };
        }
        // Ushlanma kimning hamyonidan: hamyon — xaridor, karta — sotuvchi.
        const payerWalletUid = isCard ? sellerWalletUid : walletUid;
        const ledger = await settlementLedger.prepareBonusInTx(t, db, payerWalletUid, {
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
        if (isCard) {
          const no = (reason) => fail('failed-precondition', 'Bu buyurtmani karta orqali to\'lab bo\'lmaydi', reason);
          if (!cardCtx.hasCard) throw no('seller_no_card');
          if (cardCtx.blocked) throw no('seller_debt');
          if (cardCtx.refusals >= CARD_REFUSAL_LIMIT) throw no('buyer_limited');
          // Sotuvchi balansi xaridorga OSHKOR QILINMAYDI (faqat sabab kodi).
          if (ledger.pcPrev < cardHold) throw no('seller_balance_insufficient');
        } else if (ledger.pcPrev < q.total) {
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

        if (isCard) {
          // Kuryer haqi + AVA ulushi — SOTUVCHI hamyonidan (ega, 2026-10-31). Xaridor hamyoniga tegilmaydi.
          settlementLedger.commitBonusInTx(t, ledger, {
            delta: -cardHold,
            kind: 'wholesale_card_hold',
            refType: 'wholesale_order',
            refId: orderId,
            meta: {
              module: 'wholesale', paymentMethod: method, productId: q.productId, packId: q.packId, qty: q.qty,
              deliveryFee: q.deliveryFee, avaFee: q.avaFee,
            },
            postedBy: 'system',
            postedRole: 'system',
          });
          mirrorWallet(t, sellerWalletUid, -cardHold, 'wholesale_card_hold', orderId, when, {
            deliveryFee: q.deliveryFee, avaFee: q.avaFee,
          });
        } else {
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
        }

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
          paymentMethod: method,
          payment: isCard ? {
            status: 'held_seller',
            amount: cardHold,
            payer: 'seller',
            payerWalletUid: sellerWalletUid,
            heldAt: when,
            escrowAccount: escrowAccount(orderId),
            holdEntryId: `bonus:${holdKey(orderId)}`,
          } : {
            status: 'held',
            amount: q.total,
            payer: 'buyer',
            heldAt: when,
            escrowAccount: escrowAccount(orderId),
            holdEntryId: `bonus:${holdKey(orderId)}`,
          },
          ...(isCard ? { cardPayment: { status: CARD_PAYMENT.AWAITING, confirmedAt: null } } : {}),
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
          meta: { quoteId, total: q.total, paymentMethod: method, ...(isCard ? { sellerHold: cardHold } : {}) }, at: when,
        });
        t.set(idemRef, {
          kind: 'wholesale_place', orderId, quoteId, buyerId: uid, createdAt: when,
        });
        return {
          orderId, total: q.total, productId: q.productId, packId: q.packId, qty: q.qty, held: isCard ? cardHold : q.total,
        };
      });

      if (out.replay) {
        const r = replay(out.replay, quoteId);
        log('place', { result: 'already', orderId: r.orderId, quoteId, durationMs: Date.now() - started });
        return r;
      }
      log('place', {
        result: 'ok', orderId: out.orderId, quoteId, productId: out.productId, packId: out.packId,
        qty: out.qty, amount: out.total, held: out.held, paymentMethod: method, durationMs: Date.now() - started,
      });
      return {
        ok: true, orderId: out.orderId, status: STATUS.PLACED, total: out.total, paymentMethod: method, idempotent: false,
      };
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

  /** Buyurtma ushlagan qoldiqni qaytarish kerakmi (`stock.decremented` va hali tiklanmagan). */
  function stockToRestore(o) {
    const so = (o || {}).stock || {};
    const restore = so.decremented === true && so.restored !== true
      && isPosInt(so.qty) && typeof so.packId === 'string' && so.packId !== '';
    return { so, restore };
  }

  /** Qoldiq +N + versiya + history (o'qish — chaqiruvchida, yozuvdan oldin). */
  function writeStockRestore(t, stockRef, sSnap, o, so, when, kind) {
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
      kind, from: packs, to: nextPacks, packId: so.packId, qty: so.qty,
      orderId: o.__id || null, by: 'system', at: when, version,
    });
  }

  /**
   * 3b REFUSED: karta buyurtmasi rad etildi (yetkazish haqi allaqachon escrow:{shipmentId} da —
   * kuryerlar uchun QOLADI). escrow:wholesale:{id} da qolgan avaFee → SOTUVCHI hamyoniga
   * (sotuv bo'lmadi — PROPOSED). Eskrou AYNAN avaFee bo'lishi shart (aks holda anomaliya).
   * Qoldiq bu yerda TIKLANMAYDI — faqat tovar sotuvchiga qaytganda (`returned`).
   */
  async function settleRefusalInTx(t, orderRef, o, orderId, when) {
    const pay = o.payment || {};
    const payerWalletUid = String(pay.payerWalletUid || '');
    if (methodOf(o) !== PAYMENT_METHOD.CARD || pay.status !== 'held_seller' || !payerWalletUid) {
      return { skipped: 'refusal_payment_invalid', anomaly: true };
    }
    if (pay.deliveryFunded !== true) return { skipped: 'refusal_not_funded', anomaly: true };
    const amount = pay.amount - o.deliveryFee;
    if (!isInt(amount) || amount < 0) return { skipped: 'refusal_amount_invalid', anomaly: true };
    const ledger = await settlementLedger.prepareBonusInTx(t, db, payerWalletUid, {
      fundingAccount: escrowAccount(orderId), idempotencyKey: refusedKey(orderId),
    });
    if (!ledger.jExists && ledger.fundPrev !== amount) {
      return { skipped: 'escrow_mismatch', anomaly: true, escrow: ledger.fundPrev };
    }
    if (amount > 0 && !ledger.jExists) {
      settlementLedger.commitBonusInTx(t, ledger, {
        delta: amount,
        kind: 'wholesale_refusal_refund',
        refType: 'wholesale_order',
        refId: orderId,
        meta: { module: 'wholesale', status: o.status, payer: 'seller', reason: 'buyer_refused' },
        postedBy: 'system',
        postedRole: 'system',
      });
      mirrorWallet(t, payerWalletUid, amount, 'wholesale_refusal_refund', orderId, when, { reason: 'buyer_refused' });
    }
    const seq = (isInt(o.historySeq) ? o.historySeq : 0) + 1;
    t.update(orderRef, {
      refundStatus: REFUND_STATUS.DONE,
      refundedAt: when,
      'payment.status': 'refusal_settled',
      'payment.refusalRefund': amount,
      'payment.refusalEntryId': amount > 0 ? `bonus:${refusedKey(orderId)}` : null,
      'payment.refundedAt': when,
      historySeq: seq,
      updatedAt: when,
    });
    t.set(orderRef.collection(HISTORY).doc(String(seq)), {
      seq, from: o.status, to: o.status, event: 'refusal_settled', actor: 'system', actorId: null,
      reason: '', meta: { avaFeeRefunded: amount, payer: 'seller' }, at: when,
    });
    return { refunded: amount, refusal: true, stockRestored: false, ledgerExisted: ledger.jExists };
  }

  // ── QAYTARISH: cancelled → to'lovchiga to'liq + qoldiq +N; refused → AVA ulushi sotuvchiga ──
  /**
   * Idempotent (holat tranzaksiya ichida): `refundStatus === 'done'` bo'lsa hech narsa
   * yozilmaydi. Jurnal yozuvi allaqachon bo'lsa (`jExists`) — pul qayta yozilmaydi.
   * To'lovchi: hamyon buyurtmasi — xaridor (`buyerWalletUid`, o'zgarmagan); karta — sotuvchi
   * (`payment.payerWalletUid`).
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
      if (o.status === STATUS.REFUSED) return settleRefusalInTx(t, orderRef, o, orderId, when);
      const pay = o.payment || {};
      const amount = pay.amount;
      const isCard = methodOf(o) === PAYMENT_METHOD.CARD;
      const walletUid = isCard ? String(pay.payerWalletUid || '') : String(o.buyerWalletUid || '');
      if (pay.status !== (isCard ? 'held_seller' : 'held') || !isPosInt(amount) || !walletUid) {
        return { skipped: 'payment_invalid', anomaly: true };
      }
      // 3-bosqich himoyasi: yetkazish haqi relay eskrouga O'TGAN bo'lsa — bu (to'liq
      // `total`) qaytarish ISHLAMAYDI: pul ikki marta qaytib ketardi. Bunday bekor
      // qilish — admin oqimi (5-bosqich). Belgi ham, jurnal yozuvi ham tekshiriladi.
      const sfSnap = await t.get(db.collection(settlementLedger.COL_JOURNAL).doc(shipFundKey(orderId)));
      if (sfSnap.exists || pay.deliveryFunded === true) {
        return { skipped: 'delivery_funded', anomaly: true };
      }
      const { so, restore } = stockToRestore(o);
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
          meta: { module: 'wholesale', status: o.status, ...(isCard ? { payer: 'seller' } : {}) },
          postedBy: 'system',
          postedRole: 'system',
        });
        mirrorWallet(t, walletUid, amount, 'wholesale_refund', orderId, when, { status: o.status });
      }
      if (restore) writeStockRestore(t, stockRef, sSnap, { ...o, __id: orderId }, so, when, 'order_refund');
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
      const codes = {
        escrow_short: 'WHOLESALE_ESCROW_SHORT',
        delivery_funded: 'WHOLESALE_REFUND_AFTER_SHIP_FUND',
        escrow_mismatch: 'WHOLESALE_REFUSAL_ESCROW_MISMATCH',
        refusal_not_funded: 'WHOLESALE_REFUSAL_NOT_FUNDED',
        refusal_payment_invalid: 'WHOLESALE_REFUSAL_PAYMENT_INVALID',
        refusal_amount_invalid: 'WHOLESALE_REFUSAL_AMOUNT_INVALID',
      };
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
          // Hamyon — `held` (xaridor), karta — `held_seller` (sotuvchi ushlanmasi): ikkalasida
          // eskrouda yetkazish haqi bor (karta: deliveryFee + avaFee).
          if (!HELD_STATUSES.includes((o.payment || {}).status)) throw anomalyErr('payment_invalid');
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
    if (methodOf(o0) === PAYMENT_METHOD.CARD) return releaseCard(orderId, shipmentId, st, started);
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

  // ── 3b: KARTA buyurtmasi yetkazildi — faqat AVA ulushi (tovar puli sotuvchiga to'g'ridan-to'g'ri) ──
  /**
   * RELEASE (karta): eskrouda (SHIP_FUND dan keyin) AYNAN avaFee qolgan: Dr escrow:wholesale:{id}
   * / Cr earnings:ava_wholesale_fee (`wholesaleRelease:{id}`), AVA orqali sotuvchiga 0. avaFee = 0
   * bo'lsa — jurnal yozuvi YO'Q (nol yozuv taqiqlangan), eskrou 0 ekani tranzaksiyada tekshiriladi.
   * Sotuvchi «Pul tushdi» bosmagan bo'lsa ham (kod faqat tasdiqdan keyin beriladi — bunday
   * yetkazish relay egasi kodi orqali bo'lishi mumkin) AVA ulushi olinadi; holat history'da.
   */
  async function releaseCard(orderId, shipmentId, st, started) {
    const orderRef = db.collection(ORDERS).doc(orderId);
    const settleRef = orderRef.collection(PRIVATE).doc('settlement');
    const shipRef = db.collection(SHIPMENTS).doc(shipmentId);
    const escRef = db.collection(settlementLedger.COL_ACCOUNTS).doc(escrowAccount(orderId));
    const { avaFee } = st;
    const key = releaseKey(orderId);
    const when = now();
    const precheck = async (tx) => {
      const [os, ss, sts] = await Promise.all([tx.get(orderRef), tx.get(shipRef), tx.get(settleRef)]);
      if (!os.exists) throw skipErr('order_missing');
      const o = os.data() || {};
      if (o.status !== STATUS.IN_DELIVERY) throw skipErr(`status_${o.status || 'none'}`);
      if (String((o.shipment || {}).shipmentId || '') !== shipmentId) throw anomalyErr('shipment_mismatch');
      const pay = o.payment || {};
      if (pay.deliveryFunded !== true) throw anomalyErr('delivery_not_funded');
      if (pay.status !== 'held_seller') throw anomalyErr('payment_invalid');
      const s = ss.exists ? (ss.data() || {}) : {};
      if (s.wholesaleOrderId !== orderId) throw anomalyErr('shipment_not_wholesale');
      if (!isShipmentDelivered(s)) throw skipErr(`shipment_${s.status || 'none'}`);
      const cur = sts.exists ? (sts.data() || {}) : {};
      if (cur.avaFee !== avaFee) throw anomalyErr('settlement_changed');
      return { o };
    };
    const onCommit = (tx, { pre }, entryId) => {
      const cps = (pre.o.cardPayment || {}).status || null;
      const seq = (isInt(pre.o.historySeq) ? pre.o.historySeq : 0) + 1;
      tx.update(orderRef, {
        status: STATUS.DELIVERED,
        deliveredAt: when,
        statusUpdatedAt: when,
        updatedAt: when,
        historySeq: seq,
        'payment.status': 'released',
        'payment.releasedAt': when,
        'payment.releaseEntryId': entryId,
        'payment.sellerPayoutViaAva': 0,
        releaseAnomaly: null,
      });
      tx.set(orderRef.collection(HISTORY).doc(String(seq)), {
        seq, from: STATUS.IN_DELIVERY, to: STATUS.DELIVERED, event: 'goods_released', actor: 'system', actorId: null,
        reason: '', meta: {
          shipmentId, sellerPayout: 0, avaFee, paymentMethod: PAYMENT_METHOD.CARD, cardPaymentStatus: cps,
        },
        at: when,
      });
    };
    try {
      let idempotent = false;
      if (avaFee > 0) {
        const res = await settlementLedger.postEntry(db, {
          idempotencyKey: key,
          kind: 'wholesale_release',
          refType: 'wholesale_order',
          refId: orderId,
          postedBy: 'system',
          postedRole: 'system',
          legs: [{ account: escrowAccount(orderId), dr: avaFee }, { account: AVA_FEE_ACCOUNT, cr: avaFee }],
        }, {
          mirrorBonus: false,
          meta: {
            module: 'wholesale', paymentMethod: PAYMENT_METHOD.CARD, shipmentId, avaFee, sellerPayout: 0,
            avaFeeBps: isInt(st.avaFeeBps) ? st.avaFeeBps : null, feeVersion: isInt(st.feeVersion) ? st.feeVersion : null,
          },
          precheck,
          assert: ({ accounts }) => {
            const e = accounts.get(escrowAccount(orderId));
            if (!e || e.next !== 0) throw anomalyErr('escrow_not_zero', { escrowBefore: e ? e.prev : null });
          },
          onCommit: (tx, ctx) => onCommit(tx, ctx, key),
        });
        idempotent = res.idempotent === true;
      } else {
        await db.runTransaction(async (tx) => {
          const pre = await precheck(tx);
          const es = await tx.get(escRef);
          const bal = es.exists ? ((es.data() || {}).balance || 0) : 0;
          if (bal !== 0) throw anomalyErr('escrow_not_zero', { escrowBefore: bal });
          onCommit(tx, { pre }, null);
        });
      }
      log('release', {
        orderId, shipmentId, result: idempotent ? 'already' : 'ok', paymentMethod: PAYMENT_METHOD.CARD, amount: avaFee,
        sellerPayout: 0, avaFee, durationMs: Date.now() - started,
      });
      return { released: avaFee, sellerPayout: 0, avaFee, shipmentId, card: true, idempotent };
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

  // ── 3b: RAD — CHIQISH jo'natmasini relay yetkazilgandagidek yopish (kuryer haqi kuryerlarga) ──
  /**
   * Ega qarori: rad etilganda kuryer haqi QAYTARILMAYDI = kuryerlarniki. Relay o'z EARNED/RELEASE'ini
   * faqat yetkazishda (custody `deliversShipment`) qiladi — rad etilgan jo'natmada pul abadiy
   * escrow:{shipmentId} da qolardi. Shu sabab Ulgurji moduli relay'ning AYNAN o'sha yozuvlarini
   * AYNAN o'sha kalitlar bilan yozadi (relay fayliga tegilmaydi):
   *   EARNED  (har ishlangan LEG) Dr platform_accrual / Cr supplier_payable:{ijrochi} = legPayout
   *           `relayEarned:{shipmentId}:{legId}` (kind `logistics_leg_earned`)
   *   RELEASE Dr escrow:{shipmentId} = customerPrice / Cr platform_accrual Σ ishlangan /
   *           Cr earnings:ava_logistics_fee platformShare / Cr passenger_credit:{sotuvchi} Σ ishlanmagan
   *           `relayRelease:{shipmentId}` (kind `logistics_escrow_release`) — eskrou AYNAN 0.
   * «Ishlangan LEG» = indeksi ≤ joriy LEG (`currentLegId`, posilka shu yerga yetgan) va ijrochisi bor.
   * Undan keyingi (posilka yetmagan) yoki ijrochisiz LEG ulushi — to'lovchiga (sotuvchiga) qaytadi
   * (PROPOSED). Holat (AYNI RELEASE tranzaksiyasida): jo'natma `paymentStatus: settled` (relay RELEASE
   * yozadigan qiymat) + `wholesaleOutcome: 'refused'` — `in_transit` dan relay mashinasida «rad» holati
   * YO'Q, shuning uchun `status` o'zgarmaydi; joriy LEG `in_progress → completed` (`outcome:
   * 'buyer_refused'`), posilka yetmagan LEG'lar `→ cancelled`; ijrochi match'idan kontakt (PII) olinadi.
   * Idempotent: relay kalitlari; `relayRelease` allaqachon bo'lsa (relay o'zi yopgan) — pul yozilmaydi.
   */
  async function settleOutboundOnRefusal(orderId) {
    const started = Date.now();
    const orderRef = db.collection(ORDERS).doc(orderId);
    const s0 = await orderRef.get();
    if (!s0.exists) return { skipped: 'order_missing' };
    const o0 = s0.data() || {};
    if (!OUTBOUND_SETTLE_STATUSES.includes(o0.status)) return { skipped: `status_${o0.status || 'none'}` };
    if (methodOf(o0) !== PAYMENT_METHOD.CARD) return { skipped: 'not_card' };
    if ((o0.outboundSettlement || {}).status === 'settled') return { skipped: 'already_settled' };
    const shipmentId = String((o0.shipment || {}).shipmentId || '');
    const anomaly0 = async (reason, extra) => {
      logError('outboundSettle', { orderId, shipmentId, errorCode: `WHOLESALE_OUTBOUND_${reason.toUpperCase()}`, ...(extra || {}) });
      await markAnomaly(orderId, 'outboundAnomaly', reason);
      return { skipped: reason, anomaly: true };
    };
    if (!shipmentId) return anomaly0('no_shipment');
    const shipRef = db.collection(SHIPMENTS).doc(shipmentId);
    const releaseKey0 = relayReleaseKey(shipmentId);
    const when = now();
    const markSettled = async (patch) => {
      await db.runTransaction(async (t) => {
        const s = await t.get(orderRef);
        const o = s.data() || {};
        if ((o.outboundSettlement || {}).status === 'settled') return;
        const seq = (isInt(o.historySeq) ? o.historySeq : 0) + 1;
        t.update(orderRef, {
          outboundSettlement: { status: 'settled', shipmentId, at: when, ...patch }, outboundAnomaly: null, historySeq: seq, updatedAt: when,
        });
        t.set(orderRef.collection(HISTORY).doc(String(seq)), {
          seq, from: o.status, to: o.status, event: 'outbound_settled', actor: 'system', actorId: null, reason: '', meta: { shipmentId, ...patch }, at: when,
        });
      });
    };
    // Relay o'zi yopgan (masalan keyin baribir «yetkazildi») — pul yozuvi yo'q, faqat belgi.
    if ((await db.collection(settlementLedger.COL_JOURNAL).doc(releaseKey0).get()).exists) {
      await markSettled({ byRelay: true, releaseEntryId: releaseKey0 });
      log('outboundSettle', { orderId, shipmentId, result: 'already_released' });
      return { skipped: 'relay_already_released' };
    }
    const [ss, is] = await Promise.all([shipRef.get(), shipRef.collection(PRIVATE).doc('internal').get()]);
    if (!ss.exists) return anomaly0('shipment_missing');
    const ship = ss.data() || {};
    if (ship.wholesaleOrderId !== orderId || ship.source !== 'wholesale') return anomaly0('shipment_not_wholesale');
    if (ship.paymentStatus !== 'escrow_funded') return anomaly0('outbound_not_funded', { paymentStatus: ship.paymentStatus || null });
    const internal = is.exists ? (is.data() || {}) : {};
    const amount = (ship.priceSnapshot || {}).customerPrice;
    const { platformShare, providerPool } = internal;
    const payouts = Array.isArray(internal.legPayouts) ? internal.legPayouts : [];
    const legIds = Array.isArray(ship.legIds) ? ship.legIds : [];
    if (!isPosInt(amount) || !isInt(platformShare) || platformShare < 0 || !isInt(providerPool) || providerPool < 0
      || platformShare + providerPool !== amount || !legIds.length) {
      return anomaly0('internal_invalid');
    }
    const legSnaps = await Promise.all(legIds.map((id) => db.collection('demands').doc(id).get()));
    const curIdx = legIds.indexOf(ship.currentLegId);
    const earned = [];
    let unearned = 0;
    for (let i = 0; i < legIds.length; i += 1) {
      const p = payouts.find((x) => x && x.index === i) || payouts[i] || {};
      if (!isInt(p.amount) || p.amount < 0) return anomaly0('leg_payout_invalid');
      const leg = legSnaps[i].exists ? (legSnaps[i].data() || {}) : {};
      const provider = canonicalUid((ship.legAssignments || {})[legIds[i]] || (leg.assignment || {}).providerId || '');
      if (i <= curIdx && /^998\d{9}$/.test(provider)) earned.push({ legId: legIds[i], index: i, providerId: provider, amount: p.amount });
      else unearned += p.amount;
    }
    const earnedSum = earned.reduce((s, e) => s + e.amount, 0);
    if (earnedSum + unearned !== providerPool) return anomaly0('leg_payouts_mismatch', { earnedSum, unearned, providerPool });
    const sellerWalletUid = String((o0.payment || {}).payerWalletUid || '');
    if (unearned > 0 && !sellerWalletUid) return anomaly0('seller_wallet_missing');

    try {
      // a) EARNED — relay `postEarned` bilan AYNI yozuv/kalit.
      for (const e of earned) {
        if (e.amount <= 0) continue;
        await settlementLedger.postEntry(db, {
          idempotencyKey: relayEarnedKey(shipmentId, e.legId),
          kind: 'logistics_leg_earned',
          refType: 'shipment',
          refId: shipmentId,
          postedBy: 'system',
          postedRole: 'system',
          legs: [
            { account: RELAY_ACCRUAL_ACCOUNT, dr: e.amount },
            { account: settlementLedger.supplierPayableAccount(e.providerId), cr: e.amount },
          ],
        }, {
          mirrorBonus: false,
          meta: {
            shipmentId, legId: e.legId, providerId: e.providerId, legIndex: e.index, source: 'wholesale_refused', wholesaleOrderId: orderId,
          },
        });
      }
      // b) RELEASE — relay `releaseEscrow` kaliti; eskrou AYNAN 0.
      const legs = [{ account: shipmentEscrowAccount(shipmentId), dr: amount }];
      if (earnedSum > 0) legs.push({ account: RELAY_ACCRUAL_ACCOUNT, cr: earnedSum });
      if (platformShare > 0) legs.push({ account: RELAY_FEE_ACCOUNT, cr: platformShare });
      if (unearned > 0) legs.push({ account: settlementLedger.passengerCreditAccount(sellerWalletUid), cr: unearned });
      const legRefs = legIds.map((id) => db.collection('demands').doc(id));
      const res = await settlementLedger.postEntry(db, {
        idempotencyKey: releaseKey0,
        kind: 'logistics_escrow_release',
        refType: 'shipment',
        refId: shipmentId,
        postedBy: 'system',
        postedRole: 'system',
        legs,
      }, {
        mirrorBonus: false, // sotuvchi ko'zgusi — `mirrorWallet` onCommit'da
        meta: {
          shipmentId, platformShare, providerPool, earned: earnedSum, unearnedRefund: unearned, outcome: 'wholesale_refused', wholesaleOrderId: orderId,
        },
        precheck: async (tx) => {
          const reads = await Promise.all([tx.get(orderRef), tx.get(shipRef), ...legRefs.map((r) => tx.get(r))]);
          const o = reads[0].data() || {};
          const s = reads[1].exists ? (reads[1].data() || {}) : {};
          if (!OUTBOUND_SETTLE_STATUSES.includes(o.status)) throw skipErr(`status_${o.status || 'none'}`);
          if ((o.outboundSettlement || {}).status === 'settled') throw skipErr('already_settled');
          if (String((o.shipment || {}).shipmentId || '') !== shipmentId) throw anomalyErr('shipment_mismatch');
          if (s.paymentStatus !== 'escrow_funded') throw anomalyErr('outbound_not_funded', { paymentStatus: s.paymentStatus || null });
          if (s.currentLegId !== ship.currentLegId) throw skipErr('custody_changed');
          return { o, legs: reads.slice(2).map((x) => (x.exists ? (x.data() || {}) : null)) };
        },
        assert: ({ accounts }) => {
          const e = accounts.get(shipmentEscrowAccount(shipmentId));
          if (!e || e.next !== 0) throw anomalyErr('outbound_escrow_not_zero', { escrowBefore: e ? e.prev : null });
        },
        onCommit: (tx, { pre }) => {
          tx.update(shipRef, {
            paymentStatus: 'settled', settledAt: when, releaseEntryId: releaseKey0,
            wholesaleOutcome: 'refused', wholesaleOutcomeAt: when, updatedAt: when,
          });
          pre.legs.forEach((leg, i) => {
            if (!leg) return;
            const pid = (leg.assignment || {}).providerId || null;
            if (i === curIdx && leg.status === 'in_progress') {
              tx.update(legRefs[i], { status: 'completed', completedAt: when, outcome: 'buyer_refused', updatedAt: when });
              if (pid) {
                tx.set(db.collection('demand_matches').doc(`${legIds[i]}_${pid}`), {
                  status: 'completed', closedAt: when, contactUnlocked: null, outcome: 'buyer_refused',
                }, { merge: true });
              }
            } else if (i > curIdx && ['draft', 'active', 'accepted'].includes(leg.status)) {
              tx.update(legRefs[i], { status: 'cancelled', cancelledBy: 'wholesale_refused', cancelledAt: when, updatedAt: when });
              if (pid) {
                tx.set(db.collection('demand_matches').doc(`${legIds[i]}_${pid}`), {
                  status: 'cancelled', closedAt: when, contactUnlocked: null,
                }, { merge: true });
              }
            }
          });
          if (unearned > 0) {
            mirrorWallet(tx, sellerWalletUid, unearned, 'wholesale_unearned_delivery_refund', orderId, when, { shipmentId });
          }
          const seq = (isInt(pre.o.historySeq) ? pre.o.historySeq : 0) + 1;
          tx.update(orderRef, {
            outboundSettlement: {
              status: 'settled', shipmentId, earned: earnedSum, platformShare, unearnedRefund: unearned,
              earnedLegs: earned.map((e) => ({ legId: e.legId, providerId: e.providerId, amount: e.amount })),
              releaseEntryId: releaseKey0, at: when,
            },
            outboundAnomaly: null,
            historySeq: seq,
            updatedAt: when,
          });
          tx.set(orderRef.collection(HISTORY).doc(String(seq)), {
            seq, from: pre.o.status, to: pre.o.status, event: 'outbound_settled', actor: 'system', actorId: null, reason: '',
            meta: {
              shipmentId, earned: earnedSum, platformShare, unearnedRefund: unearned,
            },
            at: when,
          });
        },
      });
      if (res.idempotent) await markSettled({ byRelay: true, releaseEntryId: releaseKey0 });
      log('outboundSettle', {
        orderId, shipmentId, result: res.idempotent ? 'already' : 'ok', earned: earnedSum, platformShare, unearnedRefund: unearned,
        legs: earned.length, durationMs: Date.now() - started,
      });
      return {
        settled: true, earned: earnedSum, platformShare, unearnedRefund: unearned, idempotent: res.idempotent === true,
      };
    } catch (e) {
      if (e && e.wholesaleSkip) return { skipped: e.reason };
      if (e && e.wholesaleAnomaly) return anomaly0(e.reason, e.extra);
      throw e;
    }
  }

  // ── 3b: QAYTISH — sotuvchi hamyonidan haq (yetmasa qarz), jo'natma to'lanadi, yetganda qoldiq ──
  /**
   * `refused` (AVA ulushi allaqachon qaytarilgan: `refundStatus === done`) + qaytish jo'natmasi
   * bog'langan (demand) → 1) HOLD: Dr passenger_credit:{sotuvchi} / Cr escrow:wholesale_return:{id}
   * (`bonus:wholesaleReturnHold:{id}`) — balans yetmasa MANFIYGA TUSHMAYDI: `returnDebt` +
   * `wholesale_seller_stats/{sotuvchi}` (`cardBlocked`, `debtOrderIds`); 2) FUND: Dr
   * escrow:wholesale_return:{id} / Cr escrow:{qaytishShipmentId} (`wholesaleReturnFund:{id}`) +
   * jo'natma `escrow_funded`/`ready` + buyurtma refused → returning (+ qarz yopiladi, blok yechiladi).
   * Har qadam idempotent; ikkisi orasida yiqilsa — reconcile davom ettiradi.
   */
  async function fundReturn(orderId) {
    const started = Date.now();
    const orderRef = db.collection(ORDERS).doc(orderId);
    const s0 = await orderRef.get();
    if (!s0.exists) return { skipped: 'order_missing' };
    const o0 = s0.data() || {};
    if (o0.status !== STATUS.REFUSED) return { skipped: `status_${o0.status || 'none'}` };
    if (methodOf(o0) !== PAYMENT_METHOD.CARD) return { skipped: 'not_card' };
    if (o0.refundStatus !== REFUND_STATUS.DONE) return { skipped: 'refund_pending' };
    const rs = o0.returnShipment || {};
    const returnShipmentId = String(rs.shipmentId || '');
    if (!returnShipmentId) return { skipped: 'no_return_shipment' };
    if ((o0.returnPayment || {}).status === 'funded') return { skipped: 'already_funded' };
    const fee = rs.fee;
    const anomaly0 = async (reason) => {
      logError('returnFund', { orderId, returnShipmentId, errorCode: `WHOLESALE_RETURN_${reason.toUpperCase()}` });
      await markAnomaly(orderId, 'returnAnomaly', reason);
      return { skipped: reason, anomaly: true };
    };
    if (!isPosInt(fee)) return anomaly0('fee_invalid');
    const sellerKey = canonicalUid(o0.sellerId || '');
    const sellerWalletUid = /^998\d{9}$/.test(sellerKey) ? await walletUidOf(sellerKey) : null;
    if (!sellerWalletUid) return anomaly0('seller_wallet_missing');
    const statsRef = db.collection(SELLER_STATS).doc(sellerKey);
    const shipRef = db.collection(SHIPMENTS).doc(returnShipmentId);
    const holdEsc = returnEscrowAccount(orderId);
    const when = now();

    // 1) HOLD (yoki qarz).
    const h = await db.runTransaction(async (t) => {
      const [os, ss] = await Promise.all([t.get(orderRef), t.get(statsRef)]);
      const o = os.data() || {};
      if (o.status !== STATUS.REFUSED) return { skip: `status_${o.status || 'none'}` };
      if (String((o.returnShipment || {}).shipmentId || '') !== returnShipmentId) return { skip: 'return_shipment_changed' };
      const ledger = await settlementLedger.prepareBonusInTx(t, db, sellerWalletUid, {
        fundingAccount: holdEsc, idempotencyKey: returnHoldKey(orderId),
      });
      if (ledger.jExists) return { held: true, already: true };
      if (ledger.pcPrev < fee) {
        const prev = o.returnDebt || null;
        const attempts = (prev && isInt(prev.attempts) ? prev.attempts : 0) + 1;
        t.update(orderRef, {
          returnDebt: { amount: fee, at: (prev && prev.at) || when, attempts, lastTriedAt: when },
          returnStatus: RETURN_STATUS.AWAITING_PAYMENT,
          updatedAt: when,
        });
        const st = ss.exists ? (ss.data() || {}) : {};
        const ids = Array.isArray(st.debtOrderIds) ? st.debtOrderIds : [];
        t.set(statsRef, {
          sellerId: sellerKey,
          cardBlocked: true,
          debtOrderIds: ids.includes(orderId) ? ids : [...ids, orderId],
          updatedAt: when,
        }, { merge: true });
        return { debt: true, attempts, first: !prev };
      }
      settlementLedger.commitBonusInTx(t, ledger, {
        delta: -fee,
        kind: 'wholesale_return_hold',
        refType: 'wholesale_order',
        refId: orderId,
        meta: { module: 'wholesale', returnShipmentId, payer: 'seller' },
        postedBy: 'system',
        postedRole: 'system',
      });
      mirrorWallet(t, sellerWalletUid, -fee, 'wholesale_return_hold', orderId, when, { returnShipmentId });
      t.update(orderRef, {
        returnPayment: {
          status: 'held',
          amount: fee,
          payer: 'seller',
          payerWalletUid: sellerWalletUid,
          heldAt: when,
          escrowAccount: holdEsc,
          holdEntryId: `bonus:${returnHoldKey(orderId)}`,
        },
        updatedAt: when,
      });
      return { held: true };
    });
    if (h.skip) return { skipped: h.skip };
    if (h.debt) {
      log('returnFund', { orderId, returnShipmentId, result: 'debt', amount: fee, attempts: h.attempts, durationMs: Date.now() - started });
      if (h.first) logError('returnFund', { orderId, returnShipmentId, errorCode: 'WHOLESALE_RETURN_SELLER_DEBT', amount: fee });
      return { debt: true, amount: fee, attempts: h.attempts };
    }

    // 2) FUND → relay eskrou + jo'natma to'landi + refused → returning.
    const key = returnFundKey(orderId);
    try {
      const res = await settlementLedger.postEntry(db, {
        idempotencyKey: key,
        kind: 'wholesale_return_fund',
        refType: 'wholesale_order',
        refId: orderId,
        postedBy: 'system',
        postedRole: 'system',
        legs: [{ account: holdEsc, dr: fee }, { account: shipmentEscrowAccount(returnShipmentId), cr: fee }],
      }, {
        mirrorBonus: false,
        meta: { module: 'wholesale', returnShipmentId, fee },
        precheck: async (tx) => {
          const [os, ss, sts] = await Promise.all([tx.get(orderRef), tx.get(shipRef), tx.get(statsRef)]);
          const o = os.data() || {};
          if (o.status !== STATUS.REFUSED) throw skipErr(`status_${o.status || 'none'}`);
          if (String((o.returnShipment || {}).shipmentId || '') !== returnShipmentId) throw anomalyErr('return_shipment_changed');
          if (!ss.exists) throw anomalyErr('return_shipment_missing');
          const s = ss.data() || {};
          if (s.source !== RETURN_SOURCE || s.wholesaleOrderId !== orderId) throw anomalyErr('shipment_not_return');
          if (s.status !== 'awaiting_payment' || s.paymentStatus !== 'pending') {
            throw anomalyErr('return_shipment_not_payable', { status: s.status || null, paymentStatus: s.paymentStatus || null });
          }
          if ((s.priceSnapshot || {}).customerPrice !== fee) throw anomalyErr('return_fee_mismatch');
          return { o, stats: sts.exists ? (sts.data() || {}) : {} };
        },
        assert: ({ accounts }) => {
          const e = accounts.get(holdEsc);
          if (!e || e.next !== 0) throw anomalyErr('return_escrow_not_exact', { escrow: e ? e.prev : null });
        },
        onCommit: (tx, { pre }) => {
          tx.update(shipRef, {
            paymentStatus: 'escrow_funded', status: 'ready', fundedAt: when,
            escrowEntryId: key, escrowAmount: fee, updatedAt: when,
          });
          const seq = (isInt(pre.o.historySeq) ? pre.o.historySeq : 0) + 1;
          const hadDebt = !!pre.o.returnDebt;
          tx.update(orderRef, {
            status: STATUS.RETURNING,
            statusUpdatedAt: when,
            updatedAt: when,
            historySeq: seq,
            returnStatus: RETURN_STATUS.IN_TRANSIT,
            'returnPayment.status': 'funded',
            'returnPayment.fundedAt': when,
            'returnPayment.fundEntryId': key,
            returnDebt: null,
            returnDebtSettledAt: hadDebt ? when : null,
            returnAnomaly: null,
          });
          tx.set(orderRef.collection(HISTORY).doc(String(seq)), {
            seq, from: STATUS.REFUSED, to: STATUS.RETURNING, event: 'return_funded', actor: 'system', actorId: null,
            reason: '', meta: { returnShipmentId, fee, debtSettled: hadDebt }, at: when,
          });
          const ids = Array.isArray(pre.stats.debtOrderIds) ? pre.stats.debtOrderIds : [];
          if (ids.includes(orderId) || pre.stats.cardBlocked === true) {
            const rest = ids.filter((x) => x !== orderId);
            tx.set(statsRef, {
              sellerId: sellerKey, debtOrderIds: rest, cardBlocked: rest.length > 0, updatedAt: when,
            }, { merge: true });
          }
        },
      });
      log('returnFund', {
        orderId, returnShipmentId, result: res.idempotent ? 'already' : 'ok', amount: fee, durationMs: Date.now() - started,
      });
      return { funded: fee, returnShipmentId, idempotent: res.idempotent === true };
    } catch (e) {
      if (e && e.wholesaleSkip) return { skipped: e.reason };
      if (e && e.wholesaleAnomaly) {
        logError('returnFund', { orderId, returnShipmentId, errorCode: `WHOLESALE_RETURN_${e.reason.toUpperCase()}`, ...e.extra });
        await markAnomaly(orderId, 'returnAnomaly', e.reason);
        return { skipped: e.reason, anomaly: true };
      }
      throw e;
    }
  }

  /**
   * Qaytish jo'natmasi sotuvchiga yetdi (custody `deliversShipment`, relay `confirmDelivery`):
   * returning → returned + qoldiq +N (FAQAT shu yerda — ega, 2026-10-31). Pul yo'q (relay o'z
   * RELEASE'ida escrow:{qaytishShipmentId} ni kuryerga yopadi). Idempotent (holat tranzaksiyada).
   */
  async function completeReturn(orderId, returnShipmentId) {
    const started = Date.now();
    const orderRef = db.collection(ORDERS).doc(orderId);
    const shipRef = db.collection(SHIPMENTS).doc(returnShipmentId);
    const when = now();
    const out = await db.runTransaction(async (t) => {
      const [os, ss] = await Promise.all([t.get(orderRef), t.get(shipRef)]);
      if (!os.exists) return { skipped: 'order_missing' };
      const o = os.data() || {};
      if (o.status === STATUS.RETURNED) return { skipped: 'already_returned' };
      if (o.status !== STATUS.RETURNING) return { skipped: `status_${o.status || 'none'}` };
      if (String((o.returnShipment || {}).shipmentId || '') !== returnShipmentId) return { skipped: 'return_shipment_mismatch', anomaly: true };
      const s = ss.exists ? (ss.data() || {}) : {};
      if (s.source !== RETURN_SOURCE || s.wholesaleOrderId !== orderId) return { skipped: 'shipment_not_return', anomaly: true };
      if (!isShipmentDelivered(s)) return { skipped: `shipment_${s.status || 'none'}` };
      const { so, restore } = stockToRestore(o);
      const stockRef = db.collection(STOCK).doc(String(o.productId || ''));
      const sSnap = restore ? await t.get(stockRef) : null;
      if (restore) writeStockRestore(t, stockRef, sSnap, { ...o, __id: orderId }, so, when, 'order_return');
      const seq = (isInt(o.historySeq) ? o.historySeq : 0) + 1;
      t.update(orderRef, {
        status: STATUS.RETURNED,
        returnedAt: when,
        statusUpdatedAt: when,
        updatedAt: when,
        historySeq: seq,
        returnStatus: RETURN_STATUS.RETURNED,
        'stock.restored': restore || so.restored === true,
        'stock.restoredAt': restore ? when : (so.restoredAt || null),
      });
      t.set(orderRef.collection(HISTORY).doc(String(seq)), {
        seq, from: STATUS.RETURNING, to: STATUS.RETURNED, event: 'goods_returned', actor: 'system', actorId: null,
        reason: '', meta: { returnShipmentId, stockRestored: restore }, at: when,
      });
      return { returned: true, stockRestored: restore };
    });
    if (out.anomaly) logError('completeReturn', { orderId, returnShipmentId, errorCode: `WHOLESALE_RETURN_${out.skipped.toUpperCase()}` });
    else log('completeReturn', { orderId, returnShipmentId, result: out.returned ? 'ok' : 'skipped', skipped: out.skipped || null, durationMs: Date.now() - started });
    return out;
  }

  /**
   * Jo'natma yetkazilgan (`deliversShipment` custody hodisasi) va Ulgurji buyurtmasiniki
   * bo'lsa — tovar puli. Oddiy jo'natma — tegmaydi. Relay o'z RELEASE'ini o'zining
   * `onLogisticsCustodyEvent` triggerida qiladi (bu yerdan mustaqil, boshqa eskrou).
   * 3b: QAYTISH jo'natmasi (`source: wholesale_return`) — `completeReturn` (pulsiz).
   */
  async function onShipmentDelivered(shipmentId) {
    const s = await db.collection(SHIPMENTS).doc(String(shipmentId || '')).get();
    if (!s.exists) return { skipped: 'shipment_missing' };
    const ship = s.data() || {};
    const orderId = typeof ship.wholesaleOrderId === 'string' ? ship.wholesaleOrderId : '';
    if (!orderId) return { skipped: 'not_wholesale' };
    if (!isShipmentDelivered(ship)) return { skipped: `shipment_${ship.status || 'none'}` };
    if (ship.source === RETURN_SOURCE) return completeReturn(orderId, String(shipmentId));
    return releaseGoods(orderId);
  }

  /**
   * `custody_events/{id}` onCreate (alohida trigger — relay `onLogisticsCustodyEvent`
   * O'ZGARMAYDI). Faqat `deliversShipment === true`; qolgan hodisalar o'qishsiz o'tadi.
   * Yiqilsa — `wholesaleOrdersReconcile` qayta urinadi (idempotent `wholesaleRelease:{id}`).
   */
  async function onCustodyEvent(event) {
    const ev = event || {};
    if (ev.deliversShipment !== true || !ev.shipmentId) return { skipped: 'not_delivery' };
    try {
      return await onShipmentDelivered(String(ev.shipmentId));
    } catch (e) {
      logError('release', {
        shipmentId: String(ev.shipmentId), errorCode: 'WHOLESALE_RELEASE_FAILED',
        message: String((e && e.message) || e).slice(0, 200),
      });
      return { skipped: 'failed' };
    }
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
    // 3b: rad etilgan karta buyurtmasi — AVA ulushi qaytgach, CHIQISH jo'natmasini relay kalitlari bilan
    // yopish (kuryer haqi kuryerlarga). Anomaliya belgisi bo'lsa trigger qayta urinmaydi (reconcile).
    if (OUTBOUND_SETTLE_STATUSES.includes(a.status) && methodOf(a) === PAYMENT_METHOD.CARD
      && a.refundStatus === REFUND_STATUS.DONE && (a.shipment || {}).shipmentId
      && (a.outboundSettlement || {}).status !== 'settled' && !a.outboundAnomaly) {
      try {
        return await settleOutboundOnRefusal(orderId);
      } catch (e) {
        logError('outboundSettle', { orderId, errorCode: 'WHOLESALE_OUTBOUND_SETTLE_FAILED', message: String((e && e.message) || e).slice(0, 200) });
        return { skipped: 'failed' };
      }
    }
    // 3b: rad etilgan karta buyurtmasi — AVA ulushi qaytgach + qaytish jo'natmasi bog'langach →
    // sotuvchi hamyonidan qaytish haqi. `returnDebt` / `returnAnomaly` bo'lsa trigger qayta
    // URINMAYDI (belgi yozuvi triggerni yana chaqiradi — aylanish bo'lmasin); qayta urinish — reconcile.
    if (a.status === STATUS.REFUSED && a.refundStatus === REFUND_STATUS.DONE
      && (a.returnShipment || {}).shipmentId && (a.returnPayment || {}).status !== 'funded'
      && !a.returnDebt && !a.returnAnomaly) {
      try {
        return await fundReturn(orderId);
      } catch (e) {
        logError('returnFund', { orderId, errorCode: 'WHOLESALE_RETURN_FUND_FAILED', message: String((e && e.message) || e).slice(0, 200) });
        return { skipped: 'failed' };
      }
    }
    if (!REFUND_STATUSES.includes(a.status) || a.refundStatus !== REFUND_STATUS.PENDING) {
      return { skipped: 'no_refund_needed' };
    }
    try {
      return await refundOrder(orderId);
    } catch (e) {
      // Reconcile (har 10 daqiqa) qayta urinadi; har qadam idempotent.
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
    // D) 3b: rad etilgan karta buyurtmasi — qaytish haqi (qarz bo'lsa HAR aylanishda, ya'ni
    //    sotuvchi hamyonni to'ldirgach; aks holda trigger yiqilgan bo'lsa, 10 daqiqadan keyin).
    out.returnFundChecked = 0; out.returnFunded = 0; out.returnDebts = 0;
    out.outboundChecked = 0; out.outboundSettled = 0;
    // Chiqish jo'natmasi yopilmagan rad etilgan / qaytayotgan buyurtmalar (trigger yiqilgan).
    const needOutbound = (o) => methodOf(o) === PAYMENT_METHOD.CARD && o.refundStatus === REFUND_STATUS.DONE
      && (o.shipment || {}).shipmentId && (o.outboundSettlement || {}).status !== 'settled' && !o.outboundAnomaly
      && nowMs - (msOf(o.refundedAt) || msOf(o.updatedAt) || 0) >= minAgeMs;
    const settleOut = async (d) => {
      out.outboundChecked += 1;
      try {
        const r = await settleOutboundOnRefusal(d.id);
        if (r && r.settled && !r.idempotent) out.outboundSettled += 1;
      } catch (e) {
        out.failed += 1;
        logError('reconcile', { orderId: d.id, errorCode: 'WHOLESALE_RECONCILE_OUTBOUND_FAILED', message: String((e && e.message) || e).slice(0, 200) });
      }
    };
    const refused = await db.collection(ORDERS).where('status', '==', STATUS.REFUSED).limit(limit).get();
    for (const d of refused.docs) {
      const o = d.data() || {};
      if (needOutbound(o)) await settleOut(d);
      const rs = o.returnShipment || {};
      if (o.refundStatus !== REFUND_STATUS.DONE || !rs.shipmentId || (o.returnPayment || {}).status === 'funded') continue;
      if (o.returnAnomaly) continue; // admin ko'radi (pul o'ylab topilmaydi)
      if (!o.returnDebt && nowMs - (msOf(rs.createdAt) || msOf(o.updatedAt) || 0) < minAgeMs) continue;
      out.returnFundChecked += 1;
      try {
        const r = await fundReturn(d.id);
        if (r && r.funded && !r.idempotent) out.returnFunded += 1;
        else if (r && r.debt) out.returnDebts += 1;
      } catch (e) {
        out.failed += 1;
        logError('reconcile', { orderId: d.id, errorCode: 'WHOLESALE_RECONCILE_RETURN_FUND_FAILED', message: String((e && e.message) || e).slice(0, 200) });
      }
    }
    // E) 3b: qaytish jo'natmasi yetkazilgan, buyurtma hali `returning` → returned + qoldiq.
    out.returnChecked = 0; out.returned = 0;
    const returning = await db.collection(ORDERS).where('status', '==', STATUS.RETURNING).limit(limit).get();
    for (const d of returning.docs) {
      const o = d.data() || {};
      if (needOutbound(o)) await settleOut(d);
      const rsId = String((o.returnShipment || {}).shipmentId || '');
      if (!rsId) continue;
      try {
        const s = await db.collection(SHIPMENTS).doc(rsId).get();
        const ship = s.exists ? (s.data() || {}) : {};
        if (!isShipmentDelivered(ship)) continue;
        if (nowMs - (msOf(ship.deliveredAt) || msOf(ship.updatedAt) || 0) < minAgeMs) continue;
        out.returnChecked += 1;
        const r = await completeReturn(d.id, rsId);
        if (r && r.returned) out.returned += 1;
      } catch (e) {
        out.failed += 1;
        logError('reconcile', { orderId: d.id, errorCode: 'WHOLESALE_RECONCILE_RETURN_FAILED', message: String((e && e.message) || e).slice(0, 200) });
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
  exportsObj.onWholesaleCustodyEvent = functions.firestore
    .document('custody_events/{eventId}')
    .onCreate(async (snap) => { await onCustodyEvent(snap.data() || {}); return null; });
  // 3b: har 10 daqiqa (ega, 2026-10-31: qaytish qarzi hamyon to'ldirilgach 10 daqiqada yopilsin).
  exportsObj.wholesaleOrdersReconcile = functions.pubsub
    .schedule('every 10 minutes')
    .onRun(async () => { await reconcile(); return null; });

  return {
    place, refundOrder, onStatusChange, reconcile, shipFund, releaseGoods, onShipmentDelivered, onCustodyEvent,
    fundReturn, completeReturn, settleOutboundOnRefusal,
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
  refusedKey,
  returnHoldKey,
  returnFundKey,
  returnEscrowAccount,
  relayEarnedKey,
  relayReleaseKey,
  RELAY_ACCRUAL_ACCOUNT,
  RELAY_FEE_ACCOUNT,
  PAYMENT_METHOD,
  CARD_PAYMENT,
  CARD_REFUSAL_LIMIT,
  RETURN_STATUS,
  HELD_STATUSES,
  RETURN_SOURCE,
  methodOf,
  quoteAmountsOk,
  attachWholesaleOrders,
};
