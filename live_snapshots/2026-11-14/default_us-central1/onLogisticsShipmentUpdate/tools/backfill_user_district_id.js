/**
 * `users/{uid}.districtId` — манзилдаги туман НОМИдан `geo_districts` ID'си.
 *
 * МУАММО (аудит, 2026-09-27): фойдаланувчи манзилини тўлдирганда профилга
 * `address.district` — туманнинг ЎҚИЛАДИГАН НОМИ ёзилади («Гурлан»), лекин
 * `districtId` (геолокация ID'си, «gurlan») ёзилмайди.
 *
 * `ownerGeoStamp()` эса ФАҚАТ `districtId` ни ўқийди ва топа олмаса бўш
 * қайтаради. Натижада ўша фойдаланувчининг ҲАР эълони — ҳам АҲОЛИ БОЗОРИ
 * (`submitMarketAd`), ҳам ИШ ЭЪЛОН (`submitJobAd`) — тумансиз чиқади ва
 * бош саҳифада БАРЧА туманда кўринади.
 *
 * Ўлчов: 199 фойдаланувчидан 76 таси (38%) айнан шу ҳолатда эди.
 *
 * Бу скрипт ТАХМИН ҚИЛМАЙДИ: фақат фойдаланувчининг ЎЗИ ёзган туман номи
 * `geo_districts` даги ном билан мос тушса ёзади. Мос келмаса — ўтказиб
 * юборади ва рўйхатда кўрсатади (қўлда ҳал қилинади).
 *
 * Ишлатиш:
 *   node functions/tools/backfill_user_district_id.js            # dry run
 *   node functions/tools/backfill_user_district_id.js --apply
 */
const admin = require('firebase-admin');
const path = require('path');

if (!admin.apps.length) {
  const sa = path.join(__dirname, '..', 'service-account.json');
  admin.initializeApp({credential: admin.credential.cert(require(sa))});
}
const db = admin.firestore();
db.settings({preferRest: true});

const APPLY = process.argv.includes('--apply');

