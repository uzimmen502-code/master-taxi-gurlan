/**
 * Capability modeli — `core/capabilities.js` (D-12…D-16, D-TAXI, T-2, T-3).
 *
 *   node functions_demand/test/capabilities_model.test.js
 *
 * Qulflanadi:
 *   1. Ruxsat IKKI shartdan: `status` (HUQUQ) va `active` (XOHISH).
 *   2. Har xizmatning O'Z lifecycle'i: kuryer (3k + 5k grace), taksi
 *      (4 oy starter → verification_required → verified), oddiylar.
 *   3. Grace FAQAT BIR MARTA; taksida grace YO'Q.
 *   4. `verification_required` da mavjud ish davom etadi, yangi pullik
 *      e'lon yo'q (D-TAXI-5). Taksi billing faqat verified + grace o'tgach.
 *   5. `suspended` tupik emas; qo'ldagi ish tugatiladi.
 */
const assert = require('assert');
const c = require('../core/capabilities');

let passed = 0;
const tests = [];
function ok(name, fn) { tests.push({ name, fn }); }

const NOW = new Date('2026-10-06T10:00:00.000Z');
const day = (n) => new Date(NOW.getTime() + n * c.DAY_MS);

function doc(over = {}) {
  return {
    identity: { accountId: 'accTEST', primaryUid: '998901110001' },
    courier: { active: true, regionIds: ['xorazm'] },
    status: { courier: c.COURIER.approved },
    window: {},
    ...over,
  };
}

// ─── huquq + xohish ───────────────────────────────────────────────────
ok('tasdiqlangan va aktiv kuryer nomzod', () => {
  assert.strictEqual(c.isEligible(doc(), 'courier'), true);
});
ok('HUQUQ bor, XOHISH yo\'q -> nomzod emas (T-3)', () => {
  assert.strictEqual(c.isEligible(doc({ courier: { active: false } }), 'courier'), false);
});
ok('XOHISH bor, HUQUQ yo\'q -> nomzod emas', () => {
  assert.strictEqual(c.isEligible(doc({ status: { courier: c.COMMON.suspended } }), 'courier'), false);
});
ok('status yo\'q yoki noma\'lum -> `not_registered`', () => {
  assert.strictEqual(c.statusOf(doc({ status: {} }), 'courier'), c.COMMON.notRegistered);
  assert.strictEqual(c.statusOf(doc({ status: { courier: 'xudo' } }), 'courier'), c.COMMON.notRegistered);
  // Boshqa xizmatning statusi bu xizmatda yaroqsiz.
  assert.strictEqual(c.statusOf(doc({ status: { courier: c.TAXI.starter } }), 'courier'), c.COMMON.notRegistered);
});
ok('PARALLEL capability: bitta to\'xtasa qolgani ishlaydi (D-13, D-SERVICE-3)', () => {
  const d = {
    identity: { accountId: 'a', primaryUid: '998901110001' },
    courier: { active: true }, taxi: { active: true }, seller: { active: true },
    status: {
      courier: c.COURIER.approved,
      taxi: c.TAXI.verificationRequired,
      seller: c.COMMON.suspended,
    },
  };
  assert.strictEqual(c.isEligible(d, 'courier'), true);
  assert.strictEqual(c.isEligible(d, 'taxi'), true, 'verification_required mavjud ishni to\'xtatmaydi');
  assert.strictEqual(c.canPublishPaid(d, 'taxi'), false, 'lekin yangi pullik reys yo\'q');
  assert.strictEqual(c.isEligible(d, 'seller'), false);
});
ok('ro\'yxatda yo\'q xizmat — hech qachon ruxsat yo\'q', () => {
  assert.strictEqual(c.isService('carpet'), false);
  assert.strictEqual(c.isEligible({ carpet: { active: true }, status: { carpet: 'enabled' } }, 'carpet'), false);
});
ok('bo\'sh hujjat xato tashlamaydi', () => {
  assert.strictEqual(c.isEligible(null, 'courier'), false);
  assert.strictEqual(c.isEligible({}, 'taxi'), false);
});

// ─── kuryer lifecycle ─────────────────────────────────────────────────
ok('kuryer: ishlaydigan holatlar', () => {
  for (const s of [c.COURIER.trial, c.COURIER.trialExpired, c.COURIER.documentSubmitted,
    c.COURIER.underReview, c.COURIER.approved]) {
    assert.strictEqual(c.isWorking('courier', s), true, s);
  }
  for (const s of [c.COMMON.notRegistered, c.COURIER.documentRejected, c.COMMON.suspended]) {
    assert.strictEqual(c.isWorking('courier', s), false, s);
  }
});
ok('kuryer: odam o\'ziga faqat `trial` so\'raydi, `approved` EMAS (D-14)', () => {
  assert.strictEqual(c.canTransition('courier', c.COMMON.notRegistered, c.COURIER.trial, 'provider'), true);
  for (const from of c.LIFECYCLES.courier.statuses) {
    assert.strictEqual(c.canTransition('courier', from, c.COURIER.approved, 'provider'), false, from);
  }
});
ok('kuryer: tiklanish suspended -> document_submitted (D-15.1)', () => {
  assert.strictEqual(c.canTransition('courier', c.COMMON.suspended, c.COURIER.documentSubmitted, 'provider'), true);
  assert.strictEqual(c.canTransition('courier', c.COMMON.suspended, c.COURIER.approved, 'admin'), true);
});

