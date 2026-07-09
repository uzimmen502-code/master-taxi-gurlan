/**
 * Bir martalik: cheap_product e'lonlarini moderatsiya siyosatiga moslashtirish.
 * Default: --dry (faqat hisobot). --apply bilan pending ga o'tkazish (faqat owner
 * tomonidan yaratilgan, admin tasdiqlanmagan eski active).
 *
 * NODE_OPTIONS="--use-system-ca" node functions/tools/migrate_cheap_product_pending.js [--apply]
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

async function main() {
  const snap = await db.collection('ads')
    .where('type', '==', 'cheap_product')
    .where('status', '==', 'active')
    .limit(500)
    .get();
  console.log(`Found ${snap.size} active cheap_product ads`);
  let migrated = 0;
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    if (d.publishedAt) continue;
    console.log(`  pending candidate: ${doc.id} ${d.title || ''}`);
    if (APPLY) {
      await doc.ref.update({
        status: 'pending',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      migrated++;
    }
  }
  console.log(APPLY ? `Migrated ${migrated} to pending` : 'Dry run — use --apply');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
