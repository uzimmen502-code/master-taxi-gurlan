/**
 * «Бозорлар» STAGE 11 (эга 2026-11-16) — ўз дўкони АНИҚ олиб кетиш нуқтаси оммавий эмас:
 *   `tv_shops/{phone}/private/pickup` { lat, lng, address, updatedAt } — фақат эгаси (шакл текширилади);
 *   `tv_shops/{phone}` оммавий `areaLat`/`areaLng` (тахминий) + `showExactLocation` — шакл; эски
 *   `pickupLat/pickupLng/pickupAddress` ни эга фақат ўчира олади (қўша/ўзгартира олмайди).
 *
 *   firebase emulators:exec --only firestore --project demo-tv-shops-pickup \
 *     "node test/tv_shops_pickup_rules.test.js"
 *   (бошқа қоида матнини синаш: RULES_FILE=<йўл>)
 */
'use strict';
const path = require('path');
const fs = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { serverTimestamp, deleteField, Timestamp } = require('firebase/firestore');

const RULES_PATH = process.env.RULES_FILE || path.join(__dirname, '..', '..', 'firestore.rules');
const [HOST, PORT] = (process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:18080').split(':');

const ADMIN = '998901110000';
const SELLER = '998911000001';
const OTHER = '998911000002';
const PRIV = `tv_shops/${SELLER}/private/pickup`;

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'demo-tv-shops-pickup',
    firestore: { rules: fs.readFileSync(RULES_PATH, 'utf8'), host: HOST, port: Number(PORT) },
  });
  const results = [];
  async function check(name, fn) {
    try { await fn(); results.push(true); console.log(`PASS - ${name}`); } catch (e) {
      results.push(false); console.log(`FAIL - ${name} :: ${e.message}`);
    }
  }
  const as = (phone) => testEnv.authenticatedContext(`uid_${phone}`, { phone_number: `+${phone}` }).firestore();
  const anon = () => testEnv.unauthenticatedContext().firestore();
  const seed = (fn) => testEnv.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));
  const good = (extra = {}) => ({ lat: 41.8406, lng: 60.3917, address: 'Gurlan bozor 7', updatedAt: serverTimestamp(), ...extra });

  await testEnv.clearFirestore();
  await seed(async (db) => {
    await db.doc(`users/${ADMIN}`).set({ role: 'admin' });
    await db.doc(`users/${SELLER}`).set({ role: 'user' });
    await db.doc(`users/${OTHER}`).set({ role: 'user' });
  });

  await check('P1 эга private/pickup яратади, ўқийди, янгилайди, ўчиради', async () => {
    await assertSucceeds(as(SELLER).doc(PRIV).set(good()));
    await assertSucceeds(as(SELLER).doc(PRIV).get());
    await assertSucceeds(as(SELLER).doc(PRIV).set(good({ address: 'Yangi joy' })));
    await assertSucceeds(as(SELLER).doc(PRIV).delete());
    await assertSucceeds(as(SELLER).doc(PRIV).set(good()));
  });

  await check('P2 бегона / аноним / админ (клиент) private/pickup ни ўқий ҳам, ёза ҳам олмайди', async () => {
    for (const db of [as(OTHER), anon(), as(ADMIN)]) {
      await assertFails(db.doc(PRIV).get());
      await assertFails(db.doc(PRIV).set(good()));
      await assertFails(db.doc(PRIV).delete());
    }
    await assertFails(as(OTHER).collection(`tv_shops/${SELLER}/private`).get());
  });

  await check('P3 шакл: lat/lng сон ва чегарада, address ≤200 сатр, updatedAt == request.time, ортиқча майдон йўқ', async () => {
    const db = as(SELLER);
    await assertFails(db.doc(PRIV).set(good({ lat: '41.8' })));
    await assertFails(db.doc(PRIV).set(good({ lat: 91 })));
    await assertFails(db.doc(PRIV).set(good({ lng: -181 })));
    await assertFails(db.doc(PRIV).set(good({ address: 'x'.repeat(201) })));
    await assertSucceeds(db.doc(PRIV).set(good({ address: 'x'.repeat(200) })));
    await assertFails(db.doc(PRIV).set(good({ address: 5 })));
    await assertFails(db.doc(PRIV).set(good({ updatedAt: Timestamp.fromMillis(Date.now() - 60000) })));
    await assertFails(db.doc(PRIV).set(good({ phone: SELLER })));
    const { address, ...noAddr } = good();
    await assertFails(db.doc(PRIV).set(noAddr));
    await assertFails(db.doc(`tv_shops/${SELLER}/private/other`).set(good()));
  });

  await check('A1 оммавий tv_shops: эга areaLat/areaLng + showExactLocation ёзади; ҳамма ўқийди', async () => {
    await assertSucceeds(as(SELLER).doc(`tv_shops/${SELLER}`).set({
      name: 'Texnika', ownerPhone: SELLER, createdAt: serverTimestamp(), areaLat: 41.84, areaLng: 60.39, showExactLocation: false,
    }));
    await assertSucceeds(as(SELLER).doc(`tv_shops/${SELLER}`).update({ areaLat: 41.8406, areaLng: 60.3917, showExactLocation: true }));
    await assertSucceeds(anon().doc(`tv_shops/${SELLER}`).get());
    await assertSucceeds(as(SELLER).doc(`tv_shops/${SELLER}`).update({ name: 'Faqat nom' }));
  });

  await check('A2 area шакли: сатр / чегарадан ташқари / ёлғиз areaLat / showExactLocation сатр → рад', async () => {
    const ref = as(SELLER).doc(`tv_shops/${SELLER}`);
    await assertFails(ref.update({ areaLat: '41.84' }));
    await assertFails(ref.update({ areaLat: 95 }));
    await assertFails(ref.update({ areaLng: 200 }));
    await assertFails(ref.update({ showExactLocation: 'yes' }));
    await assertFails(as(OTHER).doc(`tv_shops/${OTHER}`).set({ name: 'B', ownerPhone: OTHER, areaLat: 41.8 }));
  });

  await check('L1 эски оммавий pickup*: яратишда ва қўшишда рад; мавжудини эга ЎЧИРАДИ, ўзгартира олмайди', async () => {
    await assertFails(as(OTHER).doc(`tv_shops/${OTHER}`).set({ name: 'B', ownerPhone: OTHER, pickupLat: 41.8, pickupLng: 60.3 }));
    await assertFails(as(SELLER).doc(`tv_shops/${SELLER}`).update({ pickupLat: 41.8, pickupLng: 60.3, pickupAddress: 'x' }));
    await seed((db) => db.doc(`tv_shops/${SELLER}`).update({ pickupLat: 41.8, pickupLng: 60.3, pickupAddress: 'Eski' }));
    await assertSucceeds(as(SELLER).doc(`tv_shops/${SELLER}`).update({ name: 'Nom' })); // ўзгармаган — ок
    await assertFails(as(SELLER).doc(`tv_shops/${SELLER}`).update({ pickupLat: 41.9 }));
    await assertSucceeds(as(SELLER).doc(`tv_shops/${SELLER}`).update({
      pickupLat: deleteField(), pickupLng: deleteField(), pickupAddress: deleteField(), areaLat: 41.84, areaLng: 60.39,
    }));
  });

  await check('R1 мавжуд қоидалар: бегона tv_shops ёза олмайди; блок майдонлари эгага ёпиқ; админ ёзади', async () => {
    await assertFails(as(OTHER).doc(`tv_shops/${SELLER}`).update({ name: 'X' }));
    await assertFails(as(SELLER).doc(`tv_shops/${SELLER}`).update({ status: 'active' }));
    await assertSucceeds(as(ADMIN).doc(`tv_shops/${SELLER}`).update({ status: 'blocked' }));
  });

  await testEnv.cleanup();
  const passed = results.filter(Boolean).length;
  console.log(`\n${passed}/${results.length} passed`);
  process.exit(passed === results.length ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
