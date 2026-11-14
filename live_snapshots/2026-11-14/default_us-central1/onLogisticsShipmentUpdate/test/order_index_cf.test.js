/**
 * «Барча буюртмалар» — `order_index` синхронизацияси (триггерлар чақирадиган
 * `syncOne`), `adminSetSectionGrant`, `setUserRoleByAdmin` audit.
 * Firestore + Auth Emulator, Admin SDK:
 *   firebase emulators:exec --only firestore,auth --project demo-order-index \
 *     "node functions/test/order_index_cf.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-order-index';
process.env.FUNCTIONS_EMULATOR = 'true';

const fns = require('../index.js');
const admin = require('firebase-admin');
const db = admin.firestore();
const oi = require('../order_index');

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const ADMIN = '998905000001';
const SUPER = '998905000002';
const DISP = '998905000003';
const FIN = '998905000004';
const USER = '998905000005';
const MIN = 60000;
const T0 = Date.UTC(2026, 9, 12, 5, 0); // 2026-10-12 10:00 Тошкент (Душанба)
const ts = (m) => admin.firestore.Timestamp.fromMillis(m);

async function wipe(col) {
  const docs = await db.collection(col).listDocuments();
  await Promise.all(docs.map((d) => db.recursiveDelete(d)));
}
const idx = async (id) => {
  const s = await db.collection('order_index').doc(id).get();
  return s.exists ? s.data() : null;
};
const sync = (col, id, data, updateMs) =>
  oi.syncOne(db, admin, { sourceCollection: col, sourceId: id, data, updateMs, eventMs: updateMs || T0 });
async function rejectsWith(promise, code, detailCode) {
  try { await promise; } catch (e) {
    assert.strictEqual(e.code, code, `kutilgan ${code}, keldi ${e.code}: ${e.message}`);
    if (detailCode) assert.strictEqual((e.details || {}).code, detailCode);
    return;
  }
  throw new Error(`kutilgan ${code}, lekin muvaffaqiyatli`);
}

(async () => {
  await Promise.all(['order_index', 'demands', 'settings', 'users', 'admin_section_grants', 'admin_audit'].map(wipe));
  oi._resetSettingsCache();

  // ─── order_index ───────────────────────────────────────────────────
  await check('I1 нон буюртмаси: индекс ёзилади, вақтлар Timestamp, stuckAt = +15 дақ', async () => {
    const r = await sync('orders', 'o1', { type: 'bread', status: 'new', statusUpdatedAt: ts(T0), createdAt: ts(T0), userPhone: '998901234567', total: 8000 }, T0);
    assert.strictEqual(r.action, 'written');
    const d = await idx('bread_o1');
    assert.strictEqual(d.normStatus, 'NEW');
    assert.ok(d.createdAt instanceof admin.firestore.Timestamp);
    assert.strictEqual(d.stuckAt.toMillis(), T0 + 15 * MIN);
    assert.strictEqual(d.customerTail, '4567');
    assert.strictEqual(d.sourceId, 'o1');
  });

  await check('I2 босқич ўзгармаса stageSince сақланади; ўзгарса янгиланади', async () => {
    await sync('orders', 'o1', { type: 'bread', status: 'new', statusUpdatedAt: ts(T0 + 5 * MIN), total: 9000 }, T0 + 5 * MIN);
    let d = await idx('bread_o1');
    assert.strictEqual(d.stageSince.toMillis(), T0);
    assert.strictEqual(d.amount, 9000);
    await sync('orders', 'o1', { type: 'bread', status: 'accepted', statusUpdatedAt: ts(T0 + 10 * MIN) }, T0 + 10 * MIN);
    d = await idx('bread_o1');
    assert.strictEqual(d.normStatus, 'ACCEPTED');
    assert.strictEqual(d.stageSince.toMillis(), T0 + 10 * MIN);
  });

  await check('I3 эскирган ҳодиса (кичик updateTime) ёзилмайди', async () => {
    const r = await sync('orders', 'o1', { type: 'bread', status: 'new', statusUpdatedAt: ts(T0) }, T0 + 1 * MIN);
    assert.strictEqual(r.action, 'stale_skipped');
    assert.strictEqual((await idx('bread_o1')).normStatus, 'ACCEPTED');
  });

  await check('I4 такрор (бир хил updateTime) — иккинчи марта ёзилмайди (idempotent)', async () => {
    const r = await sync('orders', 'o1', { type: 'bread', status: 'accepted', statusUpdatedAt: ts(T0 + 10 * MIN) }, T0 + 10 * MIN);
    assert.strictEqual(r.action, 'stale_skipped');
  });

  await check('I5 ҳужжат ўчирилса индекс ҳам ўчади', async () => {
    const r = await sync('orders', 'o1', null, T0 + 20 * MIN);
    assert.strictEqual(r.action, 'removed');
    assert.strictEqual(await idx('bread_o1'), null);
  });

  await check('I6 «Овқат» буюртмаси индексга тушмайди', async () => {
    const r = await sync('orders', 'f1', { type: 'food', status: 'new' }, T0);
    assert.strictEqual(r.action, 'removed');
    assert.strictEqual((await db.collection('order_index').where('sourceId', '==', 'f1').get()).size, 0);
  });

  await check('I7 Logistics: LEG тури demands ҳужжатидан ўқилади (line_haul → 3 иш куни)', async () => {
    await db.collection('demands').doc('L2').set({
      module: 'logistics', status: 'in_progress',
      attributes: { legKind: 'line_haul', shipmentId: 's1' },
      location: { regionId: 'xorazm' }, destination: { regionId: 'tashkent' },
    });
    await sync('shipments', 's1', {
      status: 'in_transit', currentLegId: 'L2', updatedAt: ts(T0), fundedAt: ts(T0),
      priceSnapshot: { customerPrice: 42000 }, trackingNumber: 'AVA-1', origin: { regionId: 'xorazm' }, ownerId: '998901110000',
    }, T0);
    const d = await idx('logistics_s1');
    assert.strictEqual(d.stage, 'leg_linehaul_transit');
    assert.strictEqual(d.amount, 42000);
    assert.strictEqual(d.title, 'AVA-1');
    assert.strictEqual(d.stuckAt.toMillis(), T0 + 3 * 24 * 60 * MIN); // Сешанба…Пайшанба
  });

  await check('I8 курьер бўлмаган талаб (LEG) индексга тушмайди', async () => {
    const r = await sync('demands', 'L2', { module: 'logistics', status: 'active' }, T0);
    assert.strictEqual(r.action, 'removed');
    assert.strictEqual(await idx('courier_L2'), null);
  });

  await check('I9 созламадаги чегара қўлланади', async () => {
    await db.collection('settings').doc('all_orders_stuck').set({ version: 2, rules: { courier: { stages: { no_courier: { min: 5 } } } } });
    oi._resetSettingsCache();
    await sync('demands', 'c1', { module: 'courier', status: 'active', updatedAt: ts(T0), ownerId: '998901112233' }, T0);
    const d = await idx('courier_c1');
    assert.strictEqual(d.stuckAt.toMillis(), T0 + 5 * MIN);
    assert.strictEqual(d.rulesVersion, 2);
  });

  await check('I10 параллел икки ҳодиса — охирида янгиси қолади', async () => {
    await Promise.all([
      sync('carpet_wash_orders', 'k1', { status: 'new', updatedAt: ts(T0) }, T0),
      sync('carpet_wash_orders', 'k1', { status: 'accepted', updatedAt: ts(T0 + MIN) }, T0 + MIN),
    ]);
    const d = await idx('carpet_k1');
    assert.strictEqual(d.rawStatus, 'accepted');
  });

  // ─── Бўлим рухсати ─────────────────────────────────────────────────
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  await db.collection('users').doc(SUPER).set({ role: 'superadmin' });
  await db.collection('users').doc(DISP).set({ role: 'dispatcher' });
  await db.collection('users').doc(FIN).set({ role: 'finance' });
  await db.collection('users').doc(USER).set({ role: 'user' });
  const grant = (who, data) => fns.adminSetSectionGrant.run(data, ctxOf(who));
  const audits = async (kind) => (await db.collection('admin_audit').where('kind', '==', kind).get()).size;

  await check('G1 admin finance ходимига рухсат беради: ҳужжат + audit', async () => {
    const r = await grant(ADMIN, { targetPhone: FIN, section: 'all_orders', granted: true });
    assert.strictEqual(r.changed, true);
    const g = (await db.collection('admin_section_grants').doc(FIN).get()).data();
    assert.deepStrictEqual(g.sections, ['all_orders']);
    assert.strictEqual(g.updatedBy, ADMIN);
    assert.strictEqual(await audits('section_grant'), 1);
  });
  await check('G2 такрор — ўзгармайди, иккинчи audit йўқ', async () => {
    const r = await grant(ADMIN, { targetPhone: FIN, section: 'all_orders', granted: true });
    assert.strictEqual(r.changed, false);
    assert.strictEqual(await audits('section_grant'), 1);
  });
  await check('G3 dispatcher рухсат бера олмайди', async () => {
    await rejectsWith(grant(DISP, { targetPhone: FIN, section: 'all_orders', granted: true }), 'permission-denied');
  });
  await check('G4 оддий фойдаланувчига рухсат берилмайди', async () => {
    await rejectsWith(grant(SUPER, { targetPhone: USER, section: 'all_orders', granted: true }), 'failed-precondition', 'TARGET_NOT_PANEL');
    assert.strictEqual((await db.collection('admin_section_grants').doc(USER).get()).exists, false);
  });
  await check('G5 номаълум бўлим — рад', async () => {
    await rejectsWith(grant(SUPER, { targetPhone: FIN, section: 'finance_center', granted: true }), 'invalid-argument', 'SECTION_UNKNOWN');
  });
  await check('G6 superadmin рухсатни олади: audit section_revoke', async () => {
    const r = await grant(SUPER, { targetPhone: FIN, section: 'all_orders', granted: false });
    assert.strictEqual(r.changed, true);
    assert.deepStrictEqual((await db.collection('admin_section_grants').doc(FIN).get()).data().sections, []);
    assert.strictEqual(await audits('section_revoke'), 1);
  });
  await check('G7 кирмаган — unauthenticated', async () => {
    await rejectsWith(fns.adminSetSectionGrant.run({ targetPhone: FIN, section: 'all_orders', granted: true }, {}), 'unauthenticated');
  });

  // ─── Рол audit (D-ALL-6) ───────────────────────────────────────────
  await check('A1 setUserRoleByAdmin: рол ўзгарса role_change audit; ўзгармаса — йўқ', async () => {
    await fns.setUserRoleByAdmin.run({ adminPhone: SUPER, targetPhone: USER, role: 'auditor' }, ctxOf(SUPER));
    const a = (await db.collection('admin_audit').where('kind', '==', 'role_change').get()).docs.map((d) => d.data());
    assert.strictEqual(a.length, 1);
    assert.deepStrictEqual([a[0].from, a[0].to, a[0].actor, a[0].target], ['user', 'auditor', SUPER, USER]);
    await fns.setUserRoleByAdmin.run({ adminPhone: SUPER, targetPhone: USER, role: 'auditor' }, ctxOf(SUPER));
    assert.strictEqual((await db.collection('admin_audit').where('kind', '==', 'role_change').get()).size, 1);
  });

  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} order_index CF checks passed.`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
