/**
 * Кечаги (ёки берilgan кун) cheap_product эълонларини platform_products га ўтказиш.
 *
 * Default: dry-run. --apply билан ёзади + асл ads ни inactive қилади.
 *
 * NODE_OPTIONS="--use-system-ca" node functions/tools/migrate_market_ads_to_platform.js [--apply] [--day=2026-07-26]
 */
const admin = require('firebase-admin');
const path = require('path');

if (!admin.apps.length) {
  const sa = path.join(__dirname, '..', 'service-account.json');
  admin.initializeApp({ credential: admin.credential.cert(require(sa)) });
}
const db = admin.firestore();
db.settings({ preferRest: true });

const APPLY = process.argv.includes('--apply');
const dayArg = process.argv.find((a) => a.startsWith('--day='));
// Default: «кеча» Asia/Tashkent (+05)
function defaultYesterdayTashkent() {
  const now = new Date();
  // approximate: local machine may be UTC+5 already; use explicit offset day string
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Tashkent',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  const todayStr = fmt.format(now); // YYYY-MM-DD
  const [y, m, d] = todayStr.split('-').map(Number);
  const utcNoon = Date.UTC(y, m - 1, d, 12, 0, 0);
  const yest = new Date(utcNoon - 24 * 60 * 60 * 1000);
  return fmt.format(yest);
}

const DAY = dayArg ? dayArg.slice('--day='.length) : defaultYesterdayTashkent();

function dayWindowTashkent(dayStr) {
  const start = new Date(`${dayStr}T00:00:00+05:00`);
  const end = new Date(`${dayStr}T00:00:00+05:00`);
  end.setDate(end.getDate() + 1);
  return { start, end };
}

async function main() {
  const { start, end } = dayWindowTashkent(DAY);
  console.log(`Day ${DAY} (Tashkent) → ${start.toISOString()} .. ${end.toISOString()}`);
  console.log(APPLY ? 'MODE: APPLY' : 'MODE: dry-run (pass --apply)');

  let snap;
  try {
    snap = await db
      .collection('ads')
      .where('type', '==', 'cheap_product')
      .where('createdAt', '>=', admin.firestore.Timestamp.fromDate(start))
      .where('createdAt', '<', admin.firestore.Timestamp.fromDate(end))
      .get();
  } catch (e) {
    console.error('Range query failed, client filter fallback:', e.message);
    // type + status indexes exist; fetch active+pending+inactive pools
    const pools = await Promise.all([
      db.collection('ads').where('type', '==', 'cheap_product').where('status', '==', 'active').limit(500).get(),
      db.collection('ads').where('type', '==', 'cheap_product').where('status', '==', 'pending').limit(500).get(),
      db.collection('ads').where('type', '==', 'cheap_product').where('status', '==', 'inactive').limit(500).get(),
    ]);
    const docs = [];
    const seen = new Set();
    for (const pool of pools) {
      for (const d of pool.docs) {
        if (seen.has(d.id)) continue;
        const ca = d.data().createdAt;
        if (!ca || !ca.toDate) continue;
        const t = ca.toDate();
        if (t >= start && t < end) {
          seen.add(d.id);
          docs.push(d);
        }
      }
    }
    docs.sort((a, b) => {
      const ta = a.data().createdAt.toDate().getTime();
      const tb = b.data().createdAt.toDate().getTime();
      return tb - ta;
    });
    snap = { docs, size: docs.length };
  }

  console.log(`Found ${snap.size} cheap_product ads`);
  if (snap.size === 0) {
    const pools = await Promise.all([
      db.collection('ads').where('type', '==', 'cheap_product').where('status', '==', 'active').limit(40).get(),
      db.collection('ads').where('type', '==', 'cheap_product').where('status', '==', 'pending').limit(40).get(),
    ]);
    const recent = [...pools[0].docs, ...pools[1].docs]
      .sort((a, b) => {
        const ta = a.data().createdAt?.toDate?.()?.getTime?.() || 0;
        const tb = b.data().createdAt?.toDate?.()?.getTime?.() || 0;
        return tb - ta;
      })
      .slice(0, 40);
    console.log('No ads that day. Recent cheap_product:');
    for (const d of recent) {
      const x = d.data();
      const ca = x.createdAt && x.createdAt.toDate ? x.createdAt.toDate().toISOString() : null;
      console.log(`  ${d.id} [${x.status}] ${x.title} ${x.price} ${ca}`);
    }
    return;
  }

  let created = 0;
  let skipped = 0;
  let inactivated = 0;

  for (const doc of snap.docs) {
    const x = doc.data() || {};
    const title = String(x.title || '').trim();
    const price = Number(x.price) || 0;
    const imageUrl = Array.isArray(x.imageUrls) && x.imageUrls[0]
      ? String(x.imageUrls[0]).trim()
      : '';
    const description = String(x.description || '').trim();
    const ca = x.createdAt && x.createdAt.toDate ? x.createdAt.toDate().toISOString() : '';

    console.log(`- ${doc.id} [${x.status}] ${title} | ${price} | ${ca}`);

    if (!title || price <= 0) {
      console.log('  skip: empty title/price');
      skipped++;
      continue;
    }

    // Idempotent: already migrated?
    const existing = await db
      .collection('platform_products')
      .where('sourceAdId', '==', doc.id)
      .limit(1)
      .get();
    if (!existing.empty) {
      console.log(`  skip: already platform ${existing.docs[0].id}`);
      skipped++;
      continue;
    }

    if (!APPLY) continue;

    const ref = db.collection('platform_products').doc();
    await ref.set({
      name: title,
      description,
      price,
      imageUrl,
      unit: 'дона',
      minQty: 1,
      step: 1,
      totalStock: 0,
      soldToday: 0,
      active: true,
      featuredOnHome: true,
      showInMarket: true,
      sortOrder: created,
      sourceAdId: doc.id,
      migratedFrom: 'cheap_product',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    created++;
    console.log(`  → platform_products/${ref.id}`);

    if (x.status !== 'inactive') {
      await doc.ref.update({
        status: 'inactive',
        adminNote: String(x.adminNote || '')
          ? `${x.adminNote} | migrated→platform ${ref.id}`
          : `migrated→platform ${ref.id}`,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      inactivated++;
    }
  }

  console.log(
    APPLY
      ? `Done: created=${created} inactivated=${inactivated} skipped=${skipped}`
      : `Dry-run done: would migrate ${snap.size - skipped} (skipped preview ${skipped}). Re-run with --apply`,
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
