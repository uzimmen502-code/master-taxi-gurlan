/**
 * Т-7 — Notification Policy.
 *
 *   npm --prefix functions_demand run test:policy
 *
 * Qabul mezoni (13.2.4): «Bir talab bo'yicha bir taklifchiga hech qachon
 * ikkinchi push ketmaydi.» Shu bilan birga eng muhim xususiyat:
 * LIMIT KO'RINISHGA TEGMAYDI — limitdan oshgan push dayjestga aylanadi,
 * talab esa inbox'da baribir ko'rinadi.
 */
const assert = require('assert');
const p = require('../notify/policy');
const { DEFAULTS, deepMerge } = require('../core/config');

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

const cfg = DEFAULTS;
/** Tashkent 12:00 = UTC 07:00 — tinch soatlardan tashqari. */
const kunduzi = new Date('2026-10-03T07:00:00Z');
/** Tashkent 01:00 = UTC 20:00 (oldingi kun) — tinch soat. */
const kechasi = new Date('2026-10-02T20:00:00Z');

function provider(over = {}) {
  return {
    moduleOptOut: false,
    digestOnly: false,
    hasToken: true,
    sentLastHour: 0,
    sentToday: 0,
    ...over,
  };
}

/**
 * Калибровкаланган конфиг: `push.minScore = 0.70` (ҳар мослик учун push чегараси,
 * ега 2026-10-20, вариант 3). Стандарт `minScore: null` — калибровка йўқ.
 */
const calibrated = deepMerge(DEFAULTS, { push: { minScore: 0.7 } });

function decide(over = {}) {
  return p.decidePush({
    mode: 'quote',
    config: calibrated,
    pushEnabled: true,
    provider: provider(),
    score: 0.8,
    now: kunduzi,
    ...over,
  });
}

console.log('localHour — Asia/Tashkent');
ok('UTC 07:00 -> Tashkent 12:00', () => {
  assert.strictEqual(p.localHour(new Date('2026-10-03T07:00:00Z')), 12);
});
ok('UTC 20:00 -> Tashkent 01:00 (keyingi kun)', () => {
  assert.strictEqual(p.localHour(new Date('2026-10-02T20:00:00Z')), 1);
});
ok('UTC 19:00 -> Tashkent 00:00', () => {
  assert.strictEqual(p.localHour(new Date('2026-10-02T19:00:00Z')), 0);
});

console.log('inQuietHours — 23:00-07:00');
const q = cfg.push.quietHours;
ok('Tashkent 01:00 — tinch soat', () => {
  assert.strictEqual(p.inQuietHours(new Date('2026-10-02T20:00:00Z'), q), true);
});
ok('Tashkent 23:30 — tinch soat', () => {
  assert.strictEqual(p.inQuietHours(new Date('2026-10-03T18:30:00Z'), q), true);
});
ok('Tashkent 12:00 — tinch soat EMAS', () => {
  assert.strictEqual(p.inQuietHours(new Date('2026-10-03T07:00:00Z'), q), false);
});
ok('Tashkent 07:00 — tinch soat tugadi', () => {
  assert.strictEqual(p.inQuietHours(new Date('2026-10-03T02:00:00Z'), q), false);
});
ok('Tashkent 06:59 — hali tinch soat', () => {
  assert.strictEqual(p.inQuietHours(new Date('2026-10-03T01:59:00Z'), q), true);
});
ok('from === to -> tinch soat yo`q (24/7 bo`lib qolmaydi)', () => {
  assert.strictEqual(p.inQuietHours(kunduzi, { from: 7, to: 7 }), false);
});

console.log('quietHoursEndAt');
ok('kechasi 01:00 -> ertalab 07:00 ga rejalashtiriladi', () => {
  const at = p.quietHoursEndAt(new Date('2026-10-02T20:00:00Z'), q);
  assert.strictEqual(p.localHour(at), 7);
  assert.ok(at.getTime() > new Date('2026-10-02T20:00:00Z').getTime());
});
ok('23:30 -> keyingi kun 07:00', () => {
  const at = p.quietHoursEndAt(new Date('2026-10-03T18:30:00Z'), q);
  assert.strictEqual(p.localHour(at), 7);
});

console.log('IDEMPOTENTLIK — eng qat`iy qoida');
ok('alreadyLogged -> push KETMAYDI', () => {
  const r = decide({ alreadyLogged: true });
  assert.strictEqual(r.send, false);
  assert.strictEqual(r.digest, false, 'takroriy push dayjestga ham aylanmaydi');
  assert.strictEqual(r.reason, p.REASON.ALREADY_SENT);
});
ok('alreadyLogged hamma narsadan ustun (dispatch`da ham)', () => {
  const r = decide({ mode: 'dispatch', alreadyLogged: true });
  assert.strictEqual(r.send, false);
});

