/**
 * 13.5.1 — SHADOW MODE'НИ ЁҚИШ.
 *
 *   node functions_demand/tools/seed_module_config.js --shadow
 *   node functions_demand/tools/seed_module_config.js --push      # дарвозадан кейин
 *   node functions_demand/tools/seed_module_config.js --kill      # kill switch
 *   node functions_demand/tools/seed_module_config.js --status    # фақат ўқиш
 *
 * НИМА ҚИЛАДИ: `module_config/global` ва `module_config/service_all`
 * (бутун республика; алоҳида вилоят: `--region xorazm`) ҳужжатларини ёзади. Кодда стандарт қиймат `enabled: false`, шунинг
 * учун деплойдан кейин ҳеч нарса ўзидан ишга тушмайди — модул
 * АЙНИ ШУ СКРИПТ билан ёқилади.
 *
 * ШАДОУ РЕЖИМНИНГ АНИҚ МАЪНОСИ:
 *   matchingEnabled: true   — мослик ҳисобланади, `demand_matches` ёзилади
 *   pushEnabled: false      — ҲЕЧ КИМГА push кетмайди
 * Яъни таклифчилар талабни inbox'да кўради, лекин телефон жиринглаmaydi.
 * Эга талаби: «Аввал production'га тўлиқ тарқатмасдан shadow mode».
 *
 * МИНИМАЛ ҚИЙМАТ ЁЗИЛАДИ: қолган ҳамма созлама коддаги стандартдан
 * келади (`core/config.js`). Шунда конфиг ҳужжати кичик қолади ва
 * стандарт қиймат ўзгарса, у ўзидан қўлланади.
 */
const path = require('path');

const MODULE = 'service';
// Standart — `all` (butun respublika, `module_config/service_all`); alohida
// viloyat uchun: `--region xorazm`. Eski qat'iy `xorazm` olib tashlandi
// (ega 2026-10-20: qoidalar butun respublikada).
const { moduleRegionKey } = require('../core/ids');
const { parseMinScoreArg } = require('../core/calibration');

const regionIdx = process.argv.indexOf('--region');
// `--region` berilgan, lekin noto'g'ri bo'lsa JIM `all`ga tushmaydi: xato yozilgan
// viloyat butun respublikani yoqib yuborishi mumkin edi.
if (regionIdx >= 0 && !/^[a-z][a-z0-9_]{0,40}$/.test(process.argv[regionIdx + 1] || '')) {
  console.error('XATO: --region noto\'g\'ri (masalan: xorazm, toshkent_shahri). Hech narsa yozilmadi.');
  process.exit(1);
}
const REGION = regionIdx >= 0 ? process.argv[regionIdx + 1] : 'all';
// Hujjat ID'si yadro bilan BIR XIL qoida (`_`li hudud: `service__toshkent_shahri`).
const MODULE_KEY = moduleRegionKey(MODULE, REGION);

const admin = require(path.join(__dirname, '..', 'node_modules', 'firebase-admin'));

const SA = path.join(__dirname, '..', '..', 'functions', 'service-account.json');

function initDb() {
  if (admin.apps.length === 0) {
    // eslint-disable-next-line global-require, import/no-dynamic-require
    admin.initializeApp({ credential: admin.credential.cert(require(SA)) });
  }
  return admin.firestore();
}

const PRESETS = {
  shadow: {
    label: 'SHADOW MODE — matching ishlaydi, push YO\'Q',
    global: { enabled: true, matchingEnabled: true, pushEnabled: true, reason: '' },
    module: { enabled: true, matchingEnabled: true, pushEnabled: false },
  },
  push: {
    label: 'TO\'LIQ — push yoqildi (darvozadan keyin)',
    global: { enabled: true, matchingEnabled: true, pushEnabled: true, reason: '' },
    module: { enabled: true, matchingEnabled: true, pushEnabled: true },
  },
  kill: {
    label: 'KILL SWITCH — butun yadro to\'xtadi',
    global: {
      enabled: false,
      matchingEnabled: false,
      pushEnabled: false,
      reason: `qo'lda to'xtatildi ${new Date().toISOString()}`,
    },
    module: null,
  },
};

