/**
 * admin_news O'QISH qoidasi (xavfsizlik: shaxsiy xabarlar — telefon, chek, summa — ochiq edi).
 *
 * Ilova so'rovlari qoida bilan ISBOTLANishi kerak (list'da rules faqat so'rov
 * cheklovlarini ko'radi) — shuning uchun testlar `NewsRepository` dagi aynan
 * shu so'rov shakllarini ishlatadi:
 *   umumiy:   where targetUserId == '' + orderBy createdAt desc + limit 50 (+ createdAt >)
 *   shaxsiy:  where targetUserId in [998.., +998.., 9 xonali] + orderBy createdAt desc + limit 30
 *   admin:    orderBy createdAt desc limit 300 | where category == 'order' (+ createdAt >)
 *   ESKI ilova (build < 72): FILTRSIZ orderBy createdAt limit 50 — endi rad bo'lishi KERAK.
 *
 * Ishlatish: repo ildizidan
 *   firebase emulators:exec --only firestore --project demo-news-read-rules \
 *     "node functions/test/admin_news_read_rules.test.js"
 */
'use strict';
const path = require('path');
const fs = require('fs');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const ADMIN = '998901112233';
const DISPATCHER = '998901112244';
const SUPER = '998901112255';
const OWNER = '998905556677'; // 12 xonali kanon
const STRANGER = '998904445566';
const PLAIN_ROLE = '998903332211'; // role: 'user' (admin emas)

function aliases(d12) {
  return [d12, '+' + d12, d12.slice(3)]; // NewsRepository phoneAliases(canon)
}

