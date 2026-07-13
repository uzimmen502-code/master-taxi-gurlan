#!/usr/bin/env node
/**
 * Configuration-driven platforma uchun boshlang'ich seed.
 *
 * XAVFSIZ: faqat `set(..., { merge: true })` — mavjud hujjatlarni buzmaydi,
 * hech narsa o'chirmaydi. Qayta ishga tushirsa bo'ladi (idempotent).
 *
 * Seed qiladi:
 *   geo_regions/xorazm
 *   geo_districts/*               (Xorazm — 11 tuman)
 *   config/module_defaults        (global baseline: intercity nationwide)
 *   service_areas/<area>          (har tuman uchun kamida 1 zona)
 *   service_area_modules/<area>   (tuman bo'yicha modul override)
 *
 * Ishlatish:
 *   node functions/tools/seed-service-config.js
 *   node functions/tools/seed-service-config.js --dry   (faqat ko'rsatadi)
 */
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const DRY = process.argv.includes('--dry');
const keyPath = path.join(__dirname, '..', 'service-account.json');

if (!fs.existsSync(keyPath)) {
  console.error('service-account.json topilmadi:', keyPath);
  process.exit(1);
}

const serviceAccount = require(keyPath);
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();
// Ba'zi tarmoqlarda gRPC "Premature close" bo'ladi — REST transport barqarorroq.
db.settings({ preferRest: true });
const now = admin.firestore.FieldValue.serverTimestamp();
const BY = 'seed-script';

// ── Seed ma'lumotlari ──────────────────────────────────────────────────────

const regions = [
  { id: 'xorazm', name: 'Xorazm', nameUz: 'Хоразм', code: 'xorazm', active: true, order: 10 },
];

// Xorazm viloyati — markaz shahri va tumanlarning to'liq ro'yxati.
// (Foydalanuvchi taqdim etgan rasmiy ro'yxat bo'yicha.)
const KHOREZM_DISTRICTS = [
  { id: 'urganch_shahri', name: 'Urganch shahri', nameUz: 'Урганч шаҳри', order: 10 },
  { id: 'bogot', name: 'Bogʻot tumani', nameUz: 'Боғот тумани', order: 20 },
  { id: 'gurlan', name: 'Gurlan tumani', nameUz: 'Гурлан тумани', order: 30 },
  { id: 'qoshkopir', name: 'Qoʻshkoʻpir tumani', nameUz: 'Қўшкўпир тумани', order: 40 },
  { id: 'urganch', name: 'Urganch tumani', nameUz: 'Урганч тумани', order: 50 },
  { id: 'shovot', name: 'Shovot tumani', nameUz: 'Шовот тумани', order: 60 },
  { id: 'xiva_shahri', name: 'Xiva shahri', nameUz: 'Хива шаҳри', order: 70 },
  { id: 'xiva', name: 'Xiva tumani', nameUz: 'Хива тумани', order: 80 },
  { id: 'hazarasp', name: 'Hazorasp tumani', nameUz: 'Ҳазорасп тумани', order: 90 },
  { id: 'xonqa', name: 'Xonqa tumani', nameUz: 'Хонқа тумани', order: 100 },
  { id: 'yangiarik', name: 'Yangiariq tumani', nameUz: 'Янгиариқ тумани', order: 110 },
  { id: 'yangibozor', name: 'Yangibozor tumani', nameUz: 'Янгибозор тумани', order: 120 },
  { id: 'tuproqqala', name: 'Tuproqqalʼa tumani', nameUz: 'Тупроққалъа тумани', order: 130 },
];

const districts = KHOREZM_DISTRICTS.map((d) => ({
  id: d.id,
  regionId: 'xorazm',
  name: d.name,
  nameUz: d.nameUz,
  code: d.id,
  active: true,
  order: d.order,
}));

// Global baseline (butun viloyat bo'yicha standart holat):
//   enabled     — hamma joyda ochiq (intercity, taksi, sotish, arzon, ish)
//   coming_soon — ko'rinadi, lekin "tez orada" (Gurlandan boshqa tumanlarda:
//                 Non, Ovqat, Kuryer, Gilam yuvish, Sut qabul)
// Gurlan bu coming_soon modullarni override bilan `enabled` qiladi.
const moduleDefaults = {
  // enforce=false — gating O'CHIQ. Ilova hozirgidek barcha modulni ochadi.
  // Barcha user'lar serviceAreaId oldgach admin buni `true` qiladi.
  enforce: false,
  modules: {
    // Butun viloyat bo'yicha ochiq:
    intercity: { status: 'enabled' },
    sell: { status: 'enabled' },
    cheap_products_home: { status: 'enabled' },
    jobs: { status: 'enabled' },
    local_taxi: { status: 'enabled' },
    marshrut: { status: 'enabled' },
    oil_change: { status: 'enabled' },
    // Gurlandan boshqa tumanlarda hali "tez orada":
    bread: { status: 'coming_soon' },
    food: { status: 'coming_soon' },
    courier: { status: 'coming_soon' },
    carpet_wash: { status: 'coming_soon' },
    milk: { status: 'coming_soon' },
  },
};

