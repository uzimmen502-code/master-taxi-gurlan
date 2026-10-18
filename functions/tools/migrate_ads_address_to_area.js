/**
 * `ads` (Иш топ: work / service / ad) — eski `address` (egasining PROFIL / UY
 * manzili) ni OMMAVIY hudud yorlig'iga almashtiradi: "Гурлан тумани, Хоразм вилояти".
 *
 * Nega: 2026-10-18 audit B6. Eski `submitJobAd` mijozdan kelgan `address`ni (profildagi
 * uy manzili) ommaviy `ads` hujjatiga yozgan, `ads` esa hammaga o'qiladi. Yangi
 * `submitJobAd` faqat hudud yorlig'i yozadi; bu skript ESKI hujjatlarni shunga keltiradi.
 *
 * Hudud manbasi: hujjatning `districtId`/`regionId` si; bo'sh bo'lsa — egasining
 * `users/{...}.districtId` si (FAQAT o'qiladi; `districtId` hujjatga YOZILMAYDI — bu
 * skript faqat `address`ga tegadi). Hudud topilmasa `address` = '' (uy manzili
 * ommaviy qolmasin). Nom: `nameUz` (kirill) → `name` (lotin) — `submitJobAd` bilan bir xil.
 *
 * CLAUDE.md 27: dry-run · backup · batch · progress · verification · rollback.
 *   1) node functions/tools/migrate_ads_address_to_area.js            (DRY, default; hech narsa yozilmaydi)
 *   2) node functions/tools/migrate_ads_address_to_area.js --apply     (backup -> yozish -> tekshirish)
 *   3) node functions/tools/migrate_ads_address_to_area.js --rollback <backup.json>
 *
 * Xavfsizlik:
 *  - faqat `address` maydoni; `editedAt`/`moderatedAt`/`status` tegilmaydi (`onAdUpdate`
 *    faqat text/title/priceText/isUrgent/type o'zgarsa qayta moderatsiyaga qaytaradi);
 *  - har yozuv `lastUpdateTime` sharti bilan: orada hujjat o'zgargan bo'lsa SKIP (ustiga yozmaydi);
 *  - idempotent: `address` allaqachon yorliqqa teng bo'lsa tegilmaydi;
 *  - backup (eski manzillar — PII!) `functions/tools/backup/` ga yoziladi, GIT'GA QO'SHILMAYDI.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const argv = process.argv.slice(2);
const APPLY = argv.includes('--apply');
const rbIdx = argv.indexOf('--rollback');
const ROLLBACK_FILE = rbIdx >= 0 ? argv[rbIdx + 1] : '';
const CONCURRENCY = 10;
const JOBS_TYPES = ['work', 'service', 'ad'];

const EMULATOR = !!process.env.FIRESTORE_EMULATOR_HOST;   // test (demo-* loyiha) — productionga tegmaydi
if (EMULATOR) {
  const pid = process.env.GCLOUD_PROJECT || '';
  if (!/^demo-/.test(pid)) { console.error('Emulyatorda demo-* loyiha kerak'); process.exit(1); }
  admin.initializeApp({ projectId: pid });
} else {
  const keyPath = path.join(__dirname, '..', 'service-account.json');
  if (!fs.existsSync(keyPath)) {
    console.error('service-account.json topilmadi:', keyPath);
    process.exit(1);
  }
  admin.initializeApp({ credential: admin.credential.cert(require(keyPath)) });
}
const db = admin.firestore();
if (!EMULATOR) db.settings({ preferRest: true });
const BACKUP_DIR = process.env.MIGRATION_BACKUP_DIR || path.join(__dirname, 'backup');

const digits = (raw) => String(raw || '').replace(/\D/g, '');
function ownerAliases(raw) {
  const d = digits(raw);
  if (d.length < 9) return [];
  const out = new Set([d]);
  if (d.length === 12 && d.startsWith('998')) out.add(d.slice(3));
  if (d.length === 9) out.add(`998${d}`);
  return [...out];
}

/** Kirill nom birinchi (eski ilovalar ham ko'rsatadi), bo'lmasa lotin. */
const pickName = (v) => String((v && (v.nameUz || v.name)) || '').trim();

