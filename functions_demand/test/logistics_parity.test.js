/**
 * AVA Logistics — SERVER ↔ ILOVA PARITET TESTI.
 *
 *   node functions_demand/test/logistics_parity.test.js            # tekshiradi
 *   node functions_demand/test/logistics_parity.test.js --update   # fixture `docs`ni qayta yozadi
 *
 * Juftligi: `test/features/logistics/logistics_parity_test.dart`.
 * Ikkisi AYNI fixturani o'qiydi: `fixtures/logistics_parity.json`.
 *
 * Qulflanadi:
 *   1) enum satrlari (shipment/payment/order status, custodian, holat
 *      belgilari, LEG turlari, tracking shakli, QR prefiksi);
 *   2) callable `details.reason` kodlari — api/logistics.js, core/tariff.js
 *      va functions/relay_escrow.js manbasidan o'qiladi va fixture bilan
 *      IKKI tomonlama solishtiriladi (ilova matn tanlash uchun ishlatadi);
 *   3) hujjat shakli — to'liq oqim FakeFirestore'da yuritiladi va
 *      `docs` bo'limi bilan kalit-ma-kalit solishtiriladi (`--update`
 *      fixture'ni serverdan qayta yozadi; Dart modeli o'sha hujjatni o'qiydi).
 */
const assert = require('assert');
const path = require('path');
const fs = require('fs');
const L = require('../core/logistics');
const tariff = require('../core/tariff');
const api = require('../api/logistics');
const config = require('../core/config');
const H = require('./helpers/logistics_harness');

const FIXTURE = path.join(__dirname, 'fixtures', 'logistics_parity.json');
const UPDATE = process.argv.includes('--update');
const fx = JSON.parse(fs.readFileSync(FIXTURE, 'utf8'));

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

// ── 1. ENUM SATRLARI ───────────────────────────────────────────────────
ok('shipment statuslari fixture bilan bir xil', () => {
  assert.deepStrictEqual(Object.values(L.SHIPMENT_STATUS).sort(), [...fx.shipmentStatuses].sort());
});
ok('to\'lov statuslari fixture bilan bir xil', () => {
  assert.deepStrictEqual(Object.values(L.PAYMENT_STATUS).sort(), [...fx.paymentStatuses].sort());
});
ok('custodian turlari, holat belgilari, LEG turlari', () => {
  assert.deepStrictEqual(Object.values(L.CUSTODIAN_KIND).sort(), [...fx.custodianKinds].sort());
  assert.deepStrictEqual([...L.CONDITION_FLAGS].sort(), [...fx.conditionFlags].sort());
  assert.deepStrictEqual([...tariff.LEG_KINDS].sort(), [...fx.legKinds].sort());
});
ok('order statuslari — deriveOrderStatus faqat fixture qiymatlarini qaytaradi', () => {
  const S = Object.values(L.SHIPMENT_STATUS);
  const seen = new Set([L.deriveOrderStatus([])]);
  for (const a of S) for (const b of S) seen.add(L.deriveOrderStatus([a, b]));
  for (const s of seen) assert.ok(fx.orderStatuses.includes(s), `fixture'da yo'q: ${s}`);
});
ok('tracking shakli va QR prefiksi', () => {
  assert.strictEqual(L.TRACKING_RE.source, new RegExp(fx.trackingPattern).source);
  assert.ok(L.qrPayloadFor('x', 'y').startsWith(fx.qrPrefix));
});

// ── 2. REASON KODLARI (manbadan) ───────────────────────────────────────
/**
 * `fnName(` chaqiruvlarining argumentlarini qavs/qo'shtirnoq hisobga olib
 * ajratadi (xabar ternary yoki o'zgaruvchi bo'lishi mumkin — regex yetmaydi).
 */
function callArgs(src, fnName) {
  const calls = [];
  const re = new RegExp(`\\b${fnName}\\(`, 'g');
  let m;
  while ((m = re.exec(src)) !== null) {
    let depth = 1; let q = null; let cur = ''; const args = [];
    for (let i = m.index + m[0].length; i < src.length && depth > 0; i += 1) {
      const ch = src[i];
      if (q) {
        cur += ch;
        if (ch === '\\') { i += 1; cur += src[i]; } else if (ch === q) q = null;
        continue;
      }
      if (ch === '\'' || ch === '"' || ch === '`') { q = ch; cur += ch; continue; }
      if ('([{'.includes(ch)) { depth += 1; cur += ch; continue; }
      if (')]}'.includes(ch)) { depth -= 1; if (depth === 0) break; cur += ch; continue; }
      if (ch === ',' && depth === 1) { args.push(cur.trim()); cur = ''; continue; }
      cur += ch;
    }
    if (cur.trim()) args.push(cur.trim());
    calls.push(args);
  }
  return calls;
}
function reasonsIn(file, fnName) {
  const out = new Set();
  for (const args of callArgs(fs.readFileSync(file, 'utf8'), fnName)) {
    const r = /^'([a-z_]+)'$/.exec(args[2] || '');
    if (r) out.add(r[1]);
  }
  return out;
}
function escrowReasons() {
  const src = fs.readFileSync(path.join(__dirname, '..', '..', 'functions', 'relay_escrow.js'), 'utf8');
  const out = new Set();
  const re = /reason: '([a-z_]+)'/g;
  let m;
  while ((m = re.exec(src)) !== null) out.add(m[1]);
  return out;
}
ok('callable `reason` kodlari: api + tarif + eskrou manbasi == fixture (ikki tomonlama)', () => {
  const fromSrc = new Set([
    ...reasonsIn(path.join(__dirname, '..', 'api', 'logistics.js'), 'fail'),
    ...reasonsIn(path.join(__dirname, '..', 'core', 'tariff.js'), 'typedError'),
    ...escrowReasons(),
  ]);
  const inFixture = new Set(fx.callableReasons);
  const missing = [...fromSrc].filter((r) => !inFixture.has(r)).sort();
  const extra = [...inFixture].filter((r) => !fromSrc.has(r)).sort();
  assert.deepStrictEqual(missing, [], `fixture'ga qo'shilmagan: ${missing.join(', ')}`);
  assert.deepStrictEqual(extra, [], `manbada yo'q (eskirgan): ${extra.join(', ')}`);
});

