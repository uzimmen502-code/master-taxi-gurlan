/**
 * Lifecycle — status o'tishlari va Т-19 dagi yopilgan teshiklar.
 *
 *   npm --prefix functions_demand run test:state
 */
const assert = require('assert');
const sm = require('../core/state_machine');

let passed = 0;
function ok(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`  OK  ${name}`);
  } catch (e) {
    console.error(`  XATO ${name}\n       ${e.message}`);
    process.exitCode = 1;
  }
}

const S = sm.STATUS;
const O = sm.OFFER_STATUS;

console.log('statuslar royxati');
ok('konsepsiyadagi `matched` statusi YO`Q', () => {
  // U status emas, matching holati edi — `matching.state`ga ko'chirildi.
  assert.ok(!Object.values(S).includes('matched'));
});
ok('`in_progress` qo`shilgan', () => {
  assert.strictEqual(S.IN_PROGRESS, 'in_progress');
});
ok('matching holati alohida enum', () => {
  assert.deepStrictEqual(
    Object.values(sm.MATCHING_STATE).sort(),
    ['done', 'failed', 'no_providers', 'pending', 'running'],
  );
});

console.log('canTransition — ruxsat etilganlar');
const validPaths = [
  [S.DRAFT, S.ACTIVE],
  [S.ACTIVE, S.ACCEPTED],
  [S.ACTIVE, S.EXPIRED],
  [S.ACTIVE, S.CANCELLED],
  [S.ACCEPTED, S.IN_PROGRESS],
  [S.ACCEPTED, S.ACTIVE],
  [S.IN_PROGRESS, S.COMPLETED],
  [S.IN_PROGRESS, S.DISPUTED],
  [S.EXPIRED, S.ACTIVE],
  [S.DISPUTED, S.COMPLETED],
  [S.DISPUTED, S.CANCELLED],
];
for (const [a, b] of validPaths) {
  ok(`${a} -> ${b}`, () => assert.ok(sm.canTransition(a, b)));
}

console.log('canTransition — rad etilganlar');
const invalidPaths = [
  [S.ACTIVE, S.IN_PROGRESS, 'taklif qabul qilinmasdan ish boshlanmaydi'],
  [S.ACTIVE, S.COMPLETED, 'ijrochisiz bajarilmaydi'],
  [S.DRAFT, S.ACCEPTED, 'yuborilmagan talab qabul qilinmaydi'],
  [S.COMPLETED, S.ACTIVE, 'bajarilgan ish qayta ochilmaydi'],
  [S.COMPLETED, S.CANCELLED, 'bajarilgandan keyin bekor qilinmaydi'],
  [S.CANCELLED, S.ACTIVE, 'bekor qilingan talab qayta tirilmaydi'],
  [S.CANCELLED, S.COMPLETED, 'bekor qilingan ish bajarilmaydi'],
  [S.EXPIRED, S.ACCEPTED, 'muddati o`tgan talab qabul qilinmaydi'],
];
for (const [a, b, why] of invalidPaths) {
  ok(`${a} -/-> ${b} (${why})`, () => assert.ok(!sm.canTransition(a, b)));
}
ok('bir xil statusga o`tish o`tish DEB HISOBLANMAYDI', () => {
  assert.ok(!sm.canTransition(S.ACTIVE, S.ACTIVE));
});
ok('noma`lum status -> false', () => {
  assert.ok(!sm.canTransition('xayoliy', S.ACTIVE));
  assert.ok(!sm.canTransition(S.ACTIVE, 'xayoliy'));
});

console.log('assertTransition');
ok('to`g`ri o`tish statusni qaytaradi', () => {
  assert.strictEqual(sm.assertTransition(S.ACTIVE, S.ACCEPTED), S.ACCEPTED);
});
ok('noto`g`ri o`tish XATO tashlaydi (jimgina o`tmaydi)', () => {
  assert.throws(
    () => sm.assertTransition(S.COMPLETED, S.ACTIVE, 'acceptOffer'),
    (e) => e.code === 'failed-precondition' && /acceptOffer/.test(e.message),
  );
});
ok('xato xabari mumkin bo`lgan yo`llarni ko`rsatadi', () => {
  try {
    sm.assertTransition(S.CANCELLED, S.ACTIVE);
    assert.fail('xato kutilgan edi');
  } catch (e) {
    assert.ok(/hech qayerga/.test(e.message), e.message);
  }
});

