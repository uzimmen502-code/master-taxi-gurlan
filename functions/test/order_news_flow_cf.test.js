/**
 * «Буюртма хабар» оқими (админ сайдбар бўлими, 2026-10-11 аудити) — HAQIQIY
 * `functions/index.js` триггерлари `.run()` орқали, Firestore Emulator.
 * FCM — stub (тармоққа чиқмайди), юборилган push'лар саналади.
 *
 *   firebase emulators:exec --only firestore --project demo-order-news \
 *     "node functions/test/order_news_flow_cf.test.js"
 *
 * Qulflanadi:
 *   N1 onOrderCreate: триггер қайта етказилса ҳам битта «Буюртма юборилди»
 *      хабари ва мижозга битта push
 *   N2 onOrderUpdate: битта event (eventId) — битта хабар/push; кейинги
 *      статус — алоҳида хабар
 *   N3 onOrderUpdate: push йиқилса ҳам функция хато бермайди, хабар бор
 *   N4 тур ёрлиғи: `platform` — «Улгуржи бозор» (аввал «Нон»)
 *   N5 notifyUserInApp → onAdminNewsCreate: push БИР марта (аввал икки)
 *   N6 админ қўлда ёзган шахсий хабар — onAdminNewsCreate push'и сақланди
 */
'use strict';
const assert = require('assert');

process.env.FIRESTORE_EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || 'demo-order-news';
process.env.FUNCTIONS_EMULATOR = 'true';
if (!/^demo-/.test(process.env.GCLOUD_PROJECT)) {
  throw new Error(`demo-* loyiha kerak, berilgan: ${process.env.GCLOUD_PROJECT}`);
}

const fns = require('../index.js');
const admin = require('firebase-admin');
const db = admin.firestore();

// FCM stub: `admin.messaging` прототипдаги getter — ўз хусусияти билан
// яширилади. `failNext` — навбатдаги send йиқилади.
const sent = [];
let failNext = false;
Object.defineProperty(admin, 'messaging', {
  configurable: true,
  value: () => ({
    send: async (m) => {
      if (failNext) { failNext = false; throw new Error('stub: token invalid'); }
      sent.push(m);
      return 'stub-id';
    },
    sendEach: async (ms) => { sent.push(...ms); return { successCount: ms.length }; },
  }),
});

const CUSTOMER = '998901000020';
const OWNER = '998901000021';
const TOKEN = 'tok_customer_1234567890';
const OWNER_TOKEN = 'tok_owner_1234567890';
const pushesTo = (token) => sent.filter((m) => m.token === token).length;

