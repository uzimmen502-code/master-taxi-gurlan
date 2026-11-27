/**
 * Ulgurji karta buyurtmasi → HAQIQIY relay jo'natmasi → oxirgi LEG kuryeri posilkani oldi.
 * FakeFirestore (`makeDb`) va Emulator (Admin SDK) uchun BIR XIL (faqat `db.collection` API).
 * `wholesale_return.test.js` dagi `flow()` bilan bir xil qadamlar (o'sha relay callable'lari).
 */
'use strict';
const api = require('../../api/logistics');
const W = require('../../api/wholesale_orders');
const tariffCore = require('../../core/tariff');
const config = require('../../core/config');
const {
  K1, NOW, ctx, seed, deps, PHOTO,
} = require('./logistics_harness');

const BUYER = '998905556677';
const SELLER = '998901234567';
const STRANGER = '998907770007';
const ADMIN = '998909990000'; // harness seed: role admin
const SUPER = '998906660000';
const DISP = '998908880000';
const ORDER_ID = 'wo1';

const ORIGIN = {
  regionId: 'xorazm', districtId: 'gurlan', lat: 41.84, lng: 60.39, geohash: 'tp5my0b', addressText: 'Gurlan, Markaz 1',
};
const DEST = {
  regionId: 'xorazm', districtId: 'gurlan', lat: 41.85, lng: 60.40, geohash: 'tp5my2c', addressText: 'Gurlan, Bog\'cha 5',
};

function seedW(extra = {}) {
  config.clearCache();
  tariffCore.clearCache();
  return seed({
    [`users/${BUYER}`]: { name: 'Bobur', fcmToken: 'tokB', appLang: 'uz_Latn' },
    [`users/${SELLER}`]: { name: 'Sotuvchi', fcmToken: 'tokS' },
    [`users/${K1}`]: { accountId: `acc${K1}`, fcmToken: 'tokK1', appLang: 'ru' },
    [`users/${SUPER}`]: { role: 'superadmin' },
    [`users/${DISP}`]: { role: 'dispatcher' },
    ...extra,
  });
}

async function orderDoc(db, extra = {}) {
  const t = (await db.collection('module_tariffs').doc('logistics_v7').get()).data();
  const snap = tariffCore.quoteParcel(t, { actualWeightG: 800, declaredValue: 140000 }, ORIGIN, DEST, { dimsOptional: true });
  const fee = snap.customerPrice;
  return {
    buyerId: BUYER,
    buyerWalletUid: BUYER,
    sellerId: SELLER,
    productId: 'rice',
    productTitle: 'Guruch',
    packId: 'p1',
    packLabel: '1 kg',
    qty: 10,
    unitPrice: 14000,
    goodsTotal: 140000,
    deliveryFee: fee,
    total: 140000 + fee,
    currency: 'UZS',
    delivery: {
      tariffVersion: snap.tariffVersion, zone: snap.zone, actualWeightG: 800, chargeableWeightG: snap.chargeableWeightG, dims: null, priceSnapshot: snap,
    },
    origin: ORIGIN,
    destination: DEST,
    quoteId: 'q1',
    status: 'placed',
    historySeq: 1,
    paymentMethod: 'card_on_delivery',
    payment: { status: 'held_seller', amount: fee + 3500, payer: 'seller', payerWalletUid: SELLER },
    cardPayment: { status: 'awaiting', confirmedAt: null },
    stock: { packId: 'p1', qty: 10, decremented: true, restored: false },
    shipment: null,
    refundStatus: null,
    createdAt: NOW,
    updatedAt: NOW,
    statusUpdatedAt: NOW,
    ...extra,
  };
}

// Parallel / ichma-ich chaqiruvda ham console ASL holiga qaytadi: asl funksiyalar faqat birinchi
// (tashqi) chaqiruvda saqlanadi, oxirgisi tugaganda tiklanadi (avval ikkinchi chaqiruv «jim»ni asl
// deb saqlab, console.log'ni butunlay yutib yuborardi).
let quietDepth = 0;
let savedConsole = null;
const quiet = async (fn) => {
  if (quietDepth === 0) {
    savedConsole = { error: console.error, log: console.log };
    console.error = () => {}; console.log = () => {};
  }
  quietDepth += 1;
  try { return await fn(); } finally {
    quietDepth -= 1;
    if (quietDepth === 0 && savedConsole) {
      console.error = savedConsole.error; console.log = savedConsole.log;
      savedConsole = null;
    }
  }
};

/** `db` allaqachon `seedW()` bilan to'ldirilgan. Qaytaradi {shipmentId, legId}. */
async function flow(db, { scan = true, extraOrder = {}, orderId = ORDER_ID } = {}) {
  await db.collection('wholesale_orders').doc(orderId).set(await orderDoc(db, extraOrder));
  const d = deps(db);
  const r = await quiet(() => W.ensureWholesaleShipment(d, orderId));
  const shipmentId = r.shipmentId;
  const ref = db.collection('shipments').doc(shipmentId);
  const before = (await ref.get()).data();
  const legId = before.legIds[0];
  await ref.update({ paymentStatus: 'escrow_funded', status: 'ready', fundedAt: NOW });
  await db.collection('wholesale_orders').doc(orderId).update({ status: 'in_delivery', 'payment.deliveryFunded': true, historySeq: 3 });
  await quiet(async () => api.makeOnShipmentFunded(d)(before, (await ref.get()).data(), shipmentId));
  await api.makeAcceptLeg(d)({ legId }, ctx(K1));
  if (scan) {
    const sec = await api.makeGetShipmentSecrets(d)({ shipmentId }, ctx(SELLER));
    await api.makeScanHandover(d)({ legId, code: sec.handoverCode, photoUrls: PHOTO }, ctx(K1));
  }
  return { shipmentId, legId };
}

module.exports = {
  BUYER, SELLER, STRANGER, ADMIN, SUPER, DISP, ORDER_ID, ORIGIN, DEST, K1, NOW, ctx, seedW, orderDoc, flow, quiet,
};