console.log('isTerminal / isOpenForOffers');
ok('completed va cancelled — oxirgi', () => {
  assert.ok(sm.isTerminal(S.COMPLETED));
  assert.ok(sm.isTerminal(S.CANCELLED));
});
ok('expired oxirgi EMAS (mijoz qayta yuborishi mumkin)', () => {
  assert.ok(!sm.isTerminal(S.EXPIRED));
  assert.ok(sm.canTransition(S.EXPIRED, S.ACTIVE));
});
ok('faqat active holatda taklif qabul qilinadi', () => {
  assert.ok(sm.isOpenForOffers(S.ACTIVE));
  for (const s of [S.DRAFT, S.ACCEPTED, S.IN_PROGRESS, S.COMPLETED, S.EXPIRED]) {
    assert.ok(!sm.isOpenForOffers(s), `${s} ochiq bo'lmasligi kerak`);
  }
});

console.log('rejim bo`yicha in_progress');
ok('dispatch va quote da bor', () => {
  assert.ok(sm.usesInProgress('dispatch'));
  assert.ok(sm.usesInProgress('quote'));
});
ok('alert va recurring da yo`q (konsepsiya talabi)', () => {
  assert.ok(!sm.usesInProgress('alert'));
  assert.ok(!sm.usesInProgress('recurring'));
});
ok('nextAfterAccept rejimga qarab', () => {
  assert.strictEqual(sm.nextAfterAccept('quote'), S.IN_PROGRESS);
  assert.strictEqual(sm.nextAfterAccept('alert'), S.COMPLETED);
});

console.log('Т-19.1 — assignmentDeadline');
const cfg = { assignmentDeadlineMinutes: { dispatch: 15, quote: 120 } };
ok('dispatch 15 daqiqa', () => {
  const acceptedAt = new Date('2026-10-03T10:00:00Z');
  const r = sm.assignmentDeadline(acceptedAt, 'dispatch', cfg, new Date('2026-10-03T10:14:00Z'));
  assert.strictEqual(r.expired, false);
  const r2 = sm.assignmentDeadline(acceptedAt, 'dispatch', cfg, new Date('2026-10-03T10:16:00Z'));
  assert.strictEqual(r2.expired, true);
});
ok('quote 120 daqiqa', () => {
  const acceptedAt = new Date('2026-10-03T10:00:00Z');
  const r = sm.assignmentDeadline(acceptedAt, 'quote', cfg, new Date('2026-10-03T11:30:00Z'));
  assert.strictEqual(r.expired, false);
});
ok('konfig bermasa 120 daqiqa standart', () => {
  const r = sm.assignmentDeadline(
    new Date('2026-10-03T10:00:00Z'), 'dispatch', {},
    new Date('2026-10-03T11:00:00Z'),
  );
  assert.strictEqual(r.expired, false);
});
ok('muddat o`tsa `accepted -> active` ruxsat etilgan', () => {
  // Т-19.1 ning asosiy natijasi: talab abadiy `accepted`da qolmaydi.
  assert.ok(sm.canTransition(S.ACCEPTED, S.ACTIVE));
});

console.log('Т-19.2 — qayta ochilganda taklif statusi');
ok('accepted taklif rejected bo`ladi (withdrawn EMAS)', () => {
  // `withdrawn` = taklifchi o'zi qaytarib oldi. Bu holatda ish bekor bo'ldi,
  // shuning uchun `rejected` — tarix to'g'ri qolishi uchun muhim.
  assert.strictEqual(sm.offerStatusOnReopen(O.ACCEPTED), O.REJECTED);
});
ok('rejected taklif active ga QAYTMAYDI (narxi eskirgan)', () => {
  assert.strictEqual(sm.offerStatusOnReopen(O.REJECTED), O.REJECTED);
});
ok('active taklif o`zgarmaydi', () => {
  assert.strictEqual(sm.offerStatusOnReopen(O.ACTIVE), O.ACTIVE);
});