function news(extra = {}) {
  return {
    title: 'Xabar',
    body: 'Matn',
    category: 'info',
    audience: 'all',
    priority: 0,
    targetUserId: '',
    createdAt: new Date(),
    ...extra,
  };
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'rules-test-news-read',
    firestore: {
      rules: fs.readFileSync(RULES_PATH, 'utf8'),
      host: HOST,
      port: Number(PORT),
    },
  });

  const results = [];
  function record(name, pass, detail) {
    results.push({name, pass, detail});
    console.log(`${pass ? 'PASS' : 'FAIL'} - ${name}${detail ? ' :: ' + detail : ''}`);
  }
  async function check(name, fn) {
    try {
      await fn();
      record(name, true);
    } catch (e) {
      record(name, false, e.message);
    }
  }

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [id, role] of [[ADMIN, 'admin'], [DISPATCHER, 'dispatcher'], [SUPER, 'superadmin'],
      [OWNER, 'user'], [STRANGER, 'user'], [PLAIN_ROLE, 'user']]) {
      await db.collection('users').doc(id).set({role, phone: '+' + id});
    }
    const t = (min) => new Date(Date.now() - min * 60000);
    await db.collection('admin_news').doc('pub1').set(news({createdAt: t(5)}));
    await db.collection('admin_news').doc('pub2').set(news({createdAt: t(4), audience: 'driver'}));
    await db.collection('admin_news').doc('mine').set(news({
      audience: 'user', targetUserId: OWNER, category: 'order', source: 'order_status',
      title: 'Buyurtma chek', body: 'Manzil: Gurlan, summa 120000', createdAt: t(3)}));
    await db.collection('admin_news').doc('mineLegacy9').set(news({
      audience: 'user', targetUserId: OWNER.slice(3), createdAt: t(2)}));
    await db.collection('admin_news').doc('theirs').set(news({
      audience: 'user', targetUserId: STRANGER, category: 'order', source: 'order_status',
      title: 'Boshqa chek', body: 'Manzil: Toshkent, summa 99000', createdAt: t(1)}));
    // Eski, backfill qilinmagan hujjat: targetUserId maydoni YO'Q.
    const legacy = news({createdAt: t(6)});
    delete legacy.targetUserId;
    await db.collection('admin_news').doc('noField').set(legacy);
  });

  const as = (phone) => testEnv.authenticatedContext(`uid_${phone}`, {phone_number: '+' + phone}).firestore();
  const anon = () => testEnv.authenticatedContext('uid_anon').firestore(); // telefonsiz (guest) sessiya
  const unauth = () => testEnv.unauthenticatedContext().firestore();
  const col = (db) => db.collection('admin_news');

  // Ilovaning aynan o'sha so'rovlari.
  const broadcastQ = (db) => col(db).where('targetUserId', '==', '').orderBy('createdAt', 'desc').limit(50);
  const broadcastUnreadQ = (db) => col(db).where('targetUserId', '==', '')
      .orderBy('createdAt', 'desc').where('createdAt', '>', new Date(Date.now() - 3600000)).limit(50);
  const personalQ = (db, d12) => col(db).where('targetUserId', 'in', aliases(d12))
      .orderBy('createdAt', 'desc').limit(30);
  const oldClientQ = (db) => col(db).orderBy('createdAt', 'desc').limit(50);

  // ── Ijobiy ─────────────────────────────────────────────────────────
  await check('umumiy lenta (ilova so\'rovi): kirgan foydalanuvchi o\'qiydi, faqat umumiylar keladi', async () => {
    const snap = await assertSucceeds(broadcastQ(as(OWNER)).get());
    const ids = snap.docs.map((d) => d.id).sort();
    if (JSON.stringify(ids) !== JSON.stringify(['pub1', 'pub2'])) throw new Error('ids=' + ids);
  });
  await check('umumiy lenta + createdAt > (o\'qilmaganlar hisobi) ishlaydi', () =>
    assertSucceeds(broadcastUnreadQ(as(OWNER)).get()));
  await check('shaxsiy (ilova so\'rovi): egasi o\'z xabarlarini oladi (kanon + 9 xonali meros)', async () => {
    const snap = await assertSucceeds(personalQ(as(OWNER), OWNER).get());
    const ids = snap.docs.map((d) => d.id).sort();
    if (JSON.stringify(ids) !== JSON.stringify(['mine', 'mineLegacy9'])) throw new Error('ids=' + ids);
  });
  await check('shaxsiy + createdAt > (o\'qilmaganlar hisobi) ishlaydi', () =>
    assertSucceeds(col(as(OWNER)).where('targetUserId', 'in', aliases(OWNER))
        .orderBy('createdAt', 'desc').where('createdAt', '>', new Date(Date.now() - 3600000)).limit(30).get()));
  await check('shaxsiy bitta hujjat: egasi o\'qiydi', () =>
    assertSucceeds(col(as(OWNER)).doc('mine').get()));
  await check('shaxsiy so\'rov faqat kanon id bilan ham ishlaydi (where ==)', () =>
    assertSucceeds(col(as(OWNER)).where('targetUserId', '==', OWNER).get()));
  await check('telefonsiz (guest) sessiya umumiy lentani o\'qiydi (ilova guest bilan ishlaydi)', () =>
    assertSucceeds(broadcastQ(anon()).get()));
  await check('admin: butun kolleksiya orderBy createdAt limit 300 (admin panel «Хабарлар»)', async () => {
    const snap = await assertSucceeds(col(as(ADMIN)).orderBy('createdAt', 'desc').limit(300).get());
    if (snap.size !== 6) throw new Error('size=' + snap.size);
  });
  await check('admin: category == order (admin panel «Буюртма хабар») + createdAt >', async () => {
    await assertSucceeds(col(as(ADMIN)).where('category', '==', 'order').orderBy('createdAt', 'desc').limit(300).get());
    await assertSucceeds(col(as(ADMIN)).where('category', '==', 'order')
        .where('createdAt', '>', new Date(Date.now() - 3600000)).orderBy('createdAt', 'desc').limit(100).get());
  });
  await check('dispatcher va superadmin ham o\'qiydi (isAdmin)', async () => {
    await assertSucceeds(col(as(DISPATCHER)).orderBy('createdAt', 'desc').limit(300).get());
    await assertSucceeds(col(as(SUPER)).orderBy('createdAt', 'desc').limit(300).get());
  });
  await check('admin boshqa foydalanuvchining shaxsiy hujjatini ham ko\'ra oladi (get)', () =>
    assertSucceeds(col(as(ADMIN)).doc('theirs').get()));

  // ── Salbiy ─────────────────────────────────────────────────────────
  await check('bosqinchi: boshqaning shaxsiy hujjati (get) — rad', () =>
    assertFails(col(as(OWNER)).doc('theirs').get()));
  await check('bosqinchi: boshqaning telefoni bo\'yicha shaxsiy ro\'yxat (in) — rad', () =>
    assertFails(personalQ(as(OWNER), STRANGER).get()));
  await check('bosqinchi: boshqaning telefoni bo\'yicha where == — rad', () =>
    assertFails(col(as(OWNER)).where('targetUserId', '==', STRANGER).get()));
  await check('bosqinchi: o\'z + boshqaning alias aralash `in` — rad', () =>
    assertFails(col(as(OWNER)).where('targetUserId', 'in', [OWNER, STRANGER]).get()));
  await check('bosqinchi: `!= \'\'` (barcha shaxsiylarni terish) — rad', () =>
    assertFails(col(as(OWNER)).where('targetUserId', '!=', '').get()));
  await check('ESKI ilova so\'rovi (filtrsiz orderBy createdAt limit 50) — rad', () =>
    assertFails(oldClientQ(as(OWNER)).get()));
  await check('filtrsiz to\'liq kolleksiya `.get()` (oddiy foydalanuvchi) — rad', () =>
    assertFails(col(as(PLAIN_ROLE)).get()));
  await check('category == order filtri (admin emas) — rad (boshqa chek sizishi)', () =>
    assertFails(col(as(OWNER)).where('category', '==', 'order').orderBy('createdAt', 'desc').limit(50).get()));
  await check('audience filtri (admin emas) — rad (shaxsiylar audience=user)', () =>
    assertFails(col(as(OWNER)).where('audience', '==', 'user').get()));
  await check('kirmagan: umumiy ro\'yxat — rad', () => assertFails(broadcastQ(unauth()).get()));
  await check('kirmagan: shaxsiy ro\'yxat — rad', () => assertFails(personalQ(unauth(), OWNER).get()));
  await check('kirmagan: filtrsiz ro\'yxat va get — rad', async () => {
    await assertFails(oldClientQ(unauth()).get());
    await assertFails(col(unauth()).doc('pub1').get());
    await assertFails(col(unauth()).doc('mine').get());
  });
  await check('telefonsiz (guest) sessiya: shaxsiy ro\'yxat (egasining aliaslari) — rad', () =>
    assertFails(personalQ(anon(), OWNER).get()));
  await check('telefonsiz (guest) sessiya: filtrsiz ro\'yxat va shaxsiy get — rad', async () => {
    await assertFails(oldClientQ(anon()).get());
    await assertFails(col(anon()).doc('mine').get());
  });
  await check('telefon claim bo\'sh satr (anonim) — `in [\'\']` orqali umumiyni emas, shaxsiyni ochmaydi', () =>
    assertFails(col(anon()).where('targetUserId', 'in', ['', OWNER]).get()));
  await check('targetUserId maydonsiz eski hujjat: oddiy foydalanuvchi o\'qiy olmaydi (get)', () =>
    assertFails(col(as(OWNER)).doc('noField').get()));
  await check('targetUserId maydonsiz hujjat umumiy so\'rovga tushmaydi (backfill kerakligi)', async () => {
    const snap = await assertSucceeds(broadcastQ(as(OWNER)).get());
    if (snap.docs.some((d) => d.id === 'noField')) throw new Error('noField keldi');
  });
  await check('yozish qoidalari o\'zgarmagan: oddiy foydalanuvchi yarata olmaydi', () =>
    assertFails(col(as(OWNER)).add(news())));
  await check('yozish qoidalari o\'zgarmagan: admin yaratadi', () =>
    assertSucceeds(col(as(ADMIN)).add(news())));

  await testEnv.cleanup();
  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length}/${results.length} o'tdi`);
  if (failed.length) process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
