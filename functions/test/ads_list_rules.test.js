/**
 * `ads` o'qish: `allow get` / `allow list` bo'linishi (2026-10-08) — Firestore rules.
 *
 * Teshik: eski `allow read` ichidagi `resource.data.get('type', '')` ro'yxat
 * so'rovida so'rov cheklamagan maydon uchun standart '' qaytaradi →
 * `!isCheapProductAdData` true → FILTRSIZ so'rov (hatto kirmagan) bozorning
 * pending / rad etilgan e'lonlarini egasining telefoni bilan qaytarardi.
 * Bitta hujjat `get` esa to'g'ri rad etilardi.
 *
 * Bu test:
 *   A) ilovadagi HAR BIR `ads` so'rovi (joriy kod + eski Play versiyalari)
 *      o'z chaqiruvchisi bilan o'tishini;
 *   B) teshik yopilganini (filtrsiz, bozor turi bo'yicha, begona egasi
 *      bo'yicha; bo'sh `phone_number` claim bilan '' == '' tuzog'i);
 *   C) bitta hujjat `get` semantikasi o'zgarmaganini tekshiradi.
 *
 * Ishlatish (Windows: port > 15000 bo'lsin):
 *   firebase emulators:exec --config <scratch>/firebase.json --only firestore \
 *     --project demo-ads-list "node functions/test/ads_list_rules.test.js"
 * Boshqa rules faylini tekshirish (masalan jonli manba + shu tuzatish):
 *   $env:ADS_RULES_PATH = '<fayl>'
 */
'use strict';
const path = require('path');
const fs = require('fs');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  collection,
  query,
  where,
  getCountFromServer,
} = require('firebase/firestore');

const RULES_PATH = process.env.ADS_RULES_PATH
  || path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const ADMIN = '998901112233';
const DISPATCHER = '998901112244';
const SUPER = '998901112255';
const FINANCE = '998901112266';
const OWNER = '998905556677';
const OWNER9 = '905556677';
const STRANGER = '998904445566';
const DISTRICT = 'gurlan';

