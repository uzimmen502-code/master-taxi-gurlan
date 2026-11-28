/**
 * «Туғилган кунингизни киритинг» ҳафталик пуш — scheduler + админ callable, ҲАҚИҚИЙ index.js + маҳаллий attach
 * (сохта вақт, хабарларни йиғиш), Firestore Emulator.
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
const U7 = '998912000007'; // санаси йўқ, бошқа туман
const LEGACY = '912000008'; // эски 9 хонали ҳужжат
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

// Якшанба 2026-11-29 12:00 Тошкент (2026-W48); кейинги якшанбалар — +7 кун.
const SUN = h.startOfKeyMs('2026-11-29') + 12 * 3600000;
const WEEK_MS = 7 * 86400000;
let fakeNow = SUN;
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
const setCfg = (s) => db.doc('settings/birthday_prompt').set(s);

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

  await check('C0 index.js: функциялар уланган (birthdayPromptWeekly, adminGet/SetBirthdayPromptSettings)', async () => {
    for (const n of ['birthdayPromptWeekly', 'adminGetBirthdayPromptSettings', 'adminSetBirthdayPromptSettings']) assert.ok(fns[n], n);
  });

  await check('C1 созлама йўқ = OFF: ҳеч нарса юборилмайди, run ҳужжати ёзилмайди', async () => {
    const r = await run();
    assert.strictEqual(r.reason, 'STAGE_OFF');
    assert.strictEqual(sent.length, 0);
    assert.strictEqual((await db.collection('birthday_prompt_runs').get()).size, 0);
  });

  await check('C2 админ: рухсатсиз — PERMISSION_DENIED; нотўғри — SETTINGS_INVALID; тўғри — версия 1 + admin_audit', async () => {
    const S = { stage: 'internal', internalPhones: [T1, T2, T3], pilotDistrictIds: [], maxSends: 2 };
    await expectCode(call('adminSetBirthdayPromptSettings', { settings: S }, U4), 'PERMISSION_DENIED');
    await expectCode(call('adminSetBirthdayPromptSettings', { settings: { ...S, maxSends: 0 } }, ADMIN), 'SETTINGS_INVALID');
    await expectCode(call('adminSetBirthdayPromptSettings', { settings: { ...S, internalPhones: ['912000001'] } }, ADMIN), 'SETTINGS_INVALID');
    const r = await call('adminSetBirthdayPromptSettings', { settings: S, expectedVersion: 0, reason: 'синов' }, ADMIN);
    assert.deepStrictEqual([r.changed, r.version], [true, 1]);
    const again = await call('adminSetBirthdayPromptSettings', { settings: S }, ADMIN);
    assert.strictEqual(again.changed, false);
    await expectCode(call('adminSetBirthdayPromptSettings', { settings: { ...S, maxSends: 3 }, expectedVersion: 0 }, ADMIN), 'VERSION_CONFLICT');
    const au = (await db.collection('admin_audit').where('kind', '==', 'birthday_prompt_settings').get()).docs.map((d) => d.data());
    assert.strictEqual(au.length, 1);
    assert.strictEqual(au[0].before, null);
    assert.strictEqual(au[0].after.stage, 'internal');
    const g = await call('adminGetBirthdayPromptSettings', {}, ADMIN);
    assert.strictEqual(g.settings.stage, 'internal');
    assert.strictEqual(g.settings.maxSends, 2);
    assert.strictEqual(g.defaults.maxSends, 4);
    await expectCode(call('adminGetBirthdayPromptSettings', {}, U4), 'PERMISSION_DENIED');
  });

  await check('C3 ойнадан ташқари (шанба) — юборилмайди', async () => {
    fakeNow = SUN - 86400000;
    const r = await run();
    fakeNow = SUN;
    assert.strictEqual(r.reason, 'OUT_OF_WINDOW');
    assert.strictEqual(sent.length, 0);
  });

  await check('C4 internal: фақат тестерлар; санаси бор/токенсиз — йўқ; тестер бўлмаган — йўқ; тил uz_Latn; push маълумоти', async () => {
    const r = await run();
    assert.strictEqual(r.result, 'ok');
    assert.strictEqual(r.done, true);
    assert.deepStrictEqual(sentTo(), [T1]);
    const m = sent[0];
    assert.strictEqual(m.title, b.PROMPT_TEXT.uz_Latn.title);
    assert.strictEqual(m.body, b.PROMPT_TEXT.uz_Latn.body);
    assert.deepStrictEqual([m.source, m.dataType, m.screen], ['birthday_prompt', 'birthday_prompt', 'user_info']);
    assert.strictEqual(m.extraData.promptWeek, '2026-W48');
    assert.strictEqual(r.HAS_BIRTHDATE, 1);
    assert.strictEqual(r.NO_TOKEN, 1);
    const st = await get(`birthday_prompt_state/${T1}`);
    assert.deepStrictEqual([st.sends, st.lastWeek], [1, '2026-W48']);
    const runDoc = await get('birthday_prompt_runs/2026-W48_internal');
    assert.strictEqual(runDoc.done, true);
    assert.strictEqual(runDoc.stats.sent, 1);
    assert.strictEqual(runDoc.leaseUntil, undefined);
  });

  await check('C5 идемпотентлик: шу ҳафта қайта чақирув — DONE; run ўчирилса ҳам (retry) ҳолат иккинчи юборишни тўсади', async () => {
    assert.strictEqual((await run()).reason, 'DONE');
    await db.doc('birthday_prompt_runs/2026-W48_internal').delete();
    const r = await run();
    assert.strictEqual(r.ALREADY_THIS_WEEK, 1);
    assert.strictEqual(sent.length, 1);
  });

  await check('C6 параллел икки чақирув (lease + транзакция): бир ҳафтада битта юбориш', async () => {
    fakeNow = SUN + WEEK_MS; // 2026-W49
    const [a, c] = await Promise.all([run(), run()]);
    const sentNow = sent.filter((m) => m.extraData.promptWeek === '2026-W49');
    assert.strictEqual(sentNow.length, 1, JSON.stringify([a, c]));
    assert.strictEqual((await get(`birthday_prompt_state/${T1}`)).sends, 2);
  });

  await check('C7 чегара (maxSends=2): учинчи ҳафтада CAP_REACHED, юборилмайди', async () => {
    fakeNow = SUN + 2 * WEEK_MS; // 2026-W50
    const r = await run();
    assert.strictEqual(r.CAP_REACHED, 1);
    assert.strictEqual(sent.filter((m) => m.extraData.promptWeek === '2026-W50').length, 0);
  });

  await check('C8 public: бутун users саҳифалаб (pageSize 2); санаси йўқлар ҳаммасига; opt-out/ўчирилиш/9 хонали/токенсиз — йўқ', async () => {
    await call('adminSetBirthdayPromptSettings', { settings: { stage: 'public', internalPhones: [], pilotDistrictIds: [], maxSends: 4 } }, ADMIN);
    fakeNow = SUN + 3 * WEEK_MS; // 2026-W51
    sent.length = 0;
    const r = await run();
    assert.strictEqual(r.done, true);
    assert.deepStrictEqual(sentTo(), [T1, U4, U7].sort()); // T1: 2/4 → 3; U7 — birthDate '' = йўқ
    assert.strictEqual(r.scanned, 9);
    assert.strictEqual(r.OPTED_OUT, 1);
    assert.strictEqual(r.DELETION, 1);
    assert.strictEqual(r.NOT_CANONICAL, 1);
    assert.strictEqual(r.NO_TOKEN, 1);
    assert.strictEqual(sent.find((m) => m.userId === U4).title, b.PROMPT_TEXT.ru.title);
    assert.ok((await get('birthday_prompt_runs/2026-W51_public')).cursor);
  });

  await check('C9 сана киритилгач тўхтайди: кейинги ҳафта U4 (сана киритди) — йўқ, қолганлар — бор', async () => {
    await db.doc(`users/${U4}`).update({ birthDate: '1995-03-08' });
    fakeNow = SUN + 4 * WEEK_MS; // 2026-W52
    sent.length = 0;
    const r = await run();
    assert.deepStrictEqual(sentTo(), [T1, U7].sort());
    assert.strictEqual(r.HAS_BIRTHDATE, 3); // ADMIN, T2, U4
  });

  await check('C10 pilot: фақат тестерлар + пилот тумани (urganch), Гурлан санаси йўқлари — йўқ; тестер такрори — бир марта', async () => {
    await db.doc(`users/${U7}`).update({ birthDate: FieldDel() });
    await call('adminSetBirthdayPromptSettings', { settings: { stage: 'pilot', internalPhones: [U7], pilotDistrictIds: ['urganch'], maxSends: 12 } }, ADMIN);
    fakeNow = SUN + 5 * WEEK_MS; // 2027-01-03 (якшанба) = 2026-W53
    sent.length = 0;
    const r = await run();
    assert.deepStrictEqual(sentTo(), [U7]);
    assert.strictEqual(r.ALREADY_THIS_WEEK, 1); // тестер U7 туман сканида яна учради
  });

  await check('C11 хабар хатоси: белги олинган (шу ҳафта қайта юборилмайди), NOTIFY_FAILED ҳисобланади, run тугайди', async () => {
    await call('adminSetBirthdayPromptSettings', { settings: { stage: 'internal', internalPhones: [U4, T1], pilotDistrictIds: [], maxSends: 12 } }, ADMIN);
    await db.doc(`users/${U4}`).update({ birthDate: FieldDel() });
    fakeNow = SUN + 6 * WEEK_MS;
    notifyFail = true;
    const r = await run();
    notifyFail = false;
    assert.strictEqual(r.NOTIFY_FAILED, 2);
    assert.strictEqual(r.done, true);
    const wk = b.weekKeyOfMs(fakeNow);
    assert.strictEqual((await get(`birthday_prompt_state/${U4}`)).lastWeek, wk);
  });

  await check('C12 lease: бошқа чақирув ишлаётган бўлса (leaseUntil келажакда) — LEASED, ҳеч нарса юборилмайди', async () => {
    fakeNow = SUN + 7 * WEEK_MS;
    const wk = b.weekKeyOfMs(fakeNow);
    await db.doc(`birthday_prompt_runs/${wk}_internal`).set({ week: wk, stage: 'internal', leaseUntil: admin.firestore.Timestamp.fromMillis(fakeNow + 60000) });
    sent.length = 0;
    assert.strictEqual((await run()).reason, 'LEASED');
    assert.strictEqual(sent.length, 0);
  });

  await check('C13 админ get: охирги тарқатишлар статистикаси қайтади', async () => {
    const g = await call('adminGetBirthdayPromptSettings', {}, ADMIN);
    assert.ok(g.runs.length >= 3);
    assert.ok(g.runs.some((x) => x.id === '2026-W51_public' && x.done && x.stats.sent === 3));
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
}
const FieldDel = () => admin.firestore.FieldValue.delete();

main().catch((e) => { console.error(e); process.exit(1); });
