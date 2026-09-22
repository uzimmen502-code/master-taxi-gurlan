/**
 * ⚡ EV зарядлаш нуқталари — очиқ манба (OSM/TOK BOR/Yashil Energiya/Open
 * Charge Map) импорти `ev_charging_stations`'га.
 *
 * Манба: юкловчи томонидан тайёрланган архив (README_AVA_UZ.md,
 * ava_ev_uzbekistan_*.json — CSV эмас, JSON асосий манба; иккаласи бир хил
 * маълумот, иккита импорт такрор ёзувга олиб келади).
 *
 * АСОСИЙ ҚОИДАЛАР (README'дан, кодга мослаб):
 *   - Координата — `location: {latitude, longitude}` МАП (Firestore
 *     GeoPoint ЭМАС — `EvChargingStation.fromDoc` `location['latitude']`
 *     деб ўқийди, GeoPoint'да бу ишламайди).
 *   - Манба ID (`id`) — Firestore ҳужжат ID сифатида ишлатилади: шу орқали
 *     идемпотент upsert (қайта юритилса такрор ёзув яратилмайди).
 *   - Ампер кВтга айлантирилмайди, станция умумий қуввати (`site_capacity_kw`)
 *     бир разъём қуввати (`powerKw`) сифатида ёзилмайди — алоҳида майдон
 *     (`sitePowerKw`).
 *   - Барча импорт ёзувлари `verificationStatus:'imported'`, `status:'unknown'`
 *     — жойида текширилмаган, "ишлаяпти" деб ўйлаб топилмайди.
 *   - `import_status === 'review_required'` (хусусий/ишга тушмаган/тест
 *     режими/зиддиятли қувват) — `isActive:false` билан импорт қилинади:
 *     ҳужжат коллекцияда бор (рўйхатга кирган), лекин оддий очиқ станция
 *     сифатида харитада кўринмайди (`watchNearby` фақат `isActive==true`ни
 *     сўрайди). Admin панелдаги мавжуд "Xaritaga qaytarish" тугмаси
 *     (`adminSetEvStationActive`) — шу ёзувларни қўлда текшириб
 *     фаоллаштириш учун ишлатилади (янги UI шарт эмас).
 *   - Жамоа таҳрирлай оладиган майдонлар (`chargingTypes`, `connectors`,
 *     `powerKw`, `price`, `operatorName`, `note` — `firestore.rules`даги
 *     `evStationCommunityPatch()` whitelist) — ФАҚАТ биринчи яратишда
 *     ёзилади; қайта импортда (ҳужжат аллақачон бор) уларга тегилмайди,
 *     токи фойдаланувчи тузатган маълумот босилиб кетмасин. Бошқа ҳамма
 *     майдон ("source-owned") ҳар импортда янгиланади.
 *
 * Хавфсизлик / қайтариш:
 *   - Default — DRY RUN (ҳеч нарса ёзилмайди), `--apply` билан ҳақиқий ёзув.
 *   - Ҳар югуриш `ev_import_batches/{batchId}` ҳужжатига natija yozadi
 *     (createdIds/updatedIds/unchangedIds/reviewRequiredIds).
 *   - Янгиланган (олдин мавжуд) ҳужжатларнинг ЭСКИ ҳолати
 *     `ev_import_batches/{batchId}/backups/{stationId}`'га сақланади.
 *   - Қайтариш: `--revert <batchId>` — create'ларни ўчиради, update'ларни
 *     backup'дан тиклайди.
 *
 * Ишлатиш:
 *   node functions/tools/import_ev_open_data.js                                   # dry run
 *   node functions/tools/import_ev_open_data.js --file "D:\Downloads\ava_ev_uzbekistan_2026-09-22.json"
 *   node functions/tools/import_ev_open_data.js --apply                            # haqiqiy yozuv
 *   node functions/tools/import_ev_open_data.js --revert import_2026-09-22T120000Z
 */
