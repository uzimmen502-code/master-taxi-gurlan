/**
 * «Туғилган кунингизни киритинг» пуш (4 кун + ҳар якшанба) — тоза функциялар (эга 2026-11-28).  node test/birthday_prompt_pure.test.js
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

check('B3 юбориш ойнаси: ҲАР КУНИ 08:00–19:59 Тошкент (эга: «соат 8:00 - 20:00 гача»; чегаралар); якшанба аниқлаш', () => {
  assert.ok(b.inSendWindow(tash('2026-11-29', 8, 0)));
  assert.ok(b.inSendWindow(tash('2026-11-29', 19, 59)));
  assert.ok(!b.inSendWindow(tash('2026-11-29', 7, 59)));
  assert.ok(!b.inSendWindow(tash('2026-11-29', 20, 0)));
  assert.ok(!b.inSendWindow(tash('2026-11-29', 23, 0)));
  assert.ok(!b.inSendWindow(Date.UTC(2026, 10, 29, 2, 59))); // UTC 02:59 = Тошкент 07:59
  assert.ok(b.inSendWindow(Date.UTC(2026, 10, 29, 3, 0))); // UTC 03:00 = Тошкент 08:00
  assert.ok(!b.inSendWindow(Date.UTC(2026, 10, 29, 15, 0))); // UTC 15:00 = Тошкент 20:00
  assert.ok(b.inSendWindow(tash('2026-11-28', 12, 0))); // шанба — энди ҳам
  assert.ok(b.inSendWindow(tash('2026-11-30', 12, 0))); // душанба — энди ҳам
  assert.ok(!b.inSendWindow(tash('2026-11-30', 3, 0))); // кечаси — йўқ
  assert.strictEqual(b.SCHEDULE, '*/10 8-19 * * *'); // 20:00 ва ундан кейин чақирув йўқ
  assert.ok(b.isSundayKey('2026-11-29') && b.isSundayKey('2026-12-06'));
  assert.ok(!b.isSundayKey('2026-11-30') && !b.isSundayKey('2026-12-05') && !b.isSundayKey('bad'));
  assert.strictEqual(b.dayKeyOfMs(Date.UTC(2026, 10, 29, 19, 0)), '2026-11-30'); // UTC 19:00 = Тошкент эртаси 00:00
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

// claimDecision симуляцияси: ҳар куни бир марта чақирилади (ok бўлса patch ҳолатга қўшилади — транзакциядаги merge каби).
const CFG = { dailyCount: 4, weeklySunday: true };
function simulate(fromKey, days, cfg = CFG, initial = null) {
  let st = initial;
  const log = [];
  for (let i = 0; i < days; i += 1) {
    const day = h.addDays(fromKey, i);
    const dec = b.claimDecision(st, day, b.isoWeekKey(day), cfg);
    if (dec.ok) st = { ...(st || {}), ...dec.patch };
    log.push({ day, ok: dec.ok, kind: dec.kind, reason: dec.reason });
  }
  return { st, log, sentDays: log.filter((x) => x.ok).map((x) => `${x.day}:${x.kind}`) };
}

check('B6 1-фаза: 1–4-кун ҳар куни бир марта (позитив); 5–10-кун — жим (танаффус ичидаги якшанба 12-06 ҳам)', () => {
  // 1-кун — душанба 2026-11-30; 4-кун — пайшанба 12-03; танаффус 12-03+7 = 12-10; биринчи якшанба — 12-13.
  const { st, log } = simulate('2026-11-30', 11);
  assert.deepStrictEqual(log.slice(0, 4).map((x) => [x.ok, x.kind]), [[true, 'daily'], [true, 'daily'], [true, 'daily'], [true, 'daily']]);
  for (const x of log.slice(4, 10)) assert.strictEqual(x.ok, false, x.day);
  assert.strictEqual(log.find((x) => x.day === '2026-12-06').reason, 'PAUSE'); // якшанба, лекин 3 кун ўтди
  assert.strictEqual(log.find((x) => x.day === '2026-12-05').reason, 'NOT_SUNDAY');
  assert.deepStrictEqual([st.phase, st.dailySends, st.dailyDoneDay, st.lastDay], ['weekly', 4, '2026-12-03', '2026-12-03']);
});

