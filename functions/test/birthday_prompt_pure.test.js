/**
 * «Туғилган кунингизни киритинг» ҳафталик пуш — тоза функциялар (эга 2026-11-28).  node test/birthday_prompt_pure.test.js
 */
'use strict';
const assert = require('assert');
const b = require('../birthday_prompt');
const h = require('../holiday');

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`); }
};
const tash = (key, hh, mm = 0) => h.startOfKeyMs(key) + hh * 3600000 + mm * 60000;
const P = '998912000001';

check('B1 ISO ҳафта: оддий, йил чегараси (2026 — 53 ҳафта), душанба/якшанба', () => {
  assert.strictEqual(b.isoWeekKey('2026-11-23'), '2026-W48'); // душанба
  assert.strictEqual(b.isoWeekKey('2026-11-29'), '2026-W48'); // якшанба — ўша ҳафта
  assert.strictEqual(b.isoWeekKey('2026-11-30'), '2026-W49');
  assert.strictEqual(b.isoWeekKey('2026-12-31'), '2026-W53');
  assert.strictEqual(b.isoWeekKey('2027-01-03'), '2026-W53'); // якшанба, ҳафта йили — 2026
  assert.strictEqual(b.isoWeekKey('2027-01-04'), '2027-W01');
  assert.strictEqual(b.isoWeekKey('2025-12-29'), '2026-W01'); // душанба, ҳафта йили — 2026
  assert.strictEqual(b.isoWeekKey('2027-02-29'), null);
  assert.strictEqual(b.isoWeekKey('x'), null);
});

check('B2 ҳафта Тошкент вақтида: якшанба 23:59 Тошкент — ўша ҳафта; душанба 00:00 — кейинги', () => {
  assert.strictEqual(b.weekKeyOfMs(tash('2026-11-29', 23, 59)), '2026-W48');
  assert.strictEqual(b.weekKeyOfMs(tash('2026-11-30', 0, 0)), '2026-W49');
  assert.strictEqual(b.weekKeyOfMs(Date.UTC(2026, 10, 29, 19, 0)), '2026-W49'); // UTC 19:00 якшанба = Тошкент душанба 00:00
});

check('B3 юбориш ойнаси: якшанба 11:00–18:59 Тошкент (чегаралар)', () => {
  assert.ok(b.inSendWindow(tash('2026-11-29', 11, 0)));
  assert.ok(b.inSendWindow(tash('2026-11-29', 18, 59)));
  assert.ok(!b.inSendWindow(tash('2026-11-29', 10, 59)));
  assert.ok(!b.inSendWindow(tash('2026-11-29', 19, 0)));
  assert.ok(!b.inSendWindow(tash('2026-11-28', 12, 0))); // шанба
  assert.ok(!b.inSendWindow(tash('2026-11-30', 12, 0))); // душанба
});

check('B4 туғилган сана бор/йўқ — клиент birthDatePromptVisibleFor билан бир хил қоида', () => {
  for (const v of [undefined, null, '', '   ']) assert.strictEqual(b.hasBirthDate(v), false, String(v));
  for (const v of ['1990-07-10', '10.7.1990', 'x', { toMillis: () => 0 }]) assert.strictEqual(b.hasBirthDate(v), true);
});

check('B5 номзод сабаблари: позитив + ҳар бир негатив', () => {
  const ok = { fcmToken: 'tok', appLang: 'ru' };
  assert.strictEqual(b.skipReasonOf(P, ok), null);
  assert.strictEqual(b.skipReasonOf(P, { ...ok, holidayRemindersOptIn: true }), null);
  assert.strictEqual(b.skipReasonOf('912000001', ok), 'NOT_CANONICAL'); // эски 9 хонали ҳужжат — push у ерга бормайди
  assert.strictEqual(b.skipReasonOf('demo_user', ok), 'NOT_CANONICAL');
  assert.strictEqual(b.skipReasonOf(P, { ...ok, birthDate: '1990-07-10' }), 'HAS_BIRTHDATE');
  assert.strictEqual(b.skipReasonOf(P, { ...ok, birthDate: '  ' }), null);
  assert.strictEqual(b.skipReasonOf(P, { ...ok, deletion: { status: 'PENDING' } }), 'DELETION');
  assert.strictEqual(b.skipReasonOf(P, { ...ok, deleted: true }), 'DELETION');
  assert.strictEqual(b.skipReasonOf(P, { ...ok, holidayRemindersOptIn: false }), 'OPTED_OUT');
  assert.strictEqual(b.skipReasonOf(P, { appLang: 'ru' }), 'NO_TOKEN');
  assert.strictEqual(b.skipReasonOf(P, { fcmToken: ' ' }), 'NO_TOKEN');
  assert.strictEqual(b.skipReasonOf(P, null), 'NO_TOKEN');
});

check('B6 идемпотентлик ва чегара: шу ҳафта — бир марта; N-чи юборишдан кейин тўхтайди (чегара N)', () => {
  assert.deepStrictEqual(b.claimDecision(null, '2026-W48', 4), { ok: true, sends: 1 });
  assert.deepStrictEqual(b.claimDecision({ sends: 1, lastWeek: '2026-W48' }, '2026-W48', 4), { ok: false, reason: 'ALREADY_THIS_WEEK' });
  assert.deepStrictEqual(b.claimDecision({ sends: 3, lastWeek: '2026-W47' }, '2026-W48', 4), { ok: true, sends: 4 });
  assert.deepStrictEqual(b.claimDecision({ sends: 4, lastWeek: '2026-W47' }, '2026-W48', 4), { ok: false, reason: 'CAP_REACHED' });
  assert.deepStrictEqual(b.claimDecision({ sends: 4, lastWeek: '2026-W47' }, '2026-W48', 5), { ok: true, sends: 5 }); // админ чегарани оширди
  assert.deepStrictEqual(b.claimDecision({ sends: 'x' }, '2026-W48', 1), { ok: true, sends: 1 }); // бузуқ ҳолат — 0 деб
});

check('B7 созлама валидацияси: тўғри, номаълум калит, босқич, телефон, туман, чегара (1..12), пилот бўш', () => {
  const ok = { stage: 'internal', internalPhones: [P], pilotDistrictIds: [], maxSends: 4 };
  assert.ok(b.validateSettings(ok).ok);
  assert.ok(b.validateSettings({ ...ok, maxSends: 1 }).ok);
  assert.ok(b.validateSettings({ ...ok, maxSends: 12 }).ok);
  assert.ok(!b.validateSettings({ ...ok, maxSends: 0 }).ok);
  assert.ok(!b.validateSettings({ ...ok, maxSends: 13 }).ok);
  assert.ok(!b.validateSettings({ ...ok, maxSends: 2.5 }).ok);
  assert.ok(!b.validateSettings({ ...ok, stage: 'on' }).ok);
  assert.ok(!b.validateSettings({ ...ok, extra: 1 }).ok);
  assert.ok(!b.validateSettings({ ...ok, internalPhones: ['912000001'] }).ok);
  assert.ok(!b.validateSettings({ ...ok, internalPhones: [P, P] }).ok);
  assert.ok(!b.validateSettings({ ...ok, internalPhones: Array.from({ length: 51 }, (_, i) => `998900${String(i).padStart(6, '0')}`) }).ok);
  assert.ok(!b.validateSettings({ ...ok, pilotDistrictIds: ['Gurlan!'] }).ok);
  assert.ok(!b.validateSettings({ ...ok, pilotDistrictIds: Array.from({ length: 31 }, (_, i) => `d${i}x`) }).ok);
  assert.ok(!b.validateSettings({ ...ok, stage: 'pilot', internalPhones: [] }).ok);
  assert.ok(b.validateSettings({ ...ok, stage: 'pilot', internalPhones: [], pilotDistrictIds: ['gurlan'] }).ok);
  assert.ok(!b.validateSettings(null).ok);
});

check('B8 сақланган ҳужжат: йўқ = OFF, сукут maxSends = 4 (PROPOSED), бузуқ қийматлар ташланади', () => {
  assert.deepStrictEqual(b.normalizeSettings(undefined), { stage: 'off', internalPhones: [], pilotDistrictIds: [], maxSends: 4, version: 0 });
  const n = b.normalizeSettings({ stage: 'public', internalPhones: [P, 'bad'], pilotDistrictIds: ['gurlan', 'X!'], maxSends: 99, version: 3 });
  assert.deepStrictEqual(n, { stage: 'public', internalPhones: [P], pilotDistrictIds: ['gurlan'], maxSends: 4, version: 3 });
  assert.strictEqual(b.normalizeSettings({ stage: 'weird' }).stage, 'off');
});

check('B9 матн: 3 тил, uz_Latn янги ҳарфлар (ğ, ç), номаълум тил — uz_Cyrl', () => {
  for (const l of ['uz_Cyrl', 'uz_Latn', 'ru']) {
    const t = b.PROMPT_TEXT[l];
    assert.ok(t.title.trim() && t.body.trim() && t.title.length <= 80 && t.body.length <= 120, l);
  }
  assert.ok(/ğ/.test(b.PROMPT_TEXT.uz_Latn.title) && /ç/.test(b.PROMPT_TEXT.uz_Latn.body));
  assert.ok(!/[og][''ʻ]/i.test(`${b.PROMPT_TEXT.uz_Latn.title} ${b.PROMPT_TEXT.uz_Latn.body}`)); // эски o'/g' ёзуви йўқ
  assert.strictEqual(b.promptTextFor('xx'), b.PROMPT_TEXT.uz_Cyrl);
  assert.strictEqual(b.promptTextFor('ru'), b.PROMPT_TEXT.ru);
  assert.strictEqual(b.PROMPT_TEXT.uz_Cyrl.title, 'Туғилган кунингизни киритинг');
});

(async () => {
  let active = 0;
  let peak = 0;
  const seen = [];
  await b.mapPool(Array.from({ length: 53 }, (_, i) => i), 7, async (x) => {
    active += 1; peak = Math.max(peak, active);
    await new Promise((r) => setTimeout(r, 1));
    seen.push(x); active -= 1;
  });
  try {
    assert.strictEqual(seen.length, 53);
    assert.deepStrictEqual([...seen].sort((a, c) => a - c), Array.from({ length: 53 }, (_, i) => i));
    assert.ok(peak <= 7 && peak > 1);
    await b.mapPool([], 5, async () => { throw new Error('чақирилмасин'); });
    results.push(true); console.log('PASS - B10 mapPool: 53 элемент, параллеллик ≤ 7, бўш рўйхат');
  } catch (e) { results.push(false); console.log(`FAIL - B11 mapPool :: ${e.message}`); }
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})();