// ── 3. HUJJAT SHAKLI (to'liq oqim) ─────────────────────────────────────
function plain(v) {
  if (v instanceof Date) return v.toISOString();
  if (Array.isArray(v)) return v.map(plain);
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v).sort()) o[k] = plain(v[k]);
    return o;
  }
  return v;
}
function keyShape(v) {
  if (Array.isArray(v)) return v.length ? ['[]', keyShape(v[0])] : ['[]'];
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v).sort()) o[k] = keyShape(v[k]);
    return o;
  }
  return v === null ? 'null' : typeof v;
}

async function runFlow() {
  const db = H.makeDb(H.seed()); config.clearCache(); tariff.clearCache();
  const d = H.deps(db);
  const r = await api.makeCreateLogisticsOrder(d)(H.orderPayload(), H.ctx(H.OWNER));
  const shipmentId = r.shipmentIds[0];
  const legId = H.legOf(db, shipmentId)[0];
  const quote = await api.makeQuoteLogisticsOrder({ db })(H.orderPayload(), H.ctx(H.OWNER));
  await H.fund(db, shipmentId);
  await api.makeAcceptLeg(d)({ legId }, H.ctx(H.K1));
  const matchAccepted = db.dump('demand_matches')[`${legId}_${H.K1}`];
  const secrets = await api.makeGetShipmentSecrets(d)({ shipmentId }, H.ctx(H.OWNER));
  const scan = await api.makeScanHandover(d)({
    legId, code: secrets.handoverCode, photoUrls: H.PHOTO, conditionFlags: ['intact'],
    location: { lat: 41.84, lng: 60.39, accuracy: 12 }, clientRequestId: 'req-scan-1',
  }, H.ctx(H.K1));
  const matchInProgress = db.dump('demand_matches')[`${legId}_${H.K1}`];
  const pickupEvent = db.dump('custody_events')[scan.eventId];
  const shipmentInTransit = db.dump('shipments')[shipmentId];
  const confirm = await api.makeConfirmDelivery(d)({
    legId, deliveryCode: secrets.deliveryCode, photoUrls: H.PHOTO, clientRequestId: 'req-deliver-1',
  }, H.ctx(H.K1));
  const deliveryEvent = db.dump('custody_events')[confirm.eventId];
  const out = {
    createResult: r,
    quoteResult: quote,
    secretsResult: { ...secrets, qrPayload: secrets.qrPayload.replace(/\|[a-f0-9]+$/, '|<hmac>'), handoverCode: '123456', deliveryCode: '654321' },
    order: db.dump('logistics_orders')[r.orderId],
    shipment: shipmentInTransit,
    shipmentDelivered: db.dump('shipments')[shipmentId],
    matchAccepted,
    matchInProgress,
    pickupEvent,
    deliveryEvent,
    leg: db.dump('demands')[legId],
  };
  // Tasodifiy ID'lar → barqaror nomlar (fixture har `--update`da bir xil
  // bo'lsin; Dart testi ham shu nomlarga tayanadi). Orkestrator match
  // `createdAt`ini haqiqiy vaqt bilan yozadi — u ham muhrlanadi.
  const ids = { [r.orderId]: 'ORDER1', [shipmentId]: 'SHIP1', [legId]: 'LEG1' };
  for (const m of [out.matchAccepted, out.matchInProgress]) {
    if (m && m.createdAt instanceof Date) m.createdAt = H.NOW;
  }
  return stabilize(out, ids);
}

function stabilize(v, ids) {
  const sub = (s) => Object.entries(ids).reduce((acc, [from, to]) => acc.split(from).join(to), s);
  if (typeof v === 'string') return sub(v);
  if (Array.isArray(v)) return v.map((x) => stabilize(x, ids));
  if (v instanceof Date) return v;
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) o[sub(k)] = stabilize(v[k], ids);
    return o;
  }
  return v;
}

ok('hujjat shakli (`docs`) serverning haqiqiy chiqishi bilan bir xil', async () => {
  const live = plain(await runFlow());
  if (UPDATE) {
    fx.docs = live;
    fs.writeFileSync(FIXTURE, `${JSON.stringify(fx, null, 2)}\n`);
    console.log(`  (fixture \`docs\` yangilandi: ${Object.keys(live).length} hujjat)`);
    return;
  }
  assert.ok(fx.docs, 'fixture\'da `docs` yo\'q — `--update` bilan yozing');
  for (const name of Object.keys(live)) {
    assert.ok(fx.docs[name], `fixture'da \`docs.${name}\` yo'q — \`--update\``);
    assert.deepStrictEqual(keyShape(live[name]), keyShape(fx.docs[name]),
      `\`docs.${name}\` shakli o'zgargan — Dart modelini tekshiring, keyin \`--update\``);
  }
  for (const name of Object.keys(fx.docs)) {
    assert.ok(live[name], `fixture'dagi \`docs.${name}\` server oqimida yo'q`);
  }
});

(async () => {
  for (const t of tests) {
    try { await t.fn(); passed += 1; console.log(`  OK  ${t.name}`); } catch (e) {
      console.error(`  XATO ${t.name}\n       ${e.message}`);
      process.exitCode = 1;
    }
  }
  console.log(`\n${passed} test o'tdi.`);
})();
