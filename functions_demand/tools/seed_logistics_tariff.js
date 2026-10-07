/**
 * AVA LOGISTICS TARIFI — QORALAMANI YOZISH.
 *
 *   node functions_demand/tools/seed_logistics_tariff.js            # dry-run (standart)
 *   node functions_demand/tools/seed_logistics_tariff.js --write    # module_tariffs/logistics_v1 (draft)
 *   node functions_demand/tools/seed_logistics_tariff.js --status   # faqat o'qish
 *
 * NIMA QILADI: `core/seed/logistics_tariff_draft.json` ni
 * `module_tariffs/logistics_v1` ga `status: draft` bilan yozadi. NARXLAR
 * YO'Q (ega qarori) — admin panelda to'ldiriladi, keyin
 * `adminActivateLogisticsTariff` faol qiladi. Faol versiya ko'rsatkichi
 * (`module_tariffs/logistics.activeVersion`) BU SKRIPT TOMONIDAN
 * YOZILMAYDI — tarif faol qilish alohida admin amali (audit bilan).
 *
 * Mavjud hujjat `draft` bo'lmasa (active/retired) — yozilmaydi (9-band).
 */
const path = require('path');
const tariff = require('../core/tariff');

const draft = require('../core/seed/logistics_tariff_draft.json');
const admin = require(path.join(__dirname, '..', 'node_modules', 'firebase-admin'));
const SA = path.join(__dirname, '..', '..', 'functions', 'service-account.json');

function initDb() {
  if (admin.apps.length === 0) {
    // eslint-disable-next-line global-require, import/no-dynamic-require
    admin.initializeApp({ credential: admin.credential.cert(require(SA)) });
  }
  return admin.firestore();
}

async function status(db) {
  const ptr = await db.collection(tariff.COLLECTION).doc(tariff.POINTER_DOC_ID).get();
  console.log(`${tariff.COLLECTION}/${tariff.POINTER_DOC_ID}:`, ptr.exists ? JSON.stringify(ptr.data()) : '(yo\'q — faol tarif YO\'Q)');
  const snap = await db.collection(tariff.COLLECTION).get();
  for (const d of snap.docs) {
    if (d.id === tariff.POINTER_DOC_ID) continue;
    const t = d.data();
    if (t.module !== tariff.MODULE) continue;
    const errs = tariff.validateTariff(t, { forActivation: true });
    console.log(`  ${d.id}: status=${t.status} version=${t.version} faol_qilishga=${errs.length ? `YO'Q (${errs.length} xato)` : 'TAYYOR'}`);
    for (const e of errs) console.log(`      - ${e}`);
  }
}

(async () => {
  const arg = (process.argv[2] || '--dry-run').replace(/^--/, '');
  const db = initDb();
  if (arg === 'status') { await status(db); process.exit(0); }

  const { _comment, ...doc } = draft;
  const errors = tariff.validateTariff(doc);
  if (errors.length) {
    console.error('Qoralama noto\'g\'ri:', errors.join('; '));
    process.exit(1);
  }
  const ref = db.collection(tariff.COLLECTION).doc(tariff.versionDocId(doc.version));
  const existing = await ref.get();
  if (existing.exists && (existing.data() || {}).status !== tariff.STATUS.DRAFT) {
    console.error(`${ref.id} mavjud va ${existing.data().status} — ustiga yozilmaydi (9-band).`);
    process.exit(1);
  }
  console.log(`${arg === 'write' ? 'YOZILADI' : 'DRY-RUN'}: ${tariff.COLLECTION}/${ref.id} (status: draft)`);
  console.log('  faol qilish uchun yetishmaydi:', tariff.validateTariff(doc, { forActivation: true }).join('; '));
  if (arg === 'write') {
    // TO'LIQ almashtirish (merge EMAS): merge bilan eski qoralamaning
    // `prices.ZONE_x` kabi ichki kalitlari production'da qolib ketardi
    // (2026-10-07 da shunday bo'lgan). Draft — yagona qoralama, tarixi yo'q.
    const createdAt = existing.exists ? ((existing.data() || {}).createdAt || new Date()) : new Date();
    await ref.set({ ...doc, createdAt, createdBy: 'seed_logistics_tariff.js', updatedAt: new Date() });
    console.log('  yozildi (to\'liq almashtirildi).');
  }
  await status(db);
  process.exit(0);
})().catch((e) => {
  console.error('XATO:', e.message);
  process.exit(1);
});
