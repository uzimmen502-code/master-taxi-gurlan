/**
 * Бош экран баннери (`home_ticker_ads`) матнларидан юмшоқ дефисни (U+00AD) олиб ташлаш (эга, 2026-10-26: «рухсат»).
 *
 * Сабаб: 2026-06-21 да (61730198, `migrate_ticker_hyphenation.js`) бўғин кўчириш учун атайлаб қўйилган эди, лекин
 * Flutter бу нуқтада сўзни ДЕФИССИЗ бўлади — жонли веб (375 px) да «QIDIRAYAPSIZ / MI?», «TOPI / SHINGIZ» каби
 * иккита сўз бўлиб ўқилади. Баннер энди 75 px / 4 қатор (аввал 53 px / 3 қатор) — сўзлар бутунлигича кўчади.
 *
 * Хавфсизлик (27, 28-банд):
 *   - DRY RUN — стандарт: қайси ҳужжатнинг қайси майдонида нечта белги бор, ҳеч нарса ёзилмайди.
 *   - `--apply`: ёзишдан ОЛДИН заҳира (`tools/backup/ticker_shy_<vaqt>.json`: майдоннинг аввалги тўлиқ қиймати),
 *     битта батч (ҳужжатлар кам), фақат шу майдонлар + `updatedAt`; такрор ишга туширилса — ўзгариш йўқ (idempotent).
 *   - Қайтариш: `--rollback <backup.json> --apply` — аввалги матнлар айнан тикланади.
 *
 *   node functions/tools/strip_ticker_soft_hyphens.js            # dry run
 *   node functions/tools/strip_ticker_soft_hyphens.js --apply
 *   node functions/tools/strip_ticker_soft_hyphens.js --rollback functions/tools/backup/<file>.json --apply
 *   Ихтиёрий: `--sa <service-account.json>` (стандарт: functions/service-account.json).
 */
'use strict';

const fs = require('fs');
const path = require('path');

const FIELDS = ['text', 'textLatn', 'textRu'];
const SHY = /­/g;

/** Режа (тест ишлатади): қайси ҳужжатнинг қайси майдонига нима ёзилади. */
async function plan(db) {
  const out = [];
  const snap = await db.collection('home_ticker_ads').get();
  snap.docs.forEach((d) => {
    const x = d.data() || {};
    FIELDS.forEach((f) => {
      const v = x[f];
      if (typeof v !== 'string' || !SHY.test(v)) return;
      SHY.lastIndex = 0;
      out.push({ id: d.id, field: f, before: v, value: v.replace(SHY, ''), count: (v.match(SHY) || []).length });
    });
  });
  return out;
}

async function write(db, admin, steps, pick) {
  const { FieldValue } = admin.firestore;
  const byDoc = new Map();
  steps.forEach((s) => byDoc.set(s.id, { ...(byDoc.get(s.id) || {}), [s.field]: pick(s) }));
  const ids = [...byDoc.keys()];
  for (let i = 0; i < ids.length; i += 400) {
    const batch = db.batch();
    ids.slice(i, i + 400).forEach((id) => {
      batch.update(db.collection('home_ticker_ads').doc(id), { ...byDoc.get(id), updatedAt: FieldValue.serverTimestamp() });
    });
    await batch.commit();
  }
  return ids.length;
}

async function main() {
  const admin = require('firebase-admin');
  const saIdx = process.argv.indexOf('--sa');
  const sa = saIdx > 0 ? path.resolve(process.argv[saIdx + 1]) : path.join(__dirname, '..', 'service-account.json');
  if (!admin.apps.length) {
    if (process.env.FIRESTORE_EMULATOR_HOST) {
      admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-ticker' });
    } else {
      admin.initializeApp({ credential: admin.credential.cert(require(sa)) });
    }
  }
  const db = admin.firestore();
  const apply = process.argv.includes('--apply');
  const rbIdx = process.argv.indexOf('--rollback');
  if (rbIdx > 0) {
    const steps = JSON.parse(fs.readFileSync(process.argv[rbIdx + 1], 'utf8'));
    console.log(`${apply ? 'APPLY' : 'DRY RUN'} rollback: ${steps.length} ta maydon`);
    if (apply) console.log(`tiklandi: ${await write(db, admin, steps, (s) => s.before)} ta hujjat`);
    return;
  }
  const steps = await plan(db);
  const docs = new Set(steps.map((s) => s.id)).size;
  const total = steps.reduce((n, s) => n + s.count, 0);
  console.log(`${apply ? 'APPLY' : 'DRY RUN'}: ${docs} ta hujjat, ${steps.length} ta maydon, ${total} ta U+00AD`);
  steps.forEach((s) => console.log(`  ${s.id} ${s.field} x${s.count}: ${s.value.slice(0, 60)}`));
  if (!apply || steps.length === 0) return;
  const dir = path.join(__dirname, 'backup');
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `ticker_shy_${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(file, JSON.stringify(steps, null, 1), 'utf8');
  console.log(`zaxira: ${file}`);
  console.log(`yozildi: ${await write(db, admin, steps, (s) => s.value)} ta hujjat`);
  const left = await plan(db);
  console.log(`tekshiruv: qolgan U+00AD maydonlar = ${left.length}`);
}

module.exports = { plan };

if (require.main === module) {
  main().then(() => process.exit(0)).catch((e) => { console.error(e.message); process.exit(1); });
}
