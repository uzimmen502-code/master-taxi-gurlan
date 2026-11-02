/**
 * tv_shop_items.priceUnit — narx birligi (biznes zanjiri S2, ega 2026-11-03). Ixtiyoriy; bo'lsa — faqat ro'yxatdagi satr.
 *
 *   firebase emulators:exec --only firestore --project demo-price-unit-rules \
 *     "node functions/test/tv_shop_items_price_unit_rules.test.js"
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

const RULES_PATH = process.env.RULES_FILE
  ? path.resolve(process.env.RULES_FILE)
  : path.join(__dirname, '..', '..', 'firestore.rules');
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080';
const [HOST, PORT] = EMULATOR_HOST.split(':');

const OWNER = '998901112233';

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-price-unit-rules',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  const check = async (name, fn) => {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  };
  const db = () => testEnv.authenticatedContext('u1', { phone_number: `+${OWNER}` }).firestore();
  const item = (extra = {}) => ({
    ownerPhone: OWNER, title: 'Soch olish', description: '', price: 50000, photoUrls: [], clipIds: [],
    kind: 'service', status: 'active', viewCount: 0, ...extra,
  });

  await testEnv.clearFirestore();
  await check('U1 priceUnit yo\'q (eski shakl) — yaratiladi', () =>
    assertSucceeds(db().collection('tv_shop_items').doc('a').set(item())));
  await check('U2 ro\'yxatdagi birlik (hour, from, negotiable) — yaratiladi', async () => {
    await assertSucceeds(db().collection('tv_shop_items').doc('b').set(item({ priceUnit: 'hour' })));
    await assertSucceeds(db().collection('tv_shop_items').doc('c').set(item({ priceUnit: 'from' })));
    await assertSucceeds(db().collection('tv_shop_items').doc('d').set(item({ priceUnit: 'negotiable', price: 0 })));
  });
  await check('U3 noma\'lum birlik / son / bo\'sh emas noto\'g\'ri tur — rad', async () => {
    await assertFails(db().collection('tv_shop_items').doc('e').set(item({ priceUnit: 'week' })));
    await assertFails(db().collection('tv_shop_items').doc('f').set(item({ priceUnit: 5 })));
    await assertFails(db().collection('tv_shop_items').doc('g').set(item({ priceUnit: ['hour'] })));
  });
  await check('U4 egasi birlikni o\'zgartiradi (ro\'yxatdagi) — o\'tadi; noma\'lumga — rad', async () => {
    await assertSucceeds(db().collection('tv_shop_items').doc('a').update({ priceUnit: 'session' }));
    await assertFails(db().collection('tv_shop_items').doc('a').update({ priceUnit: 'year' }));
  });

  const failed = results.filter((r) => !r).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  await testEnv.cleanup();
  process.exit(failed ? 1 : 0);
}
main().catch((e) => { console.error(e); process.exit(2); });
