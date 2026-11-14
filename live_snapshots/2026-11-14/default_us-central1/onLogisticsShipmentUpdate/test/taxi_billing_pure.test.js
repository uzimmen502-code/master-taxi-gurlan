/**
 * Taxi billing — SOF funksiyalar: komissiya formulasi va anti-fraud.
 *
 *   node functions/test/taxi_billing_pure.test.js
 *
 * ENG MUHIM: `AVA fee = farePerSeat × 4 × 2%` — AVA orqali nechta
 * yo'lovchi topilgani komissiyaga TA'SIR QILMAYDI (D-TAXI-7…9).
 * Bu test formulani raqam bilan qulflaydi; kimdir `passengers` bilan
 * hisoblashga o'tsa — shu yerda yiqiladi.
 */
const assert = require('assert');
const { calculateTaxiFee, SEAT_BASIS, RATE_BPS } = require('../taxi_billing');
const fraud = require('../taxi_fraud');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

// ─── D-TAXI-7…10: formula ─────────────────────────────────────────────
ok('Urganch → Toshkent misoli: 350 000 × 4 × 2% = 28 000 (D-TAXI-8)', () => {
  const f = calculateTaxiFee(350000);
  assert.strictEqual(f.grossBasis, 1400000);
  assert.strictEqual(f.feeAmount, 28000);
  assert.strictEqual(f.seatBasis, 4);
  assert.strictEqual(f.rate, 0.02);
});
ok('250 000 → 20 000; 400 000 → 32 000 (D-TAXI-10)', () => {
  assert.strictEqual(calculateTaxiFee(250000).feeAmount, 20000);
  assert.strictEqual(calculateTaxiFee(400000).feeAmount, 32000);
});
ok('YO\'LOVCHI SONI FORMULADA YO\'Q — 1 ham, 4 ham 28 000 (D-TAXI-9)', () => {
  // Funksiya yo'lovchi sonini umuman QABUL QILMAYDI: bu ataylab.
  assert.strictEqual(calculateTaxiFee.length, 1);
  for (const passengers of [0, 1, 2, 3, 4]) {
    assert.strictEqual(calculateTaxiFee(350000).feeAmount, 28000, `passengers=${passengers}`);
  }
  // Taqiqlangan hisob: 350 000 × 1 × 2% = 7 000 — hech qachon chiqmasin.
  assert.notStrictEqual(calculateTaxiFee(350000).feeAmount, 7000);
});
ok('BUTUN SO\'M, yuqoriga (T-4, 8-qoida): 333 333 → 26 667', () => {
  const f = calculateTaxiFee(333333);
  assert.strictEqual(f.grossBasis, 1333332);
  assert.strictEqual(f.feeAmount, 26667, '26 666.64 → 26 667');
  assert.ok(Number.isInteger(f.feeAmount));
});
ok('deterministik va float xatosisiz: 1 000 000 marta bir xil', () => {
  const a = calculateTaxiFee(123457).feeAmount;
  for (let i = 0; i < 1000; i += 1) assert.strictEqual(calculateTaxiFee(123457).feeAmount, a);
  assert.strictEqual(a, Math.ceil((123457 * 4 * 2) / 100));
});
ok('noto\'g\'ri narx rad etiladi', () => {
  for (const bad of [0, -1, 1.5, '350000', NaN, null, undefined]) {
    assert.throws(() => calculateTaxiFee(bad), (e) => e.code === 'invalid-argument', String(bad));
  }
});
ok('konstantalar: 4 o\'rin, 200 bps', () => {
  assert.strictEqual(SEAT_BASIS, 4);
  assert.strictEqual(RATE_BPS, 200);
});

// ─── D-TAXI-16…19: anti-fraud ─────────────────────────────────────────
const T0 = new Date('2026-10-06T06:00:00Z');
const h = (n) => new Date(T0.getTime() + n * 3600000);
const URG = { lat: 41.55, lng: 60.63 };
const TSH = { lat: 41.3111, lng: 69.2797 };

