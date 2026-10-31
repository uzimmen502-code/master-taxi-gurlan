/**
 * Kuryer toifasi — LEG (ega qarorlari 2026-10-31): `core/courier_scopes.js`, `adapters/logistics.isEligible`,
 * `api/logistics.acceptLeg`.
 *
 *   node functions_demand/test/courier_scopes_leg.test.js
 *
 * Qulflanadi:
 *   - LEG toifasi yo'nalishdan: bir tuman → district, bir viloyat → region, boshqa viloyat/noma'lum → republic;
 *   - toifa faol emas kuryerga LEG mos kelmaydi (push ham yo'q) — `courier_scope`;
 *   - match bo'lgandan keyin toifa olib tashlansa, acceptLeg RAD (`courier_scope`);
 *   - yuk tashuvchi (freight) bu qoidaga kirmaydi;
 *   - mantiq default codebase `functions/courier_scopes.js` bilan bir xil (o'sha fayl bo'lsa — solishtiriladi).
 */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const cs = require('../core/courier_scopes');
const adapter = require('../adapters/logistics');
const api = require('../api/logistics');
const {
  OWNER, K1, F1, NOW, ctx, makeDb, capDoc, seed, orderPayload, deps, fund, legOf,
} = require('./helpers/logistics_harness');

const K3 = '998906660006'; // kuryer, posilka oladi, faqat «Туман»

let passed = 0;
let failed = 0;
async function t(name, fn) {
  try { await fn(); passed += 1; console.log(`  OK  ${name}`); } catch (e) {
    failed += 1; console.log(`  XATO ${name}\n       ${e.stack}`);
  }
}

const G = { regionId: 'xorazm', districtId: 'gurlan' };
const U = { regionId: 'xorazm', districtId: 'urganch_shahri' };
const C = { regionId: 'toshkent_shahri', districtId: 'chilonzor' };

