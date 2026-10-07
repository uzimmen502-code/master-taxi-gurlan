/**
 * MODULNI YOQISH — ikkita kalit bir joyda (ega buyrug'i bilan ishlatiladi).
 *
 *   node functions_demand/tools/enable_module.js --module logistics --region all          # dry-run
 *   node functions_demand/tools/enable_module.js --module logistics --region all --write
 *   node functions_demand/tools/enable_module.js --module logistics --region all --status
 *
 * NIMA QILADI (faqat --write bilan):
 *   1) `module_config/{module}_{region}` ← { enabled: true, matchingEnabled: true,
 *      pushEnabled: true } (yadro kill-switch, functions_demand/core/config.js);
 *      mavjud bo'lsa merge, boshqa maydonlar saqlanadi.
 *   2) `config/module_defaults` ← modules.{module}.status = 'enabled'
 *      (ilova Service Runtime Gate — lib/core/service_config_holder.dart;
 *      admin «Ҳудудлар ва хизматлар» bilan bir xil shakl). Boshqa modullar
 *      TEGILMAYDI (nested field update).
 *
 * Hech qachon o'chirmaydi va tarifni faol qilmaydi — bu alohida admin amali.
 */
const path = require('path');

const admin = require(path.join(__dirname, '..', 'node_modules', 'firebase-admin'));
const SA = path.join(__dirname, '..', '..', 'functions', 'service-account.json');

function arg(name, def) {
  const i = process.argv.indexOf(`--${name}`);
  if (i < 0) return def;
  const v = process.argv[i + 1];
  return v && !v.startsWith('--') ? v : true;
}

const MODULE = String(arg('module', ''));
const REGION = String(arg('region', 'all'));
const WRITE = process.argv.includes('--write');
const STATUS_ONLY = process.argv.includes('--status');
if (!/^[a-z][a-z0-9_]{1,40}$/.test(MODULE)) {
  console.error('--module majburiy (masalan: logistics)');
  process.exit(1);
}
if (!/^[a-z][a-z0-9_]{0,40}$/.test(REGION)) {
  console.error('--region noto\'g\'ri (masalan: all, xorazm)');
  process.exit(1);
}

function initDb() {
  if (admin.apps.length === 0) {
    // eslint-disable-next-line global-require, import/no-dynamic-require
    admin.initializeApp({ credential: admin.credential.cert(require(SA)) });
  }
  return admin.firestore();
}

async function show(db) {
  const cfgRef = db.collection('module_config').doc(`${MODULE}_${REGION}`);
  const defRef = db.collection('config').doc('module_defaults');
  const [cfg, def] = await Promise.all([cfgRef.get(), defRef.get()]);
  console.log(`module_config/${cfgRef.id}:`, cfg.exists ? JSON.stringify(cfg.data()) : '(yo\'q → DEFAULTS: enabled:false)');
  const modules = def.exists ? ((def.data() || {}).modules || {}) : null;
  console.log('config/module_defaults:', def.exists
    ? `${Object.keys(modules).length} modul; enforce=${(def.data() || {}).enforce}; ${MODULE}=${JSON.stringify(modules[MODULE] || null)}`
    : '(yo\'q)');
  return { cfgRef, defRef, cfg, def };
}

(async () => {
  const db = initDb();
  const { cfgRef, defRef, cfg, def } = await show(db);
  if (STATUS_ONLY) process.exit(0);

  const now = new Date();
  const by = 'enable_module.js';
  const cfgPatch = { module: MODULE, regionId: REGION, enabled: true, matchingEnabled: true, pushEnabled: true, updatedAt: now, updatedBy: by };
  const cur = cfg.exists ? (cfg.data() || {}) : {};
  const cfgAlready = cur.enabled === true && cur.matchingEnabled === true && cur.pushEnabled === true;
  const defModules = def.exists ? ((def.data() || {}).modules || {}) : {};
  const defAlready = !!(defModules[MODULE] && defModules[MODULE].status === 'enabled');
  console.log(`\n${WRITE ? 'YOZILADI' : 'DRY-RUN'}:`);
  console.log(`  module_config/${cfgRef.id} ← ${cfgAlready ? 'allaqachon yoqilgan, tegilmaydi' : `merge ${JSON.stringify({ enabled: true, matchingEnabled: true, pushEnabled: true })}`}`);
  console.log(`  config/module_defaults.modules.${MODULE} ← ${defAlready ? 'allaqachon enabled, tegilmaydi' : '{status: "enabled"} (boshqa modullar tegilmaydi)'}`);
  if (!WRITE) { console.log('\n(--write bilan ishga tushiring)'); process.exit(0); }

  if (!cfgAlready) await cfgRef.set(cfgPatch, { merge: true });
  if (defAlready) {
    // Hech narsa yozilmaydi — updatedAt ham o'zgarmasin (audit toza qolsin).
  } else if (def.exists) {
    await defRef.update({
      [`modules.${MODULE}`]: { status: 'enabled' },
      updatedAt: now,
      updatedBy: by,
    });
  } else {
    // Hujjat yo'q — faqat shu modul bilan yaratiladi (boshqalar DEFAULT: ilova
    // enforce=false rejimida konfig bo'sh bo'lsa hamma ma'lum modulni ochadi;
    // bitta modulli hujjat esa FAQAT shu modulni «configured» qiladi).
    console.error('config/module_defaults mavjud emas — bitta modulli hujjat yaratish boshqa modullarni YASHIRADI. To\'xtatildi.');
    process.exit(1);
  }
  console.log('  yozildi.\n');
  await show(db);
  process.exit(0);
})().catch((e) => {
  console.error('XATO:', e.message);
  process.exit(1);
});