console.log('taklif o`tishlari');
ok('active -> accepted/rejected/withdrawn/expired', () => {
  for (const to of [O.ACCEPTED, O.REJECTED, O.WITHDRAWN, O.EXPIRED]) {
    assert.ok(sm.canTransitionOffer(O.ACTIVE, to), `active -> ${to}`);
  }
});
ok('withdrawn qaytib active bo`lmaydi', () => {
  assert.ok(!sm.canTransitionOffer(O.WITHDRAWN, O.ACTIVE));
});
ok('rejected qaytib accepted bo`lmaydi', () => {
  assert.ok(!sm.canTransitionOffer(O.REJECTED, O.ACCEPTED));
});
ok('accepted -> rejected (ish bekor bo`lsa)', () => {
  assert.ok(sm.canTransitionOffer(O.ACCEPTED, O.REJECTED));
});
ok('assertOfferTransition xato tashlaydi', () => {
  assert.throws(
    () => sm.assertOfferTransition(O.WITHDRAWN, O.ACCEPTED),
    (e) => e.code === 'failed-precondition',
  );
});

console.log('Т-19.3 — nizo SLA');
ok('SLA 48 soat', () => {
  assert.strictEqual(sm.DISPUTE_SLA_HOURS, 48);
});
ok('47 soat — muddati o`tmagan', () => {
  const at = new Date('2026-10-01T10:00:00Z');
  assert.strictEqual(sm.disputeOverdue(at, new Date('2026-10-03T09:00:00Z')), false);
});
ok('49 soat — muddati o`tgan', () => {
  const at = new Date('2026-10-01T10:00:00Z');
  assert.strictEqual(sm.disputeOverdue(at, new Date('2026-10-03T11:00:00Z')), true);
});

console.log('canRate');
ok('faqat completed bo`yicha baho', () => {
  assert.ok(sm.canRate(S.COMPLETED));
  for (const s of [S.ACTIVE, S.ACCEPTED, S.IN_PROGRESS, S.CANCELLED, S.EXPIRED, S.DISPUTED]) {
    assert.ok(!sm.canRate(s), `${s} bo'yicha baho berilmasligi kerak`);
  }
});

console.log('toMillis');
ok('Date, number, ISO, Firestore Timestamp', () => {
  const ms = 1759485600000;
  assert.strictEqual(sm.toMillis(new Date(ms)), ms);
  assert.strictEqual(sm.toMillis(ms), ms);
  assert.strictEqual(sm.toMillis(new Date(ms).toISOString()), ms);
  assert.strictEqual(sm.toMillis({ toMillis: () => ms }), ms);
  assert.strictEqual(sm.toMillis({ toDate: () => new Date(ms) }), ms);
  assert.strictEqual(sm.toMillis({ seconds: ms / 1000 }), ms);
});
ok('null va axlat -> 0', () => {
  assert.strictEqual(sm.toMillis(null), 0);
  assert.strictEqual(sm.toMillis(undefined), 0);
  assert.strictEqual(sm.toMillis('axlat'), 0);
  assert.strictEqual(sm.toMillis({}), 0);
});

console.log('jadval sogligi');
ok('har bir status ALLOWED jadvalida bor', () => {
  for (const s of Object.values(S)) {
    assert.ok(sm.ALLOWED[s] !== undefined, `«${s}» jadvalda yo'q`);
  }
});
ok('ALLOWED dagi har bir nishon haqiqiy status', () => {
  const all = new Set(Object.values(S));
  for (const [from, tos] of Object.entries(sm.ALLOWED)) {
    for (const to of tos) {
      assert.ok(all.has(to), `${from} -> «${to}» noma'lum status`);
    }
  }
});
ok('har bir taklif statusi OFFER_ALLOWED da bor', () => {
  for (const s of Object.values(O)) {
    assert.ok(sm.OFFER_ALLOWED[s] !== undefined, `«${s}» jadvalda yo'q`);
  }
});

console.log(`\n${passed} test o'tdi.`);
