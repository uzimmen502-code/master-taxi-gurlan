/**
 * storage.rules — `restaurant_images/{rid}/…`: faqat restoran A'ZOSI
 * (`restaurants/{rid}/members/{phone}`, cross-service `firestore.exists`),
 * ≤ 8MB, faqat rasm; o'qish hammaga. Namuna: storage_catalog_rules.test.js.
 *
 * Storage + Firestore emulator BIRGA (alohida config, portlar > 15000):
 *   firebase emulators:exec --config <cfg> --only firestore,storage \
 *     --project demo-storage-restaurant "node functions/test/storage_restaurant_rules.test.js"
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

const ROOT = path.join(__dirname, '..', '..');
const [FS_HOST, FS_PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18180').split(':');
const [ST_HOST, ST_PORT] = (process.env.FIREBASE_STORAGE_EMULATOR_HOST || '127.0.0.1:19199').split(':');

const OWNER = '998911000001';
const STAFF = '998911000002';
const STRANGER = '998914000001';
const ADMIN = '998901110000';
const R1 = 'rest_r1';
const R2 = 'rest_r2';

const results = [];
async function check(name, fn) {
  try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
    results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
  }
}

async function main() {
  const env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT || 'demo-storage-restaurant',
    firestore: { rules: fs.readFileSync(path.join(ROOT, 'firestore.rules'), 'utf8'), host: FS_HOST, port: Number(FS_PORT) },
    storage: { rules: fs.readFileSync(path.join(ROOT, 'storage.rules'), 'utf8'), host: ST_HOST, port: Number(ST_PORT) },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection('users').doc(ADMIN).set({ role: 'admin' });
    await db.collection('restaurants').doc(R1).set({ name: 'R1', status: 'approved', ownerUid: OWNER });
    await db.collection('restaurants').doc(R1).collection('members').doc(OWNER).set({ role: 'owner' });
    await db.collection('restaurants').doc(R1).collection('members').doc(STAFF).set({ role: 'staff' });
    await db.collection('restaurants').doc(R2).set({ name: 'R2', status: 'approved', ownerUid: STRANGER });
    await db.collection('restaurants').doc(R2).collection('members').doc(STRANGER).set({ role: 'owner' });
    await ctx.storage().ref(`restaurant_images/${R1}/seed.jpg`).put(new Uint8Array([1, 2, 3]), { contentType: 'image/jpeg' });
  });

  const as = (p) => env.authenticatedContext(`uid_${p}`, { phone_number: `+${p}` }).storage();
  const unauth = () => env.unauthenticatedContext().storage();
  const jpg = new Uint8Array(1024);
  const put = (st, p, data = jpg, contentType = 'image/jpeg') => st.ref(p).put(data, { contentType });

  await check('a\'zo (owner/staff) o\'z restoraniga rasm yuklaydi', async () => {
    await assertSucceeds(put(as(OWNER), `restaurant_images/${R1}/logo.jpg`));
    await assertSucceeds(put(as(STAFF), `restaurant_images/${R1}/item1.jpg`));
  });
  await check('begona, boshqa restoran egasi, admin (a\'zo emas), loginsiz — yuklay olmaydi', async () => {
    await assertFails(put(as(STRANGER), `restaurant_images/${R1}/x.jpg`));
    await assertFails(put(as(STRANGER), `restaurant_images/${R1}/y.jpg`), 'R2 egasi R1 ga');
    await assertFails(put(as(ADMIN), `restaurant_images/${R1}/z.jpg`), 'admin a\'zo emas');
    await assertFails(put(unauth(), `restaurant_images/${R1}/w.jpg`));
  });
  await check('rasm emas / 8MB dan katta — rad', async () => {
    await assertFails(put(as(OWNER), `restaurant_images/${R1}/doc.pdf`, jpg, 'application/pdf'));
    await assertFails(put(as(OWNER), `restaurant_images/${R1}/big.jpg`, new Uint8Array(8 * 1024 * 1024 + 1)));
  });
  await check('o\'qish — hammaga (menyu loginsiz ko\'riladi)', async () => {
    await assertSucceeds(unauth().ref(`restaurant_images/${R1}/seed.jpg`).getDownloadURL());
    await assertSucceeds(as(STRANGER).ref(`restaurant_images/${R1}/seed.jpg`).getDownloadURL());
  });
  await check('o\'chirish — faqat a\'zo', async () => {
    await assertFails(as(STRANGER).ref(`restaurant_images/${R1}/seed.jpg`).delete());
    await assertSucceeds(as(OWNER).ref(`restaurant_images/${R1}/seed.jpg`).delete());
  });

  await env.cleanup();
  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
