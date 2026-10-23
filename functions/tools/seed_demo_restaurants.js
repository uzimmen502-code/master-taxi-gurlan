/**
 * НАМУНА кафе-ресторан ва уй ошпазларини киритиш / олиб ташлаш (эга қарори 2026-10-23, `functions/restaurant_demo.js`).
 *
 * Хавфсизлик (28, 27, 41-банд):
 *   - DRY RUN — стандарт: нима яратилиши чиқади, ҳеч нарса ёзилмайди.
 *   - `--apply`: фақат ҳали йўқ ҳужжатларни яратади (бор бўлса тегмайди); тури бўйича ҳақиқий тасдиқланган сони
 *     аллақачон ≥ 3 бўлса, шу тур намунаси ЯРАТИЛМАЙДИ (кўрсатадиган нарса қолмаган).
 *   - `--remove`: қўлда олиб ташлаш (авто-ўчириш триггеридан мустақил); барча `isDemo==true` ҳужжатлар, audit билан.
 *   - Орқага қайтариш: `--remove` (ёки триггер ўзи).
 *
 * Ишлатиш (прода — `functions/service-account.json` керак, у git'да йўқ):
 *   node functions/tools/seed_demo_restaurants.js            # dry run
 *   node functions/tools/seed_demo_restaurants.js --apply
 *   node functions/tools/seed_demo_restaurants.js --remove --apply
 */
'use strict';

const demo = require('../restaurant_demo');

/** Асосий мантиқ (тест ишлатади): `apply=false` — фақат режа. */
async function seedDemos(db, admin, { apply = false } = {}) {
  const { real } = await demo.evaluate(db);
  // `evaluate` намуна йўқ бўлса `real: null` — ҳақиқий сонни алоҳида ҳисоблаймиз.
  const counts = real || await realCounts(db);
  const plan = [];
  for (const spec of demo.DEMO_SET) {
    const ref = db.collection(demo.RESTAURANTS).doc(spec.id);
    const exists = (await ref.get()).exists;
    let action = 'create';
    if (exists) action = 'exists';
    else if (counts[spec.kind] >= demo.REAL_THRESHOLD) action = 'skip_real_enough';
    plan.push({ id: spec.id, kind: spec.kind, name: spec.name, dishes: spec.dishes.length, action });
  }
  if (!apply) return { plan, real: counts, applied: false };

  const ts = admin.firestore.FieldValue.serverTimestamp();
  const pausedUntil = admin.firestore.Timestamp.fromDate(new Date(demo.PAUSED_UNTIL_ISO));
  const created = [];
  for (const p of plan.filter((x) => x.action === 'create')) {
    const spec = demo.DEMO_SET.find((s) => s.id === p.id);
    const docs = demo.buildDemoDocs(spec, { ts, pausedUntil });
    const ref = db.collection(demo.RESTAURANTS).doc(spec.id);
    const batch = db.batch();
    batch.create(ref, docs.restaurant); // create: бор бўлса хато — устига ёзмайди
    docs.categories.forEach((c) => batch.set(ref.collection('menu_categories').doc(c.id), c.data));
    docs.items.forEach((i) => batch.set(ref.collection('menu_items').doc(i.id), i.data));
    await batch.commit();
    created.push(spec.id);
  }
  if (created.length) {
    await db.collection('admin_audit').add({
      kind: 'demo_restaurants_seed', actor: 'script:seed_demo_restaurants', created,
      batch: demo.DEMO_BATCH, reason: 'Эга буйруғи 2026-10-23: намуна кафе/уй ошпази', at: ts,
    });
  }
  return { plan, real: counts, applied: true, created };
}

async function realCounts(db) {
  const approvedAll = (await db.collection(demo.RESTAURANTS).where('status', '==', 'approved').count().get()).data().count;
  const approvedHome = (await db.collection(demo.RESTAURANTS)
    .where('status', '==', 'approved').where('venueType', '==', 'home').count().get()).data().count;
  return { home: approvedHome, cafe: approvedAll - approvedHome };
}

/** Барча намуналарни олиб ташлаш (триггердан мустақил). */
async function removeAllDemos(db, admin, { apply = false } = {}) {
  const snap = await db.collection(demo.RESTAURANTS).where('isDemo', '==', true).get();
  const ids = snap.docs.map((d) => d.id);
  if (!apply || ids.length === 0) return { ids, applied: false };
  await db.collection('admin_audit').add({
    kind: 'demo_restaurants_cleanup', actor: 'script:seed_demo_restaurants', removed: ids, kinds: ['manual'],
    reason: 'Қўлда олиб ташлаш (--remove)', at: admin.firestore.FieldValue.serverTimestamp(),
  });
  for (const d of snap.docs) {
    await db.recursiveDelete(d.ref);
    const stale = await db.collection('restaurant_dish_index').where('restaurantId', '==', d.id).get();
    await Promise.all(stale.docs.map((x) => x.ref.delete()));
  }
  return { ids, applied: true };
}

async function main() {
  const admin = require('firebase-admin');
  const path = require('path');
  if (!admin.apps.length) {
    if (process.env.FIRESTORE_EMULATOR_HOST) {
      admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-seed' });
    } else {
      admin.initializeApp({ credential: admin.credential.cert(require(path.join(__dirname, '..', 'service-account.json'))) });
    }
  }
  const db = admin.firestore();
  const apply = process.argv.includes('--apply');
  const remove = process.argv.includes('--remove');
  console.log(`${apply ? 'APPLY' : 'DRY RUN'} ${remove ? '--remove' : 'seed'}  project=${admin.app().options.projectId || '(service account)'}`);
  const out = remove ? await removeAllDemos(db, admin, { apply }) : await seedDemos(db, admin, { apply });
  console.log(JSON.stringify(out, null, 2));
  if (!apply) console.log('DRY RUN: ҳеч нарса ёзилмади. Ёзиш учун --apply.');
}

if (require.main === module) {
  main().catch((e) => { console.error(e); process.exit(1); });
}

module.exports = { seedDemos, removeAllDemos, realCounts };