check('B7 2-фаза: танаффусдан кейинги биринчи якшанба юборилади, кейин ҳар якшанба, ЧЕГАРАСИЗ (20 ҳафта)', () => {
  const { st, sentDays } = simulate('2026-11-30', 7 * 22);
  assert.deepStrictEqual(sentDays.slice(0, 6), [
    '2026-11-30:daily', '2026-12-01:daily', '2026-12-02:daily', '2026-12-03:daily', '2026-12-13:weekly', '2026-12-20:weekly',
  ]);
  const weekly = sentDays.filter((x) => x.endsWith(':weekly'));
  assert.ok(weekly.length >= 20, String(weekly.length)); // жами чегара йўқ
  for (const x of weekly) assert.ok(b.isSundayKey(x.slice(0, 10)), x);
  assert.strictEqual(st.weeklySends, weekly.length);
  // ISO ҳафта йил чегараси: 2027-01-03 (якшанба, 2026-W53) ва 2027-01-10 (2027-W01) — иккаласи ҳам юборилади
  assert.ok(sentDays.includes('2027-01-03:weekly') && sentDays.includes('2027-01-10:weekly'));
});

check('B8 идемпотентлик/чегара: бир кунда иккинчи марта — ALREADY_TODAY; шу ҳафта иккинчи якшанба — ALREADY_THIS_WEEK; танаффус чегараси 7 кун', () => {
  const d1 = b.claimDecision(null, '2026-11-30', '2026-W49', CFG);
  assert.ok(d1.ok && d1.kind === 'daily' && d1.send === 1);
  assert.deepStrictEqual(b.claimDecision(d1.patch, '2026-11-30', '2026-W49', CFG), { ok: false, reason: 'ALREADY_TODAY' });
  const wk = { phase: 'weekly', dailySends: 4, weeklySends: 1, lastDay: '2026-12-13', lastWeek: '2026-W50', dailyDoneDay: '2026-12-03' };
  assert.deepStrictEqual(b.claimDecision(wk, '2026-12-13', '2026-W50', CFG), { ok: false, reason: 'ALREADY_TODAY' });
  assert.deepStrictEqual(b.claimDecision({ ...wk, lastDay: '2026-12-12' }, '2026-12-13', '2026-W50', CFG), { ok: false, reason: 'ALREADY_THIS_WEEK' });
  // 4-юбориш якшанба 11-29 → 12-06 (роппа-роса 7 кун) — юборилади; 12-06 дан олдин танаффус бўлса — PAUSE
  const sunDone = { phase: 'weekly', dailySends: 4, weeklySends: 0, lastDay: '2026-11-29', dailyDoneDay: '2026-11-29' };
  assert.strictEqual(b.claimDecision(sunDone, '2026-12-06', '2026-W49', CFG).ok, true);
  const satDone = { ...sunDone, lastDay: '2026-11-30', dailyDoneDay: '2026-11-30' };
  assert.deepStrictEqual(b.claimDecision(satDone, '2026-12-06', '2026-W49', CFG), { ok: false, reason: 'PAUSE' });
  assert.strictEqual(b.claimDecision(satDone, '2026-12-13', '2026-W50', CFG).ok, true);
  // weeklySunday = false — 2-фаза йўқ
  assert.deepStrictEqual(b.claimDecision(sunDone, '2026-12-06', '2026-W49', { dailyCount: 4, weeklySunday: false }), { ok: false, reason: 'WEEKLY_OFF' });
  // dailyCount чегаралари: 1 — биринчи юборишдан кейин дарҳол 2-фаза; 14 — 14 кун
  assert.strictEqual(b.claimDecision(null, '2026-11-30', '2026-W49', { dailyCount: 1, weeklySunday: true }).patch.phase, 'weekly');
  assert.strictEqual(simulate('2026-11-30', 16, { dailyCount: 14, weeklySunday: true }).sentDays.filter((x) => x.endsWith(':daily')).length, 14);
  // фаза қайтмас: админ 4 → 6 қилса ҳам 2-фазадаги фойдаланувчи кунлик фазага қайтмайди
  assert.deepStrictEqual(b.claimDecision(wk, '2026-12-14', '2026-W51', { dailyCount: 6, weeklySunday: true }), { ok: false, reason: 'NOT_SUNDAY' });
  // админ 4 → 2 қилса: кунлик фазада 2 та юборган — 2-фазага ўтади, танаффус охирги юборишдан
  const two = { phase: 'daily', dailySends: 2, lastDay: '2026-12-01' };
  assert.deepStrictEqual(b.claimDecision(two, '2026-12-06', '2026-W49', { dailyCount: 2, weeklySunday: true }), { ok: false, reason: 'PAUSE' });
  assert.strictEqual(b.claimDecision(two, '2026-12-13', '2026-W50', { dailyCount: 2, weeklySunday: true }).patch.dailyDoneDay, '2026-12-01');
});