console.log('kill switch');
ok('pushEnabled: false -> ketmaydi', () => {
  const r = decide({ pushEnabled: false });
  assert.strictEqual(r.send, false);
  assert.strictEqual(r.digest, false, 'shadow mode`da dayjest ham yuborilmaydi');
});
ok('shadow mode: dispatch`da ham push yo`q', () => {
  const r = decide({ mode: 'dispatch', pushEnabled: false });
  assert.strictEqual(r.send, false);
});

console.log('taklifchining o`z qarori');
ok('modulda push`ni o`chirgan -> ketmaydi, dayjest ham yo`q', () => {
  const r = decide({ provider: provider({ moduleOptOut: true }) });
  assert.strictEqual(r.send, false);
  assert.strictEqual(r.digest, false);
  assert.strictEqual(r.reason, p.REASON.PUSH_DISABLED_BY_PROVIDER);
});
ok('«faqat dayjest» tanlagan -> dayjest', () => {
  const r = decide({ provider: provider({ digestOnly: true }) });
  assert.strictEqual(r.send, false);
  assert.strictEqual(r.digest, true);
});
ok('dispatch`da «faqat dayjest» ham push oladi', () => {
  // Bitta kuryer kerak, mijoz kutib turibdi.
  const r = decide({ mode: 'dispatch', provider: provider({ digestOnly: true }) });
  assert.strictEqual(r.send, true);
});

console.log('allaqachon ko`rgan / token yo`q');
ok('talabni allaqachon ko`rgan -> jiringlatmaymiz', () => {
  const r = decide({ alreadySeen: true });
  assert.strictEqual(r.send, false);
  assert.strictEqual(r.reason, p.REASON.SEEN_ALREADY);
});
ok('token yo`q -> yuborilmaydi (inbox`da baribir ko`rinadi)', () => {
  const r = decide({ provider: provider({ hasToken: false }) });
  assert.strictEqual(r.send, false);
  assert.strictEqual(r.reason, p.REASON.NO_TOKEN);
});

console.log('dispatch — limitsiz');
ok('tinch soatda ham push ketadi', () => {
  const r = decide({ mode: 'dispatch', now: kechasi });
  assert.strictEqual(r.send, true);
});
ok('kunlik limit dispatch`ga ta`sir qilmaydi', () => {
  const r = decide({ mode: 'dispatch', provider: provider({ sentToday: 999, sentLastHour: 99 }) });
  assert.strictEqual(r.send, true);
});

console.log('quote — LIMIT (konsepsiyadagi teshik yopildi)');
ok('limit ichida -> push ketadi', () => {
  const r = decide({ provider: provider({ sentLastHour: 4, sentToday: 19 }) });
  assert.strictEqual(r.send, true);
});
ok('soatlik limitga yetdi -> DAYJEST (ko`rinish saqlanadi)', () => {
  const r = decide({ provider: provider({ sentLastHour: 5 }) });
  assert.strictEqual(r.send, false);
  assert.strictEqual(r.digest, true, 'talab inbox`da baribir ko`rinishi kerak');
  assert.strictEqual(r.reason, p.REASON.HOURLY_LIMIT);
});
ok('kunlik limitga yetdi -> DAYJEST', () => {
  const r = decide({ provider: provider({ sentToday: 20 }) });
  assert.strictEqual(r.send, false);
  assert.strictEqual(r.digest, true);
  assert.strictEqual(r.reason, p.REASON.DAILY_LIMIT);
});
ok('tinch soat -> dayjest + ertalabga rejalashtiriladi', () => {
  const r = decide({ now: kechasi });
  assert.strictEqual(r.send, false);
  assert.strictEqual(r.digest, true);
  assert.strictEqual(r.reason, p.REASON.QUIET_HOURS);
  assert.ok(r.retryAt instanceof Date);
  assert.strictEqual(p.localHour(r.retryAt), 7);
});
ok('alert rejimida qattiqroq limit (3/soat, 10/kun)', () => {
  const r1 = decide({ mode: 'alert', provider: provider({ sentLastHour: 3 }) });
  assert.strictEqual(r1.digest, true);
  const r2 = decide({ mode: 'alert', provider: provider({ sentLastHour: 2 }) });
  assert.strictEqual(r2.send, true);
});