function courierDoc(over = {}, status = c.COURIER.trial) {
  return doc({ status: { courier: status }, window: { courier: { ...c.windowFor('courier', NOW), ...over } } });
}
ok('kuryer: 3 kun ichida tegilmaydi, chegarada ham', () => {
  assert.strictEqual(c.nextStep(courierDoc(), 'courier', day(2)).action, 'none');
  assert.strictEqual(c.nextStep(courierDoc(), 'courier', day(3)).action, 'none');
});
ok('kuryer: 3 kun o\'tdi -> grace (bir marta, 5 kun)', () => {
  const r = c.nextStep(courierDoc(), 'courier', day(3.5));
  assert.strictEqual(r.action, 'grant_grace');
  assert.strictEqual(r.patch.status, c.COURIER.trialExpired);
  assert.strictEqual(r.patch.graceEndsAt.getTime() - r.patch.graceGrantedAt.getTime(), 5 * c.DAY_MS);
});
ok('kuryer: grace tugadi -> suspended; grace berilgan `trial` -> darhol suspend', () => {
  const g = { graceGrantedAt: day(3.5), graceEndsAt: day(8.5) };
  assert.strictEqual(c.nextStep(courierDoc(g, c.COURIER.trialExpired), 'courier', day(6)).action, 'none');
  assert.strictEqual(c.nextStep(courierDoc(g, c.COURIER.trialExpired), 'courier', day(9)).action, 'suspend');
  assert.strictEqual(c.nextStep(courierDoc(g, c.COURIER.trial), 'courier', day(10)).action, 'suspend', 'ikkinchi grace');
});
ok('kuryer: hujjat yuklangan bo\'lsa soat to\'xtaydi; muddatsiz ariza tegilmaydi', () => {
  for (const s of [c.COURIER.documentSubmitted, c.COURIER.underReview, c.COURIER.approved, c.COURIER.documentRejected]) {
    assert.strictEqual(c.nextStep(courierDoc({}, s), 'courier', day(100)).action, 'none', s);
  }
  assert.strictEqual(c.nextStep(doc({ status: { courier: c.COURIER.trial }, window: {} }), 'courier', day(100)).action, 'none');
});

