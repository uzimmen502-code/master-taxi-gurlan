/**
 * Оила боғланиши (эга 2026-11-28) — callable'лар, Firestore Emulator, маҳаллий attach (вақт/хабар DI).
 *   firebase emulators:exec --only firestore --project demo-family "node functions/test/family_links_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-family';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const admin = require('firebase-admin');
const functions = require('firebase-functions');
const fl = require('../family_links');

if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const HttpsError = functions.https.HttpsError;

const ADMIN = '998915000001';
const A = '998912000001'; // таклиф қилувчи (эркак)
const B9 = '912000002'; const B = `998${B9}`; // фақат эски 9 хонали users ҳужжати
const C = '998912000003';
const D = '998912000004';
const E = '998912000005';
const F = '998912000006';
const G = '998912000007';
const H = '998912000008'; // AVA'да йўқ (кейин қўшилади)
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const N = { uz_Cyrl: 'Дастур', uz_Latn: 'Dastur', ru: 'Программа' };

let fakeNow = Date.UTC(2026, 10, 28, 6);
const sent = [];
const local = {};
fl.attachFamilyLinks(local, {
  functions, db, admin, nowMs: () => fakeNow,
  callerPhone: (c) => String(c.auth.token.phone_number || '').replace(/\D/g, ''),
  canonicalUid: (v) => { const d = String(v).replace(/\D/g, ''); return d.length === 9 ? `998${d}` : d; },
  requireCallerRoles: async (c) => { if (!c || !c.auth) throw new HttpsError('unauthenticated', 'x'); if (c.auth.token.phone_number !== `+${ADMIN}`) throw new HttpsError('permission-denied', 'x'); return ADMIN; },
  notifyUserInApp: async (m) => { sent.push(m); },
});
const call = (name, data, who) => local[name].run(data, ctxOf(who));

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
const self = async (owner) => (await db.collection(`relatives/${owner}/people`).where('isSelf', '==', true).get()).docs[0].data();
const program = (extra = {}) => ({ title: N, stage: 'internal', internalPhones: [A, B, C, D, E, F, G, H], pilotDistrictIds: [], amount: 10000, minOrderAmount: 0, maxOrderSharePct: 100, validityDays: 30, budgetTotal: 1000000, ...extra });

async function main() {
  await clearEmulator();
  await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
  await db.doc(`users/${A}`).set({ role: 'user', name: 'Ali Valiyev', gender: 'male', birthDate: '1990-07-10', districtId: 'gurlan', appLang: 'uz_Cyrl', phone: 'secret-A' });
  await db.doc(`users/${B9}`).set({ role: 'user', name: 'Malika', gender: 'female', birthDate: '12.12.1992', appLang: 'uz_Latn', address: 'maxfiy' });
  for (const [p, g] of [[C, 'female'], [D, 'male'], [E, 'female'], [F, 'male'], [G, 'female']]) await db.doc(`users/${p}`).set({ role: 'user', name: `U${p.slice(-1)}`, gender: g });
  await db.doc(`relatives/${A}/people/me`).set({ fullName: 'Ali', isSelf: true, spouseId: null });
  await db.doc(`relatives/${B}/people/me`).set({ fullName: 'Malika', isSelf: true, spouseId: null });

  await check('K1 админ: дастур валидацияси, audit; бошқа фойдаланувчи — рад; эски 3→10k дастури формаси қабул қилинмайди', async () => {
    await expectCode(call('adminUpsertFamilyBonusProgram', { programId: 'spouse_link', program: program({ amount: 0 }) }, ADMIN), 'PROGRAM_INVALID');
    await expectCode(call('adminUpsertFamilyBonusProgram', { programId: 'relatives_birthdays', program: program() }, ADMIN), 'PROGRAM_INVALID');
    await expectCode(call('adminUpsertFamilyBonusProgram', { programId: 'spouse_link', program: program() }, A), 'PERMISSION_DENIED');
    const r = await call('adminUpsertFamilyBonusProgram', { programId: 'spouse_link', program: program(), reason: 'test' }, ADMIN);
    assert.deepStrictEqual([r.ok, r.changed], [true, true]);
    assert.strictEqual((await call('adminUpsertFamilyBonusProgram', { programId: 'spouse_link', program: program() }, ADMIN)).changed, false);
    const au = (await db.collection('admin_audit').where('programKind', '==', 'spouse_link').get()).docs;
    assert.strictEqual(au.length, 1);
    const g = await call('adminGetFamilyBonusPrograms', {}, ADMIN);
    assert.deepStrictEqual([g.programs.spouse_link.amount, g.programs.relative_link], [10000, null]);
  });

  await check('K2 турмуш ўртоғи таклифи: эски 9 хонали ҳисобга хабар (таклиф қилувчининг ЎЗ исми); рўйхатда шахс + «Мен».spouseId; такрор — идемпотент', async () => {
    sent.length = 0;
    const r = await call('inviteSpouse', { name: 'Malika', birthDate: '1992-12-12', phone: '+998 91 200 00 02' }, A);
    assert.deepStrictEqual([r.inviteId, r.duplicate, r.onAva], [`${A}_${B}`, false, true]);
    assert.strictEqual(sent.length, 1);
    assert.deepStrictEqual([sent[0].userId, sent[0].source, sent[0].extraData.inviteId], [B9, 'family_invite', r.inviteId]);
    assert.ok(sent[0].body.startsWith('Ali Valiyev sizni turmuş örtoği deb körsatdi'), sent[0].body);
    const inv = await get(`family_invites/${r.inviteId}`);
    assert.deepStrictEqual([inv.status, inv.reverse, inv.toUid], ['pending', 'spouse', B9]);
    const p = await get(`relatives/${A}/people/${inv.personId}`);
    assert.deepStrictEqual([p.fullName, p.phone, p.isSelf], ['Malika', `+${B}`, false]);
    assert.strictEqual((await self(A)).spouseId, inv.personId);
    const again = await call('inviteSpouse', { name: 'Malika', birthDate: '1992-12-12', phone: B9 }, A);
    assert.strictEqual(again.duplicate, true);
    assert.strictEqual(sent.length, 1, 'такрор хабар йўқ');
    await expectCode(call('inviteSpouse', { name: 'X', birthDate: '1992-12-12', phone: A }, A), 'SELF_INVITE');
    await expectCode(call('inviteSpouse', { name: 'X', phone: C }, A), 'INVALID_REQUEST');
    await expectCode(call('inviteSpouse', { name: 'X', birthDate: '1992-12-12', phone: '123' }, A), 'PHONE_INVALID');
  });

  await check('K3 бегона жавоб бера олмайди; B қабул қилади → ўзаро боғланиш, ҲАР ИККИСИГА 10 000 (эски ҳисобга uid=9 хонали), хабар; махфийлик', async () => {
    await expectCode(call('respondSpouseInvite', { inviteId: `${A}_${B}`, accept: true }, C), 'INVITE_NOT_FOUND');
    sent.length = 0;
    const r = await call('respondSpouseInvite', { inviteId: `${A}_${B}`, accept: true }, B);
    assert.deepStrictEqual([r.result, r.bonus], ['accepted', 'granted']);
    const link = await get(`family_links/${A}_${B}`);
    assert.deepStrictEqual([link.status, link.kind, link.rel[A], link.rel[B]], ['active', 'spouse', 'spouse', 'spouse']);
    assert.strictEqual((await get(`family_link_state/${A}`)).spousePair, `${A}_${B}`);
    const ga = await get(`incentive_grants/spouse_link_${A}`);
    const gb = await get(`incentive_grants/spouse_link_${B}`);
    assert.deepStrictEqual([ga.uid, ga.amount, ga.buckets, gb.uid, gb.personKey], [A, 10000, { supermarket: 10000 }, B9, B]);
    assert.strictEqual((await get(`users/${B9}`)).incentiveBalance, 10000);
    assert.strictEqual(await get(`users/${B}`), undefined, 'канон ҳужжат яратилмади');
    const bonus = sent.filter((m) => m.source === 'family_bonus');
    assert.strictEqual(bonus.length, 2);
    assert.ok(bonus.find((m) => m.userId === A).body.includes('10 000 сўм AVA бонуси') && bonus.find((m) => m.userId === A).body.includes('30 кун'));
    assert.ok(sent.some((m) => m.source === 'family_link' && m.userId === A));
    // Махфийлик: B рўйхатида A — фақат исм ва туғилган кун (телефон/манзил йўқ).
    const pb = await get(`relatives/${B}/people/link_${A}_${B}`);
    assert.deepStrictEqual([pb.fullName, pb.phone, pb.address], ['Ali Valiyev', '', '']);
    assert.strictEqual(new Date(pb.birthDate.toMillis() + 5 * 3600000).toISOString().slice(0, 10), '1990-07-10');
    assert.strictEqual((await self(B)).spouseId, `link_${A}_${B}`);
    assert.strictEqual((await call('respondSpouseInvite', { inviteId: `${A}_${B}`, accept: true }, B)).result, 'duplicate');
    assert.strictEqual((await get(`users/${B9}`)).incentiveBalance, 10000, 'қайта бонус йўқ');
  });

  await check('K4 битта фаол турмуш ўртоғи: A янги таклиф — SPOUSE_EXISTS; C→A таклифи қабулда — SPOUSE_TAKEN', async () => {
    await expectCode(call('inviteSpouse', { name: 'C', birthDate: '1990-01-01', phone: C }, A), 'SPOUSE_EXISTS');
    const r = await call('inviteSpouse', { name: 'Ali', birthDate: '1990-07-10', phone: A }, C);
    await expectCode(call('respondSpouseInvite', { inviteId: r.inviteId, accept: true }, A), 'SPOUSE_TAKEN');
    assert.strictEqual((await call('respondSpouseInvite', { inviteId: r.inviteId, accept: false }, A)).result, 'declined');
    await expectCode(call('respondSpouseInvite', { inviteId: r.inviteId, accept: true }, A), 'INVITE_CLOSED');
  });

  await check('K5 ажратиш (исталган томон): бонус қайтарилмайди; «Мен».spouseId тозаланади; қайта боғланса — қайта бонус ЙЎҚ', async () => {
    const r = await call('unlinkSpouse', {}, B);
    assert.strictEqual(r.result, 'unlinked');
    assert.strictEqual((await get(`family_links/${A}_${B}`)).status, 'unlinked');
    assert.strictEqual((await get(`family_link_state/${A}`)).spousePair, null);
    assert.strictEqual((await self(B)).spouseId, null);
    assert.strictEqual((await get(`incentive_grants/spouse_link_${A}`)).status, 'active');
    await expectCode(call('unlinkSpouse', {}, B), 'LINK_NOT_FOUND');
    fakeNow += 86400000;
    const inv = await call('inviteSpouse', { name: 'Malika', birthDate: '1992-12-12', phone: B }, A);
    sent.length = 0;
    const acc = await call('respondSpouseInvite', { inviteId: inv.inviteId, accept: true }, B);
    assert.deepStrictEqual([acc.result, acc.bonus], ['accepted', 'duplicate']);
    assert.strictEqual(sent.filter((m) => m.source === 'family_bonus').length, 0);
    assert.strictEqual((await get('incentive_programs/spouse_link')).counters.grantedCount, 2);
  });

  await check('K6 кунлик чегара: турмуш ўртоғи таклифи 3/кун', async () => {
    fakeNow += 86400000;
    for (const p of [D, E, F]) await call('inviteSpouse', { name: 'X', birthDate: '1990-01-01', phone: p }, C);
    await expectCode(call('inviteSpouse', { name: 'X', birthDate: '1990-01-01', phone: G }, C), 'RATE_LIMITED');
  });

  await check('K7 қариндош: ота → қабул (ўғил) — ҲАР ИККИ томонга 5 000, жуфтлик бўйича бир марта; ажратиш/қайта — қайта йўқ', async () => {
    await call('adminUpsertFamilyBonusProgram', { programId: 'relative_link', program: program({ amount: 5000, maxParents: 1, maxSiblings: 1 }) }, ADMIN);
    await expectCode(call('inviteRelative', { name: 'X', phone: D, relation: 'uncle' }, A), 'INVALID_REQUEST');
    await expectCode(call('inviteRelative', { name: 'X', phone: D, relation: 'spouse' }, A), 'INVALID_REQUEST');
    const r = await call('inviteRelative', { name: 'Ota', phone: D, relation: 'father', birthDate: '1960-03-01' }, A);
    const inv = await get(`family_invites/${r.inviteId}`);
    assert.strictEqual(inv.reverse, 'son', 'A эркак');
    const acc = await call('respondRelativeInvite', { inviteId: r.inviteId, accept: true }, D);
    assert.deepStrictEqual([acc.result, acc.bonus], ['accepted', 'granted']);
    const pair = `${A}_${D}`;
    assert.strictEqual((await get(`incentive_grants/relative_link_${A}_${pair}`)).amount, 5000);
    assert.strictEqual((await get(`incentive_grants/relative_link_${D}_${pair}`)).amount, 5000);
    assert.deepStrictEqual([(await get(`family_link_state/${A}`)).parents, (await get(`family_link_state/${D}`)).children], [1, 1]);
    // Чегара: ота-она ≤1 (дастурдан) — таклифда рад.
    await expectCode(call('inviteRelative', { name: 'Ona', phone: E, relation: 'mother' }, A), 'CAP_REACHED');
    await call('unlinkRelative', { pairKey: pair }, D);
    assert.strictEqual((await get(`family_link_state/${A}`)).parents, 0);
    assert.strictEqual((await get(`incentive_grants/relative_link_${A}_${pair}`)).status, 'active', 'қайтариб олинмайди');
    const r2 = await call('inviteRelative', { name: 'Ota', phone: D, relation: 'father' }, A);
    assert.strictEqual((await call('respondRelativeInvite', { inviteId: r2.inviteId, accept: true }, D)).bonus, 'duplicate');
  });

  await check('K8 чегара қабул пайтида ҳам: ака-ука ≤1 — иккинчиси (бошқа томон таклифи) рад', async () => {
    const r1 = await call('inviteRelative', { name: 'Uka', phone: F, relation: 'brother' }, A);
    await call('respondRelativeInvite', { inviteId: r1.inviteId, accept: true }, F);
    const r2 = await call('inviteRelative', { name: 'Aka', phone: A, relation: 'brother' }, G); // G (аёл) → A учун G — singil
    await expectCode(call('respondRelativeInvite', { inviteId: r2.inviteId, accept: true }, A), 'CAP_REACHED');
  });

  await check('K9 AVA\'да йўқ рақам: хабар йўқ, эслатма учун шахс; қўшилгач кирувчи таклифни кўради ва қабулда бонус олади', async () => {
    sent.length = 0;
    const r = await call('inviteRelative', { name: 'Opa', phone: H, relation: 'sister', birthDate: '1985-05-05' }, C);
    assert.strictEqual(r.onAva, false);
    assert.strictEqual(sent.length, 0);
    const inv = await get(`family_invites/${r.inviteId}`);
    assert.ok((await get(`relatives/${C}/people/${inv.personId}`)).birthDate);
    await db.doc(`users/${H}`).set({ role: 'user', name: 'H', gender: 'female' });
    const mine = await call('getMyFamilyLinks', {}, H);
    assert.deepStrictEqual(mine.incoming.map((x) => [x.inviteId, x.relation, x.fromName]), [[r.inviteId, 'sister', 'U3']]);
    assert.deepStrictEqual([mine.programs.relative.active, mine.programs.relative.amount, mine.programs.spouse.amount], [true, 5000, 10000]);
    assert.strictEqual((await call('respondRelativeInvite', { inviteId: r.inviteId, accept: true }, H)).bonus, 'granted');
  });

  await check('K10 getMyFamilyLinks: боғланишлар (менга нисбатан ким), чиқувчи таклифлар; дастур OFF — бонус йўқ', async () => {
    const mine = await call('getMyFamilyLinks', {}, A);
    const spouse = mine.links.find((l) => l.kind === 'spouse');
    assert.deepStrictEqual([spouse.relation, spouse.name], ['spouse', 'Malika']);
    assert.ok(mine.links.some((l) => l.relation === 'father'));
    assert.ok(mine.outgoing.length >= 3);
    await call('adminUpsertFamilyBonusProgram', { programId: 'relative_link', program: program({ amount: 5000, stage: 'off' }) }, ADMIN);
    const r = await call('inviteRelative', { name: 'Ona', phone: E, relation: 'mother' }, G);
    assert.strictEqual((await call('respondRelativeInvite', { inviteId: r.inviteId, accept: true }, E)).bonus, 'skip');
    assert.strictEqual((await call('getMyFamilyLinks', {}, E)).programs.relative.active, false);
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed} passed, ${results.length - passed} failed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
