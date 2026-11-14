/**
 * Admin «Аҳоли бозори» рўйхати — саҳифалар ва «Яна юклаш»
 * (functions/admin_market_list.js, эга 2026-10-08). Firestore — Emulator
 * (курсор ва тартиб ҳақиқий; индекс талабини emulator текширмайди — у
 * production'да REST орқали алоҳида текширилган).
 *
 *   firebase emulators:exec --only firestore --project demo-market-list \
 *     "node functions/test/admin_market_list.test.js"
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-market-list';
process.env.FUNCTIONS_EMULATOR = 'true';

// index.js ўзи `admin.initializeApp()` қилади — callable'ни охиригача
// (`.run(data, context)`) текшириш учун.
const fns = require('../index.js');
const admin = require('firebase-admin');
const functions = require('firebase-functions');
const db = admin.firestore();

const ml = require('../admin_market_list');

const ADMIN = '998901000010';
const USER = '998901000020';
const ctxOf = (p) => ({ auth: { uid: `uid_${p}`, token: { phone_number: `+${p}` } } });
const listCf = (data, who = ADMIN) => fns.adminListMarketAds.run(data, ctxOf(who));
const rejectCode = async (p) => { try { await p; return 'OK'; } catch (e) { return e.code || e.message; } };

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
const codeOf = (fn) => { try { fn(); return 'OK'; } catch (e) { return `${e.code}:${e.message}`; } };

const ts = (s, n = 0) => new admin.firestore.Timestamp(s, n);

async function wipe() {
  const s = await db.collection('ads').get();
  await Promise.all(s.docs.map((d) => d.ref.delete()));
}

/** Барча саҳифалар бўйлаб юриш — сервер қайтарган курсорни JSON орқали
 * ўтказиб (callable'дагидек), кейин parseMarketAdsCursor. */
async function walk(pageSize) {
  const ids = [];
  let after = null;
  let pages = 0;
  for (;;) {
    const { docs, nextCursor } = await ml.listMarketAdsPage(db, { admin }, { after, pageSize });
    ids.push(...docs.map((d) => d.id));
    pages++;
    if (!nextCursor) break;
    const wire = JSON.parse(JSON.stringify(nextCursor));
    after = ml.parseMarketAdsCursor(wire, { admin, functions });
    assert.ok(pages < 50, 'чексиз цикл');
  }
  return { ids, pages };
}

