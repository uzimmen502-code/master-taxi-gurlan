/**
 * storage.rules — админ каталог расмлари ва кино (админ аудити R-7,
 * 2026-10-08). Аввал `bread/extra/oil/food/platform_images` ва
 * `entertainment/` га ҲАР КИМ (кирмаган ҳам) ёза оларди. Энди фақат панел
 * роли (`users/{телефон}.role` — Firestore cross-service `firestore.get`).
 *
 * Storage + Firestore emulator БИРГА керак (cross-service). Repo
 * `firebase.json`да storage emulator йўқ — алоҳида config (порт > 15000):
 *   { "firestore": {"rules": "<repo>/firestore.rules"},
 *     "storage": {"rules": "<repo>/storage.rules"},
 *     "emulators": {"firestore": {"port": 18180}, "storage": {"port": 19199},
 *                   "ui": {"enabled": false}} }
 *   firebase emulators:exec --config <cfg> --only firestore,storage \
 *     --project demo-storage-catalog "node functions/test/storage_catalog_rules.test.js"
 */
'use strict';
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

const ROOT = path.join(__dirname, '..', '..');
const [FS_HOST, FS_PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18180').split(':');
const [ST_HOST, ST_PORT] = (process.env.FIREBASE_STORAGE_EMULATOR_HOST || '127.0.0.1:19199').split(':');

const ADMIN = '998901112233';
const FINANCE = '998901112244';
const LEGACY_ADMIN = '998901112255'; // users ҳужжати 9 хонали id'да
const USER = '998905556677';

const results = [];
async function check(name, fn) {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
}

async function main() {
  const env = await initializeTestEnvironment({
    // Cross-service `firestore.get` Storage emulator'и ишга туширилган
    // ЛОЙИҲАдан ўқийди — `emulators:exec --project` билан бир хил бўлсин.
    projectId: process.env.GCLOUD_PROJECT || 'demo-storage-catalog',
    firestore: {
      rules: fs.readFileSync(path.join(ROOT, 'firestore.rules'), 'utf8'),
      host: FS_HOST, port: Number(FS_PORT),
    },
    storage: {
      rules: fs.readFileSync(path.join(ROOT, 'storage.rules'), 'utf8'),
      host: ST_HOST, port: Number(ST_PORT),
    },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection('users').doc(ADMIN).set({ role: 'admin' });
    await db.collection('users').doc(FINANCE).set({ role: 'finance' });
    await db.collection('users').doc(LEGACY_ADMIN.slice(3)).set({ role: 'dispatcher' });
    await db.collection('users').doc(USER).set({ role: 'user' });
    await ctx.storage().ref('bread_images/seed.png').put(new Uint8Array([1, 2, 3]), { contentType: 'image/png' });
  });

  const as = (p) => env.authenticatedContext(`uid_${p}`, { phone_number: `+${p}` }).storage();
  const anon = () => env.authenticatedContext('anon_uid', {}).storage();
  const unauth = () => env.unauthenticatedContext().storage();
  const png = new Uint8Array(1024);
  const put = (st, p, data = png, contentType = 'image/png') => st.ref(p).put(data, { contentType });

  for (const folder of ['bread_images', 'extra_images', 'oil_images', 'food_images', 'platform_images']) {
    await check(`${folder}: admin rasm yuklaydi`, () => assertSucceeds(put(as(ADMIN), `${folder}/a.png`)));
  }
  await check('bread_images: finance ham yuklaydi (narx/katalog roli)', () =>
    assertSucceeds(put(as(FINANCE), 'bread_images/f.png')));
  await check('bread_images: eski 9 xonali users hujjatidagi dispatcher', () =>
    assertSucceeds(put(as(LEGACY_ADMIN), 'bread_images/l.png')));
  await check('bread_images: oddiy foydalanuvchi — rad', () =>
    assertFails(put(as(USER), 'bread_images/u.png')));
  await check('bread_images: kirmagan — rad', () =>
    assertFails(put(unauth(), 'bread_images/x.png')));
  await check('bread_images: anonim sessiya (telefonsiz) — rad', () =>
    assertFails(put(anon(), 'bread_images/x.png')));
  await check('bread_images: admin ham rasm bo\'lmagan fayl yuklay olmaydi', () =>
    assertFails(put(as(ADMIN), 'bread_images/x.html', png, 'text/html')));
  await check('bread_images: 20MB dan katta — rad', () =>
    assertFails(put(as(ADMIN), 'bread_images/big.png', new Uint8Array(20 * 1024 * 1024 + 1))));
  await check('bread_images: o\'qish — hammaga (ilova katalogi)', () =>
    assertSucceeds(unauth().ref('bread_images/seed.png').getDownloadURL()));
  await check('bread_images: foydalanuvchi o\'chira olmaydi', () =>
    assertFails(as(USER).ref('bread_images/seed.png').delete()));
  await check('bread_images: admin o\'chiradi', () =>
    assertSucceeds(as(ADMIN).ref('bread_images/seed.png').delete()));

  const mp4 = new Uint8Array(2048);
  await check('entertainment: admin .mp4 yuklaydi', () =>
    assertSucceeds(put(as(ADMIN), 'entertainment/film1.mp4', mp4, 'video/mp4')));
  await check('entertainment: oddiy foydalanuvchi — rad', () =>
    assertFails(put(as(USER), 'entertainment/film2.mp4', mp4, 'video/mp4')));
  await check('entertainment: .mp4 bo\'lmagan nom — rad', () =>
    assertFails(put(as(ADMIN), 'entertainment/film.exe', mp4, 'video/mp4')));
  // Эслатма (emulator, 2026-10-08): мавжуд файл устидан ёзиш `create`
  // сифатида баҳоланди — қоидадаги `update: if false`га қарамай АДМИН
  // ўша номли кинони алмаштира олди. Фақат панел роли учун — хавфсизлик
  // тешиги эмас; асосийси оддий фойдаланувчи ёза олмайди.
  await check('entertainment: oddiy foydalanuvchi mavjud kinoni almashtira olmaydi', () =>
    assertFails(put(as(USER), 'entertainment/film1.mp4', mp4, 'video/mp4')));
  await check('entertainment: kino o\'chirilmaydi (admin ham)', () =>
    assertFails(as(ADMIN).ref('entertainment/film1.mp4').delete()));

  await env.cleanup();
  const failed = results.filter((x) => !x).length;
  console.log(`\n${results.length - failed}/${results.length} storage catalog rules checks passed.`);
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error('FATAL', e); process.exit(1); });