const results = [];
const check = async (name, fn) => {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
};
async function clearEmulator() {
  const res = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${
    process.env.GCLOUD_PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator clear: HTTP ${res.status}`);
}
async function reset() {
  await clearEmulator();
  sent.length = 0;
  failNext = false;
  await db.collection('users').doc(CUSTOMER).set({ role: 'user', fcmToken: TOKEN });
  await db.collection('users').doc(OWNER).set({ role: 'user', fcmToken: OWNER_TOKEN });
}
const orderNews = async (orderId) => (await db.collection('admin_news')
  .where('orderId', '==', orderId).get()).docs.map((d) => ({ id: d.id, ...d.data() }));

function changeOf(id, before, afterSnap) {
  return { before: { id, data: () => before }, after: afterSnap };
}
async function updateOrder(id, before, patch, eventId) {
  const ref = db.collection('orders').doc(id);
  await ref.set({ ...before, ...patch });
  const afterSnap = await ref.get();
  return fns.onOrderUpdate.run(changeOf(id, before, afterSnap), { eventId, params: { orderId: id } });
}

async function main() {
  const base = { userPhone: CUSTOMER, type: 'bread', status: 'new', total: 12000, items: [] };

  // ── N1 ───────────────────────────────────────────────────────────────
  await reset();
  await check('N1 onOrderCreate qayta yetkazilsa — bitta xabar, mijozga bitta push', async () => {
    const ref = db.collection('orders').doc('o1');
    await ref.set(base);
    const snap = await ref.get();
    await fns.onOrderCreate.run(snap, { eventId: 'e-create-1', params: { orderId: 'o1' } });
    await fns.onOrderCreate.run(snap, { eventId: 'e-create-1', params: { orderId: 'o1' } });
    const news = await orderNews('o1');
    assert.strictEqual(news.length, 1, `xabarlar: ${news.length}`);
    assert.strictEqual(news[0].id, 'order_placed_o1');
    assert.strictEqual(news[0].source, 'order_placed');
    assert.strictEqual(pushesTo(TOKEN), 1, `push: ${pushesTo(TOKEN)}`);
  });

  // ── N2 ───────────────────────────────────────────────────────────────
  await reset();
  await check('N2 onOrderUpdate: bitta event — bitta xabar; keyingi status — alohida', async () => {
    await updateOrder('o2', base, { status: 'accepted' }, 'evt-a');
    await updateOrder('o2', base, { status: 'accepted' }, 'evt-a'); // takror yetkazish
    let news = await orderNews('o2');
    assert.strictEqual(news.length, 1, `takrordan keyin: ${news.length}`);
    assert.strictEqual(news[0].orderStatus, 'accepted');
    assert.strictEqual(pushesTo(TOKEN), 1);
    await updateOrder('o2', { ...base, status: 'accepted' }, { status: 'ready' }, 'evt-b');
    news = await orderNews('o2');
    assert.deepStrictEqual(news.map((n) => n.orderStatus).sort(), ['accepted', 'ready']);
    assert.strictEqual(pushesTo(TOKEN), 2);
  });

  // ── N3 ───────────────────────────────────────────────────────────────
  await reset();
  await check('N3 push yiqilsa — funksiya xato bermaydi, xabar lentada', async () => {
    failNext = true;
    await updateOrder('o3', base, { status: 'rejected', rejectReason: 'Tugadi' }, 'evt-c');
    const news = await orderNews('o3');
    assert.strictEqual(news.length, 1);
    assert.strictEqual(news[0].orderStatus, 'rejected');
  });

  // ── N4 ───────────────────────────────────────────────────────────────
  await reset();
  await check('N4 platform buyurtma — «Улгуржи бозор», «Нон» emas', async () => {
    await updateOrder('o4', { ...base, type: 'platform' }, { status: 'accepted' }, 'evt-d');
    const [n] = await orderNews('o4');
    assert.ok(n.body.includes('Улгуржи бозор'), n.body);
    assert.ok(!n.body.includes('Нон'), n.body);
    const ref = db.collection('orders').doc('o5');
    await ref.set({ ...base, type: 'platform' });
    await fns.onOrderCreate.run(await ref.get(), { eventId: 'e5', params: { orderId: 'o5' } });
    const [p] = await orderNews('o5');
    assert.ok(p.body.endsWith('Улгуржи бозор'), p.body);
  });

  // ── N12 (эга 2026-11-21, 54e07faf порти): «AVA Супермаркет» (platform + subtype supermarket) ──
  await reset();
  await check('N12 supermarket: chek/status — «AVA Супермаркет»; admin push «Yangi AVA Supermarket buyurtmasi»; Ulgurji o\'zgarmagan', async () => {
    const ADMIN_TOKEN = 'tok_admin_1234567890';
    await db.collection('users').doc('998901000099').set({ role: 'admin', fcmToken: ADMIN_TOKEN });
    const sm = { ...base, type: 'platform', subtype: 'supermarket' };
    const ref = db.collection('orders').doc('s1');
    await ref.set(sm);
    await fns.onOrderCreate.run(await ref.get(), { eventId: 'e-s1', params: { orderId: 's1' } });
    const [p] = await orderNews('s1');
    assert.ok(p.body.endsWith('AVA Супермаркет') && !p.body.includes('Улгуржи'), p.body);
    assert.ok(sent.some((m) => m.token === ADMIN_TOKEN && m.notification.title === 'Yangi AVA Supermarket buyurtmasi'));
    await updateOrder('s2', sm, { status: 'accepted' }, 'evt-s2');
    const [n] = await orderNews('s2');
    assert.ok(n.body.includes('AVA Супермаркет') && !n.body.includes('Улгуржи'), n.body);
    const r3 = db.collection('orders').doc('s3');
    await r3.set({ ...base, type: 'platform' });
    await fns.onOrderCreate.run(await r3.get(), { eventId: 'e-s3', params: { orderId: 's3' } });
    assert.ok((await orderNews('s3'))[0].body.endsWith('Улгуржи бозор'));
    assert.ok(sent.some((m) => m.token === ADMIN_TOKEN && m.data.orderId === 's3' && m.notification.title === 'Yangi Ulgurji buyurtmasi'));
  });

  // ── N5 ───────────────────────────────────────────────────────────────
  await reset();
  await check('N5 notifyUserInApp → onAdminNewsCreate: push BIR marta (avval ikki)', async () => {
    const before = { status: 'active', ownerPhone: OWNER, title: 'Klip', category: 'news' };
    const ref = db.collection('tv_clips').doc('c1');
    await ref.set({ ...before, status: 'blocked', rejectReason: 'Sifat' });
    await fns.onTvClipRejected.run(changeOf('c1', before, await ref.get()), { params: { clipId: 'c1' } });
    assert.strictEqual(pushesTo(OWNER_TOKEN), 1, 'notifyUserInApp o\'zi yuboradi');
    const docs = (await db.collection('admin_news').where('targetUserId', '==', OWNER).get()).docs;
    assert.strictEqual(docs.length, 1);
    assert.strictEqual(docs[0].data().pushDirect, true);
    await fns.onAdminNewsCreate.run(docs[0], { params: { newsId: docs[0].id } });
    assert.strictEqual(pushesTo(OWNER_TOKEN), 1, `jami push: ${pushesTo(OWNER_TOKEN)}`);
  });

  // ── N6 ───────────────────────────────────────────────────────────────
  await reset();
  await check('N6 admin qo\'lda yozgan shaxsiy xabar — onAdminNewsCreate push yuboradi', async () => {
    const ref = db.collection('admin_news').doc('m1');
    await ref.set({
      title: 'Salom', body: 'Matn', category: 'info', audience: 'user',
      targetUserId: CUSTOMER, source: 'admin_compose', createdAt: new Date(),
    });
    await fns.onAdminNewsCreate.run(await ref.get(), { params: { newsId: 'm1' } });
    assert.strictEqual(pushesTo(TOKEN), 1);
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
