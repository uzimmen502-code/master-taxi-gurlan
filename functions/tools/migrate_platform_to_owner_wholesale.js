/**
 * AVA дўкони маҳсулотлари (`platform_products`) → эганинг Улгуржи бўлими (`wholesale_products`).
 *
 * Эга қарори (2026-11-01): «АВА дўкон маҳсулотларини ҳам Улгуржи бўлимимга олиб ўт, чунки уларни ҳам
 * мен киритганман». Жавоблар: Аралаш бозорда AVA нусхаси ҚОЛАДИ (сават билан, `platform_products`
 * ўзгармайди); Улгуржида фақат эганинг бўлимидан; сотувчи номи «AVA»; буюртма — қўнғироқ + чат.
 *
 * Нима қилади (--apply билан):
 *   1. Захира: platform_products (ҳаммаси), wholesale_sellers/{эга}, эганинг wholesale_products → JSON.
 *   2. Ҳар фаол AVA маҳсулоти учун `wholesale_products/pp_<platformId>` (детерминистик ID — қайта
 *      ишга туширилса дубликат йўқ; мавжуди ўтказиб юборилади). Майдонлар — илова яратадиган ҳужжат
 *      шакли (rules create whitelist), status=active, market=wholesale.
 *      Нарх поғоналари: сақланган `priceTiers`, бўлмаса `platform_pricing.js` қоидаси (эски товар →
 *      +5% / нарх / −5%), бўлмаса ягона нарх. Пул — бутун сўм.
 *   3. `wholesale_sellers/{эга}.companyName = 'AVA'` ва эганинг мавжуд маҳсулотларида
 *      `sellerCompanyName = 'AVA'`.
 *   4. `admin_audit` ёзуви.
 * platform_products'га ТЕГИЛМАЙДИ.
 *
 * Орқага қайтариш: --rollback --from=<backup.json> — `pp_*` ҳужжатларини ўчиради ва companyName /
 * sellerCompanyName'ни захирадаги қийматга қайтаради.
 *
 *   node functions/tools/migrate_platform_to_owner_wholesale.js --owner-suffix=8777 --sa=<key.json>   (dry-run)
 *   node functions/tools/migrate_platform_to_owner_wholesale.js --owner-suffix=8777 --apply
 *   node functions/tools/migrate_platform_to_owner_wholesale.js --owner-suffix=8777 --rollback --from=...json
 *
 * Логда телефон рақами тўлиқ чиқмайди (40-банд).
 */
'use strict';

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');
const { derivedTiers, isLegacyProduct } = require('../platform_pricing');
const { marketToLatin, marketToCyrillic } = require('../search_tokens');

const APPLY = process.argv.includes('--apply');
const ROLLBACK = process.argv.includes('--rollback');
const arg = (name) => {
  const a = process.argv.find((x) => x.startsWith(`--${name}=`));
  return a ? a.slice(name.length + 3) : '';
};
const OWNER_SUFFIX = arg('owner-suffix');
const COMPANY = 'AVA';
const ID_PREFIX = 'pp_';

// Калит репода йўқ (.gitignore): --sa=<йўл> ёки functions/service-account.json.
const sa = arg('sa') || path.join(__dirname, '..', 'service-account.json');
admin.initializeApp({ credential: admin.credential.cert(require(sa)) });
const db = admin.firestore();
db.settings({ preferRest: true });
const FieldValue = admin.firestore.FieldValue;
const mask = (p) => `***${String(p).slice(-4)}`;