'use strict';
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const keyPath = path.join(__dirname, '..', 'service-account.json');
if (!fs.existsSync(keyPath)) {
  console.error('service-account.json topilmadi:', keyPath);
  process.exit(1);
}
admin.initializeApp({ credential: admin.credential.cert(require(keyPath)) });
const db = admin.firestore();
db.settings({ preferRest: true });

const APPLY = process.argv.includes('--apply');

function argValue(name, fallback) {
  const i = process.argv.indexOf(name);
  if (i < 0 || i + 1 >= process.argv.length) return fallback;
  return process.argv[i + 1];
}

const DEFAULT_FILE = 'D:/Downloads/ava_ev_uzbekistan_2026-09-22.json';
const FILE_PATH = argValue('--file', DEFAULT_FILE);
const REVERT_BATCH = argValue('--revert', null);

// Ilova UI'dagi razъём qatorlari bilan mos (add_ev_station_screen.dart).
const CONNECTOR_MAP = {
  'CCS2': 'CCS2',
  'Type 2': 'Type 2',
  'CHAdeMO': 'CHAdeMO',
  'GB/T': 'GB/T',
  'GB/T DC': 'GB/T',
  'GB/T AC': 'GB/T',
};
const CHARGING_TYPES = new Set(['AC', 'DC', 'AC+DC']);

// ---- geohash — lib/utils/geo_hash.dart bilan bit-baбит bir xil (standart
// geohash algoritmi; Wikipedia namunasi bilan tasdiqlangan: 57.64911,10.40744
// precision 6 -> "u4pruy"). ----
const GEOHASH_BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';
function geohashEncode(lat, lng, precision = 4) {
  let minLat = -90;
  let maxLat = 90;
  let minLng = -180;
  let maxLng = 180;
  let buf = '';
  let bit = 0;
  let ch = 0;
  let even = true;
  while (buf.length < precision) {
    if (even) {
      const mid = (minLng + maxLng) / 2;
      if (lng >= mid) { ch |= 1 << (4 - bit); minLng = mid; } else { maxLng = mid; }
    } else {
      const mid = (minLat + maxLat) / 2;
      if (lat >= mid) { ch |= 1 << (4 - bit); minLat = mid; } else { maxLat = mid; }
    }
    even = !even;
    bit += 1;
    if (bit === 5) { buf += GEOHASH_BASE32[ch]; bit = 0; ch = 0; }
  }
  return buf;
}

// Ўзбекистон bounding box — координата saqonligini tekshirish uchun.
const UZ_BBOX = { minLat: 37, maxLat: 46, minLng: 55, maxLng: 74 };