check('B8a эски ҳолат шакли {sends, lastWeek, lastAt}: юмшоқ ўқилади (26-банд)', () => {
  const lastAt = { toMillis: () => tash('2026-11-29', 12, 0) }; // эски ҳафталик юбориш — якшанба 11-29
  const n = b.normalizeState({ sends: 2, lastWeek: '2026-W48', firstAt: lastAt, lastAt });
  assert.deepStrictEqual(n, { legacy: true, phase: 'daily', dailySends: 2, weeklySends: 0, lastDay: '2026-11-29', lastWeek: '2026-W48', dailyDoneDay: null });
  // ўша куни — иккинчи марта йўқ; эртасига — 3-кунлик юбориш
  assert.deepStrictEqual(b.claimDecision({ sends: 2, lastWeek: '2026-W48', lastAt }, '2026-11-29', '2026-W48', CFG), { ok: false, reason: 'ALREADY_TODAY' });
  const d = b.claimDecision({ sends: 2, lastWeek: '2026-W48', lastAt }, '2026-11-30', '2026-W49', CFG);
  assert.ok(d.ok && d.kind === 'daily' && d.patch.dailySends === 3);
  // эски 4 та юборилган — 2-фаза; танаффус lastAt дан (11-29 + 7 = 12-06)
  const old4 = { sends: 4, lastWeek: '2026-W48', lastAt };
  assert.deepStrictEqual(b.claimDecision(old4, '2026-12-01', '2026-W49', CFG), { ok: false, reason: 'NOT_SUNDAY' });
  assert.strictEqual(b.claimDecision(old4, '2026-12-06', '2026-W49', CFG).kind, 'weekly');
  // lastAt йўқ (бузуқ) — фақат lastWeek ҳимояси
  assert.deepStrictEqual(b.claimDecision({ sends: 4, lastWeek: '2026-W49' }, '2026-12-06', '2026-W49', CFG), { ok: false, reason: 'ALREADY_THIS_WEEK' });
  // бузуқ/бўш ҳолат — янги фойдаланувчи
  assert.strictEqual(b.claimDecision({ sends: 'x' }, '2026-11-30', '2026-W49', CFG).send, 1);
  assert.strictEqual(b.claimDecision('junk', '2026-11-30', '2026-W49', CFG).send, 1);
});

check('B8b созлама валидацияси: dailyCount 1..14, weeklySunday boolean, эски maxSends — номаълум калит', () => {
  const ok = { stage: 'internal', internalPhones: [P], pilotDistrictIds: [], dailyCount: 4, weeklySunday: true };
  assert.ok(b.validateSettings(ok).ok);
  assert.ok(b.validateSettings({ ...ok, dailyCount: 1 }).ok);
  assert.ok(b.validateSettings({ ...ok, dailyCount: 14, weeklySunday: false }).ok);
  assert.ok(!b.validateSettings({ ...ok, dailyCount: 0 }).ok);
  assert.ok(!b.validateSettings({ ...ok, dailyCount: 15 }).ok);
  assert.ok(!b.validateSettings({ ...ok, dailyCount: 2.5 }).ok);
  assert.ok(!b.validateSettings({ ...ok, weeklySunday: 'yes' }).ok);
  assert.ok(!b.validateSettings({ stage: 'internal', internalPhones: [P], pilotDistrictIds: [], dailyCount: 4 }).ok); // weeklySunday шарт
  assert.ok(!b.validateSettings({ ...ok, maxSends: 4 }).ok);
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

check('B8c сақланган ҳужжат: йўқ = OFF, сукут dailyCount 4 / weeklySunday true; эски maxSends эътиборсиз; бузуқ ташланади', () => {
  assert.deepStrictEqual(b.normalizeSettings(undefined), { stage: 'off', internalPhones: [], pilotDistrictIds: [], dailyCount: 4, weeklySunday: true, version: 0 });
  const n = b.normalizeSettings({ stage: 'public', internalPhones: [P, 'bad'], pilotDistrictIds: ['gurlan', 'X!'], dailyCount: 99, weeklySunday: 'x', maxSends: 2, version: 3 });
  assert.deepStrictEqual(n, { stage: 'public', internalPhones: [P], pilotDistrictIds: ['gurlan'], dailyCount: 4, weeklySunday: true, version: 3 });
  assert.strictEqual(b.normalizeSettings({ stage: 'public', weeklySunday: false }).weeklySunday, false);
  assert.strictEqual(b.normalizeSettings({ stage: 'weird' }).stage, 'off');
  assert.strictEqual(b.LIMITS.reasonMax, 300); // аввал изоҳ ичида қолиб кетган эди (undefined)
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