async function loadGeo() {
  const [ds, rs] = await Promise.all([
    db.collection('geo_districts').get(),
    db.collection('geo_regions').get(),
  ]);
  const districts = new Map(ds.docs.map((d) => [d.id, d.data() || {}]));
  const regions = new Map(rs.docs.map((d) => [d.id, d.data() || {}]));
  return { districts, regions };
}

function labelFor(geo, districtId, regionId) {
  const dist = districtId ? geo.districts.get(districtId) : null;
  const regId = regionId || (dist && String(dist.regionId || '').trim()) || '';
  const reg = regId ? geo.regions.get(regId) : null;
  return [pickName(dist), pickName(reg)].filter(Boolean).join(', ');
}

const ownerCache = new Map();
async function ownerGeo(phone) {
  for (const id of ownerAliases(phone)) {
    if (!ownerCache.has(id)) {
      const s = await db.collection('users').doc(id).get();
      const u = s.exists ? (s.data() || {}) : null;
      const districtId = u ? String(u.districtId || '').trim() : '';
      ownerCache.set(id, districtId
        ? { districtId, regionId: String(u.regionId || '').trim() } : null);
    }
    const hit = ownerCache.get(id);
    if (hit) return hit;
  }
  return null;
}

async function pool(items, fn, n) {
  let i = 0;
  const workers = Array.from({ length: n }, async () => {
    while (i < items.length) {
      const my = i++;
      await fn(items[my], my);
    }
  });
  await Promise.all(workers);
}

async function plan() {
  const geo = await loadGeo();
  console.log(`geo_districts=${geo.districts.size} geo_regions=${geo.regions.size}`);
  const snap = await db.collection('ads').where('type', 'in', JOBS_TYPES).get();
  console.log(`Ish top (work/service/ad) hujjatlari: ${snap.size}`);
  const stats = { alreadyOk: 0, emptyAddrAlready: 0, byDoc: 0, byOwner: 0, noGeo: 0, toChange: 0 };
  const changes = [];
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    const old = String(d.address || '');
    let districtId = String(d.districtId || '').trim();
    let regionId = String(d.regionId || '').trim();
    let source = 'doc';
    if (!districtId && !regionId) {
      const g = await ownerGeo(d.authorPhone);
      if (g) { districtId = g.districtId; regionId = g.regionId; source = 'owner'; } else source = 'none';
    }
    const label = (districtId || regionId) ? labelFor(geo, districtId, regionId) : '';
    if (source === 'doc') stats.byDoc++; else if (source === 'owner') stats.byOwner++; else stats.noGeo++;
    if (old === label) { if (old === '') stats.emptyAddrAlready++; else stats.alreadyOk++; continue; }
    changes.push({
      id: doc.id, type: d.type, status: d.status, source,
      old, neu: label, updateTime: doc.updateTime.toDate().toISOString(),
      updateTimeRaw: { s: doc.updateTime.seconds, n: doc.updateTime.nanoseconds },
    });
  }
  stats.toChange = changes.length;
  return { changes, stats, total: snap.size };
}

function report({ changes, stats, total }) {
  console.log('\n--- HISOBOT ---');
  console.log(`  jami                      : ${total}`);
  console.log(`  hudud manbai: hujjat/ega/yo'q : ${stats.byDoc} / ${stats.byOwner} / ${stats.noGeo}`);
  console.log(`  allaqachon yorliq         : ${stats.alreadyOk}`);
  console.log(`  allaqachon bo'sh          : ${stats.emptyAddrAlready}`);
  console.log(`  O'ZGARTIRILADI            : ${stats.toChange}`);
  const clear = changes.filter((c) => c.neu === '').length;
  console.log(`    shundan '' ga (hudud yo'q): ${clear}`);
  const labels = new Map();
  for (const c of changes) labels.set(c.neu, (labels.get(c.neu) || 0) + 1);
  console.log('  yangi yorliqlar (soni):');
  [...labels.entries()].sort((a, b) => b[1] - a[1]).slice(0, 12)
    .forEach(([l, n]) => console.log(`    ${String(n).padStart(4)}  ${l === '' ? "''" : l}`));
}

