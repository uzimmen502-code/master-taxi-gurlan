/**
 * `settings/restaurant_sections` — MAVJUD sozlamada bo'lim bosqichini o'zgartirish (S3/S7, D-REST-16, D-REST-33).
 *
 * `enable_restaurant_sections.js` faqat hujjat yo'q bo'lganda yaratadi; yangi bo'limlar (Ofis, Dastarxon, Mavsumiy)
 * qo'shilganda ular mavjud hujjatda `off` bo'lib turadi — shu skript ularni yoqadi. Admin callable
 * (`adminSetRestaurantSections`) bilan XUDDI SHU `mergeConfig` va yozuvlar (sozlama + `restaurant_sections_history/v{n}` +
 * `admin_audit`) Admin SDK orqali; boshqa qiymatlar saqlanadi, o'zgarish bo'lmasa versiya OSHMAYDI.
 *
 * Xavfsizlik (28, 41-qoida): DRY RUN — standart; `--apply` bilan yozadi; hujjat yo'q bo'lsa to'xtaydi.
 *
 * Ishlatish:
 *   node functions/tools/set_restaurant_sections.js --sections=office,dastarxon,seasonal --stage=public [--apply]
 */
'use strict';

const { mergeConfig, CONFIG_DOC } = require('../restaurant_sections_config');
const { SECTION_KEYS } = require('../restaurant_dish_index');

async function main() {
  const admin = require('firebase-admin');
  const path = require('path');
  if (!admin.apps.length) {
    if (process.env.FIRESTORE_EMULATOR_HOST) {
      admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-sections' });
    } else {
      admin.initializeApp({ credential: admin.credential.cert(require(path.join(__dirname, '..', 'service-account.json'))) });
    }
  }
  const db = admin.firestore();
  const apply = process.argv.includes('--apply');
  const arg = (name) => (process.argv.find((a) => a.startsWith(`--${name}=`)) || '').split('=')[1] || '';
  const keys = arg('sections').split(',').map((s) => s.trim()).filter(Boolean);
  const stage = arg('stage');
  if (!keys.length || keys.some((k) => !SECTION_KEYS.includes(k))) throw new Error(`--sections noto'g'ri; mumkin: ${SECTION_KEYS.join(', ')}`);
  if (!['off', 'internal', 'public'].includes(stage)) throw new Error(`--stage noto'g'ri: ${stage}`);

  const fail = (status, code) => new Error(`${status}/${code}`);
  const canonicalUid = (x) => String(x || '').replace(/\D/g, '');
  const ref = db.collection(CONFIG_DOC[0]).doc(CONFIG_DOC[1]);
  const reason = `Ega buyrug'i 2026-10-19: ${keys.join(', ')} → ${stage}`;
  const actor = 'script:set_restaurant_sections';
  console.log(`${apply ? 'APPLY' : 'DRY RUN'} — settings/restaurant_sections: ${keys.join(', ')} → ${stage}`);

  const out = await db.runTransaction(async (t) => {
    const snap = await t.get(ref);
    if (!snap.exists) throw new Error('Hujjat YO\'Q — avval enable_restaurant_sections.js');
    const cur = snap.data() || {};
    const next = mergeConfig({ sections: Object.fromEntries(keys.map((k) => [k, stage])) }, cur, { fail, canonicalUid });
    const same = JSON.stringify(next) === JSON.stringify({
      sections: cur.sections, testerIds: cur.testerIds, cheapRatingThreshold: cur.cheapRatingThreshold,
      newMaxRatings: cur.newMaxRatings, newMaxDays: cur.newMaxDays, newPerRestaurantPerSection: cur.newPerRestaurantPerSection,
    });
    console.log(`Joriy versiya: ${cur.version}; bo'limlar: ${JSON.stringify(cur.sections)}`);
    console.log(`Yangi bo'limlar: ${JSON.stringify(next.sections)}`);
    if (same) return { changed: false, version: cur.version };
    if (!apply) return { changed: true, dry: true, version: (cur.version || 0) + 1 };
    const version = (Number.isInteger(cur.version) ? cur.version : 0) + 1;
    const ts = admin.firestore.FieldValue.serverTimestamp();
    const doc = { ...next, version, reason, updatedAt: ts, updatedBy: actor };
    t.set(ref, doc);
    t.create(db.collection('restaurant_sections_history').doc(`v${version}`), {
      ...doc, previous: { version: cur.version || 0, sections: cur.sections || {}, cheapRatingThreshold: cur.cheapRatingThreshold ?? null },
    });
    t.set(db.collection('admin_audit').doc(), { kind: 'restaurant_sections_set', actor, target: `v${version}`, reason, at: ts });
    return { changed: true, version };
  });
  console.log(out.changed ? (out.dry ? `Yoziladi: v${out.version}` : `YOZILDI: v${out.version}`) : 'O\'zgarish yo\'q — tegilmadi.');
}

if (require.main === module) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