console.log('ҲАР МОСЛИК УЧУН PUSH ЧЕГАРАСИ (push.minScore, вариант 3)');
ok('стандарт minScore = null (калибровка ўтказилмаган)', () => {
  assert.strictEqual(DEFAULTS.push.minScore, null);
});
ok('калибровкасиз (minScore: null) quote push ҚИЛМАЙДИ, дайжест ҳам йўқ', () => {
  const r = decide({ config: cfg, score: 0.99 });
  assert.strictEqual(r.send, false);
  assert.strictEqual(r.digest, false);
  assert.strictEqual(r.reason, p.REASON.SCORE_NOT_CALIBRATED);
});
ok('чегарадан юқори (0.79 >= 0.70) -> push', () => {
  const r = decide({ score: 0.79 });
  assert.strictEqual(r.send, true);
  assert.strictEqual(r.reason, p.REASON.SEND);
});
ok('чегарага АЙНАН тенг (0.70) -> push (>= қоидаси)', () => {
  assert.strictEqual(decide({ score: 0.7 }).send, true);
});
ok('чегарадан бир оз паст (0.699) -> push йўқ, дайжест ҳам йўқ', () => {
  const r = decide({ score: 0.699 });
  assert.strictEqual(r.send, false);
  assert.strictEqual(r.digest, false, 'паст мослик дайжестга ҳам тушмайди — фақат рўйхатда кўринади');
  assert.strictEqual(r.reason, p.REASON.BELOW_MIN_SCORE);
});
ok('score йўқ/NaN/матн -> паст деб ҳисобланади (хавфсиз томон)', () => {
  for (const bad of [undefined, null, NaN, 'yuqori']) {
    const r = decide({ score: bad });
    assert.strictEqual(r.send, false, `score=${String(bad)}`);
    assert.strictEqual(r.reason, p.REASON.BELOW_MIN_SCORE);
  }
});
ok('dispatch (курьер) чегарага ва калибровкага ТАЪСИР ҚИЛМАЙДИ', () => {
  const r = p.decidePush({
    mode: 'dispatch', config: cfg, pushEnabled: true, provider: provider(), now: kunduzi,
  });
  assert.strictEqual(r.send, true, 'score йўқ, minScore null — барибир push');
});
ok('alert ва recurring режимларига ҳам чегара қўлланади', () => {
  for (const mode of ['alert', 'recurring']) {
    assert.strictEqual(decide({ mode, score: 0.5 }).reason, p.REASON.BELOW_MIN_SCORE, mode);
    assert.strictEqual(decide({ mode, score: 0.9 }).send, true, mode);
  }
});
ok('паст мослик «фақат дайжест» ёки лимитдан ОЛДИН тўхтайди', () => {
  const r1 = decide({ score: 0.5, provider: provider({ digestOnly: true }) });
  assert.strictEqual(r1.reason, p.REASON.BELOW_MIN_SCORE);
  assert.strictEqual(r1.digest, false);
  const r2 = decide({ score: 0.5, provider: provider({ sentToday: 99, sentLastHour: 99 }) });
  assert.strictEqual(r2.reason, p.REASON.BELOW_MIN_SCORE);
  const r3 = decide({ score: 0.5, now: kechasi });
  assert.strictEqual(r3.reason, p.REASON.BELOW_MIN_SCORE);
});
ok('чегарадан юқори + тинч соат -> дайжест (аввалги қоида сақланади)', () => {
  const r = decide({ score: 0.9, now: kechasi });
  assert.strictEqual(r.digest, true);
  assert.strictEqual(r.reason, p.REASON.QUIET_HOURS);
});
ok('чегарадан юқори + лимит -> дайжест (аввалги қоида сақланади)', () => {
  const r = decide({ score: 0.9, provider: provider({ sentLastHour: 5 }) });
  assert.strictEqual(r.digest, true);
  assert.strictEqual(r.reason, p.REASON.HOURLY_LIMIT);
});
ok('қарор тартиби: kill switch / optOut / alreadySeen чегарадан кучли', () => {
  assert.strictEqual(
    decide({ pushEnabled: false, score: 0.1 }).reason, p.REASON.PUSH_DISABLED_MODULE,
  );
  assert.strictEqual(
    decide({ score: 0.1, provider: provider({ moduleOptOut: true }) }).reason,
    p.REASON.PUSH_DISABLED_BY_PROVIDER,
  );
  assert.strictEqual(decide({ score: 0.1, alreadySeen: true }).reason, p.REASON.SEEN_ALREADY);
  assert.strictEqual(decide({ score: 0.1, alreadyLogged: true }).reason, p.REASON.ALREADY_SENT);
});
ok('чегара 1.0 бўлса фақат мукаммал (1.0) score push олади', () => {
  const strict = deepMerge(DEFAULTS, { push: { minScore: 1 } });
  assert.strictEqual(decide({ config: strict, score: 0.999 }).send, false);
  assert.strictEqual(decide({ config: strict, score: 1 }).send, true);
});