async function apply() {
  const p = await plan();
  report(p);
  if (!p.changes.length) { console.log('\nO\'zgartiriladigan hujjat yo\'q.'); return; }

  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const dir = BACKUP_DIR;
  fs.mkdirSync(dir, { recursive: true });
  const backupPath = path.join(dir, `ads-address-backup-${stamp}.json`);
  fs.writeFileSync(backupPath, JSON.stringify({
    createdAt: new Date().toISOString(),
    note: 'ads.address ESKI qiymatlari (PII: uy manzillari) — git\'ga QO\'SHMANG. Rollback: --rollback <shu fayl>',
    items: p.changes.map(({ id, old, neu, updateTime }) => ({ id, old, neu, updateTime })),
  }, null, 2), 'utf8');
  const back = JSON.parse(fs.readFileSync(backupPath, 'utf8'));
  if (back.items.length !== p.changes.length) throw new Error('backup tekshiruvi muvaffaqiyatsiz');
  console.log(`\nBACKUP yozildi va tekshirildi: ${backupPath} (${back.items.length})`);

  const res = { written: 0, skippedConcurrent: 0, failed: 0 };
  await pool(p.changes, async (c, idx) => {
    const ref = db.collection('ads').doc(c.id);
    try {
      // Aniq (nanosekund) updateTime — ISO (ms) bilan sharti mos kelmasdi.
      await ref.update({ address: c.neu },
        { lastUpdateTime: new admin.firestore.Timestamp(c.updateTimeRaw.s, c.updateTimeRaw.n) });
      res.written++;
    } catch (e) {
      const msg = String(e && e.message || e);
      if (/FAILED_PRECONDITION|precondition|updated|NOT_FOUND/i.test(msg)) res.skippedConcurrent++;
      else { res.failed++; console.error(`  XATO ${c.id}: ${msg}`); }
    }
    if ((idx + 1) % 50 === 0) console.log(`  progress ${idx + 1}/${p.changes.length}`);
  }, CONCURRENCY);
  console.log(`\nYOZILDI=${res.written}  SKIP(orada o'zgargan)=${res.skippedConcurrent}  XATO=${res.failed}`);

  // Tekshirish: qayta o'qib, kutilgan qiymatni solishtirish.
  let bad = 0;
  await pool(p.changes, async (c) => {
    const s = await db.collection('ads').doc(c.id).get();
    const cur = s.exists ? String((s.data() || {}).address || '') : null;
    if (cur !== c.neu && cur !== c.old) bad++;       // boshqa qiymatga o'zgargan
  }, CONCURRENCY);
  const again = await plan();
  console.log(`TEKSHIRUV: kutilmagan qiymat=${bad}; qayta rejada qolgan=${again.stats.toChange} (SKIP/xato soniga teng bo'lishi kerak)`);
  console.log(`Rollback: node functions/tools/migrate_ads_address_to_area.js --rollback "${backupPath}"`);
}

async function rollback(file) {
  const back = JSON.parse(fs.readFileSync(file, 'utf8'));
  console.log(`Rollback: ${back.items.length} hujjat, backup ${back.createdAt}`);
  let ok = 0, skipped = 0;
  await pool(back.items, async (it) => {
    const ref = db.collection('ads').doc(it.id);
    const s = await ref.get();
    if (!s.exists) { skipped++; return; }
    const cur = String((s.data() || {}).address || '');
    if (cur !== it.neu) { skipped++; return; }       // keyin o'zgartirilgan — tegmaymiz
    await ref.update({ address: it.old }, { lastUpdateTime: s.updateTime });
    ok++;
  }, CONCURRENCY);
  console.log(`Qaytarildi=${ok}  tegilmadi(keyin o'zgargan/yo'q)=${skipped}`);
}

(async () => {
  if (ROLLBACK_FILE) await rollback(ROLLBACK_FILE);
  else if (APPLY) await apply();
  else { report(await plan()); console.log('\n(DRY: hech narsa yozilmadi. Yozish uchun --apply)'); }
})().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
