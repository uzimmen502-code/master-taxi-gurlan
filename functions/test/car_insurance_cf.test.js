/**
 * «Автомобил суғуртаси» (эга 2026-11-28) — callable'лар, Firestore Emulator, маҳаллий attach (вақт/хабар/Storage DI).
 *   firebase emulators:exec --only firestore --project demo-insurance "node functions/test/car_insurance_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-insurance';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) throw new Error('demo-* loyiha kerak');

const admin = require('firebase-admin');
const functions = require('firebase-functions');
const ci = require('../car_insurance');

if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();
const HttpsError = functions.https.HttpsError;

const ADMIN = '998915000001';
const AGENT = '998915000002'; // dispatcher + agentPhones
const REP = '998915000003'; // staff + reporterPhones
const U = '998912000001';
const V = '998912000002';
const W = '998912000003';
const OUT = '998912000009'; // internal рўйхатида йўқ
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });

let fakeNow = Date.UTC(2026, 10, 28, 6); // 2026-11-28 11:00 Тошкент
const sent = [];
const saved = [];
const removed = [];
const signed = [];
const local = {};
const api = ci.attachCarInsurance(local, {
  functions, db, admin, nowMs: () => fakeNow,
  callerPhone: (c) => String(c.auth.token.phone_number || '').replace(/\D/g, ''),
  canonicalUid: (v) => { const d = String(v).replace(/\D/g, ''); return d.length === 9 ? `998${d}` : d; },
  requireCallerRoles: async (c, roles) => {
    if (!c || !c.auth) throw new HttpsError('unauthenticated', 'x');
    const uid = String(c.auth.token.phone_number).replace(/\D/g, '');
    const role = ((await db.doc(`users/${uid}`).get()).data() || {}).role || 'user';
    if (!roles.includes(role)) throw new HttpsError('permission-denied', 'x');
    return uid;
  },
  notifyUserInApp: async (m) => { sent.push(m); },
  storage: {
    async save(path, buf, contentType, opts = {}) { saved.push({ path, size: buf.length, contentType, noToken: !!opts.noToken }); return { token: opts.noToken ? null : 'tok123', bucket: 'demo-bucket' }; },
    async remove(path) { removed.push(path); },
    async signedUrl(path, ttlMs) { signed.push({ path, ttlMs }); return `https://storage.googleapis.com/demo-bucket/${path}?X-Goog-Expires=${ttlMs / 1000}&X-Goog-Signature=sig`; },
  },
});
const call = (name, data, who) => local[name].run(data, ctxOf(who));

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) { results.push(false); console.log(`FAIL - ${name} :: ${e.stack || e.message}`); }
};
async function expectCode(promise, code) {
  let caught;
  await assert.rejects(promise, (e) => { caught = e; assert.strictEqual((e.details && e.details.code) || e.message, code); return true; });
  return caught;
}
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
const get = async (p) => (await db.doc(p).get()).data();
const car = (plate) => ({ carModel: 'Cobalt', carColor: 'oq', carPlate: plate, carSeats: 4, carBrand: 'Chevrolet', carYear: 2020 });
const PDF = Buffer.from('%PDF-1.7\n1 0 obj\n<<>>\nendobj\n').toString('base64');
const JPG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(64, 1)]).toString('base64');
const tp = async (requestId, who) => { for (const side of ['front', 'back']) await call('insuranceUploadTechPassport', { requestId, side, fileBase64: JPG }, who); };
const CONFIG = { stage: 'internal', internalPhones: [U, V, W], pilotDistrictIds: [], agentPhones: [AGENT], reporterPhones: [REP], kaskoEnabled: false, remindersEnabled: true };
const CAMPAIGN = { stage: 'internal', internalPhones: [U, V, W], pilotDistrictIds: [], bonusEnabled: true, bonusAmount: 100000, bonusValidityDays: 60, bonusMaxOrderSharePct: 100, bonusBudgetTotal: 150000, oilEnabled: true, oilSteps: [{ count: 1, pct: 50 }, { count: 2, pct: 100 }] };
// Эга ОСАГО жадвали (schema 2, 20 қатор); тест учун «бошқа ҳудуд / енгил / чекланган» = 200 000. КАСКО — 20 қатор 900 000.
const OSAGO_ROWS = ci.ownerDraftRows().map((r) => (r.zone === 'other' && r.vehicleType === 'car' && r.driverScope === 'limited' ? { ...r, price: 200000 } : r));
const ROWS = [...OSAGO_ROWS, ...OSAGO_ROWS.map((r) => ({ ...r, policyType: 'kasko', price: 900000 }))];
let reqU1;

async function main() {
  await clearEmulator();
  await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
  await db.doc(`users/${AGENT}`).set({ role: 'dispatcher' });
  await db.doc(`users/${REP}`).set({ role: 'staff' });
  await db.doc(`users/${U}`).set({ role: 'user', districtId: 'gurlan', appLang: 'uz_Cyrl', bonusBalance: 0, ...car('01 A 123 BC') });
  await db.doc(`users/${V}`).set({ role: 'user', districtId: 'gurlan', appLang: 'uz_Latn', bonusBalance: 100000, incentiveBalance: 0, ...car('90 777 ZZZ') });
  await db.doc(`users/${W}`).set({ role: 'user', districtId: 'gurlan', appLang: 'ru', bonusBalance: 0, ...car('90-777-zzz') });
  await db.doc(`users/${OUT}`).set({ role: 'user', districtId: 'gurlan', ...car('40 B 555 CC') });
  await db.doc('geo_districts/gurlan').set({ regionId: 'xorazm' });
  await db.doc('oil_change_services/ava_gurlan').set({ name: 'AVA Сервис', isAvaCenter: true, districtId: 'gurlan' });

  await check('C1 админ: созлама, тариф v1→v2 (ўзгармас), кампания + рағбат дастури (stage off); бошқалар рад; audit', async () => {
    await expectCode(call('adminInsuranceSaveConfig', { config: CONFIG }, U), 'PERMISSION_DENIED');
    await expectCode(call('adminInsuranceSaveConfig', { config: { ...CONFIG, stage: 'on' } }, ADMIN), 'CONFIG_INVALID');
    await call('adminInsuranceSaveConfig', { config: CONFIG }, ADMIN);
    await expectCode(call('adminInsurancePublishTariff', { rows: [{ ...ROWS[0], price: 1.5 }] }, ADMIN), 'TARIFF_INVALID');
    await expectCode(call('adminInsurancePublishTariff', { rows: [ROWS[0]], note: 'x' }, ADMIN), 'TARIFF_INVALID'); // етишмаган комбинациялар
    assert.strictEqual((await call('adminInsurancePublishTariff', { rows: OSAGO_ROWS, note: 'v1' }, ADMIN)).version, 1);
    assert.strictEqual((await call('adminInsurancePublishTariff', { rows: ROWS, note: 'v2' }, ADMIN)).version, 2);
    assert.deepStrictEqual([(await get('insurance_tariffs/v1')).rows.length, (await get('insurance_tariffs/v1')).schema], [20, 2]);
    await call('adminInsuranceSaveCampaign', { year: 2026, campaign: CAMPAIGN }, ADMIN);
    const prog = await get('incentive_programs/car_insurance_bonus');
    assert.deepStrictEqual([prog.stage, prog.kind, prog.counters.grantedAmount], ['off', 'car_insurance_bonus', 0]);
    const s = await call('adminInsuranceGetSettings', {}, ADMIN);
    assert.deepStrictEqual([s.config.activeTariffVersion, s.tariff.version, s.tariffVersions.length, s.campaigns[0].year], [2, 2, 2, 2026]);
    const au = (await db.collection('admin_audit').get()).docs.map((d) => d.data().action).sort();
    assert.deepStrictEqual(au, ['insurance_campaign', 'insurance_config', 'insurance_tariff_publish', 'insurance_tariff_publish']);
  });

  await check('C2 ҳолат: ички рўйхатдагига ҳудуд жадвали (Хоразм → бошқа ҳудуд, 200 000), КАСКО ёпиқ; бегонага мавжуд эмас', async () => {
    const st = await call('insuranceGetMyState', {}, U);
    assert.deepStrictEqual([st.available, st.tariffVersion, st.tariffSchema, st.derivedZone, st.options.length, st.car.plateKey, st.car.complete], [true, 2, 2, 'other', 20, '01A123BC', true]);
    assert.strictEqual(st.options.find((o) => o.zone === 'other' && o.vehicleType === 'car' && o.driverScope === 'limited').price, 200000);
    assert.ok(st.options.every((o) => o.policyType === 'osago'), 'КАСКО ёпиқ');
    assert.deepStrictEqual([st.campaign.year, st.campaign.bonusAmount, st.enrollment], [2026, 100000, null]);
    const out = await call('insuranceGetMyState', {}, OUT);
    assert.deepStrictEqual([out.available, out.options.length, out.campaign], [false, 0, null]);
    await expectCode(call('insuranceCreateRequest', { policyType: 'osago', vehicleType: 'car', termMonths: 12, driverScope: 'limited', idempotencyKey: 'out-key-0001' }, OUT), 'NOT_AVAILABLE');
    await expectCode(call('insuranceCreateRequest', { policyType: 'kasko', vehicleType: 'car', termMonths: 12, driverScope: 'limited', idempotencyKey: 'u-kasko-0001' }, U), 'POLICY_TYPE_OFF');
    await expectCode(call('insuranceCreateRequest', { policyType: 'osago', vehicleType: 'bus', zone: 'cis', termMonths: 12, driverScope: 'limited', idempotencyKey: 'u-bus-00001' }, U), 'CIS_VEHICLE_NOT_ALLOWED');
    await expectCode(call('insuranceCreateRequest', { policyType: 'osago', vehicleType: 'car', termMonths: 12, idempotencyKey: 'u-noscope-01' }, U), 'INVALID_REQUEST');
    await expectCode(call('insuranceCreateRequest', { policyType: 'osago', vehicleType: 'car', zone: 'mars', termMonths: 12, driverScope: 'limited', idempotencyKey: 'u-zone-0001' }, U), 'INVALID_REQUEST');
    await expectCode(call('insuranceCreateRequest', { policyType: 'osago', vehicleType: 'car', termMonths: 6, driverScope: 'limited', idempotencyKey: 'u-term-0001' }, U), 'TARIFF_NOT_FOUND');
  });

  await check('C3 ариза: tariffVersion+нарх сақланади, такрор — бир ариза, иккинчи очиқ ариза рад; тариф ўзгарса эски ариза нархи ўзгармайди', async () => {
    const r = await call('insuranceCreateRequest', { policyType: 'osago', vehicleType: 'car', termMonths: 12, driverScope: 'limited', idempotencyKey: 'u-req-00001' }, U);
    reqU1 = r.requestId;
    assert.deepStrictEqual([r.price, r.tariffVersion, r.duplicate], [200000, 2, false]);
    assert.strictEqual((await call('insuranceCreateRequest', { policyType: 'osago', vehicleType: 'car', termMonths: 12, driverScope: 'limited', idempotencyKey: 'u-req-00001' }, U)).duplicate, true);
    await expectCode(call('insuranceCreateRequest', { policyType: 'osago', vehicleType: 'car', termMonths: 12, driverScope: 'limited', idempotencyKey: 'u-req-00002' }, U), 'OPEN_REQUEST_EXISTS');
    await call('adminInsurancePublishTariff', { rows: ROWS.map((x) => ({ ...x, price: x.price + 50000 })), note: 'v3' }, ADMIN);
    const doc = await get(`insurance_requests/${reqU1}`);
    assert.deepStrictEqual([doc.status, doc.price, doc.tariffVersion, doc.car.plateKey, doc.uid], ['requested', 200000, 2, '01A123BC', U]);
    assert.strictEqual((await db.collection('insurance_events').where('requestId', '==', reqU1).get()).size, 1);
  });

  await check('C4 тўлов: маблағ етмаса — рад, ҳеч нарса ёзилмайди; тўлдирилгач — ҳамён −200 000, журнал, ledger; такрор — икки марта ечилмайди', async () => {
    await expectCode(call('insurancePayRequest', { requestId: reqU1 }, U), 'TECH_PASSPORT_REQUIRED'); // эга 2026-11-28
    await tp(reqU1, U);
    await expectCode(call('insurancePayRequest', { requestId: reqU1 }, U), 'INSUFFICIENT_BALANCE');
    assert.strictEqual((await get(`insurance_requests/${reqU1}`)).status, 'requested');
    await expectCode(call('insurancePayRequest', { requestId: reqU1 }, V), 'REQUEST_NOT_FOUND');
    await db.doc(`users/${U}`).update({ bonusBalance: 250000 });
    const q = await call('insuranceQuote', { requestId: reqU1 }, U);
    assert.deepStrictEqual([q.walletDue, q.sufficient], [200000, true]);
    sent.length = 0;
    const p = await call('insurancePayRequest', { requestId: reqU1 }, U);
    assert.deepStrictEqual([p.status, p.walletPaid, p.duplicate], ['paid', 200000, false]);
    const again = await call('insurancePayRequest', { requestId: reqU1 }, U);
    assert.strictEqual(again.duplicate, true);
    assert.strictEqual((await get(`users/${U}`)).bonusBalance, 50000);
    const led = await get(`users/${U}/wallet_ledger/insurance_pay_${reqU1}`);
    assert.deepStrictEqual([led.amount, led.module, led.type], [-200000, 'insurance', 'purchase_debit']);
    const j = await get(`journal_entries/bonus:insurance_pay_${reqU1}`);
    assert.deepStrictEqual([j.amount, j.kind, j.refType], [200000, 'purchase_debit', 'insurance_request']);
    assert.ok(sent.some((m) => m.userId === U && m.source === 'insurance_paid'));
    assert.ok(sent.some((m) => m.userId === AGENT && m.source === 'insurance_agent_new'));
  });

  await check('C5 агент: оддий фойдаланувчи рад; рўйхат → бошлаш → нотўғри файл рад → PDF полис; профил муддати, индекс, хабар; ҳавола эгасига', async () => {
    await expectCode(call('insuranceAgentListRequests', { status: 'paid' }, U), 'PERMISSION_DENIED');
    await expectCode(call('insuranceAgentListRequests', { status: 'paid' }, REP), 'PERMISSION_DENIED');
    const l = await call('insuranceAgentListRequests', { status: 'paid' }, AGENT);
    assert.deepStrictEqual(l.requests.map((x) => x.requestId), [reqU1]);
    await call('insuranceAgentStart', { requestId: reqU1 }, AGENT);
    assert.strictEqual((await get(`insurance_requests/${reqU1}`)).status, 'in_progress');
    const base = { requestId: reqU1, policyNumber: 'ABC 1234567', validFrom: '2026-11-29', validTo: '2027-11-28' };
    await expectCode(call('insuranceAgentIssuePolicy', { ...base, fileBase64: Buffer.from('<html>x</html>!!!').toString('base64') }, AGENT), 'FILE_INVALID');
    await expectCode(call('insuranceAgentIssuePolicy', { ...base, validTo: '2026-11-01', fileBase64: PDF }, AGENT), 'DATE_INVALID');
    sent.length = 0;
    const r = await call('insuranceAgentIssuePolicy', { ...base, fileBase64: PDF }, AGENT);
    assert.strictEqual(r.duplicate, false);
    assert.strictEqual((await call('insuranceAgentIssuePolicy', { ...base, fileBase64: PDF }, AGENT)).duplicate, true);
    const pol = saved.filter((x) => x.path.startsWith('insurance_policies/'));
    assert.strictEqual(pol.length, 1);
    assert.ok(pol[0].path.startsWith(`insurance_policies/${reqU1}/`) && pol[0].contentType === 'application/pdf');
    const doc = await get(`insurance_requests/${reqU1}`);
    assert.deepStrictEqual([doc.status, doc.policy.number, doc.policy.validTo], ['issued', 'ABC 1234567', '2027-11-28']);
    assert.deepStrictEqual([(await get(`users/${U}`)).carInsurance.expiresOn, (await get(`insurance_expiry_index/${U}`)).source], ['2027-11-28', 'ava']);
    assert.strictEqual(await get(`insurance_open/${U}_osago`), undefined, 'қулф очилди');
    assert.ok(sent.some((m) => m.userId === U && m.source === 'insurance_issued' && m.body.includes('28.11.2027')));
    const link = await call('insuranceGetPolicyLink', { requestId: reqU1 }, U);
    assert.ok(link.url.includes('demo-bucket') && link.url.includes('token=tok123'));
    await expectCode(call('insuranceGetPolicyLink', { requestId: reqU1 }, V), 'PERMISSION_DENIED');
    assert.ok((await call('insuranceGetPolicyLink', { requestId: reqU1 }, AGENT)).url);
    await expectCode(call('insuranceAgentCancel', { requestId: reqU1, reason: 'xato' }, AGENT), 'INVALID_TRANSITION');
  });

  await check('C6 рағбат (бонус): 100 000 грант (ечилмайди, incentiveBalance); бир номер — бошқа шахсга рад; такрор — дубликат; бюджет', async () => {
    sent.length = 0;
    const r = await call('insuranceChooseCarOffer', { option: 'bonus' }, V);
    assert.deepStrictEqual([r.option, r.amount, r.duplicate], ['bonus', 100000, false]);
    const g = await get(`incentive_grants/car_insurance_bonus_2026_${V}`);
    assert.deepStrictEqual([g.amount, g.buckets, g.status, g.uid], [100000, { any: 100000 }, 'active', V]);
    assert.strictEqual((await get(`users/${V}`)).incentiveBalance, 100000);
    assert.strictEqual((await get(`users/${V}`)).bonusBalance, 100000, 'ҳамён (ечиладиган) ўзгармади');
    assert.ok(sent.some((m) => m.userId === V && m.source === 'insurance_bonus' && m.body.includes('100 000')));
    await expectCode(call('insuranceChooseCarOffer', { option: 'bonus' }, W), 'PLATE_ALREADY_ENROLLED'); // '90-777-zzz' = '90 777 ZZZ'
    assert.strictEqual((await call('insuranceChooseCarOffer', { option: 'oil' }, V)).duplicate, true);
    assert.strictEqual((await get('insurance_campaigns/2026')).counters.bonusGrantedAmount, 100000);
  });

  await check('C7 тўлов бонус+ҳамён, агент бекор қилади → ҳамён ва грант тикланади (идемпотент), журнал', async () => {
    const reqV = (await call('insuranceCreateRequest', { policyType: 'osago', vehicleType: 'car', termMonths: 12, driverScope: 'limited', idempotencyKey: 'v-req-00001' }, V)).requestId;
    const doc0 = await get(`insurance_requests/${reqV}`);
    assert.deepStrictEqual([doc0.price, doc0.tariffVersion], [250000, 3]); // v3 (Хоразм 250 000)
    // 250 000 − бонус 100 000 = 150 000 > ҳамён 100 000 → рад, грант ўзгармайди.
    await tp(reqV, V);
    await expectCode(call('insurancePayRequest', { requestId: reqV }, V), 'INSUFFICIENT_BALANCE');
    assert.strictEqual((await get(`incentive_grants/car_insurance_bonus_2026_${V}`)).remaining, 100000);
    await db.doc(`users/${V}`).update({ bonusBalance: 160000 });
    const p = await call('insurancePayRequest', { requestId: reqV }, V);
    assert.deepStrictEqual([p.incentive, p.walletPaid], [100000, 150000]);
    assert.deepStrictEqual([(await get(`users/${V}`)).bonusBalance, (await get(`users/${V}`)).incentiveBalance], [10000, 0]);
    assert.strictEqual((await get(`incentive_grants/car_insurance_bonus_2026_${V}`)).status, 'spent');
    await expectCode(call('insuranceAgentCancel', { requestId: reqV, reason: 'x' }, AGENT), 'REASON_REQUIRED');
    sent.length = 0;
    const c = await call('insuranceAgentCancel', { requestId: reqV, reason: 'Ҳужжат мос эмас' }, AGENT);
    assert.deepStrictEqual(c.refund, { wallet: 150000, incentive: 100000, oilRestored: false });
    assert.strictEqual((await call('insuranceAgentCancel', { requestId: reqV, reason: 'Ҳужжат мос эмас' }, AGENT)).duplicate, true);
    const u = await get(`users/${V}`);
    assert.deepStrictEqual([u.bonusBalance, u.incentiveBalance], [160000, 100000]);
    assert.strictEqual((await get(`incentive_grants/car_insurance_bonus_2026_${V}`)).remaining, 100000);
    assert.strictEqual((await get(`users/${V}/wallet_ledger/insurance_refund_${reqV}`)).amount, 150000);
    assert.ok(sent.some((m) => m.userId === V && m.source === 'insurance_cancelled'));
    const ev = (await db.collection('insurance_events').where('requestId', '==', reqV).get()).docs.map((d) => d.data().type).sort();
    assert.deepStrictEqual(ev, ['cancelled', 'paid', 'requested', 'techpass_back', 'techpass_front']);
  });

  await check('C8 мой дастури: ҳисобот (номер шакли бошқача) → 1/2 (50%), бир кунда такрор/бошқа ҳисобот — ҳисобланмайди; эртага → 2/2 (100%); кейин goal_reached', async () => {
    await call('insuranceChooseCarOffer', { option: 'oil' }, U);
    await expectCode(call('insuranceSubmitServiceReport', { centerId: 'ava_gurlan', date: '2026-11-28', plates: ['01A123BC'] }, AGENT), 'PERMISSION_DENIED');
    await expectCode(call('insuranceSubmitServiceReport', { centerId: 'ava_gurlan', date: '2026-11-29', plates: ['01A123BC'] }, REP), 'DATE_INVALID');
    await expectCode(call('insuranceSubmitServiceReport', { centerId: 'nope', date: '2026-11-28', plates: ['01A123BC'] }, REP), 'CENTER_NOT_FOUND');
    sent.length = 0;
    const r1 = await call('insuranceSubmitServiceReport', { centerId: 'ava_gurlan', date: '2026-11-28', plates: ['01 a 123 bc', '95 X 000 XX', '01-A-123-BC', '1'] }, REP);
    assert.deepStrictEqual(r1.results.map((x) => x.result), ['credited', 'not_enrolled', 'duplicate', 'invalid']);
    assert.ok(sent.some((m) => m.userId === U && m.source === 'insurance_oil' && m.body.includes('1/2') && m.body.includes('50%')));
    const r2 = await call('insuranceSubmitServiceReport', { centerId: 'ava_gurlan', date: '2026-11-28', plates: ['01A123BC'] }, REP);
    assert.deepStrictEqual(r2.results.map((x) => x.result), ['duplicate']);
    let st = await call('insuranceGetMyState', {}, U);
    assert.deepStrictEqual([st.enrollment.option, st.enrollment.oilChanges, st.enrollment.discountPct], ['oil', 1, 50]);
    fakeNow += 86400000;
    const r3 = await call('insuranceSubmitServiceReport', { centerId: 'ava_gurlan', date: '2026-11-29', plates: ['01A123BC'] }, REP);
    assert.deepStrictEqual(r3.results.map((x) => x.result), ['credited']);
    fakeNow += 86400000;
    const r4 = await call('insuranceSubmitServiceReport', { centerId: 'ava_gurlan', date: '2026-11-30', plates: ['01A123BC'] }, REP);
    assert.deepStrictEqual(r4.results.map((x) => x.result), ['goal_reached']);
    st = await call('insuranceGetMyState', {}, U);
    assert.deepStrictEqual([st.enrollment.oilChanges, st.enrollment.discountPct], [2, 100]);
    const hist = await call('insuranceListServiceReports', { limit: 10 }, REP);
    assert.strictEqual(hist.reports.length, 4);
  });

  await check('C9 100% чегирма: ҳамёндан 0 сўм, чегирма ишлатилди; бекор → чегирма қайтади; қайта тўлов → яна 100%', async () => {
    const r = await call('insuranceCreateRequest', { policyType: 'osago', vehicleType: 'car', termMonths: 12, driverScope: 'limited', idempotencyKey: 'u-req-00003' }, U);
    const bal0 = (await get(`users/${U}`)).bonusBalance;
    await tp(r.requestId, U);
    const p = await call('insurancePayRequest', { requestId: r.requestId }, U);
    assert.deepStrictEqual([p.oilDiscount, p.walletPaid, p.incentive], [250000, 0, 0]);
    assert.strictEqual((await get(`users/${U}`)).bonusBalance, bal0);
    assert.strictEqual((await call('insuranceGetMyState', {}, U)).enrollment.discountUsed, true);
    const c = await call('insuranceAgentCancel', { requestId: r.requestId, reason: 'Агент бекор қилди' }, AGENT);
    assert.deepStrictEqual(c.refund, { wallet: 0, incentive: 0, oilRestored: true });
    const st = await call('insuranceGetMyState', {}, U);
    assert.deepStrictEqual([st.enrollment.discountUsed, st.enrollment.discountPct], [false, 100]);
    const r2 = await call('insuranceCreateRequest', { policyType: 'osago', vehicleType: 'car', termMonths: 12, driverScope: 'limited', idempotencyKey: 'u-req-00004' }, U);
    await tp(r2.requestId, U);
    assert.strictEqual((await call('insurancePayRequest', { requestId: r2.requestId }, U)).oilDiscount, 250000);
  });

  await check('C10 эслатмалар: 4 ва 3 кун олдин бир мартадан; такрор ишга тушса — йўқ; opt-out — йўқ; мижоз бекор қилиши (тўланмаган)', async () => {
    fakeNow = Date.UTC(2026, 11, 1, 6); // 2026-12-01
    await call('insuranceSetMyExpiry', { expiresOn: '2026-12-05', policyType: 'osago' }, W);
    await expectCode(call('insuranceSetMyExpiry', { expiresOn: '2026-02-30' }, W), 'DATE_INVALID');
    await call('insuranceSetMyExpiry', { expiresOn: '2026-12-05' }, V);
    await db.doc(`users/${V}`).update({ insuranceRemindersOptIn: false });
    sent.length = 0;
    let s = await api.runReminders(fakeNow);
    assert.deepStrictEqual([s.sent, s.skipped], [1, 1]);
    assert.ok(sent[0].userId === W && sent[0].body.includes('4') && sent[0].body.includes('05.12.2026'));
    s = await api.runReminders(fakeNow);
    assert.strictEqual(s.sent, 0);
    fakeNow += 86400000;
    s = await api.runReminders(fakeNow);
    assert.strictEqual(s.sent, 1);
    assert.ok(await get(`insurance_reminder_log/${W}_2026-12-05_d3`));
    // Мижоз тўланмаган аризани бекор қилади; тўланганини — йўқ.
    const r = await call('insuranceCreateRequest', { policyType: 'osago', vehicleType: 'car', termMonths: 12, driverScope: 'limited', idempotencyKey: 'w-req-00001' }, W);
    await call('insuranceCancelMyRequest', { requestId: r.requestId }, W);
    assert.strictEqual((await get(`insurance_requests/${r.requestId}`)).status, 'cancelled');
    assert.strictEqual(await get(`insurance_open/${W}_osago`), undefined);
  });

  await check('C11 ҳудуд (эга 2026-11-28): Тошкент тумани → tashkent автоматик; фойдаланувчи МДҲ/бошқа ҳудудни танлайди; аризада zone/driverScope сақланади (v3 = жадвал + 50 000)', async () => {
    await db.doc('geo_districts/chilonzor').set({ regionId: 'toshkent_shahri' });
    await db.doc(`users/${W}`).update({ districtId: 'chilonzor' });
    const st = await call('insuranceGetMyState', {}, W);
    assert.deepStrictEqual([st.derivedZone, st.tariffSchema, st.zones, st.cisVehicleTypes], ['tashkent', 2, ['tashkent', 'other', 'cis'], ['car', 'truck']]);
    const cases = [
      [{ vehicleType: 'truck', driverScope: 'unlimited' }, 722000, 'tashkent', 'auto'],
      [{ vehicleType: 'car', driverScope: 'limited', zone: 'cis' }, 370000, 'cis', 'user'],
      [{ vehicleType: 'moto', driverScope: 'unlimited', zone: 'other' }, 170000, 'other', 'user'],
      [{ vehicleType: 'bus', driverScope: 'limited', zone: 'tashkent' }, 434000, 'tashkent', 'auto'],
    ];
    let i = 0;
    for (const [sel, price, zone, source] of cases) {
      i += 1;
      const r = await call('insuranceCreateRequest', { policyType: 'osago', termMonths: 12, idempotencyKey: `w-zone-000${i}`, ...sel }, W);
      assert.strictEqual(r.price, price, JSON.stringify(sel));
      const doc = await get(`insurance_requests/${r.requestId}`);
      assert.deepStrictEqual([doc.zone, doc.zoneDerived, doc.zoneSource, doc.driverScope, doc.vehicleType, doc.tariffSchema, doc.tariffVersion], [zone, 'tashkent', source, sel.driverScope, sel.vehicleType, 2, 3]);
      await call('insuranceCancelMyRequest', { requestId: r.requestId }, W);
    }
    await expectCode(call('insuranceCreateRequest', { policyType: 'osago', vehicleType: 'moto', zone: 'cis', termMonths: 12, driverScope: 'unlimited', idempotencyKey: 'w-zone-cis-m' }, W), 'CIS_VEHICLE_NOT_ALLOWED');
    const s = await call('adminInsuranceGetSettings', {}, ADMIN);
    assert.deepStrictEqual([s.tariff.schema, s.draftRows, s.tariffSchema], [2, null, 2]);
  });

  await check('C12 эски (вилоят) жадвал фаол бўлса — эски йўл ишлайди (backward compat); админга эга жадвали қоралама', async () => {
    await db.doc('insurance_tariffs/v90').set({ version: 90, rows: [{ policyType: 'osago', regionId: '*', vehicleType: 'car', termMonths: 12, price: 111000 }] });
    await db.doc('insurance_config/main').update({ activeTariffVersion: 90 });
    const st = await call('insuranceGetMyState', {}, W);
    assert.deepStrictEqual([st.tariffSchema, st.options.length, st.options[0].price], [1, 1, 111000]);
    const r = await call('insuranceCreateRequest', { policyType: 'osago', vehicleType: 'car', termMonths: 12, idempotencyKey: 'w-legacy-001' }, W);
    assert.strictEqual(r.price, 111000);
    assert.strictEqual((await get(`insurance_requests/${r.requestId}`)).zone, undefined);
    const s = await call('adminInsuranceGetSettings', {}, ADMIN);
    assert.deepStrictEqual([s.tariff.schema, s.draftRows.length], [1, 20]);
    assert.strictEqual(s.draftRows.find((x) => x.zone === 'cis' && x.vehicleType === 'truck' && x.driverScope === 'unlimited').price, 1120000);
  });

  await check('C13 техпаспорт (эга 2026-11-28): фақат эгаси, расм тури, ҳаволалар эгаси/агентга; агент тузатиши (тўланмаган — нарх; тўланган — нарх ўзгарса бекор шарт); полис/бекордан 30 кун кейин расмлар ўчади', async () => {
    await db.doc('insurance_config/main').update({ activeTariffVersion: 3 });
    await db.doc(`users/${W}`).update({ bonusBalance: 5000000 });
    for (const d of (await db.collection('insurance_requests').where('uid', '==', W).where('status', '==', 'requested').get()).docs) {
      await call('insuranceCancelMyRequest', { requestId: d.id }, W);
    }
    const r = await call('insuranceCreateRequest', { policyType: 'osago', vehicleType: 'car', termMonths: 12, driverScope: 'limited', idempotencyKey: 'w-tp-000001' }, W);
    await expectCode(call('insuranceUploadTechPassport', { requestId: r.requestId, side: 'front', fileBase64: PDF }, W), 'IMAGE_INVALID');
    await expectCode(call('insuranceUploadTechPassport', { requestId: r.requestId, side: 'top', fileBase64: JPG }, W), 'INVALID_REQUEST');
    await expectCode(call('insuranceUploadTechPassport', { requestId: r.requestId, side: 'front', fileBase64: JPG }, V), 'REQUEST_NOT_FOUND');
    await call('insuranceUploadTechPassport', { requestId: r.requestId, side: 'front', fileBase64: JPG }, W);
    await expectCode(call('insurancePayRequest', { requestId: r.requestId }, W), 'TECH_PASSPORT_REQUIRED');
    await call('insuranceUploadTechPassport', { requestId: r.requestId, side: 'front', fileBase64: JPG }, W); // алмаштириш — эскиси ўчади
    assert.strictEqual(removed.length, 1);
    await call('insuranceUploadTechPassport', { requestId: r.requestId, side: 'back', fileBase64: JPG }, W);
    const doc = await get(`insurance_requests/${r.requestId}`);
    assert.deepStrictEqual([doc.techPassport.front, doc.techPassport.back], [true, true]);
    assert.strictEqual(JSON.stringify(doc).includes('tok123'), false, 'ариза ҳужжатида ҳавола/token йўқ');
    const own = await call('insuranceGetTechPassportLinks', { requestId: r.requestId }, W);
    // Эга 2026-11-28: доимий token ЭМАС — қисқа муддатли (≤10 дақ) signed URL, ҳар чақирувда янги; файлларда token йўқ.
    assert.ok(own.front.includes('insurance_techpass') && own.back.includes('X-Goog-Signature'));
    assert.ok(!own.front.includes('token='));
    assert.strictEqual(own.expiresInSec, 600);
    assert.ok(signed.every((x) => x.ttlMs <= 10 * 60 * 1000));
    assert.ok(saved.filter((x) => x.path.startsWith('insurance_techpass/')).every((x) => x.noToken));
    const tf = await get(`insurance_techpass_files/${r.requestId}`);
    assert.strictEqual(JSON.stringify(tf).includes('token'), false);
    assert.ok((await call('insuranceGetTechPassportLinks', { requestId: r.requestId }, AGENT)).front);
    await expectCode(call('insuranceGetTechPassportLinks', { requestId: r.requestId }, V), 'PERMISSION_DENIED');
    // Тўланмаган — агент тузатади, нарх қайта (v3: бошқа ҳудуд/юк/чекланмаган = 560 000 + 50 000).
    await expectCode(call('insuranceAgentCorrect', { requestId: r.requestId, zone: 'other', vehicleType: 'truck', driverScope: 'unlimited', reason: 'x' }, AGENT), 'REASON_REQUIRED');
    await expectCode(call('insuranceAgentCorrect', { requestId: r.requestId, zone: 'other', vehicleType: 'truck', driverScope: 'unlimited', reason: 'техпаспорт' }, W), 'PERMISSION_DENIED');
    const c1 = await call('insuranceAgentCorrect', { requestId: r.requestId, zone: 'other', vehicleType: 'truck', driverScope: 'unlimited', reason: 'техпаспорт: юк' }, AGENT);
    assert.strictEqual(c1.price, 610000);
    await call('insurancePayRequest', { requestId: r.requestId }, W);
    // Тўланган — нарх ўзгарса рад (бекор қилиш шарт); ўзгармаса — рухсат.
    const e = await expectCode(call('insuranceAgentCorrect', { requestId: r.requestId, zone: 'tashkent', vehicleType: 'truck', driverScope: 'unlimited', reason: 'техпаспорт' }, AGENT), 'PRICE_CHANGED_CANCEL_REQUIRED');
    assert.deepStrictEqual([e.details.newPrice, e.details.price], [722000, 610000]);
    const same = await call('insuranceAgentCorrect', { requestId: r.requestId, zone: 'other', vehicleType: 'truck', driverScope: 'unlimited', reason: 'текширилди' }, AGENT);
    assert.strictEqual(same.price, 610000);
    const ev = (await db.collection('insurance_events').where('requestId', '==', r.requestId).get()).docs.map((x) => x.data().type);
    assert.ok(ev.includes('corrected') && ev.includes('techpass_back'));
    // Бекор — 30 кундан кейин расмлар ўчади (идемпотент).
    await call('insuranceAgentCancel', { requestId: r.requestId, reason: 'маълумот нотўғри' }, AGENT);
    const purgeAfter = (await get(`insurance_techpass_files/${r.requestId}`)).purgeAfter.toMillis();
    assert.ok(Math.abs(purgeAfter - (fakeNow + 30 * 86400000)) < 5000);
    await api.runTechPassPurge(fakeNow + 29 * 86400000); // аввалги тестлардаги эски ёзувлар тозаланади
    assert.ok(await get(`insurance_techpass_files/${r.requestId}`), '29-кун — ҳали ўчмайди');
    removed.length = 0;
    const pr = await api.runTechPassPurge(fakeNow + 31 * 86400000);
    assert.strictEqual(pr.purged >= 1, true);
    assert.strictEqual(removed.length >= 2, true);
    assert.strictEqual(await get(`insurance_techpass_files/${r.requestId}`), undefined);
    assert.deepStrictEqual((await get(`insurance_requests/${r.requestId}`)).techPassport.purged, true);
    assert.strictEqual((await api.runTechPassPurge(fakeNow + 31 * 86400000)).purged, 0);
  });

  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