console.log('limitsForMode');
ok('dispatch -> 0 (limitsiz)', () => {
  assert.deepStrictEqual(p.limitsForMode('dispatch', cfg), { perHour: 0, perDay: 0 });
});
ok('noma`lum rejim -> quote limiti', () => {
  assert.deepStrictEqual(
    p.limitsForMode('xayoliy', cfg),
    { perHour: 5, perDay: 20 },
  );
});

console.log('shouldSendDigest');
ok('1 ta talab uchun dayjest yuborilmaydi', () => {
  assert.strictEqual(p.shouldSendDigest(1, null, cfg, kunduzi), false);
});
ok('2 ta talab + oldin yuborilmagan -> yuboriladi', () => {
  assert.strictEqual(p.shouldSendDigest(2, null, cfg, kunduzi), true);
});
ok('3 soat o`tmagan -> kutadi', () => {
  const last = new Date(kunduzi.getTime() - 60 * 60 * 1000);
  assert.strictEqual(p.shouldSendDigest(5, last, cfg, kunduzi), false);
});
ok('3 soat o`tdi -> yuboriladi', () => {
  const last = new Date(kunduzi.getTime() - 181 * 60 * 1000);
  assert.strictEqual(p.shouldSendDigest(5, last, cfg, kunduzi), true);
});
ok('dayjest o`chirilgan bo`lsa yuborilmaydi', () => {
  const off = JSON.parse(JSON.stringify(cfg));
  off.push.digest.enabled = false;
  assert.strictEqual(p.shouldSendDigest(10, null, off, kunduzi), false);
});
ok('massiv ham, son ham qabul qiladi', () => {
  assert.strictEqual(p.shouldSendDigest(['a', 'b'], null, cfg, kunduzi), true);
});

console.log('MAXFIYLIK — push matni');
ok('aniq manzil va telefon push matnida YO`Q', () => {
  const t = p.buildPushText({
    mode: 'dispatch',
    categoryName: 'Santexnik',
    districtName: 'Urganch',
    landmark: 'Al-Xorazmiy atrofi',
    distanceKm: 1.4,
  });
  const matn = `${t.title} ${t.body}`;
  assert.ok(!/\+?998\d{9}/.test(matn), 'telefon raqami chiqib ketdi');
  assert.ok(/Urganch/.test(matn));
  assert.ok(/1\.4 km/.test(matn));
});
ok('buildPushText `addressText`ni UMUMAN qabul qilmaydi', () => {
  // Interfeys darajasidagi himoya: tasodifan aniq manzilni uzatib
  // bo'lmaydi, chunki funksiya bunday maydonni bilmaydi.
  const t = p.buildPushText({
    mode: 'quote',
    categoryName: 'Elektrik',
    addressText: 'Al-Xorazmiy ko`chasi 15-uy, 3-xonadon',
  });
  assert.ok(!/15-uy/.test(`${t.title} ${t.body}`));
});
ok('dispatch va quote matnlari farq qiladi', () => {
  const d = p.buildPushText({ mode: 'dispatch', categoryName: 'Kuryer' });
  const qt = p.buildPushText({ mode: 'quote', categoryName: 'Kuryer' });
  assert.notStrictEqual(d.title, qt.title);
  assert.ok(/qabul/i.test(d.title));
  assert.ok(/taklif/i.test(qt.title));
});
ok('«yo`lingiz ustida» chetlashish bilan', () => {
  const t = p.buildPushText({ mode: 'quote', categoryName: 'Posilka', detourKm: 2.1 });
  assert.ok(/\+2\.1 km/.test(t.body), t.body);
});
ok('buildDigestText son bilan', () => {
  const t = p.buildDigestText(7, 'Xizmat');
  assert.ok(/7 ta/.test(t.body), t.body);
});

console.log('qaror tartibi');
ok('qarorlar ketma-ketligi: log -> kill -> optOut -> seen -> token', () => {
  // Bir vaqtda bir nechta sabab bo'lsa, eng kuchlisi qaytishi kerak,
  // aks holda analitikada sabablar aralashib ketadi.
  const r = p.decidePush({
    mode: 'quote',
    config: cfg,
    pushEnabled: false,
    provider: provider({ moduleOptOut: true, hasToken: false }),
    alreadyLogged: true,
    alreadySeen: true,
    now: kechasi,
  });
  assert.strictEqual(r.reason, p.REASON.ALREADY_SENT);
});

console.log(`\n${passed} test o'tdi.`);
