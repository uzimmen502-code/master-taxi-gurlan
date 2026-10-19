/**
 * KAFE-RESTORAN — stol bron: sof qoidalar (S5, D-REST-23). Emulyatorsiz: `node functions/test/restaurant_bookings.test.js`
 */
'use strict';
const assert = require('assert');
const b = require('../restaurant_bookings');

let pass = 0;
let failed = 0;
function check(name, fn) {
  try { fn(); pass += 1; console.log(`PASS - ${name}`); } catch (e) {
    failed += 1; console.log(`FAIL - ${name} :: ${e.message}`);
  }
}
const fail = (status, code, extra) => Object.assign(new Error(code), { status, code, details: { code, ...extra } });
const canonicalUid = (x) => String(x).replace(/\D/g, '');

check('ega tarifi: 1–5 → 50 000, 6–10 → 150 000, 11+ → 400 000 (chegaralar: 5/6, 10/11)', () => {
  const t = b.DEFAULTS.tiers;
  const fee = (n) => b.tierFor(n, t).fee;
  assert.deepStrictEqual([1, 5, 6, 10, 11, 100].map(fee), [50000, 50000, 150000, 150000, 400000, 400000]);
});

check('tierFor: 0, manfiy, kasr, satr, 101 — bron yo\'q (null)', () => {
  for (const g of [0, -1, 2.5, '3', null, undefined, 101]) assert.strictEqual(b.tierFor(g, b.DEFAULTS.tiers), null, String(g));
});

check('sanitizeTiers: o\'sib boruvchi butun upTo, butun so\'m fee; xato — null', () => {
  assert.deepStrictEqual(b.sanitizeTiers([{ upTo: 5, fee: 0 }, { upTo: 20, fee: 10 }]), [{ upTo: 5, fee: 0 }, { upTo: 20, fee: 10 }]);
  for (const bad of [null, [], [{ upTo: 5, fee: 1.5 }], [{ upTo: 5, fee: -1 }], [{ upTo: 5, fee: 1 }, { upTo: 5, fee: 2 }],
    [{ upTo: 5, fee: 1 }, { upTo: 3, fee: 2 }], [{ upTo: 501, fee: 1 }], [{ upTo: 0, fee: 1 }], [{ upTo: 5, fee: 10000001 }],
    Array.from({ length: 9 }, (_, i) => ({ upTo: i + 1, fee: 1 }))]) {
    assert.strictEqual(b.sanitizeTiers(bad), null, JSON.stringify(bad));
  }
});

check('bookingIdFor: bir xil (uid, key) → bir xil id; boshqa uid/key → boshqa id', () => {
  const a = b.bookingIdFor('998901', 'key-aaaaaaaa');
  assert.strictEqual(a, b.bookingIdFor('998901', 'key-aaaaaaaa'));
  assert.notStrictEqual(a, b.bookingIdFor('998902', 'key-aaaaaaaa'));
  assert.notStrictEqual(a, b.bookingIdFor('998901', 'key-bbbbbbbb'));
  assert.match(a, /^bk_[0-9a-f]{24}$/);
});

check('checkWindow: 60 daqiqadan kam — TOO_SOON; 60 aniq — ok; 30 kun aniq — ok; 30 kun+1 ms — TOO_FAR', () => {
  const cfg = b.DEFAULTS;
  const now = 1_000_000_000_000;
  const MIN = 60000;
  assert.strictEqual(b.checkWindow(now, now + 59 * MIN, cfg), 'BOOKING_TOO_SOON');
  assert.strictEqual(b.checkWindow(now, now + 60 * MIN, cfg), null);
  assert.strictEqual(b.checkWindow(now, now + 30 * 24 * 60 * MIN, cfg), null);
  assert.strictEqual(b.checkWindow(now, now + 30 * 24 * 60 * MIN + 1, cfg), 'BOOKING_TOO_FAR');
  assert.strictEqual(b.checkWindow(now, now - MIN, cfg), 'BOOKING_TOO_SOON');
});