/** Manba yozuvidan Firestore maydonlarini quradi. `null` — yaroqsiz (skip). */
function mapRecord(r) {
  const id = String(r.id || '').trim();
  const lat = Number(r.latitude);
  const lng = Number(r.longitude);
  if (!id) return { skip: true, reason: 'id yo\'q' };
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return { skip: true, reason: 'koordinata yaroqsiz', id };
  }
  if (lat < UZ_BBOX.minLat || lat > UZ_BBOX.maxLat || lng < UZ_BBOX.minLng || lng > UZ_BBOX.maxLng) {
    return { skip: true, reason: `koordinata O'zbekiston bbox tashqarisida (${lat}, ${lng})`, id };
  }

  const geohash4 = geohashEncode(lat, lng, 4);

  const chargingTypes = CHARGING_TYPES.has(r.current_type) ? [r.current_type] : [];

  const connectorsSet = new Set();
  (Array.isArray(r.connector_types) ? r.connector_types : []).forEach((c) => {
    connectorsSet.add(CONNECTOR_MAP[c] || 'Бошқа');
  });
  const connectors = [...connectorsSet];

  // Quvvat: FAQAT bitta aniq qiymat bo'lsa powerKw'ga; ko'p variant yoki
  // umumiy maydon quvvati (site_capacity_kw) — aralashtirilmaydi.
  const powerRatingsKw = Array.isArray(r.power_ratings_kw)
    ? r.power_ratings_kw.filter((n) => typeof n === 'number' && Number.isFinite(n))
    : [];
  let powerKw = null;
  if (powerRatingsKw.length === 1) {
    powerKw = powerRatingsKw[0];
  } else if (typeof r.max_connector_power_kw === 'number') {
    // Ushbu datasetda har doim null, lekin kelajakdagi manba uchun qo'llab-quvvatlanadi.
    powerKw = r.max_connector_power_kw;
  }

  const sourceProviders = [...new Set(
    (Array.isArray(r.sources) ? r.sources : []).map((s) => s.source).filter(Boolean),
  )];
  const sourceUpdatedAt = (r.sources && r.sources[0] && r.sources[0].source_updated_at) || null;
  const reviewRequired = r.import_status === 'review_required';

  // Source-owned — HAR importda yangilanadi (jamoa taxrirlay olmaydigan maydonlar).
  const sourceFields = {
    location: { latitude: lat, longitude: lng },
    geohash4,
    geohash: geohash4,
    name: (r.name || '').trim() || null,
    region: r.region || null,
    operatorRef: r.operator_ref || null,
    accessType: r.access || null,
    website: r.website || null,
    phone: r.phone || null,
    address: r.address || null,
    workingHours: r.opening_hours || null,
    sitePowerKw: typeof r.site_capacity_kw === 'number' ? r.site_capacity_kw : null,
    powerRatingsKw,
    powerEvidence: r.power_evidence || null,
    sourceReportedStatus: r.source_reported_status || null,
    sourceType: 'import',
    sourceId: id,
    sourceProvider: sourceProviders.join(', '),
    sourceUrls: Array.isArray(r.source_urls) ? r.source_urls : [],
    sourceLicenses: Array.isArray(r.source_licenses) ? r.source_licenses : [],
    sourceRetrievedAt: r.retrieved_at || null,
    sourceUpdatedAt,
    reviewRequired,
    reviewFlags: Array.isArray(r.review_flags) ? r.review_flags : [],
    possibleDuplicateIds: Array.isArray(r.possible_duplicate_ids) ? r.possible_duplicate_ids : [],
  };

  // Faqat BIRINCHI yaratishda yoziladigan (keyin jamoa tomonidan
  // `evStationCommunityPatch()` orqali tahrirlanishi mumkin bo'lgan) maydonlar.
  const createOnlyFields = {
    chargingTypes,
    connectors,
    powerKw,
    status: 'unknown',
    verificationStatus: 'imported',
    confirmationCount: 0,
    reportCount: 0,
    createdBy: 'import:opendata',
    // review_required — oddiy ochiq stansiya sifatida ko'rsatilmaydi;
    // admin qo'lda tekshirib "Xaritaga qaytarish" bilan faollashtiradi.
    isActive: !reviewRequired,
  };

  return { skip: false, id, sourceFields, createOnlyFields };
}