// Gurlanda mahalliy/xizmat modullar to'liq yoqilgan (pilot rollout).
// To'liq yoziladi — eski seed qoldiqlarini (merge) ustiga yozish uchun.
const GURLAN_LOCAL_ENABLED = {
  local_taxi: { status: 'enabled' },
  marshrut: { status: 'enabled' },
  bread: { status: 'enabled' },
  food: { status: 'enabled' },
  courier: { status: 'enabled' },
  carpet_wash: { status: 'enabled' },
  milk: { status: 'enabled' },
  oil_change: { status: 'enabled' },
};

// Boshqa tumanlar: taksi/marshrut ochiq; Non/Ovqat/Kuryer/Gilam/Sut — "tez orada".
// To'liq yoziladi — eski `hidden` qoldiqlarini (merge) ustiga yozish uchun.
const OTHER_DISTRICT_MODULES = {
  local_taxi: { status: 'enabled' },
  marshrut: { status: 'enabled' },
  bread: { status: 'coming_soon' },
  food: { status: 'coming_soon' },
  courier: { status: 'coming_soon' },
  carpet_wash: { status: 'coming_soon' },
  milk: { status: 'coming_soon' },
  oil_change: { status: 'enabled' },
};

// Gurlan tumani MFY ro'yxati — `assets/data/mfy_list.json` (ilova bilan bir xil manba).
const mfyListPath = path.join(__dirname, '..', '..', 'assets', 'data', 'mfy_list.json');
let gurlanMfyNames = [];
try {
  const mfyJson = JSON.parse(fs.readFileSync(mfyListPath, 'utf8'));
  gurlanMfyNames = mfyJson?.Xorazm?.Gurlan ?? [];
  if (!Array.isArray(gurlanMfyNames)) gurlanMfyNames = [];
} catch (e) {
  console.warn('mfy_list.json o\'qilmadi — faqat Gurlan markaz qoladi:', e.message || e);
}

const gurlanMfyAreas = gurlanMfyNames.map((nameUz, i) => {
  const label = String(nameUz).trim();
  const latin = label
    .replace(/\s*МФЙ\s*$/i, '')
    .replace(/[ʻʼ'`]/g, '')
    .trim();
  return {
    id: `svc_gurlan_mfy_${String(i + 1).padStart(2, '0')}`,
    districtId: 'gurlan',
    regionId: 'xorazm',
    name: latin,
    nameUz: label,
    type: 'mfy',
    active: true,
    order: 20 + i,
    modules: GURLAN_LOCAL_ENABLED,
  };
});

// Xizmat zonasi: har tuman uchun kamida bitta zona + Gurlan MFYlari.
const serviceAreas = [
  {
    id: 'svc_gurlan_markaz',
    districtId: 'gurlan',
    regionId: 'xorazm',
    name: 'Gurlan markazi',
    nameUz: 'Гурлан маркази',
    type: 'zone',
    active: true,
    order: 10,
    modules: GURLAN_LOCAL_ENABLED,
  },
  ...gurlanMfyAreas,
  ...KHOREZM_DISTRICTS.filter((d) => d.id !== 'gurlan').map((d) => ({
    id: `svc_${d.id}`,
    districtId: d.id,
    regionId: 'xorazm',
    name: `${d.name} — markaz`,
    nameUz: `${d.nameUz} — марказ`,
    type: 'zone',
    active: true,
    order: 10,
    modules: OTHER_DISTRICT_MODULES,
  })),
];

// ── Yozish ─────────────────────────────────────────────────────────────────

async function run() {
  const plan = [];

  for (const r of regions) {
    const { id, ...data } = r;
    plan.push(['geo_regions/' + id, { ...data, updatedAt: now, updatedBy: BY }]);
  }

  for (const d of districts) {
    const { id, ...data } = d;
    plan.push(['geo_districts/' + id, { ...data, updatedAt: now, updatedBy: BY }]);
  }

  plan.push(['config/module_defaults', { ...moduleDefaults, updatedAt: now, updatedBy: BY }]);

  for (const a of serviceAreas) {
    const { id, modules, ...areaData } = a;
    plan.push(['service_areas/' + id, { ...areaData, updatedAt: now, updatedBy: BY }]);
    plan.push([
      'service_area_modules/' + id,
      {
        serviceAreaId: id,
        districtId: areaData.districtId,
        regionId: areaData.regionId,
        modules,
        updatedAt: now,
        updatedBy: BY,
      },
    ]);
  }

  console.log(`Seed reja: ${plan.length} ta hujjat (merge)${DRY ? ' — DRY RUN' : ''}`);
  console.log(`  Gurlan MFY: ${gurlanMfyAreas.length} ta (+ markaz)`);
  for (const [pathStr] of plan) console.log('  •', pathStr);

  if (DRY) {
    console.log('DRY: hech narsa yozilmadi.');
    return;
  }

  for (const [pathStr, data] of plan) {
    await db.doc(pathStr).set(data, { merge: true });
    console.log('  ✓', pathStr);
  }
  console.log('✅ Seed yozildi.');

  // Tekshirish
  const check = await db.doc('config/module_defaults').get();
  console.log('config/module_defaults:', JSON.stringify(check.data().modules));
}

run()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('Seed xato:', e.message || e);
    process.exit(1);
  });