// ── lib/core/utils/formatters.dart nusxasi (so'rov qiymatlari ilovadagidek) ──
const digits = (v) => String(v).replace(/[^\d]/g, '');
function canonicalPhoneId(raw) {
  const d = digits(raw);
  if (d.length === 9) return `998${d}`;
  return d;
}
function phoneAliases(raw) {
  const t = String(raw).trim();
  const d = digits(raw);
  const out = new Set();
  if (t) out.add(t);
  const compact = t.replace(/ /g, '');
  if (compact) out.add(compact);
  if (d) {
    out.add(d);
    out.add(`+${d}`);
    if (d.length >= 12 && d.startsWith('998')) out.add(d.substring(3));
    if (d.length === 9) out.add(`998${d}`);
  }
  return [...out].slice(0, 10);
}
/** `JobsRepository._aliases` / `AdsRepository._ownerAliases` bilan bir xil. */
function appAliases(prefsPhone) {
  const uid = canonicalPhoneId(prefsPhone);
  return [...new Set(phoneAliases(uid).map(digits).filter((p) => p.length >= 9))]
    .slice(0, 10);
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-ads-list',
    firestore: {
      rules: fs.readFileSync(RULES_PATH, 'utf8'),
      host: HOST,
      port: Number(PORT),
    },
  });
  console.log(`rules: ${RULES_PATH}`);

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

  const now = new Date();
  const future = new Date(Date.now() + 7 * 24 * 3600 * 1000);
  const market = (extra) => ({
    type: 'cheap_product', ownerId: OWNER, phone: OWNER, title: 'Velosiped',
    titleLower: 'velosiped', searchTokens: ['velosiped'], description: 'Yaxshi holatda',
    price: 50000, sellerName: 'Aziz', imageUrls: ['https://x/1.jpg'],
    districtId: DISTRICT, views: 0, createdAt: now, updatedAt: now, expiresAt: future,
    ...extra,
  });
  const job = (extra) => ({
    type: 'work', text: 'Ishchi kerak', title: 'Ish', authorName: 'Aziz',
    authorPhone: OWNER, address: 'Gurlan', districtId: DISTRICT, isUrgent: false,
    status: 'active', createdAt: now, editedAt: null, expiresAt: future,
    ...extra,
  });

  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [phone, role] of [
      [ADMIN, 'admin'], [DISPATCHER, 'dispatcher'], [SUPER, 'superadmin'],
      [FINANCE, 'finance'], [OWNER, 'user'], [STRANGER, 'user'],
    ]) {
      await db.collection('users').doc(phone).set({role, phone: '+' + phone});
    }
    const ads = db.collection('ads');
    await ads.doc('mk_active').set(market({status: 'active', publishedAt: now}));
    await ads.doc('mk_pending').set(market({status: 'pending'}));
    await ads.doc('mk_rejected').set(market({status: 'inactive', adminRejected: true}));
    await ads.doc('mk_legacy9').set(market({status: 'pending', ownerId: OWNER9, phone: OWNER9}));
    await ads.doc('mk_stranger').set(market({status: 'pending', ownerId: STRANGER, phone: STRANGER}));
    const noOwner = market({status: 'pending'});
    delete noOwner.ownerId;
    await ads.doc('mk_noowner').set(noOwner);
    await ads.doc('job_active').set(job({}));
    await ads.doc('job_pending').set(job({type: 'service', status: 'pending'}));
    await ads.doc('job_legacy9').set(job({type: 'ad', status: 'pending', authorPhone: OWNER9}));
    const noType = job({});
    delete noType.type;
    await ads.doc('job_notype').set(noType);
    await ads.doc('job_stranger').set(job({authorPhone: STRANGER}));
  });

  const unauth = () => testEnv.unauthenticatedContext().firestore();
  /** Anonim (guest) sessiya: auth bor, telefon claim yo'q. */
  const anon = () => testEnv.authenticatedContext('anon_uid_1', {}).firestore();
  /** Bo'sh `phone_number` claim — `phoneDocIdsMatch('', '')` tuzog'i. */
  const emptyPhone = () => testEnv
    .authenticatedContext('empty_phone_uid', {phone_number: ''}).firestore();
  const as = (phone) => testEnv
    .authenticatedContext(`uid_${phone}`, {phone_number: '+' + phone}).firestore();
  const ads = (db) => db.collection('ads');
  const count = (db, ...wheres) =>
    getCountFromServer(query(collection(db, 'ads'), ...wheres));
  const ok = (name, fn) => check(name, () => assertSucceeds(fn()));
  const no = (name, fn) => check(name, () => assertFails(fn()));
  const ids = (snap) => snap.docs.map((d) => d.id).sort().join(',');
  async function okIds(name, fn, expected) {
    await check(name, async () => {
      const snap = await assertSucceeds(fn());
      const got = ids(snap);
      if (got !== expected) throw new Error(`kutilgan [${expected}], keldi [${got}]`);
    });
  }

  const ownerAliases = appAliases(OWNER);
  await check('ilova aliaslari: 998905556677 → [998905556677, 905556677]', async () => {
    if (ownerAliases.join(',') !== `${OWNER},${OWNER9}`) {
      throw new Error(ownerAliases.join(','));
    }
  });
  const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const feedReaders = [['kirmagan', unauth], ['anonim', anon], ['telefonli', () => as(STRANGER)]];
  const admins = [['admin', ADMIN], ['dispatcher', DISPATCHER], ['superadmin', SUPER]];

  // ════ A. Ilova so'rovlari — o'tishi SHART ═════════════════════════════
  // ── JobsRepository (lib/repositories/jobs_repository.dart) ──────────
  for (const [who, db] of feedReaders) {
    await ok(`J1 watchActiveByType :38 (${who})`,
        () => ads(db()).where('type', '==', 'work').where('status', '==', 'active')
            .limit(300).get());
    await ok(`J2 watchForHome scoped :72 (${who})`,
        () => ads(db()).where('type', '==', 'service').where('status', '==', 'active')
            .where('districtId', '==', DISTRICT).orderBy('createdAt', 'desc').limit(5).get());
    await ok(`J3 watchAllActive :100 (${who})`,
        () => ads(db()).where('type', 'in', ['work', 'service', 'ad'])
            .where('status', '==', 'active').limit(500).get());
    await ok(`J3-eski (<=1.0.5, 'sell' bilan) (${who})`,
        () => ads(db()).where('type', 'in', ['work', 'service', 'ad', 'sell'])
            .where('status', '==', 'active').limit(500).get());
  }
  await okIds('J4 watchAdsByAuthor :119 (egasi, whereIn aliaslar) — o\'z e\'lonlari',
      () => ads(as(OWNER)).where('authorPhone', 'in', ownerAliases).limit(50).get(),
      'job_active,job_legacy9,job_notype,job_pending');
  for (const form of [OWNER, OWNER9, '+' + OWNER]) {
    await ok(`J4-eski (<=1.0.5) authorPhone == '${form}' (egasi)`,
        () => ads(as(OWNER)).where('authorPhone', '==', form).get());
  }
  for (const alias of ownerAliases) {
    await ok(`J7 dailyCountByAuthor :192 authorPhone == '${alias}' && createdAt > bugun (egasi)`,
        () => ads(as(OWNER)).where('authorPhone', '==', alias)
            .where('createdAt', '>', startOfDay).get());
  }
  for (const [who, phone] of admins) {
    await ok(`J5 watchAllForAdmin :142 filtrsiz orderBy createdAt (${who})`,
        () => ads(as(phone)).orderBy('createdAt', 'desc').limit(500).get());
  }
  await ok('J6 getAdById :172 (admin, shikoyatlar oynasi)',
      () => ads(as(ADMIN)).doc('job_pending').get());
  await ok('J8 updateAdByOwner/deleteAdByOwner oldidan get :246 (egasi)',
      () => ads(as(OWNER)).doc('job_pending').get());

  // ── AdsRepository (lib/features/ads/repositories/ads_repository.dart) ──
  const cheap = (db) => ads(db).where('type', '==', 'cheap_product');
  for (const [who, db] of feedReaders) {
    await ok(`M1 getActiveAds :126 (${who})`,
        () => cheap(db()).where('status', '==', 'active')
            .orderBy('publishedAt', 'desc').limit(200).get());
    await ok(`M2 watchForHome scoped :153 (${who})`,
        () => cheap(db()).where('status', '==', 'active').where('districtId', '==', DISTRICT)
            .orderBy('publishedAt', 'desc').limit(5).get());
    await ok(`M3 _searchPool byToken :197 (${who})`,
        () => cheap(db()).where('status', '==', 'active')
            .where('searchTokens', 'array-contains', 'velosiped').limit(100).get());
    await ok(`M6 getSimilarAds :297 (${who})`,
        () => cheap(db()).where('status', '==', 'active')
            .orderBy('publishedAt', 'desc').limit(40).get());
    await ok(`M-eski (<=1.0.5) titleLower oralig'i (${who})`,
        () => cheap(db()).where('status', '==', 'active')
            .where('titleLower', '>=', 'vel').where('titleLower', '<=', 'vel')
            .orderBy('titleLower').get());
    await ok(`M-eski (<=1.0.31) product_feed/featured (${who})`,
        () => cheap(db()).where('status', '==', 'active')
            .orderBy('createdAt', 'desc').limit(6).get());
  }
  await okIds('M4 getMyAds :254 status=pending (egasi) — o\'z pending e\'lonlari',
      () => cheap(as(OWNER)).where('ownerId', 'in', ownerAliases)
          .where('status', '==', 'pending').get(),
      'mk_legacy9,mk_pending');
  for (const st of ['active', 'inactive']) {
    await ok(`M4 getMyAds :254 status=${st} (egasi)`,
        () => cheap(as(OWNER)).where('ownerId', 'in', ownerAliases)
            .where('status', '==', st).get());
  }
  await ok('M4 getMyAds :254 statussiz (egasi)',
      () => cheap(as(OWNER)).where('ownerId', 'in', ownerAliases).get());
  await ok('M4-eski (<=1.0.5) ownerId == uid orderBy publishedAt (egasi)',
      () => cheap(as(OWNER)).where('ownerId', '==', OWNER).orderBy('publishedAt', 'desc').get());
  for (const alias of ownerAliases) {
    await check(`M5 canCreateAd :278 count() ownerId == '${alias}' (egasi)`,
        () => assertSucceeds(count(as(OWNER), where('type', '==', 'cheap_product'),
            where('ownerId', '==', alias), where('status', '==', 'active'))));
  }
  await ok('M5-eski (<=1.0.5) canCreateAd get() (egasi)',
      () => cheap(as(OWNER)).where('ownerId', '==', OWNER).where('status', '==', 'active').get());
  await ok('M7 watchAllForAdmin :370 (admin)',
      () => cheap(as(ADMIN)).limit(500).get());
  await ok('M8 updateAd/deleteAd oldidan get :77/:91 (egasi, pending)',
      () => ads(as(OWNER)).doc('mk_pending').get());

  // ── Admin web (lib/features/admin_web/screens/admin_shell.dart) ─────
  for (const [who, phone] of admins) {
    await ok(`A1 «ИШ ЭЪЛОН» nishoni :923 status == pending, turisiz (${who})`,
        () => ads(as(phone)).where('status', '==', 'pending').get());
    await ok(`A2 «Онлайн бозор» nishoni :937 (${who})`,
        () => cheap(as(phone)).where('status', '==', 'pending').limit(200).get());
    await check(`A3 analytics :237 ads.count() (${who})`,
        () => assertSucceeds(count(as(phone))));
    await check(`A4 analytics :238 createdAt oralig'i count() (${who})`,
        () => assertSucceeds(count(as(phone), where('createdAt', '>=', startOfDay),
            where('createdAt', '<', future))));
  }
  await ok('A-eski (<=1.0.5) admin nishoni filtrsiz (admin)',
      () => ads(as(ADMIN)).get());
  // 2026-10-18 (audit A5): Ish top e'lonlari ham status bo'yicha cheklanadi.
  // Avval `type != cheap_product` shoxi ularni HAR statusda (pending / blocked /
  // completed — `authorPhone` bilan) kirmagan klientga ham ochib qo'ygan edi.
  await no('L1 begona: type == service, statussiz (pending Ish top e\'loni oqib chiqardi)',
      () => ads(as(STRANGER)).where('type', '==', 'service').get());
  await okIds('L1b begona: type == work && status == active (lenta)',
      () => ads(as(STRANGER)).where('type', '==', 'work').where('status', '==', 'active').get(),
      'job_active,job_stranger');
  await okIds('L2 egasi: type == service, authorPhone bo\'yicha — o\'z pending e\'loni',
      () => ads(as(OWNER)).where('authorPhone', 'in', ownerAliases)
          .where('type', '==', 'service').get(),
      'job_pending');

  // ════ B. Teshik — rad etilishi SHART ══════════════════════════════════
  await no('B1 kirmagan: filtrsiz ads.get()', () => ads(unauth()).get());
  await no('B2 anonim: filtrsiz ads.get()', () => ads(anon()).get());
  await no('B3 telefonli begona: filtrsiz ads.get()', () => ads(as(STRANGER)).get());
  await no('B4 begona: filtrsiz orderBy createdAt (admin so\'rovi)',
      () => ads(as(STRANGER)).orderBy('createdAt', 'desc').limit(500).get());
  await check('B5 begona: filtrsiz count()',
      () => assertFails(count(as(STRANGER))));
  await check('B6 kirmagan: filtrsiz count()',
      () => assertFails(count(unauth())));
  await no('B7 begona: type == cheap_product (statussiz)',
      () => cheap(as(STRANGER)).get());
  await no('B8 kirmagan: type == cheap_product && status == pending',
      () => cheap(unauth()).where('status', '==', 'pending').get());
  await no('B9 begona: status in [active, pending]',
      () => ads(as(STRANGER)).where('status', 'in', ['active', 'pending']).get());
  await no('B10 begona: status == pending (admin nishoni)',
      () => ads(as(STRANGER)).where('status', '==', 'pending').get());
  await no('B11 begona: status == inactive (rad etilganlar)',
      () => ads(as(STRANGER)).where('status', '==', 'inactive').get());
  await no('B12 begona: boshqaning ownerId bo\'yicha',
      () => cheap(as(STRANGER)).where('ownerId', '==', OWNER).get());
  await no('B13 begona: boshqaning aliaslari bo\'yicha (whereIn)',
      () => cheap(as(STRANGER)).where('ownerId', 'in', ownerAliases).get());
  await no('B14 begona: o\'zi + boshqa ownerId aralash (whereIn)',
      () => cheap(as(STRANGER)).where('ownerId', 'in', [STRANGER, OWNER]).get());
  await no('B15 anonim: ownerId == \'\' (turisiz)',
      () => ads(anon()).where('ownerId', '==', '').get());
  await no('B16 anonim: authorPhone == \'\' (turisiz)',
      () => ads(anon()).where('authorPhone', '==', '').get());
  await no('B17 begona: type oralig\'i (cheap_product ichida)',
      () => ads(as(STRANGER)).where('type', '>=', 'a').get());
  await no('B18 begona: type != work (cheap_product kiradi)',
      () => ads(as(STRANGER)).where('type', '!=', 'work').get());
  await no('B19 begona: type in [work, cheap_product]',
      () => ads(as(STRANGER)).where('type', 'in', ['work', 'cheap_product']).get());
  await no('B20 finance roli (isAdmin emas): filtrsiz',
      () => ads(as(FINANCE)).get());
  await no('B21 begona: boshqaning authorPhone bo\'yicha (turisiz)',
      () => ads(as(STRANGER)).where('authorPhone', '==', OWNER).get());
  await no('B22 bo\'sh phone claim: type == cheap_product && ownerId == \'\' (\'\' == \'\')',
      () => cheap(emptyPhone()).where('ownerId', '==', '').get());
  await no('B23 bo\'sh phone claim: egasiz pending e\'lon get (\'\' == \'\')',
      () => ads(emptyPhone()).doc('mk_noowner').get());
  // Audit A5 — Ish top e'lonlari.
  await no('B24 kirmagan: type == work, statussiz',
      () => ads(unauth()).where('type', '==', 'work').get());
  await no('B25 begona: type in [work, service, ad], statussiz',
      () => ads(as(STRANGER)).where('type', 'in', ['work', 'service', 'ad']).get());
  await no('B26 begona: type == ad && status == pending',
      () => ads(as(STRANGER)).where('type', '==', 'ad').where('status', '==', 'pending').get());
  await no('B27 begona: Ish top, boshqaning authorPhone bo\'yicha',
      () => ads(as(STRANGER)).where('authorPhone', '==', OWNER)
          .where('type', '==', 'service').get());
  await no('B28 bo\'sh phone claim: authorPhone == \'\' (Ish top, \'\' == \'\')',
      () => ads(emptyPhone()).where('authorPhone', '==', '')
          .where('type', '==', 'work').get());

  // ════ C. Bitta hujjat `get` — semantika o'zgarmagan ═══════════════════
  await ok('C1 kirmagan: faol bozor e\'loni', () => ads(unauth()).doc('mk_active').get());
  await no('C2 kirmagan: pending bozor e\'loni', () => ads(unauth()).doc('mk_pending').get());
  await no('C3 anonim: pending bozor e\'loni', () => ads(anon()).doc('mk_pending').get());
  await no('C4 begona: pending bozor e\'loni', () => ads(as(STRANGER)).doc('mk_pending').get());
  await no('C5 begona: admin rad etgan e\'lon', () => ads(as(STRANGER)).doc('mk_rejected').get());
  await ok('C6 egasi: o\'z pending e\'loni', () => ads(as(OWNER)).doc('mk_pending').get());
  await ok('C7 egasi: 9 xonali ownerId bilan eski e\'loni',
      () => ads(as(OWNER)).doc('mk_legacy9').get());
  await ok('C8 egasi: admin rad etgan o\'z e\'loni', () => ads(as(OWNER)).doc('mk_rejected').get());
  await ok('C9 admin: boshqaning pending e\'loni', () => ads(as(ADMIN)).doc('mk_stranger').get());
  await no('C10 kirmagan: pending Ish top e\'loni (audit A5: avval ochiq edi)',
      () => ads(unauth()).doc('job_pending').get());
  await ok('C10b kirmagan: faol Ish top e\'loni', () => ads(unauth()).doc('job_active').get());
  await no('C10c begona: pending Ish top e\'loni', () => ads(as(STRANGER)).doc('job_pending').get());
  await no('C10d anonim: pending Ish top e\'loni', () => ads(anon()).doc('job_pending').get());
  await no('C10e begona: 9 xonali authorPhone bilan eski pending e\'lon',
      () => ads(as(STRANGER)).doc('job_legacy9').get());
  await ok('C10f egasi: o\'z pending Ish top e\'loni', () => ads(as(OWNER)).doc('job_pending').get());
  await ok('C10g egasi: 9 xonali authorPhone bilan eski pending e\'loni',
      () => ads(as(OWNER)).doc('job_legacy9').get());
  await no('C10h bo\'sh phone claim: pending Ish top e\'loni (\'\' == \'\' tuzog\'i)',
      () => ads(emptyPhone()).doc('job_pending').get());
  await ok('C10i admin: begonaning pending Ish top e\'loni',
      () => ads(as(ADMIN)).doc('job_pending').get());
  await ok('C11 begona: turisiz, lekin FAOL eski Ish top e\'loni (status == active)',
      () => ads(as(STRANGER)).doc('job_notype').get());

  await testEnv.cleanup();
  const failed = results.filter((r) => !r.pass);
  console.log(`\n${results.length - failed.length} passed, ${failed.length} failed`);
  process.exit(failed.length ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
