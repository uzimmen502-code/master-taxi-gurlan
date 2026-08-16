/**
 * TV роликлардаги ownerName телефон/бўш бўлса — users.name ни ёзади.
 * tv_public_profiles ни ҳам тўлдиради (лента бошқаларнинг users ҳужжатини ўқий олмайди).
 *
 * NODE_OPTIONS="--use-system-ca" node functions/tools/backfill_tv_publisher_names.js [--apply]
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

function canonicalPhoneId(raw) {
  const d = String(raw || '').replace(/\D/g, '');
  if (d.length === 9) return `998${d}`;
  if (d.length >= 12 && d.startsWith('998')) return d;
  return d;
}

function displayName(raw) {
  const s = String(raw || '').trim().replace(/\s+/g, ' ');
  if (!s || s.startsWith('@')) return '';
  const compact = s.replace(/[\s+\-()]/g, '');
  if (/^\d{7,}$/.test(compact)) return '';
  const fake = new Set([
    'фойдаланувчи',
    'foydalanuvchi',
    'пользователь',
    'user',
  ]);
  if (fake.has(s.toLowerCase())) return '';
  const first = s.split(' ')[0].toLowerCase();
  if (fake.has(first)) return '';
  return s;
}

async function main() {
  const clips = await db.collection('tv_clips').get();
  console.log(`clips ${clips.size}`);
  const userCache = new Map();
  let patchedClips = 0;
  let upsertedProfiles = 0;

  for (const doc of clips.docs) {
    const d = doc.data() || {};
    const uid = canonicalPhoneId(d.ownerPhone || '');
    const stored = displayName(d.ownerName);
    if (uid && !userCache.has(uid)) {
      const snap = await db.collection('users').doc(uid).get();
      userCache.set(uid, displayName((snap.data() || {}).name));
    }
    const fromUser = userCache.get(uid) || '';
    const next = stored || fromUser;
    if (!next) {
      console.log(`  skip ${doc.id} uid=${uid} no name`);
      continue;
    }
    if (stored !== next) {
      console.log(`  clip ${doc.id} ${JSON.stringify(d.ownerName || '')} → ${next}`);
      if (APPLY) {
        await doc.ref.update({ ownerName: next });
      }
      patchedClips++;
    }
    if (uid) {
      if (APPLY) {
        await db.collection('tv_public_profiles').doc(uid).set({
          name: next,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      upsertedProfiles++;
    }
  }

  console.log(APPLY
    ? `Patched ${patchedClips} clips, upserted ${upsertedProfiles} public profiles`
    : `Dry run — would patch ${patchedClips} clips, upsert ${upsertedProfiles} profiles. Use --apply`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
