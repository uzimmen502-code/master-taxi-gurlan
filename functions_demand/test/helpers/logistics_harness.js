/**
 * AVA Logistics testlari uchun umumiy harness (FakeFirestore + seed + oqim).
 *
 * `logistics_api.test.js` va `logistics_parity.test.js` AYNI shu seed va
 * payload'ni ishlatadi — paritet fixturasi (`fixtures/logistics_parity.json`)
 * shu oqimdan yoziladi, shuning uchun server hujjat shakli bitta joyda.
 */
const path = require('path');
const fs = require('fs');
const { FakeFirestore } = require('../fake_firestore');
const api = require('../../api/logistics');
const kw = require('../../core/keywords');
const taxonomy = require('../../core/seed/taxonomy_services.json');

const fixture = JSON.parse(fs.readFileSync(
  path.join(__dirname, '..', 'fixtures', 'logistics_tariff_test.json'), 'utf8',
));
const keywordIndex = kw.buildIndex(taxonomy);

const OWNER = '998901110001';
const K1 = '998902220002'; // kuryer, posilka oladi, Gurlan
const K2 = '998903330003'; // kuryer, posilka OLMAYDI
const F1 = '998904440004'; // yuk tashuvchi, Xorazm + Toshkent
const ADMIN = '998909990000';
const NOW = new Date('2026-10-06T21:30:00Z'); // Toshkent: 07.10 02:30
const ctx = (phone) => ({ auth: { token: { phone_number: `+${phone}` } } });

function makeDb(seedDocs) {
  const db = new FakeFirestore(seedDocs);
  db.runTransaction = async (fn) => {
    const tx = {
      get: (ref) => ref.get(),
      set: (ref, data, opts) => { tx._ops.push(() => ref.set(data, opts)); },
      update: (ref, data) => { tx._ops.push(() => ref.update(data)); },
      delete: (ref) => { tx._ops.push(() => ref.delete()); },
      _ops: [],
    };
    const out = await fn(tx);
    for (const op of tx._ops) await op();
    return out;
  };
  return db;
}

function capDoc(uid, service, svc, status) {
  return {
    identity: { accountId: `acc${uid}`, primaryUid: uid },
    [service]: svc,
    status: { [service]: status },
  };
}

function seed(extra = {}) {
  return {
    'module_config/global': { enabled: true, matchingEnabled: true, pushEnabled: true },
    // Hududsiz konfig (`CONFIG_REGION = 'all'`): logistika hududlararo.
    'module_config/logistics_all': { enabled: true, matchingEnabled: true, pushEnabled: false },
    'geo_regions/xorazm': { name: 'Xorazm' },
    'geo_regions/toshkent_shahri': { name: 'Toshkent' },
    'geo_districts/gurlan': { regionId: 'xorazm' },
    'geo_districts/urganch_shahri': { regionId: 'xorazm' },
    'geo_districts/chilonzor': { regionId: 'toshkent_shahri' },
    'module_tariffs/logistics': { activeVersion: 7 },
    'module_tariffs/logistics_v7': fixture.tariff,
    [`users/${OWNER}`]: { regionId: 'xorazm', districtId: 'gurlan' },
    [`users/${ADMIN}`]: { role: 'admin' },
    [`provider_capabilities/acc${K1}`]: capDoc(K1, 'courier', {
      active: true, regionIds: ['xorazm'], districtIds: ['gurlan'], acceptsParcels: true,
    }, 'approved'),
    [`provider_capabilities/acc${K2}`]: capDoc(K2, 'courier', {
      active: true, regionIds: ['xorazm'], districtIds: ['gurlan'], acceptsParcels: false,
    }, 'approved'),
    [`provider_capabilities/acc${F1}`]: capDoc(F1, 'freight', {
      active: true, regionIds: ['xorazm', 'toshkent_shahri'], districtIds: [],
    }, 'enabled'),
    ...extra,
  };
}

function orderPayload(over = {}) {
  return {
    clientRequestId: 'req-logistics-0001',
    origin: { regionId: 'xorazm', districtId: 'gurlan', lat: 41.84, lng: 60.39, addressText: 'Gurlan, Markaz 1' },
    destination: { regionId: 'xorazm', districtId: 'gurlan', lat: 41.85, lng: 60.40, addressText: 'Gurlan, Bog\'cha 5' },
    parcels: [{ actualWeightG: 800, lengthCm: 20, widthCm: 15, heightCm: 10, description: 'Kitoblar' }],
    recipient: { name: 'Olim aka', phone: '+998905556677' },
    termsAcceptedAt: '2026-10-06T21:00:00Z',
    ...over,
  };
}

function deps(db, now = NOW) {
  return { db, keywordIndex, notify: null, now: () => now };
}

/** Eskrouni default codebase yozadi — testda shu yozuv simulyatsiya qilinadi. */
async function fund(db, shipmentId) {
  const ref = db.collection('shipments').doc(shipmentId);
  const before = (await ref.get()).data();
  await ref.update({ paymentStatus: 'escrow_funded', status: 'ready', fundedAt: NOW });
  const after = (await ref.get()).data();
  return api.makeOnShipmentFunded(deps(db))(before, after, shipmentId);
}

const PHOTO = ['https://r2.example/handover1.jpg'];
const legOf = (db, shipmentId) => db.dump('shipments')[shipmentId].legIds;

module.exports = {
  fixture, keywordIndex, OWNER, K1, K2, F1, ADMIN, NOW, ctx,
  makeDb, capDoc, seed, orderPayload, deps, fund, PHOTO, legOf,
};