async function main() {
  await wipe();
  // 7 та бозор эълони: учтаси БИР ХИЛ вақтда (саҳифа чегарасига тушади),
  // иккитаси бир хил сонияда, микросекунди фарқли (Firestore вақтни
  // микросекундгача сақлайди; веб'даги DateTime эса миллисекундгача —
  // шунинг учун курсор seconds/nanos сифатида қайтарилади). Бошқа турлар
  // аралашмасин.
  const seed = [
    ['m1', ts(1000)], ['m2', ts(2000)], ['m3', ts(3000, 5000)], ['m4', ts(3000, 9000)],
    ['t_a', ts(4000)], ['t_b', ts(4000)], ['t_c', ts(4000)],
  ];
  await Promise.all(seed.map(([id, createdAt]) =>
    db.collection('ads').doc(id).set({ type: 'cheap_product', status: 'active', title: id, createdAt })));
  await db.collection('ads').doc('job1').set({ type: 'work', status: 'active', createdAt: ts(9000) });
  await db.collection('ads').doc('nots').set({ type: 'cheap_product', status: 'active', title: 'no createdAt' });

  const expected = ['t_c', 't_b', 't_a', 'm4', 'm3', 'm2', 'm1'];

  await check('C1 курсорсиз — биринчи саҳифа, энг янгиси биринчи (ID DESC билан)', async () => {
    const { docs, nextCursor } = await ml.listMarketAdsPage(db, { admin }, { pageSize: 3 });
    assert.deepStrictEqual(docs.map((d) => d.id), ['t_c', 't_b', 't_a']);
    assert.deepStrictEqual(nextCursor, { seconds: 4000, nanos: 0, id: 't_a' });
  });

  for (const size of [1, 2, 3, 4, 7]) {
    await check(`C2 pageSize ${size}: ҳамма эълон бир марта, тартибда, тирқишсиз`, async () => {
      const { ids } = await walk(size);
      assert.deepStrictEqual(ids, expected);
    });
  }

  await check('C3 охирги саҳифа тўлмаса — nextCursor йўқ', async () => {
    const { docs, nextCursor } = await ml.listMarketAdsPage(db, { admin }, { pageSize: 10 });
    assert.strictEqual(docs.length, 7);
    assert.strictEqual(nextCursor, null);
  });

  await check('C4 аниқ pageSize та — кейинги саҳифа бўш ва якуний', async () => {
    const { pages, ids } = await walk(7);
    assert.strictEqual(pages, 2);
    assert.strictEqual(ids.length, 7);
  });

  await check('C5 микросекунд сақланади (бир миллисекундли иккита эълон тушмайди)', async () => {
    const after = ml.parseMarketAdsCursor({ seconds: 3000, nanos: 9000, id: 'm4' }, { admin, functions });
    const { docs } = await ml.listMarketAdsPage(db, { admin }, { after, pageSize: 1 });
    assert.deepStrictEqual(docs.map((d) => d.id), ['m3']);
  });

  await check('C6 бошқа тур (work) ва createdAt сиз ҳужжат рўйхатга кирмайди', async () => {
    const { ids } = await walk(100);
    assert.ok(!ids.includes('job1'));
    assert.ok(!ids.includes('nots'));
  });

  await check('C7 нотўғри курсор — invalid-argument (биринчи саҳифага жимгина қайтмайди)', () => {
    const bad = [
      'abc', 5, {}, { seconds: 'x', nanos: 0, id: 'a' }, { seconds: 1.5, nanos: 0, id: 'a' },
      { seconds: 1, nanos: -1, id: 'a' }, { seconds: 1, nanos: 1e9, id: 'a' },
      { seconds: 1, nanos: 0, id: '' }, { seconds: 1, nanos: 0, id: 'a/b' },
      { seconds: 1, nanos: 0, id: 7 }, { seconds: 1e15, nanos: 0, id: 'a' },
    ];
    for (const raw of bad) {
      assert.strictEqual(codeOf(() => ml.parseMarketAdsCursor(raw, { admin, functions })),
        'invalid-argument:MARKET_ADS_BAD_CURSOR', JSON.stringify(raw));
    }
    assert.strictEqual(ml.parseMarketAdsCursor(null, { admin, functions }), null);
    assert.strictEqual(ml.parseMarketAdsCursor(undefined, { admin, functions }), null);
  });

  await check('C8 саҳифалар орасида янги эълон келса — эскилари тушмайди', async () => {
    const first = await ml.listMarketAdsPage(db, { admin }, { pageSize: 3 });
    await db.collection('ads').doc('new1').set({ type: 'cheap_product', status: 'pending', createdAt: ts(8000) });
    const after = ml.parseMarketAdsCursor(first.nextCursor, { admin, functions });
    const second = await ml.listMarketAdsPage(db, { admin }, { after, pageSize: 3 });
    assert.deepStrictEqual(second.docs.map((d) => d.id), ['m4', 'm3', 'm2']);
    await db.collection('ads').doc('new1').delete();
  });

  await check('C9 standart саҳифа ҳажми — 500', () => {
    assert.strictEqual(ml.MARKET_ADS_ADMIN_PAGE, 500);
  });

  // ── Callable охиригача (index.js) ───────────────────────────────────────
  await db.collection('users').doc(ADMIN).set({ role: 'admin' });
  await db.collection('users').doc(USER).set({ role: 'user' });

  await check('E1 эски чақирув (after йўқ) — аввалгидек ҳаммаси, nextCursor null', async () => {
    const res = await listCf({ adminPhone: ADMIN });
    assert.deepStrictEqual(res.ads.map((a) => a.id).sort(), [...expected].sort());
    assert.strictEqual(res.nextCursor, null);
  });

  await check('E2 after билан — фақат курсордан кейингилари', async () => {
    const first = await ml.listMarketAdsPage(db, { admin }, { pageSize: 3 });
    const wire = JSON.parse(JSON.stringify(first.nextCursor));
    const res = await listCf({ adminPhone: ADMIN, after: wire });
    assert.deepStrictEqual(res.ads.map((a) => a.id).sort(), ['m1', 'm2', 'm3', 'm4']);
    assert.strictEqual(res.nextCursor, null);
  });

  await check('E3 нотўғри курсор — invalid-argument', async () => {
    assert.strictEqual(
      await rejectCode(listCf({ adminPhone: ADMIN, after: { seconds: 'x', nanos: 0, id: 'a' } })),
      'invalid-argument');
  });

  await check('E4 оддий фойдаланувчи — рад этилади', async () => {
    assert.notStrictEqual(await rejectCode(listCf({ adminPhone: USER }, USER)), 'OK');
    assert.notStrictEqual(
      await rejectCode(fns.adminListMarketAds.run({ adminPhone: ADMIN }, { auth: { uid: 'anon', token: {} } })),
      'OK');
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