// Илова/сервер токенлари билан бир хил шакл (index.js buildMarketSearchTokens).
function searchTokens(title, description) {
  const text = `${title || ''} ${description || ''}`.toLowerCase();
  const words = text.split(/[^0-9a-zа-яёўқғҳʻʼ']+/i).filter((w) => w && w.length >= 2);
  const out = new Set();
  for (const w of words) {
    out.add(w);
    const l = marketToLatin(w);
    const c = marketToCyrillic(w);
    if (l.length >= 2) out.add(l);
    if (c.length >= 2) out.add(c);
    if (out.size >= 48) break;
  }
  return Array.from(out).slice(0, 48);
}

function tiersOf(p) {
  const stored = Array.isArray(p.priceTiers) ? p.priceTiers : [];
  const clean = stored
    .map((t) => ({ minQty: Math.trunc(Number(t && t.minQty)), price: Math.trunc(Number(t && t.price)) }))
    .filter((t) => Number.isInteger(t.minQty) && t.minQty >= 1 && Number.isInteger(t.price) && t.price > 0)
    .sort((a, b) => a.minQty - b.minQty)
    .slice(0, 5);
  if (clean.length) return clean;
  const price = Math.trunc(Number(p.price));
  if (!Number.isInteger(price) || price <= 0) return [];
  if (isLegacyProduct(p)) return derivedTiers(price);
  return [{ minQty: 1, price }];
}

function mapProduct(id, p, ownerId) {
  const title = String(p.name || '').trim().slice(0, 120);
  let description = String(p.description || '').trim().slice(0, 2000);
  if (description.length < 3) description = title;
  const images = (Array.isArray(p.imageUrls) && p.imageUrls.length ? p.imageUrls : [p.imageUrl])
    .map((u) => String(u || '').trim())
    .filter((u) => /^https:\/\//.test(u))
    .slice(0, 7);
  const priceTiers = tiersOf(p);
  const problems = [];
  if (title.length < 3) problems.push('title<3');
  if (description.length < 3) problems.push('description<3');
  if (!images.length) problems.push('no_image');
  if (!priceTiers.length) problems.push('no_price');
  const unit = String(p.unit || '').trim() || 'дона';
  return {
    problems,
    doc: {
      sellerId: ownerId,
      sellerCompanyName: COMPANY,
      title,
      titleLower: title.toLowerCase(),
      searchTokens: searchTokens(title, description),
      description,
      priceTiers,
      unit,
      imageUrls: images,
      status: 'active',
      views: 0,
      videoClipIds: [],
      market: 'wholesale',
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      publishedAt: FieldValue.serverTimestamp(),
    },
  };
}

function toJson(v) {
  if (v && typeof v.toDate === 'function') return { _ts: v.toDate().toISOString() };
  if (Array.isArray(v)) return v.map(toJson);
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, toJson(x)]));
  return v;
}

async function resolveOwner() {
  if (!/^\d{4}$/.test(OWNER_SUFFIX)) throw new Error('--owner-suffix=NNNN керак (эга рақамининг охирги 4 хонаси)');
  const snap = await db.collection('wholesale_sellers').get();
  const hits = snap.docs.filter((d) => d.id.endsWith(OWNER_SUFFIX));
  if (hits.length !== 1) throw new Error(`эга топилмади ёки бир нечта: ${hits.length}`);
  return hits[0];
}

