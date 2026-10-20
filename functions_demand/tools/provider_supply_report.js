/**
 * READ-ONLY: HUDUD BO'YICHA TAKLIFCHILAR HISOBOTI (A7, ega 2026-10-20).
 *
 *   node functions_demand/tools/provider_supply_report.js --prod [--service service] [--min 5]
 *
 * NEGA: variant A — tizim butun respublikaga tayyor, lekin HAR HUDUD alohida
 * yoqiladi: shu hududda ishlay oladigan taklifchi `min` tadan kam bo'lsa
 * talab «mos odam yo'q» bilan tugaydi va foydalanuvchi qaytib kelmaydi.
 * Hisobot qaysi viloyat tayyorligini ko'rsatadi; `min` ni ega belgilaydi
 * (taklif: 5 — PROPOSED, hali tasdiqlanmagan).
 *
 * «Ishlay oladigan» = `core/capabilities.isEligible` (huquq `status` + xohish
 * `active`), ya'ni onProviderAvailable / matching ishlatadigan shart bilan bir xil.
 *
 * HECH NARSA YOZMAYDI (`lockWrites` + `assertWritesLocked` — audit asbobidagi
 * ayni himoya). Shaxsiy ma'lumot YO'Q: faqat sonlar (40-band).
 */
'use strict';
const path = require('path');

const caps = require('../core/capabilities');

/**
 * Sof funksiya (Firestore'siz).
 *
 * @param {object} p
 * @param {Array<object>} p.capDocs `provider_capabilities` hujjatlari
 * @param {string[]} p.regionIds `geo_regions` ID'lari
 * @param {number} p.min tayyorlik chegarasi (butun, >= 1)
 * @param {string} p.service `caps.SERVICES` dan biri
 */
function summarizeSupply({ capDocs, regionIds, min, service }) {
  if (!Number.isInteger(min) || min < 1) {
    throw new Error(`min butun son >= 1 bo'lishi kerak, berilgan: ${min}`);
  }
  if (!caps.SERVICES.includes(service)) {
    throw new Error(`service noto'g'ri: «${service}» (mumkin: ${caps.SERVICES.join(', ')})`);
  }
  const counts = new Map(regionIds.map((r) => [r, 0]));
  const unknown = new Set();
  let total = 0;
  let withoutRegion = 0;

  for (const doc of capDocs || []) {
    if (!caps.isEligible(doc, service)) continue;
    total += 1;
    const regions = Array.isArray((doc[service] || {}).regionIds) ? doc[service].regionIds : [];
    if (regions.length === 0) { withoutRegion += 1; continue; }
    for (const r of new Set(regions)) {
      if (counts.has(r)) counts.set(r, counts.get(r) + 1);
      else unknown.add(r);
    }
  }

  const rows = regionIds.map((regionId) => ({
    regionId,
    providers: counts.get(regionId),
    ready: counts.get(regionId) >= min,
  }));
  return {
    service,
    min,
    totalProviders: total,
    withoutRegion,
    unknownRegions: Array.from(unknown).sort(),
    readyRegions: rows.filter((r) => r.ready).map((r) => r.regionId),
    rows,
  };
}

// ── CLI ───────────────────────────────────────────────────────────────

async function main() {
  const args = process.argv.slice(2);
  const arg = (name, def) => {
    const i = args.indexOf(`--${name}`);
    return i >= 0 && args[i + 1] && !args[i + 1].startsWith('--') ? args[i + 1] : def;
  };
  if (!args.includes('--prod')) {
    throw new Error('Production uchun --prod kerak (faqat o\'qish).');
  }
  const service = String(arg('service', 'service'));
  const min = Number(arg('min', '5'));

  const admin = require(path.join(__dirname, '..', 'node_modules', 'firebase-admin'));
  const audit = require('./audit_expired_assignments');
  admin.initializeApp({
    credential: admin.credential.cert(require(path.join(__dirname, '..', '..', 'functions', 'service-account.json'))),
    projectId: 'master-taxi-gurlan',
  });
  audit.lockWrites(admin.firestore);
  const db = admin.firestore();
  audit.assertWritesLocked(db);

  const [regSnap, capSnap] = await Promise.all([
    db.collection('geo_regions').get(),
    db.collection('provider_capabilities').where(`${service}.active`, '==', true).get(),
  ]);
  const report = summarizeSupply({
    capDocs: capSnap.docs.map((d) => d.data() || {}),
    regionIds: regSnap.docs.map((d) => d.id).sort(),
    min,
    service,
  });
  console.log(JSON.stringify(report, null, 2));
}

if (require.main === module) {
  main().then(() => process.exit(0)).catch((e) => {
    console.error(`HISOBOT XATO: ${e.message}`);
    process.exit(1);
  });
}

module.exports = { summarizeSupply };