// ─── taksi lifecycle (D-TAXI-1…6) ─────────────────────────────────────
ok('taksi: `starter` darhol ISHLAYDI va pullik e\'lon qiladi (D-TAXI-1)', () => {
  const d = doc({ taxi: { active: true }, status: { taxi: c.TAXI.starter } });
  assert.strictEqual(c.isEligible(d, 'taxi'), true);
  assert.strictEqual(c.canPublishPaid(d, 'taxi'), true);
  assert.strictEqual(c.LIFECYCLES.taxi.initial, c.TAXI.starter);
});
ok('taksi: starter oynasi = 4 oy, oy oxiriga qisqartirib (D-TAXI-2)', () => {
  const w = c.windowFor('taxi', NOW);
  assert.strictEqual(w.verificationDueAt.toISOString(), '2027-02-06T10:00:00.000Z');
  assert.strictEqual(w.billingGraceUntil, null);
  // 31-oktabr + 4 oy = 28-fevral (JS setMonth 3-martga oshib ketardi).
  assert.strictEqual(c.addMonths(new Date('2026-10-31T00:00:00Z'), 4).toISOString(), '2027-02-28T00:00:00.000Z');
});
ok('taksi: 4 oy o\'tdi -> verification_required, GRACE YO\'Q (D-TAXI-4)', () => {
  const d = doc({ taxi: { active: true }, status: { taxi: c.TAXI.starter }, window: { taxi: c.windowFor('taxi', NOW) } });
  assert.strictEqual(c.nextStep(d, 'taxi', day(100)).action, 'none');
  const r = c.nextStep(d, 'taxi', day(124));
  assert.strictEqual(r.action, 'require_verification');
  assert.strictEqual(r.patch.status, c.TAXI.verificationRequired);
});
ok('taksi: verification_required — mavjud ish HA, yangi pullik reys YO\'Q (D-TAXI-5)', () => {
  const d = doc({ taxi: { active: true }, status: { taxi: c.TAXI.verificationRequired } });
  assert.strictEqual(c.isWorking('taxi', c.TAXI.verificationRequired), true);
  assert.strictEqual(c.canPublishPaid(d, 'taxi'), false);
  assert.strictEqual(c.nextStep(d, 'taxi', day(999)).action, 'none', 'sweeper qayta tegmaydi');
});
ok('taksi: `verified` FAQAT admin (D-TAXI-4)', () => {
  assert.strictEqual(c.canTransition('taxi', c.TAXI.verificationRequired, c.TAXI.verified, 'admin'), true);
  assert.strictEqual(c.canTransition('taxi', c.TAXI.starter, c.TAXI.verified, 'admin'), true);
  for (const from of c.LIFECYCLES.taxi.statuses) {
    assert.strictEqual(c.canTransition('taxi', from, c.TAXI.verified, 'provider'), false, from);
    assert.strictEqual(c.canTransition('taxi', from, c.TAXI.verified, 'system'), false, from);
  }
  // Taksida `approved` degan status umuman yo'q — yozib bo'lmaydi.
  assert.strictEqual(c.normalizeStatus('taxi', 'approved'), c.COMMON.notRegistered);
});
ok('taksi: faqat SYSTEM 4 oyni o\'tkazadi', () => {
  assert.strictEqual(c.canTransition('taxi', c.TAXI.starter, c.TAXI.verificationRequired, 'system'), true);
  assert.strictEqual(c.canTransition('taxi', c.TAXI.starter, c.TAXI.verificationRequired, 'provider'), false);
});
ok('taksi billing: starter da YO\'Q, verified da HA, grace ichida YO\'Q (D-TAXI-3, 6, T-6)', () => {
  const starter = doc({ status: { taxi: c.TAXI.starter } });
  assert.strictEqual(c.isTaxiBillable(starter, NOW), false);
  const verified = doc({ status: { taxi: c.TAXI.verified }, window: { taxi: {} } });
  assert.strictEqual(c.isTaxiBillable(verified, NOW), true);
  const graced = doc({ status: { taxi: c.TAXI.verified }, window: { taxi: { billingGraceUntil: day(30) } } });
  assert.strictEqual(c.isTaxiBillable(graced, NOW), false, 'migratsiya grace ichida');
  assert.strictEqual(c.isTaxiBillable(graced, day(31)), true, 'grace tugagach');
  const vr = doc({ status: { taxi: c.TAXI.verificationRequired } });
  assert.strictEqual(c.isTaxiBillable(vr, NOW), false);
});

// ─── oddiy xizmatlar (D-SERVICE-1) ────────────────────────────────────
ok('seller/service/freight: yoqdi -> `enabled`, ishlaydi, admin kutmaydi', () => {
  for (const s of ['service', 'seller', 'freight']) {
    assert.strictEqual(c.LIFECYCLES[s].initial, c.SIMPLE.enabled);
    assert.strictEqual(c.canTransition(s, c.COMMON.notRegistered, c.SIMPLE.enabled, 'provider'), true);
    assert.strictEqual(c.isEligible(doc({ [s]: { active: true }, status: { [s]: c.SIMPLE.enabled } }), s), true);
    assert.strictEqual(c.windowFor(s, NOW), null);
    assert.deepStrictEqual(c.sweepableStatuses(s), []);
  }
});

// ─── umumiy ───────────────────────────────────────────────────────────
ok('suspended: yangi ish YO\'Q, qo\'ldagi ish tugatiladi', () => {
  const d = doc({ status: { courier: c.COMMON.suspended } });
  assert.strictEqual(c.isEligible(d, 'courier'), false);
  assert.strictEqual(c.canFinishActive(d, 'courier'), true);
  assert.strictEqual(c.canFinishActive(doc({ status: {} }), 'courier'), false);
});
ok('bir xil statusga o\'tish o\'tish emas; noma\'lum o\'tish rad', () => {
  assert.strictEqual(c.canTransition('courier', c.COURIER.approved, c.COURIER.approved, 'admin'), false);
  assert.strictEqual(c.canTransition('taxi', c.COMMON.notRegistered, c.COMMON.suspended, 'admin'), false);
});
ok('SERVER_KEYS qoida bilan bir xil; xizmat kaliti bilan to\'qnashmaydi', () => {
  assert.deepStrictEqual(c.SERVER_KEYS, ['identity', 'status', 'window', 'review', 'suspend', 'debt']);
  for (const s of c.SERVICES) assert.ok(!c.SERVER_KEYS.includes(s), s);
});
ok('identityOf — server yozgan kimlik, yo\'q bo\'lsa bo\'sh satr', () => {
  assert.deepStrictEqual(c.identityOf(doc()), { accountId: 'accTEST', primaryUid: '998901110001' });
  assert.deepStrictEqual(c.identityOf({}), { accountId: '', primaryUid: '' });
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
