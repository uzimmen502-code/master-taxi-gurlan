/**
 * «Туғилган кунингизни киритинг» пуш (4 кун кунига бир марта → 7 кун танаффус → ҳар якшанба) — scheduler + админ
 * callable, ҲАҚИҚИЙ index.js + маҳаллий attach (сохта вақт, хабарларни йиғиш), Firestore Emulator. Эга 2026-11-28.
 *
 *   firebase emulators:exec --only firestore --project demo-bday-prompt "node test/birthday_prompt_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-bday-prompt';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const fns = require('../index');
const admin = require('firebase-admin');
const functions = require('firebase-functions');
const b = require('../birthday_prompt');
const h = require('../holiday');

const db = admin.firestore();
const ADMIN = '998915000001';
const T1 = '998912000001'; // тестер, санаси йўқ — юборилади
const T2 = '998912000002'; // тестер, санаси бор
const T3 = '998912000003'; // тестер, токени йўқ
const U4 = '998912000004'; // тестер эмас, санаси йўқ
const U5 = '998912000005'; // opt-out
const U6 = '998912000006'; // ўчирилиш навбатида
const U7 = '998912000007'; // санаси йўқ (''), бошқа туман
const LEGACY = '912000008'; // эски 9 хонали ҳужжат
const O9 = '998912000009'; // эски ҳолат шакли, 4 та юборилган
const O10 = '998912000010'; // эски ҳолат шакли, 1 та юборилган
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const call = (name, data, who) => fns[name].run(data, who ? ctxOf(who) : {});

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`); }
};
async function expectCode(promise, code) {
  await assert.rejects(promise, (e) => { assert.strictEqual((e.details && e.details.code) || e.message, code); return true; });
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const get = async (p) => (await db.doc(p).get()).data();

// 1-кун — душанба 2026-11-30 12:00 Тошкент. at('2026-12-13') — шу кун 12:00.
const at = (key, hh = 12) => h.startOfKeyMs(key) + hh * 3600000;
let fakeNow = at('2026-11-30');
const sent = [];
let notifyFail = false;
const local = {};
const api = b.attachBirthdayPrompt(local, {
  functions, db, admin, nowMs: () => fakeNow,
  requireCallerRoles: async () => '0',
  notifyUserInApp: async (m) => { if (notifyFail) throw new Error('boom'); sent.push(m); },
});
const run = (o = {}) => api.runBirthdayPrompt({ pageSize: 2, ...o });
const sentTo = () => sent.map((m) => m.userId).sort();
const runOn = async (key, o) => { fakeNow = at(key); sent.length = 0; return run(o); };
const S0 = { stage: 'internal', internalPhones: [T1, T2, T3], pilotDistrictIds: [], dailyCount: 4, weeklySunday: true };
const setSettings = (s) => call('adminSetBirthdayPromptSettings', { settings: s }, ADMIN);

async function seedUsers() {
  await db.doc(`users/${ADMIN}`).set({ role: 'admin', birthDate: '1980-01-01', fcmToken: 'tA' });
  await db.doc(`users/${T1}`).set({ role: 'user', districtId: 'gurlan', fcmToken: 't1', appLang: 'uz_Latn' });
  await db.doc(`users/${T2}`).set({ role: 'user', districtId: 'gurlan', fcmToken: 't2', birthDate: '1990-07-10' });
  await db.doc(`users/${T3}`).set({ role: 'user', districtId: 'gurlan' });
  await db.doc(`users/${U4}`).set({ role: 'user', districtId: 'gurlan', fcmToken: 't4', appLang: 'ru' });
  await db.doc(`users/${U5}`).set({ role: 'user', districtId: 'gurlan', fcmToken: 't5', holidayRemindersOptIn: false });
  await db.doc(`users/${U6}`).set({ role: 'user', districtId: 'gurlan', fcmToken: 't6', deletion: { status: 'PENDING' } });
  await db.doc(`users/${U7}`).set({ role: 'user', districtId: 'urganch', fcmToken: 't7', birthDate: '' });
  await db.doc(`users/${LEGACY}`).set({ role: 'user', districtId: 'gurlan', fcmToken: 't8' });
}

async function main() {
  await clearEmulator();
  await seedUsers();

  await check('C0 index.js: birthdayPromptDaily, adminGet/SetBirthdayPromptSettings уланган; эски birthdayPromptWeekly йўқ', async () => {
    for (const n of ['birthdayPromptDaily', 'adminGetBirthdayPromptSettings', 'adminSetBirthdayPromptSettings']) assert.ok(fns[n], n);
    assert.strictEqual(fns.birthdayPromptWeekly, undefined);
  });

  await check('C1 созлама йўқ = OFF: ҳеч нарса юборилмайди, run ҳужжати ёзилмайди', async () => {
    const r = await run();
    assert.strictEqual(r.reason, 'STAGE_OFF');
    assert.strictEqual(sent.length, 0);
    assert.strictEqual((await db.collection('birthday_prompt_runs').get()).size, 0);
  });

  await check('C2 админ: рухсатсиз — PERMISSION_DENIED; dailyCount 0/15, эски maxSends — SETTINGS_INVALID; тўғри — версия 1 + admin_audit', async () => {
    await expectCode(call('adminSetBirthdayPromptSettings', { settings: S0 }, U4), 'PERMISSION_DENIED');
    await expectCode(call('adminSetBirthdayPromptSettings', { settings: { ...S0, dailyCount: 0 } }, ADMIN), 'SETTINGS_INVALID');
    await expectCode(call('adminSetBirthdayPromptSettings', { settings: { ...S0, dailyCount: 15 } }, ADMIN), 'SETTINGS_INVALID');
    await expectCode(call('adminSetBirthdayPromptSettings', { settings: { ...S0, maxSends: 4 } }, ADMIN), 'SETTINGS_INVALID');
    await expectCode(call('adminSetBirthdayPromptSettings', { settings: { ...S0, weeklySunday: 1 } }, ADMIN), 'SETTINGS_INVALID');
    await expectCode(call('adminSetBirthdayPromptSettings', { settings: { ...S0, internalPhones: ['912000001'] } }, ADMIN), 'SETTINGS_INVALID');
    const r = await call('adminSetBirthdayPromptSettings', { settings: S0, expectedVersion: 0, reason: 'синов' }, ADMIN);
    assert.deepStrictEqual([r.changed, r.version], [true, 1]);
    assert.strictEqual((await setSettings(S0)).changed, false);
    await expectCode(call('adminSetBirthdayPromptSettings', { settings: { ...S0, dailyCount: 5 }, expectedVersion: 0 }, ADMIN), 'VERSION_CONFLICT');
    const au = (await db.collection('admin_audit').where('kind', '==', 'birthday_prompt_settings').get()).docs.map((d) => d.data());
    assert.strictEqual(au.length, 1);
    assert.strictEqual(au[0].before, null);
    assert.deepStrictEqual([au[0].after.stage, au[0].after.dailyCount, au[0].after.weeklySunday, au[0].reason], ['internal', 4, true, 'синов']);
    const g = await call('adminGetBirthdayPromptSettings', {}, ADMIN);
    assert.deepStrictEqual([g.settings.stage, g.settings.dailyCount, g.settings.weeklySunday, g.settings.version], ['internal', 4, true, 1]);
    assert.strictEqual(g.settings.maxSends, undefined);
    assert.deepStrictEqual([g.defaults.dailyCount, g.defaults.weeklySunday, g.defaults.pauseDays, g.defaults.dailyCountMax], [4, true, 7, 14]);
    await expectCode(call('adminGetBirthdayPromptSettings', {}, U4), 'PERMISSION_DENIED');
  });

  await check('C3 ойнадан ташқари (07:59 ва 20:00 Тошкент; эга: «соат 8:00 - 20:00 гача») — юборилмайди', async () => {
    sent.length = 0;
    for (const ms of [at('2026-11-30', 8) - 60000, at('2026-11-30', 20), at('2026-11-30', 3)]) {
      fakeNow = ms;
      assert.strictEqual((await run()).reason, 'OUT_OF_WINDOW');
    }
    assert.strictEqual(sent.length, 0);
    assert.strictEqual((await db.collection('birthday_prompt_runs').get()).size, 0);
  });

  await check('C4 1-кун (душанба) internal: фақат T1; санаси бор/токенсиз — йўқ; тил uz_Latn; ҳолат phase=daily, dailySends=1', async () => {
    const r = await runOn('2026-11-30');
    assert.strictEqual(r.result, 'ok');
    assert.strictEqual(r.done, true);
    assert.deepStrictEqual(sentTo(), [T1]);
    const m = sent[0];
    assert.strictEqual(m.title, b.PROMPT_TEXT.uz_Latn.title);
    assert.strictEqual(m.body, b.PROMPT_TEXT.uz_Latn.body);
    assert.deepStrictEqual([m.source, m.dataType, m.screen], ['birthday_prompt', 'birthday_prompt', 'user_info']);
    assert.deepStrictEqual(m.extraData, { promptDay: '2026-11-30', promptPhase: 'daily' });
    assert.strictEqual(m.extraNews.promptSend, 1);
    assert.strictEqual(m.newsDocId, `birthday_prompt_${T1}`); // эга 2026-11-28: фақат охирги эслатма
    assert.strictEqual(r.HAS_BIRTHDATE, 1);
    assert.strictEqual(r.NO_TOKEN, 1);
    const st = await get(`birthday_prompt_state/${T1}`);
    assert.deepStrictEqual([st.phase, st.dailySends, st.lastDay], ['daily', 1, '2026-11-30']);
    assert.ok(st.firstSentAt && st.lastAt);
    const runDoc = await get('birthday_prompt_runs/2026-11-30_internal');
    assert.deepStrictEqual([runDoc.done, runDoc.day, runDoc.week, runDoc.stats.sent, runDoc.stats.sentDaily], [true, '2026-11-30', '2026-W49', 1, 1]);
    assert.strictEqual(runDoc.leaseUntil, undefined);
  });

  await check('C5 бир кунда иккинчи юбориш тўсилган: қайта чақирув — DONE; run ўчирилса ҳам (retry) — ALREADY_TODAY', async () => {
    assert.strictEqual((await run()).reason, 'DONE');
    await db.doc('birthday_prompt_runs/2026-11-30_internal').delete();
    sent.length = 0;
    const r = await run();
    assert.strictEqual(r.ALREADY_TODAY, 1);
    assert.strictEqual(sent.length, 0);
    assert.strictEqual((await get(`birthday_prompt_state/${T1}`)).dailySends, 1);
  });

  await check('C6 2-кун: параллел икки чақирув (lease + транзакция) — битта юбориш', async () => {
    fakeNow = at('2026-12-01');
    sent.length = 0;
    const [a, c] = await Promise.all([run(), run()]);
    assert.strictEqual(sent.length, 1, JSON.stringify([a, c]));
    assert.strictEqual((await get(`birthday_prompt_state/${T1}`)).dailySends, 2);
  });

  await check('C7 3–4-кун юборилади; 5–10-кун (12-04…12-09) жим, танаффус ичидаги якшанба 12-06 — PAUSE', async () => {
    for (const d of ['2026-12-02', '2026-12-03']) { await runOn(d); assert.deepStrictEqual(sentTo(), [T1], d); }
    const st = await get(`birthday_prompt_state/${T1}`);
    assert.deepStrictEqual([st.phase, st.dailySends, st.dailyDoneDay], ['weekly', 4, '2026-12-03']);
    const reasons = {};
    for (const d of ['2026-12-04', '2026-12-05', '2026-12-06', '2026-12-07', '2026-12-08', '2026-12-09']) {
      const r = await runOn(d);
      assert.strictEqual(sent.length, 0, d);
      reasons[d] = r.PAUSE ? 'PAUSE' : r.NOT_SUNDAY ? 'NOT_SUNDAY' : '?';
    }
    assert.strictEqual(reasons['2026-12-06'], 'PAUSE');
    assert.strictEqual(reasons['2026-12-05'], 'NOT_SUNDAY');
  });

  await check('C8 танаффусдан кейинги биринчи якшанба (12-13) — юборилади; шу куни қайта — йўқ; душанба — йўқ; кейинги якшанба — яна', async () => {
    assert.deepStrictEqual(sentTo(), []);
    let r = await runOn('2026-12-10');
    assert.strictEqual(sent.length, 0);
    r = await runOn('2026-12-13');
    assert.deepStrictEqual(sentTo(), [T1]);
    assert.deepStrictEqual(sent[0].extraData, { promptDay: '2026-12-13', promptPhase: 'weekly' });
    assert.strictEqual(r.sentWeekly, 1);
    await db.doc('birthday_prompt_runs/2026-12-13_internal').delete();
    fakeNow = at('2026-12-13', 19) + 59 * 60000; // 19:59 — ойна ичида, лекин шу куни иккинчи марта йўқ
    sent.length = 0;
    r = await run();
    assert.strictEqual(sent.length, 0);
    assert.strictEqual(r.ALREADY_TODAY, 1);
    await runOn('2026-12-14');
    assert.strictEqual(sent.length, 0);
    await runOn('2026-12-20');
    assert.deepStrictEqual(sentTo(), [T1]);
    const st = await get(`birthday_prompt_state/${T1}`);
    assert.deepStrictEqual([st.phase, st.dailySends, st.weeklySends, st.lastWeek], ['weekly', 4, 2, '2026-W51']);
  });

  await check('C9 public: бутун users саҳифалаб (pageSize 2); T1 — ҳафталик, U4/U7 — 1-кунлик; opt-out/ўчирилиш/9 хонали/токенсиз — йўқ', async () => {
    await setSettings({ ...S0, stage: 'public', internalPhones: [] });
    const r = await runOn('2026-12-27'); // якшанба
    assert.strictEqual(r.done, true);
    assert.deepStrictEqual(sentTo(), [T1, U4, U7].sort());
    assert.deepStrictEqual([r.sentWeekly, r.sentDaily], [1, 2]);
    assert.strictEqual(r.scanned, 9);
    assert.strictEqual(r.OPTED_OUT, 1);
    assert.strictEqual(r.DELETION, 1);
    assert.strictEqual(r.NOT_CANONICAL, 1);
    assert.strictEqual(r.NO_TOKEN, 1);
    assert.strictEqual(sent.find((m) => m.userId === U4).title, b.PROMPT_TEXT.ru.title);
    assert.ok((await get('birthday_prompt_runs/2026-12-27_public')).cursor);
  });

  await check('C10 сана киритилгач тўхтайди: U4 сана киритди — эртасига йўқ; U7 — 2-кунлик; T1 (душанба) — йўқ', async () => {
    await db.doc(`users/${U4}`).update({ birthDate: '1995-03-08' });
    const r = await runOn('2026-12-28');
    assert.deepStrictEqual(sentTo(), [U7]);
    assert.strictEqual(r.HAS_BIRTHDATE, 3); // ADMIN, T2, U4
    assert.strictEqual(r.NOT_SUNDAY, 1); // T1
    assert.strictEqual((await get(`birthday_prompt_state/${U7}`)).dailySends, 2);
  });

  await check('C11 рад этиш тўхтатади: U7 holidayRemindersOptIn=false — эртасига ҳеч ким', async () => {
    await db.doc(`users/${U7}`).update({ holidayRemindersOptIn: false });
    const r = await runOn('2026-12-29');
    assert.strictEqual(sent.length, 0);
    assert.strictEqual(r.OPTED_OUT, 2);
  });

  await check('C12 эски ҳолат шакли {sends, lastWeek, lastAt}: 4 та — 2-фаза (сешанба йўқ, якшанба бор); 1 та — 2-кунлик', async () => {
    const lastAt = admin.firestore.Timestamp.fromMillis(at('2026-12-27'));
    await db.doc(`users/${O9}`).set({ role: 'user', fcmToken: 't9' });
    await db.doc(`users/${O10}`).set({ role: 'user', fcmToken: 't10' });
    await db.doc(`birthday_prompt_state/${O9}`).set({ sends: 4, lastWeek: '2026-W52', firstAt: lastAt, lastAt });
    await db.doc(`birthday_prompt_state/${O10}`).set({ sends: 1, lastWeek: '2026-W52', firstAt: lastAt, lastAt });
    await runOn('2026-12-30'); // чоршанба
    assert.deepStrictEqual(sentTo(), [O10]);
    const s10 = await get(`birthday_prompt_state/${O10}`);
    assert.deepStrictEqual([s10.phase, s10.dailySends, s10.lastDay], ['daily', 2, '2026-12-30']);
    assert.strictEqual(s10.firstSentAt.toMillis(), lastAt.toMillis()); // эски firstAt сақланди
    await runOn('2027-01-03'); // якшанба (2026-W53), эски юборишдан 7 кун
    assert.ok(sentTo().includes(O9) && sentTo().includes(T1), JSON.stringify(sentTo()));
    const s9 = await get(`birthday_prompt_state/${O9}`);
    assert.deepStrictEqual([s9.phase, s9.weeklySends, s9.lastWeek, s9.dailyDoneDay], ['weekly', 1, '2026-W53', '2026-12-27']);
  });

  await check('C13 pilot: фақат тестерлар + пилот тумани (urganch); тестер такрори — бир марта', async () => {
    await db.doc(`users/${U7}`).update({ holidayRemindersOptIn: admin.firestore.FieldValue.delete(), birthDate: admin.firestore.FieldValue.delete() });
    await setSettings({ ...S0, stage: 'pilot', internalPhones: [U7], pilotDistrictIds: ['urganch'] });
    const r = await runOn('2027-01-04'); // душанба
    assert.deepStrictEqual(sentTo(), [U7]);
    assert.strictEqual(r.ALREADY_TODAY, 1); // тестер U7 туман сканида яна учради
    assert.strictEqual((await get(`birthday_prompt_state/${U7}`)).dailySends, 3);
  });

  await check('C14 weeklySunday=false: 2-фазадагилар якшанба ҳам олмайди (WEEKLY_OFF), 1-фазадаги давом этади', async () => {
    await setSettings({ ...S0, internalPhones: [T1, U7], weeklySunday: false });
    const r = await runOn('2027-01-10'); // якшанба
    assert.deepStrictEqual(sentTo(), [U7]);
    assert.strictEqual(r.WEEKLY_OFF, 1);
  });

  await check('C15 хабар хатоси: белги олинган (шу куни қайта юборилмайди), NOTIFY_FAILED ҳисобланади, run тугайди', async () => {
    // U7 4-кунлик юборишни 01-10 да олди (2-фаза); U4 — сана ўчирилди, 1-фазада (1/4) давом этади.
    await db.doc(`users/${U4}`).update({ birthDate: admin.firestore.FieldValue.delete() });
    await setSettings({ ...S0, internalPhones: [U4, U7, T1] });
    fakeNow = at('2027-01-11'); // душанба
    notifyFail = true;
    const r = await run();
    notifyFail = false;
    assert.strictEqual(r.NOTIFY_FAILED, 1); // U4 (U7, T1 — душанба, 2-фаза)
    assert.strictEqual(r.NOT_SUNDAY, 2);
    assert.strictEqual(r.done, true);
    const s4 = await get(`birthday_prompt_state/${U4}`);
    assert.deepStrictEqual([s4.lastDay, s4.dailySends], ['2027-01-11', 2]);
    assert.strictEqual((await get(`birthday_prompt_state/${U7}`)).phase, 'weekly');
  });

  await check('C16 lease: бошқа чақирув ишлаётган бўлса (leaseUntil келажакда) — LEASED, ҳеч нарса юборилмайди', async () => {
    fakeNow = at('2027-01-12');
    await db.doc('birthday_prompt_runs/2027-01-12_internal').set({ day: '2027-01-12', stage: 'internal', leaseUntil: admin.firestore.Timestamp.fromMillis(fakeNow + 60000) });
    sent.length = 0;
    assert.strictEqual((await run()).reason, 'LEASED');
    assert.strictEqual(sent.length, 0);
  });

  await check('C17 админ get: охирги тарқатишлар (кун, статистика) қайтади', async () => {
    const g = await call('adminGetBirthdayPromptSettings', {}, ADMIN);
    assert.ok(g.runs.length >= 3);
    assert.ok(g.runs.every((x) => typeof x.day === 'string'));
  });

  await check('C18 ҳар юбориш ўша ID ли ягона ҳужжат (newsDocId) — ҳамма юборишлар бир хил ID', async () => {
    // C4…C15 давомида T1 га бир неча марта юборилди — ҳар сафар ID бир хил.
    sent.length = 0;
    await setSettings({ ...S0, internalPhones: [U4] });
    await runOn('2027-01-13');
    assert.deepStrictEqual(sent.map((m) => m.newsDocId), [`birthday_prompt_${U4}`]);
    assert.strictEqual(b.newsDocIdOf(T1), `birthday_prompt_${T1}`);
  });

  await check('C19 replaceLatestNews: 1-марта яратади (existed=false), кейин ТЎЛИҚ алмаштиради (existed=true): эски майдонлар йўқ, createdAt янги, ҳужжат битта', async () => {
    const { replaceLatestNews, validNewsId } = require('../admin_news_latest');
    const FV = admin.firestore.FieldValue;
    const id = b.newsDocIdOf(U4);
    const base = { title: 'A', body: 'B', category: 'info', audience: 'user', targetUserId: U4, source: 'birthday_prompt', priority: 7, pushDirect: true };
    const r1 = await replaceLatestNews(db, id, { ...base, createdAt: FV.serverTimestamp(), promptDay: '2027-01-13' });
    assert.strictEqual(r1.existed, false);
    const c1 = (await get(`admin_news/${id}`)).createdAt.toMillis();
    // админ қайтариб олган / push қайта юборилган ҳолатни тақлид қиламиз
    await db.doc(`admin_news/${id}`).update({ retractedAt: FV.serverTimestamp(), pushResendAt: FV.serverTimestamp(), promptSend: 9 });
    await new Promise((res) => setTimeout(res, 20));
    const r2 = await replaceLatestNews(db, id, { ...base, title: 'A2', createdAt: FV.serverTimestamp(), promptDay: '2027-01-14' });
    assert.strictEqual(r2.existed, true);
    const d = await get(`admin_news/${id}`);
    assert.strictEqual(d.title, 'A2');
    assert.strictEqual(d.promptDay, '2027-01-14');
    for (const k of ['retractedAt', 'pushResendAt', 'promptSend']) assert.strictEqual(d[k], undefined, k);
    assert.ok(d.createdAt.toMillis() > c1, 'createdAt янгиланди (ўқилмаган + тепада)');
    const all = await db.collection('admin_news').where('targetUserId', '==', U4).where('source', '==', 'birthday_prompt').get();
    assert.strictEqual(all.size, 1);
    assert.strictEqual(validNewsId('a/b'), false);
    assert.strictEqual(validNewsId(''), false);
    await assert.rejects(replaceLatestNews(db, 'bad/id', base), /ADMIN_NEWS_ID_INVALID/);
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