/** `sourceFields` obyektlarini solishtiradi (yangilanishi kerakmi?). */
function sourceFieldsEqual(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

async function loadRecords() {
  if (!fs.existsSync(FILE_PATH)) {
    console.error(`Manba fayl topilmadi: ${FILE_PATH}\n--file "<yo'l>" bilan ko'rsating.`);
    process.exit(1);
  }
  const raw = fs.readFileSync(FILE_PATH, 'utf8');
  const data = JSON.parse(raw);
  if (!Array.isArray(data)) {
    console.error('Manba JSON massiv emas.');
    process.exit(1);
  }
  return data;
}

async function revert(batchId) {
  console.log(`=== REVERT: ${batchId} ===\n`);
  const batchRef = db.collection('ev_import_batches').doc(batchId);
  const batchSnap = await batchRef.get();
  if (!batchSnap.exists) {
    console.error('Batch topilmadi:', batchId);
    process.exit(1);
  }
  const b = batchSnap.data();
  const createdIds = b.createdIds || [];
  const updatedIds = b.updatedIds || [];
  console.log(`Yaratilgan (o'chiriladi): ${createdIds.length}`);
  console.log(`Yangilangan (backup'dan tiklanadi): ${updatedIds.length}\n`);

  const stations = db.collection('ev_charging_stations');
  let deleted = 0;
  let restored = 0;
  let skippedChanged = 0;

  for (let i = 0; i < createdIds.length; i += 400) {
    const chunk = createdIds.slice(i, i + 400);
    const batch = db.batch();
    for (const id of chunk) {
      const snap = await stations.doc(id).get();
      if (!snap.exists) continue;
      // Faqat shu batch yaratgan va keyin boshqa batch tegmagan hujjatni o'chiramiz.
      if (snap.data().importBatchId !== batchId) { skippedChanged += 1; continue; }
      batch.delete(stations.doc(id));
      deleted += 1;
    }
    await batch.commit();
  }

  for (let i = 0; i < updatedIds.length; i += 400) {
    const chunk = updatedIds.slice(i, i + 400);
    const batch = db.batch();
    for (const id of chunk) {
      const backupSnap = await batchRef.collection('backups').doc(id).get();
      if (!backupSnap.exists) continue;
      const current = await stations.doc(id).get();
      if (current.exists && current.data().importBatchId !== batchId) { skippedChanged += 1; continue; }
      batch.set(stations.doc(id), backupSnap.data());
      restored += 1;
    }
    await batch.commit();
  }

  console.log(`O'chirildi: ${deleted}`);
  console.log(`Tiklandi: ${restored}`);
  if (skippedChanged) {
    console.log(`O'tkazib yuborildi (keyingi batch tegan): ${skippedChanged}`);
  }
  console.log('\nRevert tugadi.');
}

async function main() {
  if (REVERT_BATCH) {
    await revert(REVERT_BATCH);
    return;
  }

  console.log('=== EV зарядлаш — очиқ манба импорти ===');
  console.log(APPLY ? 'APPLY — ҳақиқий ёзув' : 'DRY RUN — ҳеч нарса ёзилмайди (--apply билан ишга туширинг)');
  console.log('Manba fayl:', FILE_PATH);
  console.log('');

  const records = await loadRecords();
  console.log(`Manbadagi yozuvlar: ${records.length}\n`);

  const stations = db.collection('ev_charging_stations');
  const toCreate = [];
  const toUpdate = [];
  const unchanged = [];
  const skipped = [];
  let reviewRequiredCount = 0;

  for (const r of records) {
    const mapped = mapRecord(r);
    if (mapped.skip) {
      skipped.push({ id: mapped.id || '(noma\'lum)', reason: mapped.reason });
      continue;
    }
    if (mapped.createOnlyFields.isActive === false) reviewRequiredCount += 1;

    const existing = await stations.doc(mapped.id).get();
    if (!existing.exists) {
      toCreate.push(mapped);
      continue;
    }
    const existingData = existing.data();
    if (existingData.sourceType !== 'import') {
      // Doc ID kolliziyasi — nazariy jihatdan bo'lmasligi kerak (import
      // ID'lari `osm_node_...`/`tokbor_...`/`yashil_...`/`ocm_...` bilan
      // boshlanadi, ilovaning avto-generatsiya qilingan ID'lari bilan mos
      // kelmaydi) — xavfsizlik uchun tekshiramiz va tegmaymiz.
      skipped.push({ id: mapped.id, reason: 'ID community hujjat bilan mos keldi — o\'tkazib yuborildi' });
      continue;
    }
    // Solishtirish uchun eski hujjatdagi source-owned maydonlarni ajratamiz.
    const prevSourceFields = {};
    for (const k of Object.keys(mapped.sourceFields)) prevSourceFields[k] = existingData[k] ?? null;
    if (sourceFieldsEqual(prevSourceFields, mapped.sourceFields)) {
      unchanged.push(mapped);
    } else {
      toUpdate.push({ ...mapped, existingData });
    }
  }

  console.log('--- Dry-run hisoboti ---');
  console.log(`Yangi yaratiladi:      ${toCreate.length}`);
  console.log(`Yangilanadi:           ${toUpdate.length}`);
  console.log(`O'zgarishsiz:          ${unchanged.length}`);
  console.log(`O'tkazib yuborildi:    ${skipped.length}`);
  console.log(`  jumladan review_required (isActive=false): ${reviewRequiredCount}`);
  if (skipped.length) {
    console.log('\nO\'tkazib yuborilganlar:');
    skipped.forEach((s) => console.log(`  - ${s.id}: ${s.reason}`));
  }
  console.log('');

  if (!APPLY) {
    console.log('DRY RUN tugadi — hech narsa yozilmadi. Haqiqiy import uchun --apply qo\'shing.');
    return;
  }

  if (toCreate.length === 0 && toUpdate.length === 0) {
    console.log('Yangilanadigan yoki yaratiladigan yozuv yo\'q — batch yaratilmadi.');
    return;
  }

  const batchId = `import_${new Date().toISOString().replace(/[:.]/g, '-')}`;
  const batchRef = db.collection('ev_import_batches').doc(batchId);
  const now = admin.firestore.FieldValue.serverTimestamp();

  // 1) Backup — faqat YANGILANADIGAN (oldin mavjud) hujjatlar uchun.
  for (let i = 0; i < toUpdate.length; i += 400) {
    const chunk = toUpdate.slice(i, i + 400);
    const batch = db.batch();
    for (const item of chunk) {
      batch.set(batchRef.collection('backups').doc(item.id), item.existingData);
    }
    await batch.commit();
  }
  console.log(`Backup yozildi: ${toUpdate.length} ta hujjat (${batchRef.path}/backups).`);

  // 2) Create.
  for (let i = 0; i < toCreate.length; i += 400) {
    const chunk = toCreate.slice(i, i + 400);
    const batch = db.batch();
    for (const item of chunk) {
      batch.set(stations.doc(item.id), {
        ...item.sourceFields,
        ...item.createOnlyFields,
        importBatchId: batchId,
        importedAt: now,
        createdAt: now,
        updatedAt: now,
      });
    }
    await batch.commit();
  }
  console.log(`Yaratildi: ${toCreate.length}`);

  // 3) Update — faqat source-owned maydonlar (jamoa taxriri saqlanadi).
  for (let i = 0; i < toUpdate.length; i += 400) {
    const chunk = toUpdate.slice(i, i + 400);
    const batch = db.batch();
    for (const item of chunk) {
      batch.set(stations.doc(item.id), {
        ...item.sourceFields,
        importBatchId: batchId,
        importedAt: now,
        updatedAt: now,
      }, { merge: true });
    }
    await batch.commit();
  }
  console.log(`Yangilandi: ${toUpdate.length}`);

  await batchRef.set({
    source: path.basename(FILE_PATH),
    startedAt: now,
    finishedAt: admin.firestore.FieldValue.serverTimestamp(),
    totalRecords: records.length,
    createdCount: toCreate.length,
    updatedCount: toUpdate.length,
    unchangedCount: unchanged.length,
    skippedCount: skipped.length,
    reviewRequiredCount,
    createdIds: toCreate.map((i) => i.id),
    updatedIds: toUpdate.map((i) => i.id),
  });

  console.log(`\nBatch ID: ${batchId}`);
  console.log(`Qaytarish: node functions/tools/import_ev_open_data.js --revert ${batchId}`);
  console.log('\nAPPLY tugadi.');
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
