/**
 * HISOBNI O'CHIRISH — so'rov, bekor qilish, ijro (`account_deletion.js`), Firestore Emulator.
 *
 *   firebase emulators:exec --only firestore --project demo-acct-del-cf \
 *     "node test/account_deletion_cf.test.js"
 *
 * Tashqi effektlar (Auth, Storage, vaqt) inyeksiya qilinadi. Haqiqiy settlement_ledger ishlatiladi:
 * hamyon so'ndirilganda passenger_credit == bonusBalance invarianti tekshiriladi.
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-acct-del-cf';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const admin = require('firebase-admin');
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const { createAccountDeletion } = require('../account_deletion');

const U = '998901112233';
const U9 = '901112233';
const OTHER = '998907776655';
const DAY = 24 * 60 * 60 * 1000;
const HOUR = 60 * 60 * 1000;
const T0 = 1_800_000_000_000;

let T = T0;
const calls = { authDeleted: [], storagePaths: [], storagePrefixes: [] };
let authFailures = 0; // nechta marta deleteUser xato bersin
const fakeAuth = {
  async getUserByPhoneNumber(p) {
    if (p !== `+${U}`) { const e = new Error('nf'); e.code = 'auth/user-not-found'; throw e; }
    return { uid: 'auth_uid_u' };
  },
  async deleteUser(uid) {
    if (authFailures > 0) { authFailures -= 1; throw new Error('auth down'); }
    calls.authDeleted.push(uid);
  },
};
const svc = () => createAccountDeletion({
  db, admin, auth: fakeAuth, now: () => T,
  deleteStoragePath: async (p) => { calls.storagePaths.push(p); },
  deleteStoragePrefix: async (p) => { calls.storagePrefixes.push(p); },
  log: () => {},
});

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function expectCode(promise, code) {
  await assert.rejects(promise, (e) => { assert.strictEqual(e.code, code, `kod ${e.code}: ${e.message}`); return true; });
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const get = async (path) => (await db.doc(path).get());
const exists = async (path) => (await get(path)).exists;
const countCol = async (path) => (await db.collection(path).get()).size;
const enable = (on = true, waitDays) => db.collection('settings').doc('account_deletion')
  .set(on ? { enabled: true, ...(waitDays ? { waitDays } : {}) } : { enabled: false });

async function seedUser() {
  T = T0;
  authFailures = 0;
  calls.authDeleted.length = 0; calls.storagePaths.length = 0; calls.storagePrefixes.length = 0;
  await clearEmulator();
  await enable(true);
  await db.collection('users').doc(U).set({
    name: 'Ali', phone: `+${U}`, birthDate: '1990-01-01', address: { manual: 'Gurlan' }, role: 'user',
    bonusBalance: 50000, fcmToken: 'tok', accountId: 'acc_u',
  });
  await db.collection('users').doc(OTHER).set({ name: 'Vali', phone: `+${OTHER}`, bonusBalance: 777, role: 'user' });
  await db.collection('ledger_accounts').doc(`passenger_credit:${U}`).set({ type: 'liability', ownerUid: U, balance: 50000 });
  await db.collection('ledger_accounts').doc('admin_clearing').set({ type: 'asset', ownerUid: '', balance: 0 });
  const u = db.collection('users').doc(U);
  await u.collection('wallet_ledger').doc('l1').set({ type: 'topup', amount: 50000 });
  await u.collection('vehicles').doc('v1').set({ plate: '01A777AA' });
  await u.collection('saved_tv_clips').doc('c1').set({ clipId: 'x' });
  await u.collection('assistant_conversations').doc('c1').collection('assistant_messages').doc('m1').set({ text: 'salom' });
  await u.collection('fcm_tokens').doc('t1').set({ token: 'tok' });
  await db.collection('device_bindings').doc('a'.repeat(64)).set({ phone: U, fingerprint: { androidId: 'x' } });
  await db.collection('device_aliases').doc(U).set({ phone: U });
  await db.collection('telegram_links').doc('tg1').set({ uid: U, telegramUsername: 'ali' });
  await db.collection('dating_profiles').doc(U).set({ displayName: 'Ali', photos: [{ path: `dating/${U}/p1.jpg` }] });
  await db.collection('dating_profiles_public').doc(U).set({ displayName: 'Ali' });
  await db.collection('dating_interests').doc('i1').set({ fromId: U, toId: OTHER });
  await db.collection('dating_interests').doc('i2').set({ fromId: OTHER, toId: U });
  await db.collection('dating_blocks').doc(U).collection('list').doc('b1').set({ id: OTHER });
  await db.collection('dating_matches').doc('m1').set({ users: [U, OTHER] });
  await db.collection('dating_matches').doc('m1').collection('messages').doc('x').set({ text: 'hi', senderId: U });
  await db.collection('orders').doc('o_done').set({ userPhone: U, status: 'completed', total: 10000 });
  await db.collection('orders').doc('o_other').set({ userPhone: OTHER, status: 'new' });
}

async function requestAndDue(s = svc()) {
  await s.request(U);
  T = T0 + 11 * DAY;
}

async function main() {
  await seedUser();

  await check(`C1 dars' yopiq (fail-closed): sozlama yo'q yoki enabled=false → ACCOUNT_DELETION_DISABLED`, async () => {
    await db.collection('settings').doc('account_deletion').delete();
    await expectCode(svc().request(U), 'ACCOUNT_DELETION_DISABLED');
    await enable(false);
    await expectCode(svc().request(U), 'ACCOUNT_DELETION_DISABLED');
    assert.strictEqual(await exists(`account_deletions/${U}`), false);
    const p = await svc().preview(U);
    assert.strictEqual(p.enabled, false); // ko'rish ishlaydi
    await enable(true);
  });

  await check(`C2 so'rov: PENDING, 10 kun, users.deletion belgisi, voqea; takroriy so'rov o'zgartirmaydi`, async () => {
    const r = await svc().request(U);
    assert.strictEqual(r.status, 'PENDING');
    assert.strictEqual(r.duplicate, false);
    assert.strictEqual(r.scheduledForMs, T0 + 10 * DAY);
    const st = (await get(`account_deletions/${U}`)).data();
    assert.strictEqual(st.status, 'PENDING');
    assert.strictEqual(st.walletAtRequest, 50000);
    assert.strictEqual(st.scheduledFor.toMillis(), T0 + 10 * DAY);
    assert.strictEqual((await get(`users/${U}`)).data().deletion.status, 'PENDING');
    assert.strictEqual(await countCol(`account_deletions/${U}/events`), 1);
    T = T0 + 3 * DAY;
    const r2 = await svc().request(U);
    assert.strictEqual(r2.duplicate, true);
    assert.strictEqual(r2.scheduledForMs, T0 + 10 * DAY); // kechiktirilmadi
    assert.strictEqual(await countCol(`account_deletions/${U}/events`), 1);
  });

  await check(`C3 waitDays sozlamasi (3 kun) hisobga olinadi; 0 yoki xato qiymat → 10`, async () => {
    await seedUser();
    await enable(true, 3);
    assert.strictEqual((await svc().request(U)).scheduledForMs, T0 + 3 * DAY);
    await seedUser();
    await db.collection('settings').doc('account_deletion').set({ enabled: true, waitDays: 0 });
    assert.strictEqual((await svc().request(U)).scheduledForMs, T0 + 10 * DAY);
    await seedUser();
    await db.collection('settings').doc('account_deletion').set({ enabled: true, waitDays: 999 });
    assert.strictEqual((await svc().request(U)).scheduledForMs, T0 + 60 * DAY); // yuqori chegara
  });

  await check(`C4 blokirovka bor → ACCOUNT_DELETION_BLOCKED, hech narsa yozilmaydi`, async () => {
    await seedUser();
    await db.collection('orders').doc('o_new').set({ userPhone: U, status: 'new' });
    await assert.rejects(svc().request(U), (e) => {
      assert.strictEqual(e.code, 'ACCOUNT_DELETION_BLOCKED');
      assert.deepStrictEqual(e.extra.blockers.map((b) => b.code), ['ORDER_ACTIVE']);
      assert.ok(!('sample' in e.extra.blockers[0]), 'hujjat ID klientga chiqmasin');
      return true;
    });
    assert.strictEqual(await exists(`account_deletions/${U}`), false);
    assert.strictEqual((await get(`users/${U}`)).data().deletion, undefined);
  });

  await check(`C5 noma'lum hisob → ACCOUNT_NOT_FOUND, arvoh users hujjati yaratilmaydi`, async () => {
    await seedUser();
    await expectCode(svc().request('998909990000'), 'ACCOUNT_NOT_FOUND');
    assert.strictEqual(await exists('users/998909990000'), false);
    assert.strictEqual(await exists('account_deletions/998909990000'), false);
  });

  await check(`C6 bekor qilish: CANCELLED, users.deletion olinadi; qayta bekor qilish va so'rovsiz — NOT_PENDING`, async () => {
    await seedUser();
    await expectCode(svc().cancel(U), 'ACCOUNT_DELETION_NOT_PENDING'); // so'rovsiz
    await svc().request(U);
    const r = await svc().cancel(U);
    assert.strictEqual(r.status, 'CANCELLED');
    assert.strictEqual((await get(`account_deletions/${U}`)).data().status, 'CANCELLED');
    assert.strictEqual((await get(`users/${U}`)).data().deletion, undefined);
    await expectCode(svc().cancel(U), 'ACCOUNT_DELETION_NOT_PENDING');
    // bekor qilingandan keyin yangi so'rov mumkin
    assert.strictEqual((await svc().request(U)).status, 'PENDING');
  });

  await check(`E1 muddat kelmaguncha ijro — SKIPPED, hech narsa o'chmaydi`, async () => {
    await seedUser();
    await svc().request(U);
    T = T0 + 9 * DAY;
    assert.strictEqual((await svc().execute(U)).status, 'SKIPPED');
    assert.strictEqual((await get(`users/${U}`)).data().bonusBalance, 50000);
    assert.strictEqual(await exists(`users/${U}/vehicles/v1`), true);
    assert.strictEqual(calls.authDeleted.length, 0);
  });

  await check(`E2 to'liq ijro: hamyon so'ndiriladi, qobiq, shaxsiy ma'lumot o'chadi, moliyaviy yozuv qoladi`, async () => {
    await seedUser();
    const s = svc();
    await requestAndDue(s);
    const r = await s.execute(U);
    assert.strictEqual(r.status, 'DONE', JSON.stringify(r));
    // hamyon: bonusBalance 0, ledger yozuvi, invariant
    const user = (await get(`users/${U}`)).data();
    assert.strictEqual(user.bonusBalance, 0);
    assert.strictEqual(user.deleted, true);
    for (const k of ['name', 'phone', 'birthDate', 'address', 'fcmToken', 'accountId', 'deletion']) {
      assert.ok(!(k in user), `qobiqda ${k} qolgan`);
    }
    const pc = (await get(`ledger_accounts/passenger_credit:${U}`)).data();
    assert.strictEqual(pc.balance, 0, 'passenger_credit == bonusBalance buzildi');
    assert.strictEqual((await get('ledger_accounts/admin_clearing')).data().balance, -50000);
    const j = (await get(`journal_entries/bonus:acct_del_forfeit_${U}`)).data();
    assert.strictEqual(j.kind, 'account_deletion_forfeit');
    assert.strictEqual(j.amount, 50000);
    assert.strictEqual((await get(`users/${U}/wallet_ledger/account_deletion_${U}`)).data().amount, -50000);
    // moliyaviy tarix saqlandi
    assert.strictEqual(await exists(`users/${U}/wallet_ledger/l1`), true);
    assert.strictEqual(await exists('orders/o_done'), true);
    // shaxsiy ost-kolleksiyalar o'chdi
    assert.strictEqual(await countCol(`users/${U}/vehicles`), 0);
    assert.strictEqual(await countCol(`users/${U}/saved_tv_clips`), 0);
    assert.strictEqual(await countCol(`users/${U}/fcm_tokens`), 0);
    assert.strictEqual(await countCol(`users/${U}/assistant_conversations/c1/assistant_messages`), 0);
    // qurilma/telegram
    assert.strictEqual(await exists(`device_bindings/${'a'.repeat(64)}`), false);
    assert.strictEqual(await exists(`device_aliases/${U}`), false);
    assert.strictEqual(await exists('telegram_links/tg1'), false);
    // Auth
    assert.deepStrictEqual(calls.authDeleted, ['auth_uid_u']);
    // holat va tarix
    const st = (await get(`account_deletions/${U}`)).data();
    assert.strictEqual(st.status, 'DONE');
    for (const name of ['forfeit_wallet', 'delete_device_and_links', 'delete_user_subcollections', 'dating_own_side', 'user_shell', 'auth_delete']) {
      assert.strictEqual(st.steps[name].done, true, name);
    }
    assert.strictEqual((await db.collection('account_deletion_history').get()).size, 1);
    // begona foydalanuvchi tegilmadi
    assert.strictEqual((await get(`users/${OTHER}`)).data().bonusBalance, 777);
    assert.strictEqual((await get('orders/o_other')).data().status, 'new');
  });

  await check(`E3 tanishuv: o'z tomoni o'chadi, MATCH VA CHAT QOLADI; suratlar Storage'dan`, async () => {
    await seedUser();
    const s = svc();
    await requestAndDue(s);
    await s.execute(U);
    assert.strictEqual(await exists(`dating_profiles/${U}`), false);
    assert.strictEqual(await exists(`dating_profiles_public/${U}`), false);
    assert.strictEqual(await exists('dating_interests/i1'), false);
    assert.strictEqual(await exists('dating_interests/i2'), false);
    assert.strictEqual(await countCol(`dating_blocks/${U}/list`), 0);
    assert.strictEqual(await exists('dating_matches/m1'), true);
    assert.strictEqual(await countCol('dating_matches/m1/messages'), 1);
    assert.deepStrictEqual(calls.storagePaths, [`dating/${U}/p1.jpg`]);
    assert.ok(calls.storagePrefixes.includes(`dating/${U}/`));
  });

  await check(`E4 ijro paytida yangi blokirovka → POSTPONED, hech narsa o'chmaydi; blok ketgach va vaqt o'tgach DONE`, async () => {
    await seedUser();
    const s = svc();
    await s.request(U);
    await db.collection('trips').doc('t_new').set({ userPhone: U, status: 'searching' });
    T = T0 + 11 * DAY;
    const r = await s.execute(U);
    assert.strictEqual(r.status, 'POSTPONED');
    assert.deepStrictEqual(r.blockers.map((b) => b.code), ['TRIP_ACTIVE']);
    assert.strictEqual((await get(`users/${U}`)).data().bonusBalance, 50000);
    assert.strictEqual(await exists(`users/${U}/vehicles/v1`), true);
    assert.strictEqual(calls.authDeleted.length, 0);
    // darhol qayta urinish — hali erta (nextCheckAt +24 soat)
    assert.strictEqual((await s.execute(U)).status, 'SKIPPED');
    await db.collection('trips').doc('t_new').update({ status: 'completed' });
    T += 25 * HOUR;
    assert.strictEqual((await s.execute(U)).status, 'DONE');
    assert.strictEqual((await get(`users/${U}`)).data().deleted, true);
  });

  await check(`E5 uzilishdan keyin davom: Auth xato → POSTPONED; ikkinchi urinishda DONE; hamyon BIR marta so'ndirildi`, async () => {
    await seedUser();
    const s = svc();
    await requestAndDue(s);
    authFailures = 1;
    const r1 = await s.execute(U);
    assert.strictEqual(r1.status, 'POSTPONED');
    assert.strictEqual(r1.error, true);
    const mid = (await get(`account_deletions/${U}`)).data();
    assert.strictEqual(mid.steps.user_shell.done, true);
    assert.ok(!mid.steps.auth_delete, 'auth_delete tugamagan');
    assert.ok(mid.lastError.includes('auth down'));
    T += 2 * HOUR;
    const r2 = await s.execute(U);
    assert.strictEqual(r2.status, 'DONE', JSON.stringify(r2));
    assert.deepStrictEqual(calls.authDeleted, ['auth_uid_u']);
    const j = await db.collection('journal_entries').where('kind', '==', 'account_deletion_forfeit').get();
    assert.strictEqual(j.size, 1, `hamyon ikki marta so'ndirildi`);
    assert.strictEqual((await get('ledger_accounts/admin_clearing')).data().balance, -50000);
    assert.strictEqual((await get(`account_deletions/${U}`)).data().attempts, 2);
  });

  await check(`E6 5 muvaffaqiyatsiz urinish → FAILED (admin ko'radi), 6-urinish yo'q`, async () => {
    await seedUser();
    const s = svc();
    await requestAndDue(s);
    authFailures = 100;
    let last;
    for (let i = 0; i < 5; i++) { last = await s.execute(U); T += 2 * HOUR; }
    assert.strictEqual(last.status, 'FAILED');
    assert.strictEqual((await get(`account_deletions/${U}`)).data().status, 'FAILED');
    assert.strictEqual((await s.execute(U)).status, 'SKIPPED'); // FAILED o'z-o'zidan olinmaydi
    // FAILED'ni foydalanuvchi bekor qila oladi
    assert.strictEqual((await s.cancel(U)).status, 'CANCELLED');
  });

  await check(`E7 parallel ikki ijro: faqat bittasi ishlaydi (DONE + SKIPPED), hamyon bir marta`, async () => {
    await seedUser();
    const s = svc();
    await requestAndDue(s);
    const [a, b] = await Promise.all([s.execute(U), s.execute(U)]);
    const sts = [a.status, b.status].sort();
    assert.deepStrictEqual(sts, ['DONE', 'SKIPPED'], JSON.stringify([a, b]));
    const j = await db.collection('journal_entries').where('kind', '==', 'account_deletion_forfeit').get();
    assert.strictEqual(j.size, 1);
  });

  await check(`E8 EXECUTING lease tugagach (jarayon o'lgan) boshqa ijrochi qabul qiladi, tugallangan qadamlar qayta ishlamaydi`, async () => {
    await seedUser();
    const s = svc();
    await requestAndDue(s);
    await db.collection('account_deletions').doc(U).update({
      status: 'EXECUTING', attempts: 1,
      leaseUntil: admin.firestore.Timestamp.fromMillis(T - 1000),
      steps: { forfeit_wallet: { done: true, atMs: T, result: { forfeited: [] } } },
    });
    // forfeit "bajarilgan" deb belgilangan — qayta ishlanmaydi, demak balans qoladi (sinov: qadam o'tkazib yuboriladi)
    const r = await s.execute(U);
    assert.strictEqual(r.status, 'DONE');
    assert.strictEqual((await get(`users/${U}`)).data().deleted, true);
    assert.strictEqual((await db.collection('journal_entries').where('kind', '==', 'account_deletion_forfeit').get()).size, 0);
  });

  await check(`E9 lease tugamagan EXECUTING — boshqa ijrochi tegmaydi`, async () => {
    await seedUser();
    const s = svc();
    await requestAndDue(s);
    await db.collection('account_deletions').doc(U).update({
      status: 'EXECUTING', leaseUntil: admin.firestore.Timestamp.fromMillis(T + 10 * 60 * 1000),
    });
    assert.strictEqual((await s.execute(U)).status, 'SKIPPED');
    assert.strictEqual((await get(`users/${U}`)).data().bonusBalance, 50000);
  });

  await check(`E10 ikki shakldagi hujjat (9 va 12 xonali): ikkalasi ham so'ndiriladi va qobiqqa aylanadi`, async () => {
    await seedUser();
    await db.collection('users').doc(U9).set({ name: 'Ali eski', phone: U9, bonusBalance: 1200, role: 'user' });
    await db.collection('ledger_accounts').doc(`passenger_credit:${U9}`).set({ type: 'liability', ownerUid: U9, balance: 1200 });
    const s = svc();
    await requestAndDue(s);
    assert.strictEqual((await s.execute(U)).status, 'DONE');
    for (const id of [U, U9]) {
      const d = (await get(`users/${id}`)).data();
      assert.strictEqual(d.deleted, true, id);
      assert.strictEqual(d.bonusBalance, 0, id);
    }
    assert.strictEqual((await get('ledger_accounts/admin_clearing')).data().balance, -51200);
    assert.strictEqual((await get(`ledger_accounts/passenger_credit:${U9}`)).data().balance, 0);
  });

  await check(`E11 hamyon 0 bo'lsa — journal yozilmaydi; manfiy balans tegilmaydi`, async () => {
    await seedUser();
    await db.collection('users').doc(U).update({ bonusBalance: 0 });
    const s = svc();
    await requestAndDue(s);
    assert.strictEqual((await s.execute(U)).status, 'DONE');
    assert.strictEqual((await db.collection('journal_entries').get()).size, 0);
    await seedUser();
    await db.collection('users').doc(U).update({ bonusBalance: -5 });
    const s2 = svc();
    await requestAndDue(s2);
    assert.strictEqual((await s2.execute(U)).status, 'DONE');
    assert.strictEqual((await db.collection('journal_entries').get()).size, 0);
  });

  await check(`E12 so'rov va ijro orasida foydalanuvchi hujjati o'chib ketgan bo'lsa — arvoh yaratilmaydi`, async () => {
    await seedUser();
    const s = svc();
    await requestAndDue(s);
    await db.collection('users').doc(U).delete();
    const r = await s.execute(U);
    assert.strictEqual(r.status, 'DONE');
    assert.strictEqual(await exists(`users/${U}`), false, 'arvoh hujjat yaratildi');
  });

  await check(`R1 runDue: faqat muddati kelganlar; sozlama o'chiq bo'lsa hech narsa ishlamaydi`, async () => {
    await seedUser();
    await db.collection('users').doc(OTHER).update({ bonusBalance: 0 });
    await db.collection('orders').doc('o_other').delete(); // OTHER'ning faol buyurtmasi blokirovka qilardi
    const s = svc();
    await s.request(U);
    T = T0 + 5 * DAY;
    await s.request(OTHER); // OTHER 15-kuni
    T = T0 + 11 * DAY;
    const r = await s.runDue();
    assert.strictEqual(r.processed, 1);
    assert.strictEqual((await get(`account_deletions/${U}`)).data().status, 'DONE');
    assert.strictEqual((await get(`account_deletions/${OTHER}`)).data().status, 'PENDING');
    await enable(false);
    T = T0 + 20 * DAY;
    assert.deepStrictEqual(await s.runDue(), { processed: 0, skipped: 'disabled' });
    assert.strictEqual((await get(`account_deletions/${OTHER}`)).data().status, 'PENDING');
  });

  await check(`R2 o'chirilgandan keyin qayta ro'yxatdan o'tgan (yangi users hujjati) yangi so'rov yubora oladi; tarix saqlanadi`, async () => {
    await seedUser();
    const s = svc();
    await requestAndDue(s);
    await s.execute(U);
    await db.collection('users').doc(U).set({ name: 'Ali yangi', phone: `+${U}`, role: 'user', bonusBalance: 0 });
    const r = await s.request(U);
    assert.strictEqual(r.status, 'PENDING');
    assert.strictEqual(r.duplicate, false);
    assert.strictEqual((await db.collection('account_deletion_history').get()).size, 1);
    const types = (await db.collection(`account_deletions/${U}/events`).get()).docs.map((d) => d.data().type).sort();
    assert.deepStrictEqual(types, ['done', 'executing', 'requested', 'requested'], 'voqealar jurnali saqlanmadi');
  });

  await check(`P1 preview: faqat o'qiydi; hamyon, pullik xizmat va blokirovkalarni qaytaradi`, async () => {
    await seedUser();
    await db.collection('users').doc(U).update({
      realtyPro: { expiresAt: admin.firestore.Timestamp.fromMillis(T0 + 5 * DAY) },
      realtyUnlocksLeft: 2,
      assistantPaidUntil: admin.firestore.Timestamp.fromMillis(T0 + 5 * DAY),
    });
    await db.collection('orders').doc('o_new').set({ userPhone: U, status: 'accepted' });
    const before = (await get(`users/${U}`)).updateTime.toMillis();
    const p = await svc().preview(U);
    assert.strictEqual(p.walletAmount, 50000);
    assert.deepStrictEqual(p.paidServices.sort(), ['assistant_package', 'realty_pro', 'realty_unlocks']);
    assert.deepStrictEqual(p.blockers.map((b) => b.code), ['ORDER_ACTIVE']);
    assert.strictEqual(p.waitDays, 10);
    assert.strictEqual(p.state, null);
    assert.strictEqual((await get(`users/${U}`)).updateTime.toMillis(), before);
    assert.strictEqual(await exists(`account_deletions/${U}`), false);
  });

  await check(`H1 yashirgichlar (hide/unhide): so'rovda chaqiriladi, bekor qilinganda qaytariladi, xato so'rovni to'xtatmaydi`, async () => {
    await seedUser();
    const log = [];
    const s = createAccountDeletion({
      db, admin, auth: fakeAuth, now: () => T, log: () => {},
      hiders: [
        { name: 'ok', async hide() { log.push('hide:ok'); }, async unhide() { log.push('unhide:ok'); } },
        { name: 'bad', async hide() { throw new Error('boom'); }, async unhide() { log.push('unhide:bad'); } },
      ],
    });
    await s.request(U);
    assert.deepStrictEqual(log, ['hide:ok']);
    assert.strictEqual((await get(`account_deletions/${U}`)).data().hidePending, true);
    await s.cancel(U);
    assert.deepStrictEqual(log, ['hide:ok', 'unhide:ok', 'unhide:bad']);
  });
}

main().then(() => {
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}).catch((e) => { console.error(e); process.exit(1); });
