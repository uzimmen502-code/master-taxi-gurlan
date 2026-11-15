/**
 * «Бозорлар» 2a — `market_moderation.js` тоза ёрдамчилари (эмуляторсиз).
 *   node test/market_moderation_pure.test.js
 */
'use strict';
const assert = require('assert');
const m = require('../market_moderation');
const { needsExpiry, parseArgs } = require('../tools/migrate_market_expiry');

const results = [];
const check = (name, fn) => {
  try { fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
const ts = (ms) => ({ toMillis: () => ms });
const fv = { ts: () => 'TS', del: () => 'DEL', at: (ms) => ({ at: ms }) };
const NOW = Date.UTC(2026, 10, 15, 12, 0, 0);
const DAY = 24 * 60 * 60 * 1000;

check('P1 contentChanged: ҳар бир контент майдони (+ ўчириш) — true', () => {
  const base = { title: 'a', photoUrls: ['x'], photoUrl: 'x', description: 'd', price: 1, priceUnit: 'kg', market: 'farm', category: 'c', attrs: { a: 1 }, imported: false };
  for (const k of m.CONTENT_FIELDS) {
    const after = { ...base, [k]: k === 'attrs' ? { a: 2 } : k === 'photoUrls' ? ['y'] : k === 'imported' ? true : k === 'price' ? 2 : 'z' };
    assert.strictEqual(m.contentChanged(base, after), true, k);
    const del = { ...base }; delete del[k];
    assert.strictEqual(m.contentChanged(base, del), true, `${k} delete`);
  }
});
check('P2 contentChanged: контент эмас (clipIds, viewCount, kind, status, boostUntil) ва attrs калит тартиби — false', () => {
  const b = { title: 'a', attrs: { x: 1, y: 2 }, clipIds: [], viewCount: 1, kind: 'product', status: 'active' };
  const a = { title: 'a', attrs: { y: 2, x: 1 }, clipIds: ['c'], viewCount: 9, kind: 'service', status: 'deleted', boostUntil: ts(1) };
  assert.strictEqual(m.contentChanged(b, a), false);
  assert.strictEqual(m.contentChanged({}, { title: undefined }), false);
});
check('P3 nextStatusOnCreate: active/pending/статуссиз → pending; deleted/blocked/submittedAt → null', () => {
  assert.strictEqual(m.nextStatusOnCreate({ status: 'active' }), 'pending');
  assert.strictEqual(m.nextStatusOnCreate({ status: 'pending' }), 'pending');
  assert.strictEqual(m.nextStatusOnCreate({}), 'pending');
  assert.strictEqual(m.nextStatusOnCreate({ status: 'deleted' }), null);
  assert.strictEqual(m.nextStatusOnCreate({ status: 'blocked' }), null);
  assert.strictEqual(m.nextStatusOnCreate({ status: 'active', submittedAt: ts(1) }), null);
});
check('P4 expiryDate: аниқ 30 кун (чегара)', () => {
  assert.strictEqual(m.expiryDate(NOW).getTime() - NOW, 30 * DAY);
  assert.strictEqual(m.EXPIRY_DAYS, 30);
});
check('P5 planShopItemWrite: create / edit / activate / no-op', () => {
  assert.deepStrictEqual(m.planShopItemWrite(null, { ownerPhone: '998901112233', status: 'active' }, NOW), { kind: 'create_pending' });
  assert.strictEqual(m.planShopItemWrite(null, { socialPostedAt: ts(1) }, NOW), null, 'ownerPhone сиз — тегилмайди');
  const b = { status: 'active', title: 'a', moderatedAt: ts(5) };
  assert.deepStrictEqual(m.planShopItemWrite(b, { ...b, title: 'b' }, NOW), { kind: 'edit_pending', fromStatus: 'active' });
  assert.deepStrictEqual(m.planShopItemWrite({ ...b, status: 'expired' }, { ...b, status: 'expired', price: 3 }, NOW), { kind: 'edit_pending', fromStatus: 'expired' });
  assert.strictEqual(m.planShopItemWrite({ ...b, status: 'rejected' }, { ...b, status: 'rejected', title: 'b' }, NOW), null, 'rejected — эга қарорида йўқ');
  assert.strictEqual(m.planShopItemWrite({ ...b, status: 'pending' }, { ...b, status: 'pending', title: 'b' }, NOW), null);
  assert.strictEqual(m.planShopItemWrite(b, { ...b, title: 'b', moderatedAt: ts(6) }, NOW), null, 'админ (moderatedAt ўзгарди)');
  assert.strictEqual(m.planShopItemWrite(b, { ...b, status: 'deleted', title: 'b' }, NOW), null, 'ўчириш');
  assert.strictEqual(m.planShopItemWrite(b, { ...b, clipIds: ['x'] }, NOW), null);
  assert.deepStrictEqual(m.planShopItemWrite({ status: 'pending' }, { status: 'active' }, NOW), { kind: 'activate_stamp' });
  assert.deepStrictEqual(m.planShopItemWrite({ status: 'pending' }, { status: 'active', expiresAt: ts(NOW - 1) }, NOW), { kind: 'activate_stamp' });
  assert.strictEqual(m.planShopItemWrite({ status: 'pending' }, { status: 'active', expiresAt: ts(NOW + DAY) }, NOW), null);
  assert.strictEqual(m.planShopItemWrite({ status: 'active' }, { status: 'pending', submittedAt: ts(1) }, NOW), null, 'ўз ёзуви');
});
check('P6 normalizeReason: 1..300, trim; бўш/301/сатр эмас → null', () => {
  assert.strictEqual(m.normalizeReason('  ok '), 'ok');
  assert.strictEqual(m.normalizeReason('x'.repeat(300)).length, 300);
  assert.strictEqual(m.normalizeReason('x'.repeat(301)), null);
  assert.strictEqual(m.normalizeReason('   '), null);
  assert.strictEqual(m.normalizeReason(5), null);
});
check('P7 buildModerationPatch approve: tv/realty/ads expiresAt +30; wholesale йўқ; realty пуллик tierUntil узунроқ — у', () => {
  const args = { cur: {}, actor: 'A', reason: null, nowMs: NOW, fv };
  const tv = m.buildModerationPatch('tv_shop_items', 'approve', args);
  assert.strictEqual(tv.status, 'active'); assert.strictEqual(tv.expiresAt.at, NOW + 30 * DAY); assert.strictEqual(tv.rejectReason, 'DEL');
  const w = m.buildModerationPatch('wholesale_products', 'approve', args);
  assert.strictEqual(w.status, 'active'); assert.strictEqual(w.expiresAt, undefined);
  const ads = m.buildModerationPatch('ads', 'approve', args);
  assert.strictEqual(ads.expiresAt.at, NOW + 30 * DAY); assert.strictEqual(ads.adminRejected, false);
  const r = m.buildModerationPatch('realty_listings', 'approve', args);
  assert.strictEqual(r.expiresAt.at, NOW + 30 * DAY);
  const rp = m.buildModerationPatch('realty_listings', 'approve', { ...args, cur: { tier: 'promo', tierUntil: ts(NOW + 40 * DAY) } });
  assert.strictEqual(rp.expiresAt.at, NOW + 40 * DAY);
});
check('P8 buildModerationPatch reject: мавжуд луғат (rejected / inactive / blocked / inactive+adminRejected)', () => {
  const args = { cur: {}, actor: 'A', reason: 'Сабаб', nowMs: NOW, fv };
  assert.strictEqual(m.buildModerationPatch('tv_shop_items', 'reject', args).status, 'rejected');
  assert.strictEqual(m.buildModerationPatch('wholesale_products', 'reject', args).status, 'inactive');
  assert.strictEqual(m.buildModerationPatch('wholesale_products', 'reject', args).adminNote, 'Сабаб');
  assert.strictEqual(m.buildModerationPatch('realty_listings', 'reject', args).status, 'blocked');
  const a = m.buildModerationPatch('ads', 'reject', args);
  assert.strictEqual(a.status, 'inactive'); assert.strictEqual(a.adminRejected, true); assert.strictEqual(a.rejectReason, 'Сабаб');
});
check('P9 planExpiry: active → expired + expiresAt олинади (эски `expiresAtPrev`да); бошқалар — фақат олинади', () => {
  const e = m.planExpiry('tv_shop_items', { status: 'active', expiresAt: ts(1) }, fv);
  assert.strictEqual(e.notify, true); assert.strictEqual(e.patch.status, 'expired'); assert.strictEqual(e.patch.expiresAt, 'DEL');
  assert.strictEqual(e.patch.expiresAtPrev.toMillis(), 1);
  const p = m.planExpiry('realty_listings', { status: 'pending', expiresAt: ts(1) }, fv);
  assert.strictEqual(p.notify, false); assert.strictEqual(p.patch.status, undefined); assert.strictEqual(p.patch.expiresAt, 'DEL');
  assert.strictEqual(m.planExpiry('realty_listings', { status: 'active', expiresAt: ts(1) }, fv).patch.updatedAt, 'TS');
});
check('P10 needsExpiryWarning: (now, now+24h] ичида, active, шу муддат учун огоҳлантирилмаган', () => {
  assert.strictEqual(m.needsExpiryWarning({ status: 'active', expiresAt: ts(NOW + DAY) }, NOW), true, 'чегара 24h');
  assert.strictEqual(m.needsExpiryWarning({ status: 'active', expiresAt: ts(NOW + DAY + 1) }, NOW), false);
  assert.strictEqual(m.needsExpiryWarning({ status: 'active', expiresAt: ts(NOW) }, NOW), false, 'тугаган — sweep иши');
  assert.strictEqual(m.needsExpiryWarning({ status: 'pending', expiresAt: ts(NOW + 5) }, NOW), false);
  assert.strictEqual(m.needsExpiryWarning({ status: 'active', expiresAt: ts(NOW + 5), expiryWarnedFor: ts(NOW + 5) }, NOW), false);
  assert.strictEqual(m.needsExpiryWarning({ status: 'active', expiresAt: ts(NOW + 5), expiryWarnedFor: ts(NOW - DAY) }, NOW), true, 'янги давр');
});
check('P11 renderMessage: уч тил, номаълум тил → uz_Cyrl; ўринбосарлар', () => {
  for (const key of Object.keys(m.MESSAGES)) for (const l of ['uz_Cyrl', 'uz_Latn', 'ru']) assert.ok(m.MESSAGES[key][l].title && m.MESSAGES[key][l].body, `${key}.${l}`);
  assert.strictEqual(m.renderMessage('listing_rejected', 'xx', { title: 'T', reason: 'R' }).body, '«T»: R');
  assert.ok(m.renderMessage('listing_approved', 'ru', { title: 'T' }).title.includes('одобрено'));
});
check('P12 samePhone: 9/12 рақам; бўш/қисқа — false', () => {
  assert.strictEqual(m.samePhone('901112233', '998901112233'), true);
  assert.strictEqual(m.samePhone('+998 90 111 22 33', '998901112233'), true);
  assert.strictEqual(m.samePhone('', ''), false);
  assert.strictEqual(m.samePhone('998901112233', '998901112234'), false);
});
check('P13 wholesale муддатсиз; EXPIRING = tv/realty/ads (эга қарори 2)', () => {
  assert.deepStrictEqual([...m.EXPIRING].sort(), ['ads', 'realty_listings', 'tv_shop_items']);
  assert.ok(m.COLLECTIONS.includes('wholesale_products') && !m.EXPIRING.includes('wholesale_products'));
});
check('P14 migrate needsExpiry: active + expiresAt йўқ; ads фақат cheap_product; parseArgs', () => {
  const tv = { collection: 'tv_shop_items', type: null };
  const ads = { collection: 'ads', type: 'cheap_product' };
  assert.strictEqual(needsExpiry(tv, { status: 'active' }), true);
  assert.strictEqual(needsExpiry(tv, { status: 'active', expiresAt: ts(1) }), false);
  assert.strictEqual(needsExpiry(tv, { status: 'pending' }), false);
  assert.strictEqual(needsExpiry(ads, { status: 'active', type: 'job' }), false);
  assert.strictEqual(needsExpiry(ads, { status: 'active', type: 'cheap_product' }), true);
  assert.deepStrictEqual(parseArgs(['--project', 'p', '--apply']), { apply: true, project: 'p', rollback: undefined });
  assert.strictEqual(parseArgs(['--project']).project, '');
});

const failed = results.filter((x) => !x).length;
console.log(`\n${results.length - failed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