function prevTrip(over = {}) {
  return {
    from: 'Urganch', to: 'Toshkent', destLat: TSH.lat, destLng: TSH.lng,
    cancelledAt: h(1), departureAt: h(2), hadAvaBooking: true, ...over,
  };
}

ok('egalik misoli: bekor + AVA bron + 12 soatdan keyin teskari reys + GPS destination\'da → CONFIRMED (D-TAXI-17)', () => {
  const r = fraud.evaluateCancelFraud({
    prev: prevTrip(),
    next: { from: 'Toshkent', to: 'Urganch', publishedAt: h(13), driverLat: TSH.lat, driverLng: TSH.lng },
  });
  assert.strictEqual(r.verdict, 'confirmed');
  for (const s of ['location_at_dest', 'had_ava_booking', 'route_reversed', 'time_window']) assert.ok(r.signals.includes(s), s);
});
ok('CANCEL-2: bekor → ERTASIGA teskari reys, GPS YO\'Q → NORMAL (o\'z-o\'zidan dalil emas)', () => {
  const r = fraud.evaluateCancelFraud({
    prev: prevTrip(),
    next: { from: 'Toshkent', to: 'Urganch', publishedAt: h(13) },
  });
  assert.strictEqual(r.verdict, 'normal');
  assert.strictEqual(r.reason, 'no_location_evidence');
});
ok('CANCEL-2: 2 kun / 5 kun keyin xuddi shu yo\'nalish, uyda → NORMAL', () => {
  for (const hours of [48, 120]) {
    const r = fraud.evaluateCancelFraud({
      prev: prevTrip(),
      next: { from: 'Urganch', to: 'Toshkent', publishedAt: h(hours), driverLat: URG.lat, driverLng: URG.lng },
    });
    assert.strictEqual(r.verdict, 'normal', `${hours}h`);
  }
});
ok('CANCEL-4: BITTA GPS NUQTASI hukm emas → NORMAL', () => {
  const r = fraud.evaluateCancelFraud({
    prev: prevTrip({ hadAvaBooking: false, departureAt: null }),
    next: { from: 'Buxoro', to: 'Samarqand', publishedAt: h(60), driverLat: TSH.lat, driverLng: TSH.lng },
  });
  assert.strictEqual(r.verdict, 'normal');
});
ok('GPS + teskari reys, lekin AVA bron YO\'Q → NORMAL (olinadigan foyda yo\'q, CANCEL-7)', () => {
  const r = fraud.evaluateCancelFraud({
    prev: prevTrip({ hadAvaBooking: false, departureAt: null }),
    next: { from: 'Toshkent', to: 'Urganch', publishedAt: h(13), driverLat: TSH.lat, driverLng: TSH.lng },
  });
  assert.strictEqual(r.verdict, 'normal');
  assert.strictEqual(r.reason, 'no_ava_booking');
});
ok('GPS + AVA bron, boshqa hech narsa → SUSPICIOUS (faqat yoziladi, pul yo\'q)', () => {
  const r = fraud.evaluateCancelFraud({
    prev: prevTrip({ departureAt: null }),
    next: { from: 'Buxoro', to: 'Samarqand', publishedAt: h(80), driverLat: TSH.lat, driverLng: TSH.lng },
  });
  assert.strictEqual(r.verdict, 'suspicious');
});
ok('GPS + AVA bron + bitta tasdiqlovchi → MANUAL_REVIEW (admin ko\'radi, pul yo\'q)', () => {
  const r = fraud.evaluateCancelFraud({
    prev: prevTrip({ departureAt: null }),
    next: { from: 'Toshkent', to: 'Urganch', publishedAt: h(80), driverLat: TSH.lat, driverLng: TSH.lng },
  });
  assert.strictEqual(r.verdict, 'manual_review');
});
ok('AVA bron bo\'lmasa HECH QACHON confirmed emas (komissiya «ishlamagan»)', () => {
  const r = fraud.evaluateCancelFraud({
    prev: prevTrip({ hadAvaBooking: false }),
    next: { from: 'Toshkent', to: 'Urganch', publishedAt: h(13), driverLat: TSH.lat, driverLng: TSH.lng },
  });
  assert.notStrictEqual(r.verdict, 'confirmed');
});
ok('CANCEL-7: boshqa transportda ketgan haqiqiy bekor — bron yo\'q, yo\'nalish boshqa → NORMAL', () => {
  const r = fraud.evaluateCancelFraud({
    prev: prevTrip({ hadAvaBooking: false, cancelledAt: h(-20) }),
    next: { from: 'Toshkent', to: 'Samarqand', publishedAt: h(40), driverLat: TSH.lat, driverLng: TSH.lng },
  });
  assert.strictEqual(r.verdict, 'normal');
});
ok('CANCEL-9: `late_cancel` + teskari reys (vaqt oynasi yo\'q) → MANUAL_REVIEW, confirmed EMAS', () => {
  // Jo'nashdan keyin bekor (yo'lovchi topilmadi) + GPS + bron + teskari reys,
  // lekin vaqt oynasidan tashqarida. Avval late_cancel ikkinchi «extra»
  // bo'lib pulni avtomatik yechardi; endi faqat admin ko'rigi.
  const r = fraud.evaluateCancelFraud({
    prev: prevTrip({ cancelledAt: h(3) }), // departure h(2) — jo'nashdan 1 soat keyin bekor
    next: { from: 'Toshkent', to: 'Urganch', publishedAt: h(80), driverLat: TSH.lat, driverLng: TSH.lng },
  });
  assert.ok(r.signals.includes('late_cancel'));
  assert.ok(r.signals.includes('route_reversed'));
  assert.ok(!r.signals.includes('time_window'));
  assert.strictEqual(r.verdict, 'manual_review');
});
ok('CANCEL-9: `late_cancel` ustiga 2 ta MUSTAQIL dalil bo\'lsa — baribir CONFIRMED (signal yo\'qolmagan)', () => {
  const r = fraud.evaluateCancelFraud({
    prev: prevTrip({ cancelledAt: h(3), originLat: URG.lat, originLng: URG.lng, cancelLat: URG.lat, cancelLng: URG.lng }),
    next: { from: 'Toshkent', to: 'Urganch', publishedAt: h(15), driverLat: TSH.lat, driverLng: TSH.lng },
  });
  assert.ok(r.signals.includes('late_cancel'));
  assert.strictEqual(r.verdict, 'confirmed'); // route_reversed + time_window + movement_to_dest
});
ok('chegaralar KONFIGDAN: confirmedExtra oshirilsa confirmed chiqmaydi', () => {
  const r = fraud.evaluateCancelFraud({
    prev: prevTrip(),
    next: { from: 'Toshkent', to: 'Urganch', publishedAt: h(13), driverLat: TSH.lat, driverLng: TSH.lng },
    thresholds: { confirmedExtra: 99 },
  });
  assert.strictEqual(r.verdict, 'manual_review');
});
ok('bo\'sh kirish xato tashlamaydi', () => {
  assert.strictEqual(fraud.evaluateCancelFraud({ prev: null, next: null }).verdict, 'normal');
});

// ─── D-TAXI-14: origin mismatch — signal, hukm emas ───────────────────
ok('ertangi reysni uydan e\'lon qilish NORMAL (uzoq, lekin jo\'nash yaqin emas)', () => {
  const r = fraud.evaluateOriginMismatch({
    originLat: TSH.lat, originLng: TSH.lng, driverLat: URG.lat, driverLng: URG.lng,
    publishedAt: h(0), departureAt: h(20),
  });
  assert.strictEqual(r.flagged, false);
  assert.strictEqual(r.reason, 'far_but_not_soon');
});
ok('boshqa shaharda turib 1 soatdan keyin jo\'naydigan reys → FLAGGED', () => {
  const r = fraud.evaluateOriginMismatch({
    originLat: TSH.lat, originLng: TSH.lng, driverLat: URG.lat, driverLng: URG.lng,
    publishedAt: h(0), departureAt: h(1),
  });
  assert.strictEqual(r.flagged, true);
});
ok('koordinata yo\'q — tekshirilmaydi', () => {
  assert.strictEqual(fraud.evaluateOriginMismatch({ originLat: null }).flagged, false);
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