check('acceptDeadlineMs: min(2 soat, bron − 30 daqiqa)', () => {
  const MIN = 60000;
  const now = 0;
  assert.strictEqual(b.acceptDeadlineMs(now, 10 * 60 * MIN, b.DEFAULTS), 120 * MIN);
  assert.strictEqual(b.acceptDeadlineMs(now, 90 * MIN, b.DEFAULTS), 60 * MIN);
});

check('seatsUsed: slot ichidagi tasdiqlanganlar yig\'indisi; chegara (aynan slot) — kirmaydi; o\'zi chiqariladi', () => {
  const MIN = 60000;
  const t = 1_000_000 * MIN;
  const list = [
    { id: 'a', guests: 4, startMs: t },
    { id: 'b', guests: 3, startMs: t + 119 * MIN },
    { id: 'c', guests: 5, startMs: t + 120 * MIN }, // aynan slot — to'qnashmaydi
    { id: 'd', guests: 2, startMs: t - 119 * MIN },
    { id: 'e', guests: 9, startMs: t - 120 * MIN },
  ];
  assert.strictEqual(b.seatsUsed(list, t, 120), 4 + 3 + 2);
  assert.strictEqual(b.seatsUsed(list, t, 120, 'a'), 3 + 2);
  assert.strictEqual(b.seatsUsed([], t, 120), 0);
});

check('holat o\'tishlari: rejected/expired/cancelled — terminal; confirmed faqat bekor qilinadi; requested→confirmed', () => {
  assert.ok(b.canTransition('requested', 'confirmed'));
  assert.ok(b.canTransition('requested', 'rejected'));
  assert.ok(b.canTransition('requested', 'expired'));
  assert.ok(b.canTransition('confirmed', 'cancelled_by_guest'));
  assert.ok(b.canTransition('confirmed', 'cancelled_by_restaurant'));
  assert.ok(!b.canTransition('confirmed', 'rejected'));
  assert.ok(!b.canTransition('confirmed', 'confirmed'));
  for (const s of ['rejected', 'expired', 'cancelled_by_guest', 'cancelled_by_restaurant']) {
    for (const to of Object.values(b.BS)) assert.ok(!b.canTransition(s, to), `${s}→${to}`);
  }
  assert.ok(!b.canTransition('nope', 'confirmed'));
});

check('mergeConfig: bo\'sh kirish — default tarif (ega) va stage off; qisman o\'zgarish saqlanadi; xatolar', () => {
  const ctx = { fail, canonicalUid };
  const base = b.mergeConfig({}, {}, ctx);
  assert.strictEqual(base.stage, 'off');
  assert.deepStrictEqual(base.tiers, b.DEFAULTS.tiers);
  assert.strictEqual(base.slotMin, 120);
  const next = b.mergeConfig({ stage: 'public' }, base, ctx);
  assert.strictEqual(next.stage, 'public');
  assert.deepStrictEqual(next.tiers, base.tiers);
  const t2 = b.mergeConfig({ tiers: [{ upTo: 4, fee: 1000 }] }, next, ctx);
  assert.deepStrictEqual(t2.tiers, [{ upTo: 4, fee: 1000 }]);
  assert.strictEqual(t2.stage, 'public');
  assert.throws(() => b.mergeConfig({ stage: 'pilot' }, base, ctx), (e) => e.details.code === 'STAGE_INVALID');
  assert.throws(() => b.mergeConfig({ tiers: [{ upTo: 5, fee: 1.5 }] }, base, ctx), (e) => e.details.code === 'TIERS_INVALID');
  assert.throws(() => b.mergeConfig({ slotMin: 5 }, base, ctx), (e) => e.details.code === 'RULES_INVALID');
  assert.throws(() => b.mergeConfig({ maxDays: 1.5 }, base, ctx), (e) => e.details.code === 'RULES_INVALID');
  assert.throws(() => b.mergeConfig({ testerIds: ['abc'] }, base, ctx), (e) => e.details.code === 'TESTERS_INVALID');
  assert.deepStrictEqual(b.mergeConfig({ testerIds: ['+998 91 200 00 01', '998912000001'] }, base, ctx).testerIds, ['998912000001']);
});

console.log(`\n${pass} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
