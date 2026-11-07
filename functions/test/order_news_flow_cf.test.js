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
 *   N7–N9 AVA дўкони: «курьерни кутмоқда» / «курьерга топширилди» + кузатиш (мижоз ва сотувчи), нон ўзгармаган
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

  // ── N7 / N8 (эга 2026-11-07): AVA дўкони — «курьерни кутмоқда», «курьерга топширилди» + кузатиш ──
  const ADMIN = '998901000030';
  const DISP = '998901000031';
  const ADMIN_TOKEN = 'tok_admin_1234567890';
  const DISP_TOKEN = 'tok_disp_1234567890';
  const pushOf = (token) => sent.filter((m) => m.token === token);
  async function resetStaff() {
    await reset();
    await db.collection('users').doc(ADMIN).set({ role: 'admin', fcmToken: ADMIN_TOKEN, appLang: 'uz_Latn' });
    await db.collection('users').doc(DISP).set({ role: 'dispatcher', fcmToken: DISP_TOKEN });
  }
  const plat = { ...base, type: 'platform', total: 55000 };

  await resetStaff();
  await check('N7 platform ready → mijoz «курьерни кутмоқда» (3 til), sotuvchi (admin+dispetcher) — bir marta', async () => {
    await updateOrder('p1', { ...plat, status: 'accepted' }, { status: 'ready' }, 'evt-p1');
    await updateOrder('p1', { ...plat, status: 'accepted' }, { status: 'ready' }, 'evt-p1'); // takror
    const [n] = await orderNews('p1');
    assert.strictEqual(n.title, '⏳ Буюртмангиз курьерни кутмоқда');
    assert.strictEqual(n.trackOrderId, undefined);
    assert.strictEqual(pushesTo(TOKEN), 1);
    assert.strictEqual(pushOf(TOKEN)[0].data.screen, 'news');
    const a = pushOf(ADMIN_TOKEN);
    assert.strictEqual(a.length, 1, `admin push: ${a.length}`);
    assert.strictEqual(a[0].notification.title, '⏳ Buyurtma kuryerni kutmoqda', 'admin tili uz_Latn');
    assert.ok(a[0].notification.body.includes('№P1 ·'), a[0].notification.body);
    assert.strictEqual(pushOf(DISP_TOKEN).length, 1);
  });

  await resetStaff();
  await check('N8 platform in_delivery → «курьерга топширилди» + kuzatish havolasi (mijoz, admin); dispetcher — havolasiz; ru', async () => {
    await db.collection('users').doc(CUSTOMER).set({ role: 'user', fcmToken: TOKEN, appLang: 'ru' });
    await updateOrder('p2', { ...plat, status: 'ready' },
      { status: 'in_delivery', fulfillmentStatus: 'courier_picked', courierId: '998901000099' }, 'evt-p2');
    const [n] = await orderNews('p2');
    assert.strictEqual(n.title, '🚚 Ваш заказ передан курьеру');
    assert.strictEqual(n.body, 'Перейдите по ссылке, чтобы отследить курьера.');
    assert.strictEqual(n.trackOrderId, 'p2');
    const c = pushOf(TOKEN)[0];
    assert.deepStrictEqual({ screen: c.data.screen, orderId: c.data.orderId }, { screen: 'courier_tracking', orderId: 'p2' });
    const a = pushOf(ADMIN_TOKEN)[0];
    assert.strictEqual(a.data.screen, 'courier_tracking');
    assert.strictEqual(a.data.orderId, 'p2');
    const d = pushOf(DISP_TOKEN)[0];
    assert.notStrictEqual(d.data.screen, 'courier_tracking', 'dispetcher order_courier_live ni o\'qiy olmaydi');
    assert.ok(d.notification.body.includes('Курьер йўлда'), d.notification.body);
  });

  await resetStaff();
  await check('N9 non buyurtmasi o\'zgarmagan: ready — «Буюртмангиз тайёр!», sotuvchiga push yo\'q', async () => {
    await updateOrder('b1', { ...base, status: 'accepted' }, { status: 'ready' }, 'evt-b1');
    const [n] = await orderNews('b1');
    assert.strictEqual(n.title, '🟠 Буюртмангиз тайёр!');
    assert.strictEqual(pushOf(ADMIN_TOKEN).length, 0);
    assert.strictEqual(pushOf(DISP_TOKEN).length, 0);
  });

  // ── N10 (эга 2026-11-07): «тайёр» → ҳудуддаги ОНЛАЙН курьерларга овозли/вибрацияли push ──
  const NEAR = '998933000101'; // ~1 км
  const FAR = '998933000102'; // ~30 км — ҳудуддан ташқари
  const STALE = '998933000103'; // presence эски (онлайн эмас)
  const NEAR_TOKEN = 'tok_near_1234567890';
  const FAR_TOKEN = 'tok_far_1234567890';
  const STALE_TOKEN = 'tok_stale_1234567890';
  const ORDER_LOC = { lat: 41.8406, lng: 60.3917 };
  async function seedOnlineCourier(phone, token, lat, lng, ageSec = 5) {
    const acc = `acc_${phone}`;
    await db.collection('users').doc(phone).set({ role: 'user', accountId: acc, fcmToken: token, appLang: 'uz_Cyrl' });
    await db.collection('provider_capabilities').doc(acc).set({
      identity: { accountId: acc, primaryUid: phone }, courier: { active: true }, status: { courier: 'approved' },
    });
    await db.collection('provider_presence').doc(phone).set({
      isOnline: true, module: 'courier', lat, lng, updatedAt: new Date(Date.now() - ageSec * 1000),
    });
  }
  async function resetCouriers() {
    await resetStaff();
    await seedOnlineCourier(NEAR, NEAR_TOKEN, 41.8496, 60.3917);
    await seedOnlineCourier(FAR, FAR_TOKEN, 42.11, 60.39);
    await seedOnlineCourier(STALE, STALE_TOKEN, 41.8410, 60.3917, 600);
  }

  await resetCouriers();
  await check('N10 ready → faqat hududdagi ONLAYN kuryerga ovozli push (kanal courier_new_order), bir marta; uzoq/eski — yo\'q', async () => {
    const before = { ...plat, ...ORDER_LOC, status: 'accepted' };
    await updateOrder('k1', before, { status: 'ready' }, 'evt-k1');
    await updateOrder('k1', before, { status: 'ready' }, 'evt-k1'); // takror
    const near = pushOf(NEAR_TOKEN);
    assert.strictEqual(near.length, 1, `near: ${near.length}`);
    assert.strictEqual(near[0].data.type, 'courier_new_order');
    assert.strictEqual(near[0].data.orderId, 'k1');
    assert.strictEqual(near[0].android.notification.channelId, 'courier_new_order');
    assert.strictEqual(near[0].android.notification.sound, 'incoming_ring');
    // Intl uz-UZ гуруҳлагичи — узилмас бўшлиқ (U+00A0); `\s` уни ҳам қамрайди.
    assert.ok(/^AVA дўкони · 55\s000 сўм/.test(near[0].notification.body), near[0].notification.body);
    assert.ok(/1\.0 км/.test(near[0].notification.body), near[0].notification.body);
    assert.strictEqual(pushOf(FAR_TOKEN).length, 0, 'hududdan tashqari');
    assert.strictEqual(pushOf(STALE_TOKEN).length, 0, 'onlayn emas');
  });

  await resetCouriers();
  await check('N11 kuryerga push yo\'q: olib ketish (pickup), restoran, in_delivery; non ham — bor', async () => {
    await updateOrder('k2', { ...plat, ...ORDER_LOC, status: 'accepted', fulfillmentMode: 'pickup' }, { status: 'ready' }, 'evt-k2');
    await updateOrder('k3', { ...plat, ...ORDER_LOC, status: 'ready' }, { status: 'in_delivery' }, 'evt-k3');
    assert.strictEqual(pushOf(NEAR_TOKEN).length, 0, `pickup/in_delivery: ${pushOf(NEAR_TOKEN).length}`);
    await updateOrder('k4', { ...base, ...ORDER_LOC, status: 'accepted' }, { status: 'ready' }, 'evt-k4');
    const near = pushOf(NEAR_TOKEN);
    assert.strictEqual(near.length, 1);
    assert.ok(near[0].notification.body.startsWith('Нон ·'), near[0].notification.body);
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