async function status(db) {
  const g = await db.collection('module_config').doc('global').get();
  const m = await db.collection('module_config').doc(MODULE_KEY).get();
  // Zaxira qatlam: `{module}_all` (core/config.getModuleConfig bilan bir xil).
  const a = REGION === 'all' ? null : await db.collection('module_config').doc(moduleRegionKey(MODULE, 'all')).get();

  console.log('module_config/global:');
  console.log(g.exists ? JSON.stringify(g.data(), null, 2) : '  (hujjat yo\'q — standart: ruxsat beruvchi)');
  console.log(`\nmodule_config/${MODULE_KEY}:`);
  console.log(m.exists ? JSON.stringify(m.data(), null, 2) : '  (hujjat yo\'q — standart: enabled=false, ya\'ni O\'CHIQ)');
  if (a) {
    console.log(`\nmodule_config/${moduleRegionKey(MODULE, 'all')} (zaxira):`);
    console.log(a.exists ? JSON.stringify(a.data(), null, 2) : '  (hujjat yo\'q)');
  }

  // Yakuniy holat — `resolveFlags` mantiqi bilan bir xil (AND); hudud hujjati `_all` ustidan ustun.
  const gd = g.exists ? g.data() : {};
  const md = { ...(a && a.exists ? a.data() : {}), ...(m.exists ? m.data() : {}) };
  const enabled = gd.enabled !== false && md.enabled === true;
  const matching = gd.matchingEnabled !== false && md.matchingEnabled !== false;
  const push = gd.pushEnabled !== false && md.pushEnabled === true;

  console.log('\nYAKUNIY HOLAT:');
  console.log(`  enabled         : ${enabled}`);
  console.log(`  matchingEnabled : ${matching}`);
  console.log(`  pushEnabled     : ${push}`);
  console.log(`  rejim           : ${
    !enabled ? 'O\'CHIQ'
      : (matching && !push ? 'SHADOW MODE' : (matching && push ? 'TO\'LIQ' : 'noma\'lum'))
  }`);

  // Har moslik uchun push chegarasi — core/config.deepMerge bilan BIR XIL qoida:
  // hudud hujjatidagi son `_all` dagidan ustun; `null` hech narsani bekor qilmaydi.
  const pmOf = (doc) => {
    const v = doc && doc.exists ? ((doc.data() || {}).push || {}).minScore : undefined;
    return typeof v === 'number' ? v : null;
  };
  const minScore = pmOf(m) !== null ? pmOf(m) : pmOf(a);
  console.log(`  push.minScore   : ${minScore === null ? 'null (KALIBROVKA YO\'Q)' : minScore}`);
  if (minScore === null) {
    console.log(
      '  DIQQAT: chegara o\'lchab tanlanmaguncha quote/alert/recurring push ketmaydi'
      + ' (`score_not_calibrated`).\n'
      + '          Tartib: review_matches.js --csv -> `relevant` to\'ldirish -> '
      + 'calibrate_push_threshold.js -> --min-score.',
    );
  }
}

/** `--min-score <0.01..1>` (yoki `off`): faqat `push.minScore` yoziladi (boshqa maydonlarga tegmaydi). */
async function setMinScore(db, raw) {
  const value = parseMinScoreArg(raw);
  await db.collection('module_config').doc(MODULE_KEY).set({
    push: { minScore: value },
    module: MODULE,
    regionId: REGION,
    updatedAt: new Date(),
    updatedBy: 'seed_module_config.js',
  }, { merge: true });
  console.log(`  yozildi: module_config/${MODULE_KEY}  push.minScore = ${value === null ? 'null (o\'chirildi)' : value}`);
  if (value === null && REGION !== 'all') {
    console.log('  Eslatma: `null` faqat shu hujjatning o\'z qiymatini tozalaydi; `_all` dagi son baribir amal qiladi.');
  }
  console.log('');
  await status(db);
}

async function apply(db, presetName) {
  const preset = PRESETS[presetName];
  if (!preset) throw new Error(`noma'lum preset: ${presetName}`);

  console.log(`Qo'llanadi: ${preset.label}\n`);

  await db.collection('module_config').doc('global').set({
    ...preset.global,
    updatedAt: new Date(),
    updatedBy: 'seed_module_config.js',
  }, { merge: true });
  console.log('  yozildi: module_config/global');

  if (preset.module) {
    await db.collection('module_config').doc(MODULE_KEY).set({
      ...preset.module,
      module: MODULE,
      regionId: REGION,
      updatedAt: new Date(),
      updatedBy: 'seed_module_config.js',
    }, { merge: true });
    console.log(`  yozildi: module_config/${MODULE_KEY}`);
  } else {
    console.log('  modul hujjati tegilmadi (kill switch global darajada)');
  }

  console.log('');
  await status(db);
}

(async () => {
  const arg = (process.argv[2] || '--status').replace(/^--/, '');
  const db = initDb();

  if (arg === 'status') {
    await status(db);
  } else if (arg === 'min-score') {
    await setMinScore(db, process.argv[3]);
  } else if (PRESETS[arg]) {
    await apply(db, arg);
  } else {
    console.error(
      'Ishlatish:\n'
      + '  node tools/seed_module_config.js --status   # faqat o\'qish\n'
      + '  node tools/seed_module_config.js --min-score 0.75 [--region xorazm]   # har moslik uchun push chegarasi (o\'lchab tanlangan)\n'
      + '  node tools/seed_module_config.js --shadow   # matching ON, push OFF\n'
      + '  node tools/seed_module_config.js --push     # push ON (darvozadan keyin)\n'
      + '  node tools/seed_module_config.js --kill     # butun yadroni to\'xtatish',
    );
    process.exit(1);
  }
  process.exit(0);
})().catch((e) => {
  console.error('XATO:', e.message);
  process.exit(1);
});