async function main() {
  const owner = await resolveOwner();
  const ownerId = owner.id;
  console.log(`MODE: ${ROLLBACK ? 'ROLLBACK' : APPLY ? 'APPLY' : 'dry-run (pass --apply)'}; owner ${mask(ownerId)}`);

  if (ROLLBACK) {
    const from = arg('from');
    if (!from) throw new Error('--from=<backup.json> керак');
    const backup = JSON.parse(fs.readFileSync(from, 'utf8'));
    if (backup.ownerId !== ownerId) throw new Error('захира бошқа эгага тегишли');
    const created = await db.collection('wholesale_products').where('sellerId', '==', ownerId).get();
    const toDelete = created.docs.filter((d) => d.id.startsWith(ID_PREFIX));
    console.log(`delete ${toDelete.length} ${ID_PREFIX}* docs; restore companyName → "${backup.seller.companyName}"`);
    if (!APPLY) return console.log('(rollback dry-run; add --apply)');
    for (let i = 0; i < toDelete.length; i += 400) {
      const b = db.batch();
      toDelete.slice(i, i + 400).forEach((d) => b.delete(d.ref));
      await b.commit();
    }
    const b = db.batch();
    b.update(owner.ref, { companyName: backup.seller.companyName, updatedAt: FieldValue.serverTimestamp() });
    for (const p of backup.ownerProducts) {
      const ref = db.collection('wholesale_products').doc(p.id);
      if ((await ref.get()).exists) b.update(ref, { sellerCompanyName: p.data.sellerCompanyName || '' });
    }
    b.set(db.collection('admin_audit').doc(), {
      action: 'migratePlatformToOwnerWholesale.rollback', owner: mask(ownerId), deleted: toDelete.length,
      at: FieldValue.serverTimestamp(),
    });
    await b.commit();
    return console.log('rollback done');
  }

  const [platform, ownerProducts] = await Promise.all([
    db.collection('platform_products').get(),
    db.collection('wholesale_products').where('sellerId', '==', ownerId).get(),
  ]);
  const existing = new Set(ownerProducts.docs.map((d) => d.id));
  const plan = [];
  const skipped = [];
  for (const d of platform.docs) {
    const p = d.data();
    if (p.active !== true) { skipped.push([d.id, 'inactive']); continue; }
    const id = `${ID_PREFIX}${d.id}`;
    if (existing.has(id)) { skipped.push([d.id, 'already_migrated']); continue; }
    const m = mapProduct(d.id, p, ownerId);
    if (m.problems.length) { skipped.push([d.id, m.problems.join(',')]); continue; }
    plan.push({ id, sourceId: d.id, doc: m.doc });
  }
  const renameProducts = ownerProducts.docs.filter((d) => (d.data().sellerCompanyName || '') !== COMPANY);

  console.log(`platform_products: ${platform.size}; to create: ${plan.length}; skipped: ${skipped.length}`);
  skipped.forEach(([id, why]) => console.log(`  skip ${id}: ${why}`));
  console.log(`seller companyName: "${owner.data().companyName || ''}" → "${COMPANY}"; owner products to rename: ${renameProducts.length}`);
  plan.slice(0, 4).forEach((x) => console.log(`  e.g. ${x.id}: "${x.doc.title}" tiers=${JSON.stringify(x.doc.priceTiers)} imgs=${x.doc.imageUrls.length} tokens=${x.doc.searchTokens.length}`));
  if (!APPLY) return console.log('(dry-run — nothing written)');

  const backupDir = path.join(__dirname, 'backup');
  fs.mkdirSync(backupDir, { recursive: true });
  const file = path.join(backupDir, `platform-to-wholesale-backup-${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  fs.writeFileSync(file, JSON.stringify({
    ownerId,
    seller: toJson(owner.data()),
    ownerProducts: ownerProducts.docs.map((d) => ({ id: d.id, data: toJson(d.data()) })),
    platformProducts: platform.docs.map((d) => ({ id: d.id, data: toJson(d.data()) })),
  }, null, 2));
  console.log(`backup: ${file}`);

  for (let i = 0; i < plan.length; i += 400) {
    const b = db.batch();
    // create — мавжуд бўлса батч йиқилади (пойга/қайта ишга тушириш дубликат қилмайди).
    plan.slice(i, i + 400).forEach((x) => b.create(db.collection('wholesale_products').doc(x.id), x.doc));
    await b.commit();
    console.log(`created ${Math.min(i + 400, plan.length)}/${plan.length}`);
  }
  const b = db.batch();
  b.update(owner.ref, { companyName: COMPANY, updatedAt: FieldValue.serverTimestamp() });
  renameProducts.forEach((d) => b.update(d.ref, { sellerCompanyName: COMPANY }));
  b.set(db.collection('admin_audit').doc(), {
    action: 'migratePlatformToOwnerWholesale', owner: mask(ownerId), created: plan.length,
    renamed: renameProducts.length, backup: path.basename(file), at: FieldValue.serverTimestamp(),
  });
  await b.commit();

  const verify = await db.collection('wholesale_products').where('sellerId', '==', ownerId).get();
  const pp = verify.docs.filter((d) => d.id.startsWith(ID_PREFIX));
  console.log(`verify: owner products ${verify.size} (pp_* ${pp.length}, active ${pp.filter((d) => d.data().status === 'active').length})`);
}

main().then(() => process.exit(0)).catch((e) => { console.error('FAILED:', e.message); process.exit(1); });