(async () => {
  await t('legScope: tuman / viloyat / respublika / noma\'lum → qattiqroq', () => {
    assert.strictEqual(cs.legScope(G, G), 'district');
    assert.strictEqual(cs.legScope(G, U), 'region');
    assert.strictEqual(cs.legScope(G, { regionId: 'xorazm' }), 'region', 'manzil tumani noma\'lum');
    assert.strictEqual(cs.legScope(G, C), 'republic');
    assert.strictEqual(cs.legScope(G, {}), 'republic', 'manzil yo\'q');
    assert.strictEqual(cs.legScope({}, G), 'republic', 'olish nuqtasi yo\'q');
  });

  await t('isScopeActive: eski hujjat = district; region faqat tasdiq bilan', () => {
    assert.strictEqual(cs.isScopeActive({}, 'district'), true);
    assert.strictEqual(cs.isScopeActive({}, 'region'), false);
    assert.strictEqual(cs.isScopeActive({ courier: { scopes: ['region'] } }, 'region'), false);
    assert.strictEqual(cs.isScopeActive({ courier: { scopes: ['region'] },
      review: { courierScopes: { region: { status: 'approved' } } } }, 'region'), true);
    assert.strictEqual(cs.isScopeActive({ courier: { scopes: ['region'] } }, 'district'), false);
    assert.strictEqual(cs.isScopeActive({}, 'city'), false);
  });

  await t('paritet: default codebase functions/courier_scopes.js bilan bir xil natija (bo\'lsa)', () => {
    const p = path.join(__dirname, '..', '..', 'functions', 'courier_scopes.js');
    if (!fs.existsSync(p)) { console.log('       (functions/courier_scopes.js bu daraxtda yo\'q — o\'tkazildi)'); return; }
    const main = require(p);
    const docs = [{}, { courier: { scopes: [] } }, { courier: { scopes: ['region', 'republic'] } },
      { courier: { scopes: ['district', 'region'] }, review: { courierScopes: { region: { status: 'approved' } } } },
      { courier: { scopes: ['republic'] }, review: { courierScopes: { republic: { status: 'rejected' } } } }];
    for (const d of docs) for (const s of cs.SCOPES) {
      assert.strictEqual(cs.isScopeActive(d, s), main.isScopeActive(d, s), `${JSON.stringify(d)} ${s}`);
    }
  });

  await t('isEligible: kuryer toifasi; freight ta\'sirlanmaydi', () => {
    const cfg = { logistics: { stage: 'public' } };
    const leg = (to) => ({ location: G, destination: to, attributes: { legKind: 'direct' } });
    const k3 = { providerId: K3, viaService: 'courier', regionIds: ['xorazm'], districtIds: ['gurlan', 'urganch_shahri'],
      raw: { acceptsParcels: true }, courierScopeReview: {} };
    assert.strictEqual(adapter.isEligible(leg(G), k3, cfg), true, 'tuman ichi — eski kuryer oladi');
    assert.strictEqual(adapter.isEligible(leg(U), k3, cfg), 'courier_scope', 'viloyat LEG — tasdiqsiz yo\'q');
    const k3r = { ...k3, raw: { scopes: ['district', 'region'] }, courierScopeReview: { region: { status: 'approved' } } };
    assert.strictEqual(adapter.isEligible(leg(U), k3r, cfg), true);
    const k3p = { ...k3r, courierScopeReview: { region: { status: 'pending' } } };
    assert.strictEqual(adapter.isEligible(leg(U), k3p, cfg), 'courier_scope', 'kutilayotgan — yo\'q');
    const f = { providerId: F1, viaService: 'freight', regionIds: ['xorazm'], districtIds: [], raw: {} };
    assert.strictEqual(adapter.isEligible(leg(U), f, cfg), true, 'freight — toifa qoidasi yo\'q');
  });

  await t('matching: faqat «Туман» kuryer Gurlan→Urganch LEG\'iga mos EMAS; K1 (viloyat tasdiqlangan) mos', async () => {
    const db = makeDb(seed({
      [`provider_capabilities/acc${K3}`]: capDoc(K3, 'courier', {
        active: true, regionIds: ['xorazm'], districtIds: ['gurlan', 'urganch_shahri'], acceptsParcels: true,
      }, 'approved'),
    }));
    const d = deps(db);
    const r = await api.makeCreateLogisticsOrder(d)(orderPayload({
      clientRequestId: 'req-scope-0001', destination: { ...U, lat: 41.55, lng: 60.63, addressText: 'Urganch 1' },
    }), ctx(OWNER));
    const shipmentId = r.shipmentIds[0];
    await fund(db, shipmentId);
    const legId = legOf(db, shipmentId)[0];
    const matches = db.dump('demand_matches');
    assert.ok(matches[`${legId}_${K1}`], 'K1 mos');
    assert.ok(!matches[`${legId}_${K3}`], 'K3 (faqat tuman) mos EMAS');
    await assert.rejects(() => api.makeAcceptLeg(d)({ legId }, ctx(K3)), (e) => e.code === 'permission-denied');
  });

  await t('acceptLeg (audit L6 qayta tekshiruvi): match bor, toifa keyin olib tashlangan → not_matched/why=courier_scope; qaytarilsa — oladi', async () => {
    const db = makeDb(seed({ [`users/${K1}`]: { accountId: `acc${K1}` } }));
    const d = deps(db);
    const r = await api.makeCreateLogisticsOrder(d)(orderPayload({
      clientRequestId: 'req-scope-0002', destination: { ...U, lat: 41.55, lng: 60.63, addressText: 'Urganch 2' },
    }), ctx(OWNER));
    const shipmentId = r.shipmentIds[0];
    await fund(db, shipmentId);
    const legId = legOf(db, shipmentId)[0];
    assert.ok(db.dump('demand_matches')[`${legId}_${K1}`], 'K1 mos (match bor)');
    const capRef = db.collection('provider_capabilities').doc(`acc${K1}`);
    await capRef.update({ review: { courierScopes: { region: { status: 'rejected' } } } });
    await assert.rejects(() => api.makeAcceptLeg(d)({ legId }, ctx(K1)),
      (e) => e.code === 'permission-denied' && e.details && e.details.reason === 'not_matched'
        && e.details.why === 'courier_scope');
    assert.strictEqual(db.dump('demands')[legId].status, 'active', 'LEG o\'zgarmadi');
    await capRef.update({ review: { courierScopes: { region: { status: 'approved' } } } });
    await api.makeAcceptLeg(d)({ legId }, ctx(K1));
    assert.strictEqual(db.dump('demands')[legId].assignment.providerId, K1);
  });

  await t('acceptLeg: kuryer+freight bitta odam — freight ishlasa toifa talab qilinmaydi', async () => {
    const both = {
      ...capDoc(F1, 'freight', { active: true, regionIds: ['xorazm', 'toshkent_shahri'], districtIds: [] }, 'enabled'),
    };
    const db = makeDb(seed({ [`users/${F1}`]: { accountId: `acc${F1}` }, [`provider_capabilities/acc${F1}`]: both }));
    const d = deps(db);
    const r = await api.makeCreateLogisticsOrder(d)(orderPayload({
      clientRequestId: 'req-scope-0003', destination: { ...U, lat: 41.55, lng: 60.63, addressText: 'Urganch 3' },
    }), ctx(OWNER));
    const shipmentId = r.shipmentIds[0];
    await fund(db, shipmentId);
    const legId = legOf(db, shipmentId)[0];
    assert.ok(db.dump('demand_matches')[`${legId}_${F1}`], 'F1 mos');
    await api.makeAcceptLeg(d)({ legId }, ctx(F1));
    assert.strictEqual(db.dump('demands')[legId].assignment.providerId, F1);
    assert.ok(NOW);
  });

  console.log(`\n${passed} test o'tdi.${failed ? ` ${failed} XATO` : ''}`);
  process.exit(failed ? 1 : 0);
})();