/** «Gurlan tumani» / «Гурлан тумани» / «Гурлан» → «гурлан». */
function normName(s) {
  return String(s || '')
      .toLowerCase()
      .replace(/\s*(tumani|tuman|туман[иа]?|район)\s*/gi, ' ')
      .replace(/[^0-9a-zа-яёўқғҳ'’ʻ ]+/gi, ' ')
      .replace(/\s+/g, ' ')
      .trim();
}

/**
 * Ўзбек кирилл ҳарфларининг диакритикасини тушириб юборади:
 * ғ→г, қ→к, ҳ→х, ў→у, ё→е, апостроф/ъ/ь → йўқ.
 *
 * НЕГА КЕРАК: фойдаланувчилар манзилни қўлда ёзади ва телефон
 * клавиатурасида ғ/қ/ў/ҳ кўпинча йўқ — «Мирзо Улугбек» деб ёзилади,
 * `geo_districts` да эса «Мирзо Улуғбек тумани». Аниқ солиштиришда
 * булар мос тушмайди (аудитда 1 та фойдаланувчи шу сабабдан тушиб
 * қолган эди).
 *
 * Бу фақат ЗАХИРА йўл: аввал аниқ мослик изланади, топилмаса —
 * фолд. Шунинг учун фолд ҳеч қачон аниқ мосликни бузиб юбормайди.
 */
function foldName(s) {
  return normName(s)
      .replace(/ғ/g, 'г')
      .replace(/қ/g, 'к')
      .replace(/ҳ/g, 'х')
      .replace(/ў/g, 'у')
      .replace(/ё/g, 'е')
      .replace(/[ъь'’ʻ]/g, '')
      .replace(/\s+/g, ' ')
      .trim();
}

async function main() {
  console.log('=== users.districtId backfill (манзилдаги туман номидан) ===');
  console.log(APPLY ? 'APPLY — ёзилади' : 'DRY RUN — ҳеч нарса ёзилмайди');
  console.log('');

  const gs = await db.collection('geo_districts').get();
  const byName = new Map();
  // Фолд калити → мос тушган ТУМАНЛАР. Иккитадан кўп бўлса — ноаниқ,
  // ишлатилмайди (икки ҳар хил туман бир хил фолдга тушиб қолса,
  // тасодифан нотўғрисини ёзиб юбормаслик учун).
  const byFold = new Map();

  const addFold = (key, hit) => {
    if (!key) return;
    const cur = byFold.get(key);
    if (!cur) {
      byFold.set(key, hit);
    } else if (cur.id !== hit.id) {
      cur.ambiguous = true;
    }
  };

  for (const doc of gs.docs) {
    const x = doc.data() || {};
    const regionId = String(x.regionId || '').trim();
    const hit = {id: doc.id, regionId};
    for (const n of [x.name, x.nameUz, x.nameUzCyrl, x.nameRu, x.title]) {
      if (!n) continue;
      const k = normName(n);
      if (k && !byName.has(k)) byName.set(k, hit);
      addFold(foldName(n), hit);
    }
    // ID'нинг ўзи ҳам мос келиши мумкин («gurlan»).
    if (!byName.has(doc.id)) byName.set(doc.id, hit);
    addFold(foldName(doc.id), hit);
  }
  const ambiguous = [...byFold.entries()].filter(([, v]) => v.ambiguous);
  console.log(`geo_districts: ${gs.size} та, ${byName.size} та ном варианти`);
  console.log(`фолд калитлари: ${byFold.size} та` +
      (ambiguous.length ? `, ${ambiguous.length} таси ноаниқ (ишлатилмайди)` : ''));

  const us = await db.collection('users').get();
  const todo = [];
  const nomatch = new Map();
  // Фолд орқали топилганлар — эга кўриб чиқиши учун алоҳида кўрсатилади.
  const foldHits = new Map();
  let hasId = 0;
  let noAddr = 0;

  for (const doc of us.docs) {
    const u = doc.data() || {};
    if (String(u.districtId || '').trim()) {
      hasId++;
      continue;
    }
    const raw = u.address && u.address.district
        ? String(u.address.district).trim()
        : '';
    if (!raw) {
      noAddr++;
      continue;
    }
    // Аввал аниқ мослик, топилмаса — диакритикасиз (фолд) захира йўли.
    let hit = byName.get(normName(raw));
    let via = 'аниқ';
    if (!hit) {
      const f = byFold.get(foldName(raw));
      if (f && !f.ambiguous) {
        hit = f;
        via = 'фолд';
      }
    }
    if (!hit) {
      nomatch.set(raw, (nomatch.get(raw) || 0) + 1);
      continue;
    }
    if (via === 'фолд') foldHits.set(raw, hit.id);
    todo.push({ref: doc.ref, uid: doc.id, raw, ...hit});
  }

  console.log(`users жами            : ${us.size}`);
  console.log(`districtId аллақачон  : ${hasId}`);
  console.log(`манзилда туман йўқ    : ${noAddr}`);
  console.log(`ЁЗИЛАДИ               : ${todo.length}`);
  if (foldHits.size) {
    console.log('');
    console.log('ℹ️  диакритикасиз мослик (ғ→г, қ→к, ў→у, ҳ→х) — текшириб чиқинг:');
    for (const [n, id] of foldHits) {
      console.log(`   ${JSON.stringify(n)}  →  ${id}`);
    }
  }
  if (nomatch.size) {
    console.log('');
    console.log('⚠️  мос келмади (қўлда ҳал қилинг):');
    for (const [n, c] of nomatch) console.log(`   ${c} та  ${JSON.stringify(n)}`);
  }

  const byDistrict = {};
  todo.forEach((t) => {
    byDistrict[t.id] = (byDistrict[t.id] || 0) + 1;
  });
  console.log('');
  console.log('тақсимот:', JSON.stringify(byDistrict));

  if (!APPLY) {
    console.log('');
    console.log('Бажариш учун: --apply');
    return;
  }

  let batch = db.batch();
  let n = 0;
  for (const t of todo) {
    const patch = {districtId: t.id};
    if (t.regionId) patch.regionId = t.regionId;
    batch.update(t.ref, patch);
    n++;
    if (n % 400 === 0) {
      await batch.commit();
      batch = db.batch();
    }
  }
  if (n % 400 !== 0) await batch.commit();
  console.log('');
  console.log(`✅ ${n} та фойдаланувчига districtId ёзилди.`);
  console.log('Кейин: node functions/tools/backfill_ads_district.js --apply');
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
